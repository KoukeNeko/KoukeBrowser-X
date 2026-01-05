//
//  DraggableTabView.swift
//  kouke browser
//
//  Native AppKit view for draggable tabs that can be detached to create new windows.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Tab Pasteboard Type

extension NSPasteboard.PasteboardType {
    static let tabData = NSPasteboard.PasteboardType("com.koukebrowser.tab")
}

// MARK: - Tab Transfer Data

struct TabTransferData: Codable {
    let tabId: String
    let title: String
    let url: String
    let sourceWindowId: Int
}

// MARK: - Draggable Tab NSView

class DraggableTabNSView: NSView, NSDraggingSource {
    var tabId: UUID?
    var tabTitle: String = ""
    var tabURL: String = ""
    var onSelect: (() -> Void)?
    var onReorder: ((UUID, Int) -> Void)?
    var onDetach: ((UUID, NSPoint) -> Void)?
    var onDragStarted: ((UUID) -> Void)?
    var onDragEnded: (() -> Void)?

    private var isDragging = false
    private var dragStartLocation: NSPoint = .zero
    private let dragThreshold: CGFloat = 5.0
    private var mouseDownTime: Date?

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        registerForDraggedTypes([.tabData])
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .withinApplication:
            return [.move, .copy]
        case .outsideApplication:
            return .copy
        @unknown default:
            return .move
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
        onDragEnded?()

        guard let tabId = tabId else { return }

        // Check if dropped outside any browser window
        let windowUnderPoint = NSApp.windows.first { window in
            guard window.isVisible else { return false }
            return NSPointInRect(screenPoint, window.frame)
        }

        // If dropped outside all windows, create new window
        if windowUnderPoint == nil {
            onDetach?(tabId, screenPoint)
        }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = convert(event.locationInWindow, from: nil)
        mouseDownTime = Date()
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging else { return }

        let currentLocation = convert(event.locationInWindow, from: nil)
        let distance = hypot(
            currentLocation.x - dragStartLocation.x,
            currentLocation.y - dragStartLocation.y
        )

        // Only start drag after threshold
        guard distance > dragThreshold else { return }

        isDragging = true
        startDragSession(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        // Only trigger select if we weren't dragging and it was a quick click
        if !isDragging {
            onSelect?()
        }
        isDragging = false
        mouseDownTime = nil
    }

    private func startDragSession(with event: NSEvent) {
        guard let tabId = tabId, let window = self.window else { return }

        onDragStarted?(tabId)

        // Create transfer data
        let transferData = TabTransferData(
            tabId: tabId.uuidString,
            title: tabTitle,
            url: tabURL,
            sourceWindowId: window.windowNumber
        )

        // Create pasteboard item
        let pasteboardItem = NSPasteboardItem()
        if let data = try? JSONEncoder().encode(transferData) {
            pasteboardItem.setData(data, forType: .tabData)
        }
        pasteboardItem.setString(tabURL, forType: .string)

        // Create dragging item with tab snapshot
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)

        // Create visual representation of the tab
        let dragImage = createDragImage()
        draggingItem.setDraggingFrame(NSRect(origin: .zero, size: dragImage.size), contents: dragImage)

        // Start the drag session
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func createDragImage() -> NSImage {
        let size = NSSize(width: bounds.width, height: bounds.height)
        let image = NSImage(size: size)

        image.lockFocus()

        // Draw semi-transparent background
        (NSColor(named: "TabActive") ?? .windowBackgroundColor).withAlphaComponent(0.9).setFill()
        let path = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 6, yRadius: 6)
        path.fill()

        // Draw border
        (NSColor(named: "Border") ?? .separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        // Draw title
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor(named: "Text") ?? .labelColor,
            .paragraphStyle: paragraphStyle
        ]

        let titleRect = NSRect(x: 12, y: (size.height - 16) / 2, width: size.width - 40, height: 16)
        tabTitle.draw(in: titleRect, withAttributes: attributes)

        image.unlockFocus()

        return image
    }

    // MARK: - Drag Destination (for reordering)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource as? DraggableTabNSView != nil else {
            return []
        }
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource as? DraggableTabNSView != nil else {
            return []
        }
        return .move
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let data = sender.draggingPasteboard.data(forType: .tabData),
              let transferData = try? JSONDecoder().decode(TabTransferData.self, from: data),
              let draggedTabId = UUID(uuidString: transferData.tabId),
              let myTabId = tabId else {
            return false
        }

        // Don't do anything if dropping on itself
        guard draggedTabId != myTabId else { return true }

        // Calculate drop position based on mouse location
        let locationInView = convert(sender.draggingLocation, from: nil)
        let dropAtEnd = locationInView.x > bounds.width / 2

        onReorder?(draggedTabId, dropAtEnd ? 1 : 0)

        return true
    }
}

// MARK: - SwiftUI Wrapper

