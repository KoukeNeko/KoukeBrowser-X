//
//  SuggestionsManager.swift
//  kouke browser
//
//  Manages StartPage suggestions with scoring algorithm.
//

import Foundation
import Combine

@MainActor
class SuggestionsManager: ObservableObject {
    static let shared = SuggestionsManager()

    @Published private(set) var suggestions: [PageSuggestion] = []

    private let defaults = UserDefaults.standard
    private let storageKey = "pageSuggestions"
    private let maxSuggestions = 30

    private init() {
        loadSuggestions()
    }

    // MARK: - Public API

    /// Record a page visit and update suggestions
    func recordVisit(url: String, title: String, thumbnailPath: String? = nil) {
        // Skip special pages
        guard !url.hasPrefix("kouke:"),
              !url.hasPrefix("about:"),
              !url.isEmpty else {
            return
        }

        // Normalize URL for comparison
        let normalizedURL = normalizeURL(url)

        // Find existing suggestion or create new
        if let index = suggestions.firstIndex(where: { normalizeURL($0.url) == normalizedURL }) {
            // Update existing
            var suggestion = suggestions[index]
            suggestion.visitCount += 1
            suggestion.lastVisitedAt = Date()
            if !title.isEmpty {
                suggestion.title = title
            }
            if let path = thumbnailPath {
                // Delete old thumbnail if different
                if let oldPath = suggestion.thumbnailPath, oldPath != path {
                    ThumbnailService.shared.deleteThumbnail(path: oldPath)
                }
                suggestion.thumbnailPath = path
            }
            suggestions[index] = suggestion
        } else {
            // Create new suggestion
            var suggestion = PageSuggestion(url: url, title: title)
            suggestion.thumbnailPath = thumbnailPath
            suggestions.append(suggestion)
        }

        // Re-sort by score and trim
        suggestions.sort { $0.score > $1.score }
        if suggestions.count > maxSuggestions {
            let removed = suggestions.suffix(from: maxSuggestions)
            // Clean up thumbnails for removed suggestions
            for suggestion in removed {
                if let path = suggestion.thumbnailPath {
                    ThumbnailService.shared.deleteThumbnail(path: path)
                }
            }
            suggestions = Array(suggestions.prefix(maxSuggestions))
        }

        saveSuggestions()
    }

    /// Update thumbnail for existing suggestion
    func updateThumbnail(for url: String, path: String) {
        let normalizedURL = normalizeURL(url)
        if let index = suggestions.firstIndex(where: { normalizeURL($0.url) == normalizedURL }) {
            // Delete old thumbnail if different
            if let oldPath = suggestions[index].thumbnailPath, oldPath != path {
                ThumbnailService.shared.deleteThumbnail(path: oldPath)
            }
            suggestions[index].thumbnailPath = path
            saveSuggestions()
        }
    }

    /// Remove a suggestion
    func removeSuggestion(_ id: UUID) {
        if let index = suggestions.firstIndex(where: { $0.id == id }) {
            if let path = suggestions[index].thumbnailPath {
                ThumbnailService.shared.deleteThumbnail(path: path)
            }
            suggestions.remove(at: index)
            saveSuggestions()
        }
    }

    /// Clear all suggestions
    func clearAll() {
        for suggestion in suggestions {
            if let path = suggestion.thumbnailPath {
                ThumbnailService.shared.deleteThumbnail(path: path)
            }
        }
        suggestions.removeAll()
        saveSuggestions()
    }

    /// Get top suggestions for display
    func topSuggestions(limit: Int = 8) -> [PageSuggestion] {
        Array(suggestions.prefix(limit))
    }

    // MARK: - Private Methods

    private func normalizeURL(_ url: String) -> String {
        guard var components = URLComponents(string: url) else { return url.lowercased() }

        // Remove query string and fragment for grouping purposes
        components.query = nil
        components.fragment = nil

        // Remove trailing slash
        var path = components.path
        if path.hasSuffix("/") && path.count > 1 {
            path = String(path.dropLast())
            components.path = path
        }

        return components.url?.absoluteString.lowercased() ?? url.lowercased()
    }

    private func saveSuggestions() {
        if let data = try? JSONEncoder().encode(suggestions) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func loadSuggestions() {
        guard let data = defaults.data(forKey: storageKey),
              let loaded = try? JSONDecoder().decode([PageSuggestion].self, from: data) else {
            return
        }
        suggestions = loaded.sorted { $0.score > $1.score }
    }
}
