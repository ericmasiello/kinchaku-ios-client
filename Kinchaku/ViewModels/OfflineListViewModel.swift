//
//  OfflineListViewModel.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//

import Foundation
import SwiftUI

@MainActor
final class OfflineListViewModel: ObservableObject {
  @Published var pages: [OfflinePage] = []
  @Published var inputURLString: String = ""
  @Published var isBusy = false
  @Published var statusMessage: String?
  @Published var syncProgress: String?
  @Published var isSyncing = false
  @Published var authExpired = false

  private let serverDate: DateFormatter = {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = TimeZone(secondsFromGMT: 0)
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return df
  }()

  init() {
    pages = OfflineIndex.load()
    sortPages()
  }

  func sortPages() { pages.sort { $0.dateAdded > $1.dateAdded } }
  var activePages: [OfflinePage] { pages.filter { !$0.archived } }
  var archivedPages: [OfflinePage] { pages.filter { $0.archived } }
  var canDownload: Bool { URL(string: inputURLString)?.scheme?.hasPrefix("http") == true }

    // Manual add (still supported)
  func downloadAndSave(tokenStore: TokenStore, favorited: Bool = false) async {
    guard let url = URL(string: inputURLString) else { return }
    isBusy = true
    defer { isBusy = false }
    statusMessage = "Downloading…"

    do {
      // 1) Local cache first (as before)
      let result = try await OfflineDownloader.downloadSite(at: url)
      let page = OfflinePage(
        id: UUID(),
        remoteId: nil,
        title: result.pageTitle,
        originalURL: url,
        dirName: result.dirName,
        dateAdded: Date(),
        archived: false,
        favorited: favorited
      )
      pages.insert(page, at: 0)
      sortPages()
      OfflineIndex.save(pages)
      statusMessage = "Saved \"\(page.title)\" locally (\(result.assetCount) assets)"
      inputURLString = ""

      // 2) Then POST to API (best-effort). On success 201, merge fields.
      if tokenStore.token != nil {
        let articlesService = ArticlesServiceWithRefresh(tokenStore: tokenStore)
        do {
          let created = try await articlesService.createArticle(url: url, favorited: favorited)
          let serverDate = serverDate // reuse the formatter already defined on the VM
          if let idx = pages.firstIndex(where: { $0.id == page.id }) {
            pages[idx].remoteId = created.id
            pages[idx].archived = created.archived != 0
            pages[idx].favorited = created.favorited != 0
            pages[idx].dateAdded = serverDate.date(from: created.date_added) ?? pages[idx].dateAdded
          }
          sortPages()
          OfflineIndex.save(pages)
          statusMessage = "Saved locally and synced to server (id \(created.id))."
        } catch AuthError.expired, AuthError.refreshFailed {
          authExpired = true
          statusMessage = "Saved locally. Sign in again to sync."
        } catch {
          // Keep local record; report but don't roll back
          statusMessage = "Saved locally. Server create failed: \(error.localizedDescription)"
        }
      }
    } catch {
      statusMessage = "Download failed: \(error.localizedDescription)"
    }
  }

