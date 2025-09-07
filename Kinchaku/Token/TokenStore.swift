//
//  AppState.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//

import SwiftUI

@MainActor
final class TokenStore: ObservableObject {
  @Published var token: String?
  @Published var refreshToken: String?
  private let tokenStore = KeychainTokenStore(service: "OfflinePages", account: "authToken")
  private let refreshTokenStore = KeychainTokenStore(service: "OfflinePages", account: "refreshToken")

  init() {
    token = tokenStore.read()
    refreshToken = refreshTokenStore.read()
  }

  func setToken(_ newValue: String) {
    tokenStore.save(newValue);
    token = newValue
  }
  
  func setRefreshToken(_ newValue: String) {
    refreshTokenStore.save(newValue);
    refreshToken = newValue
  }
  func logout() {
    tokenStore.delete();
    refreshTokenStore.delete()
    token = nil
    refreshToken = nil
  }
}
