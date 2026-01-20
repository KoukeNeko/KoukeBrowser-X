//
//  SuggestionCard.swift
//  kouke browser
//
//  Card component for displaying a page suggestion with thumbnail.
//

import SwiftUI

struct SuggestionCard: View {
    let suggestion: PageSuggestion
    let onNavigate: (String) -> Void
    let onRemove: () -> Void

    @State private var isHovering = false
    @State private var thumbnail: NSImage?
    @ObservedObject private var faviconService = FaviconService.shared

    // Card dimensions (larger than bookmark cards)
    private let cardWidth: CGFloat = 180
    private let thumbnailHeight: CGFloat = 120

    var body: some View {
        Button(action: { onNavigate(suggestion.url) }) {
            VStack(spacing: 0) {
                // Thumbnail area
                ZStack(alignment: .topTrailing) {
                    // Thumbnail or placeholder
                    thumbnailView
                        .frame(width: cardWidth, height: thumbnailHeight)
                        .clipped()

                    // Remove button (visible on hover)
                    if isHovering {
                        Button(action: onRemove) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                }

                // Info area
                VStack(alignment: .leading, spacing: 4) {
                    // Title with favicon
                    HStack(spacing: 6) {
                        // Favicon
                        AsyncImage(url: suggestion.faviconURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            default:
                                Image(systemName: "globe")
                                    .foregroundColor(Color("TextMuted"))
                            }
                        }
                        .frame(width: 14, height: 14)

                        Text(suggestion.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color("Text"))
                            .lineLimit(1)
                    }

                    // Domain and time
                    HStack {
                        Text(suggestion.domain)
                            .font(.system(size: 11))
                            .foregroundColor(Color("TextMuted"))
                            .lineLimit(1)

                        Spacer()

                        Text(suggestion.relativeTime)
                            .font(.system(size: 10))
                            .foregroundColor(Color("TextMuted").opacity(0.7))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(width: cardWidth, alignment: .leading)
                .background(Color("CardBg"))
            }
            .background(Color("CardBg"))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color("Border"), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isHovering ? 0.15 : 0.05), radius: isHovering ? 8 : 4)
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            loadThumbnail()
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail = thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            // Placeholder with gradient background
            ZStack {
                LinearGradient(
                    colors: [Color("TabInactive"), Color("Bg")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: "globe")
                    .font(.system(size: 32))
                    .foregroundColor(Color("TextMuted").opacity(0.3))
            }
        }
    }

    private func loadThumbnail() {
        guard let path = suggestion.thumbnailPath else { return }
        Task {
            if let image = ThumbnailService.shared.loadThumbnail(path: path) {
                await MainActor.run {
                    self.thumbnail = image
                }
            }
        }
    }
}

#Preview {
    SuggestionCard(
        suggestion: PageSuggestion(
            url: "https://github.com",
            title: "GitHub: Let's build from here"
        ),
        onNavigate: { _ in },
        onRemove: { }
    )
    .padding()
    .background(Color("Bg"))
}
