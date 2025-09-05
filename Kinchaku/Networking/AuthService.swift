//
//  AuthService.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//

import Foundation

enum AuthService {
  static func login(email: String, password: String) async throws -> String {
    var req = URLRequest(url: URL(string: "https://kinchaku.synology.me/api/v1/auth/login")!)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONEncoder().encode(["email": email, "password": password])
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
      throw URLError(.userAuthenticationRequired)
    }
    return try JSONDecoder().decode(LoginResponse.self, from: data).token
  }
}
