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
    
    var body: some View {
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
                // Show active tab content
                if let activeTab = viewModel.activeTab {
                    if activeTab.url == "about:blank" {
                        StartPage(onNavigate: viewModel.navigateFromStartPage)
                    } else if activeTab.url == "about:settings" {
                        SettingsView()
                    } else {
                        WebViewContainer(
                            tabId: activeTab.id,
                            url: activeTab.url,
                            viewModel: viewModel
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color("Bg"))
        }
        .background(Color("Bg"))
        .preferredColorScheme(BrowserSettings.shared.theme.colorScheme)
        .withhostingWindow { window in
            // Make title bar transparent and content extend to top
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = NSColor(named: "TitleBarBg")
        }
    }
}

// Helper to access NSWindow
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

extension View {
    func withhostingWindow(_ callback: @escaping (NSWindow) -> Void) -> some View {
        self.background(WindowAccessor(callback: callback))
    }
}

#Preview {
    BrowserView()
        .frame(width: 1024, height: 768)
}
