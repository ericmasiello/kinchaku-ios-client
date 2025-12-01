//
//  OfflineAppView.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//

import SwiftUI

struct OfflineAppView: View {
  @EnvironmentObject var tokenStore: TokenStore
  @StateObject private var vm = OfflineListViewModel()
  @State private var selectedPage: OfflinePage?

  var body: some View {
    NavigationView {
      contentView
    }
  }
  
  private var contentView: some View {
    VStack(spacing: 12) {
      statusRow
      syncProgressRow
      addRowSection
      listSection
    }
    .padding()
    .navigationTitle("Saves")
    // only add this for non MacOS
    #if !os(macOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      toolbarContent
    }
    .task {
      await vm.fetchAndSyncFromServer(tokenStore: tokenStore)
    }
    .alert("Session expired", isPresented: $vm.authExpired) {
      Button("Sign In") { tokenStore.logout() }
      Button("Not now", role: .cancel) {}
    } message: {
      Text("Please sign in again to sync with the server.")
    }
    .sheet(item: $selectedPage) { page in
      OfflineReaderView(page: page)
    }
  }
  
  private var statusRow: some View {
    HStack {
      if let msg = vm.statusMessage {
        Text(msg).font(.footnote).foregroundColor(.secondary)
      }
      Spacer()
    }
  }
  
  @ViewBuilder
  private var syncProgressRow: some View {
    if let sync = vm.syncProgress {
      HStack {
        if vm.isSyncing {
          ProgressView()
        }
        Text(sync).font(.footnote).foregroundColor(.secondary)
        Spacer()
      }
    }
  }
  
  private var addRowSection: some View {
    HStack {
      TextField("https://example.com", text: $vm.inputURLString)
      #if os(iOS)
        .textInputAutocapitalization(.never)
        .keyboardType(.webSearch)
      #endif
        .textContentType(.URL)
        .disableAutocorrection(true)
        .textFieldStyle(.plain)
      Button {
        Task {
          await vm.downloadAndSave(tokenStore: tokenStore, favorited: false)
        }
      } label: {
        vm.isBusy ? AnyView(ProgressView()) : AnyView(Text("Save"))
      }
      .buttonStyle(.glassProminent)
      .disabled(!vm.canDownload || vm.isBusy)
    }
  }
  
  private var listSection: some View {
    List {
      activePagesSection
      archivedPagesSection
      emptyStateSection
    }
    #if !os(macOS)
    .listStyle(.insetGrouped)
    #else
    .listStyle(.plain)
    #endif
    .refreshable {
      await vm.fetchAndSyncFromServer(tokenStore: tokenStore)
    }
  }
  
  @ViewBuilder
  private var activePagesSection: some View {
    if !vm.activePages.isEmpty {
      Section("Saved (Newest)") {
        ForEach(vm.activePages) { page in
          PageRow(page: page)
            .contentShape(Rectangle())
            .onTapGesture {
              if OfflineIndex.hasCache(for: page) {
                selectedPage = page
              }
            }
            .overlay(alignment: .trailing) {
              if !OfflineIndex.hasCache(for: page) {
                Text("Downloading…").font(.caption2).foregroundColor(.secondary)
              }
            }
            // make it so that full swipe achives the document
          
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
              Button {
                vm.archive(page, archived: true, tokenStore: tokenStore)
              } label: {
                Label("Archive", systemImage: "archivebox")
              }.tint(.gray)
              
              Button(role: .destructive) {
                vm.delete(page, tokenStore: tokenStore)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
        }
      }
    }
  }
  
  @ViewBuilder
  private var archivedPagesSection: some View {
    if !vm.archivedPages.isEmpty {
      Section("Archived") {
        ForEach(vm.archivedPages) { page in
          PageRow(page: page)
            .contentShape(Rectangle())
            .onTapGesture {
              if OfflineIndex.hasCache(for: page) {
                selectedPage = page
              }
            }
            .swipeActions {
              Button {
                vm.archive(page, archived: false, tokenStore: tokenStore)
              } label: {
                Label("Unarchive", systemImage: "archivebox.fill")
              }
              Button(role: .destructive) {
                vm.delete(page, tokenStore: tokenStore)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
        }
      }
    }
  }
  
  @ViewBuilder
  private var emptyStateSection: some View {
    if vm.activePages.isEmpty && vm.archivedPages.isEmpty {
      ContentUnavailableView("No pages",
                             systemImage: "tray",
                             description: Text("Sign in and your saved list will appear here."))
    }
  }

  #if !os(macOS)
  private var refreshToolPlacement: ToolbarItemPlacement = .navigationBarTrailing
  private var logoutToolPlacement: ToolbarItemPlacement = .navigationBarLeading
  #else
  private var refreshToolPlacement: ToolbarItemPlacement = .automatic
  private var logoutToolPlacement: ToolbarItemPlacement = .automatic
  #endif
  
  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItemGroup(placement: refreshToolPlacement) {
      Button {
        Task {
          await vm.fetchAndSyncFromServer(tokenStore: tokenStore)
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

    ToolbarItem(placement: logoutToolPlacement) {
      Button(role: .destructive) {
        tokenStore.logout()
      } label: {
        Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
      }
    }
  }
}

#Preview {
  let appState = PreviewFixtures.makeAppState(token: "preview-token")
  OfflineAppView().environmentObject(appState)
}
