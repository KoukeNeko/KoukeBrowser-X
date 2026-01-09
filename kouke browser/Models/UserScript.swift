//
//  UserScript.swift
//  kouke browser
//
//  User script model for custom JavaScript injection.
//

import Foundation
import WebKit

/// Represents when a user script should be injected
enum UserScriptInjectionTime: String, Codable, CaseIterable {
    case documentStart = "document_start"
    case documentEnd = "document_end"

    var displayName: String {
        switch self {
        case .documentStart: return "Document Start"
        case .documentEnd: return "Document End"
        }
    }

    var wkInjectionTime: WKUserScriptInjectionTime {
        switch self {
        case .documentStart: return .atDocumentStart
        case .documentEnd: return .atDocumentEnd
        }
    }
}

/// Represents a user-defined JavaScript to inject into web pages
struct UserScript: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var source: String
    var isEnabled: Bool
    var injectionTime: UserScriptInjectionTime
    var matchPatterns: [String]  // URL patterns to match (e.g., "*://*.example.com/*")
    var excludePatterns: [String]  // URL patterns to exclude
    var runOnAllFrames: Bool
    var dateCreated: Date
    var dateModified: Date

    init(
        id: UUID = UUID(),
        name: String,
        source: String,
        isEnabled: Bool = true,
        injectionTime: UserScriptInjectionTime = .documentEnd,
        matchPatterns: [String] = ["*://*/*"],
        excludePatterns: [String] = [],
        runOnAllFrames: Bool = false,
        dateCreated: Date = Date(),
        dateModified: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.isEnabled = isEnabled
        self.injectionTime = injectionTime
        self.matchPatterns = matchPatterns
        self.excludePatterns = excludePatterns
        self.runOnAllFrames = runOnAllFrames
        self.dateCreated = dateCreated
        self.dateModified = dateModified
    }

    /// Check if this script should run on the given URL
    func shouldRun(on url: URL) -> Bool {
        guard isEnabled else { return false }

        let urlString = url.absoluteString

        // Check exclude patterns first
        for pattern in excludePatterns {
            if matchesPattern(urlString: urlString, pattern: pattern) {
                return false
            }
        }

        // Check match patterns
        for pattern in matchPatterns {
            if matchesPattern(urlString: urlString, pattern: pattern) {
                return true
            }
        }

        return false
    }

    /// Match URL against a simple glob-like pattern
    /// Supports: * (any characters), ? (single character)
    /// Pattern format: scheme://host/path (e.g., *://*.example.com/*)
    private func matchesPattern(urlString: String, pattern: String) -> Bool {
        // Handle special "all URLs" pattern
        if pattern == "<all_urls>" || pattern == "*://*/*" {
            return urlString.hasPrefix("http://") || urlString.hasPrefix("https://")
        }

        // Convert glob pattern to regex
        var regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "?", with: ".")
            .replacingOccurrences(of: "*", with: ".*")

        // Handle *:// scheme wildcard
        regexPattern = regexPattern.replacingOccurrences(of: ".*://", with: "(https?|file)://")

        do {
            let regex = try NSRegularExpression(pattern: "^" + regexPattern + "$", options: [.caseInsensitive])
            let range = NSRange(urlString.startIndex..., in: urlString)
            return regex.firstMatch(in: urlString, options: [], range: range) != nil
        } catch {
            return false
        }
    }

    /// Create a WKUserScript from this user script
    func toWKUserScript() -> WKUserScript {
        return WKUserScript(
            source: source,
            injectionTime: injectionTime.wkInjectionTime,
            forMainFrameOnly: !runOnAllFrames
        )
    }
}
