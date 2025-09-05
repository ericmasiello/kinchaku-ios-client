//
//  OfflinePage.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//


import Foundation

struct OfflinePage: Identifiable, Codable, Equatable {
  let id: UUID
  var remoteId: Int?          // track server item
  var title: String
  var originalURL: URL
  var dirName: String?        // nil until cached to disk
  var dateAdded: Date
  var archived: Bool
  var favorited: Bool
}

struct IndexFile: Codable { var pages: [OfflinePage] = [] }
