//
//  DebugAutomation+KeychainProbe.swift
//  kouke browser
//
//  SPIKE (iCloud 3.0) — measures which keychain the app can actually reach.
//
//  The answer depends entirely on the code signature: the data protection
//  keychain needs an application-identifier entitlement, which only a real
//  provisioning profile can grant. An ad-hoc build reports errSecMissingEntitlement
//  (-34018) here, which is exactly how the current KeychainStore came to use the
//  legacy keychain. This command exists so that conclusion can be re-measured
//  instead of assumed.
//
//  Everything is written under a host reserved by RFC 2606, so a run can never
//  touch a credential the user actually saved.
//

#if DEBUG

import Foundation
import Security

enum KeychainProbeCommand: String {
    case keychainProbe = "keychain_probe"
}

/// One keychain configuration and what happened when the app used it.
private struct KeychainProbeResult {
    let label: String
    let addStatus: OSStatus
    let readStatus: OSStatus?
    let readBackMatched: Bool?

    var asDictionary: [String: Any] {
        var result: [String: Any] = [
            "label": label,
            "addStatus": Int(addStatus),
            "addMessage": KeychainProbeResult.describe(addStatus),
            "usable": addStatus == errSecSuccess
        ]
        if let readStatus {
            result["readStatus"] = Int(readStatus)
            result["readMessage"] = KeychainProbeResult.describe(readStatus)
        }
        if let readBackMatched {
            result["readBackMatched"] = readBackMatched
        }
        return result
    }

    static func describe(_ status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
    }
}

@MainActor
extension DebugAutomation {

    /// Reserved by RFC 2606; can never resolve to a real site.
    private static var probeHost: String { "icloud-spike.kouke-test.invalid" }
    private static var probeAccount: String { "kouke-harness-spike" }
    private static var probeSecret: String { "probe-value" }

    func executeKeychainProbeCommand(_ command: KeychainProbeCommand,
                                     arguments: [String: Any]) -> Result<String, Error> {
        switch command {
        case .keychainProbe:
            return reportKeychainProbe()
        }
    }

    private func reportKeychainProbe() -> Result<String, Error> {
        let results = [
            runProbe(label: "legacy", dataProtection: false, synchronizable: false),
            runProbe(label: "dataProtection", dataProtection: true, synchronizable: false),
            runProbe(label: "dataProtectionSynchronizable", dataProtection: true, synchronizable: true)
        ]

        let payload: [String: Any] = [
            "results": results.map(\.asDictionary),
            "hasApplicationIdentifier": Self.hasApplicationIdentifierEntitlement
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: payload,
                                                  options: [.sortedKeys])
            return .success(String(decoding: data, as: UTF8.self))
        } catch {
            return .failure(error)
        }
    }

    /// A full write / read-back / delete cycle under one configuration.
    private func runProbe(label: String,
                          dataProtection: Bool,
                          synchronizable: Bool) -> KeychainProbeResult {
        var query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: Self.probeHost,
            kSecAttrAccount as String: Self.probeAccount
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        if synchronizable {
            query[kSecAttrSynchronizable as String] = true
        }

        // Residue from an earlier run would turn a fresh add into a duplicate
        // error and misreport the configuration as unusable.
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = Data(Self.probeSecret.utf8)
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        guard addStatus == errSecSuccess else {
            return KeychainProbeResult(label: label, addStatus: addStatus,
                                       readStatus: nil, readBackMatched: nil)
        }

        var readQuery = query
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let readStatus = SecItemCopyMatching(readQuery as CFDictionary, &item)
        let matched = (item as? Data).map { $0 == Data(Self.probeSecret.utf8) }

        SecItemDelete(query as CFDictionary)

        return KeychainProbeResult(label: label, addStatus: addStatus,
                                   readStatus: readStatus, readBackMatched: matched)
    }

    /// Whether the running binary carries the entitlement the data protection
    /// keychain requires. Reported alongside the probe so a failure can be told
    /// apart from a signing problem.
    private static var hasApplicationIdentifierEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        // macOS namespaces this entitlement; the bare key reads as absent even
        // on a correctly provisioned build.
        let keys = ["com.apple.application-identifier", "application-identifier"]
        return keys.contains { key in
            SecTaskCopyValueForEntitlement(task, key as CFString, nil) != nil
        }
    }
}

#endif
