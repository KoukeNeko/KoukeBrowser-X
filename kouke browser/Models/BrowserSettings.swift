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
#if os(macOS)
import AppKit
#endif

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

enum TabBarStyle: String, CaseIterable {
    case normal = "normal"
    case compact = "compact"

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .compact: return "Compact"
        }
    }
}

enum DownloadLocation: String, CaseIterable {
    case downloads = "downloads"
    case askEachTime = "ask"

    var displayName: String {
        switch self {
        case .downloads: return "Downloads"
        case .askEachTime: return "Ask for each file"
        }
    }
}

enum RemoveDownloadItems: String, CaseIterable {
    case afterOneDay = "after_one_day"
    case whenKoukeQuits = "when_quit"
    case uponSuccessfulDownload = "upon_success"
    case manually = "manually"

    var displayName: String {
        switch self {
        case .afterOneDay: return "After one day"
        case .whenKoukeQuits: return "When Kouke quits"
        case .uponSuccessfulDownload: return "Upon successful download"
        case .manually: return "Manually"
        }
    }
}

enum OpenPagesInTabs: String, CaseIterable {
    case never = "never"
    case automatically = "automatically"
    case always = "always"

    var displayName: String {
        switch self {
        case .never: return "Never"
        case .automatically: return "Automatically"
        case .always: return "Always"
        }
    }
}

class BrowserSettings: ObservableObject {
    static let shared = BrowserSettings()

    private let defaults = UserDefaults.standard

