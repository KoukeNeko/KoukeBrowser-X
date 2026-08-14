//
//  AppIconService.swift
//  kouke browser
//
//  Chooses which app icon variant the running app shows.
//
//  A running app's Dock tile draws `NSApp.applicationIconImage`, not the icon
//  on disk. That property resolves through LaunchServices, which has no record
//  of a build running out of a derived data directory and hands back the
//  generic placeholder — so the icon looks correct in Finder and wrong the
//  moment the app launches. Setting it explicitly fixes that, and gives the
//  appearance setting somewhere to take effect.
//

import AppKit

enum AppIconService {

    /// Asset names for the artwork shipped alongside KoukeBrowser.icon.
    private static let lightAssetName = "AppIconLight"
    private static let darkAssetName = "AppIconDark"

    /// Mono is derived rather than drawn: there is no third piece of artwork,
    /// and a desaturated icon is what the appearance is asking for.
    private static let monoSaturation: CGFloat = 0.0

    /// Applies the icon the settings ask for. Safe to call repeatedly.
    ///
    /// Does nothing before NSApplication exists — `App.init()` runs first, and
    /// `NSApp` is still nil there.
    static func apply(_ appearance: AppIconAppearance) {
        guard let application = NSApp,
              let icon = image(for: appearance) else { return }
        application.applicationIconImage = icon
    }

    static func image(for appearance: AppIconAppearance) -> NSImage? {
        switch appearance {
        case .auto:
            return image(for: systemPrefersDark ? .dark : .light)
        case .light:
            return NSImage(named: lightAssetName)
        case .dark:
            return NSImage(named: darkAssetName)
        case .mono:
            guard let base = NSImage(named: lightAssetName) else { return nil }
            return desaturated(base)
        }
    }

    private static var systemPrefersDark: Bool {
        guard let appearance = NSApp?.effectiveAppearance else { return false }
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Strips colour while keeping the artwork's shading and transparency.
    private static func desaturated(_ image: NSImage) -> NSImage? {
        guard let tiff = image.tiffRepresentation,
              let source = CIImage(data: tiff),
              let filter = CIFilter(name: "CIColorControls") else { return nil }

        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(monoSaturation, forKey: kCIInputSaturationKey)

        guard let output = filter.outputImage else { return nil }

        let representation = NSCIImageRep(ciImage: output)
        let result = NSImage(size: representation.size)
        result.addRepresentation(representation)
        return result
    }
}