struct DraggableTabView: NSViewRepresentable {
    let tab: Tab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let canClose: Bool
    let onReorder: (UUID, UUID) -> Void
    let onDetach: (UUID, NSPoint) -> Void
    let onDragStarted: (UUID) -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> DraggableTabContainerView {
        let container = DraggableTabContainerView()
        container.configure(
            tab: tab,
            isActive: isActive,
            onSelect: onSelect,
            onClose: onClose,
            canClose: canClose,
            onReorder: { draggedId, _ in
                onReorder(draggedId, tab.id)
            },
            onDetach: onDetach,
            onDragStarted: onDragStarted,
            onDragEnded: onDragEnded
        )
        return container
    }

    func updateNSView(_ nsView: DraggableTabContainerView, context: Context) {
        nsView.updateTab(tab, isActive: isActive, canClose: canClose)
    }
}

// MARK: - Container View with Full Tab UI

class DraggableTabContainerView: NSView, NSDraggingSource {
    var tabId: UUID?
    var tabTitle: String = ""
    var tabURL: String = ""

    private var currentTab: Tab?
    private var isActive: Bool = false
    private var canClose: Bool = true
    private var selectAction: (() -> Void)?
    private var closeAction: (() -> Void)?
    private var reorderAction: ((UUID, Int) -> Void)?
    private var detachAction: ((UUID, NSPoint) -> Void)?
    private var dragStartedAction: ((UUID) -> Void)?
    private var dragEndedAction: (() -> Void)?

    private var isDragging = false
    private var dragStartLocation: NSPoint = .zero
    private let dragThreshold: CGFloat = 5.0

    private var isHovering = false

    // UI Elements
    private var faviconView: NSImageView?
    private var titleLabel: NSTextField?
    private var closeButton: NSButton?
    private var loadingIndicator: NSProgressIndicator?

    override var mouseDownCanMoveWindow: Bool { false }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        registerForDraggedTypes([.tabData])

