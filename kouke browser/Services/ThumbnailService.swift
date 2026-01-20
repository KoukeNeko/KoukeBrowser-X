//
//  ThumbnailService.swift
//  kouke browser
//
//  Service for capturing and managing page thumbnails.
//

import Foundation
import WebKit
#if os(macOS)
import AppKit
#endif

@MainActor
class ThumbnailService {
    static let shared = ThumbnailService()

    private let thumbnailDirectory: URL
    private let maxThumbnails = 50
    private let thumbnailWidth: CGFloat = 400  // Good balance of quality/size
    private let jpegQuality: CGFloat = 0.7

    private init() {
        // Setup thumbnails directory in Application Support
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        thumbnailDirectory = appSupport
            .appendingPathComponent("Kouke", isDirectory: true)
            .appendingPathComponent("Thumbnails", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: thumbnailDirectory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Public API

    /// Capture thumbnail from WKWebView and save to disk
    func captureThumbnail(
        for webView: WKWebView,
        url: String,
        completion: @escaping (String?) -> Void
    ) {
        // Skip special pages
        guard !url.hasPrefix("kouke:"),
              !url.hasPrefix("about:"),
              let urlObj = URL(string: url),
              urlObj.host != nil else {
            completion(nil)
            return
        }

        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: Double(thumbnailWidth))

        webView.takeSnapshot(with: config) { [weak self] image, error in
            guard let self = self,
                  let image = image,
                  error == nil else {
                completion(nil)
                return
            }

            Task { @MainActor in
                let filename = self.generateFilename(for: url)
                let savedPath = self.saveThumbnail(image, filename: filename)
                completion(savedPath)
            }
        }
    }

    /// Load thumbnail image from path
    func loadThumbnail(path: String) -> NSImage? {
        let fullPath = thumbnailDirectory.appendingPathComponent(path)
        return NSImage(contentsOf: fullPath)
    }

    /// Clean up old thumbnails beyond limit
    func cleanupOldThumbnails(keeping validPaths: Set<String>) {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: thumbnailDirectory,
                includingPropertiesForKeys: [.creationDateKey]
            )

            for file in files {
                let relativePath = file.lastPathComponent
                if !validPaths.contains(relativePath) {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        } catch {
            NSLog("ThumbnailService: Failed to cleanup thumbnails: \(error)")
        }
    }

    /// Delete a specific thumbnail
    func deleteThumbnail(path: String) {
        let fullPath = thumbnailDirectory.appendingPathComponent(path)
        try? FileManager.default.removeItem(at: fullPath)
    }

    // MARK: - Private Methods

    private func generateFilename(for url: String) -> String {
        // Create deterministic filename from URL hash
        let hash = url.data(using: .utf8)?.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .prefix(32) ?? "unknown"
        return "\(hash).jpg"
    }

    private func saveThumbnail(_ image: NSImage, filename: String) -> String? {
        let destinationURL = thumbnailDirectory.appendingPathComponent(filename)

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(
                  using: .jpeg,
                  properties: [.compressionFactor: jpegQuality]
              ) else {
            return nil
        }

        do {
            try jpegData.write(to: destinationURL)
            return filename
        } catch {
            NSLog("ThumbnailService: Failed to save thumbnail: \(error)")
            return nil
        }
    }
}
