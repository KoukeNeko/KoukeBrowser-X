//
//  DebugAutomation+WebExtensions.swift
//  kouke browser
//
//  SPIKE (Phase 0) — async harness commands for driving the WKWebExtension host.
//
//  Kept out of DebugAutomation.swift so the spike stays easy to delete wholesale
//  once Phase 0 has answered its question.
//

#if DEBUG

import AppKit
import WebKit

/// Harness commands whose work cannot complete synchronously.
enum AsyncCommand: String {
    case loadExtension = "load_extension"
    case unloadExtensions = "unload_extensions"
    case loadPage = "load_page"
    case readSpikeResult = "read_spike_result"
    case evalJS = "eval_js"
    case autofillDescribe = "autofill_describe"
    case autofillFill = "autofill_fill"
}

@MainActor
extension DebugAutomation {

    /// How long to wait for a page load before giving up.
    private static var pageLoadTimeout: Duration { .seconds(15) }

    /// How long to wait for a content script to publish its result.
    private static var contentScriptTimeout: Duration { .seconds(10) }

    /// Interval between polls while waiting on the page or a content script.
    private static var pollInterval: Duration { .milliseconds(200) }

    /// Placeholder that forces a real WKWebView-backed tab into existence.
    private static var blankWebPageURL: String { "about:blank" }

    func executeAsync(_ command: AsyncCommand, arguments: [String: Any]) async -> Result<String, Error> {
        do {
            switch command {
            case .loadExtension:
                return .success(try await loadWebExtension(arguments))
            case .unloadExtensions:
                return .success(try unloadWebExtensions())
            case .loadPage:
                return .success(try await loadPage(arguments))
            case .readSpikeResult:
                return .success(try await readSpikeResult(arguments))
            case .evalJS:
                return .success(try await evaluateJavaScript(arguments))
            case .autofillDescribe:
                return .success(try await describeLoginForm(arguments))
            case .autofillFill:
                return .success(try await fillLoginForm(arguments))
            }
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Extension Commands

    private func loadWebExtension(_ arguments: [String: Any]) async throws -> String {
        guard #available(macOS 15.4, *) else {
            throw WebExtensionHostError.unsupportedSystem(WebExtensionHost.shared.unsupportedReason)
        }
        let report: WebExtensionLoadReport
        if let bundlePath = arguments["bundle"] as? String {
            report = try await WebExtensionHost.shared.loadExtension(atBundlePath: bundlePath)
        } else if let path = arguments["path"] as? String {
            report = try await WebExtensionHost.shared.loadExtension(atPath: path)
        } else {
            throw DebugAutomationError.badArguments("path or bundle is required")
        }

        return try encodeJSON(report.asDictionary)
    }

    private func unloadWebExtensions() throws -> String {
        guard #available(macOS 15.4, *) else {
            throw WebExtensionHostError.unsupportedSystem(WebExtensionHost.shared.unsupportedReason)
        }
        let unloadedPaths = WebExtensionHost.shared.loadedExtensionPaths
        try WebExtensionHost.shared.unloadAllExtensions()
        return try encodeJSON(["unloaded": unloadedPaths])
    }

    // MARK: - Page Commands

    /// Loads a local file into the active tab and waits for the load to settle.
    ///
    /// Files must already live inside the app's sandbox container — the harness
    /// script copies fixtures into the working directory precisely because an
    /// arbitrary path elsewhere on disk would be denied by the sandbox.
    private func loadPage(_ arguments: [String: Any]) async throws -> String {
        let webView = try await webViewForLoading(arguments)

        // The controller has to know the tab before the page loads: a content
        // script that runs first would have no identifiable sender, and its
        // runtime.sendMessage would fail with "Tab not found".
        if #available(macOS 15.4, *) {
            WebExtensionHost.shared.synchronizeWindowsAndTabs()
        }

