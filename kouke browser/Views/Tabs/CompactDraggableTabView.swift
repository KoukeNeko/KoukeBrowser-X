//
//  CompactDraggableTabView.swift
//  kouke browser
//
//  NSViewRepresentable wrapper for the draggable tab in compact mode.
//

import SwiftUI
import AppKit

struct CompactDraggableTabView: NSViewRepresentable {
    let tab: Tab
    let isActive: Bool
    let showActiveStyle: Bool
    let canDrag: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let canClose: Bool
    let onReorder: (UUID, UUID, Bool) -> Void
    let onReceiveTab: (TabTransferData, UUID, Bool) -> Void
    let onDetach: (UUID, NSPoint) -> Void
    let onDragStarted: (UUID) -> Void
    let onDragEnded: () -> Void
    let inputURL: String
    let onInputURLChange: (String) -> Void
    let onNavigate: () -> Void

    let isDarkTheme: Bool

    func makeNSView(context: Context) -> CompactDraggableTabContainerView {
        let container = CompactDraggableTabContainerView()
        // Initialize with correct theme
        container.updateTab(tab, isActive: isActive, showActiveStyle: showActiveStyle, canClose: canClose, canDrag: canDrag, inputURL: inputURL, isDarkTheme: isDarkTheme)
        
        container.configure(
            tab: tab,
            isActive: isActive,
            showActiveStyle: showActiveStyle,
            canDrag: canDrag,
            onSelect: onSelect,
            onClose: onClose,
            canClose: canClose,
            onReorder: { draggedId, insertAfter in
                onReorder(draggedId, tab.id, insertAfter == 1)
            },
            onReceiveTab: { transferData, insertAfter in
                onReceiveTab(transferData, tab.id, insertAfter == 1)
            },
            onDetach: onDetach,
            onDragStarted: onDragStarted,
            onDragEnded: onDragEnded,
            inputURL: inputURL,
            onInputURLChange: onInputURLChange,
            onNavigate: onNavigate
        )
        return container
    }

    func updateNSView(_ nsView: CompactDraggableTabContainerView, context: Context) {
        nsView.updateTab(tab, isActive: isActive, showActiveStyle: showActiveStyle, canClose: canClose, canDrag: canDrag, inputURL: inputURL, isDarkTheme: isDarkTheme)
    }
}

// MARK: - Compact Draggable Tab Container View (AppKit)

class CompactDraggableTabContainerView: NSView, NSDraggingSource, NSTextFieldDelegate {
    var tabId: UUID?
    var tabTitle: String = ""
    var tabURL: String = ""
    var inputURL: String = "" // For active tab editing

    private var currentTab: Tab?
    private var isActive: Bool = false
    private var showActiveStyle: Bool = true
    private var canClose: Bool = true
    private var canDrag: Bool = false
    private var selectAction: (() -> Void)?
    private var closeAction: (() -> Void)?
    private var reorderAction: ((UUID, Int) -> Void)?
    private var receiveTabAction: ((TabTransferData, Int) -> Void)?
    private var detachAction: ((UUID, NSPoint) -> Void)?
    private var dragStartedAction: ((UUID) -> Void)?
    private var dragEndedAction: (() -> Void)?
    private var inputURLChangeAction: ((String) -> Void)?
    private var navigateAction: (() -> Void)?

    private var isEditing = false
    private var isDragging = false
    private var isWindowDragging = false
    private var dragStartLocation: NSPoint = .zero
    private let dragThreshold: CGFloat = 5.0

    private var isHovering = false

    // Drop indicators
    private var leftDropIndicator: NSView?
    private var rightDropIndicator: NSView?

    // UI Elements
    private var faviconView: NSImageView?
    private var titleLabel: NSTextField?
    private var addressField: NSTextField?
    private var closeButton: NSButton?
    private var loadingIndicator: NSProgressIndicator?
    private var backgroundView: NSView?
    private var separatorView: NSView?

