//
//  OfflineError.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//


import Foundation
import CommonCrypto

enum OfflineError: Error { case badResponse, invalidHTML, unsupportedScheme }

struct DownloadResult {
  let dirName: String
  let indexHTML: URL
  let assetCount: Int
  let pageTitle: String
}

private extension URL {
  /// Returns a file-system path string for `self` relative to a `base` directory.
  func path(relativeTo base: URL) -> String {
    let rel = path.replacingOccurrences(of: base.path, with: "")
    if rel.hasPrefix("/") { return String(rel.dropFirst()) }
    return path
      .replacingOccurrences(of: base.path, with: "")
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  }
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