        if let urlString = arguments["url"] as? String {
            guard let url = URL(string: urlString) else {
                throw DebugAutomationError.badArguments("malformed url \(urlString)")
            }
            webView.load(URLRequest(url: url))
        } else if let path = arguments["path"] as? String {
            let fileURL = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw DebugAutomationError.badArguments("no file at \(path)")
            }
            webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        } else {
            throw DebugAutomationError.badArguments("url or path is required")
        }

        try await waitUntil(timeout: Self.pageLoadTimeout, description: "page load") {
            !webView.isLoading && webView.url != nil
        }

        if #available(macOS 15.4, *) {
            WebExtensionHost.shared.synchronizeWindowsAndTabs()
        }

        return try encodeJSON(["loaded": webView.url?.absoluteString ?? ""])
    }

    /// Reads the marker the spike content script publishes on documentElement.
    private func readSpikeResult(_ arguments: [String: Any]) async throws -> String {
        let webView = try activeWebView(arguments)
        let readMarkerJS = "document.documentElement.dataset.koukeSpike || ''"

        var marker = ""
        try await waitUntil(timeout: Self.contentScriptTimeout, description: "content script result") {
            let value = try? await webView.evaluateJavaScript(readMarkerJS) as? String
            marker = (value ?? "") ?? ""
            return !marker.isEmpty
        }

        return marker
    }

    /// Evaluates an expression in the active page and returns it as a string.
    private func evaluateJavaScript(_ arguments: [String: Any]) async throws -> String {
        guard let script = arguments["script"] as? String else {
            throw DebugAutomationError.badArguments("script is required")
        }
        let webView = try activeWebView(arguments)

        let value = try await webView.evaluateJavaScript(script)
        return String(describing: value ?? "null")
    }

    // MARK: - Autofill Commands

    /// Reports what the page script sees, so detection can be asserted without
    /// depending on any UI being shown.
    private func describeLoginForm(_ arguments: [String: Any]) async throws -> String {
        let webView = try activeWebView(arguments)
        let description = try await webView.evaluateJavaScript(
            PasswordFormDetector.describeExpression
        ) as? String

        return description ?? #"{"hasLoginForm":false}"#
    }

    /// Fills through the real AutofillBridge, so origin checks and value
    /// escaping are exercised rather than bypassed.
    private func fillLoginForm(_ arguments: [String: Any]) async throws -> String {
        guard let username = arguments["username"] as? String,
              let password = arguments["password"] as? String else {
            throw DebugAutomationError.badArguments("username and password are required")
        }

        let webView = try activeWebView(arguments)
        guard let bridge = (webView as? KoukeWebView)?.autofillBridge else {
            throw DebugAutomationError.badArguments(
                "no autofill bridge on this web view; is the password manager enabled?"
            )
        }

        let filled = await bridge.fill(username: username, password: password)

        // Read the fields straight from the DOM: what the page actually holds
        // is the only trustworthy evidence the fill worked.
        let readBack = """
        JSON.stringify({
          username: (document.querySelector('input[autocomplete="username"], input[type="text"], input[type="email"]') || {}).value || '',
          password: (document.querySelector('input[type="password"]') || {}).value || ''
        })
        """
        let actual = try await webView.evaluateJavaScript(readBack) as? String

        return try encodeJSON([
            "filled": filled,
            "fields": actual ?? ""
        ])
    }

    // MARK: - Helpers

    /// Returns a web view able to host a page, opening a web tab if necessary.
    ///
    /// A fresh window shows the SwiftUI start page (`kouke:blank`), which has no
    /// WKWebView behind it at all, so the harness has to put a real web tab in
    /// place before anything can be loaded.
    private func webViewForLoading(_ arguments: [String: Any]) async throws -> WKWebView {
        if let existing = try? activeWebView(arguments) {
            return existing
        }

        guard let viewModel = resolveActiveViewModel(arguments) else {
            throw DebugAutomationError.windowNotFound
        }
        viewModel.addTabWithURL(Self.blankWebPageURL)

        var webView: WKWebView?
        try await waitUntil(timeout: Self.pageLoadTimeout, description: "web view creation") {
            webView = viewModel.getActiveWebView()
            return webView != nil
        }

        guard let webView else {
            throw DebugAutomationError.badArguments("active tab has no web view")
        }
        return webView
    }

    private func activeWebView(_ arguments: [String: Any]) throws -> WKWebView {
        guard let viewModel = resolveActiveViewModel(arguments) else {
            throw DebugAutomationError.windowNotFound
        }
        guard let webView = viewModel.getActiveWebView() else {
            throw DebugAutomationError.badArguments("active tab has no web view")
        }
        return webView
    }

    private func resolveActiveViewModel(_ arguments: [String: Any]) -> BrowserViewModel? {
        if let windowNumber = arguments["window"] as? Int {
            return WindowManager.shared.debugViewModel(forWindowNumber: windowNumber)
        }
        for window in NSApp.orderedWindows where window.isVisible {
            if let viewModel = WindowManager.shared.debugViewModel(forWindowNumber: window.windowNumber) {
                return viewModel
            }
        }
        return nil
    }

    /// Polls `condition` until it holds or the timeout elapses.
    private func waitUntil(timeout: Duration,
                           description: String,
                           condition: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while ContinuousClock.now < deadline {
            if try await condition() {
                return
            }
            try await Task.sleep(for: Self.pollInterval)
        }

        throw DebugAutomationError.badArguments("timed out waiting for \(description)")
    }

    private func encodeJSON(_ value: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw DebugAutomationError.badArguments("could not encode result as JSON")
        }
        return text
    }
}

#endif
