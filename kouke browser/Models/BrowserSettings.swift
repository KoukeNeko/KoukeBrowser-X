//
//  BrowserSettings.swift
//  kouke browser
//
//  Persistent settings for browser configuration.
//

import Foundation
import SwiftUI
import WebKit
import Combine

enum SearchEngine: String, CaseIterable {
    case google = "google"
    case bing = "bing"
    case duckduckgo = "duckduckgo"
    case yahoo = "yahoo"
    
    var displayName: String {
        switch self {
        case .google: return "Google"
        case .bing: return "Bing"
        case .duckduckgo: return "DuckDuckGo"
        case .yahoo: return "Yahoo"
        }
    }
    
    func searchURL(for query: String) -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        switch self {
        case .google:
            return "https://www.google.com/search?q=\(encoded)"
        case .bing:
            return "https://www.bing.com/search?q=\(encoded)"
        case .duckduckgo:
            return "https://duckduckgo.com/?q=\(encoded)"
        case .yahoo:
            return "https://search.yahoo.com/search?p=\(encoded)"
        }
    }
}

enum StartupBehavior: String, CaseIterable {
    case startPage = "start_page"
    case lastTabs = "last_tabs"
    case customURL = "custom_url"
    
    var displayName: String {
        switch self {
        case .startPage: return "Open Start Page"
        case .lastTabs: return "Continue where you left off"
        case .customURL: return "Open a specific page"
        }
    }
}

enum AppTheme: String, CaseIterable {
    case dark = "dark"
    case light = "light"
    
    var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }
    
    var colorScheme: ColorScheme {
        switch self {
        case .dark: return .dark
        case .light: return .light
        }
    }
}

class BrowserSettings: ObservableObject {
    static let shared = BrowserSettings()
    
    private let defaults = UserDefaults.standard
    
    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: "theme") }
    }
    
    @Published var fontSize: Int {
        didSet { defaults.set(fontSize, forKey: "fontSize") }
    }
    
    @Published var searchEngine: SearchEngine {
        didSet { defaults.set(searchEngine.rawValue, forKey: "searchEngine") }
    }
    
    @Published var startupBehavior: StartupBehavior {
        didSet { defaults.set(startupBehavior.rawValue, forKey: "startupBehavior") }
    }
    
    @Published var startupURL: String {
        didSet { defaults.set(startupURL, forKey: "startupURL") }
    }
    
    private init() {
        // Load saved values or use defaults
        if let themeRaw = defaults.string(forKey: "theme"),
           let loadedTheme = AppTheme(rawValue: themeRaw) {
            theme = loadedTheme
        } else {
            theme = .dark
        }
        
        let savedFontSize = defaults.integer(forKey: "fontSize")
        fontSize = savedFontSize > 0 ? savedFontSize : 14
        
        if let engineRaw = defaults.string(forKey: "searchEngine"),
           let loadedEngine = SearchEngine(rawValue: engineRaw) {
            searchEngine = loadedEngine
        } else {
            searchEngine = .google
        }
        
        if let behaviorRaw = defaults.string(forKey: "startupBehavior"),
           let loadedBehavior = StartupBehavior(rawValue: behaviorRaw) {
            startupBehavior = loadedBehavior
        } else {
            startupBehavior = .startPage
        }
        
        startupURL = defaults.string(forKey: "startupURL") ?? ""
    }
    
    func getSearchURL(for query: String) -> String {
        return searchEngine.searchURL(for: query)
    }
    
    func clearBrowsingData() {
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast) { }
    }
}
