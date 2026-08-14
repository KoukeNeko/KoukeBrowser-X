//
//  WindowDragRegion.swift
//  kouke browser
//
//  Explicit "drag here to move the window" areas.
//
//  Browser windows set `isMovable = false` because the system's own window
//  dragging cannot be kept away from the custom tab views: every SwiftUI
//  hosting view wrapping an NSViewRepresentable reports
//  `mouseDownCanMoveWindow = true`, which overrides the tab view's own
//  `false` and turns tab drags into window drags. Window moving is therefore
//  reimplemented here and applied only to areas with nothing interactive.
//

import SwiftUI
import AppKit

extension View {
    /// Lets the user move the window by dragging this view.
    /// Apply to empty spacers only — never over tabs, buttons, or text fields,
    /// since this region consumes all mouse events within its bounds.
    func movesWindowOnDrag() -> some View {
        overlay(WindowDragRegion())
    }
}

struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragRegionView {
        WindowDragRegionView()
    }

    func updateNSView(_ nsView: WindowDragRegionView, context: Context) {}
}

final class WindowDragRegionView: NSView {
    /// Anchors captured on mouse down. Dragging is applied as an absolute
    /// offset from these, so the window cannot accumulate drift the way
    /// per-event deltas do when events are coalesced or dropped.
    private var mouseDownScreenLocation: NSPoint?
    private var windowOriginAtMouseDown: NSPoint?

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        mouseDownScreenLocation = NSEvent.mouseLocation
        windowOriginAtMouseDown = window.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window,
              let startLocation = mouseDownScreenLocation,
              let startOrigin = windowOriginAtMouseDown else { return }

        let currentLocation = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(
            x: startOrigin.x + (currentLocation.x - startLocation.x),
            y: startOrigin.y + (currentLocation.y - startLocation.y)
        ))
    }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2, let window = window {
            performDoubleClickAction(on: window)
        }
        mouseDownScreenLocation = nil
        windowOriginAtMouseDown = nil
    }

    /// Honor the system's "double-click a window's title bar to" preference,
    /// which the real title bar would normally handle for us.
    private func performDoubleClickAction(on window: NSWindow) {
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize":
            window.miniaturize(nil)
        case "None":
            break
        default:
            window.zoom(nil)
        }
    }
}
