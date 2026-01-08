//
//  HelpPageView.swift
//  kouke browser
//
//  Full-page help view with sidebar navigation.
//

import SwiftUI

// MARK: - Help Page View

struct HelpPageView: View {
    @State private var selectedSection: HelpSidebarSection = .gettingStarted

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

            ForEach(HelpSidebarSection.allCases, id: \.self) { section in
                HelpSidebarButton(
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
            case .gettingStarted:
                GettingStartedContent()
            case .navigation:
                NavigationHelpContent()
            case .tabs:
                TabsHelpContent()
            case .bookmarks:
                BookmarksHelpContent()
            case .downloads:
                DownloadsHelpContent()
            case .privacy:
                PrivacyHelpContent()
            case .shortcuts:
                ShortcutsHelpContent()
            case .about:
                AboutHelpContent()
            }

            Spacer()
        }
    }
}

// MARK: - Help Sections Enum

private enum HelpSidebarSection: CaseIterable {
    case gettingStarted
    case navigation
    case tabs
    case bookmarks
    case downloads
    case privacy
    case shortcuts
    case about

    var title: String {
        switch self {
        case .gettingStarted: return "Getting Started"
        case .navigation: return "Navigation"
        case .tabs: return "Tabs"
        case .bookmarks: return "Bookmarks"
        case .downloads: return "Downloads"
        case .privacy: return "Privacy"
        case .shortcuts: return "Keyboard Shortcuts"
        case .about: return "About Kouke"
        }
    }

    var icon: String {
        switch self {
        case .gettingStarted: return "star"
        case .navigation: return "arrow.left.arrow.right"
        case .tabs: return "square.on.square"
        case .bookmarks: return "bookmark"
        case .downloads: return "arrow.down.circle"
        case .privacy: return "hand.raised"
        case .shortcuts: return "keyboard"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Sidebar Button

private struct HelpSidebarButton: View {
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

// MARK: - Getting Started Content

private struct GettingStartedContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HelpCard(title: "Welcome to Kouke Browser") {
                Text("Kouke is a fast, lightweight browser built for macOS. Here's how to get started:")
                    .font(.system(size: 13))
                    .foregroundColor(Color("Text"))
                    .padding(.bottom, 8)

                HelpStep(number: 1, title: "Enter a URL or Search", description: "Click the address bar and type a website URL or search query.")
                HelpStep(number: 2, title: "Navigate Pages", description: "Use the back and forward buttons to move between pages you've visited.")
                HelpStep(number: 3, title: "Manage Tabs", description: "Click the + button to open new tabs, or click a tab to switch to it.")
                HelpStep(number: 4, title: "Customize Settings", description: "Visit kouke:settings to personalize your browsing experience.")
            }

            HelpCard(title: "Quick Tips") {
                HelpTip(icon: "magnifyingglass", text: "Press ⌘L to quickly focus the address bar")
                HelpTip(icon: "plus", text: "Press ⌘T to open a new tab")
                HelpTip(icon: "arrow.clockwise", text: "Press ⌘R to reload the current page")
                HelpTip(icon: "star", text: "Press ⌘D to bookmark the current page")
            }
        }
    }
}

// MARK: - Navigation Help Content

private struct NavigationHelpContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HelpCard(title: "Address Bar") {
                Text("The address bar lets you enter URLs and search queries. It shows the current page's address and security status.")
                    .font(.system(size: 13))
                    .foregroundColor(Color("Text"))
                    .padding(.bottom, 8)

                HelpFeature(title: "Smart Search", description: "Type a search query and Kouke will use your default search engine.")
                HelpFeature(title: "URL Completion", description: "Start typing a URL and Kouke will suggest matching sites from your history.")
                HelpFeature(title: "Security Indicator", description: "A lock icon appears for secure (HTTPS) websites.")
            }

            HelpCard(title: "Navigation Controls") {
                HelpFeature(title: "Back/Forward", description: "Click the arrow buttons or use ⌘[ and ⌘] to navigate your history.")
                HelpFeature(title: "Reload", description: "Click the reload button or press ⌘R to refresh the page.")
                HelpFeature(title: "Stop", description: "Click the X button while loading to stop the page from loading.")
            }
        }
    }
}

