//
//  SettingsPageView.swift
//  kouke browser
//
//  Full-page settings view with sidebar navigation.
//

import SwiftUI

// MARK: - Settings Page View

struct SettingsPageView: View {
    @StateObject private var settings = BrowserSettings.shared
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
            case .tabs:
                TabsSettingsContent(settings: settings)
            case .search:
                SearchSettingsContent(settings: settings)
            case .privacy:
                PrivacySettingsContent(settings: settings)
            case .advanced:
                AdvancedSettingsContent()
            }

            Spacer()
        }
    }
}

// MARK: - Settings Sections Enum

private enum SettingsSidebarSection: CaseIterable {
    case general
    case tabs
    case search
    case privacy
    case advanced

    var title: String {
        switch self {
        case .general: return "General"
        case .tabs: return "Tabs"
        case .search: return "Search"
        case .privacy: return "Privacy"
        case .advanced: return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
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
                    .fill(isSelected ? Color("TabActive") : (isHovering ? Color("TabHover") : Color.clear))
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

                if settings.startupBehavior == .customURL {
                    SettingsPageRow(label: "Homepage:") {
                        TextField("https://example.com", text: $settings.startupURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                    }
                }
            }

            // Appearance
            SettingsCard(title: "Appearance") {
                SettingsPageRow(label: "Theme:") {
                    Picker("", selection: $settings.theme) {
                        ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }

                SettingsPageRow(label: "Default font size:") {
                    Picker("", selection: $settings.fontSize) {
                        ForEach([12, 13, 14, 15, 16, 18, 20, 24], id: \.self) { size in
                            Text("\(size)").tag(size)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)
                }
            }

            // Downloads
            SettingsCard(title: "Downloads") {
                SettingsPageRow(label: "Save files to:") {
                    Picker("", selection: .constant("Downloads")) {
                        Text("Downloads").tag("Downloads")
                        Text("Ask for each file").tag("Ask")
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                SettingsPageRow(label: "Remove items:") {
                    Picker("", selection: .constant("After one day")) {
                        Text("After one day").tag("After one day")
                        Text("When Kouke quits").tag("Quit")
                        Text("Upon successful download").tag("Success")
                        Text("Manually").tag("Manually")
                    }
                    .labelsHidden()
                    .frame(width: 200)
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
                    Picker("", selection: .constant("Automatically")) {
                        Text("Never").tag("Never")
                        Text("Automatically").tag("Automatically")
                        Text("Always").tag("Always")
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                SettingsPageRow(label: "") {
                    Toggle("Open links in background", isOn: .constant(false))
                }

                SettingsPageRow(label: "") {
                    Toggle("⌘-Click opens in new tab", isOn: .constant(true))
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
                    Toggle("Include search engine suggestions", isOn: .constant(true))
                    Toggle("Include Kouke suggestions", isOn: .constant(true))
                    Toggle("Enable Quick Website Search", isOn: .constant(true))
                    Toggle("Preload Top Hit in background", isOn: .constant(true))
                    Toggle("Show Favorites", isOn: .constant(true))
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
                    Toggle("Prevent cross-site tracking", isOn: .constant(true))
                }

                SettingsPageRow(label: "") {
                    Toggle("Hide IP address from trackers", isOn: .constant(false))
                }
            }

            SettingsCard(title: "Cookies & Data") {
                SettingsPageRow(label: "") {
                    Toggle("Block all cookies", isOn: .constant(false))
                }

                HStack(spacing: 12) {
                    Button("Manage Website Data...") {
                        // Action
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
                }
            } message: {
                Text("This will clear all browsing history, cookies, and cached data.")
            }
        }
    }
}

// MARK: - Advanced Settings Content

private struct AdvancedSettingsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard(title: "Address Bar") {
                SettingsPageRow(label: "") {
                    Toggle("Show full website address", isOn: .constant(false))
                }
            }

            SettingsCard(title: "Accessibility") {
                SettingsPageRow(label: "") {
                    Toggle("Never use font sizes smaller than 9", isOn: .constant(false))
                }
            }

            SettingsCard(title: "Developer") {
                SettingsPageRow(label: "") {
                    Toggle("Show Develop menu in menu bar", isOn: .constant(true))
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
