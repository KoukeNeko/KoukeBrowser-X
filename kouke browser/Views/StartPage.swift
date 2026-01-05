//
//  StartPage.swift
//  kouke browser
//
//  New tab start page with favorites grid.
//

import SwiftUI

struct StartPage: View {
    var onNavigate: (String) -> Void
    
    // Favorites data matching the Tauri version
    private let favorites: [(title: String, url: String, icon: String)] = [
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
                        ForEach(favorites, id: \.url) { fav in
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
