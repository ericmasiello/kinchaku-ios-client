import SwiftUI
import WebKit
import CommonCrypto
import Security

// MARK: - AppState (Keychain-backed auth)

@MainActor
final class AppState: ObservableObject {
    @Published var token: String?
    private let tokenStore = KeychainTokenStore(service: "OfflinePages", account: "authToken")
    init() { token = tokenStore.read() }
    func setToken(_ newValue: String) { tokenStore.save(newValue); token = newValue }
    func logout() { tokenStore.delete(); token = nil }
}

struct KeychainTokenStore {
    let service: String; let account: String
    func save(_ token: String) {
        let data = Data(token.utf8)
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status != errSecSuccess {
            var add = base; add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }
    func read() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
    func delete() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}

// MARK: - Networking (Auth + Articles API)

struct LoginResponse: Codable { let token: String }

enum AuthService {
    static func login(email: String, password: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://kinchaku.synology.me/api/v1/auth/login")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["email": email, "password": password])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.userAuthenticationRequired)
        }
        return try JSONDecoder().decode(LoginResponse.self, from: data).token
    }
}

// Server payload
struct ArticlesEnvelope: Codable { let items: [RemoteArticle] }
struct RemoteArticle: Codable, Hashable {
    let id: Int
    let url: URL
    let archived: Int
    let favorited: Int
    let date_added: String
    let updated_at: String
}

enum APIService {
    static func fetchArticles(token: String) async throws -> [RemoteArticle] {
        var req = URLRequest(url: URL(string: "https://kinchaku.synology.me/api/v1/articles")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ArticlesEnvelope.self, from: data).items
    }
}

// MARK: - Models + Persistence

struct OfflinePage: Identifiable, Codable, Equatable {
    let id: UUID
    var remoteId: Int?               // <-- added to track server item
    var title: String
    var originalURL: URL
    var dirName: String?             // nil until cached to disk
    var dateAdded: Date
    var archived: Bool
    var favorited: Bool
}

struct IndexFile: Codable { var pages: [OfflinePage] = [] }

