//
//  StartPage.swift
//  kouke browser
//
//  New tab start page with favorites grid.
//

import SwiftUI

struct StartPage: View {
    var onNavigate: (String) -> Void
    @ObservedObject var bookmarkManager = BookmarkManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                    .frame(height: 80)

                // Bookmarks Section
                if !bookmarkManager.bookmarks.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Bookmarks")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color("TextMuted"))
                            .textCase(.uppercase)
                            .kerning(0.5)

                        // Grid of bookmarks
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 16)
                        ], spacing: 16) {
                            ForEach(bookmarkManager.bookmarks.prefix(12)) { bookmark in
                                BookmarkButton(
                                    bookmark: bookmark,
                                    action: { onNavigate(bookmark.url) }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    .frame(maxWidth: 600)
                } else {
                    // Empty state when no bookmarks exist
                    VStack(spacing: 16) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(Color("TextMuted").opacity(0.5))
                        
                        Text("No bookmarks yet")
                            .font(.system(size: 14))
                            .foregroundColor(Color("TextMuted"))
                        
                        Text("Press ⌘D to bookmark the current page")
                            .font(.system(size: 12))
                            .foregroundColor(Color("TextMuted").opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color("Bg"))
    }
}

// MARK: - Bookmark Button for Start Page

struct BookmarkButton: View {
    let bookmark: Bookmark
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Icon container with favicon
                ZStack {
                    Rectangle()
                        .fill(Color("CardBg"))
                        .border(Color("Border"), width: 1)

                    AsyncImage(url: bookmark.faviconURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 64, height: 64)
                                .clipped()
                        case .failure:
                            Image(systemName: "globe")
                                .font(.system(size: 24))
                                .foregroundColor(Color("TextMuted"))
                        case .empty:
                            ProgressView()
                                .scaleEffect(0.6)
                        @unknown default:
                            Image(systemName: "globe")
                                .font(.system(size: 24))
                                .foregroundColor(Color("TextMuted"))
                        }
                    }
                }
                .frame(width: 64, height: 64)
                .scaleEffect(isHovering ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isHovering)

                // Title
                Text(bookmark.title)
                    .font(.system(size: 11))
                    .foregroundColor(isHovering ? Color("Text") : Color("TextMuted"))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

#Preview {
    StartPage(onNavigate: { _ in })
        .frame(width: 800, height: 600)
}
