//
//  SecurityInfo.swift
//  kouke browser
//
//  Security information model for tracking page connection security state.
//

import Foundation

// MARK: - Security Level

/// Represents the security level of a page connection
enum SecurityLevel: Equatable {
    case secure          // HTTPS with valid certificate
    case insecure        // HTTP (no encryption)
    case mixed           // HTTPS but with mixed content
    case local           // Local/internal pages (kouke:, file:, etc.)
    case unknown         // Unable to determine

    var icon: String {
        switch self {
        case .secure:   return "lock.fill"
        case .insecure: return "lock.open.fill"
        case .mixed:    return "exclamationmark.lock.fill"
        case .local:    return "doc.fill"
        case .unknown:  return "questionmark.circle"
        }
    }

    var displayTitle: String {
        switch self {
        case .secure:   return "Connection is Secure"
        case .insecure: return "Connection is Not Secure"
        case .mixed:    return "Partially Secure"
        case .local:    return "Local Page"
        case .unknown:  return "Unknown"
        }
    }

    var displayDescription: String {
        switch self {
        case .secure:
            return "This site uses a secure connection (HTTPS). Your information is encrypted."
        case .insecure:
            return "This site uses an insecure connection (HTTP). Do not enter sensitive information."
        case .mixed:
            return "Some content on this page is loaded over an insecure connection."
        case .local:
            return "This is a browser internal page."
        case .unknown:
            return "Unable to determine the security status of this page."
        }
    }
}

// MARK: - Certificate Info

/// SSL/TLS certificate information
struct CertificateInfo: Equatable {
    let subject: String           // Certificate subject (issued to)
    let issuer: String            // Certificate issuer
    let validFrom: Date?          // Certificate valid from date
    let validUntil: Date?         // Certificate expiration date
    let serialNumber: String?     // Certificate serial number
    let version: Int?             // Certificate version (1, 2, or 3)
    let signatureAlgorithm: String?  // e.g., "SHA-256 with RSA"
    let publicKeyAlgorithm: String?  // e.g., "RSA", "EC"
    let publicKeySize: Int?       // e.g., 2048, 256
    let sha256Fingerprint: String?   // SHA-256 fingerprint

    /// Formatted validity period string
    var validityPeriod: String? {
        guard let from = validFrom, let until = validUntil else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "en_US")
        return "\(formatter.string(from: from)) - \(formatter.string(from: until))"
    }

    /// Formatted valid from date
    var formattedValidFrom: String? {
        guard let from = validFrom else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: from)
    }

    /// Formatted valid until date
    var formattedValidUntil: String? {
        guard let until = validUntil else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: until)
    }

    /// Check if certificate is currently valid
    var isValid: Bool {
        guard let from = validFrom, let until = validUntil else { return false }
        let now = Date()
        return now >= from && now <= until
    }

    /// Days until expiration
    var daysUntilExpiration: Int? {
        guard let until = validUntil else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: until).day
        return days
    }

    /// Public key description
    var publicKeyDescription: String? {
        guard let algo = publicKeyAlgorithm else { return nil }
        if let size = publicKeySize {
            return "\(algo) \(size) bits"
        }
        return algo
    }
}

// MARK: - Security Info

/// Complete security information for a page
struct SecurityInfo: Equatable {
    let level: SecurityLevel
    let certificate: CertificateInfo?
    let protocol_: String?      // e.g., "TLS 1.3"
    let host: String?

    /// Create security info from URL scheme
    static func fromURL(_ urlString: String) -> SecurityInfo {
        guard let url = URL(string: urlString) else {
            return SecurityInfo(level: .unknown, certificate: nil, protocol_: nil, host: nil)
        }

        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host

        switch scheme {
        case "https":
            // Default to secure for HTTPS, will be updated with actual cert info
            return SecurityInfo(level: .secure, certificate: nil, protocol_: nil, host: host)
        case "http":
            return SecurityInfo(level: .insecure, certificate: nil, protocol_: nil, host: host)
        case "kouke", "about", "file":
            return SecurityInfo(level: .local, certificate: nil, protocol_: nil, host: host)
        default:
            return SecurityInfo(level: .unknown, certificate: nil, protocol_: nil, host: host)
        }
    }
}
