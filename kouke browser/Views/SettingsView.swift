//
//  SettingsView.swift
//  kouke browser
//
//  Settings page with sidebar navigation and sections.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = BrowserSettings.shared
    @State private var activeSection = "appearance"
    
    private let sections: [(id: String, label: String, icon: String)] = [
        ("appearance", "Appearance", "paintbrush.fill"),
        ("search", "Search", "magnifyingglass"),
        ("startup", "Startup", "power"),
        ("privacy", "Privacy", "hand.raised.fill"),
        ("about", "About", "info.circle.fill"),
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                    Text("Settings")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundColor(Color("Text"))
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                
                ForEach(sections, id: \.id) { section in
                    SidebarItem(
                        label: section.label,
                        icon: section.icon,
                        isActive: activeSection == section.id,
                        action: { activeSection = section.id }
                    )
                    .cornerRadius(4) // Minimal rounding
                }
                
                Spacer()
            }
            .frame(width: 200)
            .background(Color("TitleBarBg"))
            
            // Divider
            Rectangle()
                .fill(Color("Border"))
                .frame(width: 1)
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch activeSection {
                    case "appearance":
                        AppearanceSection(settings: settings)
                    case "search":
                        SearchSection(settings: settings)
                    case "startup":
                        StartupSection(settings: settings)
                    case "privacy":
                        PrivacySection(settings: settings)
                    case "about":
                        AboutSection()
                    default:
                        EmptyView()
                    }
                }
                .padding(32)
                .frame(maxWidth: 600, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color("Bg"))
        }
    }
}

// MARK: - Sidebar Item

struct SidebarItem: View {
    let label: String
    let icon: String
    let isActive: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 14))
                Spacer()
                if isActive {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .foregroundColor(isActive ? Color("Text") : Color("TextMuted"))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                isActive ? Color("AccentHover") : 
                isHovering ? Color("AccentHover").opacity(0.5) : Color.clear
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Appearance Section

struct AppearanceSection: View {
    @ObservedObject var settings: BrowserSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Appearance")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color("Text"))
            
            // Theme
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Theme")
                
                HStack(spacing: 16) {
                    ThemeButton(
                        theme: .dark,
                        isSelected: settings.theme == .dark,
                        action: { settings.theme = .dark }
                    )
                    ThemeButton(
                        theme: .light,
                        isSelected: settings.theme == .light,
                        action: { settings.theme = .light }
                    )
                }
            }
            
            // Font Size
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Font Size")
                
                Picker("Font Size", selection: $settings.fontSize) {
                    ForEach([12, 13, 14, 15, 16, 18, 20, 24], id: \.self) { size in
                        Text("\(size)px").tag(size)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
        }
    }
}

struct ThemeButton: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme == .dark ? Color(white: 0.15) : Color(white: 0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(white: 0.5), lineWidth: 1)
                    )
                    .frame(width: 80, height: 56)
                
                Text(theme.displayName)
                    .font(.system(size: 14))
                    .foregroundColor(Color("Text"))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.blue : Color("Border"), lineWidth: 2)
            )
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search Section

struct SearchSection: View {
    @ObservedObject var settings: BrowserSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Search")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color("Text"))
            
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Default Search Engine")
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(SearchEngine.allCases, id: \.rawValue) { engine in
                        SearchEngineRow(
                            engine: engine,
                            isSelected: settings.searchEngine == engine,
                            action: { settings.searchEngine = engine }
                        )
                    }
                }
            }
        }
    }
}

struct SearchEngineRow: View {
    let engine: SearchEngine
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : Color("TextMuted"))
                Text(engine.displayName)
                    .foregroundColor(Color("Text"))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Startup Section

struct StartupSection: View {
    @ObservedObject var settings: BrowserSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Startup")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color("Text"))
            
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "On Startup")
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(StartupBehavior.allCases, id: \.rawValue) { behavior in
                        StartupRow(
                            behavior: behavior,
                            isSelected: settings.startupBehavior == behavior,
                            action: { settings.startupBehavior = behavior }
                        )
                    }
                }
                
                if settings.startupBehavior == .customURL {
                    TextField("Enter URL", text: $settings.startupURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 400)
                        .padding(.top, 8)
                }
            }
        }
    }
}

struct StartupRow: View {
    let behavior: StartupBehavior
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : Color("TextMuted"))
                Text(behavior.displayName)
                    .foregroundColor(Color("Text"))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Privacy Section

struct PrivacySection: View {
    @ObservedObject var settings: BrowserSettings
    @State private var showingAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Privacy")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color("Text"))
            
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Browsing Data")
                
                Button(action: { showingAlert = true }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear Browsing Data")
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red.opacity(0.5), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .alert("Clear Browsing Data", isPresented: $showingAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Clear", role: .destructive) {
                        settings.clearBrowsingData()
                    }
                } message: {
                    Text("This will clear all browsing history, cookies, and cached data. This action cannot be undone.")
                }
            }
        }
    }
}

// MARK: - About Section

struct AboutSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("About")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color("Text"))
            
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Image(systemName: "globe")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("kouke browser")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color("Text"))
                        Text("Version 1.0.0")
                            .font(.system(size: 14))
                            .foregroundColor(Color("TextMuted"))
                    }
                }
                
                Divider()
                
                Text("A lightweight, privacy-focused browser.")
                    .font(.system(size: 14))
                    .foregroundColor(Color("TextMuted"))
            }
        }
    }
}

// MARK: - Helpers

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Color("TextMuted"))
            .textCase(.uppercase)
            .kerning(0.5)
    }
}

#Preview {
    SettingsView()
        .frame(width: 800, height: 600)
}
