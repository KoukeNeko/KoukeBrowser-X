//
//  TrafficLightsView.swift
//  kouke browser
//
//  Window close/minimize/zoom controls drawn as part of the tab bar.
//
//  The real AppKit buttons cannot be placed where this design needs them.
//  AppKit rewrites their frames on every title bar layout pass — a plain window
//  title change is enough to trigger one, and no frame-change notification is
//  posted — and it re-parents them back into the title bar if they are hosted
//  elsewhere. Both were measured. Drawing the controls ourselves is what makes
//  their position stable and their padding adjustable; the system buttons are
//  hidden in WindowChromeConfigurator.
//

import SwiftUI
import AppKit

struct TrafficLightsView: View {
    /// Space before the first control.
    static let leadingInset: CGFloat = 13
    /// Space after the last control, before the first tab. Tied to the leading
    /// inset so the cluster stays evenly padded on both sides.
    static let trailingInset: CGFloat = leadingInset

    private static let diameter: CGFloat = 12
    private static let spacing: CGFloat = 8

    /// Width of the controls themselves, excluding the trailing gap.
    static var clusterWidth: CGFloat {
        leadingInset + 3 * diameter + 2 * spacing
    }

    /// Width the tab bar reserves for the controls and the gap after them.
    static var reservedWidth: CGFloat {
        clusterWidth + trailingInset
    }

    @Environment(\.controlActiveState) private var controlActiveState
    @State private var isHoveringCluster = false
    @State private var hostWindow: NSWindow?

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(WindowControl.allCases, id: \.self) { control in
                controlButton(control)
            }
        }
        .padding(.leading, Self.leadingInset)
        .frame(width: Self.clusterWidth, alignment: .leading)
        .onHover { isHoveringCluster = $0 }
        .background(WindowCapture { window in
            if hostWindow !== window { hostWindow = window }
        })
    }

    private func controlButton(_ control: WindowControl) -> some View {
        Circle()
            .fill(isWindowActive ? control.tint : Self.inactiveTint)
            .frame(width: Self.diameter, height: Self.diameter)
            .overlay {
                if isHoveringCluster {
                    Image(systemName: control.symbolName)
                        .font(.system(size: control.symbolSize, weight: .bold))
                        .foregroundColor(.black.opacity(0.55))
                }
            }
            .contentShape(Circle())
            .onTapGesture { perform(control) }
            .accessibilityLabel(control.accessibilityLabel)
            .help(control.accessibilityLabel)
    }

    private var isWindowActive: Bool {
        controlActiveState != .inactive
    }

    /// Matches the uniform grey macOS uses on a window that is not in front.
    private static let inactiveTint = Color(white: 0.42)

    private func perform(_ control: WindowControl) {
        guard let window = hostWindow else { return }
        switch control {
        case .close:
            window.performClose(nil)
        case .minimize:
            window.miniaturize(nil)
        case .zoom:
            // Matches the system button: full screen normally, zoom with Option.
            if NSEvent.modifierFlags.contains(.option) {
                window.zoom(nil)
            } else {
                window.toggleFullScreen(nil)
            }
        }
    }
}

// MARK: - Controls

enum WindowControl: CaseIterable {
    case close
    case minimize
    case zoom

    var tint: Color {
        switch self {
        case .close: return Color(red: 1.0, green: 0.37, blue: 0.34)
        case .minimize: return Color(red: 1.0, green: 0.74, blue: 0.18)
        case .zoom: return Color(red: 0.16, green: 0.78, blue: 0.25)
        }
    }

    var symbolName: String {
        switch self {
        case .close: return "xmark"
        case .minimize: return "minus"
        case .zoom: return "arrow.up.left.and.arrow.down.right"
        }
    }

    var symbolSize: CGFloat {
        switch self {
        case .close, .minimize: return 7
        case .zoom: return 5.5
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .close: return "Close"
        case .minimize: return "Minimize"
        case .zoom: return "Full Screen"
        }
    }
}

// MARK: - Window Access

/// Reports the window hosting this view, so the controls can act on it rather
/// than on whichever window happens to be key.
private struct WindowCapture: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    final class Coordinator {
        weak var reportedWindow: NSWindow?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        report(from: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        report(from: nsView, coordinator: context.coordinator)
    }

    /// Reports only when the window actually changes. Feeding the same value
    /// back into SwiftUI state on every update would retrigger this view
    /// update and spin forever.
    private func report(from view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            guard let window = view.window, coordinator.reportedWindow !== window else { return }
            coordinator.reportedWindow = window
            onResolve(window)
        }
    }
}
