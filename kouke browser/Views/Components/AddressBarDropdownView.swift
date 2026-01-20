//
//  AddressBarDropdownView.swift
//  kouke browser
//
//  Dropdown view for address bar suggestions and favorites.
//

import SwiftUI

struct AddressBarDropdownView: View {
    let suggestions: [SuggestionItem]
    let showFavorites: Bool
    let onSelect: (SuggestionItem) -> Void
    let onNavigate: (String) -> Void
    let onSwitchTab: (UUID) -> Void
    
    @ObservedObject var bookmarkManager = BookmarkManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            if showFavorites {
                favoritesSection
            } else {
                suggestionsSection
            }
        }
        .frame(minWidth: 400, maxWidth: 500)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color("Bg"))
    }

    // MARK: - Favorites Section

    @ViewBuilder
    private var favoritesSection: some View {
        let currentFolders = bookmarkManager.folders(in: nil)
        let currentBookmarks = bookmarkManager.bookmarks(in: nil)
        let hasContent = !currentBookmarks.isEmpty || !currentFolders.isEmpty

        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text("收藏夾")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color("TextMuted"))
                .textCase(.uppercase)
                .kerning(0.5)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            if hasContent {
                // Grid of folders and bookmarks
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 72, maximum: 88), spacing: 16)
                ], spacing: 16) {
                    // Folders first
                    ForEach(currentFolders.prefix(8)) { folder in
                        DropdownFolderButton(
                            folder: folder,
                            bookmarkManager: bookmarkManager,
                            onNavigate: onNavigate
                        )
                    }

                    // Then bookmarks
                    ForEach(currentBookmarks.prefix(max(0, 8 - currentFolders.count))) { bookmark in
                        DropdownBookmarkButton(bookmark: bookmark) {
                            onNavigate(bookmark.url)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            } else {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(Color("TextMuted").opacity(0.5))

                    Text("尚無書籤")
                        .font(.system(size: 13))
                        .foregroundColor(Color("TextMuted"))

                    Text("按 ⌘D 加入目前頁面")
                        .font(.system(size: 11))
                        .foregroundColor(Color("TextMuted").opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Suggestions Section

    @ViewBuilder
    private var suggestionsSection: some View {
        if suggestions.isEmpty {
            // 空狀態：顯示搜尋提示
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(Color("TextMuted").opacity(0.5))

                Text("輸入搜尋或網址")
                    .font(.system(size: 13))
                    .foregroundColor(Color("TextMuted"))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
        } else {
            VStack(spacing: 0) {
                ForEach(groupedSuggestions.keys.sorted(by: sectionOrder), id: \.self) { section in
                    if let items = groupedSuggestions[section], !items.isEmpty {
                        SuggestionSectionView(
                            title: section,
                            items: items,
                            onSelect: handleSelection
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Grouping
    
    private var groupedSuggestions: [String: [SuggestionItem]] {
        var groups: [String: [SuggestionItem]] = [:]
        
        for item in suggestions {
            let section = sectionTitle(for: item.type)
            if groups[section] == nil {
                groups[section] = []
            }
            groups[section]?.append(item)
        }
        
        return groups
    }
    
    private func sectionTitle(for type: SuggestionType) -> String {
        switch type {
        case .currentPage:
            return "目前頁面"
        case .bookmark:
            return "書籤"
        case .history:
            return "歷史記錄"
        case .searchSuggestion:
            return "Google 搜尋"
        case .tabSwitch:
            return "切換至分頁"
        }
    }
    
    private func sectionOrder(_ a: String, _ b: String) -> Bool {
        // 優先順序：分頁切換 > 歷史記錄 > 書籤 > 搜尋建議
        let order = ["切換至分頁", "歷史記錄", "書籤", "Google 搜尋"]
        let indexA = order.firstIndex(of: a) ?? 999
        let indexB = order.firstIndex(of: b) ?? 999
        return indexA < indexB
    }
    
    private func handleSelection(_ item: SuggestionItem) {
        switch item.type {
        case .tabSwitch:
            if let tabId = item.tabId {
                onSwitchTab(tabId)
            }
        case .searchSuggestion:
            // 搜尋建議：使用搜尋引擎
            let searchURL = "https://www.google.com/search?q=\(item.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? item.title)"
            onNavigate(searchURL)
        default:
            onSelect(item)
        }
    }
}

// MARK: - Suggestion Section View

struct SuggestionSectionView: View {
    let title: String
    let items: [SuggestionItem]
    let onSelect: (SuggestionItem) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color("TextMuted"))
                .textCase(.uppercase)
                .kerning(0.5)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            
            // Items
            ForEach(items) { item in
                SuggestionRowView(item: item) {
                    onSelect(item)
                }
            }
        }
    }
}

// MARK: - Suggestion Row View

struct SuggestionRowView: View {
    let item: SuggestionItem
    let onTap: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Icon
                iconView
                    .frame(width: 24, height: 24)
                
                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text(highlightedTitle)
                        .font(.system(size: 13))
                        .foregroundColor(Color("Text"))
                        .lineLimit(1)
                    
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(Color("TextMuted"))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundColor)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var highlightedTitle: AttributedString {
        var text = AttributedString(item.title)
        // 簡單顯示，不做 highlight（可後續增強）
        return text
    }
    
    @ViewBuilder
    private var iconView: some View {
        switch item.type {
        case .currentPage, .bookmark, .history:
            if let faviconURL = item.faviconURL {
                AsyncImage(url: faviconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit)
                    default:
                        defaultIcon
                    }
                }
            } else {
                defaultIcon
            }
        case .searchSuggestion:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(Color("TextMuted"))
        case .tabSwitch:
            Image(systemName: "arrow.right.arrow.left")
                .font(.system(size: 14))
                .foregroundColor(Color("TextMuted"))
        }
    }
    
    private var defaultIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: 14))
            .foregroundColor(Color("TextMuted"))
    }
    
    private var iconName: String {
        switch item.type {
        case .currentPage:
            return "globe"
        case .bookmark:
            return "star.fill"
        case .history:
            return "clock"
        case .searchSuggestion:
            return "magnifyingglass"
        case .tabSwitch:
            return "arrow.right.arrow.left"
        }
    }
    
    private var backgroundColor: Color {
        if item.type == .currentPage {
            return Color.accentColor.opacity(isHovering ? 0.9 : 0.8)
        }
        return isHovering ? Color("AccentHover") : Color.clear
    }
}

