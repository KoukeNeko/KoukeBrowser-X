//
//  WindowManager.swift
//  kouke browser
//
//  Manages browser windows, including creating new windows from detached tabs.
//

import Foundation
import SwiftUI
import AppKit
import WebKit

@MainActor
class WindowManager {
    static let shared = WindowManager()

    private var windowViewModels: [Int: BrowserViewModel] = [:]  // windowNumber -> viewModel
    private var windows: [NSWindow] = []

    private init() {
        // Listen for app termination to save session
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Execute synchronously - notification is already on main queue
            self?.saveAllSessions()
        }
    }

    // MARK: - Session Management

    /// Initialize the window manager (call at app startup)
    func initialize() {
        // This ensures the singleton is created and observers are set up
    }

    /// Save all window sessions (called on app termination)
    func saveAllSessions() {
        // Collect all tabs from all windows
        var allTabs: [Tab] = []
        var activeIndex = 0
        var currentOffset = 0

        for (_, viewModel) in windowViewModels {
            allTabs.append(contentsOf: viewModel.tabs)
            if let activeIdx = viewModel.activeTabIndex {
                activeIndex = currentOffset + activeIdx
            }
            currentOffset += viewModel.tabs.count
        }

        // If no tabs collected, try to save from first window
        if allTabs.isEmpty, let firstViewModel = windowViewModels.values.first {
            allTabs = firstViewModel.tabs
            activeIndex = firstViewModel.activeTabIndex ?? 0
        }

        if !allTabs.isEmpty {
            SessionManager.shared.saveSession(tabs: allTabs, activeTabIndex: activeIndex)
        }
    }

    /// Register a view model for a window (called from BrowserView)
    func registerViewModel(_ viewModel: BrowserViewModel, for window: NSWindow) {
        let windowNumber = window.windowNumber
        windowViewModels[windowNumber] = viewModel
        NSLog("📝 WindowManager: Registered viewModel for window #\(windowNumber). Total registered: \(windowViewModels.count)")
    }

    /// Remove tab from a specific window and return it along with WebView
    /// If the window becomes empty after removing the tab, it will be closed automatically
    func removeTabFromWindow(windowNumber: Int, tabId: UUID) -> (tab: Tab, webView: WKWebView?)? {
        NSLog("🔍 WindowManager: Attempting to remove tab \(tabId) from window #\(windowNumber)")
        NSLog("🔍 WindowManager: Registered windows: \(Array(windowViewModels.keys))")

        guard let viewModel = windowViewModels[windowNumber] else {
            NSLog("❌ WindowManager: No viewModel found for window #\(windowNumber)")
            return nil
        }

        let isLastTab = viewModel.tabs.count == 1
        let result = viewModel.detachTab(tabId, allowLastTab: true)

        if result == nil {
            NSLog("❌ WindowManager: detachTab returned nil")
        } else {
            NSLog("✅ WindowManager: Successfully detached tab")

            // If this was the last tab, close the source window after a delay
            // to allow the current drag operation to fully complete
            if isLastTab {
                NSLog("🚪 WindowManager: Will close empty window #\(windowNumber)")
                // Use a longer delay to ensure drag operation completes before closing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    NSLog("🚪 WindowManager: Attempting to close window #\(windowNumber)")
                    NSLog("🚪 WindowManager: All windows: \(NSApp.windows.map { $0.windowNumber })")
                    // Find window from all app windows, not just our tracked windows array
                    if let window = NSApp.windows.first(where: { $0.windowNumber == windowNumber }) {
                        NSLog("🚪 WindowManager: Found window, closing it")
                        window.close()
                    } else {
                        NSLog("🚪 WindowManager: Window #\(windowNumber) not found in NSApp.windows")
                    }
                    _ = self // Keep reference to avoid warning
                }
            }
        }
        return result
    }

    /// Create a new browser window with a detached tab or a new blank tab
    func createNewWindow(with tab: Tab?, webView: WKWebView? = nil, at screenPoint: NSPoint?) {
        // Create a new view model with the detached tab and its WebView, or a new blank tab
        let viewModel: BrowserViewModel
        let windowTab: Tab
        let settings = BrowserSettings.shared

        if let existingTab = tab {
            viewModel = BrowserViewModel(initialTab: existingTab, initialWebView: webView)
            windowTab = existingTab
        } else {
            // Create a new tab based on newWindowOpensWith setting
            let newTab: Tab

            switch settings.newWindowOpensWith {
            case .startPage:
                newTab = Tab(title: "New Tab", url: KoukeScheme.blank)
            case .homepage:
                let url = settings.homepage.isEmpty ? KoukeScheme.blank : settings.homepage
                let title = URL(string: url)?.host ?? "New Tab"
                newTab = Tab(title: title, url: url, isLoading: !url.hasPrefix("kouke:"))
            case .emptyPage:
                newTab = Tab(title: "New Tab", url: "about:blank")
            case .samePage:
                // Get the current page URL from the key window's active tab
                if let currentViewModel = windowViewModels.values.first(where: { vm in
                    windowViewModels.contains { $0.value === vm }
                }), let activeTab = currentViewModel.activeTab {
                    newTab = Tab(title: activeTab.title, url: activeTab.url, isLoading: !activeTab.isSpecialPage)
                } else {
                    newTab = Tab(title: "New Tab", url: KoukeScheme.blank)
                }
            }

            viewModel = BrowserViewModel(initialTab: newTab, initialWebView: nil)
            windowTab = newTab
        }

        // Create the browser view
        let browserView = BrowserViewForWindow(viewModel: viewModel)

        // Create the window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(named: "TitleBarBg")
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 400, height: 300)

        // Set window title for Dock menu display
        window.title = windowTab.title

        // Make window appear in Window menu and Dock
        window.isExcludedFromWindowsMenu = false

        // Position window at drop location or center on screen
        if let point = screenPoint {
            let windowOrigin = NSPoint(
                x: point.x - 512,  // Center horizontally
                y: point.y - 50    // Position slightly below cursor
            )
            window.setFrameOrigin(windowOrigin)
        } else {
            window.center()
        }

        // Set content view
        window.contentView = NSHostingView(rootView: browserView)

        // Configure traffic lights
        configureTrafficLights(for: window)

        // Show the window
        window.makeKeyAndOrderFront(nil)

        // Keep reference and register viewModel
        windows.append(window)
        let windowNumber = window.windowNumber
        windowViewModels[windowNumber] = viewModel
        NSLog("📝 WindowManager.createNewWindow: Registered viewModel for window #\(windowNumber). Total: \(windowViewModels.count)")

        // Clean up closed windows
        // Note: Using synchronous cleanup since notification is already on main queue
        // Avoid using Task { @MainActor } here as it can cause EXC_BAD_ACCESS
        // when the async task completes after objects are deallocated
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let closedWindow = notification.object as? NSWindow else { return }
            // Synchronous cleanup - no Task needed since we're already on main queue
            self.windows.removeAll { $0 == closedWindow }
            self.windowViewModels.removeValue(forKey: windowNumber)
            NSLog("🗑️ WindowManager: Unregistered window #\(windowNumber). Remaining: \(self.windowViewModels.count)")
        }
    }

    private func configureTrafficLights(for window: NSWindow) {
        let leadingOffset: CGFloat = 6
        let topOffset: CGFloat = 6

        // Apply offset to traffic light buttons
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { buttonType in
            if let button = window.standardWindowButton(buttonType) {
                var frame = button.frame
                frame.origin.x += leadingOffset
                frame.origin.y -= topOffset
                button.frame = frame
            }
        }

        // Observe resize to maintain positions
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            guard let window = window else { return }
            [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { buttonType in
                if let button = window.standardWindowButton(buttonType) {
                    var frame = button.frame
                    frame.origin.x += leadingOffset
                    frame.origin.y -= topOffset
                    button.frame = frame
                }
            }
        }
    }
}

