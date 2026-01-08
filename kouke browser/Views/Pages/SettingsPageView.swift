//
//  SettingsPageView.swift
//  kouke browser
//
//  Full-page settings view with sidebar navigation.
//

import SwiftUI

// MARK: - Settings Page View

struct SettingsPageView: View {
    @ObservedObject private var settings = BrowserSettings.shared
    @State private var selectedSection: SettingsSidebarSection = .general

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebar
                .frame(width: 200)
                .background(Color("CardBg").opacity(0.5))

            // Divider
            Rectangle()
                .fill(Color("Border"))
                .frame(width: 1)

            // Content
            ScrollView {
                contentView
                    .frame(maxWidth: 600)
                    .padding(32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color("Bg"))
        }
        .background(Color("Bg"))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer()
                .frame(height: 20)

            ForEach(SettingsSidebarSection.allCases, id: \.self) { section in
                SidebarButton(
                    title: section.title,
                    icon: section.icon,
                    isSelected: selectedSection == section,
                    action: { selectedSection = section }
                )
            }

            Spacer()
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Section Header
            Text(selectedSection.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color("Text"))

            // Section Content
            switch selectedSection {
            case .general:
                GeneralSettingsContent(settings: settings)
            case .appearance:
                AppearanceSettingsContent(settings: settings)
            case .tabs:
                TabsSettingsContent(settings: settings)
            case .search:
                SearchSettingsContent(settings: settings)
            case .privacy:
                PrivacySettingsContent(settings: settings)
            case .advanced:
                AdvancedSettingsContent(settings: settings)
            }

            Spacer()
        }
    }
}

// MARK: - Settings Sections Enum

