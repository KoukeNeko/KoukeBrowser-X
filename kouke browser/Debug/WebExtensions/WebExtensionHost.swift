//
//  WebExtensionHost.swift
//  kouke browser
//
//  SPIKE (Phase 0) — minimal WKWebExtension host.
//
//  Answers one question: can a real-world password-manager extension load and
//  run inside this browser? Everything here is DEBUG-only and deliberately
//  permissive; none of it is production-ready.
//
//  WKWebExtension requires macOS 15.4 while the app deploys back to 14.6, so
//  every entry point is availability-gated and degrades to a clear message.
//

#if DEBUG

import AppKit
import WebKit

/// Outcome of a load attempt, in a form the debug harness can serialize.
struct WebExtensionLoadReport {
    var displayName: String?
    var version: String?
    var manifestVersion: Double?
    var hasBackgroundContent: Bool
    var hasPersistentBackgroundContent: Bool
    var hasInjectedContent: Bool
    var hasOptionsPage: Bool
    var requestedPermissions: [String]
    var requestedMatchPatterns: [String]
    var parseErrors: [String]
    var backgroundLoadError: String?

    var asDictionary: [String: Any] {
        var result: [String: Any] = [
            "hasBackgroundContent": hasBackgroundContent,
            "hasPersistentBackgroundContent": hasPersistentBackgroundContent,
            "hasInjectedContent": hasInjectedContent,
            "hasOptionsPage": hasOptionsPage,
            "requestedPermissions": requestedPermissions,
            "requestedMatchPatterns": requestedMatchPatterns,
            "parseErrors": parseErrors
        ]
        result["displayName"] = displayName ?? NSNull()
        result["version"] = version ?? NSNull()
        result["manifestVersion"] = manifestVersion ?? NSNull()
        result["backgroundLoadError"] = backgroundLoadError ?? NSNull()
        return result
    }
}

@MainActor
final class WebExtensionHost: NSObject {

    static let shared = WebExtensionHost()

    /// Minimum macOS version exposing the WKWebExtension API.
    private static let requiredOSVersion = "macOS 15.4"

    /// Availability-gated types cannot appear in stored properties on a type
    /// that itself deploys to 14.6, so these hold `NSObject` and every read
    /// casts back behind an `if #available` check.
    private var windowAdapters: [Int: NSObject] = [:]
    private var loadedContexts: [String: NSObject] = [:]
    private var controllerStorage: NSObject?

    private override init() {
        super.init()
    }

    // MARK: - Availability

    var isSupported: Bool {
        if #available(macOS 15.4, *) { return true }
        return false
    }

    var unsupportedReason: String {
        "WKWebExtension requires \(Self.requiredOSVersion); this system is older."
    }

    // MARK: - Controller

    @available(macOS 15.4, *)
    var controller: WKWebExtensionController {
        if let existing = controllerStorage as? WKWebExtensionController {
            return existing
        }
        let created = WKWebExtensionController()
        created.delegate = self
        controllerStorage = created
        return created
    }

    /// Attaches the controller so extensions can see content in this WebView.
    /// No-op on systems without the API, and when no extension is loaded, so
    /// the normal browsing path is untouched during the spike.
    func attachIfNeeded(to configuration: WKWebViewConfiguration) {
        guard #available(macOS 15.4, *) else { return }
        guard !loadedContexts.isEmpty else { return }
        configuration.webExtensionController = controller
    }

    // MARK: - Window Registry

    @available(macOS 15.4, *)
    func windowAdapter(forWindowNumber windowNumber: Int) -> WebExtensionWindowAdapter {
        if let existing = windowAdapters[windowNumber] as? WebExtensionWindowAdapter {
            return existing
        }
        let adapter = WebExtensionWindowAdapter(windowNumber: windowNumber)
        windowAdapters[windowNumber] = adapter
        return adapter
    }

    @available(macOS 15.4, *)
    private var liveWindowAdapters: [WebExtensionWindowAdapter] {
        let browserWindowNumbers = NSApp.windows
            .filter { $0.isVisible }
            .map(\.windowNumber)
            .filter { WindowManager.shared.debugViewModel(forWindowNumber: $0) != nil }

        windowAdapters = windowAdapters.filter { browserWindowNumbers.contains($0.key) }

        return browserWindowNumbers.map { windowAdapter(forWindowNumber: $0) }
    }

    // MARK: - Loading

    /// Loads an unpacked extension from a directory containing manifest.json.
    @available(macOS 15.4, *)
    func loadExtension(atPath path: String) async throws -> WebExtensionLoadReport {
        let baseURL = URL(fileURLWithPath: path, isDirectory: true)

        guard FileManager.default.fileExists(atPath: baseURL.appendingPathComponent("manifest.json").path) else {
            throw WebExtensionHostError.manifestNotFound(path)
        }

        return try await load(try await WKWebExtension(resourceBaseURL: baseURL), identifier: path)
    }

    /// Loads an extension shipped inside a Safari app extension bundle (.appex),
    /// which is how installed Mac apps such as Bitwarden distribute theirs.
    @available(macOS 15.4, *)
    func loadExtension(atBundlePath path: String) async throws -> WebExtensionLoadReport {
        guard let bundle = Bundle(path: path) else {
            throw WebExtensionHostError.bundleNotFound(path)
        }

        return try await load(try await WKWebExtension(appExtensionBundle: bundle), identifier: path)
    }

