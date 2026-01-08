//
//  BrowserView.swift
//  kouke browser
//
//  Main browser interface combining TabBar, AddressBar, and content area.
//

import SwiftUI
import AppKit
import WebKit

struct BrowserView: View {
    @StateObject private var viewModel = BrowserViewModel()
    @ObservedObject private var settings = BrowserSettings.shared
    @ObservedObject private var bookmarkManager = BookmarkManager.shared
    @State private var showTabOverview = false
    @State private var showHistory = false
    @State private var showBookmarks = false
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
            .background(Color("Bg"))
            .ignoresSafeArea()
            .preferredColorScheme(settings.theme.colorScheme)
            .withhostingWindow(theme: settings.theme) { [viewModel, settings] window in
                configureWindow(window, viewModel: viewModel, settings: settings)
            }
            .onChange(of: viewModel.activeTab?.title) { _, newTitle in
                if let title = newTitle {
                    NSApp.keyWindow?.title = title
                }
            }
            .modifier(FileMenuModifier(viewModel: viewModel))
            .modifier(ViewMenuModifier(viewModel: viewModel, showTabOverview: $showTabOverview, currentZoomLevel: $currentZoomLevel))
            .modifier(HistoryMenuModifier(viewModel: viewModel, showHistory: $showHistory))
            .modifier(BookmarksMenuModifier(showBookmarks: $showBookmarks, showBookmarkAllTabsAlert: $showBookmarkAllTabsAlert))
            .modifier(DeveloperMenuModifier(viewModel: viewModel, settings: settings))
            .modifier(KoukeURLModifier(viewModel: viewModel))
            .alert("Bookmark All Tabs", isPresented: $showBookmarkAllTabsAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Bookmark All") {
                    bookmarkAllTabs()
                }
            } message: {
                Text("This will bookmark all \(viewModel.tabs.count) open tabs.")
            }
    }

    // MARK: - View Components

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
                .overlay(
                    Rectangle()
                        .fill(Color("Border"))
                        .frame(height: 1),
                    alignment: .bottom
                )
        } else {
            TabBar(viewModel: viewModel)
                .overlay(
                    Rectangle()
                        .fill(Color("Border"))
                        .frame(height: 1),
                    alignment: .bottom
                )
        }
    }

    private var addressBarSection: some View {
        AddressBar(viewModel: viewModel)
            .overlay(
                Rectangle()
                    .fill(Color("Border"))
                    .frame(height: 1),
                alignment: .bottom
            )
    }

    private var contentArea: some View {
        ZStack {
            ForEach(viewModel.tabs) { tab in
                Group {
                    if tab.isSpecialPage {
                        KoukePageView(
                            url: tab.url,
                            onNavigate: viewModel.navigateFromStartPage
                        )
                    } else {
                        WebViewContainer(
                            tabId: tab.id,
                            url: tab.url,
                            viewModel: viewModel
                        )
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

    // MARK: - Bookmark Methods

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

    // MARK: - Helper Methods

    private func configureWindow(_ window: NSWindow, viewModel: BrowserViewModel, settings: BrowserSettings) {
        updateWindowAppearance(window, theme: settings.theme)

        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.makeKeyAndOrderFront(nil)
        WindowManager.shared.registerViewModel(viewModel, for: window)
        if let activeTab = viewModel.activeTab {
            window.title = activeTab.title
        }
        window.isExcludedFromWindowsMenu = false
        ToolbarTabBarManager.shared.setup(for: window, viewModel: viewModel, settings: settings)
    }

    private func updateWindowAppearance(_ window: NSWindow, theme: AppTheme) {
        window.appearance = NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
        window.backgroundColor = NSColor(named: "TitleBarBg")
        window.invalidateShadow()
    }
}

// MARK: - Menu Modifiers

struct FileMenuModifier: ViewModifier {
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

struct ViewMenuModifier: ViewModifier {
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

struct HistoryMenuModifier: ViewModifier {
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

struct BookmarksMenuModifier: ViewModifier {
    @Binding var showBookmarks: Bool
    @Binding var showBookmarkAllTabsAlert: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .showBookmarks)) { _ in
                showBookmarks = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .bookmarkAllTabs)) { _ in
                showBookmarkAllTabsAlert = true
            }
    }
}

struct DeveloperMenuModifier: ViewModifier {
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

struct KoukeURLModifier: ViewModifier {
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

// MARK: - Window Accessor

struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow) -> Void
    var theme: AppTheme

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                self.callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                self.callback(window)
            }
        }
    }
}

// MARK: - Toolbar Manager

class ToolbarTabBarManager: NSObject {
    static let shared = ToolbarTabBarManager()

    private var configuredWindows = [ObjectIdentifier: TabBarStyle]()
    private var resizeObservers = [ObjectIdentifier: NSObjectProtocol]()

    func setup(for window: NSWindow, viewModel: BrowserViewModel, settings: BrowserSettings) {
        let windowId = ObjectIdentifier(window)
        let currentStyle = settings.tabBarStyle

        if configuredWindows[windowId] == currentStyle { return }
        configuredWindows[windowId] = currentStyle

        if let observer = resizeObservers[windowId] {
            NotificationCenter.default.removeObserver(observer)
            resizeObservers.removeValue(forKey: windowId)
        }

        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        let toolbar = NSToolbar(identifier: "MainToolbar")
        window.toolbar = toolbar

        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unifiedCompact
        }

        repositionTrafficLights(in: window, style: currentStyle)

        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            self?.repositionTrafficLights(in: window, style: currentStyle)
        }
        resizeObservers[windowId] = observer
    }

    private func repositionTrafficLights(in window: NSWindow, style: TabBarStyle) {
        // Standard behavior - toolbar style handles positioning
    }
}

extension View {
    func withhostingWindow(theme: AppTheme, _ callback: @escaping (NSWindow) -> Void) -> some View {
        self.background(WindowAccessor(callback: callback, theme: theme))
    }
}

#Preview {
    BrowserView()
        .frame(width: 1024, height: 768)
}
