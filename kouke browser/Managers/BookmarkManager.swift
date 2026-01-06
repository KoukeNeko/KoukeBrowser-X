//
//  BookmarkManager.swift
//  kouke browser
//
//  Manages bookmark storage and operations.
//

import Foundation
import Combine

@MainActor
class BookmarkManager: ObservableObject {
    static let shared = BookmarkManager()

    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var folders: [BookmarkFolder] = []

    private let bookmarksKey = "bookmarks"
    private let foldersKey = "bookmarkFolders"
    private let defaults = UserDefaults.standard

    private init() {
        loadBookmarks()
        loadFolders()
    }

    // MARK: - Bookmark Operations

    func addBookmark(title: String, url: String, folderId: UUID? = nil) {
        let bookmark = Bookmark(title: title, url: url, folderId: folderId)
        bookmarks.append(bookmark)
        saveBookmarks()
    }

    func addBookmark(_ bookmark: Bookmark) {
        bookmarks.append(bookmark)
        saveBookmarks()
    }

    func removeBookmark(_ id: UUID) {
        bookmarks.removeAll { $0.id == id }
        saveBookmarks()
    }

    func updateBookmark(_ id: UUID, title: String? = nil, url: String? = nil, folderId: UUID?? = nil) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }

        if let title = title {
            bookmarks[index].title = title
        }
        if let url = url {
            bookmarks[index].url = url
        }
        if let folderId = folderId {
            bookmarks[index].folderId = folderId
        }

        saveBookmarks()
    }

    func isBookmarked(url: String) -> Bool {
        bookmarks.contains { $0.url == url }
    }

    func getBookmark(for url: String) -> Bookmark? {
        bookmarks.first { $0.url == url }
    }

    func toggleBookmark(title: String, url: String) {
        if let existing = getBookmark(for: url) {
            removeBookmark(existing.id)
        } else {
            addBookmark(title: title, url: url)
        }
    }

    // MARK: - Folder Operations

    func addFolder(name: String, parentId: UUID? = nil) {
        let folder = BookmarkFolder(name: name, parentId: parentId)
        folders.append(folder)
        saveFolders()
    }

    func removeFolder(_ id: UUID) {
        // Remove all bookmarks in this folder
        bookmarks.removeAll { $0.folderId == id }

        // Remove all subfolders
        let subfolderIds = folders.filter { $0.parentId == id }.map { $0.id }
        for subfolderId in subfolderIds {
            removeFolder(subfolderId)
        }

        // Remove the folder itself
        folders.removeAll { $0.id == id }

        saveBookmarks()
        saveFolders()
    }

    func updateFolder(_ id: UUID, name: String? = nil, parentId: UUID?? = nil) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }

        if let name = name {
            folders[index].name = name
        }
        if let parentId = parentId {
            folders[index].parentId = parentId
        }

        saveFolders()
    }

    // MARK: - Query Operations

    func bookmarks(in folderId: UUID?) -> [Bookmark] {
        bookmarks.filter { $0.folderId == folderId }
    }

    func folders(in parentId: UUID?) -> [BookmarkFolder] {
        folders.filter { $0.parentId == parentId }
    }

    func rootBookmarks() -> [Bookmark] {
        bookmarks(in: nil)
    }

    func rootFolders() -> [BookmarkFolder] {
        folders(in: nil)
    }

    // MARK: - Persistence

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            defaults.set(data, forKey: bookmarksKey)
        }
    }

    private func loadBookmarks() {
        guard let data = defaults.data(forKey: bookmarksKey),
              let loaded = try? JSONDecoder().decode([Bookmark].self, from: data) else {
            return
        }
        bookmarks = loaded
    }

    private func saveFolders() {
        if let data = try? JSONEncoder().encode(folders) {
            defaults.set(data, forKey: foldersKey)
        }
    }

    private func loadFolders() {
        guard let data = defaults.data(forKey: foldersKey),
              let loaded = try? JSONDecoder().decode([BookmarkFolder].self, from: data) else {
            return
        }
        folders = loaded
    }

    // MARK: - Import/Export

    func exportBookmarks() -> Data? {
        let exportData = BookmarkExportData(bookmarks: bookmarks, folders: folders)
        return try? JSONEncoder().encode(exportData)
    }

    func importBookmarks(from data: Data) {
        guard let importData = try? JSONDecoder().decode(BookmarkExportData.self, from: data) else {
            return
        }

        // Merge imported data
        for bookmark in importData.bookmarks {
            if !bookmarks.contains(where: { $0.url == bookmark.url }) {
                bookmarks.append(bookmark)
            }
        }

        for folder in importData.folders {
            if !folders.contains(where: { $0.id == folder.id }) {
                folders.append(folder)
            }
        }

        saveBookmarks()
        saveFolders()
    }
}

// MARK: - Export Data Structure

private struct BookmarkExportData: Codable {
    let bookmarks: [Bookmark]
    let folders: [BookmarkFolder]
}
