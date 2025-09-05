//
//  OfflineIndex.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//

import Foundation

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
