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
            Task { @MainActor in
                self?.saveAllSessions()
            }
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
        windowViewModels[window.windowNumber] = viewModel
    }

    /// Remove tab from a specific window and return it along with WebView
    func removeTabFromWindow(windowNumber: Int, tabId: UUID) -> (tab: Tab, webView: WKWebView?)? {
        guard let viewModel = windowViewModels[windowNumber] else { return nil }
        return viewModel.detachTab(tabId)
    }

    /// Create a new browser window with a detached tab
    func createNewWindow(with tab: Tab, webView: WKWebView? = nil, at screenPoint: NSPoint) {
        // Create a new view model with the detached tab and its WebView
        let viewModel = BrowserViewModel(initialTab: tab, initialWebView: webView)

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
        window.title = tab.title

        // Make window appear in Window menu and Dock
        window.isExcludedFromWindowsMenu = false

        // Position window at drop location
        let windowOrigin = NSPoint(
            x: screenPoint.x - 512,  // Center horizontally
            y: screenPoint.y - 50    // Position slightly below cursor
        )
        window.setFrameOrigin(windowOrigin)

        // Set content view
        window.contentView = NSHostingView(rootView: browserView)

        // Configure traffic lights
        configureTrafficLights(for: window)

        // Show the window
        window.makeKeyAndOrderFront(nil)

        // Keep reference and register viewModel
        windows.append(window)
        windowViewModels[window.windowNumber] = viewModel

        // Clean up closed windows
        // Capture windowNumber before the window is deallocated
        let windowNumber = window.windowNumber
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let closedWindow = notification.object as? NSWindow else { return }
            Task { @MainActor [weak self] in
                self?.windows.removeAll { $0 == closedWindow }
                self?.windowViewModels.removeValue(forKey: windowNumber)
            }
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
    @State private var showTabOverview = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Tab Bar - switch based on setting
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

                // Address Bar (only show if not compact)
                if settings.tabBarStyle != .compact {
                    AddressBar(viewModel: viewModel)
                        .overlay(
                            Rectangle()
                                .fill(Color("Border"))
                                .frame(height: 1),
                            alignment: .bottom
                        )
                }

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

            if showTabOverview {
                TabOverview(viewModel: viewModel, isPresented: $showTabOverview)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(100)
            }
        }
        .background(Color("Bg"))
        .ignoresSafeArea()
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
        .preferredColorScheme(settings.theme.colorScheme)
    }
}
