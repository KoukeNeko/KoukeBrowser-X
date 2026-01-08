//
//  WebViewContainer.swift
//  kouke browser
//
//  WKWebView wrapper for SwiftUI with navigation delegate callbacks.
//

import SwiftUI
import WebKit
import CommonCrypto

// MARK: - Certificate Fetch Delegate

/// URLSession delegate for fetching SSL certificate information
private class CertificateFetchDelegate: NSObject, URLSessionDelegate {
    private let onCertificateReceived: (SecTrust) -> Void
    private var hasCaptured = false

    init(onCertificateReceived: @escaping (SecTrust) -> Void) {
        self.onCertificateReceived = onCertificateReceived
        super.init()
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Only capture once
        if !hasCaptured {
            hasCaptured = true
            onCertificateReceived(serverTrust)
        }

        completionHandler(.performDefaultHandling, nil)
    }
}

// MARK: - WebView Container

struct WebViewContainer: NSViewRepresentable {
    let tabId: UUID
    let url: String
    @ObservedObject var viewModel: BrowserViewModel
    private let settings = BrowserSettings.shared

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // Apply JavaScript setting
        configuration.defaultWebpagePreferences.allowsContentJavaScript = !settings.disableJavaScript

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

        // Note: Font size is now controlled via pageZoom instead of CSS injection
        // CSS injection of html font-size breaks sites that use rem units

        // Note: WebAuthn polyfill removed - it was overriding navigator.credentials
        // and causing compatibility issues with sites like Google

        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = webView // Assign webView to coordinator
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator


        // Enable developer extras for Web Inspector
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // Set User-Agent to mimic Safari on macOS for best compatibility
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15"

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

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        var parent: WebViewContainer
        private var titleObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?
        private var canGoBackObservation: NSKeyValueObservation?
        private var canGoForwardObservation: NSKeyValueObservation?

        weak var webView: WKWebView?
        private var pendingNavigationHost: String?
        private var hasCapturedCertificate = false

        init(_ parent: WebViewContainer) {
            self.parent = parent
            super.init()
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

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            // Fetch certificate info after navigation commits (page starts loading)
            // This ensures we have a valid URL to query
            guard let url = webView.url, url.scheme == "https" else { return }

            // Always try to fetch certificate info - the flag will be set on success
            fetchCertificateInfo(for: url)
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

            // Capture certificate from WKWebView challenge (backup for URLSession method)
            let mainHost = pendingNavigationHost ?? webView.url?.host
            if let mainHost = mainHost, isHostMatch(challengeHost: challengeHost, mainHost: mainHost) {
                // Only update if not already captured, or always update to ensure we have latest
                let securityInfo = extractSecurityInfo(from: serverTrust, host: challengeHost)
                hasCapturedCertificate = true
                Task { @MainActor in
                    self.parent.viewModel.updateTabSecurityInfo(securityInfo, for: self.parent.tabId)
                }
            }

            completionHandler(.performDefaultHandling, nil)
        }

        private func fetchCertificateInfo(for url: URL) {
            // Skip if already captured for this navigation
            guard !hasCapturedCertificate else { return }

            let host = url.host ?? ""

            // Create a URLSession that captures certificate info
            let sessionConfig = URLSessionConfiguration.ephemeral
            sessionConfig.timeoutIntervalForRequest = 5
            sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData

            let delegate = CertificateFetchDelegate { [weak self] serverTrust in
                guard let self = self else { return }

                // Mark as captured to prevent duplicate fetches
                self.hasCapturedCertificate = true

                let securityInfo = self.extractSecurityInfo(from: serverTrust, host: host)
                Task { @MainActor in
                    self.parent.viewModel.updateTabSecurityInfo(securityInfo, for: self.parent.tabId)
                }
            }

            let session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)

            // Make a simple GET request (some servers don't respond to HEAD properly)
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            // Only request headers to minimize data transfer
            request.setValue("bytes=0-0", forHTTPHeaderField: "Range")

            let task = session.dataTask(with: request) { _, _, _ in
                // Certificate is captured in delegate callback
                session.invalidateAndCancel()
            }
            task.resume()
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

