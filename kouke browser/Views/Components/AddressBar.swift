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
    @FocusState private var isAddressFocused: Bool
    @State private var showingAddBookmark = false
    @State private var showingBookmarks = false
    @State private var showingDownloads = false
    @State private var showingSecurityInfo = false

    private var isCurrentPageBookmarked: Bool {
        guard let tab = viewModel.activeTab else { return false }
        return bookmarkManager.isBookmarked(url: tab.url)
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

            // Downloads button (conditional)
            if settings.showDownloadsButton {
                Button(action: { showingDownloads = true }) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 14))
                        .foregroundColor(Color("TextMuted"))
                }
                .buttonStyle(.plain)
                .padding(6)
                .contentShape(Rectangle())
                .help("Show Downloads")
                .popover(isPresented: $showingDownloads, arrowEdge: .bottom) {
                    DownloadsView(onDismiss: { showingDownloads = false })
                }
            }

            // Add to Favorites button (conditional)
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

            // Bookmarks button (conditional)
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
            // Only handle here if button is visible (popover mode)
            if settings.showBookmarksButton {
                showingBookmarks = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDownloads)) { _ in
            // Only handle here if button is visible (popover mode)
            if settings.showDownloadsButton {
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
