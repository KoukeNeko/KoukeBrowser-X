//
//  AddressBar.swift
//  kouke browser
//
//  Navigation controls and URL input field.
//

import SwiftUI
import Combine

struct AddressBar: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var bookmarkManager = BookmarkManager.shared
    @ObservedObject var settings = BrowserSettings.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var pipManager = PIPManager.shared
    @FocusState private var isAddressFocused: Bool
    @State private var showingAddBookmark = false
    @State private var showingBookmarks = false
    @State private var showingDownloads = false
    @State private var showingSecurityInfo = false
    @State private var hasPlayingVideo = false
    @State private var showingDropdown = false

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
        HStack(spacing: 0) { // URL 區域已有 .padding(.horizontal, 12) 作為間距
            // Navigation controls
            HStack(spacing: 4) {
                // Back button with history context menu
                NavButton(
                    icon: "chevron.left",
                    action: viewModel.goBack,
                    isEnabled: viewModel.activeTab?.canGoBack == true,
                    menuItems: viewModel.getBackHistoryList(),
                    onMenuItemSelected: { index in
                        viewModel.goBackTo(index: index)
                    }
                )

                // Forward button with history context menu
                NavButton(
                    icon: "chevron.right",
                    action: viewModel.goForward,
                    isEnabled: viewModel.activeTab?.canGoForward == true,
                    menuItems: viewModel.getForwardHistoryList(),
                    onMenuItemSelected: { index in
                        viewModel.goForwardTo(index: index)
                    }
                )

                NavButton(icon: "arrow.clockwise", action: viewModel.reload)
            }
            .frame(height: 28)

            // Address input container with Safari-style dropdown
            AddressInputContainer(
                viewModel: viewModel,
                securityIcon: securityIcon,
                securityIconColor: securityIconColor,
                showingSecurityInfo: $showingSecurityInfo,
                showingDropdown: $showingDropdown
            )

            // Toolbar buttons in custom order
            HStack(spacing: 0) {
                ForEach(settings.toolbarButtonOrder) { button in
                    toolbarButton(for: button)
                }
            }
            .frame(height: 28)
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
        .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
            // Periodically check for playing videos
            if settings.showPIPButton {
                checkForPlayingVideo()
            }
        }
        .onChange(of: viewModel.activeTabId) { _, _ in
            // Check for video when tab changes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                checkForPlayingVideo()
            }
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

    private func togglePIP() {
        guard let tabId = viewModel.activeTabId,
              let webView = viewModel.getActiveWebView() else { return }

        pipManager.togglePIP(from: webView, sourceTabId: tabId)
    }

    private func checkForPlayingVideo() {
        guard let webView = viewModel.getActiveWebView() else {
            hasPlayingVideo = false
            return
        }

        pipManager.checkForPlayingVideo(in: webView) { hasVideo in
            self.hasPlayingVideo = hasVideo
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

        case .pip:
            // PIP button is shown only when there's a playing video
            if settings.showPIPButton && hasPlayingVideo {
                Button(action: togglePIP) {
                    Image(systemName: pipManager.isPIPActive ? "pip.fill" : "pip")
                        .font(.system(size: 14))
                        .foregroundColor(pipManager.isPIPActive ? Color.accentColor : Color("TextMuted"))
                }
                .buttonStyle(.plain)
                .padding(6)
                .contentShape(Rectangle())
                .help(pipManager.isPIPActive ? "Close Picture in Picture" : "Picture in Picture")
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

// MARK: - Address Input Container (Safari-style)

struct AddressInputContainer: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var suggestionService = SuggestionService.shared
    let securityIcon: String
    let securityIconColor: Color
    @Binding var showingSecurityInfo: Bool
    @Binding var showingDropdown: Bool

    @State private var addressBarFrame: CGRect = .zero
    @State private var isTyping = false
    @State private var lastInputURL = ""

    private var showFavorites: Bool {
        // 顯示收藏夾：未輸入任何東西，或剛獲得焦點還沒開始打字
        !isTyping || viewModel.inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
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

            // URL text field with auto-select on focus
            SelectableTextField(
                text: $viewModel.inputURL,
                placeholder: "Search or enter website",
                onSubmit: {
                    showingDropdown = false
                    isTyping = false
                    suggestionService.cancelSearch()
                    viewModel.navigate()
                },
                onFocus: {
                    lastInputURL = viewModel.inputURL
                    isTyping = false
                    showingDropdown = true
                },
                onBlur: {
                    // Delay closing to allow clicking on dropdown items
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        showingDropdown = false
                        isTyping = false
                        suggestionService.cancelSearch()
                    }
                },
                onMouseDown: {
                    // Reopen dropdown when clicking on already-focused text field
                    if !showingDropdown {
                        isTyping = false
                        showingDropdown = true
                    }
                }
            )
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(Color("TextMuted"))
            .onChange(of: viewModel.inputURL) { oldValue, newValue in
                // 只有當下拉選單顯示時才檢測輸入
                if showingDropdown {
                    // 檢測是否正在輸入（URL 有改變且不是初始載入）
                    if newValue != oldValue && isTyping == false {
                        // 首次輸入：用戶開始打字
                        isTyping = true
                    }

                    if isTyping {
                        // 更新建議
                        suggestionService.updateSuggestions(
                            query: newValue,
                            currentTab: viewModel.activeTab,
                            allTabs: viewModel.tabs,
                            activeTabId: viewModel.activeTabId
                        )
                    }
                }
            }
            .onChange(of: viewModel.activeTabId) { _, _ in
                // 當分頁切換時，關閉下拉選單並重置輸入狀態
                showingDropdown = false
                isTyping = false
                suggestionService.cancelSearch()
                // 強制取消焦點，讓 text field 能更新顯示的 URL
                DispatchQueue.main.async {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
            }
            .onChange(of: showingDropdown) { oldValue, newValue in
                // 當下拉選單關閉時，確保取消文字選取狀態
                if oldValue && !newValue {
                    DispatchQueue.main.async {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        // 追蹤 address bar 的 frame，用於設定 dropdown popover 寬度
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        addressBarFrame = geo.frame(in: .global)
                    }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                        addressBarFrame = newFrame
                    }
            }
        )
        .popover(isPresented: $showingDropdown, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            AddressBarDropdownView(
                suggestions: suggestionService.suggestions,
                showFavorites: showFavorites,
                onSelect: { item in
                    if let url = item.url {
                        viewModel.inputURL = url
                        showingDropdown = false
                        isTyping = false
                        viewModel.navigate()
                    }
                },
                onNavigate: { url in
                    viewModel.inputURL = url
                    showingDropdown = false
                    isTyping = false
                    viewModel.navigate()
                },
                onSwitchTab: { tabId in
                    viewModel.switchToTab(tabId)
                    showingDropdown = false
                    isTyping = false
                },
                width: addressBarFrame.width > 0 ? addressBarFrame.width : nil
            )
            .environmentObject(viewModel)
        }
    }
}

struct NavButton: View {
    let icon: String
    let action: () -> Void
    var isEnabled: Bool = true
    var menuItems: [NavigationHistoryItem]? = nil
    var onMenuItemSelected: ((Int) -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        NavButtonRepresentable(
            icon: icon,
            action: action,
            isEnabled: isEnabled,
            isHovering: $isHovering,
            menuItems: menuItems,
            onMenuItemSelected: onMenuItemSelected
        )
        .frame(width: 28, height: 28)
        .background(isHovering && isEnabled ? Color("AccentHover") : Color.clear)
        .cornerRadius(2)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

/// NSViewRepresentable for NavButton with right-click menu support
struct NavButtonRepresentable: NSViewRepresentable {
    let icon: String
    let action: () -> Void
    let isEnabled: Bool
    @Binding var isHovering: Bool
    var menuItems: [NavigationHistoryItem]?
    var onMenuItemSelected: ((Int) -> Void)?

    func makeNSView(context: Context) -> NavButtonNSView {
        let view = NavButtonNSView()
        view.icon = icon
        view.action = action
        view.isEnabled = isEnabled
        view.menuItems = menuItems
        view.onMenuItemSelected = onMenuItemSelected
        return view
    }

    func updateNSView(_ nsView: NavButtonNSView, context: Context) {
        nsView.icon = icon
        nsView.action = action
        nsView.isEnabled = isEnabled
        nsView.menuItems = menuItems
        nsView.onMenuItemSelected = onMenuItemSelected
        nsView.updateIcon()
    }
}

/// Custom NSView that handles left-click action and right-click menu
class NavButtonNSView: NSView {
    var icon: String = ""
    var action: (() -> Void)?
    var isEnabled: Bool = true
    var menuItems: [NavigationHistoryItem]?
    var onMenuItemSelected: ((Int) -> Void)?

    private var iconImageView: NSImageView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 14),
            imageView.heightAnchor.constraint(equalToConstant: 14)
        ])

        iconImageView = imageView
    }

    func updateIcon() {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        iconImageView?.image = image
        iconImageView?.contentTintColor = isEnabled
            ? NSColor(named: "TextMuted")
            : NSColor(named: "TextMuted")?.withAlphaComponent(0.4)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        action?()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isEnabled, let items = menuItems, !items.isEmpty else { return }

        let menu = NSMenu()
        menu.autoenablesItems = false

        for item in items {
            let menuItem = NSMenuItem(
                title: item.title,
                action: #selector(menuItemClicked(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.tag = item.index
            menuItem.isEnabled = true

            // Load favicon asynchronously
            loadFavicon(for: item.url) { [weak menuItem] image in
                DispatchQueue.main.async {
                    menuItem?.image = image
                }
            }

            menu.addItem(menuItem)
        }

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        onMenuItemSelected?(sender.tag)
    }

    private func loadFavicon(for urlString: String, completion: @escaping (NSImage?) -> Void) {
        guard let url = URL(string: urlString),
              let host = url.host else {
            completion(defaultGlobeIcon())
            return
        }

        // Use Google's favicon service for quick loading
        let faviconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32")

        guard let faviconURL = faviconURL else {
            completion(defaultGlobeIcon())
            return
        }

        URLSession.shared.dataTask(with: faviconURL) { data, _, _ in
            if let data = data, let image = NSImage(data: data) {
                image.size = NSSize(width: 16, height: 16)
                completion(image)
            } else {
                completion(self.defaultGlobeIcon())
            }
        }.resume()
    }

    private func defaultGlobeIcon() -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        return NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }
}

#Preview {
    AddressBar(viewModel: BrowserViewModel())
        .frame(width: 600)
}
