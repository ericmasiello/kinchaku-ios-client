import SwiftUI

struct ContentView: View {
  @EnvironmentObject var appState: AppState
  var body: some View {
    Group {
      if let _ = appState.token {
        OfflineAppView()
          .environmentObject(appState)
      } else {
        LoginView()
          .environmentObject(appState)
      }
    }
  }
}



// example of fetching data with something that requires the token
//func fetchSomethingRequiringAuth(appState: AppState) async throws -> Data {
//  guard let token = await appState.token else { throw URLError(.userAuthenticationRequired) }
//  var req = URLRequest(url: URL(string: "https://example.com/protected")!)
//  req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
//  let (data, _) = try await URLSession.shared.data(for: req)
//  return data
//}

#Preview("Content – Logged Out") {
  let appState = PreviewFixtures.makeAppState(token: nil)
  return ContentView().environmentObject(appState)
}

#Preview("Content – Logged In") {
  let appState = PreviewFixtures.makeAppState(token: "preview-token")
  return ContentView().environmentObject(appState)
}