    // Constraints for dynamic width
    private var titleWidthConstraint: NSLayoutConstraint?
    private var addressWidthConstraint: NSLayoutConstraint?

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

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: 32)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Re-apply colors when appearance (light/dark mode) changes
        updateUI()
    }

    private func setupView() {
        wantsLayer = true
        layer?.masksToBounds = false
        registerForDraggedTypes([.tabData])

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
        guard bounds.contains(point) else {
            return super.hitTest(point)
        }

        // Allow address field to receive mouse events for text selection
        if let addressField = addressField, !addressField.isHidden {
            let pointInAddress = convert(point, to: addressField)
            if addressField.bounds.contains(pointInAddress) {
                return addressField
            }
        }

        if let closeButton = closeButton, !closeButton.isHidden {
            let pointInClose = convert(point, to: closeButton)
            if closeButton.bounds.contains(pointInClose) {
                return closeButton
            }
        }

        return self
    }

    private func setupSubviews() {
        // Background view
        let bg = NSView()
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 0 // Sharp corners
        bg.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bg)
        backgroundView = bg

        // Separator line (right edge)
        let separator = NSView()
        separator.wantsLayer = true
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        separatorView = separator

        // Drop indicators
        let leftIndicator = NSView()
        leftIndicator.wantsLayer = true
        leftIndicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        leftIndicator.layer?.cornerRadius = 1.5
        leftIndicator.translatesAutoresizingMaskIntoConstraints = false
        leftIndicator.isHidden = true
        addSubview(leftIndicator)
        leftDropIndicator = leftIndicator

        let rightIndicator = NSView()
        rightIndicator.wantsLayer = true
        rightIndicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        rightIndicator.layer?.cornerRadius = 1.5
        rightIndicator.translatesAutoresizingMaskIntoConstraints = false
        rightIndicator.isHidden = true
        addSubview(rightIndicator)
        rightDropIndicator = rightIndicator

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
        title.font = .systemFont(ofSize: 11)
        title.textColor = NSColor(named: "TextMuted")
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.maximumNumberOfLines = 1
        title.cell?.truncatesLastVisibleLine = true
        addSubview(title)
        titleLabel = title

        // Address Field (TextField)
        let address = NSTextField()
        address.font = .systemFont(ofSize: 12)
        address.textColor = NSColor(named: "Text")
        address.drawsBackground = false
        address.isBordered = false
        address.focusRingType = .none
        address.isEditable = true
        address.isSelectable = true
        address.allowsEditingTextAttributes = false
        address.cell?.isScrollable = true
        address.cell?.wraps = false
        address.cell?.usesSingleLineMode = true
        address.translatesAutoresizingMaskIntoConstraints = false
        address.delegate = self
        address.isHidden = true
        address.placeholderString = "Search or enter website"
        addSubview(address)
        addressField = address

        // Close button
        let close = NSButton(frame: NSRect(x: 0, y: 0, width: 14, height: 14))
        close.bezelStyle = .regularSquare
        close.isBordered = false
        close.title = ""
        let xImage = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .medium))
        close.image = xImage
        close.imagePosition = .imageOnly
        close.contentTintColor = NSColor(named: "TextMuted")?.withAlphaComponent(0.4)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.target = self
        close.action = #selector(closeButtonClicked)
        close.isHidden = true
        addSubview(close)
        closeButton = close

        NSLayoutConstraint.activate([
            // Background - Full fill
            bg.leadingAnchor.constraint(equalTo: leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: trailingAnchor),
            bg.topAnchor.constraint(equalTo: topAnchor),
            bg.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Separator
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            separator.widthAnchor.constraint(equalToConstant: 1),

            // Left drop indicator
            leftIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -1),
            leftIndicator.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            leftIndicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            leftIndicator.widthAnchor.constraint(equalToConstant: 3),

            // Right drop indicator
            rightIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 1),
            rightIndicator.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            rightIndicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            rightIndicator.widthAnchor.constraint(equalToConstant: 3),

            // Spinner
            spinner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 14),
            spinner.heightAnchor.constraint(equalToConstant: 14),

            // Favicon
            favicon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            favicon.centerYAnchor.constraint(equalTo: centerYAnchor),
            favicon.widthAnchor.constraint(equalToConstant: 14),
            favicon.heightAnchor.constraint(equalToConstant: 14),

            // Title
            title.leadingAnchor.constraint(equalTo: favicon.trailingAnchor, constant: 6),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -4),

            // Address Field
            address.leadingAnchor.constraint(equalTo: favicon.trailingAnchor, constant: 6),
            address.centerYAnchor.constraint(equalTo: centerYAnchor),
            address.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -4),

            // Close button
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            close.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 14),
            close.heightAnchor.constraint(equalToConstant: 14),
        ])

        // Width constraint for title - use large max value, trailing constraint will limit actual size
        titleWidthConstraint = title.widthAnchor.constraint(lessThanOrEqualToConstant: 500)
        titleWidthConstraint?.isActive = true
    }

    @objc private func closeButtonClicked() {
        closeAction?()
    }

    func configure(
        tab: Tab,
        isActive: Bool,
        showActiveStyle: Bool,
        canDrag: Bool,
        onSelect: @escaping () -> Void,
        onClose: @escaping () -> Void,
        canClose: Bool,
        onReorder: @escaping (UUID, Int) -> Void,
        onReceiveTab: @escaping (TabTransferData, Int) -> Void,
        onDetach: @escaping (UUID, NSPoint) -> Void,
        onDragStarted: @escaping (UUID) -> Void,
        onDragEnded: @escaping () -> Void,
        inputURL: String,
        onInputURLChange: @escaping (String) -> Void,
        onNavigate: @escaping () -> Void
    ) {
        self.tabId = tab.id
        self.tabTitle = tab.title
        self.tabURL = tab.url
        self.currentTab = tab
        self.isActive = isActive
        self.showActiveStyle = showActiveStyle
        self.canClose = canClose
        self.canDrag = canDrag
        self.selectAction = onSelect
        self.closeAction = onClose
        self.reorderAction = onReorder
        self.receiveTabAction = onReceiveTab
        self.detachAction = onDetach
        self.dragStartedAction = onDragStarted
        self.dragEndedAction = onDragEnded
        self.inputURL = inputURL
        self.inputURLChangeAction = onInputURLChange
        self.navigateAction = onNavigate

        updateUI()
    }

    func updateTab(_ tab: Tab, isActive: Bool, showActiveStyle: Bool, canClose: Bool, canDrag: Bool, inputURL: String? = nil, isDarkTheme: Bool = false) {
        self.tabId = tab.id
        self.tabTitle = tab.title
        self.tabURL = tab.url
        self.currentTab = tab
        self.isActive = isActive
        self.showActiveStyle = showActiveStyle
        self.canClose = canClose
        self.canDrag = canDrag
        if let input = inputURL {
            self.inputURL = input
        }
        self.isDarkTheme = isDarkTheme

        // Reset editing state when tab properties or active state changes externally
        if !isActive {
            isEditing = false
        }

        updateUI()
    }

    private var isDarkTheme: Bool = false

    private func updateUI() {
        // Force the appearance on the view itself
        self.appearance = NSAppearance(named: isDarkTheme ? .darkAqua : .aqua)
        
        // Resolve colors - now that self.appearance is set, named colors should resolve correctly
        // We still use performAsCurrentDrawingAppearance just to be safe for CALayer changes
        self.appearance?.performAsCurrentDrawingAppearance { [self] in
            // Update separator color (always, even without tab)
            separatorView?.layer?.backgroundColor = NSColor(named: "Border")?.cgColor

            // Background - only show active style if showActiveStyle is true
            if isActive && showActiveStyle {
                backgroundView?.layer?.backgroundColor = NSColor(named: "TabActive")?.cgColor
            } else if isHovering && showActiveStyle {
                backgroundView?.layer?.backgroundColor = NSColor(named: "TabInactive")?.cgColor
            } else {
                backgroundView?.layer?.backgroundColor = NSColor.clear.cgColor
            }

            // Title color
            titleLabel?.textColor = isActive ? NSColor(named: "Text") : NSColor(named: "TextMuted")

            // Close button tint
            closeButton?.contentTintColor = NSColor(named: "TextMuted")?.withAlphaComponent(isHovering ? 1.0 : 0.4)

            // Favicon tint for default icon
            if currentTab?.faviconURL == nil {
                faviconView?.contentTintColor = NSColor(named: "TextMuted")
            }
        }

        guard let tab = currentTab else { return }

        // Title text
        titleLabel?.stringValue = tab.title

        // Show/hide title based on state
        // Show title if:
        // 1. Inactive & Hovering
        // 2. Active & Not Editing
        let shouldShowTitle = (!isActive && isHovering) || (isActive && !isEditing)
        titleLabel?.isHidden = !shouldShowTitle

        // Address Field
        // Show only if Active AND Editing
        let showAddress = isActive && isEditing
        addressField?.isHidden = !showAddress

        if showAddress {
             if addressField?.currentEditor() == nil {
                 addressField?.stringValue = inputURL
                 // Attempt to focus if we just switched to editing mode
                 if window?.firstResponder != addressField {
                     window?.makeFirstResponder(addressField)
                 }
             }
        } else {
            // Ensure we lose focus if we shouldn't be editing
            if window?.firstResponder == addressField {
                window?.makeFirstResponder(nil)
            }
        }

        // Loading state
        if tab.isLoading {
            loadingIndicator?.isHidden = false
            loadingIndicator?.startAnimation(nil)
            faviconView?.isHidden = true
        } else {
            loadingIndicator?.isHidden = true
            loadingIndicator?.stopAnimation(nil)
            faviconView?.isHidden = false

            if let faviconURL = tab.faviconURL {
                loadFavicon(from: faviconURL)
            } else {
                faviconView?.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
            }
        }

        // Close button - only show when hovering and can close
        closeButton?.isHidden = !(isHovering && canClose)

        invalidateIntrinsicContentSize()
    }

    private func loadFavicon(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.faviconView?.image = image
            }
        }.resume()
    }

    // MARK: - Mouse Events

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.allowsImplicitAnimation = true
            updateUI()
            layoutSubtreeIfNeeded()
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.allowsImplicitAnimation = true
            updateUI()
            layoutSubtreeIfNeeded()
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = convert(event.locationInWindow, from: nil)
        isDragging = false
        isWindowDragging = false
        window?.isMovableByWindowBackground = false
    }

    override func mouseDragged(with event: NSEvent) {
        let currentLocation = convert(event.locationInWindow, from: nil)
        let distance = hypot(
            currentLocation.x - dragStartLocation.x,
            currentLocation.y - dragStartLocation.y
        )

        guard distance > dragThreshold else { return }

        if !canDrag {
            // Window dragging mode - move window manually
            isWindowDragging = true
            if let window = self.window {
                var frame = window.frame
                frame.origin.x += event.deltaX
                frame.origin.y -= event.deltaY
                window.setFrame(frame, display: true)
            }
        } else {
            // Tab reordering mode
            guard !isDragging else { return }
            isDragging = true
            startDragSession(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        window?.isMovableByWindowBackground = true

        // Skip edit mode if we just finished a window drag
        if isWindowDragging {
            isWindowDragging = false
            return
        }

        if !isDragging {
            if isActive {
                // If already active, toggle editing mode
                isEditing = true
                updateUI()
            } else {
                selectAction?()
            }
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
        window?.isMovableByWindowBackground = true
        dragEndedAction?()

        if operation == .move {
            return
        }

        guard let tabId = tabId else { return }

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
        let size = NSSize(width: 140, height: 28)
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
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor(named: "Text") ?? .labelColor,
            .paragraphStyle: paragraphStyle
        ]

        let titleRect = NSRect(x: 24, y: (size.height - 14) / 2, width: size.width - 36, height: 14)
        tabTitle.draw(in: titleRect, withAttributes: attributes)

        image.unlockFocus()

        return image
    }

    // MARK: - Drag Destination

    private func updateDropIndicator(for location: NSPoint) {
        let dropOnRight = location.x > bounds.width / 2

        if dropOnRight {
            leftDropIndicator?.isHidden = true
            rightDropIndicator?.isHidden = false
        } else {
            leftDropIndicator?.isHidden = false
            rightDropIndicator?.isHidden = true
        }
    }

    private func hideDropIndicators() {
        leftDropIndicator?.isHidden = true
        rightDropIndicator?.isHidden = true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: [.tabData]) != nil else {
            return []
        }

        if let source = sender.draggingSource as? CompactDraggableTabContainerView,
           source.tabId == tabId {
            return []
        }

        let locationInView = convert(sender.draggingLocation, from: nil)
        updateDropIndicator(for: locationInView)

        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: [.tabData]) != nil else {
            hideDropIndicators()
            return []
        }

        if let source = sender.draggingSource as? CompactDraggableTabContainerView,
           source.tabId == tabId {
            hideDropIndicators()
            return []
        }

        let locationInView = convert(sender.draggingLocation, from: nil)
        updateDropIndicator(for: locationInView)

        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hideDropIndicators()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        hideDropIndicators()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hideDropIndicators()

        guard let data = sender.draggingPasteboard.data(forType: .tabData),
              let transferData = try? JSONDecoder().decode(TabTransferData.self, from: data),
              let draggedTabId = UUID(uuidString: transferData.tabId),
              let myTabId = tabId else {
            return false
        }

        guard draggedTabId != myTabId else { return true }

        let locationInView = convert(sender.draggingLocation, from: nil)
        let dropAtEnd = locationInView.x > bounds.width / 2

        let currentWindowNumber = self.window?.windowNumber ?? -1
        let isSameWindow = transferData.sourceWindowId == currentWindowNumber

        if isSameWindow {
            reorderAction?(draggedTabId, dropAtEnd ? 1 : 0)
        } else {
            receiveTabAction?(transferData, dropAtEnd ? 1 : 0)
        }

        return true
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field == addressField else { return }
        inputURL = field.stringValue
        inputURLChangeAction?(inputURL)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field == addressField else { return }
        // When focus is lost or enter pressed (handled in doCommandBy but also triggers end editing)
        // We revert to title view
        isEditing = false
        updateUI()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            navigateAction?()
            // Editing will end via controlTextDidEndEditing naturally, or we can force it
            window?.makeFirstResponder(nil)
            return true
        }
        // Escape key to cancel
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            isEditing = false
            updateUI()
            return true
        }
        return false
    }
}
