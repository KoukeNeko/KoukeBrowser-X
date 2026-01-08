//
//  SessionManager.swift
//  kouke browser
//
//  Manages browser session persistence for tab restoration.
//

import Foundation

// MARK: - Session Data Models

struct SavedTab: Codable {
    let title: String
    let url: String
}

struct BrowserSession: Codable {
    let tabs: [SavedTab]
    let activeTabIndex: Int
    let savedAt: Date
}

// MARK: - Session Manager

class SessionManager {
    static let shared = SessionManager()

    private let defaults = UserDefaults.standard
    private let sessionKey = "browserSession"

    private init() {}

    // MARK: - Save Session

    func saveSession(tabs: [Tab], activeTabIndex: Int?) {
        // Filter out kouke: pages that shouldn't be restored (except blank)
        let savedTabs = tabs.map { tab in
            SavedTab(title: tab.title, url: tab.url)
        }

        let session = BrowserSession(
            tabs: savedTabs,
            activeTabIndex: activeTabIndex ?? 0,
            savedAt: Date()
        )

        do {
            let data = try JSONEncoder().encode(session)
            defaults.set(data, forKey: sessionKey)
        } catch {
            print("Failed to save session: \(error)")
        }
    }

    // MARK: - Load Session

    func loadSession() -> BrowserSession? {
        guard let data = defaults.data(forKey: sessionKey) else {
            return nil
        }

        do {
            let session = try JSONDecoder().decode(BrowserSession.self, from: data)

            // Only restore if session has tabs
            guard !session.tabs.isEmpty else {
                return nil
            }

            return session
        } catch {
            print("Failed to load session: \(error)")
            return nil
        }
    }

    // MARK: - Clear Session

    func clearSession() {
        defaults.removeObject(forKey: sessionKey)
    }

    // MARK: - Session Validity

    func hasValidSession() -> Bool {
        return loadSession() != nil
    }
}