// MARK: - Tabs Help Content

private struct TabsHelpContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HelpCard(title: "Working with Tabs") {
                HelpFeature(title: "New Tab", description: "Click the + button or press ⌘T to open a new tab.")
                HelpFeature(title: "Close Tab", description: "Click the X on a tab or press ⌘W to close it.")
                HelpFeature(title: "Switch Tabs", description: "Click a tab to switch to it, or use ⌘1-9 for quick access.")
                HelpFeature(title: "Reorder Tabs", description: "Drag tabs left or right to reorder them.")
                HelpFeature(title: "Move to New Window", description: "Drag a tab outside the window to open it in a new window.")
            }

            HelpCard(title: "Tab Styles") {
                Text("Kouke offers two tab styles:")
                    .font(.system(size: 13))
                    .foregroundColor(Color("Text"))
                    .padding(.bottom, 8)

                HelpFeature(title: "Normal", description: "Traditional tab bar with a separate address bar below.")
                HelpFeature(title: "Compact", description: "Tabs and address bar combined in a single row for more screen space.")

                Text("Change your tab style in Settings > Tabs.")
                    .font(.system(size: 12))
                    .foregroundColor(Color("TextMuted"))
                    .padding(.top, 8)
            }
        }
    }
}

// MARK: - Bookmarks Help Content

private struct BookmarksHelpContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HelpCard(title: "Managing Bookmarks") {
                HelpFeature(title: "Add Bookmark", description: "Press ⌘D or click the bookmark button to save the current page.")
                HelpFeature(title: "View Bookmarks", description: "Click the bookmarks button in the toolbar or press ⌘⌥B.")
                HelpFeature(title: "Organize", description: "Create folders to organize your bookmarks by category.")
                HelpFeature(title: "Edit/Delete", description: "Right-click a bookmark to edit or delete it.")
            }

            HelpCard(title: "Favorites Bar") {
                Text("Your most-used bookmarks can appear in the favorites bar for quick access. Enable it in Settings > Appearance.")
                    .font(.system(size: 13))
                    .foregroundColor(Color("Text"))
            }
        }
    }
}

// MARK: - Downloads Help Content

private struct DownloadsHelpContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HelpCard(title: "Downloading Files") {
                HelpFeature(title: "Start Download", description: "Click a download link or right-click and select 'Download Linked File'.")
                HelpFeature(title: "View Downloads", description: "Click the downloads button in the toolbar to see your downloads.")
                HelpFeature(title: "Open File", description: "Click a completed download to open it.")
                HelpFeature(title: "Show in Finder", description: "Right-click a download and select 'Show in Finder'.")
            }

            HelpCard(title: "Download Settings") {
                Text("Configure where downloads are saved and how they're handled in Settings > General.")
                    .font(.system(size: 13))
                    .foregroundColor(Color("Text"))
            }
        }
    }
}

// MARK: - Privacy Help Content

private struct PrivacyHelpContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HelpCard(title: "Privacy Features") {
                HelpFeature(title: "Tracking Prevention", description: "Kouke blocks cross-site trackers to protect your privacy.")
                HelpFeature(title: "Cookie Control", description: "Manage which websites can store cookies on your device.")
                HelpFeature(title: "Clear Data", description: "Clear your browsing history, cookies, and cache at any time.")
            }

            HelpCard(title: "Secure Browsing") {
                HelpFeature(title: "HTTPS", description: "Kouke automatically uses secure connections when available.")
                HelpFeature(title: "Certificate Info", description: "Click the lock icon in the address bar to view site security details.")
            }
        }
    }
}

// MARK: - Shortcuts Help Content

