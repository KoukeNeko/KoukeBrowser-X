//
//  StartPage.swift
//  kouke browser
//
//  New tab start page with favorites grid including folders.
//

import SwiftUI

struct StartPage: View {
    var onNavigate: (String) -> Void
    var config: FavoritesGridConfig = .startPage
    var isCompact: Bool = false  // true = dropdown 模式（無 ScrollView、無頂部空白）

    @ObservedObject var bookmarkManager = BookmarkManager.shared
    @State private var currentFolderId: UUID? = nil
    @State private var folderPath: [UUID] = []

    private var currentFolderName: String {
        if let folderId = currentFolderId,
           let folder = bookmarkManager.folders.first(where: { $0.id == folderId }) {
            return folder.name
        }
        return isCompact ? "收藏夾" : "Bookmarks"
    }

    private var hasContent: Bool {
        let folders = bookmarkManager.folders(in: currentFolderId)
        let bookmarks = bookmarkManager.bookmarks(in: currentFolderId)
        return !folders.isEmpty || !bookmarks.isEmpty || currentFolderId != nil
    }

    var body: some View {
        if isCompact {
            // Dropdown 模式：不用 ScrollView
            contentView
        } else {
            // 全頁模式：使用 ScrollView
            ScrollView {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 80)
                    contentView
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color("Bg"))
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: isCompact ? 12 : 16) {
                // Header with back button when in folder
                HStack(spacing: 4) {
                    if currentFolderId != nil {
                        Button(action: goBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: isCompact ? 12 : 14, weight: .medium))
                                .foregroundColor(Color("TextMuted"))
                                .frame(width: isCompact ? 20 : 24, height: isCompact ? 20 : 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Text(currentFolderName)
                        .font(.system(size: isCompact ? 11 : 12, weight: .medium))
                        .foregroundColor(Color("TextMuted"))
                        .textCase(.uppercase)
                        .kerning(0.5)
                }
                .padding(.horizontal, config.horizontalPadding)
                .padding(.top, isCompact ? 16 : 0)
                .frame(height: isCompact ? nil : 24)

                // 使用共用的 FavoritesGridView
                FavoritesGridView(
                    bookmarkManager: bookmarkManager,
                    folderId: currentFolderId,
                    config: config,
                    onNavigate: onNavigate,
                    onFolderTap: enterFolder
                )
                .padding(.horizontal, config.horizontalPadding)
                .padding(.bottom, isCompact ? 20 : 0)
            }
            .frame(maxWidth: isCompact ? .infinity : 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
        } else {
            // Empty state
            VStack(spacing: isCompact ? 12 : 16) {
                Image(systemName: "bookmark")
                    .font(.system(size: isCompact ? 32 : 48, weight: .light))
                    .foregroundColor(Color("TextMuted").opacity(0.5))

                Text(isCompact ? "尚無書籤" : "No bookmarks yet")
                    .font(.system(size: isCompact ? 13 : 14))
                    .foregroundColor(Color("TextMuted"))

                Text(isCompact ? "按 ⌘D 加入目前頁面" : "Press ⌘D to bookmark the current page")
                    .font(.system(size: isCompact ? 11 : 12))
                    .foregroundColor(Color("TextMuted").opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .frame(height: isCompact ? 120 : nil)
            .padding(.top, isCompact ? 0 : 100)
        }
    }

    private func enterFolder(_ folderId: UUID) {
        folderPath.append(folderId)
        currentFolderId = folderId
    }

    private func goBack() {
        folderPath.removeLast()
        currentFolderId = folderPath.last
    }
}

// MARK: - Folder Button for Start Page

struct FolderButton: View {
    let folder: BookmarkFolder
    let bookmarkManager: BookmarkManager
    let action: () -> Void
    var size: CGFloat = 64
    @ObservedObject private var faviconService = FaviconService.shared

    @State private var isHovering = false

    private var bookmarksInFolder: [Bookmark] {
        bookmarkManager.bookmarks(in: folder.id)
    }

    private var maxFavicons: Int {
        size >= 64 ? 9 : 4
    }

    private var iconFontSize: CGFloat {
        size >= 64 ? 28 : 24
    }

    private var titleFontSize: CGFloat {
        size >= 64 ? 11 : 10
    }

    private var spacing: CGFloat {
        size >= 64 ? 8 : 6
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: spacing) {
                // Folder icon container with favicon grid
                ZStack {
                    Rectangle()
                        .fill(Color("CardBg"))
                        .border(Color("Border"), width: 1)

                    if bookmarksInFolder.isEmpty {
                        // Empty folder icon
                        Image(systemName: "folder.fill")
                            .font(.system(size: iconFontSize))
                            .foregroundColor(.yellow)
                    } else {
                        // Grid of favicons
                        FaviconCollage(bookmarks: Array(bookmarksInFolder.prefix(maxFavicons)), size: size)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .scaleEffect(isHovering ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isHovering)

                // Title
                Text(folder.name)
                    .font(.system(size: titleFontSize))
                    .foregroundColor(isHovering ? Color("Text") : Color("TextMuted"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: size - 4)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Favicon Collage (Configurable Grid)

struct FaviconCollage: View {
    let bookmarks: [Bookmark]
    var size: CGFloat = 64
    @ObservedObject private var faviconService = FaviconService.shared

    private var gridSize: Int {
        // Determine grid size based on bookmark count and container size
        if size >= 64 {
            if bookmarks.count >= 9 { return 3 }
            if bookmarks.count >= 4 { return 2 }
            return 1
        } else {
            // Smaller size: max 2x2 grid
            if bookmarks.count >= 4 { return 2 }
            return 1
        }
    }

    private var cellSize: CGFloat {
        size / CGFloat(gridSize)
    }

    private var globeIconSize: CGFloat {
        size >= 64 ? 24 : 20
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(cellSize), spacing: 0), count: gridSize),
            spacing: 0
        ) {
            ForEach(0..<(gridSize * gridSize), id: \.self) { index in
                if index < bookmarks.count {
                    AsyncImage(url: bookmarks[index].faviconURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: cellSize, height: cellSize)
                                .clipped()
                        case .failure:
                             if gridSize == 1 {
                                 Image(systemName: "globe")
                                     .font(.system(size: globeIconSize))
                                     .foregroundColor(Color("TextMuted"))
                                     .frame(width: cellSize, height: cellSize)
                             } else {
                                Rectangle()
                                    .fill(Color("TabInactive"))
                                    .frame(width: cellSize, height: cellSize)
                             }
                        case .empty:
                            Rectangle()
                                .fill(Color("TabInactive"))
                                .frame(width: cellSize, height: cellSize)
                        @unknown default:
                            Rectangle()
                                .fill(Color("TabInactive"))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                    .id(bookmarks[index].faviconURL)
                } else {
                    Rectangle()
                        .fill(Color("TabInactive"))
                        .frame(width: cellSize, height: cellSize)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Bookmark Button for Start Page

struct BookmarkButton: View {
    let bookmark: Bookmark
    let action: () -> Void
    var size: CGFloat = 64
    @ObservedObject private var faviconService = FaviconService.shared

    @State private var isHovering = false

    private var iconFontSize: CGFloat {
        size >= 64 ? 24 : 20
    }

    private var titleFontSize: CGFloat {
        size >= 64 ? 11 : 10
    }

    private var spacing: CGFloat {
        size >= 64 ? 8 : 6
    }

    private var progressScale: CGFloat {
        size >= 64 ? 0.6 : 0.5
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: spacing) {
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
                                .frame(width: size, height: size)
                                .clipped()
                        case .failure:
                            Image(systemName: "globe")
                                .font(.system(size: iconFontSize))
                                .foregroundColor(Color("TextMuted"))
                        case .empty:
                            ProgressView()
                                .scaleEffect(progressScale)
                        @unknown default:
                            Image(systemName: "globe")
                                .font(.system(size: iconFontSize))
                                .foregroundColor(Color("TextMuted"))
                        }
                    }
                    .id(bookmark.faviconURL)
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .scaleEffect(isHovering ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isHovering)

                // Title
                Text(bookmark.title)
                    .font(.system(size: titleFontSize))
                    .foregroundColor(isHovering ? Color("Text") : Color("TextMuted"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: size - 4)
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
