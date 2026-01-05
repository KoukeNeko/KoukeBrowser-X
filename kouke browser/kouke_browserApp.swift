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
        .windowToolbarStyle(.unified)
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    NotificationCenter.default.post(name: .newTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("New Window") {
                    NotificationCenter.default.post(name: .newWindow, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button("Close Tab") {
                    NotificationCenter.default.post(name: .closeTab, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            // Replace system View menu toolbar items
            CommandGroup(replacing: .toolbar) {
                Button("Reload Page") {
                    NotificationCenter.default.post(name: .reloadPage, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Force Reload") {
                    NotificationCenter.default.post(name: .forceReloadPage, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("Zoom In") {
                    NotificationCenter.default.post(name: .zoomIn, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .zoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    NotificationCenter.default.post(name: .resetZoom, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("Toggle Full Screen") {
                    NotificationCenter.default.post(name: .toggleFullScreen, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .control])

                Divider()

                Button("Show All Tabs") {
                    NotificationCenter.default.post(name: .showAllTabs, object: nil)
                }
                .keyboardShortcut("\\", modifiers: [.command, .shift])
            }

            // History menu
            CommandMenu("History") {
                Button("Back") {
                    NotificationCenter.default.post(name: .goBack, object: nil)
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Forward") {
                    NotificationCenter.default.post(name: .goForward, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)

                Divider()

                Button("Show All History") {
                    NotificationCenter.default.post(name: .showHistory, object: nil)
                }
                .keyboardShortcut("y", modifiers: .command)

                Button("Clear History...") {
                    NotificationCenter.default.post(name: .clearHistory, object: nil)
                }
            }

            // Bookmarks menu
            CommandMenu("Bookmarks") {
                Button("Add Bookmark...") {
                    NotificationCenter.default.post(name: .addBookmark, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Show All Bookmarks") {
                    NotificationCenter.default.post(name: .showBookmarks, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .option])

                Divider()

                Button("Bookmark This Tab") {
                    NotificationCenter.default.post(name: .bookmarkTab, object: nil)
                }

                Button("Bookmark All Tabs...") {
                    NotificationCenter.default.post(name: .bookmarkAllTabs, object: nil)
                }
            }

            // Developer menu
            CommandMenu("Developer") {
                Button("View Source") {
                    NotificationCenter.default.post(name: .viewSource, object: nil)
                }
                .keyboardShortcut("u", modifiers: .command)

                Button("Developer Tools") {
                    NotificationCenter.default.post(name: .openDevTools, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Button("JavaScript Console") {
                    NotificationCenter.default.post(name: .openConsole, object: nil)
                }
                .keyboardShortcut("j", modifiers: [.command, .option])

                Divider()

                Button("Disable JavaScript") {
                    NotificationCenter.default.post(name: .toggleJavaScript, object: nil)
                }

                Button("Disable Images") {
                    NotificationCenter.default.post(name: .toggleImages, object: nil)
                }

                Divider()

                Button("Clear Cache") {
                    NotificationCenter.default.post(name: .clearCache, object: nil)
                }

                Button("Clear Cookies") {
                    NotificationCenter.default.post(name: .clearCookies, object: nil)
                }
            }

            // Settings command
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
