import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TabBar: View {
    @ObservedObject var viewModel: BrowserViewModel
    @State private var draggedTabId: UUID?
    @State private var availableWidth: CGFloat = 800
    @State private var isDropTargeted: Bool = false

    // Constants for tab sizing
    private let maxTabWidth: CGFloat = 200
    private let minTabWidth: CGFloat = 100
    private let trafficLightsWidth: CGFloat = 80
    private let addButtonWidth: CGFloat = 40

    var body: some View {
        HStack(spacing: 0) {
            #if os(macOS)
            // Space for native traffic lights
            Color.clear
                .frame(width: trafficLightsWidth, height: 40)
            #endif

            // Tab strip with horizontal scrolling
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(viewModel.tabs) { tab in
                            DraggableTabView(
                                tab: tab,
                                isActive: tab.id == viewModel.activeTabId,
                                onSelect: { viewModel.switchToTab(tab.id) },
                                onClose: { viewModel.closeTab(tab.id) },
                                canClose: true,
                                onReorder: { draggedId, destinationId, insertAfter in
                                    withAnimation(.default) {
                                        if insertAfter {
                                            viewModel.moveTabAfter(draggedId: draggedId, destinationId: destinationId)
                                        } else {
                                            viewModel.moveTabBefore(draggedId: draggedId, destinationId: destinationId)
                                        }
                                    }
                                },
                                onReceiveTab: { transferData, destinationId, insertAfter in
                                    receiveTabFromOtherWindow(transferData: transferData, destinationId: destinationId, insertAfter: insertAfter)
                                },
                                onDetach: { tabId, screenPoint in
                                    detachTabToNewWindow(tabId: tabId, at: screenPoint)
                                },
                                onDragStarted: { id in
                                    draggedTabId = id
                                },
                                onDragEnded: {
                                    draggedTabId = nil
                                }
                            )
                            .frame(width: calculateTabWidth(), height: 40)
                            .opacity(draggedTabId == tab.id ? 0.5 : 1.0)
                            .id(tab.id)
                        }

                        // Add tab button
                        Button(action: { viewModel.addTab() }) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color("TextMuted"))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                }
                .onChange(of: viewModel.activeTabId) { _, newId in
                    // Scroll to active tab when it changes
                    if let newId = newId {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(newId, anchor: .center)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { geometry in
                    Color.clear.onAppear {
                        availableWidth = geometry.size.width
                    }
                    .onChange(of: geometry.size.width) { _, newWidth in
                        availableWidth = newWidth
                    }
                }
            )
            .background(
                // Drop zone as background - doesn't affect layout
                TabDropZoneView(
                    isDropTargeted: $isDropTargeted,
                    onReceiveTab: { transferData in
                        receiveTabAtEnd(transferData: transferData)
                    }
                )
            )
        }
        .frame(height: 40)
        .background(Color("TitleBarBg"))
    }

    /// Calculate the width for each tab based on available space
    private func calculateTabWidth() -> CGFloat {
        let tabCount = CGFloat(viewModel.tabs.count)
        guard tabCount > 0 else { return maxTabWidth }

        // Available width for tabs (excluding add button)
        let tabAreaWidth = availableWidth - addButtonWidth

        // Calculate ideal width per tab
        let idealWidth = tabAreaWidth / tabCount

        // Clamp between min and max
        return min(max(idealWidth, minTabWidth), maxTabWidth)
    }

    private func detachTabToNewWindow(tabId: UUID, at screenPoint: NSPoint) {
        guard let result = viewModel.detachTab(tabId) else { return }

        // Create new window with the detached tab and its WebView
        WindowManager.shared.createNewWindow(with: result.tab, webView: result.webView, at: Optional(screenPoint))
    }

    private func receiveTabFromOtherWindow(transferData: TabTransferData, destinationId: UUID, insertAfter: Bool) {
        guard let tabId = UUID(uuidString: transferData.tabId) else { return }

        NSLog("📥 TabBar: Receiving tab from window #\(transferData.sourceWindowId)")
        if let result = WindowManager.shared.removeTabFromWindow(
            windowNumber: transferData.sourceWindowId,
            tabId: tabId
        ) {
            NSLog("📥 TabBar: Adding tab to destination, webView: \(result.webView != nil ? "present" : "nil")")
            // Don't use animation to avoid state update issues during drag
            if insertAfter {
                viewModel.insertTabAfter(result.tab, webView: result.webView, destinationId: destinationId)
            } else {
                viewModel.insertTabBefore(result.tab, webView: result.webView, destinationId: destinationId)
            }
            NSLog("📥 TabBar: Tab added successfully, total tabs: \(viewModel.tabs.count)")
        }
    }

    private func receiveTabAtEnd(transferData: TabTransferData) {
        guard let tabId = UUID(uuidString: transferData.tabId) else { return }

        NSLog("📥 TabBar: Receiving tab at end from window #\(transferData.sourceWindowId)")
        if let result = WindowManager.shared.removeTabFromWindow(
            windowNumber: transferData.sourceWindowId,
            tabId: tabId
        ) {
            NSLog("📥 TabBar: Adding tab at end, webView: \(result.webView != nil ? "present" : "nil")")
            // Don't use animation to avoid state update issues during drag
            viewModel.addExistingTab(result.tab)
            if let webView = result.webView {
                viewModel.registerWebView(webView, for: result.tab.id)
            }
            NSLog("📥 TabBar: Tab added at end successfully, total tabs: \(viewModel.tabs.count)")
        }
    }
}