// MARK: - Browser View for Detached Window

struct BrowserViewForWindow: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject private var settings = BrowserSettings.shared
    @ObservedObject private var bookmarkManager = BookmarkManager.shared
    @State private var showTabOverview = false
    @State private var showHistory = false
    @State private var showBookmarks = false
    @State private var showDownloads = false
    @State private var showBookmarkAllTabsAlert = false
    @State private var currentZoomLevel: Double = 1.0

    var body: some View {
        mainContent
            .sheet(isPresented: $showHistory) {
                historySheet
            }
            .sheet(isPresented: $showBookmarks) {
                bookmarksSheet
            }
            .sheet(isPresented: $showDownloads) {
                DownloadsView(onDismiss: { showDownloads = false })
            }
            .background(Color("Bg"))
            .ignoresSafeArea()
            .onChange(of: viewModel.activeTab?.title) { _, newTitle in
                if let title = newTitle {
                    NSApp.keyWindow?.title = title
                }
            }
            .modifier(WindowFileMenuModifier(viewModel: viewModel))
            .modifier(WindowViewMenuModifier(viewModel: viewModel, showTabOverview: $showTabOverview, currentZoomLevel: $currentZoomLevel))
            .modifier(WindowHistoryMenuModifier(viewModel: viewModel, showHistory: $showHistory))
            .modifier(WindowBookmarksMenuModifier(showBookmarks: $showBookmarks, showBookmarkAllTabsAlert: $showBookmarkAllTabsAlert))
            .modifier(WindowDownloadsMenuModifier(showDownloads: $showDownloads))
            .modifier(WindowDeveloperMenuModifier(viewModel: viewModel, settings: settings))
            .modifier(WindowKoukeURLModifier(viewModel: viewModel))
            .modifier(WindowSettingsModifier(viewModel: viewModel))
            .alert("Bookmark All Tabs", isPresented: $showBookmarkAllTabsAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Bookmark All") {
                    bookmarkAllTabs()
                }
            } message: {
                Text("This will bookmark all \(viewModel.tabs.count) open tabs.")
            }
            .preferredColorScheme(settings.theme.colorScheme)
    }

    private var mainContent: some View {
        ZStack {
            VStack(spacing: 0) {
                tabBarSection
                if settings.tabBarStyle != .compact {
                    addressBarSection
                }
                contentArea
            }

            if showTabOverview {
                TabOverview(viewModel: viewModel, isPresented: $showTabOverview)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(100)
            }
        }
    }

    @ViewBuilder
    private var tabBarSection: some View {
        if settings.tabBarStyle == .compact {
            CompactTabBar(viewModel: viewModel)
                .overlay(Rectangle().fill(Color("Border")).frame(height: 1), alignment: .bottom)
        } else {
            TabBar(viewModel: viewModel)
                .overlay(Rectangle().fill(Color("Border")).frame(height: 1), alignment: .bottom)
        }
    }

    private var addressBarSection: some View {
        AddressBar(viewModel: viewModel)
            .overlay(Rectangle().fill(Color("Border")).frame(height: 1), alignment: .bottom)
    }

    private var contentArea: some View {
        ZStack {
            ForEach(viewModel.tabs) { tab in
                Group {
                    if tab.isSpecialPage {
                        KoukePageView(url: tab.url, onNavigate: viewModel.navigateFromStartPage, viewModel: viewModel)
                    } else {
                        WebViewContainer(tabId: tab.id, url: tab.url, viewModel: viewModel)
                    }
                }
                .opacity(tab.id == viewModel.activeTabId ? 1 : 0)
                .zIndex(tab.id == viewModel.activeTabId ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("Bg"))
    }

    private var historySheet: some View {
        HistoryView(
            onNavigate: { url in
                viewModel.navigateFromStartPage(to: url)
                showHistory = false
            },
            onDismiss: { showHistory = false }
        )
    }

    private var bookmarksSheet: some View {
        BookmarksView(
            onNavigate: { url in
                viewModel.navigateFromStartPage(to: url)
                showBookmarks = false
            }
        )
        .frame(width: 400, height: 500)
    }

    private func bookmarkAllTabs() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let folderName = "Tabs - \(dateFormatter.string(from: Date()))"

        bookmarkManager.addFolder(name: folderName, parentId: nil)

        if let folder = bookmarkManager.folders.last {
            for tab in viewModel.tabs {
                if !tab.isSpecialPage {
                    bookmarkManager.addBookmark(title: tab.title, url: tab.url, folderId: folder.id)
                }
            }
        }
    }
}

