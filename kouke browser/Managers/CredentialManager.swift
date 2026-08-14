//
//  CredentialManager.swift
//  kouke browser
//
//  Owns the saved-login list and the rules about what may be saved or filled.
//
//  KeychainStore does the storage; this type decides policy. Passwords are only
//  ever returned from an explicit call — never published, so no view, snapshot,
//  or session dump can pick one up by accident.
//

import Combine
import Foundation

@MainActor
final class CredentialManager: ObservableObject {

    static let shared = CredentialManager()

    /// Saved logins, without passwords. Safe to observe and render.
    @Published private(set) var credentials: [SavedCredential] = []

    /// Surfaced so the UI can explain a keychain failure instead of going quiet.
    @Published private(set) var lastError: String?

    private let store: KeychainStore

    init(store: KeychainStore = .shared,
         migrator: CredentialMigrator? = CredentialMigrator()) {
        self.store = store
        // Logins saved before the iCloud change live in the other keychain and
        // would read as missing until they are copied across.
        migrator?.migrateIfNeeded()
        reload()
    }

    // MARK: - Policy

    /// Hosts that are trustworthy over plain HTTP because the traffic never
    /// leaves the machine. Matches the secure-context rule browsers already use.
    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "[::1]", "::1"]

    /// Whether the browser will offer to save or fill logins for this URL.
    ///
    /// Plaintext HTTP is refused: a password filled into such a page is readable
    /// by anyone on the network path, and offering to save one teaches the habit
    /// that it is safe. Loopback is the documented exception — nothing is on the
    /// wire to intercept, and refusing it would break local development.
    nonisolated static func isEligible(_ url: URL?) -> Bool {
        guard let url, let scheme = url.scheme?.lowercased() else { return false }
        guard let host = host(of: url) else { return false }

        if scheme == "https" { return true }
        if scheme == "http" { return loopbackHosts.contains(host) }
        return false
    }

    /// Host a credential is keyed by.
    ///
    /// Matching is exact and never fuzzy. A substring or suffix test would hand
    /// `evil-example.com` (or an attacker's `example.com.evil.net`) the
    /// credentials belonging to `example.com`.
    nonisolated static func host(of url: URL?) -> String? {
        guard let host = url?.host?.lowercased(), !host.isEmpty else { return nil }
        return host
    }

    // MARK: - Reading

    func credentials(forHost host: String) -> [SavedCredential] {
        credentials.filter { $0.host == host }
    }

    func credentials(for url: URL?) -> [SavedCredential] {
        guard Self.isEligible(url), let host = Self.host(of: url) else { return [] }
        return credentials(forHost: host)
    }

    /// Fetches a password for immediate use. Never cache the result.
    func password(for credential: SavedCredential) -> String? {
        do {
            lastError = nil
            return try store.password(host: credential.host, username: credential.username)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Writing

    @discardableResult
    func save(password: String, username: String, for url: URL?) -> Bool {
        guard Self.isEligible(url), let host = Self.host(of: url) else {
            lastError = "Passwords are only saved for secure (https) sites."
            return false
        }
        return save(password: password, username: username, host: host)
    }

    @discardableResult
    func save(password: String, username: String, host: String) -> Bool {
        guard !password.isEmpty else {
            lastError = "Refusing to save an empty password."
            return false
        }

        do {
            try store.save(password: password, host: host, username: username)
            lastError = nil
            reload()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Deleting

    @discardableResult
    func delete(_ credential: SavedCredential) -> Bool {
        do {
            try store.delete(host: credential.host, username: credential.username)
            lastError = nil
            reload()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteAll() -> Bool {
        do {
            try store.deleteAll()
            lastError = nil
            reload()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Loading

    func reload() {
        do {
            credentials = try store.allCredentials().sorted { left, right in
                if left.host == right.host {
                    return left.username.localizedCaseInsensitiveCompare(right.username) == .orderedAscending
                }
                return left.host.localizedCaseInsensitiveCompare(right.host) == .orderedAscending
            }
            lastError = nil
        } catch {
            credentials = []
            lastError = error.localizedDescription
        }
    }
}
