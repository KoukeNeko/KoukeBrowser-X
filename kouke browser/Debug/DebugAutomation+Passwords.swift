//
//  DebugAutomation+Passwords.swift
//  kouke browser
//
//  Harness commands for verifying the password manager against the real
//  keychain, rather than a stand-in that could hide a Security framework
//  problem.
//
//  Every command works only on hosts under a reserved test suffix, so a run can
//  never read or delete a real saved login.
//

#if DEBUG

import AppKit
import Foundation

/// Commands that run synchronously against the credential store.
enum PasswordCommand: String {
    case credentialSave = "credential_save"
    case credentialList = "credential_list"
    case credentialRead = "credential_read"
    case credentialDelete = "credential_delete"
    case credentialResetTestData = "credential_reset_test_data"
    case credentialPolicy = "credential_policy"
    case credentialLegacySave = "credential_legacy_save"
    case credentialLegacyList = "credential_legacy_list"
    case credentialMigrate = "credential_migrate"
    case credentialMigrationState = "credential_migration_state"
    case autofillPrompt = "autofill_prompt"
    case autofillPromptAccept = "autofill_prompt_accept"
    case autofillPromptDismiss = "autofill_prompt_dismiss"
}

@MainActor
extension DebugAutomation {

    /// Only hosts ending in this suffix may be touched by the harness.
    ///
    /// `.invalid` is reserved by RFC 2606 and can never be a real site, so a
    /// stray test run cannot collide with a password the user actually saved.
    private static var testHostSuffix: String { ".kouke-test.invalid" }

    /// Fixtures are served from loopback, so end-to-end checks need credentials
    /// stored against it. Loopback is not disposable the way `.invalid` is — a
    /// developer may have real logins for a local site — so those are allowed
    /// only under a username no real login would use.
    private static var loopbackHost: String { "127.0.0.1" }
    private static var harnessUsernamePrefix: String { "kouke-harness-" }

    private static func isHarnessOwned(host: String, username: String) -> Bool {
        if host.hasSuffix(testHostSuffix) { return true }
        return host == loopbackHost && username.hasPrefix(harnessUsernamePrefix)
    }

    private static func isHarnessOwned(_ credential: SavedCredential) -> Bool {
        isHarnessOwned(host: credential.host, username: credential.username)
    }