  // NEW: Fetch from remote and persist offline
  func fetchAndSyncFromServer(tokenStore: TokenStore) async {
    if isSyncing { return }
    isSyncing = true
    defer { isSyncing = false }
    
    let articlesService = ArticlesServiceWithRefresh(tokenStore: tokenStore)
    
    do {
      syncProgress = "Fetching remote list…"
      let items = try await articlesService.fetchArticles()

      // Merge: update existing by remoteId or URL; add new ones
      let byRemoteId = Dictionary(uniqueKeysWithValues: pages.compactMap { p in
        p.remoteId.map { ($0, p) }
      })
      var updatedPages = pages

      for item in items {
        // Map server → model
        let date = serverDate.date(from: item.date_added) ?? Date()
        let archived = item.archived != 0
        let favorited = item.favorited != 0

        if let existing = byRemoteId[item.id] ?? pages.first(where: { $0.originalURL == item.url }) {
          // Update flags & date; keep cache dir if any
          if let idx = updatedPages.firstIndex(where: { $0.id == existing.id }) {
            updatedPages[idx].remoteId = item.id
            updatedPages[idx].archived = archived
            updatedPages[idx].favorited = favorited
            updatedPages[idx].dateAdded = date
          }
        } else {
          // New local entry (not yet cached)
          updatedPages.append(OfflinePage(
            id: UUID(), remoteId: item.id, title: item.url.host ?? "Untitled",
            originalURL: item.url, dirName: nil, dateAdded: date,
            archived: archived, favorited: favorited
          ))
        }
      }

      // Sort + save index before caching so UI shows immediately
      pages = updatedPages
      sortPages()
      OfflineIndex.save(pages)

      // Cache all uncached pages in parallel (first-order assets)
      let toCache = pages.filter { !$0.archived && !OfflineIndex.hasCache(for: $0) }
      if !toCache.isEmpty {
        syncProgress = "Caching \(toCache.count) pages for offline…"
        try await withThrowingTaskGroup(of: (UUID, DownloadResult).self) { group in
          for page in toCache {
            group.addTask {
              let result = try await OfflineDownloader.downloadSite(at: page.originalURL)
              return (page.id, result)
            }
          }
          var map: [UUID: DownloadResult] = [:]
          for try await (pid, res) in group { map[pid] = res }
          // Write back dir names and titles
          for i in pages.indices {
            if let res = map[pages[i].id] {
              pages[i].dirName = res.dirName
              if pages[i].title.isEmpty || pages[i].title == (pages[i].originalURL.host ?? "") {
                pages[i].title = res.pageTitle
              }
            }
          }
        }
        OfflineIndex.save(pages)
        syncProgress = "Offline cache complete."
      } else {
        syncProgress = "Everything is already cached."
      }
    } catch AuthError.expired, AuthError.refreshFailed {
      authExpired = true // tell the UI
      syncProgress = "Session expired."
    } catch {
      syncProgress = "Sync failed: \(error.localizedDescription)"
    }
  }

  func archive(_ page: OfflinePage, archived: Bool, tokenStore: TokenStore) {
    guard let i = pages.firstIndex(of: page) else { return }

    // 1) Optimistic local update
    pages[i].archived = archived
    sortPages()
    OfflineIndex.save(pages)
    statusMessage = archived ? "Archived locally." : "Unarchived locally."

    #if os(iOS)
    UIAccessibility.post(
      notification: .announcement,
      argument: archived ? "Archived" : "Unarchived"
    )
    #endif

    // 2) Attempt to persist to server (best-effort)
    guard let remoteId = pages[i].remoteId else { return }

    if tokenStore.token != nil {
      let articlesService = ArticlesServiceWithRefresh(tokenStore: tokenStore)
      Task {
        do {
          try await articlesService.updateArticleArchived(articleId: remoteId, archived: archived)
          await MainActor.run {
            self.statusMessage = archived ? "Archived on server." : "Unarchived on server."
          }
        } catch AuthError.expired, AuthError.refreshFailed {
          await MainActor.run {
            self.authExpired = true
            self.statusMessage = "Local change saved. Sign in again to sync archive state."
          }
        } catch {
          await MainActor.run {
            self.statusMessage = "Local change saved. Server update failed: \(error.localizedDescription)"
          }
        }
      }
    }
    
  }

  func delete(_ page: OfflinePage, tokenStore: TokenStore) {
    // 1) Optimistic local update
    OfflineIndex.removeCache(dirName: page.dirName)
    pages.removeAll { $0.id == page.id }
    OfflineIndex.save(pages)
    statusMessage = "Deleted locally."

    #if os(iOS)
    UIAccessibility.post(
      notification: .announcement,
      argument: "Deleted"
    )
    #endif

    // 2) Attempt to persist to server (best-effort)
    guard let remoteId = page.remoteId else { return }

    if tokenStore.token != nil {
      let articlesService = ArticlesServiceWithRefresh(tokenStore: tokenStore)
      Task {
        do {
          try await articlesService.deleteArticle(articleId: remoteId)
          await MainActor.run {
            self.statusMessage = "Deleted on server."
          }
        } catch AuthError.expired, AuthError.refreshFailed {
          await MainActor.run {
            self.authExpired = true
            self.statusMessage = "Local delete saved. Sign in again to sync delete state."
          }
        } catch {
          await MainActor.run {
            self.statusMessage = "Local delete saved. Server delete failed: \(error.localizedDescription)"
          }
        }
      }
    }
  }
}
