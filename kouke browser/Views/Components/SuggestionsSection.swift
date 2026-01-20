//
//  SuggestionsSection.swift
//  kouke browser
//
//  Suggestions grid section for StartPage.
//

import SwiftUI

struct SuggestionsSection: View {
    let suggestions: [PageSuggestion]
    let onNavigate: (String) -> Void
    let onRemove: (UUID) -> Void
    let onClearAll: () -> Void
    var horizontalPadding: CGFloat = 32
    var maxItems: Int = 8

    // Grid configuration
    private let cardWidth: CGFloat = 180
    private let spacing: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Suggestions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color("TextMuted"))
                    .textCase(.uppercase)
                    .kerning(0.5)

                Spacer()

                // Clear all button (only if there are suggestions)
                if !suggestions.isEmpty {
                    Button(action: onClearAll) {
                        HStack(spacing: 4) {
                            Text("Clear All")
                                .font(.system(size: 12))
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Grid of suggestions
            if suggestions.isEmpty {
                // Empty state
                emptyState
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth), spacing: spacing)],
                    spacing: spacing
                ) {
                    ForEach(suggestions.prefix(maxItems)) { suggestion in
                        SuggestionCard(
                            suggestion: suggestion,
                            onNavigate: onNavigate,
                            onRemove: { onRemove(suggestion.id) }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(Color("TextMuted").opacity(0.5))

            Text("Your frequently visited pages will appear here")
                .font(.system(size: 13))
                .foregroundColor(Color("TextMuted"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

#Preview {
    SuggestionsSection(
        suggestions: [
            PageSuggestion(url: "https://github.com", title: "GitHub"),
            PageSuggestion(url: "https://google.com", title: "Google"),
        ],
        onNavigate: { _ in },
        onRemove: { _ in },
        onClearAll: { }
    )
    .frame(width: 800)
    .background(Color("Bg"))
}
