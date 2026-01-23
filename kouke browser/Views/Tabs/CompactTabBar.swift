//
//  CompactTabBar.swift
//  kouke browser
//
//  Compact tab bar similar to Safari's design - single row with smaller tabs and integrated address bar.
//

import SwiftUI
import AppKit

struct CompactTabBar: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject private var settings = BrowserSettings.shared
    @ObservedObject private var bookmarkManager = BookmarkManager.shared
    @State private var draggedTabId: UUID?
    @State private var showingBookmarks = false
    @State private var isDropTargeted: Bool = false

    private var isCurrentPageBookmarked: Bool {
        guard let tab = viewModel.activeTab else { return false }
        return bookmarkManager.isBookmarked(url: tab.url)
    }

    // Filter tabs based on settings - show all or only active tab
    private var visibleTabs: [Tab] {
        if settings.showTabsInCompactMode {
            return viewModel.tabs
        } else {
            // Only show active tab
            return viewModel.tabs.filter { $0.id == viewModel.activeTabId }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                #if os(macOS)
                // Keep space for traffic lights - 80px seems standard for Big Sur+
                Color.clear
                    .frame(width: 80, height: 40)

                // Navigation buttons (back/forward) with history context menu
                HStack(spacing: 2) {
                    NavButton(
                        icon: "chevron.left",
                        action: { viewModel.goBack() },
                        isEnabled: viewModel.activeTab?.canGoBack == true,
                        menuItems: viewModel.getBackHistoryList(),
                        onMenuItemSelected: { index in
                            viewModel.goBackTo(index: index)
                        }
                    )

                    NavButton(
                        icon: "chevron.right",
                        action: { viewModel.goForward() },
                        isEnabled: viewModel.activeTab?.canGoForward == true,
                        menuItems: viewModel.getForwardHistoryList(),
                        onMenuItemSelected: { index in
                            viewModel.goForwardTo(index: index)
                        }
                    )
                }
                .frame(width: 60)
                #endif

                // Calculate available width for tabs (Total - TrafficLights - NavButtons - RightButtons)
                let availableWidth = geometry.size.width - 80 - 60 - 140
                let tabWidth = calculateTabWidth(totalAvailableWidth: availableWidth)

                let isDark = settings.theme == .dark
                let _ = NSLog("🟡 CompactTabBar body - isDark: %@", isDark ? "true" : "false")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(visibleTabs) { tab in
                            CompactDraggableTabView(
                                tab: tab,
                                isActive: tab.id == viewModel.activeTabId,
                                showActiveStyle: settings.showTabsInCompactMode,
                                canDrag: settings.showTabsInCompactMode,
                                onSelect: { viewModel.switchToTab(tab.id) },
                                onClose: { viewModel.closeTab(tab.id) },
                                canClose: true,
                                onReorder: { draggedId, targetId, after in
                                    if after {
                                        viewModel.moveTabAfter(draggedId: draggedId, destinationId: targetId)
                                    } else {
                                        viewModel.moveTabBefore(draggedId: draggedId, destinationId: targetId)
                                    }
                                },
                                onReceiveTab: { transferData, destinationId, after in
                                    receiveTabFromOtherWindow(transferData: transferData, destinationId: destinationId, insertAfter: after)
                                },
                                onDetach: { tabId, point in
                                    detachTabToNewWindow(tabId: tabId, at: point)
                                },
                                onDragStarted: { id in draggedTabId = id },
                                onDragEnded: { draggedTabId = nil },
                                inputURL: viewModel.inputURL,
                                onInputURLChange: { url in viewModel.inputURL = url },
                                onNavigate: { viewModel.navigate() },
                                onSwitchTab: { tabId in viewModel.switchToTab(tabId) },
                                allTabs: viewModel.tabs,
                                viewModel: viewModel,
                                isDarkTheme: isDark
                            )
                            .frame(width: tabWidth)
                            .id("\(tab.id)-\(isDark)")  // Force view recreation on theme change
                        }

                    }
                }
                .frame(width: max(0, availableWidth)) // Ensure non-negative width
                .background(
                    // Drop zone as background - doesn't affect layout
                    TabDropZoneView(
                        isDropTargeted: $isDropTargeted,
                        onReceiveTab: { transferData in
                            receiveTabAtEnd(transferData: transferData)
                        }
                    )
                )

                // Right side buttons
                HStack(spacing: 4) {
                    // Bookmark button
                    Button(action: toggleBookmark) {
                        Image(systemName: isCurrentPageBookmarked ? "star.fill" : "star")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isCurrentPageBookmarked ? .yellow : Color("TextMuted"))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help(isCurrentPageBookmarked ? "Remove Bookmark" : "Add Bookmark")
                    .popover(isPresented: $showingAddBookmark, arrowEdge: .bottom) {
                        if let tab = viewModel.activeTab {
                            AddBookmarkPopover(title: tab.title, url: tab.url) { title, url, folderId in
                                bookmarkManager.addBookmark(title: title, url: url, folderId: folderId)
                            }
                        }
                    }

                    // Show bookmarks button
                    Button(action: { showingBookmarks = true }) {
                        Image(systemName: "book")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color("TextMuted"))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Show Bookmarks")
                    .popover(isPresented: $showingBookmarks, arrowEdge: .bottom) {
                        BookmarksView(onNavigate: { url in
                            viewModel.inputURL = url
                            viewModel.navigate()
                        })
                    }

                    Button(action: { viewModel.addTab() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color("TextMuted"))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)

                    // Tab list menu
                    Menu {
                        ForEach(viewModel.tabs) { tab in
                            Button(action: { viewModel.switchToTab(tab.id) }) {
                                HStack {
                                    if tab.id == viewModel.activeTabId {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(tab.title.isEmpty ? "New Tab" : tab.title)
                                        .lineLimit(1)
                                }
                            }
                        }

                        Divider()

                        Button(action: { viewModel.addTab() }) {
                            Label("New Tab", systemImage: "plus")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color("TextMuted"))
                            .frame(width: 28, height: 28)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }
                .frame(width: 140)
                .padding(.trailing, 8)
            }
        }
        .frame(height: 40)
        .background(Color("TitleBarBg"))

        .zIndex(100) // Ensure it sits on top if used in a ZStack
    }

    private func urlDisplayText(_ url: String) -> String {
        guard url != "kouke:blank",
              let urlObj = URL(string: url),
              let host = urlObj.host else {
            return ""
        }
        return host
    }

    private func detachTabToNewWindow(tabId: UUID, at screenPoint: NSPoint) {
        // Allow detaching last tab when creating a new window (moves the window)
        guard let result = viewModel.detachTab(tabId, allowLastTab: true) else { return }
        WindowManager.shared.createNewWindow(with: result.tab, webView: result.webView, at: Optional(screenPoint))
    }

    private func receiveTabFromOtherWindow(transferData: TabTransferData, destinationId: UUID, insertAfter: Bool) {
        guard let tabId = UUID(uuidString: transferData.tabId) else { return }

        // Check if tab is already in this view model (same window drop)
        if viewModel.tabs.contains(where: { $0.id == tabId }) {
            NSLog("📥 CompactTabBar: Reordering tab within same viewModel (destination: \(destinationId))")
            if insertAfter {
                viewModel.moveTabAfter(draggedId: tabId, destinationId: destinationId)
            } else {
                viewModel.moveTabBefore(draggedId: tabId, destinationId: destinationId)
            }
            return
        }

        // Use first-principles transfer: add to destination BEFORE removing from source
        NSLog("📥 CompactTabBar: Transferring tab from window #\(transferData.sourceWindowId) using first-principles pattern")
        let position: WindowManager.TabInsertPosition = insertAfter ? .after(destinationId) : .before(destinationId)
        WindowManager.shared.transferTab(
            from: transferData.sourceWindowId,
            tabId: tabId,
            to: viewModel,
            position: position
        )
    }

    private func receiveTabAtEnd(transferData: TabTransferData) {
        guard let tabId = UUID(uuidString: transferData.tabId) else { return }

        // Check if tab is already in this view model (same window drop)
        if viewModel.tabs.contains(where: { $0.id == tabId }) {
            NSLog("📥 CompactTabBar: Moving tab within same viewModel to end")
            viewModel.moveTab(withID: tabId, to: viewModel.tabs.count)
            return
        }

        // Use first-principles transfer: add to destination BEFORE removing from source
        NSLog("📥 CompactTabBar: Transferring tab from window #\(transferData.sourceWindowId) to end using first-principles pattern")
        WindowManager.shared.transferTab(
            from: transferData.sourceWindowId,
            tabId: tabId,
            to: viewModel,
            position: .atEnd
        )
    }

    private func calculateTabWidth(totalAvailableWidth: CGFloat) -> CGFloat {
        let count = CGFloat(visibleTabs.count)
        guard count > 0 else { return 150 }

        let minWidth: CGFloat = 100 // Minimum width before scrolling starts

        // Spacing is 0 now
        let availableForTabs = totalAvailableWidth
        let idealWidth = availableForTabs / count

        return max(minWidth, idealWidth)
    }

    @State private var showingAddBookmark = false

    private func toggleBookmark() {
        guard let tab = viewModel.activeTab, !tab.isSpecialPage else { return }

        if isCurrentPageBookmarked {
            bookmarkManager.toggleBookmark(title: tab.title, url: tab.url)
        } else {
            showingAddBookmark = true
        }
    }
}

#Preview {
    CompactTabBar(viewModel: BrowserViewModel())
        .frame(width: 800)
}
