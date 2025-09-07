//
//  KinchakuApp.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/4/25.
//

import SwiftUI

@main
struct KinchakuApp: App {
  @StateObject private var appState = TokenStore()
  var body: some Scene {
    WindowGroup {
      ContentView().environmentObject(appState)
    }
  }
}
