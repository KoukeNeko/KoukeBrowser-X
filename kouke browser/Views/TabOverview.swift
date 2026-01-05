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
        GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)
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
                .padding(.top, 30)
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
                // Thumbnail area
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color("Bg"))

                    // Actual thumbnail or placeholder
                    #if os(macOS)
                    if let thumbnail = tab.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: 150)
                            .clipped()
                    } else {
                        thumbnailPlaceholder
                    }
                    #else
                    if let thumbnail = tab.thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: 150)
                            .clipped()
                    } else {
                        thumbnailPlaceholder
                    }
                    #endif

                    // Loading indicator
                    if tab.isLoading {
                        Color.black.opacity(0.3)
                        ProgressView()
                            .scaleEffect(1.5)
                    }

                    // Close button (shown on hover)
                    if canClose && isHovering {
                        VStack {
                            HStack {
                                Spacer()
                                Button(action: onClose) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.3), radius: 2)
                                }
                                .buttonStyle(.plain)
                                .padding(8)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? Color.accentColor : Color("Border"), lineWidth: isActive ? 3 : 1)
                )

                // Title
                HStack(spacing: 6) {
                    if let faviconURL = tab.faviconURL {
                        AsyncImage(url: faviconURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Image(systemName: "globe")
                                .foregroundColor(Color("TextMuted"))
                        }
                        .frame(width: 14, height: 14)
                    }

                    Text(tab.title)
                        .font(.system(size: 12))
                        .foregroundColor(Color("Text"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
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
        if tab.url == "about:blank" {
            Image(systemName: "house.fill")
                .font(.system(size: 48))
                .foregroundColor(Color("TextMuted").opacity(0.3))
        } else if tab.url == "about:settings" {
            Image(systemName: "gear")
                .font(.system(size: 48))
                .foregroundColor(Color("TextMuted").opacity(0.3))
        } else if let faviconURL = tab.faviconURL {
            AsyncImage(url: faviconURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
            } placeholder: {
                Image(systemName: "globe")
                    .font(.system(size: 48))
                    .foregroundColor(Color("TextMuted").opacity(0.3))
            }
        } else {
            Image(systemName: "globe")
                .font(.system(size: 48))
                .foregroundColor(Color("TextMuted").opacity(0.3))
        }
    }
}

struct NewTabCard: View {
    let onTap: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color("Bg").opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                                .foregroundColor(Color("Border"))
                        )

                    Image(systemName: "plus")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(Color("TextMuted"))
                }
                .frame(height: 150)

                Text("New Tab")
                    .font(.system(size: 12))
                    .foregroundColor(Color("TextMuted"))
                    .padding(.vertical, 8)
            }
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
