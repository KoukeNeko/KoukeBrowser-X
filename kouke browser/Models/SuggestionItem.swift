//
//  SuggestionItem.swift
//  kouke browser
//
//  Data model for address bar suggestions.
//

import Foundation

/// 建議項目類型
enum SuggestionType: Equatable {
    case currentPage      // 目前網頁（藍色 Hightlight)
    case history          // 歷史記錄
    case bookmark         // 書籤
    case searchSuggestion // Google 搜尋建議
    case tabSwitch        // 切換分頁
}

/// 地址欄建議項目
struct SuggestionItem: Identifiable, Equatable {
    let id: UUID
    let type: SuggestionType
    let title: String
    let subtitle: String?
    let url: String?
    let faviconURL: URL?
    let timestamp: Date?   // 用於歷史記錄
    let tabId: UUID?       // 用於分頁切換
    
    init(
        id: UUID = UUID(),
        type: SuggestionType,
        title: String,
        subtitle: String? = nil,
        url: String? = nil,
        faviconURL: URL? = nil,
        timestamp: Date? = nil,
        tabId: UUID? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.faviconURL = faviconURL
        self.timestamp = timestamp
        self.tabId = tabId
    }
    
    /// 從 HistoryItem 建立
    static func fromHistory(_ item: HistoryItem) -> SuggestionItem {
        SuggestionItem(
            type: .history,
            title: item.title,
            subtitle: formatRelativeTime(item.visitedAt),
            url: item.url,
            faviconURL: item.faviconURL,
            timestamp: item.visitedAt
        )
    }
    
    /// 從 Bookmark 建立
    static func fromBookmark(_ bookmark: Bookmark) -> SuggestionItem {
        SuggestionItem(
            type: .bookmark,
            title: bookmark.title,
            subtitle: URL(string: bookmark.url)?.host,
            url: bookmark.url,
            faviconURL: bookmark.faviconURL
        )
    }
    
    /// 從 Tab 建立（用於分頁切換）
    static func fromTab(_ tab: Tab) -> SuggestionItem {
        SuggestionItem(
            type: .tabSwitch,
            title: tab.title.isEmpty ? "New Tab" : tab.title,
            subtitle: URL(string: tab.url)?.host,
            url: tab.url,
            faviconURL: tab.faviconURL,
            tabId: tab.id
        )
    }
    
    /// 從目前頁面建立
    static func fromCurrentPage(_ tab: Tab) -> SuggestionItem {
        SuggestionItem(
            type: .currentPage,
            title: tab.title.isEmpty ? "New Tab" : tab.title,
            subtitle: URL(string: tab.url)?.host,
            url: tab.url,
            faviconURL: tab.faviconURL
        )
    }
    
    /// 建立搜尋建議
    static func searchSuggestion(_ query: String) -> SuggestionItem {
        SuggestionItem(
            type: .searchSuggestion,
            title: query,
            subtitle: nil,
            url: nil
        )
    }
    
    // MARK: - Helper
    
    private static func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "zh-TW")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
