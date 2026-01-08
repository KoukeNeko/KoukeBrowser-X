//
//  SettingsView.swift
//  kouke browser
//
//  Settings page with Safari-style toolbar and layout.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = BrowserSettings.shared

    // Fixed width for the label column to align everything perfectly like Safari
    static let labelWidth: CGFloat = 160

    var body: some View {
        TabView {
            GeneralSection(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            TabsSection(settings: settings)
                .tabItem {
                    Label("Tabs", systemImage: "square.on.square")
                }

            SearchSection(settings: settings)
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }

            PrivacySection(settings: settings)
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }

            AdvancedSection(settings: settings)
                .tabItem {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
        }
        .frame(width: 600) // Standard width for settings
        .padding(20)
    }
}

// MARK: - General Section

struct GeneralSection: View {
    @ObservedObject var settings: BrowserSettings

    var body: some View {
        Form {
            // Startup
            SettingsSection {
                SettingsRow(label: "Kouke opens with:") {
                    Picker("", selection: $settings.startupBehavior) {
                        ForEach(StartupBehavior.allCases, id: \.rawValue) { behavior in
                            Text(behavior.displayName).tag(behavior)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                SettingsRow(label: "New windows open with:") {
                    Picker("", selection: $settings.newWindowOpensWith) {
                        ForEach(NewWindowOpensWith.allCases, id: \.rawValue) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                SettingsRow(label: "New tabs open with:") {
                    Picker("", selection: $settings.newTabOpensWith) {
                        ForEach(NewTabOpensWith.allCases, id: \.rawValue) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                SettingsRow(label: "Homepage:") {
                    HStack {
                        TextField("https://example.com", text: $settings.homepage)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)

                        Button("Set to Current Page") {
                            NotificationCenter.default.post(name: .setCurrentPageAsHomepage, object: nil)
                        }
                    }
                }

                SettingsRow(label: "Remove history items:") {
                    Picker("", selection: $settings.removeHistoryItems) {
                        ForEach(RemoveHistoryItems.allCases, id: \.rawValue) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }

            Divider().padding(.vertical, 8)

            // Appearance
            SettingsSection {
                SettingsRow(label: "Appearance:") {
                    Picker("", selection: $settings.theme) {
                        ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }

                SettingsRow(label: "Default font size:") {
                     Picker("", selection: $settings.fontSize) {
                        ForEach([12, 13, 14, 15, 16, 18, 20, 24], id: \.self) { size in
                            Text("\(size)").tag(size)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 60)
                }
            }

            Divider().padding(.vertical, 8)

            SettingsSection {
                SettingsRow(label: "File download location:") {
                    Picker("", selection: $settings.downloadLocation) {
                        ForEach(DownloadLocation.allCases, id: \.rawValue) { location in
                            Text(location.displayName).tag(location)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                SettingsRow(label: "Remove download list items:") {
                    Picker("", selection: $settings.removeDownloadItems) {
                        ForEach(RemoveDownloadItems.allCases, id: \.rawValue) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                SettingsRow(label: "") {
                    Toggle("Open \"safe\" files after downloading", isOn: $settings.openSafeFilesAfterDownload)
                }
            }
        }
        .padding()
    }
}

// MARK: - Tabs Section

struct TabsSection: View {
    @ObservedObject var settings: BrowserSettings

    var body: some View {
         Form {
            SettingsRow(label: "Tab layout:") {
                Picker("", selection: $settings.tabBarStyle) {
                    ForEach(TabBarStyle.allCases, id: \.rawValue) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }

            Text("Normal shows a traditional tab bar with address bar below. Compact combines tabs and URL display in a single row like Safari.")
                .font(.system(size: 11))
                .foregroundColor(Color("TextMuted"))
                .padding(.leading, SettingsView.labelWidth * 1.05 + 10)
                .padding(.top, -4)

            if settings.tabBarStyle == .compact {
                SettingsRow(label: "Show tabs in compact mode:") {
                    Toggle("", isOn: $settings.showTabsInCompactMode)
                        .labelsHidden()
                }

                Text("When enabled, all tabs are shown in compact mode. When disabled, only the active tab is displayed.")
                    .font(.system(size: 11))
                    .foregroundColor(Color("TextMuted"))
                    .padding(.leading, SettingsView.labelWidth * 1.05 + 10)
                    .padding(.top, -4)
            }

            Divider().padding(.vertical, 8)

            SettingsSection {
                SettingsRow(label: "Open pages in tabs instead of windows:") {
                    Picker("", selection: $settings.openPagesInTabs) {
                        ForEach(OpenPagesInTabs.allCases, id: \.rawValue) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                SettingsRow(label: "Clicking a link opens a new tab in the background:") {
                    Toggle("", isOn: $settings.openLinksInBackground)
                        .labelsHidden()
                }

                SettingsRow(label: "Command-Click opens a link in a new tab:") {
                    Toggle("", isOn: $settings.commandClickOpensNewTab)
                        .labelsHidden()
                }
            }
        }
        .padding()
    }
}

// MARK: - Search Section

struct SearchSection: View {
    @ObservedObject var settings: BrowserSettings

    var body: some View {
        Form {
            SettingsRow(label: "Search engine:") {
                Picker("", selection: $settings.searchEngine) {
                    ForEach(SearchEngine.allCases, id: \.rawValue) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }

            Divider().padding(.vertical, 8)

            SettingsRow(label: "Search field:") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Include search engine suggestions", isOn: $settings.includeSearchSuggestions)
                    Toggle("Include Kouke suggestions", isOn: $settings.includeKoukeSuggestions)
                    Toggle("Enable Quick Website Search", isOn: $settings.enableQuickWebsiteSearch)
                    Toggle("Preload Top Hit in the background", isOn: $settings.preloadTopHit)
                    Toggle("Show Favorites", isOn: $settings.showFavoritesInSearch)
                }
            }
        }
        .padding()
    }
}

// MARK: - Privacy Section

struct PrivacySection: View {
    @ObservedObject var settings: BrowserSettings
    @State private var showingClearAlert = false

    var body: some View {
        Form {
            SettingsRow(label: "Website tracking:") {
                Toggle("Prevent cross-site tracking", isOn: $settings.preventCrossSiteTracking)
            }

            SettingsRow(label: "IP address:") {
                Toggle("Hide IP address from trackers", isOn: $settings.hideIPFromTrackers)
            }

            Divider().padding(.vertical, 8)

            SettingsRow(label: "Cookies and website data:") {
                VStack(alignment: .leading) {
                    Toggle("Block all cookies", isOn: $settings.blockAllCookies)

                    HStack {
                        Button("Manage Website Data...") {
                            // Open website data management
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_WebsiteData")!)
                        }

                        Button("Clear History...") {
                            showingClearAlert = true
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding()
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

// MARK: - Advanced Section

struct AdvancedSection: View {
    @ObservedObject var settings: BrowserSettings

    var body: some View {
        Form {
            SettingsRow(label: "Smart Search Field:") {
                Toggle("Show full website address", isOn: $settings.showFullWebsiteAddress)
            }

            SettingsRow(label: "Accessibility:") {
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

            Divider().padding(.vertical, 8)

            SettingsRow(label: "", alignment: .leading) {
                Toggle("Show Develop menu in menu bar", isOn: $settings.showDeveloperMenu)
            }
        }
        .padding()
    }
}

// MARK: - Layout Helpers

struct SettingsSection<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    let alignment: Alignment
    @ViewBuilder let content: Content

    init(label: String, alignment: Alignment = .trailing, @ViewBuilder content: () -> Content) {
        self.label = label
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 13))
                .frame(width: SettingsView.labelWidth * 1.05, alignment: alignment)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 3 } // Micro adjustment

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    SettingsView()
}
