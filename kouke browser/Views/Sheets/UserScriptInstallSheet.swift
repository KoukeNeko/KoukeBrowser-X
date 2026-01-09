//
//  UserScriptInstallSheet.swift
//  kouke browser
//
//  Confirmation sheet for installing userscripts from URLs.
//

import SwiftUI

struct UserScriptInstallSheet: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Environment(\.dismiss) private var dismiss

    private var metadata: UserScriptManager.UserScriptMetadata? {
        viewModel.pendingUserScriptMetadata
    }

    private var scriptName: String {
        metadata?.name ?? viewModel.pendingUserScriptURL?.deletingPathExtension().lastPathComponent ?? "Unknown Script"
    }

    private var matchPatterns: [String] {
        let patterns = metadata?.match ?? []
        return patterns.isEmpty ? ["*://*/*"] : patterns
    }

    private var sourceURL: String {
        viewModel.pendingUserScriptURL?.absoluteString ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text.below.ecg")
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Install User Script")
                        .font(.system(size: 16, weight: .semibold))

                    Text(scriptName)
                        .font(.system(size: 13))
                        .foregroundColor(Color("TextMuted"))
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(20)
            .background(Color("CardBg"))

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Source URL
                    InfoSection(title: "Source") {
                        Text(sourceURL)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color("TextMuted"))
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }

                    // Match patterns
                    InfoSection(title: "Match Patterns") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(matchPatterns.prefix(5), id: \.self) { pattern in
                                HStack(spacing: 6) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 10))
                                        .foregroundColor(Color("TextMuted"))
                                    Text(pattern)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(Color("Text"))
                                }
                            }
                            if matchPatterns.count > 5 {
                                Text("... and \(matchPatterns.count - 5) more")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color("TextMuted"))
                            }
                        }
                    }

                    // Injection time
                    if let runAt = metadata?.runAt {
                        InfoSection(title: "Run At") {
                            Text(runAt.displayName)
                                .font(.system(size: 12))
                                .foregroundColor(Color("Text"))
                        }
                    }

                    // Warning
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 14))

                        Text("User scripts can access the content of web pages you visit. Only install scripts from sources you trust.")
                            .font(.system(size: 11))
                            .foregroundColor(Color("TextMuted"))
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(20)
            }
            .background(Color("Bg"))

            Divider()

            // Footer buttons
            HStack {
                Button("Cancel") {
                    viewModel.clearPendingUserScript()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Install") {
                    viewModel.installPendingUserScript()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(Color("CardBg"))
        }
        .frame(width: 420, height: 400)
    }
}

// MARK: - Info Section

private struct InfoSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color("TextMuted"))
                .textCase(.uppercase)

            content
        }
    }
}
