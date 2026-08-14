//
//  SavedCredential.swift
//  kouke browser
//
//  A login saved for a site.
//
//  Deliberately carries no password. The secret lives only in the keychain and
//  is fetched for the moment it is used, so it never sits in an observable
//  property, a session dump, or a crash log.
//

import Foundation

struct SavedCredential: Identifiable, Equatable, Hashable {

    /// Host the credential belongs to, e.g. `accounts.example.com`.
    let host: String

    /// Username as stored in the login form.
    let username: String

    let lastModified: Date

    /// Stable across launches: the keychain treats (server, account) as the
    /// primary key, so the same pair always identifies the same credential.
    var id: String { "\(host)\u{0000}\(username)" }

    init(host: String, username: String, lastModified: Date = Date()) {
        self.host = host
        self.username = username
        self.lastModified = lastModified
    }
}

// MARK: - Display Helpers

extension SavedCredential {

    /// Host without a leading `www.`, for a less noisy list.
    var displayHost: String {
        let prefix = "www."
        guard host.hasPrefix(prefix) else { return host }
        return String(host.dropFirst(prefix.count))
    }

    var displayUsername: String {
        username.isEmpty ? "(no username)" : username
    }
}