                // Extract issuer from certificate values if not already obtained from issuer cert
                if issuer == "Unknown" {
                    if let issuerData = certValues[kSecOIDX509V1IssuerName as String] as? [String: Any],
                       let issuerItems = issuerData[kSecPropertyKeyValue as String] as? [[String: Any]] {
                        // Look for Common Name (CN) or Organization (O) in issuer
                        for item in issuerItems {
                            if let label = item[kSecPropertyKeyLabel as String] as? String,
                               let value = item[kSecPropertyKeyValue as String] as? String {
                                if label == "2.5.4.3" || label.contains("CN") || label.contains("Common Name") {
                                    issuer = value
                                    break
                                } else if (label == "2.5.4.10" || label.contains("O") || label.contains("Organization")) && issuer == "Unknown" {
                                    issuer = value
                                }
                            }
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

        // MARK: - WKDownloadDelegate

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            // Check if this response should be downloaded instead of displayed
            if let mimeType = navigationResponse.response.mimeType {
                let downloadMimeTypes = [
                    "application/octet-stream",
                    "application/zip",
                    "application/x-zip-compressed",
                    "application/x-rar-compressed",
                    "application/x-7z-compressed",
                    "application/x-tar",
                    "application/gzip",
                    "application/x-bzip2",
                    "application/pdf",
                    "application/msword",
                    "application/vnd.openxmlformats-officedocument",
                    "application/vnd.ms-excel",
                    "application/vnd.ms-powerpoint",
                    "application/x-apple-diskimage",
                    "application/x-dmg"
                ]

                let isDownloadType = downloadMimeTypes.contains { mimeType.hasPrefix($0) }

                // Also check Content-Disposition header for attachment
                let isAttachment = (navigationResponse.response as? HTTPURLResponse)?
                    .value(forHTTPHeaderField: "Content-Disposition")?
                    .contains("attachment") ?? false

                if !navigationResponse.canShowMIMEType || isDownloadType || isAttachment {
                    if #available(macOS 11.3, *) {
                        decisionHandler(.download)
                        return
                    }
                }
            }

            decisionHandler(.allow)
        }

        @available(macOS 11.3, *)
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        @available(macOS 11.3, *)
        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        @available(macOS 11.3, *)
        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let settings = BrowserSettings.shared

            // Determine download location
            let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!

            if settings.downloadLocation == .askEachTime {
                // Show save panel
                let savePanel = NSSavePanel()
                savePanel.directoryURL = downloadsURL
                savePanel.nameFieldStringValue = suggestedFilename
                savePanel.canCreateDirectories = true

                savePanel.begin { response in
                    if response == .OK, let url = savePanel.url {
                        completionHandler(url)
                    } else {
                        completionHandler(nil)
                    }
                }
            } else {
                // Save to Downloads folder with unique filename
                var destinationURL = downloadsURL.appendingPathComponent(suggestedFilename)

                // Handle duplicate filenames
                var counter = 1
                let originalName = (suggestedFilename as NSString).deletingPathExtension
                let ext = (suggestedFilename as NSString).pathExtension

                while FileManager.default.fileExists(atPath: destinationURL.path) {
                    let newName = ext.isEmpty ? "\(originalName) (\(counter))" : "\(originalName) (\(counter)).\(ext)"
                    destinationURL = downloadsURL.appendingPathComponent(newName)
                    counter += 1
                }

                completionHandler(destinationURL)
            }

            // Start tracking in DownloadManager
            if let url = download.originalRequest?.url {
                Task { @MainActor in
                    _ = DownloadManager.shared.startDownload(url: url, suggestedFilename: suggestedFilename)
                }
            }
        }

        @available(macOS 11.3, *)
        func downloadDidFinish(_ download: WKDownload) {
            // Download completed - DownloadManager handles the completion
        }

        @available(macOS 11.3, *)
        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            // Download failed - DownloadManager handles the error
            if let url = download.originalRequest?.url {
                Task { @MainActor in
                    // Find the download item and update its status
                    if let item = DownloadManager.shared.downloadItems.first(where: { $0.url == url.absoluteString }) {
                        DownloadManager.shared.failDownload(for: item.id, error: error)
                    }
                }
            }
        }
    }
}
