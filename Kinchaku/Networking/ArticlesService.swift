//
//  AuthError.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//


import Foundation

enum AuthError: Error { 
  case expired
  case refreshFailed
}

enum ArticlesService {
  
  static func fetchArticles(token: String) async throws -> [RemoteArticle] {
    var req = URLRequest(url: URL(string: "\(BaseAPIService.url)/articles")!)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    if http.statusCode == 401 { throw AuthError.expired }
    guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
    return try JSONDecoder().decode(ArticlesEnvelope.self, from: data).items
  }
  
  static func createArticle(token: String, url: URL, favorited: Bool) async throws -> RemoteArticle {
    var req = URLRequest(url: URL(string: "\(BaseAPIService.url)/articles")!)
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
  
  static func updateArticleArchived(token: String, articleId: Int, archived: Bool) async throws {
    var req = URLRequest(url: URL(string: "\(BaseAPIService.url)/articles/\(articleId)")!)
    req.httpMethod = "PATCH"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    struct PatchPayload: Codable { let archived: Bool }
    req.httpBody = try JSONEncoder().encode(PatchPayload(archived: archived))

    let (_, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    if http.statusCode == 401 { throw AuthError.expired }
    guard (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
  }

  static func deleteArticle(token: String, articleId: Int) async throws {
    var req = URLRequest(url: URL(string: "\(BaseAPIService.url)/articles/\(articleId)")!)
    req.httpMethod = "DELETE"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let (_, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    if http.statusCode == 401 { throw AuthError.expired }
    guard (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
  }
}

@MainActor
class ArticlesServiceWithRefresh {
  private let tokenStore: TokenStore
  private var hasRetried = false
  
  init(tokenStore: TokenStore) {
    self.tokenStore = tokenStore
  }
  
  func fetchArticles() async throws -> [RemoteArticle] {
    guard let token = tokenStore.token else {
      throw AuthError.expired
    }
    
    do {
      let result = try await ArticlesService.fetchArticles(token: token)
      hasRetried = false // Reset retry flag on success
      return result
    } catch AuthError.expired {
      return try await handleTokenRefresh { [weak self] in
        guard let self = self, let newToken = self.tokenStore.token else {
          throw AuthError.expired
        }
        return try await ArticlesService.fetchArticles(token: newToken)
      }
    }
  }
  
  func createArticle(url: URL, favorited: Bool) async throws -> RemoteArticle {
    guard let token = tokenStore.token else {
      throw AuthError.expired
    }
    
    do {
      let result = try await ArticlesService.createArticle(token: token, url: url, favorited: favorited)
      hasRetried = false // Reset retry flag on success
      return result
    } catch AuthError.expired {
      return try await handleTokenRefresh { [weak self] in
        guard let self = self, let newToken = self.tokenStore.token else {
          throw AuthError.expired
        }
        return try await ArticlesService.createArticle(token: newToken, url: url, favorited: favorited)
      }
    }
  }
  
  func updateArticleArchived(articleId: Int, archived: Bool) async throws {
    guard let token = tokenStore.token else {
      throw AuthError.expired
    }
    
    do {
      try await ArticlesService.updateArticleArchived(token: token, articleId: articleId, archived: archived)
      hasRetried = false // Reset retry flag on success
    } catch AuthError.expired {
      try await handleTokenRefresh { [weak self] in
        guard let self = self, let newToken = self.tokenStore.token else {
          throw AuthError.expired
        }
        return try await ArticlesService.updateArticleArchived(token: newToken, articleId: articleId, archived: archived)
      }
    }
  }
  
  func deleteArticle(articleId: Int) async throws {
    guard let token = tokenStore.token else {
      throw AuthError.expired
    }
    
    do {
      try await ArticlesService.deleteArticle(token: token, articleId: articleId)
      hasRetried = false // Reset retry flag on success
    } catch AuthError.expired {
      try await handleTokenRefresh { [weak self] in
        guard let self = self, let newToken = self.tokenStore.token else {
          throw AuthError.expired
        }
        return try await ArticlesService.deleteArticle(token: newToken, articleId: articleId)
      }
    }
  }
  
  private func handleTokenRefresh<T>(_ operation: @escaping () async throws -> T) async throws -> T {
    // Only allow one retry attempt
    guard !hasRetried else {
      throw AuthError.expired
    }
    
    guard let refreshToken = tokenStore.refreshToken else {
      throw AuthError.expired
    }
    
    do {
      let newToken = try await AuthService.refresh(refreshToken: refreshToken)
      tokenStore.setToken(newToken)
      hasRetried = true
      
      return try await operation()
    } catch {
      // If refresh fails, user must re-login
      throw AuthError.refreshFailed
    }
  }
}
