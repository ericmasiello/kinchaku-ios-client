import SwiftUI
import WebKit
import CommonCrypto

// MARK: - Models

struct OfflinePage: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var originalURL: URL
    var dirName: String          // folder name under OfflineSites
    var dateAdded: Date
    var archived: Bool
}

struct IndexFile: Codable {
    var pages: [OfflinePage] = []
}

// MARK: - Index Store

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

    static func removeDir(named dirName: String) {
        let url = rootDir.appendingPathComponent(dirName, isDirectory: true)
        try? fm.removeItem(at: url)
    }

    static func fileURL(for page: OfflinePage) -> URL {
        rootDir.appendingPathComponent(page.dirName).appendingPathComponent("index.html")
    }

    static func allowAccessDir(for page: OfflinePage) -> URL {
        rootDir.appendingPathComponent(page.dirName)
    }
}

// MARK: - Downloader / Rewriter (first-order assets)

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

        // unique folder per save (prevents collisions)
        let dirName = folderName(for: url)
        let siteDir = OfflineIndex.rootDir.appendingPathComponent(dirName, isDirectory: true)
        try? FileManager.default.removeItem(at: siteDir)
        try FileManager.default.createDirectory(at: siteDir, withIntermediateDirectories: true)

        // 1) Fetch HTML
        let (htmlData, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode ?? 0 < 400 else { throw OfflineError.badResponse }
        guard var html = String(data: htmlData, encoding: .utf8) ?? String(data: htmlData, encoding: .isoLatin1) else {
            throw OfflineError.invalidHTML
        }

        let pageTitle = extractTitle(from: html) ?? url.host ?? "Untitled"

        // 2) Extract first-order asset URLs
        let assets = HTMLAssetExtractor.extractAssetURLs(in: html, baseURL: url)

        // 3) Download assets in parallel
        var replacements: [(original: String, localRelative: String)] = []
        var count = 0

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
                if let (orig, rel) = pair {
                    replacements.append((orig, rel))
                    count += 1
                }
            }
        }

        // 4) Rewrite references in the HTML
        for r in replacements.sorted(by: { $0.original.count > $1.original.count }) {
            html = html.replacingOccurrences(of: r.original, with: r.localRelative)
        }

        // 5) Save rewritten HTML
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
        let data = Data(s.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
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
        }.map { $0 }
    }

    private static func extractURLs(html: String, baseURL: URL, pattern: String) -> Set<URL> {
        var out: Set<URL> = []
        let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let ns = html as NSString
        for match in regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges >= 2 else { continue }
            let s = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.lowercased().hasPrefix("data:"),
                  !s.lowercased().hasPrefix("mailto:"),
                  !s.lowercased().hasPrefix("tel:") else { continue }
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
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // no-op (kept simple for offline)
    }
}

// MARK: - ViewModel

@MainActor
final class OfflineListViewModel: ObservableObject {
    @Published var pages: [OfflinePage] = []
    @Published var inputURLString: String = ""
    @Published public var isBusy = false
    @Published var statusMessage: String?

    init() {
        pages = OfflineIndex.load()
        sortPages()
    }

    func sortPages() {
        pages.sort { $0.dateAdded > $1.dateAdded } // reverse chronological
    }
  
    // TODO: need to implement this

    var activePages: [OfflinePage] { pages.filter { !$0.archived } }
    var archivedPages: [OfflinePage] { pages.filter { $0.archived } }

    var canDownload: Bool { URL(string: inputURLString)?.scheme?.hasPrefix("http") == true }

    func downloadAndSave() async {
        guard let url = URL(string: inputURLString) else { return }
        isBusy = true
        defer { isBusy = false }
        statusMessage = "Downloading…"

        do {
            let result = try await OfflineDownloader.downloadSite(at: url)
            let page = OfflinePage(
                id: UUID(),
                title: result.pageTitle,
                originalURL: url,
                dirName: result.dirName,
                dateAdded: Date(),
                archived: false
            )
            pages.insert(page, at: 0)
            OfflineIndex.save(pages)
            sortPages()
            statusMessage = "Saved “\(page.title)” (\(result.assetCount) assets)"
            inputURLString = ""
        } catch {
            statusMessage = "Download failed: \(error.localizedDescription)"
        }
    }

    func archive(_ page: OfflinePage, archived: Bool) {
        guard let i = pages.firstIndex(of: page) else { return }
        pages[i].archived = archived
        sortPages()
        OfflineIndex.save(pages)
    }

    func delete(_ page: OfflinePage) {
        OfflineIndex.removeDir(named: page.dirName)
        pages.removeAll { $0.id == page.id }
        OfflineIndex.save(pages)
    }
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var vm = OfflineListViewModel()
    @State private var selectedPage: OfflinePage? = nil

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                // Add form
                HStack {
                    TextField("https://example.com", text: $vm.inputURLString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)
                    
                    
                    Button {
                        Task { await vm.downloadAndSave() }
                    } label: {
                      if vm.isBusy {
                        ProgressView()
                      } else {
                        Text("Save")
                      }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!vm.canDownload || vm.isBusy)
                }

                if let status = vm.statusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }

                // List of pages
                List {
                    if !vm.activePages.isEmpty {
                        Section("Saved (Newest)") {
                            ForEach(vm.activePages) { page in
                                PageRow(page: page)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedPage = page }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) { vm.delete(page) } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        Button { vm.archive(page, archived: true) } label: {
                                            Label("Archive", systemImage: "archivebox")
                                        }.tint(.gray)
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button { selectedPage = page } label: {
                                            Label("Open", systemImage: "arrow.forward.circle")
                                        }.tint(.blue)
                                    }
                            }
                        }
                    }

                    if !vm.archivedPages.isEmpty {
                        Section("Archived") {
                            ForEach(vm.archivedPages) { page in
                                PageRow(page: page)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedPage = page }
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
                        ContentUnavailableView("No offline pages yet",
                                               systemImage: "tray",
                                               description: Text("Paste a URL above and tap Save."))
                            .frame(maxWidth: .infinity)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .padding()
            .navigationTitle("Offline Pages")
            .sheet(item: $selectedPage) { page in
                OfflineReaderView(page: page)
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
                    .font(.headline)
                    .lineLimit(1)
                Text(page.originalURL.host ?? page.originalURL.absoluteString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(page.dateAdded, style: .relative)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct OfflineReaderView: View {
    let page: OfflinePage
    var body: some View {
        NavigationView {
            WebView(
                fileURL: OfflineIndex.fileURL(for: page),
                allowDir: OfflineIndex.allowAccessDir(for: page)
            )
            .navigationTitle(page.title.isEmpty ? "Offline Page" : page.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Link(destination: page.originalURL) {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("Open original")
                }
            }
        }
    }
}



#Preview {
    ContentView()
}