    @Published var theme: AppTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: "theme")
            applyTheme()
        }
    }

    /// Apply theme to the entire app
    func applyTheme() {
        #if os(macOS)
        DispatchQueue.main.async {
            NSApp.appearance = NSAppearance(named: self.theme == .dark ? .darkAqua : .aqua)
        }
        #endif
    }

    @Published var fontSize: Int {
        didSet {
            defaults.set(fontSize, forKey: "fontSize")
            NotificationCenter.default.post(name: .fontSizeChanged, object: fontSize)
        }
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

    @Published var tabBarStyle: TabBarStyle {
        didSet { defaults.set(tabBarStyle.rawValue, forKey: "tabBarStyle") }
    }

    @Published var showTabsInCompactMode: Bool {
        didSet { defaults.set(showTabsInCompactMode, forKey: "showTabsInCompactMode") }
    }

    // Developer settings
    @Published var disableJavaScript: Bool {
        didSet { defaults.set(disableJavaScript, forKey: "disableJavaScript") }
    }

    @Published var disableImages: Bool {
        didSet { defaults.set(disableImages, forKey: "disableImages") }
    }

    @Published var showDeveloperMenu: Bool {
        didSet { defaults.set(showDeveloperMenu, forKey: "showDeveloperMenu") }
    }

    // Download settings
    @Published var downloadLocation: DownloadLocation {
        didSet { defaults.set(downloadLocation.rawValue, forKey: "downloadLocation") }
    }

    @Published var removeDownloadItems: RemoveDownloadItems {
        didSet { defaults.set(removeDownloadItems.rawValue, forKey: "removeDownloadItems") }
    }

    // Tab behavior settings
    @Published var openPagesInTabs: OpenPagesInTabs {
        didSet { defaults.set(openPagesInTabs.rawValue, forKey: "openPagesInTabs") }
    }

    @Published var openLinksInBackground: Bool {
        didSet { defaults.set(openLinksInBackground, forKey: "openLinksInBackground") }
    }

    @Published var commandClickOpensNewTab: Bool {
        didSet { defaults.set(commandClickOpensNewTab, forKey: "commandClickOpensNewTab") }
    }

    // Search settings
    @Published var includeSearchSuggestions: Bool {
        didSet { defaults.set(includeSearchSuggestions, forKey: "includeSearchSuggestions") }
    }

    @Published var includeKoukeSuggestions: Bool {
        didSet { defaults.set(includeKoukeSuggestions, forKey: "includeKoukeSuggestions") }
    }

    @Published var enableQuickWebsiteSearch: Bool {
        didSet { defaults.set(enableQuickWebsiteSearch, forKey: "enableQuickWebsiteSearch") }
    }

    @Published var preloadTopHit: Bool {
        didSet { defaults.set(preloadTopHit, forKey: "preloadTopHit") }
    }

    @Published var showFavoritesInSearch: Bool {
        didSet { defaults.set(showFavoritesInSearch, forKey: "showFavoritesInSearch") }
    }

    // Privacy settings
    @Published var preventCrossSiteTracking: Bool {
        didSet { defaults.set(preventCrossSiteTracking, forKey: "preventCrossSiteTracking") }
    }

    @Published var hideIPFromTrackers: Bool {
        didSet { defaults.set(hideIPFromTrackers, forKey: "hideIPFromTrackers") }
    }

    @Published var blockAllCookies: Bool {
        didSet { defaults.set(blockAllCookies, forKey: "blockAllCookies") }
    }

    // Advanced settings
    @Published var showFullWebsiteAddress: Bool {
        didSet { defaults.set(showFullWebsiteAddress, forKey: "showFullWebsiteAddress") }
    }

    @Published var minimumFontSize: Int {
        didSet { defaults.set(minimumFontSize, forKey: "minimumFontSize") }
    }

    @Published var useMinimumFontSize: Bool {
        didSet { defaults.set(useMinimumFontSize, forKey: "useMinimumFontSize") }
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

        if let tabBarStyleRaw = defaults.string(forKey: "tabBarStyle"),
           let loadedTabBarStyle = TabBarStyle(rawValue: tabBarStyleRaw) {
            tabBarStyle = loadedTabBarStyle
        } else {
            tabBarStyle = .normal
        }

        showTabsInCompactMode = defaults.bool(forKey: "showTabsInCompactMode")

        // Developer settings
        disableJavaScript = defaults.bool(forKey: "disableJavaScript")
        disableImages = defaults.bool(forKey: "disableImages")

        // Show developer menu defaults to true
        if defaults.object(forKey: "showDeveloperMenu") != nil {
            showDeveloperMenu = defaults.bool(forKey: "showDeveloperMenu")
        } else {
            showDeveloperMenu = true
        }

        // Download settings
        if let downloadLocationRaw = defaults.string(forKey: "downloadLocation"),
           let loadedDownloadLocation = DownloadLocation(rawValue: downloadLocationRaw) {
            downloadLocation = loadedDownloadLocation
        } else {
            downloadLocation = .downloads
        }

        if let removeDownloadItemsRaw = defaults.string(forKey: "removeDownloadItems"),
           let loadedRemoveDownloadItems = RemoveDownloadItems(rawValue: removeDownloadItemsRaw) {
            removeDownloadItems = loadedRemoveDownloadItems
        } else {
            removeDownloadItems = .afterOneDay
        }

        // Tab behavior settings
        if let openPagesInTabsRaw = defaults.string(forKey: "openPagesInTabs"),
           let loadedOpenPagesInTabs = OpenPagesInTabs(rawValue: openPagesInTabsRaw) {
            openPagesInTabs = loadedOpenPagesInTabs
        } else {
            openPagesInTabs = .automatically
        }

        openLinksInBackground = defaults.bool(forKey: "openLinksInBackground")

        if defaults.object(forKey: "commandClickOpensNewTab") != nil {
            commandClickOpensNewTab = defaults.bool(forKey: "commandClickOpensNewTab")
        } else {
            commandClickOpensNewTab = true
        }

        // Search settings - default to true for better UX
        if defaults.object(forKey: "includeSearchSuggestions") != nil {
            includeSearchSuggestions = defaults.bool(forKey: "includeSearchSuggestions")
        } else {
            includeSearchSuggestions = true
        }

        if defaults.object(forKey: "includeKoukeSuggestions") != nil {
            includeKoukeSuggestions = defaults.bool(forKey: "includeKoukeSuggestions")
        } else {
            includeKoukeSuggestions = true
        }

        if defaults.object(forKey: "enableQuickWebsiteSearch") != nil {
            enableQuickWebsiteSearch = defaults.bool(forKey: "enableQuickWebsiteSearch")
        } else {
            enableQuickWebsiteSearch = true
        }

        if defaults.object(forKey: "preloadTopHit") != nil {
            preloadTopHit = defaults.bool(forKey: "preloadTopHit")
        } else {
            preloadTopHit = true
        }

        if defaults.object(forKey: "showFavoritesInSearch") != nil {
            showFavoritesInSearch = defaults.bool(forKey: "showFavoritesInSearch")
        } else {
            showFavoritesInSearch = true
        }

        // Privacy settings - default to safer options
        if defaults.object(forKey: "preventCrossSiteTracking") != nil {
            preventCrossSiteTracking = defaults.bool(forKey: "preventCrossSiteTracking")
        } else {
            preventCrossSiteTracking = true
        }

        hideIPFromTrackers = defaults.bool(forKey: "hideIPFromTrackers")
        blockAllCookies = defaults.bool(forKey: "blockAllCookies")

        // Advanced settings
        showFullWebsiteAddress = defaults.bool(forKey: "showFullWebsiteAddress")

        let savedMinFontSize = defaults.integer(forKey: "minimumFontSize")
        minimumFontSize = savedMinFontSize > 0 ? savedMinFontSize : 9

        useMinimumFontSize = defaults.bool(forKey: "useMinimumFontSize")

        // Apply saved theme on startup
        applyTheme()
    }

    func getSearchURL(for query: String) -> String {
        return searchEngine.searchURL(for: query)
    }

    func clearBrowsingData() {
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast) { }
    }

    // MARK: - Developer Menu Actions

    func toggleJavaScript() {
        disableJavaScript.toggle()
        // Notify webviews to reload with new setting
        NotificationCenter.default.post(name: .developerSettingsChanged, object: nil)
    }

    func toggleImages() {
        disableImages.toggle()
        NotificationCenter.default.post(name: .developerSettingsChanged, object: nil)
    }

    func clearCache() {
        let dataStore = WKWebsiteDataStore.default()
        let cacheTypes: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache
        ]
        dataStore.removeData(ofTypes: cacheTypes, modifiedSince: Date.distantPast) { }
    }

    func clearCookies() {
        let dataStore = WKWebsiteDataStore.default()
        let cookieTypes: Set<String> = [
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeLocalStorage
        ]
        dataStore.removeData(ofTypes: cookieTypes, modifiedSince: Date.distantPast) { }
    }
}

extension Notification.Name {
    static let developerSettingsChanged = Notification.Name("developerSettingsChanged")
    static let fontSizeChanged = Notification.Name("fontSizeChanged")
}
