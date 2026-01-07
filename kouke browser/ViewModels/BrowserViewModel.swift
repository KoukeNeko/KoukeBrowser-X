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

    init(initialTab: Tab? = nil, initialWebView: WKWebView? = nil) {
        // Create initial tab or use provided one based on settings
        let tab: Tab
        if let providedTab = initialTab {
            tab = providedTab
        } else {
            // Read startup behavior from settings
            switch settings.startupBehavior {
            case .startPage:
                tab = Tab(title: "New Tab", url: "kouke:blank")
            case .customURL:
                let url = settings.startupURL.isEmpty ? "kouke:blank" : settings.startupURL
                let title = extractHostname(from: url) ?? "New Tab"
                tab = Tab(title: title, url: url, isLoading: !url.isEmpty && url != "kouke:blank")
            case .lastTabs:
                // TODO: Implement session restore
                tab = Tab(title: "New Tab", url: "kouke:blank")
            }
        }

        tabs = [tab]
        activeTabId = tab.id
        inputURL = tab.url

        // Register the WebView if provided
        if let webView = initialWebView {
            webViews[tab.id] = webView
        }

        // Listen for menu bar commands
        NotificationCenter.default.publisher(for: .newTab)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.addTab()
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

    func addTabWithURL(_ url: String) {
        let title = extractHostname(from: url) ?? "New Tab"
        let newTab = Tab(title: title, url: url, isLoading: true)
        tabs.append(newTab)
        switchToTab(newTab.id)
    }

    func closeTab(_ id: UUID) {
        // If this is the last tab, show confirmation dialog and close window
        if tabs.count == 1 {
            let alert = NSAlert()
            alert.messageText = "Close Window?"
            alert.informativeText = "This is the last tab. Closing it will close the window."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Close")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                // Close the window
                NSApp.keyWindow?.close()
            }
            return
        }

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

    func moveTab(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
    }

    func moveTab(withID id: UUID, to index: Int) {
        guard let sourceIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        // Adjust destination index if moving forward
        let safeDestination = index > sourceIndex ? index - 1 : index
        guard sourceIndex != safeDestination else { return }

        let tab = tabs.remove(at: sourceIndex)
        tabs.insert(tab, at: safeDestination)
    }

    func moveTabBefore(draggedId: UUID, destinationId: UUID) {
        guard draggedId != destinationId,
              let fromIndex = tabs.firstIndex(where: { $0.id == draggedId }),
              let toIndex = tabs.firstIndex(where: { $0.id == destinationId }) else { return }

        let tab = tabs.remove(at: fromIndex)
        let newIndex = fromIndex < toIndex ? toIndex - 1 : toIndex
        tabs.insert(tab, at: newIndex)
    }

    func moveTabAfter(draggedId: UUID, destinationId: UUID) {
        guard draggedId != destinationId,
              let fromIndex = tabs.firstIndex(where: { $0.id == draggedId }),
              let toIndex = tabs.firstIndex(where: { $0.id == destinationId }) else { return }

        let tab = tabs.remove(at: fromIndex)
        let newIndex = fromIndex < toIndex ? toIndex : toIndex + 1
        tabs.insert(tab, at: newIndex)
    }

    /// Insert a tab before the destination tab (used for cross-window transfers)
    func insertTabBefore(_ tab: Tab, webView: WKWebView?, destinationId: UUID) {
        if let webView = webView {
            webViews[tab.id] = webView
        }
        guard let toIndex = tabs.firstIndex(where: { $0.id == destinationId }) else {
            tabs.append(tab)
            switchToTab(tab.id)
            return
        }
        tabs.insert(tab, at: toIndex)
        switchToTab(tab.id)
    }

    /// Insert a tab after the destination tab (used for cross-window transfers)
    func insertTabAfter(_ tab: Tab, webView: WKWebView?, destinationId: UUID) {
        if let webView = webView {
            webViews[tab.id] = webView
        }
        guard let toIndex = tabs.firstIndex(where: { $0.id == destinationId }) else {
            tabs.append(tab)
            switchToTab(tab.id)
            return
        }
        tabs.insert(tab, at: toIndex + 1)
        switchToTab(tab.id)
    }

    /// Detach a tab and return its data along with the WebView for transfer
    func detachTab(_ id: UUID) -> (tab: Tab, webView: WKWebView?)? {
        guard tabs.count > 1,
              let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }

        let tab = tabs[index]
        let webView = webViews[id]

        // Remove from this window
        webViews.removeValue(forKey: id)
        tabs.remove(at: index)

        // Switch to adjacent tab
        if activeTabId == id {
            let newIndex = min(index, tabs.count - 1)
            activeTabId = tabs[newIndex].id
            inputURL = tabs[newIndex].url
        }

        return (tab, webView)
    }

    /// Add an existing tab (used when receiving a detached tab)
    func addExistingTab(_ tab: Tab) {
        tabs.append(tab)
        switchToTab(tab.id)
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

    // MARK: - WebView Management

    func registerWebView(_ webView: WKWebView, for tabId: UUID) {
        webViews[tabId] = webView
    }

    func getWebView(for tabId: UUID) -> WKWebView? {
        return webViews[tabId]
    }

    /// Get the WebView for the active tab
    func getActiveWebView() -> WKWebView? {
        guard let id = activeTabId else { return nil }
        return webViews[id]
    }

    /// View the HTML source of the current page
    func viewSource() {
        guard let webView = getActiveWebView(), let currentURL = activeTab?.url else { return }
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, error in
            guard let self = self, let html = result as? String else { return }

            Task { @MainActor in
                // Create a new tab with kouke:// protocol
                let encodedURL = currentURL.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? currentURL
                let sourceURL = "kouke://view-source/\(encodedURL)"
                let newTab = Tab(title: "Source: \(currentURL)", url: sourceURL)
                self.tabs.append(newTab)
                self.switchToTab(newTab.id)

                // After a short delay, inject the source into a basic viewer
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let newWebView = self.webViews[newTab.id] {
                        let escapedHTML = html
                            .replacingOccurrences(of: "&", with: "&amp;")
                            .replacingOccurrences(of: "<", with: "&lt;")
                            .replacingOccurrences(of: ">", with: "&gt;")
                            .replacingOccurrences(of: "\"", with: "&quot;")
                            .replacingOccurrences(of: "\n", with: "<br>")
                            .replacingOccurrences(of: " ", with: "&nbsp;")

                        let viewerHTML = """
                        <!DOCTYPE html>
                        <html>
                        <head>
                            <title>View Source</title>
                            <style>
                                body {
                                    font-family: 'SF Mono', Menlo, Monaco, monospace;
                                    background: #1e1e1e;
                                    color: #d4d4d4;
                                    padding: 16px;
                                    margin: 0;
                                    white-space: pre-wrap;
                                    word-wrap: break-word;
                                    font-size: 12px;
                                    line-height: 1.5;
                                }
                            </style>
                        </head>
                        <body>\(escapedHTML)</body>
                        </html>
                        """
                        newWebView.loadHTMLString(viewerHTML, baseURL: nil)
                    }
                }
            }
        }
    }

    /// Open Web Inspector for the active tab
    func openDevTools() {
        guard let webView = getActiveWebView() else { return }
        // Use private API to show Web Inspector
        webView.perform(Selector(("_showInspector")))
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

    func updateTabNavigationState(canGoBack: Bool, canGoForward: Bool, for tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[index].canGoBack = canGoBack
        tabs[index].canGoForward = canGoForward
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

}
