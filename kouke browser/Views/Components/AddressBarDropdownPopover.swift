//
//  AddressBarDropdownPopover.swift
//  kouke browser
//
//  NSPopover wrapper for the address bar dropdown (SwiftUI -> AppKit bridge).
//

import AppKit
import SwiftUI

/// 地址欄下拉選單的 NSPopover 控制器
class AddressBarDropdownPopover: NSObject {
    private var popover: NSPopover?
    private var hostingController: NSHostingController<AnyView>?
    
    // Callbacks
    var onNavigate: ((String) -> Void)?
    var onSwitchTab: ((UUID) -> Void)?
    var onDismiss: (() -> Void)?
    
    // Data source
    private var viewModel: BrowserViewModel?
    private var currentTab: Tab?
    
    // MARK: - Public API
    
    /// 顯示下拉選單
    func show(
        relativeTo rect: NSRect,
        of view: NSView,
        preferredEdge: NSRectEdge,
        inputText: String,
        viewModel: BrowserViewModel?,
        currentTab: Tab?
    ) {
        self.viewModel = viewModel
        self.currentTab = currentTab
        
        // 如果已經顯示，更新內容
        if let popover = popover, popover.isShown {
            updateContent(inputText: inputText)
            return
        }
        
        // 建立新的 popover
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        
        // 建立內容
        let contentView = createContentView(inputText: inputText)
        let hostingController = NSHostingController(rootView: AnyView(contentView))
        
        popover.contentViewController = hostingController
        self.popover = popover
        self.hostingController = hostingController
        
        // 顯示
        popover.show(relativeTo: rect, of: view, preferredEdge: preferredEdge)
    }
    
    /// 更新下拉選單內容
    func updateContent(inputText: String) {
        guard let hostingController = hostingController else { return }
        
        let contentView = createContentView(inputText: inputText)
        hostingController.rootView = AnyView(contentView)
    }
    
    /// 關閉下拉選單
    func close() {
        popover?.close()
        popover = nil
        hostingController = nil
    }
    
    /// 檢查是否正在顯示
    var isShown: Bool {
        popover?.isShown ?? false
    }
    
    // MARK: - Private
    
    private func createContentView(inputText: String) -> some View {
        AddressBarDropdownContent(
            inputText: inputText,
            viewModel: viewModel,
            currentTab: currentTab,
            onNavigate: { [weak self] url in
                self?.onNavigate?(url)
                self?.close()
            },
            onSwitchTab: { [weak self] tabId in
                self?.onSwitchTab?(tabId)
                self?.close()
            },
            onDismiss: { [weak self] in
                self?.close()
            }
        )
    }
}

// MARK: - NSPopoverDelegate

extension AddressBarDropdownPopover: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        onDismiss?()
        popover = nil
        hostingController = nil
    }
}

// MARK: - Content View (SwiftUI)

private struct AddressBarDropdownContent: View {
    let inputText: String
    let viewModel: BrowserViewModel?
    let currentTab: Tab?
    let onNavigate: (String) -> Void
    let onSwitchTab: (UUID) -> Void
    let onDismiss: () -> Void
    
    @State private var suggestions: [SuggestionItem] = []
    @State private var isLoading = false
    
    private var showFavorites: Bool {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        AddressBarDropdownView(
            suggestions: suggestions,
            showFavorites: showFavorites,
            onSelect: handleSelect,
            onNavigate: onNavigate,
            onSwitchTab: onSwitchTab
        )
        .task(id: inputText) {
            await loadSuggestions()
        }
    }
    
    private func handleSelect(_ item: SuggestionItem) {
        if let url = item.url {
            onNavigate(url)
        }
    }
    
    private func loadSuggestions() async {
        guard !showFavorites else {
            suggestions = []
            return
        }
        
        isLoading = true
        
        let results = await SuggestionService.shared.getSuggestions(
            query: inputText,
            currentTab: currentTab,
            allTabs: viewModel?.tabs ?? [],
            activeTabId: viewModel?.activeTabId
        )
        
        suggestions = results
        isLoading = false
    }
}
