//
//  TabDragTypes.swift
//  kouke browser
//
//  Shared types for dragging tabs within and between browser windows.
//

import AppKit

// MARK: - Tab Pasteboard Type

extension NSPasteboard.PasteboardType {
    static let tabData = NSPasteboard.PasteboardType("com.koukebrowser.tab")
}

// MARK: - Tab Transfer Payload

/// Identifies a dragged tab and the window it came from, so a drop can tell
/// a reorder (same window) from a transfer (different window).
struct TabTransferData: Codable {
    let tabId: String
    let title: String
    let url: String
    let sourceWindowId: Int
}

// MARK: - Drop Position

/// Which side of a tab a dragged tab would be inserted on.
enum TabDropEdge {
    case leading
    case trailing
}
