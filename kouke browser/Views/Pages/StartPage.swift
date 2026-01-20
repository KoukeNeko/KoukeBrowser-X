//
//  StartPage.swift
//  kouke browser
//
//  New tab start page with favorites grid including folders.
//

import SwiftUI

struct StartPage: View {
    var onNavigate: (String) -> Void
    var config: FavoritesGridConfig = .startPage
    var useScrollView: Bool = true  // true = 全頁模式使用 ScrollView，false = 下拉選單不用
    var maxRecentlyClosedTabs: Int = 20  // 最近關閉分頁的最大顯示數量

    @ObservedObject var bookmarkManager = BookmarkManager.shared
    @ObservedObject var recentlyClosedManager = RecentlyClosedTabsManager.shared
    @ObservedObject var suggestionsManager = SuggestionsManager.shared
    @State private var currentFolderId: UUID? = nil
    @State private var folderPath: [UUID] = []

    private var currentFolderName: String {
        if let folderId = currentFolderId,
           let folder = bookmarkManager.folders.first(where: { $0.id == folderId }) {
            return folder.name
        }
        return "Bookmarks"
    }

    private var hasContent: Bool {
        let folders = bookmarkManager.folders(in: currentFolderId)
        let bookmarks = bookmarkManager.bookmarks(in: currentFolderId)
        return !folders.isEmpty || !bookmarks.isEmpty || currentFolderId != nil
    }

