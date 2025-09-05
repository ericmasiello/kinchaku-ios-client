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
  
  func submit(appState: AppState) async {
    guard canSubmit() else { return }
    isBusy = true; errorMessage = nil
    defer { isBusy = false }
    do { try appState.setToken(await AuthService.login(email: email, password: password)) }
    catch { errorMessage = error.localizedDescription }
  }
}
