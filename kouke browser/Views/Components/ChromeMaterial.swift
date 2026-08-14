//
//  ChromeMaterial.swift
//  kouke browser
//
//  Backgrounds for the browser chrome — the tab bar, the address bar and the
//  tabs themselves — under each ChromeAppearance.
//
//  Solid paints flat asset colours, the look kouke shipped with. Normal and
//  Liquid Glass are translucent, and translucency is a window property as much
//  as a view one: both materials sample what lies behind the *window*, so the
//  window has to stop painting its own opaque background first. That part is
//  `NSWindow.applyChromeBackground(_:)`.
//

import SwiftUI
import AppKit

// MARK: - Chrome Band

/// The background of a full-width chrome strip.
struct ChromeBandBackground: View {
    let appearance: ChromeAppearance
    /// The band's own colour: painted flat under Solid, and tinting the blur
    /// under Normal.
    let solidColor: Color
    var identifier: NSUserInterfaceItemIdentifier = ChromeMaterialIdentifier.chrome

    /// How much of the band's own colour survives over the blur.
    ///
    /// Without it the band takes the colour of whatever happens to be behind
    /// the window, and the chrome stops looking like kouke's — Normal is meant
    /// to be Solid you can see through, not a hole in the window. Raising this
    /// makes the chrome more solid, lowering it lets more of the desktop read.
    private static let blurTintOpacity: Double = 0.6

    var body: some View {
        switch appearance {
        case .solid:
            solidColor
        case .normal:
            VisualEffectBackground(material: .titlebar, identifier: identifier)
                .overlay(solidColor.opacity(Self.blurTintOpacity))
        case .liquidGlass:
            GlassBackground(identifier: identifier)
        }
    }
}

/// The hairline under a chrome strip. Glass draws its own edge, so a drawn line
/// there reads as a seam rather than a separator.
struct ChromeDivider: View {
    let appearance: ChromeAppearance

    var body: some View {
        if appearance.showsChromeDivider {
            Rectangle()
                .fill(Color("Border"))
                .frame(height: 1)
        }
    }
}

// MARK: - Tab Fill

/// The fill behind a single tab.
///
/// Under both translucent styles an unselected tab has no fill of its own: it
/// shows the band, so it reads as part of the strip the way Safari's do. Only
/// the selected tab is drawn — with Solid's fill under Normal, and as a clear
/// glass capsule under Liquid Glass.
struct ChromeTabBackground: View {
    let appearance: ChromeAppearance
    let isActive: Bool

    private static let glassInset: CGFloat = 4
    private static let glassCornerRadius: CGFloat = 8

    var body: some View {
        switch appearance {
        case .solid:
            isActive ? Color("TabActive") : Color("TabInactive")
        case .normal:
            isActive ? Color("TabActive") : Color.clear
        case .liquidGlass:
            if isActive {
                GlassBackground(cornerRadius: Self.glassCornerRadius, isClear: true)
                    .padding(Self.glassInset)
            } else {
                Color.clear
            }
        }
    }
}

// MARK: - Page Body

/// The background of an internal page that follows the chrome appearance —
/// see `KoukeScheme.followsChromeAppearance`. Web content is never translucent:
/// a site must not be see-through.
///
/// Both translucent styles use the window blur rather than glass. Glass is a
/// material for chrome and controls; stretched over a whole page it stops
/// reading as a surface behind the content and starts reading as a pane laid
/// on top of it. `.underWindowBackground` is what macOS uses for a translucent
/// window body, which is what a full-page surface is.
struct ChromePageBackground: View {
    let appearance: ChromeAppearance
    /// The page being painted, as its `kouke:` URL.
    let page: String

    var body: some View {
        if appearance.isTranslucent {
            VisualEffectBackground(material: .underWindowBackground,
                                   identifier: ChromeMaterialIdentifier.page(page))
        } else {
            Color("Bg")
        }
    }
}

// MARK: - Popovers

/// The background of a floating panel — the bookmarks and downloads popovers,
/// the address bar dropdown, the security details.
///
/// One look per appearance, the same way the chrome works: flat under Solid,
/// blurred under Normal, glass under Liquid Glass. `.popover` is the material
/// AppKit uses for exactly this surface, so Normal gets the system's own panel
/// blur rather than the title bar's.
struct ChromePopoverBackground: View {
    let appearance: ChromeAppearance

