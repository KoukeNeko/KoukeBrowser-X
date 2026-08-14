//
//  TabItemView.swift
//  kouke browser
//
//  A single tab in the normal-style tab bar.
//
//  The visuals are SwiftUI; all mouse input is handled by one AppKit overlay
//  (`TabDragSourceView`). Input lives in AppKit because detaching a tab into a
//  new window requires an NSDraggingSession — only that reports where a drag
//  ended when it lands outside every window.
//

import SwiftUI
import AppKit

struct TabItemView: View {
    let tab: Tab
    let isActive: Bool
    let appearance: ChromeAppearance
    let canClose: Bool
    let isBeingDragged: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onReorder: (UUID, TabDropEdge) -> Void
    let onReceiveTab: (TabTransferData, TabDropEdge) -> Void
    let onDetach: (UUID, NSPoint) -> Void
    let onDragStateChange: (UUID?) -> Void

    @State private var isHovering = false
    @State private var dropEdge: TabDropEdge?

    private static let horizontalPadding: CGFloat = 12
    private static let iconSize: CGFloat = 16
    private static let dropIndicatorWidth: CGFloat = 3

    var body: some View {
        ZStack {
            ChromeTabBackground(appearance: appearance, isActive: isActive)

            HStack(spacing: 8) {
                leadingIcon

                Text(tab.title.isEmpty ? "New Tab" : tab.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(isActive ? Color("Text") : Color("TextMuted"))

                Spacer(minLength: 4)

                if canClose {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color("TextMuted").opacity(isHovering ? 1.0 : 0.4))
                        .frame(width: Self.iconSize, height: Self.iconSize)
                }
            }
            .padding(.horizontal, Self.horizontalPadding)

            dropIndicator
        }
        .opacity(isBeingDragged ? 0.5 : 1.0)
        .overlay(alignment: .trailing) {
            // Glass tabs are separated by their own rounded edges; a drawn rule
            // between them would cut across the material.
            if appearance != .liquidGlass {
                Rectangle()
                    .fill(Color("Border"))
                    .frame(width: 1)
            }
        }
        .overlay { inputLayer }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if tab.isLoading {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
                .frame(width: Self.iconSize, height: Self.iconSize)
        } else if let faviconURL = tab.faviconURL {
            AsyncImage(url: faviconURL) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                placeholderIcon
            }
            .frame(width: Self.iconSize, height: Self.iconSize)
        } else {
            placeholderIcon
        }
    }

    private var placeholderIcon: some View {
        Image(systemName: "globe")
            .font(.system(size: 11))
            .foregroundColor(Color("TextMuted"))
            .frame(width: Self.iconSize, height: Self.iconSize)
    }

    @ViewBuilder
    private var dropIndicator: some View {
        if let dropEdge = dropEdge {
            HStack(spacing: 0) {
                if dropEdge == .trailing { Spacer() }
                RoundedRectangle(cornerRadius: Self.dropIndicatorWidth / 2)
                    .fill(Color.accentColor)
                    .frame(width: Self.dropIndicatorWidth)
                    .padding(.vertical, 6)
                if dropEdge == .leading { Spacer() }
            }
        }
    }

    private var inputLayer: some View {
        TabInputLayer(
            tabId: tab.id,
            title: tab.title,
            url: tab.url,
            canClose: canClose,
            onSelect: onSelect,
            onClose: onClose,
            onHoverChange: { isHovering = $0 },
            onDropEdgeChange: { dropEdge = $0 },
            onReorder: onReorder,
            onReceiveTab: onReceiveTab,
            onDetach: onDetach,
            onDragStateChange: onDragStateChange
        )
    }
}

// MARK: - AppKit Input Layer

struct TabInputLayer: NSViewRepresentable {
    let tabId: UUID
    let title: String
    let url: String
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onHoverChange: (Bool) -> Void
    let onDropEdgeChange: (TabDropEdge?) -> Void
    let onReorder: (UUID, TabDropEdge) -> Void
    let onReceiveTab: (TabTransferData, TabDropEdge) -> Void
    let onDetach: (UUID, NSPoint) -> Void
    let onDragStateChange: (UUID?) -> Void

    func makeNSView(context: Context) -> TabDragSourceView {
        let view = TabDragSourceView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: TabDragSourceView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: TabDragSourceView) {
        view.tabId = tabId
        view.tabTitle = title
        view.tabURL = url
        view.canClose = canClose
        view.onSelect = onSelect
        view.onClose = onClose
        view.onHoverChange = onHoverChange
        view.onDropEdgeChange = onDropEdgeChange
        view.onReorder = onReorder
        view.onReceiveTab = onReceiveTab
        view.onDetach = onDetach
        view.onDragStateChange = onDragStateChange
    }
}