    var body: some View {
        if useScrollView {
            // 全頁模式：使用 ScrollView
            ScrollView {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 80)
                    contentView

                    // 建議頁面
                    if !suggestionsManager.suggestions.isEmpty {
                        SuggestionsSection(
                            suggestions: suggestionsManager.topSuggestions(limit: 8),
                            onNavigate: onNavigate,
                            onRemove: { suggestionsManager.removeSuggestion($0) },
                            onClearAll: { suggestionsManager.clearAll() },
                            horizontalPadding: config.horizontalPadding
                        )
                        .frame(maxWidth: 1200, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                    }

                    // 最近關閉的分頁
                    if !recentlyClosedManager.closedTabs.isEmpty {
                        RecentlyClosedTabsSection(
                            closedTabs: Array(recentlyClosedManager.closedTabs.prefix(maxRecentlyClosedTabs)),
                            onReopen: { tabId in
                                if let closedTab = recentlyClosedManager.reopenTab(tabId) {
                                    onNavigate(closedTab.url)
                                }
                            },
                            onClearAll: {
                                recentlyClosedManager.clearAll()
                            },
                            horizontalPadding: config.horizontalPadding
                        )
                        .frame(maxWidth: 1200, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color("Bg"))
        } else {
            // 下拉選單模式：不用 ScrollView
            VStack(spacing: 0) {
                contentView

                // 建議頁面
                if !suggestionsManager.suggestions.isEmpty {
                    SuggestionsSection(
                        suggestions: suggestionsManager.topSuggestions(limit: 8),
                        onNavigate: onNavigate,
                        onRemove: { suggestionsManager.removeSuggestion($0) },
                        onClearAll: { suggestionsManager.clearAll() },
                        horizontalPadding: config.horizontalPadding
                    )
                    .padding(.top, 16)
                }

                // 最近關閉的分頁
                if !recentlyClosedManager.closedTabs.isEmpty {
                    RecentlyClosedTabsSection(
                        closedTabs: Array(recentlyClosedManager.closedTabs.prefix(maxRecentlyClosedTabs)),
                        onReopen: { tabId in
                            if let closedTab = recentlyClosedManager.reopenTab(tabId) {
                                onNavigate(closedTab.url)
                            }
                        },
                        onClearAll: {
                            recentlyClosedManager.clearAll()
                        },
                        horizontalPadding: config.horizontalPadding
                    )
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 16) {
                // Header with back button when in folder
                HStack(spacing: 4) {
                    if currentFolderId != nil {
                        Button(action: goBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color("TextMuted"))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Text(currentFolderName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color("TextMuted"))
                        .textCase(.uppercase)
                        .kerning(0.5)
                }
                .padding(.horizontal, config.horizontalPadding)
                .padding(.top, useScrollView ? 0 : 16)
                .frame(height: 24)  // 固定高度確保一致性

                // 使用共用的 FavoritesGridView
                FavoritesGridView(
                    bookmarkManager: bookmarkManager,
                    folderId: currentFolderId,
                    config: config,
                    onNavigate: onNavigate,
                    onFolderTap: enterFolder
                )
                .padding(.horizontal, config.horizontalPadding)
            }
            .frame(maxWidth: useScrollView ? 1200 : nil, alignment: .leading)
            .frame(maxWidth: useScrollView ? .infinity : nil)
        } else {
            // Empty state
            VStack(spacing: 16) {
                Image(systemName: "bookmark")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(Color("TextMuted").opacity(0.5))

                Text("No bookmarks yet")
                    .font(.system(size: 14))
                    .foregroundColor(Color("TextMuted"))

                Text("Press ⌘D to bookmark the current page")
                    .font(.system(size: 12))
                    .foregroundColor(Color("TextMuted").opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, useScrollView ? 100 : 20)
            .padding(.bottom, useScrollView ? 0 : 20)
        }
    }

    private func enterFolder(_ folderId: UUID) {
        folderPath.append(folderId)
        currentFolderId = folderId
    }

    private func goBack() {
        folderPath.removeLast()
        currentFolderId = folderPath.last
    }
}

// MARK: - Folder Button for Start Page

struct FolderButton: View {
    let folder: BookmarkFolder
    let bookmarkManager: BookmarkManager
    let action: () -> Void
    var size: CGFloat = 64
    @ObservedObject private var faviconService = FaviconService.shared

    @State private var isHovering = false

    private var bookmarksInFolder: [Bookmark] {
        bookmarkManager.bookmarks(in: folder.id)
    }

    private var maxFavicons: Int {
        size >= 64 ? 9 : 4
    }

    private var iconFontSize: CGFloat {
        size >= 64 ? 28 : 24
    }

    private var titleFontSize: CGFloat {
        size >= 64 ? 11 : 10
    }

    private var spacing: CGFloat {
        size >= 64 ? 8 : 6
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: spacing) {
                // Folder icon container with favicon grid
                ZStack {
                    Rectangle()
                        .fill(Color("CardBg"))
                        .border(Color("Border"), width: 1)

                    if bookmarksInFolder.isEmpty {
                        // Empty folder icon
                        Image(systemName: "folder.fill")
                            .font(.system(size: iconFontSize))
                            .foregroundColor(.yellow)
                    } else {
                        // Grid of favicons
                        FaviconCollage(bookmarks: Array(bookmarksInFolder.prefix(maxFavicons)), size: size)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .scaleEffect(isHovering ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isHovering)

                // Title
                Text(folder.name)
                    .font(.system(size: titleFontSize))
                    .foregroundColor(isHovering ? Color("Text") : Color("TextMuted"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: size - 4)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Favicon Collage (Configurable Grid)

struct FaviconCollage: View {
    let bookmarks: [Bookmark]
    var size: CGFloat = 64
    @ObservedObject private var faviconService = FaviconService.shared

    private var gridSize: Int {
        // Determine grid size based on bookmark count and container size
        if size >= 64 {
            if bookmarks.count >= 9 { return 3 }
            if bookmarks.count >= 4 { return 2 }
            return 1
        } else {
            // Smaller size: max 2x2 grid
            if bookmarks.count >= 4 { return 2 }
            return 1
        }
    }

    private var cellSize: CGFloat {
        size / CGFloat(gridSize)
    }

    private var globeIconSize: CGFloat {
        size >= 64 ? 24 : 20
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(cellSize), spacing: 0), count: gridSize),
            spacing: 0
        ) {
            ForEach(0..<(gridSize * gridSize), id: \.self) { index in
                if index < bookmarks.count {
                    AsyncImage(url: bookmarks[index].faviconURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: cellSize, height: cellSize)
                                .clipped()
                        case .failure:
                             if gridSize == 1 {
                                 Image(systemName: "globe")
                                     .font(.system(size: globeIconSize))
                                     .foregroundColor(Color("TextMuted"))
                                     .frame(width: cellSize, height: cellSize)
                             } else {
                                Rectangle()
                                    .fill(Color("TabInactive"))
                                    .frame(width: cellSize, height: cellSize)
                             }
                        case .empty:
                            Rectangle()
                                .fill(Color("TabInactive"))
                                .frame(width: cellSize, height: cellSize)
                        @unknown default:
                            Rectangle()
                                .fill(Color("TabInactive"))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                    .id(bookmarks[index].faviconURL)
                } else {
                    Rectangle()
                        .fill(Color("TabInactive"))
                        .frame(width: cellSize, height: cellSize)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Bookmark Button for Start Page

struct BookmarkButton: View {
    let bookmark: Bookmark
    let action: () -> Void
    var size: CGFloat = 64
    @ObservedObject private var faviconService = FaviconService.shared

    @State private var isHovering = false

    private var iconFontSize: CGFloat {
        size >= 64 ? 24 : 20
    }

    private var titleFontSize: CGFloat {
        size >= 64 ? 11 : 10
    }

    private var spacing: CGFloat {
        size >= 64 ? 8 : 6
    }

    private var progressScale: CGFloat {
        size >= 64 ? 0.6 : 0.5
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: spacing) {
                // Icon container with favicon
                ZStack {
                    Rectangle()
                        .fill(Color("CardBg"))
                        .border(Color("Border"), width: 1)

                    AsyncImage(url: bookmark.faviconURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: size, height: size)
                                .clipped()
                        case .failure:
                            Image(systemName: "globe")
                                .font(.system(size: iconFontSize))
                                .foregroundColor(Color("TextMuted"))
                        case .empty:
                            ProgressView()
                                .scaleEffect(progressScale)
                        @unknown default:
                            Image(systemName: "globe")
                                .font(.system(size: iconFontSize))
                                .foregroundColor(Color("TextMuted"))
                        }
                    }
                    .id(bookmark.faviconURL)
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .scaleEffect(isHovering ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isHovering)

                // Title
                Text(bookmark.title)
                    .font(.system(size: titleFontSize))
                    .foregroundColor(isHovering ? Color("Text") : Color("TextMuted"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: size - 4)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Recently Closed Tabs Section

struct RecentlyClosedTabsSection: View {
    let closedTabs: [ClosedTab]
    let onReopen: (UUID) -> Void
    let onClearAll: () -> Void
    var horizontalPadding: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header - 統一使用與 BOOKMARKS 相同的樣式
            HStack {
                Text("Recently Closed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color("TextMuted"))
                    .textCase(.uppercase)
                    .kerning(0.5)

                Spacer()

                // Clear all button
                Button(action: onClearAll) {
                    HStack(spacing: 4) {
                        Text("Clear All")
                            .font(.system(size: 12))
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }

            // Tabs flow layout
            FlowLayout(spacing: 12) {
                ForEach(closedTabs) { tab in
                    ClosedTabButton(tab: tab) {
                        onReopen(tab.id)
                    }
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
    }
}

// MARK: - Closed Tab Button

struct ClosedTabButton: View {
    let tab: ClosedTab
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(tab.title)
                .font(.system(size: 13))
                .foregroundColor(Color("Text"))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isHovering ? Color("AccentHover") : Color("CardBg"))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            // If this item doesn't fit in the current row, move to next row
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalHeight = max(totalHeight, currentY + rowHeight)
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

#Preview {
    StartPage(onNavigate: { _ in })
        .frame(width: 800, height: 600)
}
