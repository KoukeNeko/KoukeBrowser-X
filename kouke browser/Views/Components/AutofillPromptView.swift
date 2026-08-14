//
//  AutofillPromptView.swift
//  kouke browser
//
//  The card asking whether to fill a saved login or remember a new one.
//
//  Filling only ever happens from a button in here. That is the whole point of
//  the card: a page cannot silently harvest a credential when reaching the page
//  requires the user to click.
//

import SwiftUI

struct AutofillPromptView: View {

    let prompt: AutofillPrompt
    let onFill: (SavedCredential) -> Void
    let onSave: (String, String) -> Void
    let onDismiss: () -> Void

    private static let cardWidth: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            switch prompt {
            case .offerToFill(_, _, let credentials):
                fillOptions(credentials)
            case .offerToSave(_, _, let username, let password):
                saveOptions(username: username, password: password, isUpdate: false)
            case .offerToUpdate(_, _, let username, let password):
                saveOptions(username: username, password: password, isUpdate: true)
            }
        }
        .padding(16)
        .frame(width: Self.cardWidth)
        .background(Color("CardBg"))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color("Border"), lineWidth: 1)
        )
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.2), radius: 12, y: 4)
        .padding(.top, 12)
        .padding(.trailing, 16)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 12))
                .foregroundColor(Color("TextMuted"))

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color("Text"))

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundColor(Color("TextMuted"))
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
    }

    private var title: String {
        switch prompt {
        case .offerToFill: return "Fill password"
        case .offerToSave: return "Save password?"
        case .offerToUpdate: return "Update password?"
        }
    }

    // MARK: - Fill

    private func fillOptions(_ credentials: [SavedCredential]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saved for \(prompt.host)")
                .font(.system(size: 11))
                .foregroundColor(Color("TextMuted"))

            ForEach(credentials) { credential in
                Button(action: { onFill(credential) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 13))
                            .foregroundColor(Color("TextMuted"))

                        Text(credential.displayUsername)
                            .font(.system(size: 12))
                            .foregroundColor(Color("Text"))
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HoverHighlightButtonStyle())
            }
        }
    }

    // MARK: - Save

    private func saveOptions(username: String, password: String, isUpdate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(prompt.host)
                    .font(.system(size: 12))
                    .foregroundColor(Color("Text"))

                Text(username.isEmpty ? "(no username)" : username)
                    .font(.system(size: 11))
                    .foregroundColor(Color("TextMuted"))
            }

            HStack(spacing: 8) {
                Spacer()

                Button("Not Now", action: onDismiss)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(Color("TextMuted"))

                Button(isUpdate ? "Update" : "Save") {
                    onSave(username, password)
                }
                .keyboardShortcut(.defaultAction)
                .font(.system(size: 12))
            }
        }
    }
}

// MARK: - Button Style

private struct HoverHighlightButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isHovering ? Color("Bg") : Color.clear)
            .cornerRadius(6)
            .onHover { isHovering = $0 }
    }
}
