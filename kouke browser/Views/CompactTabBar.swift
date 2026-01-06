//
//  CompactTabBar.swift
//  kouke browser
//
//  Compact tab bar similar to Safari's design - single row with smaller tabs and integrated address bar.
//

import SwiftUI
import AppKit

struct CompactTabBar: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject private var settings = BrowserSettings.shared
    @State private var draggedTabId: UUID?

    // Filter tabs based on settings - show all or only active tab
    private var visibleTabs: [Tab] {
        if settings.showTabsInCompactMode {
            return viewModel.tabs
        } else {
            // Only show active tab
            return viewModel.tabs.filter { $0.id == viewModel.activeTabId }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                #if os(macOS)
                // Keep space for traffic lights - 80px seems standard for Big Sur+
                Color.clear
                    .frame(width: 80, height: 40)

                // Navigation buttons (back/forward)
                HStack(spacing: 2) {
                    Button(action: { viewModel.goBack() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(viewModel.activeTab?.canGoBack == true ? Color("Text") : Color("TextMuted").opacity(0.5))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.activeTab?.canGoBack != true)

                    Button(action: { viewModel.goForward() }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(viewModel.activeTab?.canGoForward == true ? Color("Text") : Color("TextMuted").opacity(0.5))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.activeTab?.canGoForward != true)
                }
                .frame(width: 60)
                #endif

                // Calculate available width for tabs (Total - TrafficLights - NavButtons - RightButtons)
                let availableWidth = geometry.size.width - 80 - 60 - 72
                let tabWidth = calculateTabWidth(totalAvailableWidth: availableWidth)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(visibleTabs) { tab in
                            CompactDraggableTabView(
                                tab: tab,
                                isActive: tab.id == viewModel.activeTabId,
                                showActiveStyle: settings.showTabsInCompactMode,
                                canDrag: settings.showTabsInCompactMode,
                                onSelect: { viewModel.switchToTab(tab.id) },
                                onClose: { viewModel.closeTab(tab.id) },
                                canClose: viewModel.tabs.count > 1 && settings.showTabsInCompactMode,
                                onReorder: { draggedId, targetId, after in
                                    if after {
                                        viewModel.moveTabAfter(draggedId: draggedId, destinationId: targetId)
                                    } else {
                                        viewModel.moveTabBefore(draggedId: draggedId, destinationId: targetId)
                                    }
                                },
                                onReceiveTab: { transferData, destinationId, after in
                                    receiveTabFromOtherWindow(transferData: transferData, destinationId: destinationId, insertAfter: after)
                                },
                                onDetach: { tabId, point in
                                    detachTabToNewWindow(tabId: tabId, at: point)
                                },
                                onDragStarted: { id in draggedTabId = id },
                                onDragEnded: { draggedTabId = nil },
                                inputURL: viewModel.inputURL,
                                onInputURLChange: { url in viewModel.inputURL = url },
                                onNavigate: { viewModel.navigate() }
                            )
                            .frame(width: tabWidth)
                        }
                    }
                }
                .frame(width: max(0, availableWidth)) // Ensure non-negative width

                // Right side buttons
                HStack(spacing: 4) {
                    Button(action: { viewModel.addTab() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color("TextMuted"))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)

                    // Tab list menu
                    Menu {
                        ForEach(viewModel.tabs) { tab in
                            Button(action: { viewModel.switchToTab(tab.id) }) {
                                HStack {
                                    if tab.id == viewModel.activeTabId {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(tab.title.isEmpty ? "New Tab" : tab.title)
                                        .lineLimit(1)
                                }
                            }
                        }

                        Divider()

                        Button(action: { viewModel.addTab() }) {
                            Label("New Tab", systemImage: "plus")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color("TextMuted"))
                            .frame(width: 28, height: 28)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }
                .frame(width: 72)
                .padding(.trailing, 8)
            }
        }
        .frame(height: 40)
        .background(Color("TitleBarBg"))
        .zIndex(100) // Ensure it sits on top if used in a ZStack
    }

    private func urlDisplayText(_ url: String) -> String {
        guard url != "about:blank",
              let urlObj = URL(string: url),
              let host = urlObj.host else {
            return ""
        }
        return host
    }

    private func detachTabToNewWindow(tabId: UUID, at screenPoint: NSPoint) {
        guard let result = viewModel.detachTab(tabId) else { return }
        WindowManager.shared.createNewWindow(with: result.tab, webView: result.webView, at: screenPoint)
    }

    private func receiveTabFromOtherWindow(transferData: TabTransferData, destinationId: UUID, insertAfter: Bool) {
        guard let tabId = UUID(uuidString: transferData.tabId) else { return }

        if let result = WindowManager.shared.removeTabFromWindow(
            windowNumber: transferData.sourceWindowId,
            tabId: tabId
        ) {
            withAnimation(.default) {
                if insertAfter {
                    viewModel.insertTabAfter(result.tab, webView: result.webView, destinationId: destinationId)
                } else {
                    viewModel.insertTabBefore(result.tab, webView: result.webView, destinationId: destinationId)
                }
            }
        }
    }
    
    private func calculateTabWidth(totalAvailableWidth: CGFloat) -> CGFloat {
        let count = CGFloat(visibleTabs.count)
        guard count > 0 else { return 150 }

        let minWidth: CGFloat = 100 // Minimum width before scrolling starts

        // Spacing is 0 now
        let availableForTabs = totalAvailableWidth
        let idealWidth = availableForTabs / count

        return max(minWidth, idealWidth)
    }
}

