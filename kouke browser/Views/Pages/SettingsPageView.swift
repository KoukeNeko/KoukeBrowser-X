//
//  SettingsPageView.swift
//  kouke browser
//
//  Full-page settings view with sidebar navigation.
//

import SwiftUI
import UniformTypeIdentifiers

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
            case .userScripts:
                UserScriptsSettingsContent()
            case .experiments:
                ExperimentsSettingsContent(settings: settings)
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
    case userScripts
    case experiments
    case advanced

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .tabs: return "Tabs"
        case .search: return "Search"
        case .privacy: return "Privacy"
        case .userScripts: return "User Scripts"
        case .experiments: return "Experiments"
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
        case .userScripts: return "doc.text.below.ecg"
        case .experiments: return "flask"
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
                Text("Drag to reorder buttons. Toggle visibility with the checkbox.")
                    .font(.system(size: 11))
                    .foregroundColor(Color("TextMuted"))
                    .padding(.bottom, 8)

                ToolbarButtonOrderList(settings: settings)

                Divider().padding(.vertical, 4)

                SettingsPageRow(label: "") {
                    Toggle("Always open in separate window from menu/shortcuts", isOn: $settings.alwaysUseSheetForMenuShortcuts)
                }

                Text("When toolbar buttons are visible, clicking them shows a popover. Enable this option to always open a separate window when using menu items or keyboard shortcuts instead.")
                    .font(.system(size: 11))
                    .foregroundColor(Color("TextMuted"))
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Toolbar Button Order List

private struct ToolbarButtonOrderList: View {
    @ObservedObject var settings: BrowserSettings
    @State private var draggingItem: ToolbarButton?

    // Filter out Reader Mode - it's shown automatically based on page content
    private var configurableButtons: [ToolbarButton] {
        settings.toolbarButtonOrder.filter { $0 != .readerMode }
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(configurableButtons) { button in
                ToolbarButtonRow(
                    button: button,
                    isEnabled: isButtonEnabled(button),
                    onToggle: { toggleButton(button) }
                )
                .onDrag {
                    draggingItem = button
                    return NSItemProvider(object: button.rawValue as NSString)
                }
                .onDrop(of: [.text], delegate: ToolbarButtonDropDelegate(
                    item: button,
                    items: $settings.toolbarButtonOrder,
                    draggingItem: $draggingItem
                ))
            }
        }
    }

    private func isButtonEnabled(_ button: ToolbarButton) -> Bool {
        switch button {
        case .readerMode: return true // Always enabled when available
        case .addToFavorites: return settings.showAddToFavoritesButton
        case .downloads: return settings.showDownloadsButton
        case .bookmarks: return settings.showBookmarksButton
        }
    }

    private func toggleButton(_ button: ToolbarButton) {
        switch button {
        case .readerMode: break // Reader mode visibility is automatic
        case .addToFavorites: settings.showAddToFavoritesButton.toggle()
        case .downloads: settings.showDownloadsButton.toggle()
        case .bookmarks: settings.showBookmarksButton.toggle()
        }
    }
}