// MARK: - Tab Drop Zone View

struct TabDropZoneView: NSViewRepresentable {
    @Binding var isDropTargeted: Bool
    var onReceiveTab: (TabTransferData) -> Void

    func makeNSView(context: Context) -> TabDropZoneNSView {
        let view = TabDropZoneNSView()
        view.onDropTargetChanged = { isTargeted in
            DispatchQueue.main.async {
                isDropTargeted = isTargeted
            }
        }
        view.onReceiveTab = onReceiveTab
        return view
    }

    func updateNSView(_ nsView: TabDropZoneNSView, context: Context) {}
}

class TabDropZoneNSView: NSView {
    var onDropTargetChanged: ((Bool) -> Void)?
    var onReceiveTab: ((TabTransferData) -> Void)?

    private var dropIndicator: NSView?
    private var isShowingIndicator = false

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

        // Create drop indicator
        let indicator = NSView()
        indicator.wantsLayer = true
        indicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        indicator.layer?.cornerRadius = 1.5
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.isHidden = true
        addSubview(indicator)
        dropIndicator = indicator

        NSLayoutConstraint.activate([
            indicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            indicator.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            indicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            indicator.widthAnchor.constraint(equalToConstant: 3)
        ])
    }

    private func showDropIndicator() {
        guard !isShowingIndicator else { return }
        isShowingIndicator = true
        dropIndicator?.isHidden = false
        onDropTargetChanged?(true)
    }

    private func hideDropIndicator() {
        guard isShowingIndicator else { return }
        isShowingIndicator = false
        dropIndicator?.isHidden = true
        onDropTargetChanged?(false)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: [.tabData]) != nil else {
            return []
        }
        showDropIndicator()
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: [.tabData]) != nil else {
            hideDropIndicator()
            return []
        }
        showDropIndicator()
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hideDropIndicator()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        hideDropIndicator()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hideDropIndicator()

        guard let data = sender.draggingPasteboard.data(forType: .tabData),
              let transferData = try? JSONDecoder().decode(TabTransferData.self, from: data) else {
            return false
        }

        onReceiveTab?(transferData)
        return true
    }
}

#Preview {
    TabBar(viewModel: BrowserViewModel())
        .frame(width: 600)
}