private enum SettingsSidebarSection: CaseIterable {
    case general
    case appearance
    case tabs
    case search
    case privacy
    case advanced

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .tabs: return "Tabs"
        case .search: return "Search"
        case .privacy: return "Privacy"
        case .advanced: return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .tabs: return "square.on.square"
        case .search: return "magnifyingglass"
        case .privacy: return "hand.raised"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

// MARK: - Sidebar Button

private struct SidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13))

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundColor(isSelected ? Color("Text") : Color("TextMuted"))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color("TabActive") : (isHovering ? Color("TabInactive") : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - General Settings Content

private struct GeneralSettingsContent: View {
    @ObservedObject var settings: BrowserSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Startup
            SettingsCard(title: "Startup") {
                SettingsPageRow(label: "Kouke opens with:") {
                    Picker("", selection: $settings.startupBehavior) {
                        ForEach(StartupBehavior.allCases, id: \.rawValue) { behavior in
                            Text(behavior.displayName).tag(behavior)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                SettingsPageRow(label: "New windows open with:") {
                    Picker("", selection: $settings.newWindowOpensWith) {
                        ForEach(NewWindowOpensWith.allCases, id: \.rawValue) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                SettingsPageRow(label: "New tabs open with:") {
                    Picker("", selection: $settings.newTabOpensWith) {
                        ForEach(NewTabOpensWith.allCases, id: \.rawValue) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                SettingsPageRow(label: "Homepage:") {
                    HStack {
                        TextField("https://example.com", text: $settings.homepage)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)

                        Button("Set to Current Page") {
                            NotificationCenter.default.post(name: .setCurrentPageAsHomepage, object: nil)
                        }
                    }
                }

                SettingsPageRow(label: "Remove history items:") {
                    Picker("", selection: $settings.removeHistoryItems) {
                        ForEach(RemoveHistoryItems.allCases, id: \.rawValue) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }

            // Downloads
            SettingsCard(title: "Downloads") {
                SettingsPageRow(label: "Save files to:") {
                    Picker("", selection: $settings.downloadLocation) {
                        ForEach(DownloadLocation.allCases, id: \.rawValue) { location in
                            Text(location.displayName).tag(location)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                SettingsPageRow(label: "Remove items:") {
                    Picker("", selection: $settings.removeDownloadItems) {
                        ForEach(RemoveDownloadItems.allCases, id: \.rawValue) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                SettingsPageRow(label: "") {
                    Toggle("Open \"safe\" files after downloading", isOn: $settings.openSafeFilesAfterDownload)
                }
            }
        }
    }
}

// MARK: - Appearance Settings Content

private struct AppearanceSettingsContent: View {
    @ObservedObject var settings: BrowserSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard(title: "Theme") {
                SettingsPageRow(label: "Appearance:") {
                    Picker("", selection: $settings.theme) {
                        ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
            }

            SettingsCard(title: "Toolbar Buttons") {
                Text("Choose which buttons to display in the address bar. When shown, clicking opens a popover. When hidden, use menu or keyboard shortcuts to open in a separate window.")
                    .font(.system(size: 11))
                    .foregroundColor(Color("TextMuted"))
                    .padding(.bottom, 8)

                SettingsPageRow(label: "") {
                    Toggle("Show Downloads button", isOn: $settings.showDownloadsButton)
                }

                SettingsPageRow(label: "") {
                    Toggle("Show Bookmarks button", isOn: $settings.showBookmarksButton)
                }

                SettingsPageRow(label: "") {
                    Toggle("Show Add to Favorites button", isOn: $settings.showAddToFavoritesButton)
                }
            }
        }
    }
}

// MARK: - Tabs Settings Content

private struct TabsSettingsContent: View {
    @ObservedObject var settings: BrowserSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard(title: "Tab Layout") {
                SettingsPageRow(label: "Style:") {
                    Picker("", selection: $settings.tabBarStyle) {
                        ForEach(TabBarStyle.allCases, id: \.rawValue) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                }

                Text("Normal shows a traditional tab bar with address bar below. Compact combines tabs and URL display in a single row.")
                    .font(.system(size: 11))
                    .foregroundColor(Color("TextMuted"))
                    .padding(.top, 4)

                if settings.tabBarStyle == .compact {
                    SettingsPageRow(label: "Show all tabs:") {
                        Toggle("", isOn: $settings.showTabsInCompactMode)
                            .labelsHidden()
                    }

                    Text("When enabled, all tabs are shown in compact mode. When disabled, only the active tab is displayed.")
                        .font(.system(size: 11))
                        .foregroundColor(Color("TextMuted"))
                        .padding(.top, 4)
                }
            }

            SettingsCard(title: "Tab Behavior") {
                SettingsPageRow(label: "Open pages in tabs:") {
                    Picker("", selection: $settings.openPagesInTabs) {
                        ForEach(OpenPagesInTabs.allCases, id: \.rawValue) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                SettingsPageRow(label: "") {
                    Toggle("Open links in background", isOn: $settings.openLinksInBackground)
                }

                SettingsPageRow(label: "") {
                    Toggle("⌘-Click opens in new tab", isOn: $settings.commandClickOpensNewTab)
                }
            }
        }
    }
}

// MARK: - Search Settings Content

private struct SearchSettingsContent: View {
    @ObservedObject var settings: BrowserSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard(title: "Search Engine") {
                SettingsPageRow(label: "Default:") {
                    Picker("", selection: $settings.searchEngine) {
                        ForEach(SearchEngine.allCases, id: \.rawValue) { engine in
                            Text(engine.displayName).tag(engine)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }

            SettingsCard(title: "Search Suggestions") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Include search engine suggestions", isOn: $settings.includeSearchSuggestions)
                    Toggle("Include Kouke suggestions", isOn: $settings.includeKoukeSuggestions)
                    Toggle("Enable Quick Website Search", isOn: $settings.enableQuickWebsiteSearch)
                    Toggle("Preload Top Hit in background", isOn: $settings.preloadTopHit)
                    Toggle("Show Favorites", isOn: $settings.showFavoritesInSearch)
                }
                .font(.system(size: 13))
            }
        }
    }
}

// MARK: - Privacy Settings Content

private struct PrivacySettingsContent: View {
    @ObservedObject var settings: BrowserSettings
    @State private var showingClearAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard(title: "Tracking") {
                SettingsPageRow(label: "") {
                    Toggle("Prevent cross-site tracking", isOn: $settings.preventCrossSiteTracking)
                }

                SettingsPageRow(label: "") {
                    Toggle("Hide IP address from trackers", isOn: $settings.hideIPFromTrackers)
                }
            }

            SettingsCard(title: "Cookies & Data") {
                SettingsPageRow(label: "") {
                    Toggle("Block all cookies", isOn: $settings.blockAllCookies)
                }

                HStack(spacing: 12) {
                    Button("Manage Website Data...") {
                        // Open system preferences for website data
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_WebsiteData")!)
                    }

                    Button("Clear History...") {
                        showingClearAlert = true
                    }
                }
                .padding(.top, 8)
            }
            .alert("Clear Browsing Data", isPresented: $showingClearAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    settings.clearBrowsingData()
                    HistoryManager.shared.clearHistory()
                }
            } message: {
                Text("This will clear all browsing history, cookies, and cached data.")
            }
        }
    }
}

// MARK: - Advanced Settings Content

private struct AdvancedSettingsContent: View {
    @ObservedObject var settings: BrowserSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard(title: "Address Bar") {
                SettingsPageRow(label: "") {
                    Toggle("Show full website address", isOn: $settings.showFullWebsiteAddress)
                }
            }

            SettingsCard(title: "Accessibility") {
                SettingsPageRow(label: "") {
                    HStack {
                        Toggle("Never use font sizes smaller than", isOn: $settings.useMinimumFontSize)

                        if settings.useMinimumFontSize {
                            Picker("", selection: $settings.minimumFontSize) {
                                ForEach([9, 10, 11, 12, 14, 16, 18], id: \.self) { size in
                                    Text("\(size)").tag(size)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 60)
                        }
                    }
                }
            }

            SettingsCard(title: "Developer") {
                SettingsPageRow(label: "") {
                    Toggle("Show Develop menu in menu bar", isOn: $settings.showDeveloperMenu)
                }
            }
        }
    }
}

// MARK: - Settings Card

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color("TextMuted"))
                .textCase(.uppercase)
                .kerning(0.5)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("CardBg"))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color("Border"), lineWidth: 1)
            )
        }
    }
}

// MARK: - Settings Page Row

private struct SettingsPageRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(Color("TextMuted"))
                    .frame(width: 140, alignment: .trailing)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: label.isEmpty ? .leading : .leading)
    }
}

// MARK: - Preview

#Preview {
    SettingsPageView()
        .frame(width: 900, height: 600)
}
