//
//  Bookmark.swift
//  kouke browser
//
//  Bookmark model for storing saved websites.
//

import Foundation

struct Bookmark: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var url: String
    var dateAdded: Date
    var folderId: UUID?  // nil means root level

    init(id: UUID = UUID(), title: String, url: String, dateAdded: Date = Date(), folderId: UUID? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.dateAdded = dateAdded
        self.folderId = folderId
    }

    /// Get favicon URL with apple-touch-icon priority
    var faviconURL: URL? {
        guard let urlObj = URL(string: url),
              let host = urlObj.host else {
            return nil
        }
        return FaviconService.shared.faviconURL(for: url)
    }
}

struct BookmarkFolder: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var parentId: UUID?  // nil means root level
    var dateCreated: Date

    init(id: UUID = UUID(), name: String, parentId: UUID? = nil, dateCreated: Date = Date()) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.dateCreated = dateCreated
    }
}
