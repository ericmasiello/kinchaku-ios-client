//
//  AuthError.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//


import Foundation

enum AuthError: Error { case expired }

enum APIService {
  static func fetchArticles(token: String) async throws -> [RemoteArticle] {
    var req = URLRequest(url: URL(string: "https://kinchaku.synology.me/api/v1/articles")!)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    if http.statusCode == 401 { throw AuthError.expired }
    guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
    return try JSONDecoder().decode(ArticlesEnvelope.self, from: data).items
  }
  
  static func createArticle(token: String, url: URL, favorited: Bool) async throws -> RemoteArticle {
    var req = URLRequest(url: URL(string: "https://kinchaku.synology.me/api/v1/articles")!)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.httpBody = try JSONEncoder().encode(CreateArticlePayload(url: url.absoluteString, favorited: favorited))

    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    if http.statusCode == 401 { throw AuthError.expired }
    guard http.statusCode == 201 else { throw URLError(.badServerResponse) }
    return try JSONDecoder().decode(RemoteArticle.self, from: data)
  }
}


