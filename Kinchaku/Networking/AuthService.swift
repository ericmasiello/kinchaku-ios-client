//
//  AuthService.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//

import Foundation

struct LoginResponse: Codable {
  let token: String
  let refreshToken: String
}

struct RefreshResponse: Codable {
  let token: String
}

enum AuthService {
  static func login(email: String, password: String) async throws -> LoginResponse {
    var req = URLRequest(url: URL(string: "\(BaseAPIService.url)/auth/login")!)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONEncoder().encode(["email": email, "password": password])
    
    let (data, resp) = try await URLSession.shared.data(for: req)
    
    guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
      throw URLError(.userAuthenticationRequired)
    }
    return try JSONDecoder().decode(LoginResponse.self, from: data)
  }
  
  static func refresh(refreshToken: String) async throws -> String {
    var req = URLRequest(url: URL(string: "\(BaseAPIService.url)/auth/refresh")!)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONEncoder().encode(["refreshToken": refreshToken])
    
    let (data, resp) = try await URLSession.shared.data(for: req)
    
    guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
      throw URLError(.userAuthenticationRequired)
    }
    return try JSONDecoder().decode(RefreshResponse.self, from: data).token
  }
}