// MARK: - Compact Address Bar (simple text field for URL input)

struct CompactAddressBar: View {
    let tab: Tab
    let inputURL: String
    let onInputURLChange: (String) -> Void
    let onNavigate: () -> Void

    @State private var isEditing = false
    @State private var localInput: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Favicon or loading indicator
            if tab.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 14, height: 14)
            } else {
                if let faviconURL = tab.faviconURL {
                    AsyncImage(url: faviconURL) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Image(systemName: "globe")
                            .foregroundColor(Color("TextMuted"))
                    }
                    .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                        .foregroundColor(Color("TextMuted"))
                        .frame(width: 14, height: 14)
                }
            }

            // Text field for URL/search
            TextField("Search or enter website", text: $localInput)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(Color("Text"))
                .focused($isFocused)
                .onSubmit {
                    onInputURLChange(localInput)
                    onNavigate()
                    isFocused = false
                }
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        // When focused, show full URL for editing
                        localInput = tab.url == "about:blank" ? "" : tab.url
                    }
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color("TabActive").opacity(0.5))
        .cornerRadius(6)
        .onAppear {
            // Display host or title when not editing
            localInput = displayText
        }
        .onChange(of: tab.url) { _, _ in
            if !isFocused {
                localInput = displayText
            }
        }
    }

    private var displayText: String {
        if tab.url == "about:blank" {
            return ""
        }
        if let url = URL(string: tab.url), let host = url.host {
            return host
        }
        return tab.url
    }
}

// MARK: - Compact Draggable Tab View (SwiftUI Wrapper) - DEPRECATED, kept for reference

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

    func makeNSView(context: Context) -> CompactDraggableTabContainerView {
        let container = CompactDraggableTabContainerView()
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
        nsView.updateTab(tab, isActive: isActive, showActiveStyle: showActiveStyle, canClose: canClose, canDrag: canDrag, inputURL: inputURL)
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
        separator.layer?.backgroundColor = NSColor(named: "Border")?.cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

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
        address.lineBreakMode = .byTruncatingTail
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
            separator.topAnchor.constraint(equalTo: topAnchor, constant: 6), // Slight padding for separator looks better? Or full height? Normal tabs usually full or slightly padded.
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

        // Width constraint for title (will be animated)
        titleWidthConstraint = title.widthAnchor.constraint(equalToConstant: 0)
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

    func updateTab(_ tab: Tab, isActive: Bool, showActiveStyle: Bool, canClose: Bool, canDrag: Bool, inputURL: String? = nil) {
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

        // Reset editing state when tab properties or active state changes externally
        if !isActive {
            isEditing = false
        }

        updateUI()
    }

    private func updateUI() {
        guard let tab = currentTab else { return }

        // Background - only show active style if showActiveStyle is true
        if isActive && showActiveStyle {
            backgroundView?.layer?.backgroundColor = NSColor(named: "TabActive")?.cgColor
        } else if isHovering && showActiveStyle {
            backgroundView?.layer?.backgroundColor = NSColor(named: "TabInactive")?.cgColor
        } else {
            backgroundView?.layer?.backgroundColor = NSColor.clear.cgColor
        }

        // Title
        titleLabel?.stringValue = tab.title
        titleLabel?.textColor = isActive ? NSColor(named: "Text") : NSColor(named: "TextMuted")

        // Show/hide title based on state
        // Show title if:
        // 1. Inactive & Hovering
        // 2. Active & Not Editing
        let shouldShowTitle = (!isActive && isHovering) || (isActive && !isEditing)
        titleWidthConstraint?.constant = shouldShowTitle ? 80 : 0
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
                faviconView?.contentTintColor = NSColor(named: "TextMuted")
            }
        }

        // Close button - only show when hovering and can close
        closeButton?.isHidden = !(isHovering && canClose)
        closeButton?.contentTintColor = NSColor(named: "TextMuted")?.withAlphaComponent(isHovering ? 1.0 : 0.4)

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
        window?.isMovableByWindowBackground = false
    }

    override func mouseDragged(with event: NSEvent) {
        // Only allow dragging when showTabsInCompactMode is enabled
        guard canDrag else { return }
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
        window?.isMovableByWindowBackground = true

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

#Preview {
    CompactTabBar(viewModel: BrowserViewModel())
        .frame(width: 800)
}
