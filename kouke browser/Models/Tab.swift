//
//  Tab.swift
//  kouke browser
//
//  Tab model representing a browser tab with URL, title, and loading state.
//

import Foundation

struct Tab: Identifiable, Equatable {
    let id: UUID
    var title: String
    var url: String
    var isLoading: Bool
    
    init(id: UUID = UUID(), title: String = "New Tab", url: String = "about:blank", isLoading: Bool = false) {
        self.id = id
        self.title = title
        self.url = url
        self.isLoading = isLoading
    }
    
    /// Check if this tab is showing a special internal page
    var isSpecialPage: Bool {
        url == "about:blank" || url == "about:settings"
    }
    
    /// Get favicon URL from Google's favicon service
    var faviconURL: URL? {
        guard let urlObj = URL(string: url),
              let host = urlObj.host else {
            return nil
        }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32")
    }
}
