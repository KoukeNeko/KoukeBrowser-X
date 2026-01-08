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
}
