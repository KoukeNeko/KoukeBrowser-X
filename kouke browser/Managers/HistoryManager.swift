//
//  HistoryManager.swift
//  kouke browser
//
//  Manages browsing history storage and operations.
//

import Foundation
import Combine

@MainActor
class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published private(set) var historyItems: [HistoryItem] = []

    private let historyKey = "browsingHistory"
    private let defaults = UserDefaults.standard
    private let maxHistoryItems = 10000  // Limit to prevent excessive storage

    private init() {
        loadHistory()
    }

    // MARK: - History Operations

    /// Add a new history item (skips duplicates within 1 second)
    func addHistoryItem(title: String, url: String) {
        // Skip empty URLs or about: pages
        guard !url.isEmpty,
              !url.hasPrefix("about:"),
              !url.hasPrefix("kouke:") else {
            return
        }

        // Avoid duplicate entries within 1 second (e.g., from redirects)
        let oneSecondAgo = Date().addingTimeInterval(-1)
        if let lastItem = historyItems.first,
           lastItem.url == url,
           lastItem.visitedAt > oneSecondAgo {
            return
        }

        let item = HistoryItem(title: title.isEmpty ? url : title, url: url)
        historyItems.insert(item, at: 0)

        // Trim if exceeds max
        if historyItems.count > maxHistoryItems {
            historyItems = Array(historyItems.prefix(maxHistoryItems))
        }

        saveHistory()
    }

    /// Remove a single history item
    func removeHistoryItem(_ id: UUID) {
        historyItems.removeAll { $0.id == id }
        saveHistory()
    }

    /// Clear all history
    func clearHistory() {
        historyItems.removeAll()
        saveHistory()
    }

    /// Clear history older than a specific date
    func clearHistory(olderThan date: Date) {
        historyItems.removeAll { $0.visitedAt < date }
        saveHistory()
    }

    // MARK: - Query Operations

    /// Get history items for today
    func todayItems() -> [HistoryItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return historyItems.filter { $0.visitedAt >= today }
    }

    /// Get history items for yesterday
    func yesterdayItems() -> [HistoryItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        return historyItems.filter { $0.visitedAt >= yesterday && $0.visitedAt < today }
    }

    /// Get history items for the last 7 days (excluding today and yesterday)
    func lastWeekItems() -> [HistoryItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        return historyItems.filter { $0.visitedAt >= weekAgo && $0.visitedAt < yesterday }
    }

    /// Get history items older than 7 days
    func olderItems() -> [HistoryItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        return historyItems.filter { $0.visitedAt < weekAgo }
    }

    /// Search history by title or URL
    func searchHistory(query: String) -> [HistoryItem] {
        guard !query.isEmpty else { return historyItems }
        let lowercasedQuery = query.lowercased()
        return historyItems.filter {
            $0.title.lowercased().contains(lowercasedQuery) ||
            $0.url.lowercased().contains(lowercasedQuery)
        }
    }

    /// Group history items by date for display
    func groupedByDate() -> [(title: String, items: [HistoryItem])] {
        var groups: [(title: String, items: [HistoryItem])] = []

        let today = todayItems()
        if !today.isEmpty {
            groups.append((title: "Today", items: today))
        }

        let yesterday = yesterdayItems()
        if !yesterday.isEmpty {
            groups.append((title: "Yesterday", items: yesterday))
        }

        let lastWeek = lastWeekItems()
        if !lastWeek.isEmpty {
            groups.append((title: "Last 7 Days", items: lastWeek))
        }

        let older = olderItems()
        if !older.isEmpty {
            groups.append((title: "Older", items: older))
        }

        return groups
    }

    // MARK: - Persistence

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(historyItems) {
            defaults.set(data, forKey: historyKey)
        }
    }

    private func loadHistory() {
        guard let data = defaults.data(forKey: historyKey),
              let loaded = try? JSONDecoder().decode([HistoryItem].self, from: data) else {
            return
        }
        historyItems = loaded
    }
}
