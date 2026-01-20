//
//  RecentlyClosedTabsManager.swift
//  kouke browser
//
//  Manages recently closed tabs for restoration.
//

import Foundation
import Combine

// MARK: - Closed Tab Model

struct ClosedTab: Identifiable, Codable {
    let id: UUID
    let title: String
    let url: String
    let closedAt: Date

    init(id: UUID = UUID(), title: String, url: String, closedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.closedAt = closedAt
    }

    /// Create from a Tab
    static func from(_ tab: Tab) -> ClosedTab {
        ClosedTab(
            title: tab.title,
            url: tab.url
        )
    }
}

// MARK: - Recently Closed Tabs Manager

class RecentlyClosedTabsManager: ObservableObject {
    static let shared = RecentlyClosedTabsManager()

    @Published private(set) var closedTabs: [ClosedTab] = []

    private let defaults = UserDefaults.standard
    private let storageKey = "recentlyClosedTabs"
    private let maxTabs = 20

    private init() {
        loadFromStorage()
    }

    // MARK: - Public Methods

    /// Add a closed tab to the list
    func addClosedTab(_ tab: Tab) {
        // Don't save special pages (kouke:blank, kouke:settings, etc.)
        guard !tab.isSpecialPage else { return }

        // Don't save empty or invalid URLs
        guard !tab.url.isEmpty,
              tab.url != "about:blank",
              URL(string: tab.url) != nil else { return }

        let closedTab = ClosedTab.from(tab)

        // Remove any existing entry with the same URL to avoid duplicates
        closedTabs.removeAll { $0.url == closedTab.url }

        // Insert at the beginning (most recent first)
        closedTabs.insert(closedTab, at: 0)

        // Keep only the most recent tabs
        if closedTabs.count > maxTabs {
            closedTabs = Array(closedTabs.prefix(maxTabs))
        }

        saveToStorage()
    }

    /// Remove a specific closed tab from the list
    func removeClosedTab(_ id: UUID) {
        closedTabs.removeAll { $0.id == id }
        saveToStorage()
    }

    /// Clear all recently closed tabs
    func clearAll() {
        closedTabs.removeAll()
        saveToStorage()
    }

    /// Get a closed tab for reopening (keeps the record)
    func reopenTab(_ id: UUID) -> ClosedTab? {
        return closedTabs.first { $0.id == id }
    }

    /// Reopen the most recently closed tab (keeps the record)
    func reopenLastClosedTab() -> ClosedTab? {
        return closedTabs.first
    }

    // MARK: - Private Methods

    private func loadFromStorage() {
        guard let data = defaults.data(forKey: storageKey) else { return }

        do {
            closedTabs = try JSONDecoder().decode([ClosedTab].self, from: data)
        } catch {
            NSLog("Failed to load recently closed tabs: \(error.localizedDescription)")
            closedTabs = []
        }
    }

    private func saveToStorage() {
        do {
            let data = try JSONEncoder().encode(closedTabs)
            defaults.set(data, forKey: storageKey)
        } catch {
            NSLog("Failed to save recently closed tabs: \(error.localizedDescription)")
        }
    }
}
