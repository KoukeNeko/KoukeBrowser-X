//
//  WebExtensionWindowAdapter.swift
//  kouke browser
//
//  SPIKE (Phase 0) — bridges one browser window to the WKWebExtension API.
//
//  Owns the tab adapters for its window. Adapters are cached by tab ID because
//  the extension machinery tracks tabs by object identity: handing out a fresh
//  adapter for the same tab would make it look like a different tab each time.
//

#if DEBUG

import AppKit
import WebKit

@available(macOS 15.4, *)
@MainActor
final class WebExtensionWindowAdapter: NSObject, WKWebExtensionWindow {

    let windowNumber: Int

    private var tabAdapters: [UUID: WebExtensionTabAdapter] = [:]

    init(windowNumber: Int) {
        self.windowNumber = windowNumber
        super.init()
    }

    // MARK: - Window State Lookup

    var viewModel: BrowserViewModel? {
        WindowManager.shared.debugViewModel(forWindowNumber: windowNumber)
    }

    private var window: NSWindow? {
        NSApp.windows.first { $0.windowNumber == windowNumber }
    }

    /// Returns the cached adapter for a tab, creating it on first use.
    func adapter(for tabId: UUID) -> WebExtensionTabAdapter {
        if let existing = tabAdapters[tabId] {
            return existing
        }
        let adapter = WebExtensionTabAdapter(tabId: tabId, windowAdapter: self)
        tabAdapters[tabId] = adapter
        return adapter
    }

    /// Drops adapters for tabs that have since closed, so the cache cannot grow
    /// without bound over a long session.
    func pruneClosedTabs() {
        guard let viewModel else {
            tabAdapters.removeAll()
            return
        }
        let openTabIds = Set(viewModel.tabs.map(\.id))
        tabAdapters = tabAdapters.filter { openTabIds.contains($0.key) }
    }

    /// Adapters for every open tab. Context-free so the host can announce tabs
    /// to the controller outside a protocol callback.
    func allTabAdapters() -> [WebExtensionTabAdapter] {
        guard let viewModel else { return [] }
        return viewModel.tabs.map { adapter(for: $0.id) }
    }

    func activeTabAdapter() -> WebExtensionTabAdapter? {
        guard let activeTabId = viewModel?.activeTabId else { return nil }
        return adapter(for: activeTabId)
    }

    // MARK: - WKWebExtensionWindow

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        allTabAdapters()
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        activeTabAdapter()
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType {
        .normal
    }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window else { return .normal }
        if window.isMiniaturized { return .minimized }
        if window.isZoomed { return .maximized }
        return .normal
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool {
        // Private browsing is not implemented in the browser yet. Reporting
        // `true` would make extensions withhold data they should be sharing.
        false
    }

    func frame(for context: WKWebExtensionContext) -> CGRect {
        window?.frame ?? .zero
    }

    func screenFrame(for context: WKWebExtensionContext) -> CGRect {
        window?.screen?.frame ?? NSScreen.main?.frame ?? .zero
    }

    // MARK: - WKWebExtensionWindow Actions

    func focus(for context: WKWebExtensionContext) async throws {
        guard let window else { throw WebExtensionAdapterError.windowNoLongerExists }
        window.makeKeyAndOrderFront(nil)
    }

    func close(for context: WKWebExtensionContext) async throws {
        guard let window else { throw WebExtensionAdapterError.windowNoLongerExists }
        window.performClose(nil)
    }
}

#endif
