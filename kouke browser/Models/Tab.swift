//
//  Tab.swift
//  kouke browser
//
//  Tab model representing a browser tab with URL, title, and loading state.
//

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct Tab: Identifiable, Equatable {
    let id: UUID
    var title: String
    var url: String
    var isLoading: Bool
    #if os(macOS)
    var thumbnail: NSImage?
    #else
    var thumbnail: UIImage?
    #endif

    init(id: UUID = UUID(), title: String = "New Tab", url: String = "about:blank", isLoading: Bool = false) {
        self.id = id
        self.title = title
        self.url = url
        self.isLoading = isLoading
        self.thumbnail = nil
    }

    static func == (lhs: Tab, rhs: Tab) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.url == rhs.url &&
        lhs.isLoading == rhs.isLoading
        // Intentionally not comparing thumbnail for performance
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
