//
//  DownloadManager.swift
//  kouke browser
//
//  Manages file downloads storage and operations.
//

import Foundation
import Combine
import AppKit

@MainActor
class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var downloadItems: [DownloadItem] = []
    @Published private(set) var activeDownloads: [UUID: URLSessionDownloadTask] = [:]

    private let downloadsKey = "downloadHistory"
    private let defaults = UserDefaults.standard
    private let maxDownloadItems = 1000

    private var downloadSessions: [UUID: URLSession] = [:]
    private var downloadDelegates: [UUID: DownloadDelegate] = [:]

    private init() {
        loadDownloads()
        cleanupOldDownloads()
    }

    // MARK: - Download Operations

    /// Track a download started by WKDownload (does not start a new download)
    func trackDownload(url: URL, suggestedFilename: String?, destinationPath: String?, expectedSize: Int64? = nil) -> UUID {
        let filename = suggestedFilename ?? url.lastPathComponent
        let item = DownloadItem(
            filename: filename,
            url: url.absoluteString,
            localPath: destinationPath,
            fileSize: expectedSize,
            status: .downloading
        )

        downloadItems.insert(item, at: 0)
        saveDownloads()

        return item.id
    }

    /// Start a new download using URLSession (for retry functionality)
    func startDownload(url: URL, suggestedFilename: String?) -> UUID {
        let filename = suggestedFilename ?? url.lastPathComponent
        let item = DownloadItem(
            filename: filename,
            url: url.absoluteString,
            status: .downloading
        )

        downloadItems.insert(item, at: 0)
        saveDownloads()

        // Create download task
        let delegate = DownloadDelegate(downloadId: item.id, manager: self)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: .main)

        downloadDelegates[item.id] = delegate
        downloadSessions[item.id] = session

        let task = session.downloadTask(with: url)
        activeDownloads[item.id] = task
        task.resume()

        return item.id
    }

    /// Cancel a download
    func cancelDownload(_ id: UUID) {
        if let task = activeDownloads[id] {
            task.cancel()
            activeDownloads.removeValue(forKey: id)
        }

        if let index = downloadItems.firstIndex(where: { $0.id == id }) {
            downloadItems[index].status = .cancelled
            saveDownloads()
        }

        cleanupSession(for: id)
    }

    /// Remove a download from the list
    func removeDownload(_ id: UUID) {
        cancelDownload(id)
        downloadItems.removeAll { $0.id == id }
        saveDownloads()
    }

    /// Clear all completed downloads
    func clearCompletedDownloads() {
        downloadItems.removeAll { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
        saveDownloads()
    }

    /// Clear all downloads
    func clearAllDownloads() {
        // Cancel active downloads first
        for id in activeDownloads.keys {
            cancelDownload(id)
        }
        downloadItems.removeAll()
        saveDownloads()
    }

    /// Open downloaded file
    func openDownloadedFile(_ id: UUID) {
        guard let item = downloadItems.first(where: { $0.id == id }),
              let path = item.localPath,
              item.fileExists else {
            return
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Show downloaded file in Finder
    func showInFinder(_ id: UUID) {
        guard let item = downloadItems.first(where: { $0.id == id }),
              let path = item.localPath,
              item.fileExists else {
            return
        }

        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    /// Retry a failed download
    func retryDownload(_ id: UUID) {
        guard let item = downloadItems.first(where: { $0.id == id }),
              let url = URL(string: item.url) else {
            return
        }

        // Remove old item and start fresh
        removeDownload(id)
        _ = startDownload(url: url, suggestedFilename: item.filename)
    }

    // MARK: - Internal Update Methods

    // Throttle interval for UI updates (in seconds)
    private static let updateThrottleInterval: TimeInterval = 0.1  // 100ms

    func updateProgress(for id: UUID, downloadedSize: Int64, totalSize: Int64?) {
        guard let index = downloadItems.firstIndex(where: { $0.id == id }) else { return }

        let now = Date()
        let item = downloadItems[index]

        // Throttle updates to avoid UI lag - only update every 100ms
        // But always update if this is the first update (lastUpdateTime is nil)
        if let lastTime = item.lastUpdateTime {
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed < Self.updateThrottleInterval {
                // Skip this update, too soon
                return
            }

            // Calculate speed
            let bytesDiff = downloadedSize - item.lastDownloadedSize
            let instantSpeed = Double(bytesDiff) / elapsed

            // Smooth the speed with exponential moving average
            let alpha = 0.3
            if item.bytesPerSecond > 0 {
                downloadItems[index].bytesPerSecond = alpha * instantSpeed + (1 - alpha) * item.bytesPerSecond
            } else {
                downloadItems[index].bytesPerSecond = instantSpeed
            }
        }

        // Update progress data
        downloadItems[index].lastUpdateTime = now
        downloadItems[index].lastDownloadedSize = downloadedSize
        downloadItems[index].downloadedSize = downloadedSize
        if let total = totalSize {
            downloadItems[index].fileSize = total
        }
    }

    /// Complete a WKDownload (file already at destination)
    func completeWKDownload(for id: UUID) {
        guard let index = downloadItems.firstIndex(where: { $0.id == id }) else { return }

        downloadItems[index].status = .completed
        downloadItems[index].completedAt = Date()

        // Get actual file size from destination
        if let path = downloadItems[index].localPath,
           let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attributes[.size] as? Int64 {
            downloadItems[index].fileSize = size
            downloadItems[index].downloadedSize = size
        }

        saveDownloads()

        // Open safe files if setting enabled
        if BrowserSettings.shared.openSafeFilesAfterDownload && isSafeFile(downloadItems[index].filename) {
            openDownloadedFile(id)
        }
    }

    /// Complete a URLSession download (needs to move file)
    func completeDownload(for id: UUID, localURL: URL) {
        guard let index = downloadItems.firstIndex(where: { $0.id == id }) else { return }

        // Move file to Downloads folder
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        var destinationURL = downloadsURL.appendingPathComponent(downloadItems[index].filename)

        // Handle duplicate filenames
        var counter = 1
        let originalName = (downloadItems[index].filename as NSString).deletingPathExtension
        let ext = (downloadItems[index].filename as NSString).pathExtension

        while FileManager.default.fileExists(atPath: destinationURL.path) {
            let newName = ext.isEmpty ? "\(originalName) (\(counter))" : "\(originalName) (\(counter)).\(ext)"
            destinationURL = downloadsURL.appendingPathComponent(newName)
            counter += 1
        }

        do {
            try FileManager.default.moveItem(at: localURL, to: destinationURL)

            downloadItems[index].localPath = destinationURL.path
            downloadItems[index].status = .completed
            downloadItems[index].completedAt = Date()

            // Get actual file size
            if let attributes = try? FileManager.default.attributesOfItem(atPath: destinationURL.path),
               let size = attributes[.size] as? Int64 {
                downloadItems[index].fileSize = size
                downloadItems[index].downloadedSize = size
            }

            saveDownloads()

            // Open safe files if setting enabled
            if BrowserSettings.shared.openSafeFilesAfterDownload && isSafeFile(downloadItems[index].filename) {
                openDownloadedFile(id)
            }
        } catch {
            downloadItems[index].status = .failed
            downloadItems[index].errorMessage = error.localizedDescription
            saveDownloads()
        }

        activeDownloads.removeValue(forKey: id)
        cleanupSession(for: id)
    }

    func failDownload(for id: UUID, error: Error) {
        guard let index = downloadItems.firstIndex(where: { $0.id == id }) else { return }

        downloadItems[index].status = .failed
        downloadItems[index].errorMessage = error.localizedDescription
        saveDownloads()

        activeDownloads.removeValue(forKey: id)
        cleanupSession(for: id)
    }

    // MARK: - Query Operations

    /// Get downloads for today
    func todayItems() -> [DownloadItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return downloadItems.filter { $0.startedAt >= today }
    }

    /// Get downloads for yesterday
    func yesterdayItems() -> [DownloadItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        return downloadItems.filter { $0.startedAt >= yesterday && $0.startedAt < today }
    }

    /// Get downloads older than today and yesterday
    func olderItems() -> [DownloadItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        return downloadItems.filter { $0.startedAt < yesterday }
    }

    /// Search downloads by filename or URL
    func searchDownloads(query: String) -> [DownloadItem] {
        guard !query.isEmpty else { return downloadItems }
        let lowercasedQuery = query.lowercased()
        return downloadItems.filter {
            $0.filename.lowercased().contains(lowercasedQuery) ||
            $0.url.lowercased().contains(lowercasedQuery)
        }
    }

    /// Group downloads by date for display
    func groupedByDate() -> [(title: String, items: [DownloadItem])] {
        var groups: [(title: String, items: [DownloadItem])] = []

        let today = todayItems()
        if !today.isEmpty {
            groups.append((title: "Today", items: today))
        }

        let yesterday = yesterdayItems()
        if !yesterday.isEmpty {
            groups.append((title: "Yesterday", items: yesterday))
        }

        let older = olderItems()
        if !older.isEmpty {
            groups.append((title: "Older", items: older))
        }

        return groups
    }

    // MARK: - Helper Methods

    private func isSafeFile(_ filename: String) -> Bool {
        let safeExtensions = ["pdf", "jpg", "jpeg", "png", "gif", "txt", "rtf", "mp3", "mp4", "mov", "zip"]
        let ext = (filename as NSString).pathExtension.lowercased()
        return safeExtensions.contains(ext)
    }

    private func cleanupSession(for id: UUID) {
        downloadSessions[id]?.invalidateAndCancel()
        downloadSessions.removeValue(forKey: id)
        downloadDelegates.removeValue(forKey: id)
    }

    private func cleanupOldDownloads() {
        let settings = BrowserSettings.shared

        switch settings.removeDownloadItems {
        case .afterOneDay:
            let oneDayAgo = Date().addingTimeInterval(-24 * 60 * 60)
            downloadItems.removeAll { item in
                (item.status == .completed || item.status == .failed || item.status == .cancelled) &&
                (item.completedAt ?? item.startedAt) < oneDayAgo
            }
        case .uponSuccessfulDownload:
            downloadItems.removeAll { $0.status == .completed }
        case .whenKoukeQuits, .manually:
            break
        }

        // Trim if exceeds max
        if downloadItems.count > maxDownloadItems {
            downloadItems = Array(downloadItems.prefix(maxDownloadItems))
        }

        saveDownloads()
    }

    // MARK: - Persistence

    private func saveDownloads() {
        if let data = try? JSONEncoder().encode(downloadItems) {
            defaults.set(data, forKey: downloadsKey)
        }
    }

    private func loadDownloads() {
        guard let data = defaults.data(forKey: downloadsKey),
              let loaded = try? JSONDecoder().decode([DownloadItem].self, from: data) else {
            return
        }

        // Reset any "downloading" items to "failed" since app was restarted
        downloadItems = loaded.map { item in
            var mutableItem = item
            if mutableItem.status == .downloading || mutableItem.status == .pending {
                mutableItem.status = .failed
                mutableItem.errorMessage = "Download interrupted"
            }
            return mutableItem
        }
    }
}

// MARK: - Download Delegate

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let downloadId: UUID
    weak var manager: DownloadManager?

    init(downloadId: UUID, manager: DownloadManager) {
        self.downloadId = downloadId
        self.manager = manager
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        Task { @MainActor in
            manager?.completeDownload(for: downloadId, localURL: location)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
            manager?.updateProgress(for: downloadId, downloadedSize: totalBytesWritten, totalSize: total)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error, (error as NSError).code != NSURLErrorCancelled {
            Task { @MainActor in
                manager?.failDownload(for: downloadId, error: error)
            }
        }
    }
}