private struct ToolbarButtonRow: View {
    let button: ToolbarButton
    let isEnabled: Bool
    let onToggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12))
                .foregroundColor(Color("TextMuted").opacity(0.5))

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            Image(systemName: button.icon)
                .font(.system(size: 14))
                .foregroundColor(isEnabled ? Color("Text") : Color("TextMuted"))
                .frame(width: 20)

            Text(button.displayName)
                .font(.system(size: 13))
                .foregroundColor(isEnabled ? Color("Text") : Color("TextMuted"))

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color("TabInactive") : Color("Bg"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color("Border"), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct ToolbarButtonDropDelegate: DropDelegate {
    let item: ToolbarButton
    @Binding var items: [ToolbarButton]
    @Binding var draggingItem: ToolbarButton?

    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggingItem = draggingItem,
              draggingItem != item,
              let fromIndex = items.firstIndex(of: draggingItem),
              let toIndex = items.firstIndex(of: item) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
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

// MARK: - User Scripts Settings Content

private struct UserScriptsSettingsContent: View {
    @StateObject private var scriptManager = UserScriptManager.shared
    @ObservedObject private var settings = BrowserSettings.shared
    @State private var showingAddScript = false
    @State private var editingScript: UserScript?
    @State private var showingImportPicker = false
    @State private var showingDeleteAlert = false
    @State private var scriptToDelete: UserScript?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard(title: "Auto-Detection") {
                SettingsPageRow(label: "") {
                    Toggle("Prompt to install when opening .user.js URLs", isOn: $settings.promptToInstallUserScripts)
                }

                Text("When enabled, Kouke will detect userscript URLs and ask if you want to install them.")
                    .font(.system(size: 11))
                    .foregroundColor(Color("TextMuted"))
                    .padding(.top, 4)
            }

            SettingsCard(title: "Scripts") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("User scripts are custom JavaScript that run on web pages. They can modify page content, add features, or automate tasks.")
                        .font(.system(size: 11))
                        .foregroundColor(Color("TextMuted"))

                    HStack(spacing: 12) {
                        Button("Add Script") {
                            showingAddScript = true
                        }

                        Button("Import...") {
                            showingImportPicker = true
                        }
                    }
                    .padding(.top, 4)
                }
            }

            if scriptManager.scripts.isEmpty {
                SettingsCard(title: "No Scripts") {
                    Text("You haven't added any user scripts yet. Click \"Add Script\" to create one, or \"Import\" to load a .js file.")
                        .font(.system(size: 13))
                        .foregroundColor(Color("TextMuted"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
            } else {
                SettingsCard(title: "Installed Scripts (\(scriptManager.scripts.count))") {
                    VStack(spacing: 8) {
                        ForEach(scriptManager.scripts) { script in
                            UserScriptRow(
                                script: script,
                                onToggle: { scriptManager.toggleScript(script.id) },
                                onEdit: { editingScript = script },
                                onDelete: {
                                    scriptToDelete = script
                                    showingDeleteAlert = true
                                }
                            )
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddScript) {
            UserScriptEditorView(mode: .add)
        }
        .sheet(item: $editingScript) { script in
            UserScriptEditorView(mode: .edit(script))
        }
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.javaScript, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                _ = scriptManager.importScript(from: url)
            }
        }
        .alert("Delete Script", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let script = scriptToDelete {
                    scriptManager.removeScript(script.id)
                }
            }
        } message: {
            if let script = scriptToDelete {
                Text("Are you sure you want to delete \"\(script.name)\"? This cannot be undone.")
            }
        }
    }
}

// MARK: - User Script Row

private struct UserScriptRow: View {
    let script: UserScript
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { script.isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 2) {
                Text(script.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(script.isEnabled ? Color("Text") : Color("TextMuted"))

                Text(script.matchPatterns.joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundColor(Color("TextMuted"))
                    .lineLimit(1)
            }

            Spacer()

            if isHovering {
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color("TextMuted"))

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red.opacity(0.8))
                }
            }

            Text(script.injectionTime.displayName)
                .font(.system(size: 10))
                .foregroundColor(Color("TextMuted"))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color("TabInactive"))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color("TabInactive") : Color("Bg"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color("Border"), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - User Script Editor View

private struct UserScriptEditorView: View {
    enum Mode: Identifiable {
        case add
        case edit(UserScript)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let script): return script.id.uuidString
            }
        }
    }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scriptManager = UserScriptManager.shared

    @State private var name: String = ""
    @State private var source: String = ""
    @State private var isEnabled: Bool = true
    @State private var injectionTime: UserScriptInjectionTime = .documentEnd
    @State private var matchPatternsText: String = "*://*/*"
    @State private var excludePatternsText: String = ""
    @State private var runOnAllFrames: Bool = false

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var existingScript: UserScript? {
        if case .edit(let script) = mode { return script }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Script" : "Add Script")
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isEditing ? "Save" : "Add") {
                    saveScript()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || source.isEmpty)
            }
            .padding(16)
            .background(Color("CardBg"))

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color("TextMuted"))

                        TextField("My Script", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Match Patterns
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Match Patterns (one per line)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color("TextMuted"))

                        TextEditor(text: $matchPatternsText)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(height: 60)
                            .padding(4)
                            .background(Color("Bg"))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color("Border"), lineWidth: 1)
                            )

                        Text("Examples: *://*.example.com/*, https://github.com/*")
                            .font(.system(size: 10))
                            .foregroundColor(Color("TextMuted"))
                    }

                    // Exclude Patterns
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Exclude Patterns (optional, one per line)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color("TextMuted"))

                        TextEditor(text: $excludePatternsText)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(height: 40)
                            .padding(4)
                            .background(Color("Bg"))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color("Border"), lineWidth: 1)
                            )
                    }

                    // Options
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Run At")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color("TextMuted"))

                            Picker("", selection: $injectionTime) {
                                ForEach(UserScriptInjectionTime.allCases, id: \.rawValue) { time in
                                    Text(time.displayName).tag(time)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Options")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color("TextMuted"))

                            HStack {
                                Toggle("Run on all frames", isOn: $runOnAllFrames)
                                    .font(.system(size: 12))

                                Toggle("Enabled", isOn: $isEnabled)
                                    .font(.system(size: 12))
                            }
                        }
                    }

                    // Source Code
                    VStack(alignment: .leading, spacing: 6) {
                        Text("JavaScript Code")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color("TextMuted"))

                        TextEditor(text: $source)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 200)
                            .padding(4)
                            .background(Color("Bg"))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color("Border"), lineWidth: 1)
                            )
                    }
                }
                .padding(20)
            }
            .background(Color("Bg"))
        }
        .frame(width: 600, height: 600)
        .onAppear {
            if let script = existingScript {
                name = script.name
                source = script.source
                isEnabled = script.isEnabled
                injectionTime = script.injectionTime
                matchPatternsText = script.matchPatterns.joined(separator: "\n")
                excludePatternsText = script.excludePatterns.joined(separator: "\n")
                runOnAllFrames = script.runOnAllFrames
            }
        }
    }

    private func saveScript() {
        let matchPatterns = matchPatternsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let excludePatterns = excludePatternsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if let existing = existingScript {
            var updated = existing
            updated.name = name
            updated.source = source
            updated.isEnabled = isEnabled
            updated.injectionTime = injectionTime
            updated.matchPatterns = matchPatterns.isEmpty ? ["*://*/*"] : matchPatterns
            updated.excludePatterns = excludePatterns
            updated.runOnAllFrames = runOnAllFrames
            scriptManager.updateScript(updated)
        } else {
            scriptManager.addScript(
                name: name,
                source: source,
                isEnabled: isEnabled,
                injectionTime: injectionTime,
                matchPatterns: matchPatterns.isEmpty ? ["*://*/*"] : matchPatterns,
                excludePatterns: excludePatterns,
                runOnAllFrames: runOnAllFrames
            )
        }
    }
}

