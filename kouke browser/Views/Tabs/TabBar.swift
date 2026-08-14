//
//  TabBar.swift
//  kouke browser
//
//  Normal-style tab bar: a row of tabs in the title bar area.
//
//  The tab strip is only as wide as its tabs; the space left over is an
//  explicit window-drag region. Nothing that drags the window ever overlaps a
//  tab, which is what keeps tab drags from turning into window drags.
//

import SwiftUI
import AppKit

struct TabBar: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject private var settings = BrowserSettings.shared
    @State private var draggedTabId: UUID?
    @State private var isEndDropTargeted: Bool = false

    /// The band must stay taller than the window's 32pt title bar: content
    /// that lies entirely inside the title bar area is not composited and
    /// renders blank. TrafficLightsView draws the window controls centered
    /// in this height, so they line up with the tabs.
    private static let barHeight: CGFloat = 40
    private static let addButtonWidth: CGFloat = 36
    private static let maxTabWidth: CGFloat = 200
    private static let minTabWidth: CGFloat = 100

    var body: some View {
        GeometryReader { geometry in
            let layout = stripLayout(totalWidth: geometry.size.width)

            HStack(spacing: 0) {
                #if os(macOS)
                TrafficLightsView()

                Color.clear
                    .frame(width: TrafficLightsView.trailingInset)
                    .movesWindowOnDrag()
                #endif

                tabStrip(tabWidth: layout.tabWidth)
                    .frame(width: layout.stripWidth)

                // Everything past the last tab moves the window instead.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .movesWindowOnDrag()
            }
        }
        .frame(height: Self.barHeight)
        .background(ChromeBandBackground(appearance: settings.chromeAppearance,
                                         solidColor: Color("TitleBarBg")))
        .background(
            // Drops that miss every tab append to the end of this window.
            TabDropZoneView(
                isDropTargeted: $isEndDropTargeted,
                onReceiveTab: receiveTabAtEnd
            )
        )
    }

    // MARK: - Tab Strip

    private func tabStrip(tabWidth: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(viewModel.tabs) { tab in
                        TabItemView(
                            tab: tab,
                            isActive: tab.id == viewModel.activeTabId,
                            appearance: settings.chromeAppearance,
                            canClose: true,
                            isBeingDragged: draggedTabId == tab.id,
                            onSelect: { viewModel.switchToTab(tab.id) },
                            onClose: { viewModel.closeTab(tab.id) },
                            onReorder: { draggedId, edge in
                                reorderTab(draggedId, relativeTo: tab.id, edge: edge)
                            },
                            onReceiveTab: { transferData, edge in
                                receiveTab(transferData, relativeTo: tab.id, edge: edge)
                            },
                            onDetach: detachTab,
                            onDragStateChange: { draggedTabId = $0 }
                        )
                        .frame(width: tabWidth, height: Self.barHeight)
                        .id(tab.id)
                    }

                    addTabButton
                }
            }
            .onChange(of: viewModel.activeTabId) { _, newId in
                guard let newId = newId else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newId, anchor: .center)
                }
            }
        }
    }

    private var addTabButton: some View {
        Button(action: { viewModel.addTab() }) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color("TextMuted"))
                .frame(width: Self.addButtonWidth, height: Self.barHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New Tab")
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    // MARK: - Layout

    /// Tabs shrink to share the available room and stop at `minTabWidth`,
    /// after which the strip scrolls. Whatever they don't use stays free for
    /// the window-drag region.
    private func stripLayout(totalWidth: CGFloat) -> (tabWidth: CGFloat, stripWidth: CGFloat) {
        let tabCount = CGFloat(viewModel.tabs.count)
        guard tabCount > 0 else { return (Self.maxTabWidth, Self.addButtonWidth) }

        #if os(macOS)
        let leadingInset = TrafficLightsView.reservedWidth
        #else
        let leadingInset: CGFloat = 0
        #endif

        let availableWidth = max(0, totalWidth - leadingInset - Self.addButtonWidth)
        let idealWidth = availableWidth / tabCount
        let tabWidth = min(max(idealWidth, Self.minTabWidth), Self.maxTabWidth)
        let stripWidth = min(tabCount * tabWidth + Self.addButtonWidth,
                             availableWidth + Self.addButtonWidth)
        return (tabWidth, stripWidth)
    }

    // MARK: - Tab Actions

    private func reorderTab(_ draggedId: UUID, relativeTo destinationId: UUID, edge: TabDropEdge) {
        withAnimation(.default) {
            switch edge {
            case .trailing:
                viewModel.moveTabAfter(draggedId: draggedId, destinationId: destinationId)
            case .leading:
                viewModel.moveTabBefore(draggedId: draggedId, destinationId: destinationId)
            }
        }
    }

    private func detachTab(_ tabId: UUID, at screenPoint: NSPoint) {
        WindowManager.shared.detachTabToNewWindow(tabId, from: viewModel, at: screenPoint)
    }

    private func receiveTab(_ transferData: TabTransferData, relativeTo destinationId: UUID, edge: TabDropEdge) {
        guard let tabId = UUID(uuidString: transferData.tabId) else { return }

        // A tab already in this window is a reorder, not a cross-window transfer.
        if viewModel.tabs.contains(where: { $0.id == tabId }) {
            reorderTab(tabId, relativeTo: destinationId, edge: edge)
            return
        }

        let position: WindowManager.TabInsertPosition = edge == .trailing
            ? .after(destinationId)
            : .before(destinationId)
        WindowManager.shared.transferTab(
            from: transferData.sourceWindowId,
            tabId: tabId,
            to: viewModel,
            position: position
        )
    }

    private func receiveTabAtEnd(_ transferData: TabTransferData) {
        guard let tabId = UUID(uuidString: transferData.tabId) else { return }

        if viewModel.tabs.contains(where: { $0.id == tabId }) {
            viewModel.moveTab(withID: tabId, to: viewModel.tabs.count)
            return
        }

        WindowManager.shared.transferTab(
            from: transferData.sourceWindowId,
            tabId: tabId,
            to: viewModel,
            position: .atEnd
        )
    }
}

// MARK: - End-of-Strip Drop Zone

struct TabDropZoneView: NSViewRepresentable {
    @Binding var isDropTargeted: Bool
    var onReceiveTab: (TabTransferData) -> Void

    func makeNSView(context: Context) -> TabDropZoneNSView {
        let view = TabDropZoneNSView()
        view.onDropTargetChanged = { isTargeted in
            DispatchQueue.main.async { isDropTargeted = isTargeted }
        }
        view.onReceiveTab = onReceiveTab
        return view
    }

    func updateNSView(_ nsView: TabDropZoneNSView, context: Context) {
        nsView.onReceiveTab = onReceiveTab
    }
}

class TabDropZoneNSView: NSView {
    var onDropTargetChanged: ((Bool) -> Void)?
    var onReceiveTab: ((TabTransferData) -> Void)?

    private var isTargeted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.tabData])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.tabData])
    }

    private func setTargeted(_ targeted: Bool) {
        guard isTargeted != targeted else { return }
        isTargeted = targeted
        onDropTargetChanged?(targeted)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: [.tabData]) != nil else { return [] }
        setTargeted(true)
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: [.tabData]) != nil else {
            setTargeted(false)
            return []
        }
        setTargeted(true)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setTargeted(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        setTargeted(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setTargeted(false)

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
        .frame(width: 800)
}
