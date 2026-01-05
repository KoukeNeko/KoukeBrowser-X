import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TabBar: View {
    @ObservedObject var viewModel: BrowserViewModel
    @State private var draggedTabId: UUID?

    var body: some View {
        HStack(spacing: 0) {
            #if os(macOS)
            // Space for native traffic lights
            Color.clear
                .frame(width: 80, height: 40)
            #endif

            // Tab strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(viewModel.tabs) { tab in
                        DraggableTabView(
                            tab: tab,
                            isActive: tab.id == viewModel.activeTabId,
                            onSelect: { viewModel.switchToTab(tab.id) },
                            onClose: { viewModel.closeTab(tab.id) },
                            canClose: viewModel.tabs.count > 1,
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
                        .frame(minWidth: 120, maxWidth: 220, maxHeight: .infinity)
                        .opacity(draggedTabId == tab.id ? 0.5 : 1.0)
                    }

                    // Add tab button
                    Button(action: { viewModel.addTab() }) {
                        Text("+")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color("TextMuted"))
                            .frame(width: 32, height: 28)
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
            .layoutPriority(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 40)
        .background(Color("TitleBarBg"))
    }

    private func detachTabToNewWindow(tabId: UUID, at screenPoint: NSPoint) {
        guard let result = viewModel.detachTab(tabId) else { return }

        // Create new window with the detached tab and its WebView
        WindowManager.shared.createNewWindow(with: result.tab, webView: result.webView, at: screenPoint)
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
