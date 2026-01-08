//
//  HistoryItem.swift
//  kouke browser
//
//  Model for storing browsing history entries.
//

import Foundation

struct HistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var url: String
    var visitedAt: Date

    init(id: UUID = UUID(), title: String, url: String, visitedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.visitedAt = visitedAt
    }

    /// Get favicon URL from Google's favicon service
    var faviconURL: URL? {
        guard let urlObj = URL(string: url),
              let host = urlObj.host else {
            return nil
        }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32")
    }

    /// Get the domain from the URL for display
    var domain: String? {
        guard let urlObj = URL(string: url) else { return nil }
        return urlObj.host
    }
}
