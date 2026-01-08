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

    @State private var folderPath: [UUID] = []
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
            // Header using shared component
            SheetHeader(
                title: currentFolderName,
                showBackButton: !folderPath.isEmpty,
                onBack: { folderPath.removeLast() },
                onDismiss: { dismiss() },
                trailingButton: AnyView(
                    Button(action: { showingNewFolderDialog = true }) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 14))
                            .foregroundColor(Color("TextMuted"))
                    }
                    .buttonStyle(.plain)
                    .help("New Folder")
                )
            )

            Divider()

            // Search using shared component
            SheetSearchBar(text: $searchText, placeholder: "Search bookmarks")

            // Content
            if filteredBookmarks.isEmpty && filteredFolders.isEmpty {
                SheetEmptyState(
                    icon: "bookmark",
                    title: searchText.isEmpty ? "No bookmarks yet" : "No results found",
                    subtitle: searchText.isEmpty ? "Press ⌘D to bookmark the current page" : nil
                )
            } else {
                bookmarksList
            }
        }
        .frame(minWidth: 320, maxWidth: 400, minHeight: 400, maxHeight: 600)
        .background(Color("Bg"))
        .sheet(item: $editingBookmark) { bookmark in
            EditBookmarkView(bookmark: bookmark) { updatedTitle, updatedURL, updatedFolderId in
                bookmarkManager.updateBookmark(bookmark.id, title: updatedTitle, url: updatedURL, folderId: .some(updatedFolderId))
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

    private var bookmarksList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Folders
                ForEach(filteredFolders) { folder in
                    BookmarkFolderRow(folder: folder, onTap: {
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
                    BookmarkItemRow(bookmark: bookmark, onNavigate: {
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
            .padding(.horizontal, 16)
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

// MARK: - Bookmark Item Row

struct BookmarkItemRow: View {
    let bookmark: Bookmark
    let onNavigate: () -> Void
    let onEdit: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onNavigate) {
            HStack(spacing: 12) {
                AsyncImage(url: bookmark.faviconURL) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image(systemName: "globe")
                        .foregroundColor(Color("TextMuted"))
                }
                .frame(width: 16, height: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(bookmark.title)
                        .font(.system(size: 13))
                        .foregroundColor(Color("Text"))
                        .lineLimit(1)

                    Text(bookmark.url)
                        .font(.system(size: 11))
                        .foregroundColor(Color("TextMuted"))
                        .lineLimit(1)
                }

                Spacer()

                if isHovering {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundColor(Color("TextMuted"))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(isHovering ? Color("CardBg") : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Bookmark Folder Row

struct BookmarkFolderRow: View {
    let folder: BookmarkFolder
    let onTap: () -> Void
    let onEdit: () -> Void
    @ObservedObject private var bookmarkManager = BookmarkManager.shared
    @State private var isHovering = false

    private var bookmarkCount: Int {
        bookmarkManager.bookmarks(in: folder.id).count
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.yellow)
                    .frame(width: 16, height: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.system(size: 13))
                        .foregroundColor(Color("Text"))
                        .lineLimit(1)

                    Text(bookmarkCount == 1 ? "1 bookmark" : "\(bookmarkCount) bookmarks")
                        .font(.system(size: 11))
                        .foregroundColor(Color("TextMuted"))
                        .lineLimit(1)
                }

                Spacer()

                if isHovering {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundColor(Color("TextMuted"))
                    }
                    .buttonStyle(.plain)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(Color("TextMuted"))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(isHovering ? Color("CardBg") : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Edit Bookmark View

struct EditBookmarkView: View {
    @ObservedObject var bookmarkManager = BookmarkManager.shared
    let bookmark: Bookmark
    let onSave: (String, String, UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var url: String
    @State private var folderId: UUID?

    init(bookmark: Bookmark, onSave: @escaping (String, String, UUID?) -> Void) {
        self.bookmark = bookmark
        self.onSave = onSave
        _title = State(initialValue: bookmark.title)
        _url = State(initialValue: bookmark.url)
        _folderId = State(initialValue: bookmark.folderId)
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Folder")
                    .font(.caption)
                    .foregroundColor(Color("TextMuted"))
                Picker("", selection: $folderId) {
                    Text("Bookmarks Bar").tag(UUID?.none)
                    ForEach(bookmarkManager.folders) { folder in
                        Text(folder.name).tag(UUID?.some(folder.id))
                    }
                }
                .labelsHidden()
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Save") {
                    onSave(title, url, folderId)
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
    @ObservedObject var bookmarkManager = BookmarkManager.shared
    let initialTitle: String
    let initialURL: String
    let onSave: (String, String, UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var url: String
    @State private var folderId: UUID? = nil

    init(title: String, url: String, onSave: @escaping (String, String, UUID?) -> Void) {
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Folder")
                    .font(.caption)
                    .foregroundColor(Color("TextMuted"))
                Picker("", selection: $folderId) {
                    Text("Bookmarks Bar").tag(UUID?.none)
                    ForEach(bookmarkManager.folders) { folder in
                        Text(folder.name).tag(UUID?.some(folder.id))
                    }
                }
                .labelsHidden()
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Add") {
                    onSave(title, url, folderId)
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

// MARK: - Add Bookmark Popover (Folder Selection)

struct AddBookmarkPopover: View {
    @ObservedObject var bookmarkManager = BookmarkManager.shared
    @Environment(\.dismiss) private var dismiss

    let initialTitle: String
    let initialURL: String
    let onSave: (String, String, UUID?) -> Void

    @State private var title: String
    @State private var folderPath: [UUID] = []

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

    init(title: String, url: String, onSave: @escaping (String, String, UUID?) -> Void) {
        self.initialTitle = title
        self.initialURL = url
        self.onSave = onSave
        _title = State(initialValue: title)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header using shared component
            SheetHeader(
                title: folderPath.isEmpty ? "Add Bookmark" : currentFolderName,
                showBackButton: !folderPath.isEmpty,
                onBack: { folderPath.removeLast() },
                onDismiss: { dismiss() }
            )

            Divider()

            // Name input using shared component
            SheetInputField(label: "Name", text: $title, placeholder: "Bookmark name", icon: "bookmark.fill")
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            // URL preview
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 12))
                    .foregroundColor(Color("TextMuted"))
                Text(initialURL)
                    .font(.system(size: 11))
                    .foregroundColor(Color("TextMuted"))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            // Folder section header using shared component
            SheetSectionHeader(title: "Location")
                .padding(.horizontal, 16)
                .padding(.top, 4)

            // Folder list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Subfolders
                    ForEach(bookmarkManager.folders(in: currentFolderId)) { folder in
                        FolderSelectionRow(
                            folder: folder,
                            onTap: { folderPath.append(folder.id) }
                        )
                    }
                }
            }

            // Bottom buttons using shared component
            SheetButtonBar(
                leading: {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.escape)
                        .foregroundColor(Color("TextMuted"))
                },
                trailing: {
                    Button(action: {
                        onSave(title, initialURL, currentFolderId)
                        dismiss()
                    }) {
                        Text("Add Bookmark")
                            .fontWeight(.medium)
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.isEmpty)
                }
            )
        }
        .frame(minWidth: 320, maxWidth: 400, minHeight: 400, maxHeight: 500)
        .background(Color("Bg"))
    }
}

// MARK: - Folder Selection Row

struct FolderSelectionRow: View {
    let folder: BookmarkFolder
    let onTap: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.yellow)

                Text(folder.name)
                    .font(.system(size: 13))
                    .foregroundColor(Color("Text"))
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(Color("TextMuted"))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(isHovering ? Color("CardBg") : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}


// MARK: - Notification Extension

extension Notification.Name {
    static let openURLInNewTab = Notification.Name("openURLInNewTab")
}

#Preview {
    BookmarksView(onNavigate: { _ in })
}
