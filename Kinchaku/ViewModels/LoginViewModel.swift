//
//  LoginViewModel.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//

import Foundation
import SwiftUI

@MainActor
final class LoginViewModel: ObservableObject {
  @Published var email = ""; @Published var password = ""
  @Published var isBusy = false; @Published var errorMessage: String?
  
  func canSubmit() -> Bool { !email.isEmpty && !password.isEmpty && !isBusy }
  
  func submit(tokenStore: TokenStore) async {
    guard canSubmit() else {
      return
    }
    isBusy = true;
    errorMessage = nil
    
    defer { isBusy = false }
    
    do {
      
      let loginResponse = try await AuthService.login(email: email, password: password)
      
      tokenStore.setToken(loginResponse.token)
      tokenStore.setRefreshToken(loginResponse.refreshToken)
    }
    catch { errorMessage = error.localizedDescription }
  }
}
