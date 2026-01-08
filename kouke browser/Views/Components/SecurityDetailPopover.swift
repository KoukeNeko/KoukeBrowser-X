//
//  SecurityDetailPopover.swift
//  kouke browser
//
//  Popover view displaying security information for the current page.
//

import SwiftUI

struct SecurityDetailPopover: View {
    let securityInfo: SecurityInfo?
    let url: String
    @Environment(\.dismiss) private var dismiss

    private var displayInfo: SecurityInfo {
        securityInfo ?? SecurityInfo.fromURL(url)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            SheetHeader(
                title: "Security Info",
                onDismiss: { dismiss() }
            )

            Divider()

            // Content - scrollable
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Security status section
                    securityStatusSection

                    Divider()

                    // Certificate info section (only for HTTPS)
                    if displayInfo.level == .secure, let cert = displayInfo.certificate {
                        certificateSection(cert)

                        Divider()

                        validitySection(cert)

                        Divider()

                        technicalSection(cert)

                        if let fingerprint = cert.sha256Fingerprint {
                            Divider()
                            fingerprintSection(fingerprint)
                        }
                    }

                    // Host info
                    if let host = displayInfo.host {
                        hostSection(host)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 340)
        .frame(minHeight: 300, maxHeight: 500)
        .background(Color("Bg"))
    }

    // MARK: - Sections

    private var securityStatusSection: some View {
        HStack(spacing: 12) {
            Image(systemName: displayInfo.level.icon)
                .font(.system(size: 24))
                .foregroundColor(iconColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayInfo.level.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color("Text"))

                Text(displayInfo.level.displayDescription)
                    .font(.system(size: 12))
                    .foregroundColor(Color("TextMuted"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func certificateSection(_ cert: CertificateInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Certificate")

            VStack(alignment: .leading, spacing: 8) {
                certificateRow(label: "Issued To", value: cert.subject)
                certificateRow(label: "Issued By", value: cert.issuer)

                if let version = cert.version {
                    certificateRow(label: "Version", value: "V\(version)")
                }

                if let serial = cert.serialNumber {
                    certificateRow(label: "Serial Number", value: serial)
                }
            }
        }
    }

    private func validitySection(_ cert: CertificateInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Validity")

            VStack(alignment: .leading, spacing: 8) {
                if let from = cert.formattedValidFrom {
                    certificateRow(label: "Not Before", value: from)
                }

                if let until = cert.formattedValidUntil {
                    certificateRow(label: "Not After", value: until)
                }

                if let days = cert.daysUntilExpiration {
                    let statusColor: Color = days < 30 ? .orange : (days < 7 ? .red : .green)
                    HStack {
                        Text("Expires In")
                            .font(.system(size: 10))
                            .foregroundColor(Color("TextMuted"))
                        Spacer()
                        Text("\(days) days")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(statusColor)
                    }
                }
            }
        }
    }

    private func technicalSection(_ cert: CertificateInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Technical Details")

            VStack(alignment: .leading, spacing: 8) {
                if let pubKey = cert.publicKeyDescription {
                    certificateRow(label: "Public Key", value: pubKey)
                }

                if let sigAlg = cert.signatureAlgorithm {
                    certificateRow(label: "Signature Algorithm", value: sigAlg)
                }
            }
        }
    }

    private func fingerprintSection(_ fingerprint: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Fingerprint")

            VStack(alignment: .leading, spacing: 4) {
                Text("SHA-256")
                    .font(.system(size: 10))
                    .foregroundColor(Color("TextMuted"))

                Text(fingerprint)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color("Text"))
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func hostSection(_ host: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Host")

            Text(host)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color("Text"))
                .textSelection(.enabled)
        }
    }

    // MARK: - Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color("TextMuted"))
            .textCase(.uppercase)
    }

    private func certificateRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color("TextMuted"))

            Text(value)
                .font(.system(size: 12))
                .foregroundColor(Color("Text"))
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
        }
    }

    // MARK: - Helpers

    private var iconColor: Color {
        switch displayInfo.level {
        case .secure:
            return .green
        case .insecure:
            return .red
        case .mixed:
            return .orange
        case .local, .unknown:
            return Color("TextMuted")
        }
    }
}

#Preview {
    SecurityDetailPopover(
        securityInfo: SecurityInfo(
            level: .secure,
            certificate: CertificateInfo(
                subject: "*.google.com",
                issuer: "GTS CA 1C3",
                validFrom: Date(),
                validUntil: Date().addingTimeInterval(86400 * 90),
                serialNumber: "01:23:45:67:89:AB:CD:EF",
                version: 3,
                signatureAlgorithm: "ECDSA with SHA-256",
                publicKeyAlgorithm: "ECDSA",
                publicKeySize: 256,
                sha256Fingerprint: "A1:B2:C3:D4:E5:F6:A1:B2:C3:D4:E5:F6:A1:B2:C3:D4:E5:F6:A1:B2:C3:D4:E5:F6:A1:B2:C3:D4:E5:F6:A1:B2"
            ),
            protocol_: "TLS 1.3",
            host: "www.google.com"
        ),
        url: "https://www.google.com"
    )
}
