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
    @State private var showTabOverview = false
    @State private var showHistory = false

    var body: some View {
        mainContent
            .sheet(isPresented: $showHistory) {
                historySheet
            }
            .background(Color("Bg"))
            .ignoresSafeArea()
            .preferredColorScheme(settings.theme.colorScheme)
            .withhostingWindow { [viewModel, settings] window in
                configureWindow(window, viewModel: viewModel, settings: settings)
            }
            .onChange(of: viewModel.activeTab?.title) { _, newTitle in
                if let title = newTitle {
                    NSApp.keyWindow?.title = title
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showAllTabs)) { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showTabOverview.toggle()
                }
            }
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
            .onReceive(NotificationCenter.default.publisher(for: .showHistory)) { _ in
                showHistory = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .clearHistory)) { _ in
                HistoryManager.shared.clearHistory()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openKoukeURL)) { notification in
                if let urlString = notification.userInfo?["url"] as? String {
                    viewModel.openKoukeURL(urlString)
                }
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

    // MARK: - Helper Methods

    private func configureWindow(_ window: NSWindow, viewModel: BrowserViewModel, settings: BrowserSettings) {
        window.backgroundColor = NSColor(named: "TitleBarBg")
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

// Helper to access NSWindow and observe changes
struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                self.callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// Manages toolbar with overlay style and traffic light positioning
class ToolbarTabBarManager: NSObject {
    static let shared = ToolbarTabBarManager()

    private var configuredWindows = [ObjectIdentifier: TabBarStyle]()
    private var resizeObservers = [ObjectIdentifier: NSObjectProtocol]()

    func setup(for window: NSWindow, viewModel: BrowserViewModel, settings: BrowserSettings) {
        let windowId = ObjectIdentifier(window)
        let currentStyle = settings.tabBarStyle

        // Skip if already configured with the same style
        if configuredWindows[windowId] == currentStyle { return }
        configuredWindows[windowId] = currentStyle

        // Remove old resize observer if exists
        if let observer = resizeObservers[windowId] {
            NotificationCenter.default.removeObserver(observer)
            resizeObservers.removeValue(forKey: windowId)
        }

        // Enable full size content view - content extends under titlebar
        window.styleMask.insert(.fullSizeContentView)

        // Make title bar transparent so our content shows through
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        // Always add toolbar - it controls traffic light positioning
        let toolbar = NSToolbar(identifier: "MainToolbar")
        window.toolbar = toolbar

        if #available(macOS 11.0, *) {
            // unifiedCompact centers traffic lights in the toolbar area
            window.toolbarStyle = .unifiedCompact
        }

        // Position traffic lights
        repositionTrafficLights(in: window, style: currentStyle)

        // Listen for resize to maintain traffic light position
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
        // Auto Layout prevents moving standard buttons - they snap back
        // Instead, we just ensure the toolbar style is correct
        // The actual "custom positioning" would require hiding system buttons
        // and drawing custom ones, which is complex and loses native behavior

        // For now, keep the standard behavior - the toolbar style should handle it
    }
}

extension View {
    func withhostingWindow(_ callback: @escaping (NSWindow) -> Void) -> some View {
        self.background(WindowAccessor(callback: callback))
    }
}

#Preview {
    BrowserView()
        .frame(width: 1024, height: 768)
}
