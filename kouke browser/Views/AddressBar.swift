//
//  AddressBar.swift
//  kouke browser
//
//  Navigation controls and URL input field.
//

import SwiftUI

struct AddressBar: View {
    @ObservedObject var viewModel: BrowserViewModel
    @FocusState private var isAddressFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Navigation controls
            HStack(spacing: 4) {
                NavButton(
                    icon: "chevron.left",
                    action: viewModel.goBack,
                    isEnabled: viewModel.activeTab?.canGoBack == true
                )
                NavButton(
                    icon: "chevron.right",
                    action: viewModel.goForward,
                    isEnabled: viewModel.activeTab?.canGoForward == true
                )
                NavButton(icon: "arrow.clockwise", action: viewModel.reload)
            }
            
            // Address input container (no border, like Rust version)
            HStack(spacing: 8) {
                // Lock icon
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color("TextMuted").opacity(0.7))

                // URL text field
                TextField("Search or enter website", text: $viewModel.inputURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color("TextMuted"))
                    .focused($isAddressFocused)
                    .onSubmit {
                        viewModel.navigate()
                    }
            }
            
            // Bookmark button
            Button(action: {}) {
                Image(systemName: "star")
                    .font(.system(size: 14))
                    .foregroundColor(Color("TextMuted"))
            }
            .buttonStyle(.plain)
            .padding(6)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 6)
        .frame(height: 40)
        .background(Color("Bg"))
    }
}

struct NavButton: View {
    let icon: String
    let action: () -> Void
    var isEnabled: Bool = true

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(isEnabled ? Color("TextMuted") : Color("TextMuted").opacity(0.4))
                .frame(width: 28, height: 28)
                .background(isHovering && isEnabled ? Color("AccentHover") : Color.clear)
                .cornerRadius(2) // Minimal rounding
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

#Preview {
    AddressBar(viewModel: BrowserViewModel())
        .frame(width: 600)
}
