//
//  HTMLAssetExtractor.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//

import Foundation


// TODO: if the website is medium, we should not store the JavaScript because it blocks the user from reading the site

enum HTMLAssetExtractor {
  static func extractAssetURLs(in html: String, baseURL: URL) -> [URL] {
    var results: Set<URL> = []
    let attrPattern = #"(?:src|href)\s*=\s*["']([^"']+)["']"#
    results.formUnion(extractURLs(html: html, baseURL: baseURL, pattern: attrPattern))
    let cssURLPattern = #"url\(\s*['"]?([^'")]+)['"]?\s*\)"#
    results.formUnion(extractURLs(html: html, baseURL: baseURL, pattern: cssURLPattern))
    let allowedExts: Set<String> = ["js", "css", "png", "jpg", "jpeg", "gif", "webp", "svg", "ico", "woff", "woff2", "ttf", "otf", "mp4", "webm", "mp3", "m4a"]
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
