//
//  AboutPageView.swift
//  kouke browser
//
//  About page showing browser information and credits.
//

import SwiftUI

struct AboutPageView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var systemVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 80)

                // App Icon and Name
                VStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 128, height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)

                    VStack(spacing: 4) {
                        Text("Kouke Browser")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(Color("Text"))

                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(.system(size: 14))
                            .foregroundColor(Color("TextMuted"))
                    }
                }
                .padding(.bottom, 40)

                // Info Cards
                VStack(spacing: 16) {
                    InfoCard(title: "System", items: [
                        ("macOS", systemVersion),
                        ("WebKit", webKitVersion)
                    ])

                    InfoCard(title: "Credits", items: [
                        ("Developer", "Kouke Team"),
                        ("License", "MIT License")
                    ])
                }
                .frame(maxWidth: 400)

                Spacer()
                    .frame(height: 40)

                // Footer
                Text("Made with SwiftUI")
                    .font(.system(size: 12))
                    .foregroundColor(Color("TextMuted").opacity(0.6))

                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color("Bg"))
    }

    private var webKitVersion: String {
        // WebKit version is typically tied to macOS version
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "Safari \(version.majorVersion).\(version.minorVersion)"
    }
}

// MARK: - Info Card Component

private struct InfoCard: View {
    let title: String
    let items: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color("TextMuted"))
                .textCase(.uppercase)
                .kerning(0.5)

            VStack(spacing: 8) {
                ForEach(items, id: \.0) { item in
                    HStack {
                        Text(item.0)
                            .font(.system(size: 13))
                            .foregroundColor(Color("TextMuted"))

                        Spacer()

                        Text(item.1)
                            .font(.system(size: 13))
                            .foregroundColor(Color("Text"))
                    }
                }
            }
            .padding(12)
            .background(Color("CardBg"))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color("Border"), lineWidth: 1)
            )
        }
    }
}

#Preview {
    AboutPageView()
        .frame(width: 800, height: 600)
}
