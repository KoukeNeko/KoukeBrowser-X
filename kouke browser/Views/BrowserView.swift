//
//  BrowserView.swift
//  kouke browser
//
//  Main browser interface combining TabBar, AddressBar, and content area.
//

import SwiftUI
import AppKit

struct BrowserView: View {
    @StateObject private var viewModel = BrowserViewModel()
    @ObservedObject private var settings = BrowserSettings.shared
    @State private var showTabOverview = false

    var body: some View {
        ZStack {
            // Main browser content
            VStack(spacing: 0) {
                // Tab Bar - in the titlebar area (overlay style)
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

                // Address Bar (only show if not compact, since compact has URL display in toolbar)
                if settings.tabBarStyle != .compact {
                    AddressBar(viewModel: viewModel)
                        .overlay(
                            Rectangle()
                                .fill(Color("Border"))
                                .frame(height: 1),
                            alignment: .bottom
                        )
                }

                // Content Area
                ZStack {
                    // Keep all WebViews alive, show/hide based on active tab
                    ForEach(viewModel.tabs) { tab in
                        Group {
                            if tab.url == "about:blank" {
                                StartPage(onNavigate: viewModel.navigateFromStartPage)
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

            // Tab Overview overlay
            if showTabOverview {
                TabOverview(viewModel: viewModel, isPresented: $showTabOverview)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(100)
            }
        }
        .background(Color("Bg"))
        .ignoresSafeArea()
        .preferredColorScheme(BrowserSettings.shared.theme.colorScheme)
        .withhostingWindow { [viewModel, settings] window in
            window.backgroundColor = NSColor(named: "TitleBarBg")
            window.isMovableByWindowBackground = true
            // Disable system tab bar (we use our own)
            window.tabbingMode = .disallowed
            // Ensure window can become key
            window.makeKeyAndOrderFront(nil)
            // Register viewModel with WindowManager for cross-window tab transfers
            WindowManager.shared.registerViewModel(viewModel, for: window)
            // Set initial window title for Dock menu
            if let activeTab = viewModel.activeTab {
                window.title = activeTab.title
            }
            // Make window appear in Window menu and Dock
            window.isExcludedFromWindowsMenu = false

            // Setup toolbar with tab bar
            ToolbarTabBarManager.shared.setup(for: window, viewModel: viewModel, settings: settings)
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