// MARK: - Experiments Settings Content

private struct ExperimentsSettingsContent: View {
    @ObservedObject var settings: BrowserSettings
    @StateObject private var scriptManager = UserScriptManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard(title: "About Experiments") {
                Text("These features are experimental and may not work as expected. They can be changed or removed at any time.")
                    .font(.system(size: 11))
                    .foregroundColor(Color("TextMuted"))
            }

            SettingsCard(title: "YouTube") {
                SettingsPageRow(label: "") {
                    Toggle("Show dislike count on YouTube videos", isOn: $settings.showYouTubeDislike)
                }

                Text("Uses the Return YouTube Dislike API to show dislike counts on YouTube videos. Data is estimated based on extension users and historical data.")
                    .font(.system(size: 11))
                    .foregroundColor(Color("TextMuted"))
                    .padding(.top, 4)

                if settings.showYouTubeDislike, let script = scriptManager.getYouTubeDislikeScript() {
                    Divider()
                        .padding(.vertical, 4)

                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(script.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color("Text"))

                            Text("Matches: \(script.matchPatterns.joined(separator: ", "))")
                                .font(.system(size: 10))
                                .foregroundColor(Color("TextMuted"))
                        }

                        Spacer()

                        Text("Active")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .padding(.top, 4)

                    Text("Reload YouTube tabs to apply changes.")
                        .font(.system(size: 10))
                        .foregroundColor(Color("TextMuted"))
                        .padding(.top, 4)
                }
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
