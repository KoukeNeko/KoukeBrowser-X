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
    var canGoBack: Bool
    var canGoForward: Bool
    #if os(macOS)
    var thumbnail: NSImage?
    #else
    var thumbnail: UIImage?
    #endif

    init(id: UUID = UUID(), title: String = "New Tab", url: String = "kouke:blank", isLoading: Bool = false, canGoBack: Bool = false, canGoForward: Bool = false) {
        self.id = id
        self.title = title
        self.url = url
        self.isLoading = isLoading
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.thumbnail = nil
    }

    static func == (lhs: Tab, rhs: Tab) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.url == rhs.url &&
        lhs.isLoading == rhs.isLoading &&
        lhs.canGoBack == rhs.canGoBack &&
        lhs.canGoForward == rhs.canGoForward
        // Intentionally not comparing thumbnail for performance
    }
    
    /// Check if this tab is showing a special internal page
    var isSpecialPage: Bool {
        url == "kouke:blank" || url.hasPrefix("kouke://")
    }

    /// Check if this is a kouke:// internal page
    var isKoukePage: Bool {
        url.hasPrefix("kouke://")
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