// MARK: - Window Menu Modifiers

private struct WindowFileMenuModifier: ViewModifier {
    let viewModel: BrowserViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .newWindow)) { _ in
                WindowManager.shared.createNewWindow(with: nil, webView: nil, at: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: .closeTab)) { _ in
                if let activeTabId = viewModel.activeTabId {
                    viewModel.closeTab(activeTabId)
                }
            }
    }
}

private struct WindowViewMenuModifier: ViewModifier {
    let viewModel: BrowserViewModel
    @Binding var showTabOverview: Bool
    @Binding var currentZoomLevel: Double

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .reloadPage)) { _ in
                viewModel.reload()
            }
            .onReceive(NotificationCenter.default.publisher(for: .forceReloadPage)) { _ in
                viewModel.getActiveWebView()?.reloadFromOrigin()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in
                handleZoomIn()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in
                handleZoomOut()
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetZoom)) { _ in
                handleResetZoom()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleFullScreen)) { _ in
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showAllTabs)) { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showTabOverview.toggle()
                }
            }
    }

    private func handleZoomIn() {
        guard let webView = viewModel.getActiveWebView() else { return }
        currentZoomLevel = min(currentZoomLevel + 0.1, 3.0)
        webView.pageZoom = currentZoomLevel
    }

    private func handleZoomOut() {
        guard let webView = viewModel.getActiveWebView() else { return }
        currentZoomLevel = max(currentZoomLevel - 0.1, 0.5)
        webView.pageZoom = currentZoomLevel
    }

    private func handleResetZoom() {
        guard let webView = viewModel.getActiveWebView() else { return }
        currentZoomLevel = 1.0
        webView.pageZoom = currentZoomLevel
    }
}

