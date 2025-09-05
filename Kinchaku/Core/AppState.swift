//
//  AppState.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//

import SwiftUI

@MainActor
final class AppState: ObservableObject {
  @Published var token: String?
  private let tokenStore = KeychainTokenStore(service: "OfflinePages", account: "authToken")

  init() { token = tokenStore.read() }

  func setToken(_ newValue: String) { tokenStore.save(newValue); token = newValue }
  func logout() { tokenStore.delete(); token = nil }
}
