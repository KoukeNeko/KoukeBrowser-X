//
//  DownloadItem.swift
//  kouke browser
//
//  Model for storing download entries.
//

import Foundation

enum DownloadStatus: String, Codable {
    case pending
    case downloading
    case completed
    case failed
    case cancelled
}

struct DownloadItem: Identifiable, Codable, Equatable {
    let id: UUID
    var filename: String
    var url: String
    var localPath: String?
    var fileSize: Int64?
    var downloadedSize: Int64
    var status: DownloadStatus
    var startedAt: Date
    var completedAt: Date?
    var errorMessage: String?

    // Speed tracking (not persisted)
    var bytesPerSecond: Double = 0
    var lastUpdateTime: Date?
    var lastDownloadedSize: Int64 = 0

    // Custom coding keys to exclude speed tracking from persistence
    enum CodingKeys: String, CodingKey {
        case id, filename, url, localPath, fileSize, downloadedSize
        case status, startedAt, completedAt, errorMessage
    }

    init(
        id: UUID = UUID(),
        filename: String,
        url: String,
        localPath: String? = nil,
        fileSize: Int64? = nil,
        downloadedSize: Int64 = 0,
        status: DownloadStatus = .pending,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.url = url
        self.localPath = localPath
        self.fileSize = fileSize
        self.downloadedSize = downloadedSize
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
    }

    /// Progress as a percentage (0.0 - 1.0)
    var progress: Double {
        guard let total = fileSize, total > 0 else { return 0 }
        return Double(downloadedSize) / Double(total)
    }

    /// Human-readable file size
    var formattedFileSize: String? {
        guard let size = fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Human-readable downloaded size
    var formattedDownloadedSize: String {
        ByteCountFormatter.string(fromByteCount: downloadedSize, countStyle: .file)
    }

    /// File extension for icon display
    var fileExtension: String {
        (filename as NSString).pathExtension.lowercased()
    }

    /// Get domain from URL
    var domain: String? {
        guard let urlObj = URL(string: url) else { return nil }
        return urlObj.host
    }

    /// Check if the file exists at local path
    var fileExists: Bool {
        guard let path = localPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    /// Human-readable download speed
    var formattedSpeed: String? {
        guard bytesPerSecond > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }

    /// Estimated time remaining
    var estimatedTimeRemaining: TimeInterval? {
        guard bytesPerSecond > 0,
              let total = fileSize,
              total > downloadedSize else { return nil }
        let remaining = Double(total - downloadedSize)
        return remaining / bytesPerSecond
    }

    /// Human-readable time remaining
    var formattedTimeRemaining: String? {
        guard let seconds = estimatedTimeRemaining else { return nil }

        if seconds < 60 {
            return "\(Int(seconds))s remaining"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(secs)s remaining"
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m remaining"
        }
    }
}