// MARK: - Dropdown Folder Button

struct DropdownFolderButton: View {
    let folder: BookmarkFolder
    let bookmarkManager: BookmarkManager
    let onNavigate: (String) -> Void

    @State private var isHovering = false

    private var bookmarksInFolder: [Bookmark] {
        bookmarkManager.bookmarks(in: folder.id)
    }

    var body: some View {
        Button(action: {
            // Navigate to first bookmark in folder if exists
            if let first = bookmarksInFolder.first {
                onNavigate(first.url)
            }
        }) {
            VStack(spacing: 6) {
                ZStack {
                    Rectangle()
                        .fill(Color("CardBg"))
                        .border(Color("Border"), width: 1)

                    if bookmarksInFolder.isEmpty {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.yellow)
                    } else {
                        // Mini favicon collage
                        DropdownFaviconCollage(bookmarks: Array(bookmarksInFolder.prefix(4)))
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .scaleEffect(isHovering ? 1.03 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isHovering)

                Text(folder.name)
                    .font(.system(size: 10))
                    .foregroundColor(isHovering ? Color("Text") : Color("TextMuted"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 60)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Dropdown Favicon Collage

struct DropdownFaviconCollage: View {
    let bookmarks: [Bookmark]

    private var gridSize: Int {
        if bookmarks.count >= 4 { return 2 }
        return 1
    }

    private var cellSize: CGFloat {
        56.0 / CGFloat(gridSize)
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
                        default:
                            Rectangle()
                                .fill(Color("TabInactive"))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                } else {
                    Rectangle()
                        .fill(Color("TabInactive"))
                        .frame(width: cellSize, height: cellSize)
                }
            }
        }
        .frame(width: 56, height: 56)
    }
}

// MARK: - Dropdown Bookmark Button

struct DropdownBookmarkButton: View {
    let bookmark: Bookmark
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
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
                                .frame(width: 56, height: 56)
                                .clipped()
                        case .failure:
                            Image(systemName: "globe")
                                .font(.system(size: 20))
                                .foregroundColor(Color("TextMuted"))
                        case .empty:
                            ProgressView()
                                .scaleEffect(0.5)
                        @unknown default:
                            Image(systemName: "globe")
                                .font(.system(size: 20))
                                .foregroundColor(Color("TextMuted"))
                        }
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .scaleEffect(isHovering ? 1.03 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isHovering)

                Text(bookmark.title)
                    .font(.system(size: 10))
                    .foregroundColor(isHovering ? Color("Text") : Color("TextMuted"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 60)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

#Preview {
    AddressBarDropdownView(
        suggestions: [
            .searchSuggestion("swift programming"),
            .searchSuggestion("swiftui tutorial")
        ],
        showFavorites: false,
        onSelect: { _ in },
        onNavigate: { _ in },
        onSwitchTab: { _ in }
    )
    .frame(width: 400, height: 300)
    .background(Color.black)
}