    @available(macOS 15.4, *)
    private func load(_ webExtension: WKWebExtension, identifier: String) async throws -> WebExtensionLoadReport {
        let context = WKWebExtensionContext(for: webExtension)

        grantAllRequestedPermissions(of: webExtension, to: context)

        try controller.load(context)
        loadedContexts[identifier] = context

        var report = makeReport(for: webExtension)

        // Background content starts lazily; forcing it now surfaces service
        // worker failures here instead of leaving them silent.
        if webExtension.hasBackgroundContent {
            do {
                try await context.loadBackgroundContent()
            } catch {
                report.backgroundLoadError = error.localizedDescription
            }
        }

        return report
    }

    /// Announces the current windows and tabs to the controller.
    ///
    /// Without this the controller has no record of tabs opened after an
    /// extension loaded, and `runtime.sendMessage` from a content script fails
    /// with "Tab not found" because the sender cannot be identified.
    ///
    /// Phase 2 must drive these events from the real tab lifecycle instead of
    /// re-announcing everything on demand.
    @available(macOS 15.4, *)
    func synchronizeWindowsAndTabs() {
        for windowAdapter in liveWindowAdapters {
            controller.didOpenWindow(windowAdapter)

            for tabAdapter in windowAdapter.allTabAdapters() {
                controller.didOpenTab(tabAdapter)
            }

            if let activeTab = windowAdapter.activeTabAdapter() {
                controller.didActivateTab(activeTab, previousActiveTab: nil)
            }
        }

        controller.didFocusWindow(liveWindowAdapters.first)
    }

    @available(macOS 15.4, *)
    func unloadAllExtensions() throws {
        for context in loadedContexts.values.compactMap({ $0 as? WKWebExtensionContext }) {
            try controller.unload(context)
        }
        loadedContexts.removeAll()
    }

    var loadedExtensionPaths: [String] {
        Array(loadedContexts.keys)
    }

    // MARK: - Loading Helpers

    /// Grants everything the manifest asks for. Acceptable only because this is
    /// a throwaway spike — the real host must prompt the user (Phase 2).
    @available(macOS 15.4, *)
    private func grantAllRequestedPermissions(of webExtension: WKWebExtension,
                                              to context: WKWebExtensionContext) {
        for permission in webExtension.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        for pattern in webExtension.allRequestedMatchPatterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }
    }

    @available(macOS 15.4, *)
    private func makeReport(for webExtension: WKWebExtension) -> WebExtensionLoadReport {
        WebExtensionLoadReport(
            displayName: webExtension.displayName,
            version: webExtension.version,
            manifestVersion: webExtension.manifestVersion,
            hasBackgroundContent: webExtension.hasBackgroundContent,
            hasPersistentBackgroundContent: webExtension.hasPersistentBackgroundContent,
            hasInjectedContent: webExtension.hasInjectedContent,
            hasOptionsPage: webExtension.hasOptionsPage,
            requestedPermissions: webExtension.requestedPermissions.map(\.rawValue).sorted(),
            requestedMatchPatterns: webExtension.allRequestedMatchPatterns.map(\.string).sorted(),
            parseErrors: webExtension.errors.map(\.localizedDescription),
            backgroundLoadError: nil
        )
    }
}

// MARK: - WKWebExtensionControllerDelegate

@available(macOS 15.4, *)
extension WebExtensionHost: WKWebExtensionControllerDelegate {

    func webExtensionController(_ controller: WKWebExtensionController,
                                openWindowsFor context: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        liveWindowAdapters
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                focusedWindowFor context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        guard let keyWindowNumber = NSApp.keyWindow?.windowNumber,
              WindowManager.shared.debugViewModel(forWindowNumber: keyWindowNumber) != nil else {
            return liveWindowAdapters.first
        }
        return windowAdapter(forWindowNumber: keyWindowNumber)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                in tab: (any WKWebExtensionTab)?,
                                for context: WKWebExtensionContext) async -> (Set<WKWebExtension.Permission>, Date?) {
        NSLog("🧩 WebExtensionHost: auto-granting permissions %@", permissions.map(\.rawValue).joined(separator: ", "))
        return (permissions, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissionToAccess urls: Set<URL>,
                                in tab: (any WKWebExtensionTab)?,
                                for context: WKWebExtensionContext) async -> (Set<URL>, Date?) {
        (urls, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
                                in tab: (any WKWebExtensionTab)?,
                                for context: WKWebExtensionContext) async -> (Set<WKWebExtension.MatchPattern>, Date?) {
        (matchPatterns, nil)
    }
}

// MARK: - Errors

enum WebExtensionHostError: LocalizedError {
    case manifestNotFound(String)
    case bundleNotFound(String)
    case unsupportedSystem(String)

    var errorDescription: String? {
        switch self {
        case .manifestNotFound(let path):
            return "No manifest.json found in \(path)"
        case .bundleNotFound(let path):
            return "No loadable bundle at \(path)"
        case .unsupportedSystem(let reason):
            return reason
        }
    }
}

#endif
