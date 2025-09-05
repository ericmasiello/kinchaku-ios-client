//
//  PageRow.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//

import SwiftUI

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

#Preview {
  PageRow(page: PreviewFixtures.samplePage())
}
