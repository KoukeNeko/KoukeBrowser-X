//
//  BrowserViewModel+Autofill.swift
//  kouke browser
//
//  Turns page reports into the prompts the user sees, and carries out whatever
//  they choose.
//
//  Kept apart from BrowserViewModel so the autofill rules stay readable and can
//  be reviewed on their own.
//

import Foundation
import WebKit

// MARK: - Receiving Page Reports

extension BrowserViewModel: AutofillBridgeDelegate {

    func autofillBridge(_ bridge: AutofillBridge, didReceive event: AutofillPageEvent) {
        guard BrowserSettings.shared.enablePasswordManager else { return }

        // A background tab must not interrupt what the user is looking at.
        guard bridge.tabId == activeTabId else { return }

        switch event {
        case .loginFormDetected(let host, _):
            presentFillOfferIfCredentialsExist(host: host, tabId: bridge.tabId)

        case .credentialsSubmitted(let host, let username, let password):
            presentSaveOfferIfNew(host: host, username: username,
                                  password: password, tabId: bridge.tabId)
        }
    }

    private func presentFillOfferIfCredentialsExist(host: String, tabId: UUID) {
        // A save or update offer reflects something the user just did, so it
        // outranks a detection notice raised by the page re-rendering.
        if case .offerToSave = autofillPrompt { return }
        if case .offerToUpdate = autofillPrompt { return }

        let matches = CredentialManager.shared.credentials(forHost: host)
        guard !matches.isEmpty else {
            autofillPrompt = nil
            return
        }
        autofillPrompt = .offerToFill(tabId: tabId, host: host, credentials: matches)
    }

    private func presentSaveOfferIfNew(host: String, username: String,
                                       password: String, tabId: UUID) {
        let existing = CredentialManager.shared.credentials(forHost: host)
            .first { $0.username == username }

        guard let existing else {
            autofillPrompt = .offerToSave(tabId: tabId, host: host,
                                          username: username, password: password)
            return
        }

        // Nothing to ask about when the stored password already matches.
        guard CredentialManager.shared.password(for: existing) != password else {
            autofillPrompt = nil
            return
        }

        autofillPrompt = .offerToUpdate(tabId: tabId, host: host,
                                        username: username, password: password)
    }
}

// MARK: - Acting On A Prompt

extension BrowserViewModel {

    /// Fills a chosen credential into the page it was offered for.
    func fillCredential(_ credential: SavedCredential, in tabId: UUID) {
        guard let bridge = autofillBridge(for: tabId) else { return }

        guard let password = CredentialManager.shared.password(for: credential) else {
            autofillPrompt = nil
            return
        }

        Task { @MainActor in
            _ = await bridge.fill(username: credential.username, password: password)
            self.autofillPrompt = nil
        }
    }

    func saveSubmittedCredential(host: String, username: String, password: String) {
        CredentialManager.shared.save(password: password, username: username, host: host)
        autofillPrompt = nil
    }

    func dismissAutofillPrompt() {
        autofillPrompt = nil
    }

    private func autofillBridge(for tabId: UUID) -> AutofillBridge? {
        (getWebView(for: tabId) as? KoukeWebView)?.autofillBridge
    }
}
