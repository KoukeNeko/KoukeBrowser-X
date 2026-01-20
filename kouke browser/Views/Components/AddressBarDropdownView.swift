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
    var width: CGFloat? = nil

    var body: some View {
        VStack(spacing: 0) {
            if showFavorites {
                favoritesSection
            } else {
                suggestionsSection
            }
        }
        .frame(width: width ?? 400)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color("Bg"))
    }

    // MARK: - Favorites Section

    @ViewBuilder
    private var favoritesSection: some View {
        // 直接使用 StartPage（下拉選單模式）
        StartPage(
            onNavigate: onNavigate,
            config: .dropdown,
            useScrollView: false,
            maxRecentlyClosedTabs: 6
        )
        .frame(minHeight: 500, alignment: .top)  // 最小高度，頂部對齊
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
