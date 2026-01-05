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

                // Address Bar (only show if not compact, since compact has URL display)
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
        .withhostingWindow { [viewModel] window in
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
                // Setup traffic lights position manager
                TrafficLightsPositionManager.shared.setup(for: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// Manages traffic light positioning
class TrafficLightsPositionManager: NSObject {
    static let shared = TrafficLightsPositionManager()

    private let xOffset: CGFloat = 7
    private let yOffset: CGFloat = 3  // Distance from top

    private var observedWindows = Set<ObjectIdentifier>()
    private var displayLink: CVDisplayLink?

    func setup(for window: NSWindow) {
        let windowId = ObjectIdentifier(window)
        guard !observedWindows.contains(windowId) else { return }
        observedWindows.insert(windowId)

        // Make title bar transparent so our SwiftUI view shows through
        window.titlebarAppearsTransparent = true

        // Initial position
        positionTrafficLights(in: window)

        // Use KVO to watch for layout changes on the button's superview
        if let closeButton = window.standardWindowButton(.closeButton),
           let titleBarView = closeButton.superview {
            titleBarView.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(titleBarFrameChanged(_:)),
                name: NSView.frameDidChangeNotification,
                object: titleBarView
            )
        }

        // Also observe window state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidUpdate(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidUpdate(_:)),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidUpdate(_:)),
            name: NSWindow.didExitFullScreenNotification,
            object: window
        )
    }

    @objc private func titleBarFrameChanged(_ notification: Notification) {
        guard let titleBarView = notification.object as? NSView,
              let window = titleBarView.window else { return }
        positionTrafficLights(in: window)
    }

    @objc private func windowDidUpdate(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        // Delay slightly to let system finish its layout
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            self.positionTrafficLights(in: window)
        }
    }

    private func positionTrafficLights(in window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton),
              let miniaturizeButton = window.standardWindowButton(.miniaturizeButton),
              let zoomButton = window.standardWindowButton(.zoomButton),
              let titleBarView = closeButton.superview else { return }

        let titleBarHeight = titleBarView.frame.height
        let buttonHeight = closeButton.frame.height

        // Calculate Y to vertically center in title bar area (which should be ~40px for our tab bar)
        // The title bar view might be taller due to toolbar, so we position from top
        let y = titleBarHeight - buttonHeight - yOffset

        closeButton.setFrameOrigin(NSPoint(x: xOffset, y: y))
        miniaturizeButton.setFrameOrigin(NSPoint(x: xOffset + 20, y: y))
        zoomButton.setFrameOrigin(NSPoint(x: xOffset + 40, y: y))
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
