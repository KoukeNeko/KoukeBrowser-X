//
//  SourcePageView.swift
//  kouke browser
//
//  View for displaying page source code with syntax highlighting.
//

import SwiftUI

struct SourcePageView: View {
    let sourceContent: String
    let sourceURL: String

    @State private var searchText = ""
    @State private var fontSize: CGFloat = 12

    private var displayContent: AttributedString {
        var attributed = AttributedString(sourceContent)
        attributed.font = .system(size: fontSize, design: .monospaced)
        attributed.foregroundColor = Color("Text")
        return attributed
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with URL and controls
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(Color("TextMuted"))

                Text("Source: \(sourceURL)")
                    .font(.system(size: 13))
                    .foregroundColor(Color("TextMuted"))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // Font size controls
                HStack(spacing: 4) {
                    Button(action: { fontSize = max(8, fontSize - 1) }) {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color("TextMuted"))

                    Text("\(Int(fontSize))pt")
                        .font(.system(size: 11))
                        .foregroundColor(Color("TextMuted"))
                        .frame(width: 30)

                    Button(action: { fontSize = min(24, fontSize + 1) }) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color("TextMuted"))
                }
                .padding(.horizontal, 8)

                // Copy button
                Button(action: copySource) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(Color("TextMuted"))
                .help("Copy Source")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color("CardBg"))

            Divider()

            // Source code view with line numbers
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 0) {
                    // Line numbers
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(sourceLines.enumerated()), id: \.offset) { index, _ in
                            Text("\(index + 1)")
                                .font(.system(size: fontSize, design: .monospaced))
                                .foregroundColor(Color("TextMuted").opacity(0.5))
                                .frame(minWidth: lineNumberWidth, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 8)
                    .background(Color("CardBg").opacity(0.5))

                    Divider()

                    // Source code
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sourceLines.enumerated()), id: \.offset) { _, line in
                            Text(highlightHTML(line))
                                .font(.system(size: fontSize, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }
            .background(Color("Bg"))
        }
        .background(Color("Bg"))
    }

    private var sourceLines: [String] {
        sourceContent.components(separatedBy: "\n")
    }

    private var lineNumberWidth: CGFloat {
        let digits = String(sourceLines.count).count
        return CGFloat(digits) * fontSize * 0.6 + 8
    }

    private func copySource() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sourceContent, forType: .string)
        #endif
    }

    /// Basic HTML syntax highlighting
    private func highlightHTML(_ line: String) -> AttributedString {
        var result = AttributedString(line)
        result.foregroundColor = Color("Text")

        // Highlight HTML tags
        let tagPattern = "<[^>]+>"
        if let regex = try? NSRegularExpression(pattern: tagPattern, options: []) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = regex.matches(in: line, options: [], range: range)

            for match in matches.reversed() {
                if let swiftRange = Range(match.range, in: line) {
                    let startIdx = result.index(result.startIndex, offsetByCharacters: line.distance(from: line.startIndex, to: swiftRange.lowerBound))
                    let endIdx = result.index(result.startIndex, offsetByCharacters: line.distance(from: line.startIndex, to: swiftRange.upperBound))
                    result[startIdx..<endIdx].foregroundColor = Color.blue.opacity(0.8)
                }
            }
        }

        // Highlight attributes
        let attrPattern = "\\s([a-zA-Z-]+)="
        if let regex = try? NSRegularExpression(pattern: attrPattern, options: []) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = regex.matches(in: line, options: [], range: range)

            for match in matches.reversed() {
                if match.numberOfRanges > 1,
                   let swiftRange = Range(match.range(at: 1), in: line) {
                    let startIdx = result.index(result.startIndex, offsetByCharacters: line.distance(from: line.startIndex, to: swiftRange.lowerBound))
                    let endIdx = result.index(result.startIndex, offsetByCharacters: line.distance(from: line.startIndex, to: swiftRange.upperBound))
                    result[startIdx..<endIdx].foregroundColor = Color.orange.opacity(0.9)
                }
            }
        }

        // Highlight strings
        let stringPattern = "\"[^\"]*\""
        if let regex = try? NSRegularExpression(pattern: stringPattern, options: []) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = regex.matches(in: line, options: [], range: range)

            for match in matches.reversed() {
                if let swiftRange = Range(match.range, in: line) {
                    let startIdx = result.index(result.startIndex, offsetByCharacters: line.distance(from: line.startIndex, to: swiftRange.lowerBound))
                    let endIdx = result.index(result.startIndex, offsetByCharacters: line.distance(from: line.startIndex, to: swiftRange.upperBound))
                    result[startIdx..<endIdx].foregroundColor = Color.green.opacity(0.8)
                }
            }
        }

        return result
    }
}

#Preview {
    SourcePageView(
        sourceContent: """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <title>Example Page</title>
        </head>
        <body>
            <h1>Hello World</h1>
            <p class="content">This is a test paragraph.</p>
        </body>
        </html>
        """,
        sourceURL: "https://example.com"
    )
    .frame(width: 800, height: 600)
}