    var body: some View {
        material
            // A backdrop has nothing to respond to, and an AppKit view sitting
            // behind SwiftUI content would otherwise take clicks and focus that
            // belong to the panel's own controls.
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var material: some View {
        switch appearance {
        case .solid:
            Color("Bg")
        case .normal:
            VisualEffectBackground(material: .popover,
                                   identifier: ChromeMaterialIdentifier.popover)
        case .liquidGlass:
            GlassBackground(identifier: ChromeMaterialIdentifier.popover)
        }
    }
}

extension View {
    /// Paints a presented panel — a popover or a sheet — with the chrome
    /// material.
    ///
    /// The material goes on the *presentation*, not on the content. A popover
    /// draws its own arrow out of the system's background, so painting only the
    /// content leaves the arrow in a different material and a seam shows where
    /// the two meet: the panel reads as two pieces rather than one. Safari's
    /// popovers look continuous because the arrow and the body are the same
    /// surface, and this is what makes ours behave the same way.
    func chromePanelBackground() -> some View {
        modifier(ChromePanelBackground())
    }
}

private struct ChromePanelBackground: ViewModifier {
    @ObservedObject private var settings = BrowserSettings.shared

    func body(content: Content) -> some View {
        content.presentationBackground {
            ChromePopoverBackground(appearance: settings.chromeAppearance)
        }
    }
}

// MARK: - Materials

/// Identifiers on the material views.
///
/// AppKit creates visual effect views of its own inside a window's frame, so a
/// test that only looked for the class could not tell ours apart from the
/// system's. Naming them makes the harness's assertions exact.
enum ChromeMaterialIdentifier {
    /// Chrome materials no test needs to single out.
    static let chrome = NSUserInterfaceItemIdentifier("KoukeChrome")
    /// The address bar band and its input capsule, which the address bar can be
    /// opted out of drawing at all.
    static let addressBar = NSUserInterfaceItemIdentifier("KoukeChromeAddressBar")
    static let addressField = NSUserInterfaceItemIdentifier("KoukeChromeAddressField")
    /// Floating panels: bookmarks, downloads, the address bar dropdown.
    static let popover = NSUserInterfaceItemIdentifier("KoukeChromePopover")

    /// One per page. Hidden tabs stay in the view tree, so a single shared
    /// identifier could not say which page painted the material found there.
    static func page(_ koukeURL: String) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("KoukeChromePage:\(koukeURL)")
    }
}

/// A behind-window blur. `.titlebar` is the material AppKit uses for a
/// translucent title bar, which is exactly the band this sits in.
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    var identifier: NSUserInterfaceItemIdentifier = ChromeMaterialIdentifier.chrome

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        // Matches every other macOS window chrome: the blur fades out when the
        // window is not in front.
        view.state = .followsWindowActiveState
        view.identifier = identifier
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

/// The macOS 26 glass material.
///
/// Glass only exists on macOS 26 and the deployment target is older, so this is
/// the single place that degrades: below 26 it produces the same blur Normal
/// uses. Call sites never have to branch on the OS version.
struct GlassBackground: NSViewRepresentable {
    var cornerRadius: CGFloat = 0
    /// Clear glass passes far more of the backdrop through than regular glass.
    /// A Bool rather than `NSGlassEffectView.Style`, which does not exist below
    /// macOS 26 and so cannot be stored here.
    var isClear: Bool = false
    var identifier: NSUserInterfaceItemIdentifier = ChromeMaterialIdentifier.chrome

    func makeNSView(context: Context) -> NSView {
        guard #available(macOS 26.0, *) else {
            return Self.makeFallbackView(identifier: identifier)
        }
        let view = NSGlassEffectView()
        view.cornerRadius = cornerRadius
        view.style = isClear ? .clear : .regular
        view.identifier = identifier
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *), let glassView = nsView as? NSGlassEffectView {
            glassView.cornerRadius = cornerRadius
            glassView.style = isClear ? .clear : .regular
        }
    }

    private static func makeFallbackView(identifier: NSUserInterfaceItemIdentifier) -> NSView {
        let view = NSVisualEffectView()
        view.material = .titlebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        // Keeps the caller's identifier: this view fills glass's role, and the
        // class name in a hierarchy dump already says which material it is.
        view.identifier = identifier
        return view
    }
}

// MARK: - Window

extension NSWindow {
    /// Translucent chrome blurs what is behind the window, which only produces
    /// anything once the window stops painting an opaque background of its own.
    func applyChromeBackground(_ appearance: ChromeAppearance) {
        if appearance.isTranslucent {
            isOpaque = false
            backgroundColor = .clear
        } else {
            isOpaque = true
            backgroundColor = NSColor(named: "TitleBarBg")
        }
        invalidateShadow()
    }
}
