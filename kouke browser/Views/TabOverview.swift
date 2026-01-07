//
//  TabOverview.swift
//  kouke browser
//
//  Grid view showing all tabs with thumbnails, similar to Safari's "Show All Tabs"
//

import SwiftUI
import AppKit

struct TabOverview: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Binding var isPresented: Bool
    @Namespace private var animation

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ZStack {
            // Solid background to fully cover content
            Color("TitleBarBg")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("\(viewModel.tabs.count) Tabs")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(Color("Text"))

                    Spacer()

                    // Close button
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Color("TextMuted"))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(.horizontal, 30)
                .padding(.top, 60)
                .padding(.bottom, 20)

                // Tab grid
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(viewModel.tabs) { tab in
                            TabThumbnailCard(
                                tab: tab,
                                isActive: tab.id == viewModel.activeTabId,
                                onSelect: {
                                    viewModel.switchToTab(tab.id)
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        isPresented = false
                                    }
                                },
                                onClose: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        viewModel.closeTab(tab.id)
                                    }
                                },
                                canClose: viewModel.tabs.count > 1
                            )
                        }

                        // New tab button
                        NewTabCard(onTap: {
                            viewModel.addTab()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isPresented = false
                            }
                        })
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)
                }
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}

struct TabThumbnailCard: View {
    let tab: Tab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let canClose: Bool

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                // Window Title Bar
                HStack(spacing: 8) {
                    // Close Button (Mac-like)
                    if canClose {
                        Button(action: onClose) {
                            Circle()
                                .fill(isHovering ? Color.red.opacity(0.8) : Color.gray.opacity(0.3))
                                .frame(width: 12, height: 12)
                                .overlay(
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(Color.white)
                                        .opacity(isHovering ? 1 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 4)
                    } else {
                         Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 12, height: 12)
                            .padding(.leading, 4)
                            .opacity(0) // Hidden but takes space
                    }

                    // Favicon & Title
                    HStack(spacing: 4) {
                        if let faviconURL = tab.faviconURL {
                            AsyncImage(url: faviconURL) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } placeholder: {
                                Image(systemName: "globe")
                                    .foregroundColor(Color("TextMuted"))
                            }
                            .frame(width: 12, height: 12)
                        }

                        Text(tab.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color("Text"))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 6)
                .frame(height: 24)
                .background(Color("TitleBarBg"))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color("Border").opacity(0.5)),
                    alignment: .bottom
                )

                // Thumbnail Content
                ZStack {
                    Color("Bg")

                    #if os(macOS)
                    if let thumbnail = tab.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .clipped()
                    } else {
                        thumbnailPlaceholder
                    }
                    #else
                    if let thumbnail = tab.thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .clipped()
                    } else {
                        thumbnailPlaceholder
                    }
                    #endif

                    // Loading indicator
                    if tab.isLoading {
                        Color.black.opacity(0.2)
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }
            .aspectRatio(1.5, contentMode: .fit) // Window aspect ratio
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive ? Color.accentColor : Color("Border"), lineWidth: isActive ? 2 : 1)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
             withAnimation(.easeInOut(duration: 0.15)) {
                 isHovering = hovering
             }
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
    }

    @ViewBuilder
    private var thumbnailPlaceholder: some View {
        Group {
            if tab.url == "about:blank" {
                Image(systemName: "plus.square.dashed")
                    .font(.system(size: 32))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 32))
            }
        }
        .foregroundColor(Color("TextMuted").opacity(0.3))
    }
}

struct NewTabCard: View {
    let onTap: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color("Bg").opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                            .foregroundColor(Color("TextMuted").opacity(0.5))
                    )

                VStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .light))
                    Text("New Tab")
                        .font(.system(size: 12))
                }
                .foregroundColor(Color("TextMuted"))
            }
            .aspectRatio(1.5, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .opacity(isHovering ? 1.0 : 0.7)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
    }
}

#Preview {
    TabOverview(viewModel: BrowserViewModel(), isPresented: .constant(true))
        .frame(width: 800, height: 600)
}
