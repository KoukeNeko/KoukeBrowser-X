//
//  TabBar.swift
//  kouke browser
//
//  Horizontal tab bar with tabs, close buttons, and new tab button.
//

import SwiftUI
import AppKit

struct TabBar: View {
    @ObservedObject var viewModel: BrowserViewModel

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
                        TabItem(
                            tab: tab,
                            isActive: tab.id == viewModel.activeTabId,
                            onSelect: { viewModel.switchToTab(tab.id) },
                            onClose: { viewModel.closeTab(tab.id) },
                            canClose: viewModel.tabs.count > 1
                        )
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
        #if os(macOS)
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
        #endif
    }
}

struct TabItem: View {
    let tab: Tab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let canClose: Bool
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Favicon or loading spinner
                Group {
                    if tab.isLoading {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                    } else if let faviconURL = tab.faviconURL {
                        AsyncImage(url: faviconURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Rectangle()
                                .fill(Color("TextMuted").opacity(0.2))
                        }
                        .frame(width: 16, height: 16)
                    } else {
                        Rectangle()
                            .fill(Color("TextMuted").opacity(0.2))
                            .frame(width: 16, height: 16)
                    }
                }
                
                // Title
                Text(tab.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(isActive ? Color("Text") : Color("TextMuted"))
                
                Spacer(minLength: 0)
                
                // Close button
                if canClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color("TextMuted").opacity(isHovering ? 1 : 0.4))
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(minWidth: 120, maxWidth: 220, maxHeight: .infinity)
            .background(isActive ? Color("TabActive") : Color("TabInactive"))
            .overlay(
                Rectangle()
                    .fill(Color("Border"))
                    .frame(width: 1),
                alignment: .trailing
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

#Preview {
    TabBar(viewModel: BrowserViewModel())
        .frame(width: 600)
}
