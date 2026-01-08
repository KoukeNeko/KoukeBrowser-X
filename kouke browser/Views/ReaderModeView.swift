//
//  ReaderModeView.swift
//  kouke browser
//
//  Clean reading view for article content.
//

import SwiftUI

struct ReaderModeView: View {
    let article: ReaderArticle
    let originalURL: String
    let onClose: () -> Void

    @ObservedObject private var settings = BrowserSettings.shared
    @State private var fontSize: CGFloat = 20
    @State private var fontFamily: ReaderFontFamily = .system
    @State private var theme: ReaderTheme = .dark
    @State private var showAppearancePopover: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Reader toolbar
            readerToolbar
                .zIndex(1)

            // Article content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Article header
                    articleHeader

                    Divider()
                        .overlay(theme.secondaryColor.opacity(0.3))
                        .padding(.vertical, 8)

                    // Article body
                    articleBody
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 40)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .background(theme.backgroundColor)
        .overlay(
            Rectangle()
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Reader Toolbar

    private var readerToolbar: some View {
        HStack(spacing: 16) {
            // Close button
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                    Text("Back")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(theme.secondaryColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(article.siteName ?? "Reader View")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.secondaryColor)

            Spacer()

            // Appearance Menu
            Button(action: { showAppearancePopover.toggle() }) {
                Image(systemName: "textformat.size")
                    .font(.system(size: 16))
                    .foregroundColor(theme.secondaryColor)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAppearancePopover, arrowEdge: .bottom) {
                appearanceControls
                    .padding()
                    .frame(width: 300)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(theme.backgroundColor.opacity(0.95))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(theme.secondaryColor.opacity(0.1)),
            alignment: .bottom
        )
    }

    private var appearanceControls: some View {
        VStack(spacing: 20) {
            // Theme Selector
            HStack(spacing: 12) {
                ForEach(ReaderTheme.allCases, id: \.self) { t in
                    Circle()
                        .fill(t.backgroundColor)
                        .overlay(
                            Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(t.textColor)
                                .opacity(theme == t ? 1 : 0)
                        )
                        .frame(width: 32, height: 32)
                        .onTapGesture {
                            theme = t
                        }
                }
            }

            Divider()

            // Font Size
            HStack {
                Button(action: { fontSize = max(14, fontSize - 2) }) {
                    Image(systemName: "textformat.size.smaller")
                        .frame(maxWidth: .infinity)
                }

                Divider().frame(height: 20)

                Button(action: { fontSize = min(36, fontSize + 2) }) {
                    Image(systemName: "textformat.size.larger")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.plain)
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

            // Font Family
            Picker("", selection: $fontFamily) {
                ForEach(ReaderFontFamily.allCases, id: \.self) { family in
                    Text(family.displayName).tag(family)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Article Header

    private var articleHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Site name & Date
            HStack {
                if let siteName = article.siteName {
                    Text(siteName.uppercased())
                        .fontWeight(.bold)
                }

                if article.siteName != nil && article.publishedDate != nil {
                    Text("•")
                }

                if let date = article.publishedDate {
                    Text(formatDate(date))
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(theme.accentColor)
            .kerning(0.5)

            // Title
            Text(article.title)
                .font(.custom(fontFamily.fontName, size: fontSize * 1.6))
                .fontWeight(.bold)
                .foregroundColor(theme.textColor)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

            // Byline & Read time
            HStack(spacing: 16) {
                if let byline = article.byline {
                    Label(byline, systemImage: "person.fill")
                }

                Label("\(article.estimatedReadTime) min read", systemImage: "clock.fill")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(theme.secondaryColor)
        }
    }

    // MARK: - Article Body

    private var articleBody: some View {
        // Use AttributedString for styled HTML content
        Text(AttributedString(htmlContent: article.content, fontSize: fontSize, fontFamily: fontFamily, theme: theme) ?? AttributedString(article.textContent))
            .font(.custom(fontFamily.fontName, size: fontSize))
            .foregroundColor(theme.textColor)
            .lineSpacing(fontSize * 0.4) // Native SwiftUI line spacing add-on
            .textSelection(.enabled)
    }

    // MARK: - Helpers

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            return displayFormatter.string(from: date)
        }
        return dateString.components(separatedBy: "T").first ?? dateString
    }
}

// MARK: - Reader Theme

enum ReaderTheme: String, CaseIterable {
    case light
    case paper
    case dark
    case black

    var backgroundColor: Color {
        switch self {
        case .light: return Color.white
        case .paper: return Color(red: 0.96, green: 0.93, blue: 0.88)
        case .dark: return Color(red: 0.18, green: 0.18, blue: 0.18)
        case .black: return Color.black
        }
    }

    var textColor: Color {
        switch self {
        case .light: return Color(red: 0.1, green: 0.1, blue: 0.1)
        case .paper: return Color(red: 0.25, green: 0.2, blue: 0.15)
        case .dark: return Color(red: 0.9, green: 0.9, blue: 0.9)
        case .black: return Color(red: 0.8, green: 0.8, blue: 0.8)
        }
    }

    var secondaryColor: Color {
        switch self {
        case .light: return Color.gray
        case .paper: return Color(red: 0.5, green: 0.45, blue: 0.4)
        case .dark: return Color.gray
        case .black: return Color.gray
        }
    }

    var accentColor: Color {
        switch self {
        case .light, .paper: return Color.orange
        case .dark, .black: return Color.orange.opacity(0.8)
        }
    }

    // CSS Hex codes
    var cssHexBackground: String {
        switch self {
        case .light: return "#ffffff"
        case .paper: return "#f5ecd4"
        case .dark: return "#2d2d2d"
        case .black: return "#000000"
        }
    }

    var cssHexText: String {
        switch self {
        case .light: return "#333333"
        case .paper: return "#4a4a4a"
        case .dark: return "#e0e0e0"
        case .black: return "#c0c0c0"
        }
    }

    var cssHexLink: String {
        switch self {
        case .light, .paper: return "#d35400"
        case .dark, .black: return "#e67e22"
        }
    }

    var cssHexBlockquoteBorder: String {
        switch self {
        case .light, .paper: return "#e5e5e5"
        case .dark, .black: return "#404040"
        }
    }

    var cssHexCodeBackground: String {
        switch self {
        case .light: return "#f5f5f5"
        case .paper: return "#eaddc5"
        case .dark: return "#383838"
        case .black: return "#1a1a1a"
        }
    }
}

// MARK: - Reader Font Family

enum ReaderFontFamily: String, CaseIterable {
    case system = "System"
    case serif = "Serif"
    case sansSerif = "Sans"

    var displayName: String { rawValue }

    var fontName: String {
        switch self {
        case .system: return ".AppleSystemUIFont"
        case .serif: return "Charter" // Better serif for reading
        case .sansSerif: return "Avenir Next" // Better sans
        }
    }

    var cssFontFamily: String {
        switch self {
        case .system: return "-apple-system, BlinkMacSystemFont, sans-serif"
        case .serif: return "Charter, Georgia, Cambria, Times New Roman, serif"
        case .sansSerif: return "'Avenir Next', 'Helvetica Neue', Arial, sans-serif"
        }
    }
}

// MARK: - AttributedString HTML Extension

extension AttributedString {
    init?(htmlContent: String, fontSize: CGFloat, fontFamily: ReaderFontFamily, theme: ReaderTheme) {
        let styledHTML = """
        <html>
        <head>
        <style>
            body {
                font-family: \(fontFamily.cssFontFamily);
                font-size: \(fontSize)px;
                line-height: 1.6;
                color: \(theme.cssHexText);
                background-color: \(theme.cssHexBackground);
                margin: 0;
                padding: 0;
            }
            h1, h2, h3, h4, h5, h6 {
                font-weight: 700;
                margin-top: 1.5em;
                margin-bottom: 0.5em;
                line-height: 1.3;
            }
            h1 { font-size: 1.8em; }
            h2 { font-size: 1.5em; border-bottom: 1px solid \(theme.cssHexBlockquoteBorder); padding-bottom: 0.3em; }
            h3 { font-size: 1.3em; }

            p { margin-bottom: 1.2em; }

            img {
                max-width: 100%;
                height: auto;
                border-radius: 8px;
                margin: 1.5em auto;
                display: block;
                box-shadow: 0 4px 12px rgba(0,0,0,0.1);
            }

            figure { margin: 2em 0; text-align: center; }
            figcaption {
                font-size: 0.85em;
                color: \(theme.cssHexText);
                opacity: 0.7;
                margin-top: 0.5em;
            }

            a { color: \(theme.cssHexLink); text-decoration: none; border-bottom: 1px dotted; }
            a:hover { border-bottom: 1px solid; }

            blockquote {
                border-left: 4px solid \(theme.cssHexBlockquoteBorder);
                margin: 1.5em 0;
                padding: 0.5em 0 0.5em 1.2em;
                font-style: italic;
                opacity: 0.9;
            }

            ul, ol { margin: 1.5em 0; padding-left: 1.5em; }
            li { margin-bottom: 0.5em; }

            pre, code {
                font-family: 'Menlo', 'Monaco', 'Courier New', monospace;
                font-size: 0.9em;
                background-color: \(theme.cssHexCodeBackground);
                border-radius: 4px;
            }
            code { padding: 0.2em 0.4em; }
            pre {
                padding: 1em;
                overflow-x: auto;
                border: 1px solid \(theme.cssHexBlockquoteBorder);
            }

            hr { border: 0; height: 1px; background: \(theme.cssHexBlockquoteBorder); margin: 2em 0; }
        </style>
        </head>
        <body>\(htmlContent)</body>
        </html>
        """

        guard let data = styledHTML.data(using: .utf8),
              let nsAttrString = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return nil
        }

        self.init(nsAttrString)
    }
}

#Preview {
    ReaderModeView(
        article: ReaderArticle(
            title: "The Art of Simplicity in Software Design",
            byline: "Jane Architect",
            content: """
            <p>Complexity is the enemy of execution. In software, this manifests as <strong>spaghetti code</strong>, tightly coupled modules, and opaque logic.</p>
            <h2>Why Simplicity Matters</h2>
            <p>Simple systems are easier to maintain, easier to test, and easier to reason about.</p>
            <blockquote>"Simplicity is the ultimate sophistication." - Leonardo da Vinci</blockquote>
            <p>When we prioritize simplicity, we are not being lazy; we are being strategic.</p>
            <ul>
                <li>Readability counts.</li>
                <li>Less code is often better code.</li>
            </ul>
            """,
            textContent: "Preview Content",
            siteName: "Tech Daily",
            publishedDate: "2024-03-10T14:30:00Z",
            estimatedReadTime: 6
        ),
        originalURL: "https://example.com",
        onClose: {}
    )
    .frame(width: 800, height: 700)
}