final class TabDragSourceView: NSView, NSDraggingSource {
    /// Width of the trailing strip that acts as the close button. The close
    /// glyph is drawn by SwiftUI underneath, so its hit area is expressed here.
    private static let closeHitWidth: CGFloat = 34
    private static let dragThreshold: CGFloat = 5

    var tabId: UUID?
    var tabTitle: String = ""
    var tabURL: String = ""
    var canClose: Bool = true

    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    var onDropEdgeChange: ((TabDropEdge?) -> Void)?
    var onReorder: ((UUID, TabDropEdge) -> Void)?
    var onReceiveTab: ((TabTransferData, TabDropEdge) -> Void)?
    var onDetach: ((UUID, NSPoint) -> Void)?
    var onDragStateChange: ((UUID?) -> Void)?

    private var mouseDownLocation: NSPoint = .zero
    private var isDraggingTab = false
    private var hoverTrackingArea: NSTrackingArea?

    /// Must stay false so a press on a tab never becomes a window drag.
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.tabData])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.tabData])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = hoverTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    // MARK: - Mouse

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        isDraggingTab = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDraggingTab else { return }

        let location = convert(event.locationInWindow, from: nil)
        let distance = hypot(location.x - mouseDownLocation.x, location.y - mouseDownLocation.y)
        guard distance > Self.dragThreshold else { return }

        isDraggingTab = true
        beginTabDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { isDraggingTab = false }
        guard !isDraggingTab else { return }

        if canClose && isInCloseRegion(convert(event.locationInWindow, from: nil)) {
            onClose?()
        } else {
            onSelect?()
        }
    }

    private func isInCloseRegion(_ point: NSPoint) -> Bool {
        point.x > bounds.maxX - Self.closeHitWidth
    }

    // MARK: - Drag Source

    private func beginTabDrag(with event: NSEvent) {
        guard let tabId = tabId, let window = window else { return }

        onDragStateChange?(tabId)

        let transferData = TabTransferData(
            tabId: tabId.uuidString,
            title: tabTitle,
            url: tabURL,
            sourceWindowId: window.windowNumber
        )

        let pasteboardItem = NSPasteboardItem()
        if let encoded = try? JSONEncoder().encode(transferData) {
            pasteboardItem.setData(encoded, forType: .tabData)
        }
        pasteboardItem.setString(tabURL, forType: .string)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let dragImage = makeDragImage()
        draggingItem.setDraggingFrame(NSRect(origin: .zero, size: dragImage.size), contents: dragImage)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    /// Snapshot the SwiftUI tab drawn beneath this overlay, so the drag image
    /// always matches the real tab without redrawing it by hand.
    private func makeDragImage() -> NSImage {
        let sourceView = superview ?? self
        let bounds = sourceView.bounds
        guard bounds.width > 0, bounds.height > 0,
              let bitmap = sourceView.bitmapImageRepForCachingDisplay(in: bounds) else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        sourceView.cacheDisplay(in: bounds, to: bitmap)

        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        return image
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        isDraggingTab = false
        onDragStateChange?(nil)

        // A completed move was already handled by the destination tab bar.
        guard operation != .move, let tabId = tabId else { return }

        let droppedOnAWindow = NSApp.windows.contains { window in
            window.isVisible && NSPointInRect(screenPoint, window.frame)
        }
        if !droppedOnAWindow {
            onDetach?(tabId, screenPoint)
        }
    }

    // MARK: - Drop Target

    private func dropEdge(for sender: NSDraggingInfo) -> TabDropEdge {
        let location = convert(sender.draggingLocation, from: nil)
        return location.x > bounds.midX ? .trailing : .leading
    }

    /// A tab may not be dropped onto itself.
    private func isDraggingSelf(_ sender: NSDraggingInfo) -> Bool {
        if let source = sender.draggingSource as? TabDragSourceView {
            return source.tabId == tabId
        }
        if let source = sender.draggingSource as? CompactDraggableTabContainerView {
            return source.tabId == tabId
        }
        return false
    }

    private func canAccept(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.availableType(from: [.tabData]) != nil && !isDraggingSelf(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAccept(sender) else { return [] }
        onDropEdgeChange?(dropEdge(for: sender))
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAccept(sender) else {
            onDropEdgeChange?(nil)
            return []
        }
        onDropEdgeChange?(dropEdge(for: sender))
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDropEdgeChange?(nil)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onDropEdgeChange?(nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDropEdgeChange?(nil)

        guard let data = sender.draggingPasteboard.data(forType: .tabData),
              let transferData = try? JSONDecoder().decode(TabTransferData.self, from: data),
              let draggedTabId = UUID(uuidString: transferData.tabId) else {
            return false
        }
        guard draggedTabId != tabId else { return true }

        let edge = dropEdge(for: sender)
        if transferData.sourceWindowId == window?.windowNumber {
            onReorder?(draggedTabId, edge)
        } else {
            onReceiveTab?(transferData, edge)
        }
        return true
    }
}
