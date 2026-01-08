//
//  StartPage.swift
//  kouke browser
//
//  New tab start page with favorites grid including folders.
//

import SwiftUI

struct StartPage: View {
    var onNavigate: (String) -> Void
    @ObservedObject var bookmarkManager = BookmarkManager.shared
    @State private var currentFolderId: UUID? = nil
    @State private var folderPath: [UUID] = []

    private var currentFolderName: String {
        if let folderId = currentFolderId,
           let folder = bookmarkManager.folders.first(where: { $0.id == folderId }) {
            return folder.name
        }
        return "Bookmarks"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                    .frame(height: 80)

                // Bookmarks Section
                let currentFolders = bookmarkManager.folders(in: currentFolderId)
                let currentBookmarks = bookmarkManager.bookmarks(in: currentFolderId)

                if !currentBookmarks.isEmpty || !currentFolders.isEmpty || currentFolderId != nil {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header with back button when in folder
                        HStack {
                            if currentFolderId != nil {
                                Button(action: goBack) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color("TextMuted"))
                                }
                                .buttonStyle(.plain)
                            }

                            Text(currentFolderName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color("TextMuted"))
                                .textCase(.uppercase)
                                .kerning(0.5)
                        }

                        // Grid of folders and bookmarks
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 16)
                        ], spacing: 16) {
                            // Folders first
                            ForEach(currentFolders) { folder in
                                FolderButton(
                                    folder: folder,
                                    bookmarkManager: bookmarkManager,
                                    action: { enterFolder(folder.id) }
                                )
                            }

                            // Then bookmarks
                            ForEach(currentBookmarks.prefix(12 - currentFolders.count)) { bookmark in
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

    @State private var isHovering = false

    private var bookmarksInFolder: [Bookmark] {
        bookmarkManager.bookmarks(in: folder.id)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Folder icon container with 3x3 favicon grid
                ZStack {
                    Rectangle()
                        .fill(Color("CardBg"))
                        .border(Color("Border"), width: 1)

                    if bookmarksInFolder.isEmpty {
                        // Empty folder icon
                        Image(systemName: "folder.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.yellow)
                    } else {
                        // 3x3 grid of favicons
                        FaviconCollage(bookmarks: Array(bookmarksInFolder.prefix(9)))
                    }
                }
                .frame(width: 64, height: 64)
                .scaleEffect(isHovering ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isHovering)

                // Title
                Text(folder.name)
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

// MARK: - Favicon Collage (3x3 Grid)

struct FaviconCollage: View {
    let bookmarks: [Bookmark]

    private var gridSize: Int {
        // Determine grid size based on bookmark count
        if bookmarks.count >= 9 { return 3 }
        if bookmarks.count >= 4 { return 2 }
        return 1
    }

    private var cellSize: CGFloat {
        64.0 / CGFloat(gridSize)
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
                            Rectangle()
                                .fill(Color("TabInactive"))
                                .frame(width: cellSize, height: cellSize)
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
                } else {
                    Rectangle()
                        .fill(Color("TabInactive"))
                        .frame(width: cellSize, height: cellSize)
                }
            }
        }
        .frame(width: 64, height: 64)
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
