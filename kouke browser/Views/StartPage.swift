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

    // Default favorites if no bookmarks exist
    private let defaultFavorites: [(title: String, url: String, icon: String)] = [
        ("Apple", "https://apple.com", ""),
        ("iCloud", "https://icloud.com", "☁️"),
        ("Google", "https://google.com", "G"),
        ("Twitter", "https://x.com", "𝕏"),
        ("GitHub", "https://github.com", "🐙"),
        ("YouTube", "https://youtube.com", "▶️"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                    .frame(height: 80)

                // Bookmarks Section (if any)
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

                    Spacer().frame(height: 40)
                }

                // Favorites Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Favorites")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color("TextMuted"))
                        .textCase(.uppercase)
                        .kerning(0.5)

                    // Grid of favorites
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 16)
                    ], spacing: 16) {
                        ForEach(defaultFavorites, id: \.url) { fav in
                            FavoriteButton(
                                title: fav.title,
                                icon: fav.icon,
                                action: { onNavigate(fav.url) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: 600)

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

                    AsyncImage(url: bookmark.faviconURL) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Image(systemName: "globe")
                            .font(.system(size: 20))
                            .foregroundColor(Color("TextMuted"))
                    }
                    .frame(width: 24, height: 24)
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

struct FavoriteButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Icon container
                ZStack {
                    Rectangle()
                        .fill(Color("CardBg"))
                        .border(Color("Border"), width: 1)

                    Text(icon)
                        .font(.system(size: 20))
                }
                .frame(width: 64, height: 64) // Larger, square
                .scaleEffect(isHovering ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isHovering)

                // Title
                Text(title)
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