private struct ShortcutsHelpContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HelpCard(title: "General") {
                ShortcutRow(keys: "⌘N", action: "New Window")
                ShortcutRow(keys: "⌘T", action: "New Tab")
                ShortcutRow(keys: "⌘W", action: "Close Tab")
                ShortcutRow(keys: "⌘Q", action: "Quit Kouke")
                ShortcutRow(keys: "⌘,", action: "Open Settings")
            }

            HelpCard(title: "Navigation") {
                ShortcutRow(keys: "⌘L", action: "Focus Address Bar")
                ShortcutRow(keys: "⌘R", action: "Reload Page")
                ShortcutRow(keys: "⌘⇧R", action: "Force Reload (no cache)")
                ShortcutRow(keys: "⌘[", action: "Go Back")
                ShortcutRow(keys: "⌘]", action: "Go Forward")
                ShortcutRow(keys: "⌘↵", action: "Open URL in New Tab")
            }

            HelpCard(title: "Tabs") {
                ShortcutRow(keys: "⌘1-9", action: "Switch to Tab 1-9")
                ShortcutRow(keys: "⌘⇧[", action: "Previous Tab")
                ShortcutRow(keys: "⌘⇧]", action: "Next Tab")
                ShortcutRow(keys: "⌘⇧T", action: "Reopen Closed Tab")
            }

            HelpCard(title: "View") {
                ShortcutRow(keys: "⌘+", action: "Zoom In")
                ShortcutRow(keys: "⌘-", action: "Zoom Out")
                ShortcutRow(keys: "⌘0", action: "Reset Zoom")
                ShortcutRow(keys: "⌘⌃F", action: "Toggle Full Screen")
            }

            HelpCard(title: "Bookmarks") {
                ShortcutRow(keys: "⌘D", action: "Bookmark Current Page")
                ShortcutRow(keys: "⌘⌥B", action: "Show Bookmarks")
            }

            HelpCard(title: "Developer") {
                ShortcutRow(keys: "⌘⌥I", action: "Open Developer Tools")
                ShortcutRow(keys: "⌘⌥U", action: "View Page Source")
            }
        }
    }
}

// MARK: - About Help Content

private struct AboutHelpContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HelpCard(title: "About Kouke Browser") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "globe")
                            .font(.system(size: 48))
                            .foregroundColor(Color("AccentColor"))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Kouke Browser")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(Color("Text"))

                            Text("Version 1.0")
                                .font(.system(size: 13))
                                .foregroundColor(Color("TextMuted"))
                        }
                    }
                    .padding(.bottom, 8)

                    Text("A fast, lightweight browser built for macOS with privacy in mind.")
                        .font(.system(size: 13))
                        .foregroundColor(Color("Text"))
                }
            }

            HelpCard(title: "Special Pages") {
                HelpFeature(title: "kouke:home", description: "Your homepage with quick access to favorites.")
                HelpFeature(title: "kouke:settings", description: "Customize your browser settings.")
                HelpFeature(title: "kouke:help", description: "View this help page.")
                HelpFeature(title: "kouke:history", description: "Browse your browsing history.")
                HelpFeature(title: "kouke:bookmarks", description: "Manage all your bookmarks.")
            }

            HelpCard(title: "Feedback & Support") {
                Text("Have a question or found a bug? We'd love to hear from you!")
                    .font(.system(size: 13))
                    .foregroundColor(Color("Text"))
                    .padding(.bottom, 8)

                Button("Visit Support Website") {
                    if let url = URL(string: "https://github.com/user/kouke-browser") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Help Card

private struct HelpCard<Content: View>: View {
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

// MARK: - Help Components

private struct HelpStep: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color("AccentColor")))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color("Text"))

                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(Color("TextMuted"))
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HelpTip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(Color("AccentColor"))
                .frame(width: 20)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Color("Text"))

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct HelpFeature: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color("Text"))

            Text(description)
                .font(.system(size: 12))
                .foregroundColor(Color("TextMuted"))
        }
        .padding(.vertical, 4)
    }
}

private struct ShortcutRow: View {
    let keys: String
    let action: String

    var body: some View {
        HStack {
            Text(keys)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(Color("Text"))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color("TabInactive"))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(width: 80, alignment: .leading)

            Text(action)
                .font(.system(size: 13))
                .foregroundColor(Color("TextMuted"))

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    HelpPageView()
        .frame(width: 900, height: 600)
}
