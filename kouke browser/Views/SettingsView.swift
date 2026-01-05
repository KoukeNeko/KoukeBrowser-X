//
//  SettingsView.swift
//  kouke browser
//
//  Settings page with Safari-style toolbar and layout.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = BrowserSettings.shared

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

            AdvancedSection()
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
                SettingsRow(label: "Safari opens with:") {
                    Picker("", selection: $settings.startupBehavior) {
                        ForEach(StartupBehavior.allCases, id: \.rawValue) { behavior in
                            Text(behavior.displayName).tag(behavior)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                if settings.startupBehavior == .customURL {
                    SettingsRow(label: "Homepage:") {
                        TextField("https://example.com", text: $settings.startupURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                    }
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
                    .pickerStyle(.menu) // Safari uses a menu often, or segmented.
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
                     Picker("", selection: .constant("Downloads")) {
                        Text("Downloads").tag("Downloads")
                        Text("Ask for each file").tag("Ask")
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                SettingsRow(label: "Remove download list items:") {
                     Picker("", selection: .constant("After one day")) {
                        Text("After one day").tag("After one day")
                        Text("When Safari quits").tag("Quit")
                        Text("Upon successful download").tag("Success")
                        Text("Manually").tag("Manually")
                    }
                    .labelsHidden()
                    .frame(width: 200)
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

            Divider().padding(.vertical, 8)

            SettingsSection {
                SettingsRow(label: "Open pages in tabs instead of windows:") {
                     Picker("", selection: .constant("Automatically")) {
                        Text("Never").tag("Never")
                        Text("Automatically").tag("Automatically")
                        Text("Always").tag("Always")
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                SettingsRow(label: "Clicking a link opens a new tab in the background:") {
                     Toggle("", isOn: .constant(false))
                        .labelsHidden()
                }

                SettingsRow(label: "Command-Click opens a link in a new tab:") {
                     Toggle("", isOn: .constant(true))
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
                    Toggle("Include search engine suggestions", isOn: .constant(true))
                    Toggle("Include Safari suggestions", isOn: .constant(true))
                    Toggle("Enable Quick Website Search", isOn: .constant(true))
                    Toggle("Preload Top Hit in the background", isOn: .constant(true))
                    Toggle("Show Favorites", isOn: .constant(true))
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
                Toggle("Prevent cross-site tracking", isOn: .constant(true))
            }

            SettingsRow(label: "IP address:") {
                Toggle("Hide IP address from trackers", isOn: .constant(false))
            }

            Divider().padding(.vertical, 8)

            SettingsRow(label: "Cookies and website data:") {
                VStack(alignment: .leading) {
                     Toggle("Block all cookies", isOn: .constant(false))

                    HStack {
                        Button("Manage Website Data...") {
                            // Action
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
            }
        } message: {
            Text("This will clear all browsing history, cookies, and cached data.")
        }
    }
}

// MARK: - Advanced Section

struct AdvancedSection: View {
    var body: some View {
        Form {
            SettingsRow(label: "Smart Search Field:") {
                 Toggle("Show full website address", isOn: .constant(false))
            }

            SettingsRow(label: "Accessibility:") {
                 Toggle("Never use font sizes smaller than", isOn: .constant(false))
            }

            Divider().padding(.vertical, 8)

            SettingsRow(label: "", alignment: .leading) {
                 Toggle("Show Develop menu in menu bar", isOn: .constant(true))
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
