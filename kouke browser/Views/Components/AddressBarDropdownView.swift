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
        .frame(width: 400)
        .background(Color("Bg"))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
    
    // MARK: - Favorites Section
    
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Bookmarks header
            Text("收藏夾")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color("TextMuted"))
                .textCase(.uppercase)
                .kerning(0.5)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            
            // Bookmarks grid
            let rootBookmarks = bookmarkManager.rootBookmarks()
            
            if rootBookmarks.isEmpty {
                emptyFavoritesView
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 60, maximum: 80), spacing: 12)
                ], spacing: 12) {
                    ForEach(rootBookmarks.prefix(12)) { bookmark in
                        FavoriteItemView(
                            title: bookmark.title,
                            faviconURL: bookmark.faviconURL
                        ) {
                            onNavigate(bookmark.url)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }
    
    private var emptyFavoritesView: some View {
        VStack(spacing: 8) {
            Image(systemName: "star")
                .font(.system(size: 24))
                .foregroundColor(Color("TextMuted").opacity(0.5))
            Text("尚無收藏夾")
                .font(.system(size: 12))
                .foregroundColor(Color("TextMuted"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
    
    // MARK: - Suggestions Section
    
    private var suggestionsSection: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
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
        }
        .frame(maxHeight: 400)
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
        let order = ["目前頁面", "書籤", "歷史記錄", "切換至分頁", "Google 搜尋"]
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

// MARK: - Favorite Item View

struct FavoriteItemView: View {
    let title: String
    let faviconURL: URL?
    let onTap: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                // Favicon container
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color("CardBg"))
                        .frame(width: 56, height: 56)
                    
                    if let faviconURL = faviconURL {
                        AsyncImage(url: faviconURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            default:
                                Image(systemName: "globe")
                                    .font(.system(size: 20))
                                    .foregroundColor(Color("TextMuted"))
                            }
                        }
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 20))
                            .foregroundColor(Color("TextMuted"))
                    }
                }
                .scaleEffect(isHovering ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isHovering)
                
                // Title
                Text(title)
                    .font(.system(size: 10))
                    .foregroundColor(Color("TextMuted"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 56)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
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
