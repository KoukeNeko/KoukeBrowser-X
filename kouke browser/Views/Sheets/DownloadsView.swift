//
//  DownloadsView.swift
//  kouke browser
//
//  Safari-style downloads list view with date grouping and search.
//

import SwiftUI

struct DownloadsView: View {
    @ObservedObject var downloadManager = DownloadManager.shared
    @State private var searchText = ""
    @State private var showingClearAlert = false
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header using shared component
            SheetHeader(
                title: "Downloads",
                onDismiss: onDismiss,
                trailingButton: AnyView(
                    Button(action: { showingClearAlert = true }) {
                        Text("Clear")
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .disabled(downloadManager.downloadItems.isEmpty)
                )
            )

            Divider()

            // Search bar using shared component
            SheetSearchBar(text: $searchText, placeholder: "Search downloads")

            // Content
            if filteredItems.isEmpty {
                SheetEmptyState(
                    icon: "arrow.down.circle",
                    title: searchText.isEmpty ? "No downloads yet" : "No results found",
                    subtitle: searchText.isEmpty ? "Files you download will appear here" : nil
                )
            } else {
                downloadsList
            }
        }
        .frame(minWidth: 360, maxWidth: 420, minHeight: 400, maxHeight: 600)
        .background(Color("Bg"))
        .alert("Clear Downloads", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                downloadManager.clearAllDownloads()
            }
        } message: {
            Text("This will remove all downloads from the list. Downloaded files will not be deleted.")
        }
    }

    private var filteredItems: [DownloadItem] {
        if searchText.isEmpty {
            return downloadManager.downloadItems
        }
        return downloadManager.searchDownloads(query: searchText)
    }

    private var downloadsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if searchText.isEmpty {
                    // Grouped by date
                    ForEach(downloadManager.groupedByDate(), id: \.title) { group in
                        Section(header: SheetSectionHeader(title: group.title)) {
                            ForEach(group.items) { item in
                                DownloadRow(item: item)
                                    .contextMenu {
                                        contextMenu(for: item)
                                    }
                            }
                        }
                    }
                } else {
                    // Search results (not grouped)
                    ForEach(filteredItems) { item in
                        DownloadRow(item: item)
                            .contextMenu {
                                contextMenu(for: item)
                            }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func contextMenu(for item: DownloadItem) -> some View {
        if item.status == .completed && item.fileExists {
            Button("Open") {
                downloadManager.openDownloadedFile(item.id)
            }

            Button("Show in Finder") {
                downloadManager.showInFinder(item.id)
            }

            Divider()
        }

        if item.status == .downloading {
            Button("Cancel") {
                downloadManager.cancelDownload(item.id)
            }

            Divider()
        }

        if item.status == .failed || item.status == .cancelled {
            Button("Retry") {
                downloadManager.retryDownload(item.id)
            }

            Divider()
        }

        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url, forType: .string)
        }

        Divider()

        Button("Remove from List", role: .destructive) {
            downloadManager.removeDownload(item.id)
        }
    }
}

// MARK: - Download Row

struct DownloadRow: View {
    let item: DownloadItem
    @ObservedObject var downloadManager = DownloadManager.shared
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // File icon
            fileIcon
                .frame(width: 32, height: 32)

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.system(size: 13))
                    .foregroundColor(Color("Text"))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    statusText

                    if let size = item.formattedFileSize, item.status == .completed {
                        Text("—")
                            .foregroundColor(Color("TextMuted"))
                        Text(size)
                            .foregroundColor(Color("TextMuted"))
                    }
                }
                .font(.system(size: 11))

                // Progress bar for downloading items
                if item.status == .downloading {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                        .frame(height: 4)
                }
            }

            Spacer()

            // Action buttons
            actionButtons
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(isHovering ? Color("CardBg") : Color.clear)
        .cornerRadius(6)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var fileIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(iconBackgroundColor)

            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundColor(iconColor)
        }
    }

    private var iconName: String {
        switch item.status {
        case .downloading, .pending:
            return "arrow.down.circle"
        case .completed:
            return fileIconForExtension(item.fileExtension)
        case .failed:
            return "exclamationmark.circle"
        case .cancelled:
            return "xmark.circle"
        }
    }

    private var iconBackgroundColor: Color {
        switch item.status {
        case .downloading, .pending:
            return Color.blue.opacity(0.15)
        case .completed:
            return Color.green.opacity(0.15)
        case .failed:
            return Color.red.opacity(0.15)
        case .cancelled:
            return Color.gray.opacity(0.15)
        }
    }

    private var iconColor: Color {
        switch item.status {
        case .downloading, .pending:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return Color("TextMuted")
        }
    }

    private func fileIconForExtension(_ ext: String) -> String {
        switch ext {
        case "pdf":
            return "doc.fill"
        case "zip", "rar", "7z", "tar", "gz":
            return "doc.zipper"
        case "jpg", "jpeg", "png", "gif", "webp", "svg":
            return "photo"
        case "mp4", "mov", "avi", "mkv":
            return "film"
        case "mp3", "wav", "aac", "flac":
            return "music.note"
        case "doc", "docx":
            return "doc.text"
        case "xls", "xlsx":
            return "tablecells"
        case "ppt", "pptx":
            return "rectangle.fill.on.rectangle.fill"
        case "dmg", "pkg":
            return "shippingbox"
        case "app":
            return "app.badge"
        default:
            return "doc"
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch item.status {
        case .pending:
            Text("Waiting...")
                .foregroundColor(Color("TextMuted"))
        case .downloading:
            if let total = item.fileSize {
                Text("\(item.formattedDownloadedSize) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                    .foregroundColor(Color("TextMuted"))
            } else {
                Text("Downloading \(item.formattedDownloadedSize)")
                    .foregroundColor(Color("TextMuted"))
            }
        case .completed:
            if item.fileExists {
                Text(item.domain ?? "Completed")
                    .foregroundColor(Color("TextMuted"))
            } else {
                Text("File moved or deleted")
                    .foregroundColor(.orange)
            }
        case .failed:
            Text(item.errorMessage ?? "Download failed")
                .foregroundColor(.red)
        case .cancelled:
            Text("Cancelled")
                .foregroundColor(Color("TextMuted"))
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if isHovering {
            switch item.status {
            case .downloading:
                Button(action: { downloadManager.cancelDownload(item.id) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color("TextMuted"))
                }
                .buttonStyle(.plain)

            case .completed where item.fileExists:
                HStack(spacing: 8) {
                    Button(action: { downloadManager.showInFinder(item.id) }) {
                        Image(systemName: "folder")
                            .font(.system(size: 14))
                            .foregroundColor(Color("TextMuted"))
                    }
                    .buttonStyle(.plain)

                    Button(action: { downloadManager.openDownloadedFile(item.id) }) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }

            case .failed, .cancelled:
                Button(action: { downloadManager.retryDownload(item.id) }) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)

            default:
                EmptyView()
            }
        }
    }
}

#Preview {
    DownloadsView(onDismiss: {})
        .frame(width: 400, height: 500)
}
