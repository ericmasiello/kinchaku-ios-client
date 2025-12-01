//
//  LoginView.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//

import SwiftUI

struct LoginView: View {
  @EnvironmentObject var tokenStore: TokenStore
  @StateObject private var vm = LoginViewModel()
  @FocusState private var focused: Bool
  var body: some View {
    NavigationView {
      VStack(spacing: 16) {
        TextField("Email", text: $vm.email)
          .autocorrectionDisabled()
          .focused($focused)
          .textFieldStyle(.roundedBorder)
        #if !os(macOS)
          .textInputAutocapitalization(.never)
          .keyboardType(.emailAddress)
        #endif
        SecureField("Password", text: $vm.password)
          .textFieldStyle(.roundedBorder)

        if let err = vm.errorMessage {
          Text(err).foregroundColor(.red).font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        Button {
          Task { await vm.submit(tokenStore: tokenStore) }
        } label: {
          vm.isBusy ? AnyView(ProgressView()) : AnyView(Text("Log In"))
        }
        .buttonStyle(.borderedProminent)
        .disabled(!vm.canSubmit())

        Spacer()
      }
      .padding()
      .navigationTitle("Kinchaku sign in")
      .onAppear { focused = true }
    }
  }
}

#Preview {
  let appState = PreviewFixtures.makeAppState(token: nil)
  return LoginView().environmentObject(appState)
}
