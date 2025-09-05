//
//  OfflineReaderView.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//

import SwiftUI

struct OfflineReaderView: View, Identifiable {
  let id = UUID()
  let page: OfflinePage
  var body: some View {
    NavigationView {
      if let file = OfflineIndex.fileURL(for: page),
         let dir = OfflineIndex.allowAccessDir(for: page)
      {
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

#Preview {
  OfflineReaderView(page: PreviewFixtures.samplePage(cached: true))
}
