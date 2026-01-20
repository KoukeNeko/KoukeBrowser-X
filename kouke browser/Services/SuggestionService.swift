//
//  SuggestionService.swift
//  kouke browser
//
//  Service for generating address bar suggestions from various sources.
//

import Foundation
import Combine

@MainActor
class SuggestionService: ObservableObject {
    static let shared = SuggestionService()
    
    @Published private(set) var suggestions: [SuggestionItem] = []
    @Published private(set) var isLoading = false
    
    private var searchTask: Task<Void, Never>?
    private let maxLocalResults = 5
    private let maxSearchSuggestions = 5
    
    private init() {}
    
    // MARK: - Public API
    
    /// 根據查詢取得建議
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
        
        var results: [SuggestionItem] = []
        
        // 1. 目前頁面（如果符合）
        if let tab = currentTab, matchesQuery(tab: tab, query: trimmedQuery) {
            results.append(.fromCurrentPage(tab))
        }
        
        // 2. 書籤配對
        let bookmarkMatches = matchBookmarks(query: trimmedQuery)
        results.append(contentsOf: bookmarkMatches)
        
        // 3. 歷史記錄配對
        let historyMatches = matchHistory(query: trimmedQuery)
        results.append(contentsOf: historyMatches)
        
        // 4. 其他分頁配對（分頁切換）
        let tabMatches = matchTabs(query: trimmedQuery, tabs: allTabs, activeTabId: activeTabId)
        results.append(contentsOf: tabMatches)
        
        // 5. Google 搜尋建議（非同步）
        let searchSuggestions = await fetchGoogleSuggestions(query: query)
        results.append(contentsOf: searchSuggestions)
        
        return results
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
            .prefix(maxLocalResults)
            .map { .fromBookmark($0) }
    }
    
    private func matchHistory(query: String) -> [SuggestionItem] {
        let history = HistoryManager.shared.searchHistory(query: query)
        
        return history
            .prefix(maxLocalResults)
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
            .prefix(maxLocalResults)
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
