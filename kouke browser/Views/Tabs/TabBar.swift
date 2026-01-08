import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TabBar: View {
    @ObservedObject var viewModel: BrowserViewModel
    @State private var draggedTabId: UUID?
    @State private var availableWidth: CGFloat = 800

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
        // Request the tab from the source window via WindowManager
        guard let tabId = UUID(uuidString: transferData.tabId) else { return }

        // Find the source window and remove the tab from it
        if let result = WindowManager.shared.removeTabFromWindow(
            windowNumber: transferData.sourceWindowId,
            tabId: tabId
        ) {
            // Insert into this window with the WebView
            withAnimation(.default) {
                if insertAfter {
                    viewModel.insertTabAfter(result.tab, webView: result.webView, destinationId: destinationId)
                } else {
                    viewModel.insertTabBefore(result.tab, webView: result.webView, destinationId: destinationId)
                }
            }
        }
    }
}

#Preview {
    TabBar(viewModel: BrowserViewModel())
        .frame(width: 600)
}