        // Setup tracking area for hover
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)

        setupSubviews()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Check if the click is on the close button
        if let closeButton = closeButton {
            let pointInClose = closeButton.convert(point, from: self)
            if closeButton.bounds.contains(pointInClose) {
                return closeButton
            }
        }
        // Otherwise, handle it ourselves to prevent window dragging
        if bounds.contains(point) {
            return self
        }
        return nil
    }

    private func setupSubviews() {
        // Loading indicator
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        addSubview(spinner)
        loadingIndicator = spinner

        // Favicon
        let favicon = NSImageView()
        favicon.imageScaling = .scaleProportionallyUpOrDown
        favicon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(favicon)
        faviconView = favicon

        // Title
        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 13)
        title.textColor = NSColor(named: "TextMuted")
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.maximumNumberOfLines = 1
        title.cell?.truncatesLastVisibleLine = true
        addSubview(title)
        titleLabel = title

        // Close button
        let close = NSButton(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        close.bezelStyle = .regularSquare
        close.isBordered = false
        close.title = ""
        let xImage = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))
        close.image = xImage
        close.imagePosition = .imageOnly
        close.contentTintColor = NSColor(named: "TextMuted")?.withAlphaComponent(0.4)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.target = self
        close.action = #selector(closeButtonClicked)
        addSubview(close)
        closeButton = close

        // Separator line (right edge)
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(named: "Border")?.cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            // Spinner
            spinner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),

            // Favicon
            favicon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            favicon.centerYAnchor.constraint(equalTo: centerYAnchor),
            favicon.widthAnchor.constraint(equalToConstant: 16),
            favicon.heightAnchor.constraint(equalToConstant: 16),

            // Title
            title.leadingAnchor.constraint(equalTo: favicon.trailingAnchor, constant: 8),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -4),

            // Close button
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            close.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 16),
            close.heightAnchor.constraint(equalToConstant: 16),

            // Separator
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1)
        ])
    }

    @objc private func closeButtonClicked() {
        closeAction?()
    }

    func configure(
        tab: Tab,
        isActive: Bool,
        onSelect: @escaping () -> Void,
        onClose: @escaping () -> Void,
        canClose: Bool,
        onReorder: @escaping (UUID, Int) -> Void,
        onDetach: @escaping (UUID, NSPoint) -> Void,
        onDragStarted: @escaping (UUID) -> Void,
        onDragEnded: @escaping () -> Void
    ) {
        self.tabId = tab.id
        self.tabTitle = tab.title
        self.tabURL = tab.url
        self.currentTab = tab
        self.isActive = isActive
        self.canClose = canClose
        self.selectAction = onSelect
        self.closeAction = onClose
        self.reorderAction = onReorder
        self.detachAction = onDetach
        self.dragStartedAction = onDragStarted
        self.dragEndedAction = onDragEnded

        updateUI()
    }

    func updateTab(_ tab: Tab, isActive: Bool, canClose: Bool) {
        self.tabId = tab.id
        self.tabTitle = tab.title
        self.tabURL = tab.url
        self.currentTab = tab
        self.isActive = isActive
        self.canClose = canClose

        updateUI()
    }

    private func updateUI() {
        guard let tab = currentTab else { return }

        // Background color
        layer?.backgroundColor = isActive
            ? NSColor(named: "TabActive")?.cgColor
            : NSColor(named: "TabInactive")?.cgColor

        // Title
        titleLabel?.stringValue = tab.title
        titleLabel?.textColor = isActive ? NSColor(named: "Text") : NSColor(named: "TextMuted")

        // Loading state
        if tab.isLoading {
            loadingIndicator?.isHidden = false
            loadingIndicator?.startAnimation(nil)
            faviconView?.isHidden = true
        } else {
            loadingIndicator?.isHidden = true
            loadingIndicator?.stopAnimation(nil)
            faviconView?.isHidden = false

            // Load favicon
            if let faviconURL = tab.faviconURL {
                loadFavicon(from: faviconURL)
            } else {
                faviconView?.image = nil
            }
        }

        // Close button
        closeButton?.isHidden = !canClose
        updateCloseButtonAppearance()
    }

    private func loadFavicon(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.faviconView?.image = image
            }
        }.resume()
    }

    private func updateCloseButtonAppearance() {
        closeButton?.contentTintColor = NSColor(named: "TextMuted")?.withAlphaComponent(isHovering ? 1.0 : 0.4)
    }

    // MARK: - Mouse Events

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateCloseButtonAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateCloseButtonAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = convert(event.locationInWindow, from: nil)
        isDragging = false

        // Temporarily disable window moving while handling tab interaction
        window?.isMovableByWindowBackground = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging else { return }

        let currentLocation = convert(event.locationInWindow, from: nil)
        let distance = hypot(
            currentLocation.x - dragStartLocation.x,
            currentLocation.y - dragStartLocation.y
        )

        guard distance > dragThreshold else { return }

        isDragging = true
        startDragSession(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        // Re-enable window moving
        window?.isMovableByWindowBackground = true

        if !isDragging {
            selectAction?()
        }
        isDragging = false
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .withinApplication:
            return [.move, .copy]
        case .outsideApplication:
            return .copy
        @unknown default:
            return .move
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false

        // Re-enable window moving
        window?.isMovableByWindowBackground = true

        dragEndedAction?()

        guard let tabId = tabId else { return }

        // Check if dropped outside any browser window
        let windowUnderPoint = NSApp.windows.first { window in
            guard window.isVisible else { return false }
            return NSPointInRect(screenPoint, window.frame)
        }

        if windowUnderPoint == nil {
            detachAction?(tabId, screenPoint)
        }
    }

    private func startDragSession(with event: NSEvent) {
        guard let tabId = tabId, let window = self.window else { return }

        dragStartedAction?(tabId)

        let transferData = TabTransferData(
            tabId: tabId.uuidString,
            title: tabTitle,
            url: tabURL,
            sourceWindowId: window.windowNumber
        )

        let pasteboardItem = NSPasteboardItem()
        if let data = try? JSONEncoder().encode(transferData) {
            pasteboardItem.setData(data, forType: .tabData)
        }
        pasteboardItem.setString(tabURL, forType: .string)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let dragImage = createDragImage()
        draggingItem.setDraggingFrame(NSRect(origin: .zero, size: dragImage.size), contents: dragImage)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func createDragImage() -> NSImage {
        let size = NSSize(width: bounds.width, height: bounds.height)
        let image = NSImage(size: size)

        image.lockFocus()

        (NSColor(named: "TabActive") ?? .windowBackgroundColor).withAlphaComponent(0.9).setFill()
        let path = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 6, yRadius: 6)
        path.fill()

        (NSColor(named: "Border") ?? .separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor(named: "Text") ?? .labelColor,
            .paragraphStyle: paragraphStyle
        ]

        let titleRect = NSRect(x: 12, y: (size.height - 16) / 2, width: size.width - 40, height: 16)
        tabTitle.draw(in: titleRect, withAttributes: attributes)

        image.unlockFocus()

        return image
    }

    // MARK: - Drag Destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource as? DraggableTabContainerView != nil else { return [] }
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource as? DraggableTabContainerView != nil else { return [] }
        return .move
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let data = sender.draggingPasteboard.data(forType: .tabData),
              let transferData = try? JSONDecoder().decode(TabTransferData.self, from: data),
              let draggedTabId = UUID(uuidString: transferData.tabId),
              let myTabId = tabId else {
            return false
        }

        guard draggedTabId != myTabId else { return true }

        let locationInView = convert(sender.draggingLocation, from: nil)
        let dropAtEnd = locationInView.x > bounds.width / 2

        reorderAction?(draggedTabId, dropAtEnd ? 1 : 0)

        return true
    }
}