enum OfflineIndex {
    private static var fm: FileManager { .default }
    static var rootDir: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("OfflineSites", isDirectory: true)
    }
    private static var indexURL: URL { rootDir.appendingPathComponent("_index.json") }

    static func load() -> [OfflinePage] {
        try? fm.createDirectory(at: rootDir, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? JSONDecoder().decode(IndexFile.self, from: data).pages) ?? []
    }

    static func save(_ pages: [OfflinePage]) {
        let data = try? JSONEncoder().encode(IndexFile(pages: pages))
        try? fm.createDirectory(at: rootDir, withIntermediateDirectories: true)
        if let data { try? data.write(to: indexURL, options: .atomic) }
    }

    static func fileURL(for page: OfflinePage) -> URL? {
        guard let dir = page.dirName else { return nil }
        return rootDir.appendingPathComponent(dir).appendingPathComponent("index.html")
    }
    static func allowAccessDir(for page: OfflinePage) -> URL? {
        guard let dir = page.dirName else { return nil }
        return rootDir.appendingPathComponent(dir)
    }
    static func hasCache(for page: OfflinePage) -> Bool {
        guard let file = fileURL(for: page) else { return false }
        return FileManager.default.fileExists(atPath: file.path)
    }
    static func removeCache(dirName: String?) {
        guard let dirName else { return }
        let url = rootDir.appendingPathComponent(dirName, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Downloader (first-order assets + rewrite)

enum OfflineError: Error { case badResponse, invalidHTML, unsupportedScheme }

struct DownloadResult {
    let dirName: String
    let indexHTML: URL
    let assetCount: Int
    let pageTitle: String
}

enum OfflineDownloader {
    static func downloadSite(at url: URL) async throws -> DownloadResult {
        guard url.scheme?.hasPrefix("http") == true else { throw OfflineError.unsupportedScheme }
        let dirName = folderName(for: url)
        let siteDir = OfflineIndex.rootDir.appendingPathComponent(dirName, isDirectory: true)
        try? FileManager.default.removeItem(at: siteDir)
        try FileManager.default.createDirectory(at: siteDir, withIntermediateDirectories: true)

        let (htmlData, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode ?? 0 < 400 else { throw OfflineError.badResponse }
        guard var html = String(data: htmlData, encoding: .utf8) ?? String(data: htmlData, encoding: .isoLatin1) else {
            throw OfflineError.invalidHTML
        }

        let pageTitle = extractTitle(from: html) ?? url.host ?? "Untitled"
        let assets = HTMLAssetExtractor.extractAssetURLs(in: html, baseURL: url)

        var replacements: [(String, String)] = []; var count = 0
        try await withThrowingTaskGroup(of: (String, String)?.self) { group in
            for asset in assets {
                group.addTask {
                    do {
                        let (data, response) = try await URLSession.shared.data(from: asset)
                        guard (response as? HTTPURLResponse)?.statusCode ?? 0 < 400 else { return nil }
                        let localPath = localPathFor(assetURL: asset, under: siteDir)
                        try FileManager.default.createDirectory(at: localPath.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try data.write(to: localPath, options: .atomic)
                        let rel = localPath.path(relativeTo: siteDir)
                        return (asset.absoluteString, rel)
                    } catch { return nil }
                }
            }
            for try await pair in group {
                if let p = pair { replacements.append(p); count += 1 }
            }
        }
        for (orig, rel) in replacements.sorted(by: { $0.0.count > $1.0.count }) {
            html = html.replacingOccurrences(of: orig, with: rel)
        }
        let indexHTML = siteDir.appendingPathComponent("index.html")
        try html.data(using: .utf8)?.write(to: indexHTML, options: .atomic)
        return .init(dirName: dirName, indexHTML: indexHTML, assetCount: count, pageTitle: pageTitle)
    }

    private static func folderName(for url: URL) -> String {
        let t = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return "\(safeHost(url.host ?? "site"))__\(sha1(url.absoluteString))__\(t)"
    }
    private static func safeHost(_ s: String) -> String {
        s.replacingOccurrences(of: "[^A-Za-z0-9.-]", with: "_", options: .regularExpression)
    }
    private static func localPathFor(assetURL: URL, under root: URL) -> URL {
        var path = assetURL.host.map { "assets/\($0)\(assetURL.path)" } ?? "assets\(assetURL.path)"
        if path.hasSuffix("/") { path.append("index.txt") }
        if let q = assetURL.query, !q.isEmpty {
            let short = String(sha1(q).prefix(8))
            let ext = assetURL.pathExtension.isEmpty ? "bin" : assetURL.pathExtension
            path = path.replacingOccurrences(of: ".\(ext)", with: "_\(short).\(ext)")
            if path == "assets/index.txt" { path = "assets/index_\(short).txt" }
        }
        return root.appendingPathComponent(path)
    }
    private static func extractTitle(from html: String) -> String? {
        let pattern = #"<title[^>]*>(.*?)</title>"#
        guard let r = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let ns = html as NSString
        guard let m = r.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func sha1(_ s: String) -> String {
        let data = Data(s.utf8); var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest) }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - HTML Asset Extraction

enum HTMLAssetExtractor {
    static func extractAssetURLs(in html: String, baseURL: URL) -> [URL] {
        var results: Set<URL> = []
        let attrPattern = #"(?:src|href)\s*=\s*["']([^"']+)["']"#
        results.formUnion(extractURLs(html: html, baseURL: baseURL, pattern: attrPattern))
        let cssURLPattern = #"url\(\s*['"]?([^'")]+)['"]?\s*\)"#
        results.formUnion(extractURLs(html: html, baseURL: baseURL, pattern: cssURLPattern))
        let allowedExts: Set<String> = ["js","css","png","jpg","jpeg","gif","webp","svg","ico","woff","woff2","ttf","otf","mp4","webm","mp3","m4a"]
        return results.filter { u in
            guard let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
            return allowedExts.contains(u.pathExtension.lowercased())
        }
    }
    private static func extractURLs(html: String, baseURL: URL, pattern: String) -> Set<URL> {
        var out: Set<URL> = []
        let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let ns = html as NSString
        for match in regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges >= 2 else { continue }
            let s = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.lowercased().hasPrefix("data:"), !s.lowercased().hasPrefix("mailto:"), !s.lowercased().hasPrefix("tel:") else { continue }
            if let u = URL(string: s, relativeTo: baseURL)?.absoluteURL { out.insert(u) }
        }
        return out
    }
}

// MARK: - URL helper

private extension URL {
    func path(relativeTo base: URL) -> String {
        let rel = self.path.replacingOccurrences(of: base.path, with: "")
        if rel.hasPrefix("/") { return String(rel.dropFirst()) }
        return self.path.replacingOccurrences(of: base.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

// MARK: - WebView wrapper

struct WebView: UIViewRepresentable {
    let fileURL: URL
    let allowDir: URL
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.loadFileURL(fileURL, allowingReadAccessTo: allowDir)
        return wv
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - View Models

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email = ""; @Published var password = ""
    @Published var isBusy = false; @Published var errorMessage: String?
    func canSubmit() -> Bool { !email.isEmpty && !password.isEmpty && !isBusy }
    func submit(appState: AppState) async {
        guard canSubmit() else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do { appState.setToken(try await AuthService.login(email: email, password: password)) }
        catch { errorMessage = error.localizedDescription }
    }
}

@MainActor
final class OfflineListViewModel: ObservableObject {
    @Published var pages: [OfflinePage] = []
    @Published var inputURLString: String = ""
    @Published var isBusy = false
    @Published var statusMessage: String?
    @Published var syncProgress: String?
    @Published var isSyncing = false

    private let serverDate: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df
    }()

    init() {
        pages = OfflineIndex.load()
        sortPages()
    }

    func sortPages() { pages.sort { $0.dateAdded > $1.dateAdded } }
    var activePages: [OfflinePage] { pages.filter { !$0.archived } }
    var archivedPages: [OfflinePage] { pages.filter { $0.archived } }
    var canDownload: Bool { URL(string: inputURLString)?.scheme?.hasPrefix("http") == true }

    // Manual add (still supported)
    func downloadAndSave() async {
        guard let url = URL(string: inputURLString) else { return }
        isBusy = true; defer { isBusy = false }
        statusMessage = "Downloading…"
        do {
            let result = try await OfflineDownloader.downloadSite(at: url)
            let page = OfflinePage(
                id: UUID(), remoteId: nil, title: result.pageTitle, originalURL: url,
                dirName: result.dirName, dateAdded: Date(), archived: false, favorited: false
            )
            pages.insert(page, at: 0)
            OfflineIndex.save(pages); sortPages()
            statusMessage = "Saved “\(page.title)” (\(result.assetCount) assets)"
            inputURLString = ""
        } catch { statusMessage = "Download failed: \(error.localizedDescription)" }
    }

    // NEW: Fetch from remote and persist offline
    func fetchAndSyncFromServer(token: String) async {
      if isSyncing { return }
      isSyncing = true
      defer { isSyncing = false }
        do {
            syncProgress = "Fetching remote list…"
            let items = try await APIService.fetchArticles(token: token)

            // Merge: update existing by remoteId or URL; add new ones
            var byRemoteId = Dictionary(uniqueKeysWithValues: pages.compactMap { p in
                p.remoteId.map { ($0, p) }
            })
            var updatedPages = pages

            for item in items {
                // Map server → model
                let date = serverDate.date(from: item.date_added) ?? Date()
                let archived = item.archived != 0
                let favorited = item.favorited != 0

                if let existing = byRemoteId[item.id] ?? pages.first(where: { $0.originalURL == item.url }) {
                    // Update flags & date; keep cache dir if any
                    if let idx = updatedPages.firstIndex(where: { $0.id == existing.id }) {
                        updatedPages[idx].remoteId = item.id
                        updatedPages[idx].archived = archived
                        updatedPages[idx].favorited = favorited
                        updatedPages[idx].dateAdded = date
                    }
                } else {
                    // New local entry (not yet cached)
                    updatedPages.append(OfflinePage(
                        id: UUID(), remoteId: item.id, title: item.url.host ?? "Untitled",
                        originalURL: item.url, dirName: nil, dateAdded: date,
                        archived: archived, favorited: favorited
                    ))
                }
            }

            // Sort + save index before caching so UI shows immediately
            pages = updatedPages
            sortPages()
            OfflineIndex.save(pages)

            // Cache all uncached pages in parallel (first-order assets)
            let toCache = pages.filter { !$0.archived && !OfflineIndex.hasCache(for: $0) }
            if !toCache.isEmpty {
                syncProgress = "Caching \(toCache.count) pages for offline…"
                try await withThrowingTaskGroup(of: (UUID, DownloadResult).self) { group in
                    for page in toCache {
                        group.addTask {
                            let result = try await OfflineDownloader.downloadSite(at: page.originalURL)
                            return (page.id, result)
                        }
                    }
                    var map: [UUID: DownloadResult] = [:]
                    for try await (pid, res) in group { map[pid] = res }
                    // Write back dir names and titles
                    for i in pages.indices {
                        if let res = map[pages[i].id] {
                            pages[i].dirName = res.dirName
                            if pages[i].title.isEmpty || pages[i].title == (pages[i].originalURL.host ?? "") {
                                pages[i].title = res.pageTitle
                            }
                        }
                    }
                }
                OfflineIndex.save(pages)
                syncProgress = "Offline cache complete."
            } else {
                syncProgress = "Everything is already cached."
            }
        } catch {
            syncProgress = "Sync failed: \(error.localizedDescription)"
        }
    }

    func archive(_ page: OfflinePage, archived: Bool) {
        guard let i = pages.firstIndex(of: page) else { return }
        pages[i].archived = archived
        sortPages()
        OfflineIndex.save(pages)
    }

    func delete(_ page: OfflinePage) {
        OfflineIndex.removeCache(dirName: page.dirName)
        pages.removeAll { $0.id == page.id }
        OfflineIndex.save(pages)
    }
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var appState = AppState()
    var body: some View {
        Group {
            if let _ = appState.token {
                OfflineAppView()
                    .environmentObject(appState)
            } else {
                LoginView()
                    .environmentObject(appState)
            }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = LoginViewModel()
    @FocusState private var focused: Bool
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                TextField("Email", text: $vm.email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                SecureField("Password", text: $vm.password)
                    .textFieldStyle(.roundedBorder)

                if let err = vm.errorMessage {
                    Text(err).foregroundColor(.red).font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await vm.submit(appState: appState) }
                } label: {
                    vm.isBusy ? AnyView(ProgressView()) : AnyView(Text("Log In"))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canSubmit())

                Spacer()
            }
            .padding()
            .navigationTitle("Sign In")
            .onAppear { focused = true }
        }
    }
}

struct OfflineAppView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = OfflineListViewModel()
    @State private var selectedPage: OfflinePage?

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                // Status / actions row
                HStack {
                    if let msg = vm.statusMessage { Text(msg).font(.footnote).foregroundColor(.secondary) }
                    Spacer()
                    Button(role: .destructive) { appState.logout() } label: {
                        Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                if let sync = vm.syncProgress {
                    HStack {
                        ProgressView()
                        Text(sync).font(.footnote).foregroundColor(.secondary)
                        Spacer()
                    }
                }

                // Manual add (still supported)
                HStack {
                    TextField("https://example.com", text: $vm.inputURLString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task { await vm.downloadAndSave() }
                    } label: { vm.isBusy ? AnyView(ProgressView()) : AnyView(Text("Save")) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!vm.canDownload || vm.isBusy)
                }

                // List
                List {
                    if !vm.activePages.isEmpty {
                        Section("Saved (Newest)") {
                            ForEach(vm.activePages) { page in
                                PageRow(page: page)
                                    .contentShape(Rectangle())
                                    .onTapGesture { if OfflineIndex.hasCache(for: page) { selectedPage = page } }
                                    .overlay(alignment: .trailing) {
                                        if !OfflineIndex.hasCache(for: page) {
                                            Text("Downloading…").font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) { vm.delete(page) } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        Button { vm.archive(page, archived: true) } label: {
                                            Label("Archive", systemImage: "archivebox")
                                        }.tint(.gray)
                                    }
                            }
                        }
                    }
                    if !vm.archivedPages.isEmpty {
                        Section("Archived") {
                            ForEach(vm.archivedPages) { page in
                                PageRow(page: page)
                                    .contentShape(Rectangle())
                                    .onTapGesture { if OfflineIndex.hasCache(for: page) { selectedPage = page } }
                                    .swipeActions {
                                        Button { vm.archive(page, archived: false) } label: {
                                            Label("Unarchive", systemImage: "archivebox.fill")
                                        }
                                        Button(role: .destructive) { vm.delete(page) } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                    if vm.activePages.isEmpty && vm.archivedPages.isEmpty {
                        ContentUnavailableView("No pages",
                                               systemImage: "tray",
                                               description: Text("Sign in and your saved list will appear here."))
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    if let token = appState.token {
                        await vm.fetchAndSyncFromServer(token: token)
                    }
                }
            }
            .padding()
            .navigationTitle("Offline Pages")
            .sheet(item: $selectedPage) { page in
                OfflineReaderView(page: page)
            }
            .task {
                // Fetch remote items and cache them for offline, using stored token
                if let token = appState.token {
                    await vm.fetchAndSyncFromServer(token: token)
                }
            }
        }
    }
}

struct PageRow: View {
    let page: OfflinePage
    var body: some View {
        HStack {
            Image(systemName: page.archived ? "doc.text.magnifyingglass" : "doc.richtext")
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title.isEmpty ? page.originalURL.absoluteString : page.title)
                    .font(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    Text(page.originalURL.host ?? page.originalURL.absoluteString)
                    if page.favorited { Image(systemName: "star.fill") }
                }
                .font(.subheadline).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Text(page.dateAdded, style: .date)
                .font(.footnote).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct OfflineReaderView: View, Identifiable {
    let id = UUID()
    let page: OfflinePage
    var body: some View {
        NavigationView {
            if let file = OfflineIndex.fileURL(for: page),
               let dir = OfflineIndex.allowAccessDir(for: page) {
                WebView(fileURL: file, allowDir: dir)
                    .navigationTitle(page.title.isEmpty ? "Offline Page" : page.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Link(destination: page.originalURL) { Image(systemName: "safari") }
                        }
                    }
            } else {
                Text("This page is not cached yet.").padding()
            }
        }
    }
}




// example of fetching data with something that requires the token
func fetchSomethingRequiringAuth(appState: AppState) async throws -> Data {
  guard let token = await appState.token else { throw URLError(.userAuthenticationRequired) }
    var req = URLRequest(url: URL(string: "https://example.com/protected")!)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, _) = try await URLSession.shared.data(for: req)
    return data
}


#Preview {
    ContentView()
}
