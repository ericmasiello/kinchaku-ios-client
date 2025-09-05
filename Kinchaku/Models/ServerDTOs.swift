//
//  LoginResponse.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//

import Foundation

struct LoginResponse: Codable { let token: String }

struct ArticlesEnvelope: Codable { let items: [RemoteArticle] }

struct RemoteArticle: Codable, Hashable {
  let id: Int
  let url: URL
  let archived: Int
  let favorited: Int
  let date_added: String
  let updated_at: String
}

struct CreateArticlePayload: Codable {
  let url: String
  let favorited: Bool
}
