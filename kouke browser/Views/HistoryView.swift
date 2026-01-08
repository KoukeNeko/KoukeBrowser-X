//
//  HistoryView.swift
//  kouke browser
//
//  Safari-style browsing history view with date grouping and search.
//

import SwiftUI

struct HistoryView: View {
    @ObservedObject var historyManager = HistoryManager.shared
    @State private var searchText = ""
    @State private var showingClearAlert = false
    var onNavigate: (String) -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("History")
                    .font(.system(size: 18, weight: .semibold))

                Spacer()

                Button(action: { showingClearAlert = true }) {
                    Text("Clear")
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .disabled(historyManager.historyItems.isEmpty)

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color("TextMuted"))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color("TextMuted"))
                TextField("Search history", text: $searchText)
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
            .background(Color("CardBg"))
            .cornerRadius(6)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Content
            if filteredItems.isEmpty {
                emptyState
            } else {
                historyList
            }
        }
        .frame(minWidth: 320, maxWidth: 400, minHeight: 400, maxHeight: 600)
        .background(Color("Bg"))
        .alert("Clear History", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                historyManager.clearHistory()
            }
        } message: {
            Text("This will remove all browsing history. This action cannot be undone.")
        }
    }

    private var filteredItems: [HistoryItem] {
        if searchText.isEmpty {
            return historyManager.historyItems
        }
        return historyManager.searchHistory(query: searchText)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(Color("TextMuted").opacity(0.5))

            Text(searchText.isEmpty ? "No history yet" : "No results found")
                .font(.system(size: 14))
                .foregroundColor(Color("TextMuted"))

            if searchText.isEmpty {
                Text("Websites you visit will appear here")
                    .font(.system(size: 12))
                    .foregroundColor(Color("TextMuted").opacity(0.7))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if searchText.isEmpty {
                    // Grouped by date
                    ForEach(historyManager.groupedByDate(), id: \.title) { group in
                        Section(header: sectionHeader(group.title)) {
                            ForEach(group.items) { item in
                                HistoryRow(item: item, onNavigate: onNavigate)
                                    .contextMenu {
                                        contextMenu(for: item)
                                    }
                            }
                        }
                    }
                } else {
                    // Search results (not grouped)
                    ForEach(filteredItems) { item in
                        HistoryRow(item: item, onNavigate: onNavigate)
                            .contextMenu {
                                contextMenu(for: item)
                            }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color("TextMuted"))
            .textCase(.uppercase)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("Bg"))
    }

    @ViewBuilder
    private func contextMenu(for item: HistoryItem) -> some View {
        Button("Open") {
            onNavigate(item.url)
        }

        Button("Open in New Tab") {
            NotificationCenter.default.post(name: .openURLInNewTab, object: item.url)
        }

        Divider()

        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url, forType: .string)
        }

        Divider()

        Button("Delete", role: .destructive) {
            historyManager.removeHistoryItem(item.id)
        }
    }
}

// MARK: - History Row

struct HistoryRow: View {
    let item: HistoryItem
    let onNavigate: (String) -> Void
    @State private var isHovering = false

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        Button(action: { onNavigate(item.url) }) {
            HStack(spacing: 12) {
                // Favicon
                AsyncImage(url: item.faviconURL) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image(systemName: "globe")
                        .foregroundColor(Color("TextMuted"))
                }
                .frame(width: 16, height: 16)

                // Title and URL
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13))
                        .foregroundColor(Color("Text"))
                        .lineLimit(1)

                    Text(item.domain ?? item.url)
                        .font(.system(size: 11))
                        .foregroundColor(Color("TextMuted"))
                        .lineLimit(1)
                }

                Spacer()

                // Time
                Text(timeFormatter.string(from: item.visitedAt))
                    .font(.system(size: 11))
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

#Preview {
    HistoryView(onNavigate: { _ in }, onDismiss: {})
        .frame(width: 360, height: 500)
}
