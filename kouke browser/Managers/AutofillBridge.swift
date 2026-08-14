//
//  AutofillBridge.swift
//  kouke browser
//
//  Receives messages from the password autofill page script.
//
//  This is the project's first JS-to-native channel, so it sets the rules:
//  every message is untrusted input, and the origin a decision applies to is
//  read from the WKWebView, never from the message. A page can post anything it
//  likes to a message handler, including a claim about which site it is.
//

import Foundation
import WebKit

/// What the page reported, once validated.
enum AutofillPageEvent {
    /// A login form is present and could be filled.
    case loginFormDetected(host: String, existingUsername: String)

    /// The user submitted credentials that could be offered for saving.
    case credentialsSubmitted(host: String, username: String, password: String)
}

@MainActor
protocol AutofillBridgeDelegate: AnyObject {
    func autofillBridge(_ bridge: AutofillBridge, didReceive event: AutofillPageEvent)
}

@MainActor
final class AutofillBridge: NSObject {

    /// Upper bound on any string accepted from the page.
    ///
    /// A page can post a megabyte-long "password"; nothing legitimate is near
    /// this, and the cap keeps a hostile page from bloating memory or the UI.
    private static let maximumFieldLength = 1024

    weak var delegate: AutofillBridgeDelegate?

    /// Which tab this channel belongs to, so a prompt raised by a background
    /// page is never shown over whatever the user is currently looking at.
    let tabId: UUID

    private weak var webView: WKWebView?

    init(webView: WKWebView, tabId: UUID) {
        self.webView = webView
        self.tabId = tabId
        super.init()
    }

    // MARK: - Filling

    /// Fills a credential into the page. Returns false if the page no longer
    /// presents a login form.
    func fill(username: String, password: String) async -> Bool {
        guard let webView, isEligible(webView) else { return false }
        guard let expression = PasswordFormDetector.fillExpression(username: username,
                                                                   password: password) else {
            return false
        }

        guard let raw = try? await webView.evaluateJavaScript(expression) as? String,
              let data = raw.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return result["filled"] as? Bool ?? false
    }

    // MARK: - Validation

    /// The origin any decision applies to.
    ///
    /// Always taken from the web view's own URL. Trusting a host named in the
    /// message would let a page ask for another site's stored password.
    private func currentHost() -> String? {
        guard let webView, isEligible(webView) else { return nil }
        return CredentialManager.host(of: webView.url)
    }

    private func isEligible(_ webView: WKWebView) -> Bool {
        CredentialManager.isEligible(webView.url)
    }

    private static func sanitized(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        guard text.count <= maximumFieldLength else { return nil }
        return text
    }
}

// MARK: - WKScriptMessageHandler

extension AutofillBridge: WKScriptMessageHandler {

    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        // The body is whatever the page chose to send; nothing about its shape
        // can be assumed before it is checked.
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            return
        }

        Task { @MainActor in
            self.handle(type: type, body: body)
        }
    }

    @MainActor
    private func handle(type: String, body: [String: Any]) {
        guard let host = currentHost() else { return }

        switch type {
        case "detected":
            let existingUsername = Self.sanitized(body["usernameValue"]) ?? ""
            delegate?.autofillBridge(self, didReceive: .loginFormDetected(
                host: host,
                existingUsername: existingUsername
            ))

        case "submit":
            guard let password = Self.sanitized(body["password"]), !password.isEmpty else { return }
            let username = Self.sanitized(body["username"]) ?? ""
            delegate?.autofillBridge(self, didReceive: .credentialsSubmitted(
                host: host,
                username: username,
                password: password
            ))

        default:
            break
        }
    }
}
