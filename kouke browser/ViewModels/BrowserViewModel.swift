//
//  BrowserViewModel.swift
//  kouke browser
//
//  Central state management for browser tabs and navigation.
//

import Foundation
import SwiftUI
import Combine
import WebKit

@MainActor
class BrowserViewModel: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var activeTabId: UUID?
    @Published var inputURL: String = ""
    
    // WebView instances managed separately
    private var webViews: [UUID: WKWebView] = [:]
    
    let settings = BrowserSettings.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Create initial tab
        let initialTab = Tab(title: "example.com", url: "https://example.com", isLoading: true)
        tabs = [initialTab]
        activeTabId = initialTab.id
        inputURL = initialTab.url
        
        // Listen for menu bar commands
        NotificationCenter.default.publisher(for: .newTab)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.addTab()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .openSettings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.openSettings()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Computed Properties
    
    var activeTab: Tab? {
        guard let id = activeTabId else { return nil }
        return tabs.first { $0.id == id }
    }
    
    var activeTabIndex: Int? {
        guard let id = activeTabId else { return nil }
        return tabs.firstIndex { $0.id == id }
    }
    
    // MARK: - Tab Management
    
    func addTab() {
        let newTab = Tab()
        tabs.append(newTab)
        switchToTab(newTab.id)
    }
    
    func closeTab(_ id: UUID) {
        guard tabs.count > 1 else { return }
        
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            // Remove webview
            webViews.removeValue(forKey: id)
            
            // Remove tab
            tabs.remove(at: index)
            
            // Switch to adjacent tab if closing active tab
            if activeTabId == id {
                let newIndex = min(index, tabs.count - 1)
                activeTabId = tabs[newIndex].id
                inputURL = tabs[newIndex].url
            }
        }
    }
    
    func switchToTab(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        activeTabId = id
        inputURL = tab.url
    }
    
    // MARK: - Navigation
    
    func navigate() {
        guard let index = activeTabIndex else { return }
        
        var urlString = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { return }
        
        // Determine if input is URL or search query
        if isLikelyURL(urlString) {
            if !urlString.hasPrefix("http://") && 
               !urlString.hasPrefix("https://") && 
               !urlString.hasPrefix("about:") {
                urlString = "https://" + urlString
            }
        } else {
            urlString = settings.getSearchURL(for: urlString)
        }
        
        inputURL = urlString
        
        // Update tab
        var tab = tabs[index]
        tab.url = urlString
        tab.title = extractHostname(from: urlString) ?? "New Tab"
        tab.isLoading = !tab.isSpecialPage
        tabs[index] = tab
        
        // Notify webview to load
        if let webView = webViews[tab.id], !tab.isSpecialPage {
            if let url = URL(string: urlString) {
                webView.load(URLRequest(url: url))
            }
        }
    }
    
    func goBack() {
        guard let id = activeTabId, let webView = webViews[id] else { return }
        webView.goBack()
    }
    
    func goForward() {
        guard let id = activeTabId, let webView = webViews[id] else { return }
        webView.goForward()
    }
    
    func reload() {
        guard let id = activeTabId, let webView = webViews[id] else { return }
        webView.reload()
    }
    
    func navigateFromStartPage(to url: String) {
        inputURL = url
        navigate()
    }
    
    func openSettings() {
        inputURL = "about:settings"
        navigate()
    }
    
    // MARK: - WebView Management
    
    func registerWebView(_ webView: WKWebView, for tabId: UUID) {
        webViews[tabId] = webView
    }
    
    func getWebView(for tabId: UUID) -> WKWebView? {
        return webViews[tabId]
    }
    
    // MARK: - Tab State Updates (called from WebView delegates)
    
    func updateTabTitle(_ title: String, for tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[index].title = title
    }
    
    func updateTabURL(_ url: String, for tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[index].url = url
        if tabId == activeTabId {
            inputURL = url
        }
    }
    
    func updateTabLoadingState(_ isLoading: Bool, for tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[index].isLoading = isLoading
    }

    #if os(macOS)
    func updateTabThumbnail(_ thumbnail: NSImage, for tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[index].thumbnail = thumbnail
    }

    func captureTabThumbnail(for tabId: UUID) {
        guard let webView = webViews[tabId] else { return }

        let config = WKSnapshotConfiguration()
        config.snapshotWidth = 300  // Reasonable thumbnail width

        webView.takeSnapshot(with: config) { [weak self] image, error in
            guard let self = self, let image = image, error == nil else { return }
            Task { @MainActor in
                self.updateTabThumbnail(image, for: tabId)
            }
        }
    }
    #endif
    
    // MARK: - Helpers
    
    private func isLikelyURL(_ input: String) -> Bool {
        // Has protocol
        if input.hasPrefix("http://") || input.hasPrefix("https://") || input.hasPrefix("about:") {
            return true
        }
        
        // Domain-like pattern (contains dot with valid structure)
        let pattern = "^[\\w-]+(\\.[\\w-]+)+([\\/?#].*)?$"
        if input.range(of: pattern, options: .regularExpression) != nil {
            return true
        }
        
        // Localhost or IP address
        if input.hasPrefix("localhost") {
            return true
        }
        let ipPattern = "^\\d{1,3}(\\.\\d{1,3}){3}"
        if input.range(of: ipPattern, options: .regularExpression) != nil {
            return true
        }
        
        return false
    }
    
    private func extractHostname(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        return url.host
    }
}

// MARK: - Notification Names

extension Notification.Name {
    // File menu
    static let newTab = Notification.Name("newTab")
    static let newWindow = Notification.Name("newWindow")
    static let closeTab = Notification.Name("closeTab")

    // View menu
    static let reloadPage = Notification.Name("reloadPage")
    static let forceReloadPage = Notification.Name("forceReloadPage")
    static let zoomIn = Notification.Name("zoomIn")
    static let zoomOut = Notification.Name("zoomOut")
    static let resetZoom = Notification.Name("resetZoom")
    static let toggleFullScreen = Notification.Name("toggleFullScreen")
    static let showAllTabs = Notification.Name("showAllTabs")

    // History menu
    static let goBack = Notification.Name("goBack")
    static let goForward = Notification.Name("goForward")
    static let showHistory = Notification.Name("showHistory")
    static let clearHistory = Notification.Name("clearHistory")

    // Bookmarks menu
    static let addBookmark = Notification.Name("addBookmark")
    static let showBookmarks = Notification.Name("showBookmarks")
    static let bookmarkTab = Notification.Name("bookmarkTab")
    static let bookmarkAllTabs = Notification.Name("bookmarkAllTabs")

    // Developer menu
    static let viewSource = Notification.Name("viewSource")
    static let openDevTools = Notification.Name("openDevTools")
    static let openConsole = Notification.Name("openConsole")
    static let toggleJavaScript = Notification.Name("toggleJavaScript")
    static let toggleImages = Notification.Name("toggleImages")
    static let clearCache = Notification.Name("clearCache")
    static let clearCookies = Notification.Name("clearCookies")

    // Settings
    static let openSettings = Notification.Name("openSettings")
}
