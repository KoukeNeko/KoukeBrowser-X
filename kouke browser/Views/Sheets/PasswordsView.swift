//
//  PasswordsView.swift
//  kouke browser
//
//  Manages saved logins. Follows the DownloadsView / BookmarksView sheet layout.
//
//  A password is only ever fetched from the keychain for the row the user asked
//  to reveal, and is dropped again when the sheet closes.
//

import SwiftUI

struct PasswordsView: View {

    let onDismiss: () -> Void

    @StateObject private var credentialManager = CredentialManager.shared

    @State private var searchText = ""
    @State private var showingDeleteAllAlert = false
    @State private var credentialPendingDeletion: SavedCredential?

    /// Passwords revealed in this sitting, keyed by credential.
    ///
    /// Deliberately view-local: closing the sheet forgets them, so a revealed
    /// password never outlives the moment the user asked to see it.
    @State private var revealedPasswords: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Passwords",
                onDismiss: onDismiss,
                trailingButton: AnyView(
                    Button(action: { showingDeleteAllAlert = true }) {
                        Text("Remove All")
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .disabled(credentialManager.credentials.isEmpty)
                )
            )

            Divider()

            SheetSearchBar(text: $searchText, placeholder: "Search passwords")

            if let errorMessage = credentialManager.lastError {
                keychainErrorBanner(errorMessage)
            }

            if filteredCredentials.isEmpty {
                SheetEmptyState(
                    icon: "key",
                    title: searchText.isEmpty ? "No saved passwords" : "No results found",
                    subtitle: searchText.isEmpty
                        ? "Logins you choose to save will appear here"
                        : nil
                )
            } else {
                credentialsList
            }
        }
        .frame(minWidth: 380, maxWidth: 460, minHeight: 400, maxHeight: 600)
        .background(Color("Bg"))
        .onAppear { credentialManager.reload() }
        .onDisappear { revealedPasswords.removeAll() }
        .alert("Remove All Passwords", isPresented: $showingDeleteAllAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Remove All", role: .destructive) {
                credentialManager.deleteAll()
                revealedPasswords.removeAll()
            }
        } message: {
            Text("This permanently deletes every saved login from your keychain. It cannot be undone.")
        }
        .alert(item: $credentialPendingDeletion) { credential in
            Alert(
                title: Text("Remove Password"),
                message: Text("Remove the saved login for \(credential.displayHost)?"),
                primaryButton: .destructive(Text("Remove")) {
                    revealedPasswords[credential.id] = nil
                    credentialManager.delete(credential)
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Content

    private var credentialsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filteredCredentials) { credential in
                    PasswordRow(
                        credential: credential,
                        revealedPassword: revealedPasswords[credential.id],
                        onToggleReveal: { toggleReveal(of: credential) },
                        onCopy: { copyPassword(of: credential) }
                    )
                    .contextMenu {
                        Button("Copy Username") {
                            copyToPasteboard(credential.username)
                        }
                        Button("Copy Password") {
                            copyPassword(of: credential)
                        }
                        Divider()
                        Button("Remove", role: .destructive) {
                            credentialPendingDeletion = credential
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func keychainErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(Color("TextMuted"))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Filtering

    private var filteredCredentials: [SavedCredential] {
        guard !searchText.isEmpty else { return credentialManager.credentials }
        return credentialManager.credentials.filter {
            $0.host.localizedCaseInsensitiveContains(searchText)
                || $0.username.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Actions

    private func toggleReveal(of credential: SavedCredential) {
        if revealedPasswords[credential.id] != nil {
            revealedPasswords[credential.id] = nil
            return
        }
        revealedPasswords[credential.id] = credentialManager.password(for: credential)
    }

    private func copyPassword(of credential: SavedCredential) {
        guard let password = credentialManager.password(for: credential) else { return }
        copyToPasteboard(password)
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

// MARK: - Row

private struct PasswordRow: View {

    let credential: SavedCredential
    let revealedPassword: String?
    let onToggleReveal: () -> Void
    let onCopy: () -> Void

    @State private var isHovering = false

    /// Fixed-width mask so a row's width never hints at password length.
    private static let maskedPassword = "••••••••••"

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 14))
                .foregroundColor(Color("TextMuted"))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(credential.displayHost)
                    .font(.system(size: 13))
                    .foregroundColor(Color("Text"))
                    .lineLimit(1)

                Text(credential.displayUsername)
                    .font(.system(size: 11))
                    .foregroundColor(Color("TextMuted"))
                    .lineLimit(1)
            }

            Spacer()

            Text(revealedPassword ?? Self.maskedPassword)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color("TextMuted"))
                .lineLimit(1)
                .textSelection(.enabled)

            if isHovering {
                Button(action: onToggleReveal) {
                    Image(systemName: revealedPassword == nil ? "eye" : "eye.slash")
                        .font(.system(size: 12))
                        .foregroundColor(Color("TextMuted"))
                }
                .buttonStyle(.plain)
                .help(revealedPassword == nil ? "Show password" : "Hide password")

                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(Color("TextMuted"))
                }
                .buttonStyle(.plain)
                .help("Copy password")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(isHovering ? Color("CardBg") : Color.clear)
        .cornerRadius(6)
        .onHover { isHovering = $0 }
    }
}
