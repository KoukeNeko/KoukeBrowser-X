//
//  PageSuggestion.swift
//  kouke browser
//
//  Data model for StartPage suggestions (Safari-like "候補" feature).
//

import Foundation

struct PageSuggestion: Identifiable, Codable, Equatable {
    let id: UUID
    var url: String
    var title: String
    var domain: String
    var visitCount: Int
    var lastVisitedAt: Date
    var thumbnailPath: String?  // Relative path within Thumbnails directory

    init(
        id: UUID = UUID(),
        url: String,
        title: String,
        visitCount: Int = 1,
        lastVisitedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.title = title.isEmpty ? url : title
        self.domain = URL(string: url)?.host ?? ""
        self.visitCount = visitCount
        self.lastVisitedAt = lastVisitedAt
        self.thumbnailPath = nil
    }

    // MARK: - Computed Properties

    /// Score for ranking (combines frequency and recency)
    var score: Double {
        let frequencyScore = Double(min(visitCount, 50))  // Cap at 50
        let daysSinceVisit = Date().timeIntervalSince(lastVisitedAt) / 86400
        let recencyScore = max(0, 30 - daysSinceVisit)  // Decay over 30 days
        return frequencyScore * 0.6 + recencyScore * 0.4
    }

    /// Relative time display for UI
    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "zh-TW")
        return formatter.localizedString(for: lastVisitedAt, relativeTo: Date())
    }

    /// Favicon URL (reuse existing FaviconService pattern)
    var faviconURL: URL? {
        FaviconService.shared.faviconURL(for: url)
    }

    // MARK: - Equatable

    static func == (lhs: PageSuggestion, rhs: PageSuggestion) -> Bool {
        lhs.id == rhs.id
    }
}
