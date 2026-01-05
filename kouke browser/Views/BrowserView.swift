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
    @State private var showTabOverview = false

    var body: some View {
        ZStack {
            // Main browser content
            VStack(spacing: 0) {
                // Tab Bar
                TabBar(viewModel: viewModel)
                    .overlay(
                        Rectangle()
                            .fill(Color("Border"))
                            .frame(height: 1),
                        alignment: .bottom
                    )

                // Address Bar
                AddressBar(viewModel: viewModel)
                    .overlay(
                        Rectangle()
                            .fill(Color("Border"))
                            .frame(height: 1),
                        alignment: .bottom
                    )

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
        .withhostingWindow { window in
            window.backgroundColor = NSColor(named: "TitleBarBg")
            window.isMovableByWindowBackground = true
            // Disable system tab bar (we use our own)
            window.tabbingMode = .disallowed
            // Ensure window can become key
            window.makeKeyAndOrderFront(nil)
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

// Manages traffic light positioning using NotificationCenter
class TrafficLightsPositionManager: NSObject {
    static let shared = TrafficLightsPositionManager()

    private let leadingOffset: CGFloat = 6
    private let topOffset: CGFloat = 6

    private var observedWindows = Set<ObjectIdentifier>()

    func setup(for window: NSWindow) {
        let windowId = ObjectIdentifier(window)
        guard !observedWindows.contains(windowId) else { return }
        observedWindows.insert(windowId)

        // Observe window resize via NotificationCenter
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidExitFullScreen(_:)),
            name: NSWindow.didExitFullScreenNotification,
            object: window
        )

        // Apply initial offset
        applyOffset(to: window)
    }

    @objc private func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        applyOffset(to: window)
    }

    @objc private func windowDidExitFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        applyOffset(to: window)
    }

    private func applyOffset(to window: NSWindow) {
        // Apply offset directly to current positions
        window.standardWindowButton(.closeButton)?.frame.origin.x += leadingOffset
        window.standardWindowButton(.closeButton)?.frame.origin.y -= topOffset

        window.standardWindowButton(.miniaturizeButton)?.frame.origin.x += leadingOffset
        window.standardWindowButton(.miniaturizeButton)?.frame.origin.y -= topOffset

        window.standardWindowButton(.zoomButton)?.frame.origin.x += leadingOffset
        window.standardWindowButton(.zoomButton)?.frame.origin.y -= topOffset
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
