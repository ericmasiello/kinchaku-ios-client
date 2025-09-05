//
//  PreviewFixture.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//

import Foundation
import SwiftUI

enum PreviewFixtures {
  @MainActor static func makeAppState(token: String?) -> AppState {
    let s = AppState()
    s.token = token
    return s
  }

  static func samplePage(cached: Bool = false) -> OfflinePage {
    var p = OfflinePage(
      id: UUID(),
      remoteId: 123,
      title: "Example Domain",
      originalURL: URL(string: "https://example.com")!,
      dirName: nil,
      dateAdded: Date(),
      archived: false,
      favorited: true
    )

    if cached {
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("PreviewCached", isDirectory: true)
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let html = dir.appendingPathComponent("index.html")
      try? "<html><body><h1>Example</h1></body></html>".data(using: .utf8)?.write(to: html)
      p.dirName = dir.lastPathComponent

      // Place under OfflineIndex.rootDir so `fileURL(for:)` resolves:
      // create root and move
      try? FileManager.default.createDirectory(at: OfflineIndex.rootDir, withIntermediateDirectories: true)
      let targetDir = OfflineIndex.rootDir.appendingPathComponent(p.dirName!, isDirectory: true)
      try? FileManager.default.removeItem(at: targetDir)
      try? FileManager.default.copyItem(at: dir, to: targetDir)
    }
    return p
  }
}
