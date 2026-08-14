//
//  WebExtensionTabAdapter.swift
//  kouke browser
//
//  SPIKE (Phase 0) — bridges one browser tab to the WKWebExtension API.
//
//  `Tab` is a struct, but WKWebExtensionTab inherits from the NSObject protocol
//  and the extension machinery compares tabs by object identity. A value type
//  cannot satisfy either requirement, so each tab gets a long-lived adapter
//  object that looks its state up by ID on demand.
//

#if DEBUG

import WebKit

@available(macOS 15.4, *)
@MainActor
final class WebExtensionTabAdapter: NSObject, WKWebExtensionTab {

    let tabId: UUID

    private weak var windowAdapter: WebExtensionWindowAdapter?

    init(tabId: UUID, windowAdapter: WebExtensionWindowAdapter) {
        self.tabId = tabId
        self.windowAdapter = windowAdapter
        super.init()
    }

    // MARK: - Tab State Lookup

    private var viewModel: BrowserViewModel? {
        windowAdapter?.viewModel
    }

    private var tab: Tab? {
        viewModel?.tabs.first { $0.id == tabId }
    }

    // MARK: - WKWebExtensionTab

    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        viewModel?.getWebView(for: tabId)
    }

    func url(for context: WKWebExtensionContext) -> URL? {
        guard let urlString = tab?.url else { return nil }

        // Internal pages are not real web content; reporting them would let an
        // extension try to inject into the browser's own UI.
        guard !KoukeScheme.isKoukeURL(urlString) else { return nil }

        return URL(string: urlString)
    }

    func title(for context: WKWebExtensionContext) -> String? {
        tab?.title
    }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        windowAdapter
    }

    func isSelected(for context: WKWebExtensionContext) -> Bool {
        viewModel?.activeTabId == tabId
    }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool {
        guard let tab else { return true }
        return !tab.isLoading
    }

    // MARK: - WKWebExtensionTab Actions

    func activate(for context: WKWebExtensionContext) async throws {
        guard let viewModel else { throw WebExtensionAdapterError.tabNoLongerExists }
        viewModel.switchToTab(tabId)
    }

    func close(for context: WKWebExtensionContext) async throws {
        guard let viewModel else { throw WebExtensionAdapterError.tabNoLongerExists }
        viewModel.closeTab(tabId)
    }

    func loadURL(_ url: URL, for context: WKWebExtensionContext) async throws {
        guard let webView = viewModel?.getWebView(for: tabId) else {
            throw WebExtensionAdapterError.tabNoLongerExists
        }
        webView.load(URLRequest(url: url))
    }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext) async throws {
        guard let webView = viewModel?.getWebView(for: tabId) else {
            throw WebExtensionAdapterError.tabNoLongerExists
        }
        if fromOrigin {
            webView.reloadFromOrigin()
        } else {
            webView.reload()
        }
    }

    func goBack(for context: WKWebExtensionContext) async throws {
        guard let webView = viewModel?.getWebView(for: tabId) else {
            throw WebExtensionAdapterError.tabNoLongerExists
        }
        webView.goBack()
    }

    func goForward(for context: WKWebExtensionContext) async throws {
        guard let webView = viewModel?.getWebView(for: tabId) else {
            throw WebExtensionAdapterError.tabNoLongerExists
        }
        webView.goForward()
    }
}

// MARK: - Errors

enum WebExtensionAdapterError: LocalizedError {
    case tabNoLongerExists
    case windowNoLongerExists

    var errorDescription: String? {
        switch self {
        case .tabNoLongerExists:
            return "The tab is no longer open."
        case .windowNoLongerExists:
            return "The window is no longer open."
        }
    }
}

#endif