    func executePasswordCommand(_ command: PasswordCommand,
                                arguments: [String: Any]) -> Result<String, Error> {
        do {
            switch command {
            case .credentialSave:
                return .success(try saveCredential(arguments))
            case .credentialList:
                return .success(try listCredentials(arguments))
            case .credentialRead:
                return .success(try readCredential(arguments))
            case .credentialDelete:
                return .success(try deleteCredential(arguments))
            case .credentialResetTestData:
                return .success(try resetTestCredentials())
            case .credentialPolicy:
                return .success(try evaluatePolicy(arguments))
            case .credentialLegacySave:
                return .success(try saveLegacyCredential(arguments))
            case .credentialLegacyList:
                return .success(try listLegacyCredentials())
            case .credentialMigrate:
                return .success(try runCredentialMigration())
            case .credentialMigrationState:
                return .success(try reportMigrationState())
            case .autofillPrompt:
                return .success(try reportAutofillPrompt(arguments))
            case .autofillPromptAccept:
                return .success(try acceptAutofillPrompt(arguments))
            case .autofillPromptDismiss:
                return .success(try dismissAutofillPrompt(arguments))
            }
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Commands

    private func saveCredential(_ arguments: [String: Any]) throws -> String {
        let username = try requiredString(arguments, key: "username")
        let host = try harnessHost(arguments, username: username)
        let password = try requiredString(arguments, key: "password")

        let saved = CredentialManager.shared.save(password: password, username: username, host: host)
        return try encodePasswordJSON([
            "saved": saved,
            "error": CredentialManager.shared.lastError ?? NSNull()
        ])
    }

    private func listCredentials(_ arguments: [String: Any]) throws -> String {
        let matching: [SavedCredential]
        if let host = arguments["host"] as? String {
            matching = CredentialManager.shared.credentials(forHost: host)
        } else {
            matching = CredentialManager.shared.credentials.filter {
                $0.host.hasSuffix(Self.testHostSuffix)
            }
        }

        let described = matching.map { ["host": $0.host, "username": $0.username] }
        return try encodePasswordJSON(["credentials": described, "count": described.count])
    }

    private func readCredential(_ arguments: [String: Any]) throws -> String {
        let username = try requiredString(arguments, key: "username")
        let host = try harnessHost(arguments, username: username)

        let credential = SavedCredential(host: host, username: username)
        let password = CredentialManager.shared.password(for: credential)

        return try encodePasswordJSON([
            "found": password != nil,
            "password": password ?? NSNull()
        ])
    }

    private func deleteCredential(_ arguments: [String: Any]) throws -> String {
        let username = try requiredString(arguments, key: "username")
        let host = try harnessHost(arguments, username: username)

        let deleted = CredentialManager.shared.delete(SavedCredential(host: host, username: username))
        return try encodePasswordJSON([
            "deleted": deleted,
            "error": CredentialManager.shared.lastError ?? NSNull()
        ])
    }

    /// Removes only this harness's own credentials, from both keychains.
    ///
    /// The old keychain has to be swept too: anything left there would be picked
    /// up by the next migration run and show up as a login the run never seeded.
    private func resetTestCredentials() throws -> String {
        let manager = CredentialManager.shared
        let testCredentials = manager.credentials.filter(Self.isHarnessOwned)
        for credential in testCredentials {
            manager.delete(credential)
        }

        let legacyCredentials = try KeychainStore.legacy.allCredentials().filter(Self.isHarnessOwned)
        for credential in legacyCredentials {
            try KeychainStore.legacy.delete(host: credential.host, username: credential.username)
        }

        CredentialMigrator().resetCompletionFlag()

        return try encodePasswordJSON([
            "removed": testCredentials.count,
            "removedLegacy": legacyCredentials.count
        ])
    }

    // MARK: - Migration Commands

    /// Seeds a login in the old keychain, standing in for one saved before the
    /// iCloud change. Writes straight to the store: CredentialManager only ever
    /// talks to the new keychain, so it cannot produce this starting state.
    private func saveLegacyCredential(_ arguments: [String: Any]) throws -> String {
        let username = try requiredString(arguments, key: "username")
        let host = try harnessHost(arguments, username: username)
        let password = try requiredString(arguments, key: "password")

        try KeychainStore.legacy.save(password: password, host: host, username: username)
        return try encodePasswordJSON(["saved": true])
    }

    /// The harness's own logins still in the old keychain. Migration must leave
    /// these in place, so the check needs to see them directly.
    private func listLegacyCredentials() throws -> String {
        let legacy = try KeychainStore.legacy.allCredentials().filter(Self.isHarnessOwned)
        let described = legacy.map { ["host": $0.host, "username": $0.username] }
        return try encodePasswordJSON(["credentials": described, "count": described.count])
    }

    /// Forces a migration run regardless of whether one already completed.
    private func runCredentialMigration() throws -> String {
        let migrator = CredentialMigrator()
        migrator.resetCompletionFlag()
        let report = migrator.migrate()
        CredentialManager.shared.reload()
        return try encodePasswordJSON(report.asDictionary)
    }

    private func reportMigrationState() throws -> String {
        try encodePasswordJSON(["hasCompleted": CredentialMigrator().hasCompleted])
    }

    /// Reports the save/fill eligibility decision for a URL, so the security
    /// rules can be asserted directly instead of inferred from behaviour.
    private func evaluatePolicy(_ arguments: [String: Any]) throws -> String {
        let urlString = try requiredString(arguments, key: "url")
        let url = URL(string: urlString)

        return try encodePasswordJSON([
            "url": urlString,
            "eligible": CredentialManager.isEligible(url),
            "host": CredentialManager.host(of: url) ?? NSNull()
        ])
    }

    // MARK: - Prompt Commands

    /// Reports what the browser is currently asking the user, so the prompt can
    /// be asserted without needing to click the card.
    private func reportAutofillPrompt(_ arguments: [String: Any]) throws -> String {
        guard let viewModel = activeViewModel(arguments) else {
            throw DebugAutomationError.windowNotFound
        }

        guard let prompt = viewModel.autofillPrompt else {
            return try encodePasswordJSON(["kind": "none"])
        }

        switch prompt {
        case .offerToFill(_, let host, let credentials):
            return try encodePasswordJSON([
                "kind": "fill",
                "host": host,
                "usernames": credentials.map(\.username)
            ])
        case .offerToSave(_, let host, let username, _):
            return try encodePasswordJSON(["kind": "save", "host": host, "username": username])
        case .offerToUpdate(_, let host, let username, _):
            return try encodePasswordJSON(["kind": "update", "host": host, "username": username])
        }
    }

    /// Performs what the prompt's primary button would do.
    private func acceptAutofillPrompt(_ arguments: [String: Any]) throws -> String {
        guard let viewModel = activeViewModel(arguments) else {
            throw DebugAutomationError.windowNotFound
        }
        guard let prompt = viewModel.autofillPrompt else {
            throw DebugAutomationError.badArguments("no autofill prompt is showing")
        }

        switch prompt {
        case .offerToFill(let tabId, _, let credentials):
            let requested = arguments["username"] as? String
            let chosen = requested.flatMap { name in credentials.first { $0.username == name } }
                ?? credentials.first
            guard let chosen else {
                throw DebugAutomationError.badArguments("prompt offered no credentials")
            }
            viewModel.fillCredential(chosen, in: tabId)
            return try encodePasswordJSON(["accepted": "fill", "username": chosen.username])

        case .offerToSave(_, let host, let username, let password),
             .offerToUpdate(_, let host, let username, let password):
            viewModel.saveSubmittedCredential(host: host, username: username, password: password)
            return try encodePasswordJSON(["accepted": "save", "host": host, "username": username])
        }
    }

    private func dismissAutofillPrompt(_ arguments: [String: Any]) throws -> String {
        guard let viewModel = activeViewModel(arguments) else {
            throw DebugAutomationError.windowNotFound
        }
        viewModel.dismissAutofillPrompt()
        return try encodePasswordJSON(["dismissed": true])
    }

    private func activeViewModel(_ arguments: [String: Any]) -> BrowserViewModel? {
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

    // MARK: - Helpers

    private func harnessHost(_ arguments: [String: Any], username: String) throws -> String {
        let host = try requiredString(arguments, key: "host")
        guard Self.isHarnessOwned(host: host, username: username) else {
            throw DebugAutomationError.badArguments(
                "refusing to touch \(host): harness hosts must end in \(Self.testHostSuffix), "
                + "or be \(Self.loopbackHost) with a \(Self.harnessUsernamePrefix) username"
            )
        }
        return host
    }

    private func requiredString(_ arguments: [String: Any], key: String) throws -> String {
        guard let value = arguments[key] as? String else {
            throw DebugAutomationError.badArguments("\(key) is required")
        }
        return value
    }

    private func encodePasswordJSON(_ value: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw DebugAutomationError.badArguments("could not encode result as JSON")
        }
        return text
    }
}

#endif
