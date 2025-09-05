//
//  OfflineAppView.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//

import SwiftUI

struct OfflineAppView: View {
  @EnvironmentObject var appState: AppState
  @StateObject private var vm = OfflineListViewModel()
  @State private var selectedPage: OfflinePage?

  var body: some View {
    NavigationView {
      VStack(spacing: 12) {
        // Status / actions row
        HStack {
          if let msg = vm.statusMessage { Text(msg).font(.footnote).foregroundColor(.secondary) }
          Spacer()
        }

        if let sync = vm.syncProgress {
          HStack {
            if (vm.isSyncing) {
              ProgressView()
            }
            
            Text(sync).font(.footnote).foregroundColor(.secondary)
            Spacer()
          }
        }

        // Manual add (still supported)
        HStack {
          TextField("https://example.com", text: $vm.inputURLString)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .disableAutocorrection(true)
            .textFieldStyle(.roundedBorder)
          Button {
            Task {
              await vm.downloadAndSave(token: appState.token, favorited: false)
            }
          } label: {
            vm.isBusy ? AnyView(ProgressView()) : AnyView(Text("Save"))
          }
          .buttonStyle(.borderedProminent)
          .disabled(!vm.canDownload || vm.isBusy)
        }

        // List
        List {
          if !vm.activePages.isEmpty {
            Section("Saved (Newest)") {
              ForEach(vm.activePages) { page in
                PageRow(page: page)
                  .contentShape(Rectangle())
                  .onTapGesture { if OfflineIndex.hasCache(for: page) { selectedPage = page } }
                  .overlay(alignment: .trailing) {
                    if !OfflineIndex.hasCache(for: page) {
                      Text("Downloading…").font(.caption2).foregroundColor(.secondary)
                    }
                  }
                  .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { vm.delete(page) } label: {
                      Label("Delete", systemImage: "trash")
                    }
                    Button { vm.archive(page, archived: true) } label: {
                      Label("Archive", systemImage: "archivebox")
                    }.tint(.gray)
                  }
              }
            }
          }
          if !vm.archivedPages.isEmpty {
            Section("Archived") {
              ForEach(vm.archivedPages) { page in
                PageRow(page: page)
                  .contentShape(Rectangle())
                  .onTapGesture { if OfflineIndex.hasCache(for: page) { selectedPage = page } }
                  .swipeActions {
                    Button { vm.archive(page, archived: false) } label: {
                      Label("Unarchive", systemImage: "archivebox.fill")
                    }
                    Button(role: .destructive) { vm.delete(page) } label: {
                      Label("Delete", systemImage: "trash")
                    }
                  }
              }
            }
          }
          if vm.activePages.isEmpty && vm.archivedPages.isEmpty {
            ContentUnavailableView("No pages",
                                   systemImage: "tray",
                                   description: Text("Sign in and your saved list will appear here."))
          }
        }
        .listStyle(.insetGrouped)
        .refreshable {
          if let token = appState.token {
            await vm.fetchAndSyncFromServer(token: token)
          }
        }
      }
      .padding()
      .navigationTitle("Offline Pages")
      .toolbar {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
          Button {
            Task {
              if let token = appState.token {
                await vm.fetchAndSyncFromServer(token: token)
              }
            }
          } label: {
            if vm.isSyncing {
              ProgressView()
            } else {
              Label("Refresh", systemImage: "arrow.clockwise")
            }
          }
          .disabled(vm.isSyncing)
        }

        ToolbarItem(placement: .navigationBarLeading) {
          Button(role: .destructive) { appState.logout() } label: {
            Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
          }
        }
      }

      .task {
        if let token = appState.token {
          await vm.fetchAndSyncFromServer(token: token)
        }
      }
      .alert("Session expired", isPresented: $vm.authExpired) {
        Button("Sign In") { appState.logout() }
        Button("Not now", role: .cancel) {}
      } message: {
        Text("Please sign in again to sync with the server.")
      }
      .sheet(item: $selectedPage) { page in
        OfflineReaderView(page: page)
      }
    }
  }
}

#Preview {
  let appState = PreviewFixtures.makeAppState(token: "preview-token")
  let view = OfflineAppView().environmentObject(appState)
  return view
}
