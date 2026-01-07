//
//  WebViewContainer.swift
//  kouke browser
//
//  WKWebView wrapper for SwiftUI with navigation delegate callbacks.
//

import SwiftUI
import WebKit

struct WebViewContainer: NSViewRepresentable {
    let tabId: UUID
    let url: String
    @ObservedObject var viewModel: BrowserViewModel
    private let settings = BrowserSettings.shared

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // Apply JavaScript setting
        configuration.defaultWebpagePreferences.allowsContentJavaScript = !settings.disableJavaScript
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop

        // Apply image blocking if enabled
        if settings.disableImages {
            let blockImagesRule = """
            [{
                "trigger": { "url-filter": ".*", "resource-type": ["image"] },
                "action": { "type": "block" }
            }]
            """
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "BlockImages",
                encodedContentRuleList: blockImagesRule
            ) { ruleList, error in
                if let ruleList = ruleList {
                    configuration.userContentController.add(ruleList)
                }
            }
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Enable developer extras for Web Inspector
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // Set User-Agent to mimic Chrome on macOS for proper rendering
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

        // Register with ViewModel
        Task { @MainActor in
            viewModel.registerWebView(webView, for: tabId)
        }

        // Add KVO observers for title and URL changes
        context.coordinator.setupObservers(for: webView)

        // Load initial URL (skip kouke:// URLs as they are handled by viewSource)
        if !url.hasPrefix("kouke://"), let urlObj = URL(string: url) {
            webView.load(URLRequest(url: urlObj))
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // URL changes are handled by the ViewModel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebViewContainer
        private var titleObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?
        private var canGoBackObservation: NSKeyValueObservation?
        private var canGoForwardObservation: NSKeyValueObservation?

        init(_ parent: WebViewContainer) {
            self.parent = parent
        }

        deinit {
            titleObservation?.invalidate()
            urlObservation?.invalidate()
            canGoBackObservation?.invalidate()
            canGoForwardObservation?.invalidate()
        }

        func setupObservers(for webView: WKWebView) {
            // Observe title changes
            titleObservation = webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
                guard let self = self else { return }
                Task { @MainActor in
                    if let title = webView.title, !title.isEmpty {
                        self.parent.viewModel.updateTabTitle(title, for: self.parent.tabId)
                    }
                }
            }

            // Observe URL changes (skip for kouke:// URLs to preserve custom URLs)
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                guard let self = self else { return }
                Task { @MainActor in
                    // Don't overwrite kouke:// URLs (they're internal pages with custom content)
                    let currentTabURL = self.parent.viewModel.tabs.first { $0.id == self.parent.tabId }?.url ?? ""
                    if currentTabURL.hasPrefix("kouke:") {
                        return
                    }
                    if let url = webView.url?.absoluteString {
                        self.parent.viewModel.updateTabURL(url, for: self.parent.tabId)
                    }
                }
            }

            // Observe canGoBack changes
            canGoBackObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
                guard let self = self else { return }
                Task { @MainActor in
                    self.parent.viewModel.updateTabNavigationState(
                        canGoBack: webView.canGoBack,
                        canGoForward: webView.canGoForward,
                        for: self.parent.tabId
                    )
                }
            }

            // Observe canGoForward changes
            canGoForwardObservation = webView.observe(\.canGoForward, options: [.new]) { [weak self] webView, _ in
                guard let self = self else { return }
                Task { @MainActor in
                    self.parent.viewModel.updateTabNavigationState(
                        canGoBack: webView.canGoBack,
                        canGoForward: webView.canGoForward,
                        for: self.parent.tabId
                    )
                }
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                parent.viewModel.updateTabLoadingState(true, for: parent.tabId)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                parent.viewModel.updateTabLoadingState(false, for: parent.tabId)
                // Title and URL updates are now handled by KVO observers

                // Capture thumbnail after page loads with a slight delay for rendering
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.parent.viewModel.captureTabThumbnail(for: self.parent.tabId)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                parent.viewModel.updateTabLoadingState(false, for: parent.tabId)
            }
        }

        // MARK: - WKUIDelegate

        // Handle target="_blank" links - open in new tab
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url?.absoluteString {
                Task { @MainActor in
                    self.parent.viewModel.addTabWithURL(url)
                }
            }
            return nil
        }
    }
}
