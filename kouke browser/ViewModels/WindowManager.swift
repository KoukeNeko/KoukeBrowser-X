//
//  WindowManager.swift
//  kouke browser
//
//  Manages browser windows, including creating new windows from detached tabs.
//

import Foundation
import SwiftUI
import AppKit

@MainActor
class WindowManager {
    static let shared = WindowManager()

    private var windowViewModels: [Int: BrowserViewModel] = [:]  // windowNumber -> viewModel
    private var windows: [NSWindow] = []

    private init() {}

    /// Register a view model for a window (called from BrowserView)
    func registerViewModel(_ viewModel: BrowserViewModel, for window: NSWindow) {
        windowViewModels[window.windowNumber] = viewModel
    }

    /// Remove tab from a specific window and return it
    func removeTabFromWindow(windowNumber: Int, tabId: UUID) -> Tab? {
        guard let viewModel = windowViewModels[windowNumber] else { return nil }
        return viewModel.detachTab(tabId)
    }

    /// Create a new browser window with a detached tab
    func createNewWindow(with tab: Tab, at screenPoint: NSPoint) {
        // Create a new view model with the detached tab
        let viewModel = BrowserViewModel(initialTab: tab)

        // Create the browser view
        let browserView = BrowserViewForWindow(viewModel: viewModel)
            .preferredColorScheme(BrowserSettings.shared.theme.colorScheme)

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
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let closedWindow = notification.object as? NSWindow else { return }
            Task { @MainActor [weak self] in
                self?.windows.removeAll { $0 == closedWindow }
                self?.windowViewModels.removeValue(forKey: closedWindow.windowNumber)
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
    @State private var showTabOverview = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TabBar(viewModel: viewModel)
                    .overlay(
                        Rectangle()
                            .fill(Color("Border"))
                            .frame(height: 1),
                        alignment: .bottom
                    )

                AddressBar(viewModel: viewModel)
                    .overlay(
                        Rectangle()
                            .fill(Color("Border"))
                            .frame(height: 1),
                        alignment: .bottom
                    )

                ZStack {
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

            if showTabOverview {
                TabOverview(viewModel: viewModel, isPresented: $showTabOverview)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(100)
            }
        }
        .background(Color("Bg"))
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: .showAllTabs)) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showTabOverview.toggle()
            }
        }
    }
}
