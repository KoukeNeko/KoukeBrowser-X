//
//  kouke_browserApp.swift
//  kouke browser
//
//  Created by doeshing on 2026/1/5.
//

import SwiftUI

@main
struct kouke_browserApp: App {
    @StateObject private var viewModel = BrowserViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(BrowserSettings.shared.theme.colorScheme)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    NotificationCenter.default.post(name: .newTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
            }
            
            // Custom settings command
            CommandGroup(after: .appSettings) {
                Button("Settings...") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        #endif
    }
}
