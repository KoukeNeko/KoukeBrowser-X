//
//  BookmarksView.swift
//  kouke browser
//
//  Bookmarks sidebar and management view.
//

import SwiftUI

struct BookmarksView: View {
    @ObservedObject var bookmarkManager = BookmarkManager.shared
    @Environment(\.dismiss) private var dismiss
    let onNavigate: (String) -> Void

    @State private var folderPath: [UUID] = []  // Navigation stack
    @State private var editingBookmark: Bookmark? = nil
    @State private var editingFolder: BookmarkFolder? = nil
    @State private var showingNewFolderDialog = false
    @State private var newFolderName = ""
    @State private var searchText = ""

    private var currentFolderId: UUID? {
        folderPath.last
    }

    private var currentFolderName: String {
        if let folderId = currentFolderId,
           let folder = bookmarkManager.folders.first(where: { $0.id == folderId }) {
            return folder.name
        }
        return "Bookmarks"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                // Back button when in a folder
                if !folderPath.isEmpty {
                    Button(action: { folderPath.removeLast() }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(Color("TextMuted"))
                    }
                    .buttonStyle(.plain)
                }

                Text(currentFolderName)
                    .font(.headline)

                Spacer()

                Button(action: { showingNewFolderDialog = true }) {
                    Image(systemName: "folder.badge.plus")
                        .foregroundColor(Color("TextMuted"))
                }
                .buttonStyle(.plain)
                .help("New Folder")

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .foregroundColor(Color("TextMuted"))
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color("TitleBarBg"))

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color("TextMuted"))
                TextField("Search bookmarks", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color("TextMuted"))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color("TabInactive"))
            .cornerRadius(6)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Content
            if filteredBookmarks.isEmpty && filteredFolders.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 48))
                        .foregroundColor(Color("TextMuted"))
                    Text(searchText.isEmpty ? "No bookmarks yet" : "No results found")
                        .foregroundColor(Color("TextMuted"))
                    if searchText.isEmpty {
                        Text("Press \(Image(systemName: "command")) D to bookmark the current page")
                            .font(.caption)
                            .foregroundColor(Color("TextMuted"))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // Folders
                    ForEach(filteredFolders) { folder in
                        FolderRow(folder: folder, onTap: {
                            folderPath.append(folder.id)
                        }, onEdit: { editingFolder = folder })
                            .contextMenu {
                                Button("Rename") { editingFolder = folder }
                                Button("Delete", role: .destructive) {
                                    bookmarkManager.removeFolder(folder.id)
                                }
                            }
                    }

                    // Bookmarks
                    ForEach(filteredBookmarks) { bookmark in
                        BookmarkRow(bookmark: bookmark, onNavigate: {
                            onNavigate(bookmark.url)
                            dismiss()
                        }, onEdit: {
                            editingBookmark = bookmark
                        })
                        .contextMenu {
                            Button("Open") {
                                onNavigate(bookmark.url)
                                dismiss()
                            }
                            Button("Open in New Tab") {
                                NotificationCenter.default.post(name: .openURLInNewTab, object: bookmark.url)
                                dismiss()
                            }
                            Divider()
                            Button("Edit") { editingBookmark = bookmark }
                            Button("Delete", role: .destructive) {
                                bookmarkManager.removeBookmark(bookmark.id)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 280, minHeight: 400)
        .background(Color("Bg"))
        .sheet(item: $editingBookmark) { bookmark in
            EditBookmarkView(bookmark: bookmark) { updatedTitle, updatedURL in
                bookmarkManager.updateBookmark(bookmark.id, title: updatedTitle, url: updatedURL)
            }
        }
        .sheet(item: $editingFolder) { folder in
            EditFolderView(folder: folder) { updatedName in
                bookmarkManager.updateFolder(folder.id, name: updatedName)
            }
        }
        .alert("New Folder", isPresented: $showingNewFolderDialog) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create") {
                if !newFolderName.isEmpty {
                    bookmarkManager.addFolder(name: newFolderName, parentId: currentFolderId)
                    newFolderName = ""
                }
            }
        }
    }

    private var filteredBookmarks: [Bookmark] {
        let bookmarks = bookmarkManager.bookmarks(in: currentFolderId)
        if searchText.isEmpty {
            return bookmarks
        }
        return bookmarks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.url.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredFolders: [BookmarkFolder] {
        let folders = bookmarkManager.folders(in: currentFolderId)
        if searchText.isEmpty {
            return folders
        }
        return folders.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
}

// MARK: - Bookmark Row

struct BookmarkRow: View {
    let bookmark: Bookmark
    let onNavigate: () -> Void
    let onEdit: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            // Favicon
            AsyncImage(url: bookmark.faviconURL) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                Image(systemName: "globe")
                    .foregroundColor(Color("TextMuted"))
            }
            .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.title)
                    .lineLimit(1)
                    .foregroundColor(Color("Text"))

                Text(bookmark.url)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(Color("TextMuted"))
            }

            Spacer()

            if isHovering {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundColor(Color("TextMuted"))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onNavigate()
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Folder Row

struct FolderRow: View {
    let folder: BookmarkFolder
    let onEdit: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundColor(.blue)
                .frame(width: 16, height: 16)

            Text(folder.name)
                .lineLimit(1)
                .foregroundColor(Color("Text"))

            Spacer()

            if isHovering {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundColor(Color("TextMuted"))
                }
                .buttonStyle(.plain)
            }

            Image(systemName: "chevron.right")
                .foregroundColor(Color("TextMuted"))
                .font(.caption)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Edit Bookmark View

struct EditBookmarkView: View {
    let bookmark: Bookmark
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var url: String

    init(bookmark: Bookmark, onSave: @escaping (String, String) -> Void) {
        self.bookmark = bookmark
        self.onSave = onSave
        _title = State(initialValue: bookmark.title)
        _url = State(initialValue: bookmark.url)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Bookmark")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.caption)
                    .foregroundColor(Color("TextMuted"))
                TextField("Bookmark name", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("URL")
                    .font(.caption)
                    .foregroundColor(Color("TextMuted"))
                TextField("URL", text: $url)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Save") {
                    onSave(title, url)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

// MARK: - Edit Folder View

struct EditFolderView: View {
    let folder: BookmarkFolder
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(folder: BookmarkFolder, onSave: @escaping (String) -> Void) {
        self.folder = folder
        self.onSave = onSave
        _name = State(initialValue: folder.name)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Folder")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.caption)
                    .foregroundColor(Color("TextMuted"))
                TextField("Folder name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Save") {
                    onSave(name)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 280)
    }
}

// MARK: - Add Bookmark Dialog

struct AddBookmarkDialog: View {
    let initialTitle: String
    let initialURL: String
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var url: String

    init(title: String, url: String, onSave: @escaping (String, String) -> Void) {
        self.initialTitle = title
        self.initialURL = url
        self.onSave = onSave
        _title = State(initialValue: title)
        _url = State(initialValue: url)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.blue)
                Text("Add Bookmark")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.caption)
                    .foregroundColor(Color("TextMuted"))
                TextField("Bookmark name", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("URL")
                    .font(.caption)
                    .foregroundColor(Color("TextMuted"))
                TextField("URL", text: $url)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Add") {
                    onSave(title, url)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty || url.isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let openURLInNewTab = Notification.Name("openURLInNewTab")
}

#Preview {
    BookmarksView(onNavigate: { _ in })
}
