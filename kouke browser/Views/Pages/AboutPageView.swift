//
//  AboutPageView.swift
//  kouke browser
//
//  About page showing browser information and credits.
//

import SwiftUI
import AppKit

struct AboutPageView: View {
    @ObservedObject private var settings = BrowserSettings.shared

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var systemVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    /// The app icon, read from this bundle rather than from `NSApp`.
    ///
    /// `NSApp.applicationIconImage` resolves through LaunchServices, which has
    /// no record of a build running out of a derived data directory and hands
    /// back the generic placeholder icon instead of the real artwork. Reading
    /// the bundle's own icon shows the right thing in every build, and the name
    /// comes from Info.plist so renaming the icon does not silently break this.
    private var appIcon: NSImage {
        let iconName = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String

        if let iconName {
            if let fromCatalog = NSImage(named: iconName) {
                return fromCatalog
            }
            if let iconURL = Bundle.main.url(forResource: iconName, withExtension: "icns"),
               let fromResource = NSImage(contentsOf: iconURL) {
                return fromResource
            }
        }

        return NSApp.applicationIconImage
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 80)

                // App Icon and Name
                VStack(spacing: 16) {
                    // No clip shape: a macOS icon already carries its own
                    // rounded silhouette, and masking it again cuts the corners
                    // twice at slightly different radii.
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 128, height: 128)
                        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)

                    VStack(spacing: 4) {
                        Text("Ciruvo")
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
        .background(ChromePageBackground(appearance: settings.chromeAppearance,
                                         page: KoukeScheme.about))
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
