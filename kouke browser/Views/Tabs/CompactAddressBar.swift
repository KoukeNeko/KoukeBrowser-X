//
//  CompactAddressBar.swift
//  kouke browser
//
//  Compact address bar for the compact tab style.
//

import SwiftUI

struct CompactAddressBar: View {
    let tab: Tab
    let inputURL: String
    let onInputURLChange: (String) -> Void
    let onNavigate: () -> Void

    @State private var isEditing = false
    @State private var localInput: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Favicon or loading indicator
            if tab.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 14, height: 14)
            } else {
                if let faviconURL = tab.faviconURL {
                    AsyncImage(url: faviconURL) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Image(systemName: "globe")
                            .foregroundColor(Color("TextMuted"))
                    }
                    .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                        .foregroundColor(Color("TextMuted"))
                        .frame(width: 14, height: 14)
                }
            }

            // Text field for URL/search
            TextField("Search or enter website", text: $localInput)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(Color("Text"))
                .focused($isFocused)
                .onSubmit {
                    onInputURLChange(localInput)
                    onNavigate()
                    isFocused = false
                }
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        // When focused, show full URL for editing
                        localInput = tab.url == "kouke:blank" ? "" : tab.url
                    }
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color("TabActive").opacity(0.5))
        .cornerRadius(6)
        .onAppear {
            // Display host or title when not editing
            localInput = displayText
        }
        .onChange(of: tab.url) { _, _ in
            if !isFocused {
                localInput = displayText
            }
        }
    }

    private var displayText: String {
        if tab.url == "kouke:blank" {
            return ""
        }
        if let url = URL(string: tab.url), let host = url.host {
            return host
        }
        return tab.url
    }
}
