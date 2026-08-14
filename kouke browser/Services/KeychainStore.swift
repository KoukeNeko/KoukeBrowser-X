//
//  KeychainStore.swift
//  kouke browser
//
//  Keychain access for saved website logins.
//
//  Saved logins live in the data protection keychain, marked synchronizable so
//  iCloud Keychain carries them to the user's other Macs. That needs the
//  application-identifier entitlement, which only a real provisioning profile
//  grants — an ad-hoc build gets errSecMissingEntitlement (-34018) instead.
//
//  The legacy file-based keychain is still reachable through `.legacy`, because
//  logins saved before the move live there and have to be migrated across.
//
//  This type knows nothing about browsing or policy — it is a thin, testable
//  wrapper over the Security framework. Rules about which sites may be saved
//  live in CredentialManager.
//

import Foundation
import Security

/// Failure modes callers have to handle explicitly; none are silently ignored.
enum KeychainStoreError: LocalizedError, Equatable {
    case unexpectedPasswordData
    case operationFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedPasswordData:
            return "The stored password could not be decoded."
        case .operationFailed(let status):
            let explanation = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
            return "Keychain error \(status): \(explanation)"
        }
    }
}

struct KeychainStore {

    /// Which of the two macOS keychains a store instance talks to.
    ///
    /// The distinction is not cosmetic: an item written to one is invisible to
    /// the other, which is exactly why migrating existing logins is a real step
    /// rather than a flag flip.
    enum Storage {
        /// Modern keychain, synchronized to the user's other devices by iCloud.
        case dataProtection
        /// Pre-migration home of saved logins. Read during migration only.
        case legacy
    }

    /// Distinguishes this browser's items from anything else in the keychain.
    private static let serviceLabel = "kouke browser"

    let storage: Storage

    static let shared = KeychainStore(storage: .dataProtection)

    /// Where logins saved before the iCloud move still live.
    static let legacy = KeychainStore(storage: .legacy)

    // MARK: - Writing

    /// Stores a password, replacing any existing one for the same host and user.
    func save(password: String, host: String, username: String) throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw KeychainStoreError.unexpectedPasswordData
        }

        if try contains(host: host, username: username) {
            try updatePassword(passwordData, host: host, username: username)
        } else {
            try addPassword(passwordData, host: host, username: username)
        }
    }

    private func addPassword(_ passwordData: Data, host: String, username: String) throws {
        var query = baseQuery(host: host, username: username)
        query[kSecValueData as String] = passwordData
        query[kSecAttrLabel as String] = Self.serviceLabel
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStoreError.operationFailed(status: status)
        }
    }

    private func updatePassword(_ passwordData: Data, host: String, username: String) throws {
        let query = baseQuery(host: host, username: username)
        let attributes: [String: Any] = [kSecValueData as String: passwordData]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status == errSecSuccess else {
            throw KeychainStoreError.operationFailed(status: status)
        }
    }

    // MARK: - Reading

    /// Returns the password, or nil when nothing is stored for this pair.
    func password(host: String, username: String) throws -> String? {
        var query = baseQuery(host: host, username: username)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainStoreError.operationFailed(status: status)
        }
        guard let data = item as? Data else {
            throw KeychainStoreError.unexpectedPasswordData
        }
        guard let password = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.unexpectedPasswordData
        }
        return password
    }

    func contains(host: String, username: String) throws -> Bool {
        var query = baseQuery(host: host, username: username)
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess: return true
        case errSecItemNotFound: return false
        default: throw KeychainStoreError.operationFailed(status: status)
        }
    }

    /// Every credential this browser saved, without touching the passwords.
    func allCredentials() throws -> [SavedCredential] {
        var query = everythingThisBrowserSavedQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnData as String] = false

        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)

        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else {
            throw KeychainStoreError.operationFailed(status: status)
        }
        guard let attributeList = items as? [[String: Any]] else { return [] }

        return attributeList.compactMap(Self.credential(from:))
    }

    func credentials(forHost host: String) throws -> [SavedCredential] {
        try allCredentials().filter { $0.host == host }
    }

    // MARK: - Deleting

    func delete(host: String, username: String) throws {
        let status = SecItemDelete(baseQuery(host: host, username: username) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.operationFailed(status: status)
        }
    }

    func deleteAll() throws {
        let status = SecItemDelete(everythingThisBrowserSavedQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.operationFailed(status: status)
        }
    }

    // MARK: - Query Construction

    private func baseQuery(host: String, username: String) -> [String: Any] {
        var query = storageAttributes
        query[kSecClass as String] = kSecClassInternetPassword
        query[kSecAttrServer as String] = host
        query[kSecAttrAccount as String] = username
        return query
    }

    /// Matches every login this browser saved in this store, and nothing else.
    private var everythingThisBrowserSavedQuery: [String: Any] {
        var query = storageAttributes
        query[kSecClass as String] = kSecClassInternetPassword
        query[kSecAttrLabel as String] = Self.serviceLabel
        return query
    }

    /// The attributes that decide which keychain a query reaches.
    ///
    /// `kSecAttrSynchronizable` is as much a selector as a setting: a query that
    /// omits it matches only non-synchronizable items, so leaving it off is what
    /// keeps the legacy store visible to `.legacy` and nothing else.
    private var storageAttributes: [String: Any] {
        switch storage {
        case .dataProtection:
            return [
                kSecUseDataProtectionKeychain as String: true,
                kSecAttrSynchronizable as String: true
            ]
        case .legacy:
            return [:]
        }
    }

    private static func credential(from attributes: [String: Any]) -> SavedCredential? {
        guard let host = attributes[kSecAttrServer as String] as? String,
              let username = attributes[kSecAttrAccount as String] as? String else {
            return nil
        }
        let modified = attributes[kSecAttrModificationDate as String] as? Date ?? Date()
        return SavedCredential(host: host, username: username, lastModified: modified)
    }
}
