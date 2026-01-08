//
//  WebViewContainer.swift
//  kouke browser
//
//  WKWebView wrapper for SwiftUI with navigation delegate callbacks.
//

import SwiftUI
import WebKit
import CommonCrypto

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

        // Apply default font size via CSS injection
        let fontSizeCSS = """
        (function() {
            var style = document.createElement('style');
            style.id = 'kouke-font-size';
            style.textContent = 'html { font-size: \(settings.fontSize)px !important; }';
            document.head.appendChild(style);
        })();
        """
        let fontSizeScript = WKUserScript(source: fontSizeCSS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(fontSizeScript)

        // WebAuthn / Passkey Polyfill
        // Intercepts navigator.credentials.create and get to send to native app
        let webAuthnPolyfill = """
        if (!navigator.credentials) { navigator.credentials = {}; }
        
        navigator.credentials.create = async function(options) {
            console.log("WebAuthn: create called", options);
            // TODO: Serialize options (ArrayBuffers to Base64)
            // return window.webkit.messageHandlers.webAuthnCreate.postMessage(JSON.stringify(options));
            return Promise.reject("WebAuthn not fully implemented in bridge");
        };

        navigator.credentials.get = async function(options) {
            console.log("WebAuthn: get called", options);
            // TODO: Serialize options
            // return window.webkit.messageHandlers.webAuthnGet.postMessage(JSON.stringify(options));
             return Promise.reject("WebAuthn not fully implemented in bridge");
        };
        """
        let webAuthnScript = WKUserScript(source: webAuthnPolyfill, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        configuration.userContentController.addUserScript(webAuthnScript)



        // Register message handlers
        configuration.userContentController.add(context.coordinator, name: "webAuthnCreate")
        configuration.userContentController.add(context.coordinator, name: "webAuthnGet")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = webView // Assign webView to coordinator
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Enable developer extras for Web Inspector
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // Set User-Agent on macOS (more authentic for WebKit)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Kouke/2026.01"

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

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: WebViewContainer
        private var titleObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?
        private var canGoBackObservation: NSKeyValueObservation?
        private var canGoForwardObservation: NSKeyValueObservation?
        private var fontSizeObserver: NSObjectProtocol?
        private let webAuthnManager = WebAuthnManager()
        weak var webView: WKWebView?
        private var pendingNavigationHost: String?
        private var hasCapturedCertificate = false

        init(_ parent: WebViewContainer) {
            self.parent = parent
            super.init()
            setupFontSizeObserver()
        }

        deinit {
            titleObservation?.invalidate()
            urlObservation?.invalidate()
            canGoBackObservation?.invalidate()
            canGoForwardObservation?.invalidate()
            if let observer = fontSizeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        private func setupFontSizeObserver() {
            fontSizeObserver = NotificationCenter.default.addObserver(
                forName: .fontSizeChanged,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self = self,
                      let webView = self.webView,
                      let fontSize = notification.object as? Int else { return }

                let js = """
                (function() {
                    var style = document.getElementById('kouke-font-size');
                    if (!style) {
                        style = document.createElement('style');
                        style.id = 'kouke-font-size';
                        document.head.appendChild(style);
                    }
                    style.textContent = 'html { font-size: \(fontSize)px !important; }';
                })();
                """
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
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

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Only capture the target host for main frame navigations (not iframes)
            if navigationAction.targetFrame?.isMainFrame == true,
               let host = navigationAction.request.url?.host {
                pendingNavigationHost = host
                hasCapturedCertificate = false
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            // Update pending host on server redirect (main frame only)
            if let newHost = webView.url?.host {
                pendingNavigationHost = newHost
                // Don't reset hasCapturedCertificate here - we want to capture after redirect settles
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                parent.viewModel.updateTabLoadingState(true, for: parent.tabId)

                // Set initial security info based on URL scheme
                if let url = webView.url?.absoluteString ?? pendingNavigationURL() {
                    let basicSecurityInfo = SecurityInfo.fromURL(url)
                    parent.viewModel.updateTabSecurityInfo(basicSecurityInfo, for: parent.tabId)
                }
            }
        }

        private func pendingNavigationURL() -> String? {
            if let host = pendingNavigationHost {
                return "https://\(host)"
            }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                parent.viewModel.updateTabLoadingState(false, for: parent.tabId)
                // Title and URL updates are now handled by KVO observers

                // Record to browsing history
                if let url = webView.url?.absoluteString {
                    HistoryManager.shared.addHistoryItem(
                        title: webView.title ?? "",
                        url: url
                    )
                }

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

        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let serverTrust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            let challengeHost = challenge.protectionSpace.host

            // Only capture certificate once per navigation, for the main host
            if !hasCapturedCertificate {
                let mainHost = pendingNavigationHost ?? webView.url?.host
                if let mainHost = mainHost, isHostMatch(challengeHost: challengeHost, mainHost: mainHost) {
                    hasCapturedCertificate = true
                    let securityInfo = extractSecurityInfo(from: serverTrust, host: challengeHost)
                    Task { @MainActor in
                        parent.viewModel.updateTabSecurityInfo(securityInfo, for: parent.tabId)
                    }
                }
            }

            completionHandler(.performDefaultHandling, nil)
        }

        private func isHostMatch(challengeHost: String, mainHost: String) -> Bool {
            // Exact match
            if challengeHost == mainHost { return true }
            // Challenge is subdomain of main (e.g., www.example.com matches example.com)
            if challengeHost.hasSuffix(".\(mainHost)") { return true }
            // Main is subdomain of challenge (e.g., example.com matches www.example.com)
            if mainHost.hasSuffix(".\(challengeHost)") { return true }
            // Handle www prefix differences
            let challengeWithoutWww = challengeHost.hasPrefix("www.") ? String(challengeHost.dropFirst(4)) : challengeHost
            let mainWithoutWww = mainHost.hasPrefix("www.") ? String(mainHost.dropFirst(4)) : mainHost
            return challengeWithoutWww == mainWithoutWww
        }

        private func extractSecurityInfo(from serverTrust: SecTrust, host: String) -> SecurityInfo {
            var certificateInfo: CertificateInfo?

            if let certificates = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
               let leafCert = certificates.first {
                // Get issuer from the second certificate in chain (the CA that signed the leaf)
                let issuerCert = certificates.count > 1 ? certificates[1] : nil
                certificateInfo = extractCertificateInfo(from: leafCert, issuerCert: issuerCert)
            }

            return SecurityInfo(
                level: .secure,
                certificate: certificateInfo,
                protocol_: nil,
                host: host
            )
        }

        private func extractCertificateInfo(from certificate: SecCertificate, issuerCert: SecCertificate?) -> CertificateInfo {
            var subject = "Unknown"
            var issuer = "Unknown"
            var validFrom: Date?
            var validUntil: Date?
            var serialNumber: String?
            var version: Int?
            var signatureAlgorithm: String?
            var publicKeyAlgorithm: String?
            var publicKeySize: Int?
            var sha256Fingerprint: String?

            // Get certificate subject (who the cert is issued to)
            if let summary = SecCertificateCopySubjectSummary(certificate) as String? {
                subject = summary
            }

            // Get issuer from the issuer certificate's subject (more reliable)
            if let issuerCert = issuerCert,
               let issuerSummary = SecCertificateCopySubjectSummary(issuerCert) as String? {
                issuer = issuerSummary
            }

            // Get SHA-256 fingerprint
            let certData = SecCertificateCopyData(certificate) as Data
            sha256Fingerprint = sha256Hash(of: certData)

            // Get public key info
            if let publicKey = SecCertificateCopyKey(certificate) {
                let keyAttributes = SecKeyCopyAttributes(publicKey) as? [String: Any]
                if let keyType = keyAttributes?[kSecAttrKeyType as String] as? String {
                    if keyType == kSecAttrKeyTypeRSA as String {
                        publicKeyAlgorithm = "RSA"
                    } else if keyType == kSecAttrKeyTypeEC as String || keyType == kSecAttrKeyTypeECSECPrimeRandom as String {
                        publicKeyAlgorithm = "ECDSA"
                    } else {
                        publicKeyAlgorithm = keyType
                    }
                }
                if let keySizeNumber = keyAttributes?[kSecAttrKeySizeInBits as String] as? Int {
                    publicKeySize = keySizeNumber
                }
            }

            // Get detailed certificate values
            if let certValues = SecCertificateCopyValues(certificate, nil, nil) as? [String: Any] {
                // Extract validity period
                if let notBeforeData = certValues[kSecOIDX509V1ValidityNotBefore as String] as? [String: Any],
                   let notBeforeValue = notBeforeData[kSecPropertyKeyValue as String] as? Double {
                    validFrom = Date(timeIntervalSinceReferenceDate: notBeforeValue)
                }

                if let notAfterData = certValues[kSecOIDX509V1ValidityNotAfter as String] as? [String: Any],
                   let notAfterValue = notAfterData[kSecPropertyKeyValue as String] as? Double {
                    validUntil = Date(timeIntervalSinceReferenceDate: notAfterValue)
                }

                // Extract serial number
                if let serialData = certValues[kSecOIDX509V1SerialNumber as String] as? [String: Any],
                   let serialValue = serialData[kSecPropertyKeyValue as String] as? String {
                    serialNumber = serialValue
                }

                // Extract version
                if let versionData = certValues[kSecOIDX509V1Version as String] as? [String: Any],
                   let versionValue = versionData[kSecPropertyKeyValue as String] as? Int {
                    version = versionValue + 1  // Version is 0-indexed in the cert
                }

                // Extract signature algorithm
                if let sigAlgData = certValues[kSecOIDX509V1SignatureAlgorithm as String] as? [String: Any],
                   let sigAlgValue = sigAlgData[kSecPropertyKeyValue as String] as? [[String: Any]] {
                    for item in sigAlgValue {
                        if let value = item[kSecPropertyKeyValue as String] as? String {
                            signatureAlgorithm = formatSignatureAlgorithm(value)
                            break
                        }
                    }
                }
            }

            return CertificateInfo(
                subject: subject,
                issuer: issuer,
                validFrom: validFrom,
                validUntil: validUntil,
                serialNumber: serialNumber,
                version: version,
                signatureAlgorithm: signatureAlgorithm,
                publicKeyAlgorithm: publicKeyAlgorithm,
                publicKeySize: publicKeySize,
                sha256Fingerprint: sha256Fingerprint
            )
        }

        private func sha256Hash(of data: Data) -> String {
            var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            data.withUnsafeBytes {
                _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
            }
            return hash.map { String(format: "%02X", $0) }.joined(separator: ":")
        }

        private func formatSignatureAlgorithm(_ oid: String) -> String {
            // Common OIDs for signature algorithms
            let algorithms: [String: String] = [
                "1.2.840.113549.1.1.11": "SHA-256 with RSA",
                "1.2.840.113549.1.1.12": "SHA-384 with RSA",
                "1.2.840.113549.1.1.13": "SHA-512 with RSA",
                "1.2.840.113549.1.1.5": "SHA-1 with RSA",
                "1.2.840.10045.4.3.2": "ECDSA with SHA-256",
                "1.2.840.10045.4.3.3": "ECDSA with SHA-384",
                "1.2.840.10045.4.3.4": "ECDSA with SHA-512"
            ]
            return algorithms[oid] ?? oid
        }

        // MARK: - WKUIDelegate

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url?.absoluteString {
                Task { @MainActor in
                    self.parent.viewModel.addTabWithURL(url)
                }
            }
            return nil
        }

        // MARK: - WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let jsonString = message.body as? String, let webView = webView, let window = webView.window else { return }
            
            if message.name == "webAuthnCreate" {
                webAuthnManager.performRegistration(jsonRequest: jsonString, in: window) { result, error in
                    // Return result to JS (TODO: invoke JS callback)
                }
            } else if message.name == "webAuthnGet" {
                webAuthnManager.performAssertion(jsonRequest: jsonString, in: window) { result, error in
                    // Return result to JS
                }
            }
        }
    }
}
