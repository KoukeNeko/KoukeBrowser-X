//
//  CredentialMigrator.swift
//  kouke browser
//
//  Moves logins saved before the iCloud change into the data protection keychain.
//
//  The two keychains cannot see each other, so without this step every password
//  a user saved before updating would simply vanish from the UI while still
//  sitting on disk.
//
//  Nothing is ever deleted from the old keychain. A copy that leaves the source
//  intact cannot lose data if it fails halfway, and it leaves a way back if the
//  move turns out to be wrong. The cost is that one password briefly exists in
//  two places, which is the cheaper side of that trade.
//

import Foundation

/// What a migration run did, in a form the debug harness can serialize.
struct CredentialMigrationReport: Equatable {
    var copied: Int = 0
    /// Already present in the destination, so left alone — see `migrate`.
    var skipped: Int = 0
    var failures: [String] = []

    var didComplete: Bool { failures.isEmpty }

    var asDictionary: [String: Any] {
        [
            "copied": copied,
            "skipped": skipped,
            "failures": failures,
            "didComplete": didComplete
        ]
    }
}

struct CredentialMigrator {

    /// Set only after a run with no failures, so a partial run is retried rather
    /// than silently leaving some logins behind.
    private static let completionKey = "credentialsMigratedToDataProtectionKeychain"

    private let source: KeychainStore
    private let destination: KeychainStore
    private let defaults: UserDefaults

    init(source: KeychainStore = .legacy,
         destination: KeychainStore = .shared,
         defaults: UserDefaults = .standard) {
        self.source = source
        self.destination = destination
        self.defaults = defaults
    }

    var hasCompleted: Bool {
        defaults.bool(forKey: Self.completionKey)
    }

    /// Runs the migration unless a previous run already finished cleanly.
    @discardableResult
    func migrateIfNeeded() -> CredentialMigrationReport {
        guard !hasCompleted else { return CredentialMigrationReport() }
        return migrate()
    }

    /// Copies every legacy login the destination does not already hold.
    ///
    /// Existing destination entries win. A login present in both was saved again
    /// after the move, so the legacy copy is the older one and overwriting with
    /// it would undo a password the user has since changed.
    @discardableResult
    func migrate() -> CredentialMigrationReport {
        var report = CredentialMigrationReport()

        let legacyCredentials: [SavedCredential]
        do {
            legacyCredentials = try source.allCredentials()
        } catch {
            report.failures.append("reading old keychain: \(error.localizedDescription)")
            return report
        }

        for credential in legacyCredentials {
            do {
                if try destination.contains(host: credential.host,
                                            username: credential.username) {
                    report.skipped += 1
                    continue
                }
                guard let password = try source.password(host: credential.host,
                                                         username: credential.username) else {
                    // The listing said it was there, so a missing password means
                    // the item changed underneath us rather than never existing.
                    report.failures.append("\(credential.host): password could not be read")
                    continue
                }
                try destination.save(password: password,
                                     host: credential.host,
                                     username: credential.username)
                report.copied += 1
            } catch {
                report.failures.append("\(credential.host): \(error.localizedDescription)")
            }
        }

        if report.didComplete {
            defaults.set(true, forKey: Self.completionKey)
        }
        return report
    }

    /// Clears the completion flag. Test support only — the harness needs to run
    /// the migration repeatedly against seeded data.
    func resetCompletionFlag() {
        defaults.removeObject(forKey: Self.completionKey)
    }
}
