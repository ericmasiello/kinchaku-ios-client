//
//  AuthError.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//


import Foundation

enum AuthError: Error { case expired }

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
}

// class ArticleWrappedService {
//   var retryAuth = false
  
//   func fetchArticles(tokenStore: TokenStore) async throws -> [RemoteArticle] {
//     guard let token = await tokenStore.token, let refreshToken = await tokenStore.refreshToken else {
//       throw AuthError.expired
//     }
    
//     do {
//       return try await ArticlesService.fetchArticles(token: token)
//     } catch let err as AuthError {
//       if err == .expired && retryAuth == false {
//         let nextToken = try await AuthService.refresh(refreshToken: refreshToken)
//         await tokenStore.setToken(nextToken)
//         retryAuth = true
//         return try await fetchArticles(tokenStore: tokenStore)
//       } else {
//         retryAuth = false
//         throw err
//       }
//     } catch {
//       throw error
//     }
//   }
  
//   func createArticle(tokenStore: TokenStore, url: URL, favorited: Bool) async throws -> RemoteArticle {
//     guard let token = await tokenStore.token, let refreshToken = await tokenStore.refreshToken else {
//       throw AuthError.expired
//     }
    
//     do {
//       return try await ArticlesService.createArticle(token: token, url: url, favorited: favorited)
//     } catch let err as AuthError {
//       if err == .expired && retryAuth == false {
//         let nextToken = try await AuthService.refresh(refreshToken: refreshToken)
//         await tokenStore.setToken(nextToken)
//         retryAuth = true
//         return try await createArticle(tokenStore: tokenStore, url: url, favorited: favorited)
//       } else {
//         retryAuth = false
//         throw err
//       }
//     } catch {
//       throw error
//     }
//   }
  
//   func updateArticleArchived(tokenStore: TokenStore, articleId: Int, archived: Bool) async throws {
//     guard let token = await tokenStore.token, let refreshToken = await tokenStore.refreshToken else {
//       throw AuthError.expired
//     }
    
//     do {
//       return try await ArticlesService.updateArticleArchived(token: token, articleId: articleId, archived: archived)
//     } catch let err as AuthError {
//       if err == .expired && retryAuth == false {
//         let nextToken = try await AuthService.refresh(refreshToken: refreshToken)
//         await tokenStore.setToken(nextToken)
//         retryAuth = true
//         return try await updateArticleArchived(tokenStore: tokenStore, articleId: articleId, archived: archived)
//       } else {
//         retryAuth = false
//         throw err
//       }
//     } catch {
//       throw error
//     }
//   }
// }
