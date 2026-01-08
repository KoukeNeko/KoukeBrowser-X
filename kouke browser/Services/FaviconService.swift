//
//  FaviconService.swift
//  kouke browser
//
//  Service to fetch website favicons with apple-touch-icon priority.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class FaviconService: ObservableObject {
    static let shared = FaviconService()

    // Cache structure: domain -> (URL, isAppleTouchIcon)
    private var urlCache: [String: URL] = [:]
    private var checkingDomains: Set<String> = []

    private init() {}

    /// Get the best favicon URL for a given URL string
    /// Prefers apple-touch-icon over Google's favicon service
    func faviconURL(for urlString: String) -> URL? {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return nil
        }

        // Return cached URL if available
        if let cachedURL = urlCache[host] {
            return cachedURL
        }

        // Return Google favicon as initial fallback, but trigger async check
        let googleFavicon = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128")
        
        // Start async check for apple-touch-icon if not already checking
        if !checkingDomains.contains(host) {
            checkingDomains.insert(host)
            Task {
                await checkAppleTouchIcon(for: host)
            }
        }

        return googleFavicon
    }

    /// Get the best favicon URL for a URL object
    func faviconURL(for url: URL?) -> URL? {
        guard let url = url else { return nil }
        return faviconURL(for: url.absoluteString)
    }

    /// Async method to check for apple-touch-icon
    /// Returns the best available icon URL
    func bestFaviconURL(for urlString: String) async -> URL? {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return nil
        }

        // Return cached URL if available
        if let cachedURL = urlCache[host] {
            return cachedURL
        }

        // Try apple-touch-icon first
        if let appleTouchIcon = await fetchAppleTouchIconURL(for: host) {
            urlCache[host] = appleTouchIcon
            return appleTouchIcon
        }

        // Fallback to Google's favicon service
        let googleFavicon = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128")
        if let favicon = googleFavicon {
            urlCache[host] = favicon
        }
        return googleFavicon
    }

    /// Check for apple-touch-icon and update cache
    private func checkAppleTouchIcon(for host: String) async {
        if let appleTouchIcon = await fetchAppleTouchIconURL(for: host) {
            urlCache[host] = appleTouchIcon
            objectWillChange.send()
        } else {
            // Cache the Google fallback
            if let googleFavicon = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128") {
                urlCache[host] = googleFavicon
            }
        }
        checkingDomains.remove(host)
    }

    /// Fetch apple-touch-icon URL by parsing HTML link tags for the largest icon
    private func fetchAppleTouchIconURL(for host: String) async -> URL? {
        // First, try to parse HTML to find apple-touch-icon links
        if let iconFromHTML = await parseHTMLForAppleTouchIcon(host: host) {
            return iconFromHTML
        }

        // Fallback: check common static paths
        return await checkStaticAppleTouchIconPaths(for: host)
    }

    /// Parse HTML to find apple-touch-icon link tags and return the largest icon
    private func parseHTMLForAppleTouchIcon(host: String) async -> URL? {
        guard let pageURL = URL(string: "https://\(host)") else { return nil }

        var request = URLRequest(url: pageURL)
        request.timeoutInterval = 5
        // Only fetch the head section if possible, but GET is safer for HTML
        request.httpMethod = "GET"
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else {
                return nil
            }

            // Parse apple-touch-icon links from HTML
            let icons = parseAppleTouchIconLinks(from: html, baseHost: host)

            // Return the largest icon
            if let largestIcon = icons.max(by: { $0.size < $1.size }) {
                return largestIcon.url
            }
        } catch {
            // Continue to fallback
        }

        return nil
    }

    /// Structure to hold parsed icon info
    private struct IconInfo {
        let url: URL
        let size: Int
    }

    /// Parse HTML string to extract apple-touch-icon links with their sizes
    private func parseAppleTouchIconLinks(from html: String, baseHost: String) -> [IconInfo] {
        var icons: [IconInfo] = []

        // Regex to match <link rel="apple-touch-icon" ... href="..." sizes="...">
        // This handles various attribute orders
        let linkPattern = #"<link[^>]*rel\s*=\s*[\"']apple-touch-icon(?:-precomposed)?[\"'][^>]*>"#

        guard let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: .caseInsensitive) else {
            return icons
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = linkRegex.matches(in: html, options: [], range: range)

        for match in matches {
            guard let matchRange = Range(match.range, in: html) else { continue }
            let linkTag = String(html[matchRange])

            // Extract href
            guard let href = extractAttribute(named: "href", from: linkTag) else { continue }

            // Resolve URL (handle relative URLs)
            let iconURL: URL?
            if href.hasPrefix("http://") || href.hasPrefix("https://") {
                iconURL = URL(string: href)
            } else if href.hasPrefix("//") {
                iconURL = URL(string: "https:" + href)
            } else if href.hasPrefix("/") {
                iconURL = URL(string: "https://\(baseHost)\(href)")
            } else {
                iconURL = URL(string: "https://\(baseHost)/\(href)")
            }

            guard let resolvedURL = iconURL else { continue }

            // Extract size (default to 57 if not specified, which is the default apple-touch-icon size)
            var size = 57
            if let sizesAttr = extractAttribute(named: "sizes", from: linkTag) {
                // Parse "180x180" format
                let sizeComponents = sizesAttr.lowercased().split(separator: "x")
                if let firstSize = sizeComponents.first, let parsedSize = Int(firstSize) {
                    size = parsedSize
                }
            }

            icons.append(IconInfo(url: resolvedURL, size: size))
        }

        return icons
    }

    /// Extract an attribute value from a tag string
    private func extractAttribute(named name: String, from tag: String) -> String? {
        // Match both single and double quotes
        let pattern = "\(name)\\s*=\\s*[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match = regex.firstMatch(in: tag, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: tag) else {
            return nil
        }

        return String(tag[valueRange])
    }

    /// Check common static apple-touch-icon paths as fallback
    private func checkStaticAppleTouchIconPaths(for host: String) async -> URL? {
        let appleTouchIconPaths = [
            "https://\(host)/apple-touch-icon.png",
            "https://\(host)/apple-touch-icon-precomposed.png",
            "https://\(host)/apple-touch-icon-180x180.png",
            "https://\(host)/apple-touch-icon-152x152.png"
        ]

        for path in appleTouchIconPaths {
            guard let iconURL = URL(string: path) else { continue }

            var request = URLRequest(url: iconURL)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 3
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
                       contentType.contains("image") {
                        return iconURL
                    }
                }
            } catch {
                continue
            }
        }

        return nil
    }

    /// Clear the cache
    func clearCache() {
        urlCache.removeAll()
        checkingDomains.removeAll()
    }

    /// Get cached URL for a domain (if available)
    func cachedURL(for host: String) -> URL? {
        return urlCache[host]
    }
}

// MARK: - AsyncFaviconImage View

/// A SwiftUI view that displays favicon with apple-touch-icon priority
struct AsyncFaviconImage: View {
    let urlString: String
    var size: CGFloat = 16
    @ObservedObject private var faviconService = FaviconService.shared
    @State private var faviconURL: URL?

    var body: some View {
        AsyncImage(url: faviconURL) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .scaleEffect(0.5)
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .failure:
                Image(systemName: "globe")
                    .foregroundColor(Color("TextMuted"))
            @unknown default:
                Image(systemName: "globe")
                    .foregroundColor(Color("TextMuted"))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size / 4))
        .onAppear {
            faviconURL = faviconService.faviconURL(for: urlString)
        }
        .onReceive(faviconService.objectWillChange) { _ in
            // Update when cache changes
            if let url = URL(string: urlString),
               let host = url.host,
               let cachedURL = faviconService.cachedURL(for: host) {
                faviconURL = cachedURL
            }
        }
    }
}

// MARK: - URL Extension for Favicon

extension URL {
    /// Get the best favicon URL for this URL
    var faviconURL: URL? {
        FaviconService.shared.faviconURL(for: self)
    }
}