private struct WindowHistoryMenuModifier: ViewModifier {
    let viewModel: BrowserViewModel
    @Binding var showHistory: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .goBack)) { _ in
                viewModel.goBack()
            }
            .onReceive(NotificationCenter.default.publisher(for: .goForward)) { _ in
                viewModel.goForward()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showHistory)) { _ in
                showHistory = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .clearHistory)) { _ in
                HistoryManager.shared.clearHistory()
            }
    }
}

private struct WindowBookmarksMenuModifier: ViewModifier {
    @Binding var showBookmarks: Bool
    @Binding var showBookmarkAllTabsAlert: Bool
    @ObservedObject var settings = BrowserSettings.shared

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .showBookmarks)) { _ in
                // Show sheet if button is hidden OR alwaysUseSheet is enabled
                if !settings.showBookmarksButton || settings.alwaysUseSheetForMenuShortcuts {
                    showBookmarks = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .bookmarkAllTabs)) { _ in
                showBookmarkAllTabsAlert = true
            }
    }
}

private struct WindowDownloadsMenuModifier: ViewModifier {
    @Binding var showDownloads: Bool
    @ObservedObject var settings = BrowserSettings.shared

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .showDownloads)) { _ in
                // Show sheet if button is hidden OR alwaysUseSheet is enabled
                if !settings.showDownloadsButton || settings.alwaysUseSheetForMenuShortcuts {
                    showDownloads = true
                }
            }
    }
}

private struct WindowDeveloperMenuModifier: ViewModifier {
    let viewModel: BrowserViewModel
    let settings: BrowserSettings

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .viewSource)) { _ in
                viewModel.viewSource()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDevTools)) { _ in
                viewModel.openDevTools()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openConsole)) { _ in
                handleOpenConsole()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleJavaScript)) { _ in
                settings.toggleJavaScript()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleImages)) { _ in
                settings.toggleImages()
            }
            .onReceive(NotificationCenter.default.publisher(for: .clearCache)) { _ in
                settings.clearCache()
            }
            .onReceive(NotificationCenter.default.publisher(for: .clearCookies)) { _ in
                settings.clearCookies()
            }
    }

    private func handleOpenConsole() {
        if let webView = viewModel.getActiveWebView() {
            webView.evaluateJavaScript("""
                (function() {
                    var logs = [];
                    var originalLog = console.log;
                    console.log = function() {
                        logs.push(Array.from(arguments).join(' '));
                        originalLog.apply(console, arguments);
                    };
                    return 'Console logging enabled. Check console output.';
                })()
            """, completionHandler: nil)
        }
    }
}

private struct WindowKoukeURLModifier: ViewModifier {
    let viewModel: BrowserViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openKoukeURL)) { notification in
                if let urlString = notification.userInfo?["url"] as? String {
                    viewModel.openKoukeURL(urlString)
                }
            }
    }
}

private struct WindowSettingsModifier: ViewModifier {
    let viewModel: BrowserViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .setCurrentPageAsHomepage)) { _ in
                if let activeTab = viewModel.activeTab, !activeTab.isSpecialPage {
                    BrowserSettings.shared.homepage = activeTab.url
                }
            }
    }
}
