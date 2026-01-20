//
//  SuggestionService.swift
//  kouke browser
//
//  Service for generating address bar suggestions from various sources.
//

import Foundation
import Combine

/// 建議類別優先順序
enum SuggestionCategory: String, CaseIterable {
    case tabSwitch = "tabSwitch"
    case history = "history"
    case bookmark = "bookmark"
    case searchSuggestion = "searchSuggestion"

    var displayName: String {
        switch self {
        case .tabSwitch: return "切換分頁"
        case .history: return "歷史記錄"
        case .bookmark: return "書籤"
        case .searchSuggestion: return "搜尋建議"
        }
    }
}

@MainActor
class SuggestionService: ObservableObject {
    static let shared = SuggestionService()

    @Published private(set) var suggestions: [SuggestionItem] = []
    @Published private(set) var isLoading = false

    // 可配置的優先順序（數字越小越優先）
    var categoryPriority: [SuggestionCategory] = [.tabSwitch, .history, .bookmark, .searchSuggestion]

    // 可配置的數量限制
    var maxTabSwitchResults = 3
    var maxHistoryResults = 5
    var maxBookmarkResults = 5
    var maxSearchSuggestions = 6

    private var searchTask: Task<Void, Never>?

    private init() {}
    
    // MARK: - Public API

    /// 根據查詢取得建議（按優先順序排列）
    func getSuggestions(
        query: String,
        currentTab: Tab?,
        allTabs: [Tab],
        activeTabId: UUID?
    ) async -> [SuggestionItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 空查詢時返回空陣列（讓 UI 顯示收藏夾）
        guard !trimmedQuery.isEmpty else {
            return []
        }

        isLoading = true
        defer { isLoading = false }

        // 收集各類別的結果
        var categoryResults: [SuggestionCategory: [SuggestionItem]] = [:]

        // 分頁切換
        categoryResults[.tabSwitch] = matchTabs(query: trimmedQuery, tabs: allTabs, activeTabId: activeTabId)

        // 歷史記錄
        categoryResults[.history] = matchHistory(query: trimmedQuery)

        // 書籤
        categoryResults[.bookmark] = matchBookmarks(query: trimmedQuery)

        // Google 搜尋建議（非同步）
        categoryResults[.searchSuggestion] = await fetchGoogleSuggestions(query: query)

        // 按優先順序組合結果
        var results: [SuggestionItem] = []
        for category in categoryPriority {
            if let items = categoryResults[category] {
                results.append(contentsOf: items)
            }
        }

        suggestions = results
        return results
    }

    /// 即時更新建議（帶 debounce）
    func updateSuggestions(
        query: String,
        currentTab: Tab?,
        allTabs: [Tab],
        activeTabId: UUID?
    ) {
        // 取消之前的搜尋
        searchTask?.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            suggestions = []
            return
        }

        searchTask = Task {
            // Debounce: 等待 150ms
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }

            let results = await getSuggestions(
                query: query,
                currentTab: currentTab,
                allTabs: allTabs,
                activeTabId: activeTabId
            )

            guard !Task.isCancelled else { return }
            suggestions = results
        }
    }
    
    /// 取消正在進行的搜尋
    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
    }
    
    // MARK: - Local Matching
    
    private func matchesQuery(tab: Tab, query: String) -> Bool {
        let lowerTitle = tab.title.lowercased()
        let lowerURL = tab.url.lowercased()
        return lowerTitle.contains(query) || lowerURL.contains(query)
    }
    
    private func matchBookmarks(query: String) -> [SuggestionItem] {
        let bookmarks = BookmarkManager.shared.bookmarks

        return bookmarks
            .filter { bookmark in
                bookmark.title.lowercased().contains(query) ||
                bookmark.url.lowercased().contains(query)
            }
            .prefix(maxBookmarkResults)
            .map { .fromBookmark($0) }
    }

    private func matchHistory(query: String) -> [SuggestionItem] {
        let history = HistoryManager.shared.searchHistory(query: query)

        // 按 URL 去重，只保留最近一次訪問（假設 history 已按時間排序）
        var seenURLs = Set<String>()
        var uniqueHistory: [HistoryItem] = []

        for item in history {
            let normalizedURL = item.url.lowercased()
            if !seenURLs.contains(normalizedURL) {
                seenURLs.insert(normalizedURL)
                uniqueHistory.append(item)
            }
        }

        return uniqueHistory
            .prefix(maxHistoryResults)
            .map { .fromHistory($0) }
    }

    private func matchTabs(query: String, tabs: [Tab], activeTabId: UUID?) -> [SuggestionItem] {
        return tabs
            .filter { tab in
                // 排除目前分頁
                guard tab.id != activeTabId else { return false }
                // 排除空白頁
                guard !tab.isSpecialPage else { return false }
                // 配對標題或 URL
                return tab.title.lowercased().contains(query) ||
                       tab.url.lowercased().contains(query)
            }
            .prefix(maxTabSwitchResults)
            .map { .fromTab($0) }
    }
    
    // MARK: - Google Search Suggestions
    
    private func fetchGoogleSuggestions(query: String) async -> [SuggestionItem] {
        guard !query.isEmpty else { return [] }
        
        // Google Suggest API (公開，無需 API Key)
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://suggestqueries.google.com/complete/search?client=firefox&q=\(encodedQuery)"
        
        guard let url = URL(string: urlString) else { return [] }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return []
            }
            
            // Google 返回格式: ["query", ["suggestion1", "suggestion2", ...]]
            if let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
               json.count >= 2,
               let suggestions = json[1] as? [String] {
                return suggestions
                    .prefix(maxSearchSuggestions)
                    .map { .searchSuggestion($0) }
            }
        } catch {
            // 網路錯誤時靜默失敗
            NSLog("Failed to fetch Google suggestions: \(error.localizedDescription)")
        }
        
        return []
    }
}
