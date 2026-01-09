//
//  AddressBar.swift
//  kouke browser
//
//  Navigation controls and URL input field.
//

import SwiftUI

struct AddressBar: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var bookmarkManager = BookmarkManager.shared
    @ObservedObject var settings = BrowserSettings.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @FocusState private var isAddressFocused: Bool
    @State private var showingAddBookmark = false
    @State private var showingBookmarks = false
    @State private var showingDownloads = false
    @State private var showingSecurityInfo = false

    /// Calculate overall download progress (0.0 to 1.0)
    private var downloadProgress: Double? {
        let activeItems = downloadManager.downloadItems.filter { $0.status == .downloading }
        guard !activeItems.isEmpty else { return nil }

        var totalDownloaded: Int64 = 0
        var totalSize: Int64 = 0

        for item in activeItems {
            totalDownloaded += item.downloadedSize
            if let size = item.fileSize, size > 0 {
                totalSize += size
            }
        }

        guard totalSize > 0 else { return nil }
        return Double(totalDownloaded) / Double(totalSize)
    }

    private var hasActiveDownloads: Bool {
        downloadManager.downloadItems.contains { $0.status == .downloading }
    }

    private var isCurrentPageBookmarked: Bool {
        guard let tab = viewModel.activeTab else { return false }
        return bookmarkManager.isBookmarked(url: tab.url)
    }

    private var isReaderModeAvailable: Bool {
        viewModel.activeTab?.readerModeAvailable == true
    }

    private var isReaderModeActive: Bool {
        viewModel.activeTab?.isReaderMode == true
    }

    private var currentSecurityInfo: SecurityInfo {
        viewModel.activeTab?.securityInfo ?? SecurityInfo.fromURL(viewModel.activeTab?.url ?? "")
    }

    private var securityIcon: String {
        currentSecurityInfo.level.icon
    }

    private var securityIconColor: Color {
        switch currentSecurityInfo.level {
        case .insecure:
            return .red
        case .mixed:
            return .orange
        case .local, .secure, .unknown:
            return Color("TextMuted").opacity(0.7)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Navigation controls
            HStack(spacing: 4) {
                NavButton(
                    icon: "chevron.left",
                    action: viewModel.goBack,
                    isEnabled: viewModel.activeTab?.canGoBack == true
                )
                NavButton(
                    icon: "chevron.right",
                    action: viewModel.goForward,
                    isEnabled: viewModel.activeTab?.canGoForward == true
                )
                NavButton(icon: "arrow.clockwise", action: viewModel.reload)
            }

            // Address input container (no border, like Rust version)
            HStack(spacing: 8) {
                // Security lock icon (clickable)
                Button(action: { showingSecurityInfo = true }) {
                    Image(systemName: securityIcon)
                        .font(.system(size: 11))
                        .foregroundColor(securityIconColor)
                }
                .buttonStyle(.plain)
                .help("View Security Info")
                .popover(isPresented: $showingSecurityInfo, arrowEdge: .bottom) {
                    if let tab = viewModel.activeTab {
                        SecurityDetailPopover(securityInfo: tab.securityInfo, url: tab.url)
                    }
                }

                // URL text field
                TextField("Search or enter website", text: $viewModel.inputURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color("TextMuted"))
                    .focused($isAddressFocused)
                    .onSubmit {
                        viewModel.navigate()
                    }
            }

            // Toolbar buttons in custom order
            ForEach(settings.toolbarButtonOrder) { button in
                toolbarButton(for: button)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 40)
        .background(Color("Bg"))

        .onReceive(NotificationCenter.default.publisher(for: .addBookmark)) { _ in
            if let tab = viewModel.activeTab, !tab.isSpecialPage {
                if isCurrentPageBookmarked {
                    // Already bookmarked, show edit dialog
                } else {
                    showingAddBookmark = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showBookmarks)) { _ in
            // Only handle here if button is visible AND not using sheet mode
            if settings.showBookmarksButton && !settings.alwaysUseSheetForMenuShortcuts {
                showingBookmarks = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDownloads)) { _ in
            // Only handle here if button is visible AND not using sheet mode
            if settings.showDownloadsButton && !settings.alwaysUseSheetForMenuShortcuts {
                showingDownloads = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarkTab)) { _ in
            toggleBookmark()
        }
    }

    private func toggleBookmark() {
        guard let tab = viewModel.activeTab, !tab.isSpecialPage else { return }

        if isCurrentPageBookmarked {
             bookmarkManager.toggleBookmark(title: tab.title, url: tab.url)
        } else {
             showingAddBookmark = true
        }
    }

    private func toggleReaderMode() {
        guard let tabId = viewModel.activeTabId,
              let webView = viewModel.getActiveWebView() else { return }

        if isReaderModeActive {
            // Exit reader mode
            viewModel.setReaderMode(false, for: tabId)
            viewModel.readerArticle = nil
        } else {
            // Enter reader mode - extract article
            ReaderModeService.shared.extractArticle(webView: webView) { article in
                if let article = article {
                    viewModel.readerArticle = article
                    viewModel.setReaderMode(true, for: tabId)
                }
            }
        }
    }

    @ViewBuilder
    private func toolbarButton(for button: ToolbarButton) -> some View {
        switch button {
        case .readerMode:
            // Reader Mode button is shown only when the page supports it (automatic)
            if isReaderModeAvailable {
                Button(action: toggleReaderMode) {
                    Image(systemName: isReaderModeActive ? "doc.plaintext.fill" : "doc.plaintext")
                        .font(.system(size: 14))
                        .foregroundColor(isReaderModeActive ? Color.accentColor : Color("TextMuted"))
                }
                .buttonStyle(.plain)
                .padding(6)
                .contentShape(Rectangle())
                .help(isReaderModeActive ? "Exit Reader Mode" : "Enter Reader Mode")
            }

        case .addToFavorites:
            if settings.showAddToFavoritesButton {
                Button(action: toggleBookmark) {
                    Image(systemName: isCurrentPageBookmarked ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundColor(isCurrentPageBookmarked ? .yellow : Color("TextMuted"))
                }
                .buttonStyle(.plain)
                .padding(6)
                .contentShape(Rectangle())
                .help(isCurrentPageBookmarked ? "Remove Bookmark" : "Add Bookmark")
                .popover(isPresented: $showingAddBookmark, arrowEdge: .bottom) {
                    if let tab = viewModel.activeTab {
                        AddBookmarkPopover(title: tab.title, url: tab.url) { title, url, folderId in
                            bookmarkManager.addBookmark(title: title, url: url, folderId: folderId)
                        }
                    }
                }
            }

        case .downloads:
            if settings.showDownloadsButton {
                Button(action: { showingDownloads = true }) {
                    ZStack {
                        if let progress = downloadProgress {
                            Circle()
                                .stroke(Color("TextMuted").opacity(0.2), lineWidth: 2)
                                .frame(width: 18, height: 18)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .frame(width: 18, height: 18)
                                .rotationEffect(.degrees(-90))

                            Image(systemName: "arrow.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Color.accentColor)
                        } else {
                            Image(systemName: hasActiveDownloads ? "arrow.down.circle.fill" : "arrow.down.circle")
                                .font(.system(size: 14))
                                .foregroundColor(hasActiveDownloads ? Color.accentColor : Color("TextMuted"))
                        }
                    }
                    .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .padding(6)
                .contentShape(Rectangle())
                .help("Show Downloads")
                .popover(isPresented: $showingDownloads, arrowEdge: .bottom) {
                    DownloadsView(onDismiss: { showingDownloads = false })
                }
            }

        case .bookmarks:
            if settings.showBookmarksButton {
                Button(action: { showingBookmarks = true }) {
                    Image(systemName: "book")
                        .font(.system(size: 14))
                        .foregroundColor(Color("TextMuted"))
                }
                .buttonStyle(.plain)
                .padding(6)
                .contentShape(Rectangle())
                .help("Show Bookmarks")
                .popover(isPresented: $showingBookmarks, arrowEdge: .bottom) {
                    BookmarksView(onNavigate: { url in
                        viewModel.inputURL = url
                        viewModel.navigate()
                    })
                }
            }
        }
    }
}

struct NavButton: View {
    let icon: String
    let action: () -> Void
    var isEnabled: Bool = true

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(isEnabled ? Color("TextMuted") : Color("TextMuted").opacity(0.4))
                .frame(width: 28, height: 28)
                .background(isHovering && isEnabled ? Color("AccentHover") : Color.clear)
                .cornerRadius(2) // Minimal rounding
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

#Preview {
    AddressBar(viewModel: BrowserViewModel())
        .frame(width: 600)
}
