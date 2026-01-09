//
//  UserScriptManager.swift
//  kouke browser
//
//  Manages user script storage and operations.
//

import Foundation
import Combine
import WebKit

@MainActor
class UserScriptManager: ObservableObject {
    static let shared = UserScriptManager()

    @Published private(set) var scripts: [UserScript] = []

    /// Built-in experimental scripts (not shown in user scripts list)
    @Published private(set) var experimentalScripts: [UserScript] = []

    private let scriptsKey = "userScripts"
    private let defaults = UserDefaults.standard

    /// ID for the YouTube Dislike script
    static let youTubeDislikeScriptId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// ID for the SponsorBlock script
    static let sponsorBlockScriptId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private init() {
        loadScripts()
        setupExperimentalScripts()
        observeSettings()
    }

    private func observeSettings() {
        NotificationCenter.default.addObserver(
            forName: .youTubeDislikeSettingChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateYouTubeDislikeScript()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .sponsorBlockSettingChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateSponsorBlockScript()
            }
        }
    }

    private func setupExperimentalScripts() {
        updateYouTubeDislikeScript()
        updateSponsorBlockScript()
    }

    private func updateYouTubeDislikeScript() {
        let isEnabled = BrowserSettings.shared.showYouTubeDislike

        // Remove existing YouTube Dislike script
        experimentalScripts.removeAll { $0.id == Self.youTubeDislikeScriptId }

        if isEnabled {
            let script = UserScript(
                id: Self.youTubeDislikeScriptId,
                name: "Return YouTube Dislike",
                source: YouTubeDislikeService.getUserScript(),
                isEnabled: true,
                injectionTime: .documentEnd,
                matchPatterns: ["*://*.youtube.com/*"],
                excludePatterns: ["*://music.youtube.com/*"],
                runOnAllFrames: false
            )
            experimentalScripts.append(script)
        }

        notifyScriptsChanged()
    }

    /// Get the YouTube Dislike script if enabled
    func getYouTubeDislikeScript() -> UserScript? {
        experimentalScripts.first { $0.id == Self.youTubeDislikeScriptId }
    }

    private func updateSponsorBlockScript() {
        let isEnabled = BrowserSettings.shared.enableSponsorBlock

        // Remove existing SponsorBlock script
        experimentalScripts.removeAll { $0.id == Self.sponsorBlockScriptId }

        if isEnabled {
            let script = UserScript(
                id: Self.sponsorBlockScriptId,
                name: "SponsorBlock",
                source: SponsorBlockService.getUserScript(),
                isEnabled: true,
                injectionTime: .documentEnd,
                matchPatterns: ["*://*.youtube.com/*"],
                excludePatterns: ["*://music.youtube.com/*"],
                runOnAllFrames: false
            )
            experimentalScripts.append(script)
        }

        notifyScriptsChanged()
    }

    /// Get the SponsorBlock script if enabled
    func getSponsorBlockScript() -> UserScript? {
        experimentalScripts.first { $0.id == Self.sponsorBlockScriptId }
    }

    // MARK: - Script Operations

    func addScript(_ script: UserScript) {
        scripts.append(script)
        saveScripts()
        notifyScriptsChanged()
    }

    func addScript(
        name: String,
        source: String,
        isEnabled: Bool = true,
        injectionTime: UserScriptInjectionTime = .documentEnd,
        matchPatterns: [String] = ["*://*/*"],
        excludePatterns: [String] = [],
        runOnAllFrames: Bool = false
    ) {
        let script = UserScript(
            name: name,
            source: source,
            isEnabled: isEnabled,
            injectionTime: injectionTime,
            matchPatterns: matchPatterns,
            excludePatterns: excludePatterns,
            runOnAllFrames: runOnAllFrames
        )
        addScript(script)
    }

    func removeScript(_ id: UUID) {
        scripts.removeAll { $0.id == id }
        saveScripts()
        notifyScriptsChanged()
    }

    func updateScript(_ script: UserScript) {
        guard let index = scripts.firstIndex(where: { $0.id == script.id }) else { return }
        var updatedScript = script
        updatedScript.dateModified = Date()
        scripts[index] = updatedScript
        saveScripts()
        notifyScriptsChanged()
    }

    func toggleScript(_ id: UUID) {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        scripts[index].isEnabled.toggle()
        scripts[index].dateModified = Date()
        saveScripts()
        notifyScriptsChanged()
    }

    func getScript(_ id: UUID) -> UserScript? {
        scripts.first { $0.id == id }
    }

    // MARK: - Script Matching

    /// Get all enabled scripts that should run on the given URL
    func scriptsForURL(_ url: URL) -> [UserScript] {
        scripts.filter { $0.shouldRun(on: url) }
    }

    /// Get scripts grouped by injection time for a URL
    func scriptsGroupedByInjectionTime(for url: URL) -> [UserScriptInjectionTime: [UserScript]] {
        var result: [UserScriptInjectionTime: [UserScript]] = [:]
        for script in scriptsForURL(url) {
            result[script.injectionTime, default: []].append(script)
        }
        return result
    }

    // MARK: - WebView Integration

    /// Apply user scripts to a WKUserContentController for the given URL
    func applyScripts(to contentController: WKUserContentController, for url: URL) {
        let matchingScripts = scriptsForURL(url)
        for script in matchingScripts {
            contentController.addUserScript(script.toWKUserScript())
        }
    }

    /// Get all enabled scripts (for pre-loading into WebView configuration)
    func allEnabledScripts() -> [UserScript] {
        let userScripts = scripts.filter { $0.isEnabled }
        let expScripts = experimentalScripts.filter { $0.isEnabled }
        return userScripts + expScripts
    }

    // MARK: - Persistence

    private func saveScripts() {
        if let data = try? JSONEncoder().encode(scripts) {
            defaults.set(data, forKey: scriptsKey)
        }
    }

    private func loadScripts() {
        guard let data = defaults.data(forKey: scriptsKey),
              let loaded = try? JSONDecoder().decode([UserScript].self, from: data) else {
            return
        }
        scripts = loaded
    }

    // MARK: - Import/Export

    func exportScripts() -> Data? {
        try? JSONEncoder().encode(scripts)
    }

    func importScripts(from data: Data) {
        guard let imported = try? JSONDecoder().decode([UserScript].self, from: data) else {
            return
        }

        for script in imported {
            // Check for duplicate by name
            if !scripts.contains(where: { $0.name == script.name }) {
                scripts.append(script)
            }
        }

        saveScripts()
        notifyScriptsChanged()
    }

    func importScript(from fileURL: URL) -> UserScript? {
        guard fileURL.startAccessingSecurityScopedResource() else {
            return nil
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }

        guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        // Parse userscript metadata from the source
        let metadata = parseUserScriptMetadata(from: source)

        let name = metadata.name ?? fileURL.deletingPathExtension().lastPathComponent
        let script = UserScript(
            name: name,
            source: source,
            isEnabled: true,
            injectionTime: metadata.runAt,
            matchPatterns: metadata.match.isEmpty ? ["*://*/*"] : metadata.match,
            excludePatterns: metadata.exclude,
            runOnAllFrames: metadata.runOnAllFrames
        )
        addScript(script)
        return script
    }

    // MARK: - Userscript Metadata Parsing

    /// Parsed metadata from userscript header block
    struct UserScriptMetadata {
        var name: String?
        var match: [String] = []
        var exclude: [String] = []
        var include: [String] = []
        var require: [String] = []  // URLs of required scripts
        var runAt: UserScriptInjectionTime = .documentEnd
        var runOnAllFrames: Bool = false
    }

    /// Parse userscript metadata block (// ==UserScript== ... // ==/UserScript==)
    func parseUserScriptMetadata(from source: String) -> UserScriptMetadata {
        var metadata = UserScriptMetadata()

        // Find metadata block
        guard let startRange = source.range(of: "// ==UserScript=="),
              let endRange = source.range(of: "// ==/UserScript==") else {
            return metadata
        }

        let metadataBlock = String(source[startRange.upperBound..<endRange.lowerBound])
        let lines = metadataBlock.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("//") else { continue }

            let content = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)

            // Parse @directive value
            if content.hasPrefix("@") {
                // Split on any whitespace (space or tab), not just space
                let directiveContent = content.dropFirst()
                let parts = directiveContent.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
                guard let directive = parts.first else { continue }
                let value = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

                switch String(directive).lowercased() {
                case "name":
                    metadata.name = value
                case "match":
                    if !value.isEmpty {
                        metadata.match.append(value)
                    }
                case "exclude", "exclude-match":
                    if !value.isEmpty {
                        metadata.exclude.append(value)
                    }
                case "include":
                    if !value.isEmpty {
                        metadata.include.append(value)
                    }
                case "require":
                    if !value.isEmpty {
                        metadata.require.append(value)
                    }
                case "run-at":
                    if value.contains("document-start") {
                        metadata.runAt = .documentStart
                    } else {
                        metadata.runAt = .documentEnd
                    }
                case "noframes":
                    metadata.runOnAllFrames = false
                case "allframes":
                    metadata.runOnAllFrames = true
                default:
                    break
                }
            }
        }

        // If no @match but has @include, use @include as match patterns
        if metadata.match.isEmpty && !metadata.include.isEmpty {
            metadata.match = metadata.include
        }

        return metadata
    }

    // MARK: - Notifications

    private func notifyScriptsChanged() {
        NotificationCenter.default.post(name: .userScriptsChanged, object: nil)
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let userScriptsChanged = Notification.Name("userScriptsChanged")
}
