//
//  PIPWindow.swift
//  kouke browser
//
//  Picture-in-Picture manager using native AVPlayer.
//  Extracts video URL from webpage and plays in native PIP.
//

import SwiftUI
import WebKit
import AppKit
import AVKit
import Combine
import YouTubeKit

// MARK: - PIP Window Controller

class PIPWindowController: NSWindowController {
    private var playerView: AVPlayerView?
    private var player: AVPlayer?
    private var pipController: AVPictureInPictureController?
    private weak var sourceWebView: WKWebView?
    private var currentTime: Double = 0
    private var volume: Float = 1.0

    static var shared: PIPWindowController?

    convenience init(videoURL: URL, startTime: Double, volume: Float, sourceWebView: WKWebView?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 225),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.init(window: window)
        self.sourceWebView = sourceWebView
        self.currentTime = startTime
        self.volume = volume

        setupWindow()
        setupPlayer(with: videoURL, startTime: startTime, volume: volume)
    }

    private func setupWindow() {
        guard let window = window else { return }

        window.title = "Picture in Picture"
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black

        // Position at bottom-right
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 420
            let y = screenFrame.minY + 20
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.minSize = NSSize(width: 280, height: 158)
        window.aspectRatio = NSSize(width: 16, height: 9)
        window.delegate = self
    }

    private func setupPlayer(with url: URL, startTime: Double, volume: Float) {
        guard let window = window else { return }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        // Set volume to match source video
        player?.volume = volume

        playerView = AVPlayerView()
        playerView?.player = player
        playerView?.controlsStyle = .floating
        playerView?.frame = window.contentView?.bounds ?? .zero
        playerView?.autoresizingMask = [.width, .height]

        window.contentView?.addSubview(playerView!)

        // Seek to start time
        let time = CMTime(seconds: startTime, preferredTimescale: 600)
        player?.seek(to: time) { [weak self] _ in
            self?.player?.play()
        }

        // Pause original video (mute first to avoid audio overlap)
        muteAndPauseSourceVideo()

        // Setup native PIP if available
        if AVPictureInPictureController.isPictureInPictureSupported(),
           let playerLayer = playerView?.layer as? AVPlayerLayer {
            pipController = AVPictureInPictureController(playerLayer: playerLayer)
            pipController?.delegate = self
        }
    }

    private func muteAndPauseSourceVideo() {
        let script = """
        (function() {
            const video = document.querySelector('video');
            if (video) {
                video.muted = true;
                video.pause();
            }
        })();
        """
        sourceWebView?.evaluateJavaScript(script, completionHandler: nil)
    }

    private func resumeSourceVideo(at time: Double) {
        let script = """
        (function() {
            const video = document.querySelector('video');
            if (video) {
                video.muted = false;
                video.currentTime = \(time);
                video.play();
            }
        })();
        """
        sourceWebView?.evaluateJavaScript(script, completionHandler: nil)
    }

    func closePIP() {
        // Get current playback time and resume in webpage
        if let currentTime = player?.currentTime().seconds, currentTime.isFinite {
            resumeSourceVideo(at: currentTime)
        }

        player?.pause()
        player = nil
        pipController = nil
        window?.close()
        PIPWindowController.shared = nil

        Task { @MainActor in
            PIPManager.shared.isPIPActive = false
        }
    }

    static func show(videoURL: URL, startTime: Double, volume: Float, sourceWebView: WKWebView?) {
        shared?.closePIP()

        let controller = PIPWindowController(videoURL: videoURL, startTime: startTime, volume: volume, sourceWebView: sourceWebView)
        controller.showWindow(nil)
        shared = controller
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private override init(window: NSWindow?) {
        super.init(window: window)
    }
}

extension PIPWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Don't call closePIP here to avoid recursion, just cleanup
        if let currentTime = player?.currentTime().seconds, currentTime.isFinite {
            resumeSourceVideo(at: currentTime)
        }
        player?.pause()
        player = nil
        pipController = nil
        PIPWindowController.shared = nil
        Task { @MainActor in
            PIPManager.shared.isPIPActive = false
        }
    }
}

extension PIPWindowController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[PIP] Started native PIP")
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[PIP] Stopped native PIP")
    }
}

// MARK: - PIP Manager

@MainActor
class PIPManager: ObservableObject {
    static let shared = PIPManager()

    @Published var hasPlayingVideo = false
    @Published var isPIPActive = false

    private weak var currentWebView: WKWebView?

    private init() {}

    /// Check if there's a playing video in the webview
    func checkForPlayingVideo(in webView: WKWebView, completion: @escaping (Bool) -> Void) {
        let script = """
        (function() {
            const videos = document.querySelectorAll('video');
            for (const video of videos) {
                if (!video.paused || video.readyState >= 2 || video.currentTime > 0) {
                    return true;
                }
            }
            return false;
        })();
        """

        webView.evaluateJavaScript(script) { result, error in
            let hasVideo = (result as? Bool) ?? false
            DispatchQueue.main.async {
                completion(hasVideo)
            }
        }
    }

    /// Toggle PIP state
    func togglePIP(from webView: WKWebView, sourceTabId: UUID) {
        if isPIPActive {
            closePIP()
            return
        }

        currentWebView = webView

        // Extract video info from the page
        extractVideoInfo(from: webView)
    }

    private func extractVideoInfo(from webView: WKWebView) {
        let script = """
        (function() {
            const video = document.querySelector('video');
            if (!video) return null;

            const info = {
                currentTime: video.currentTime,
                duration: video.duration,
                paused: video.paused,
                volume: video.muted ? 0 : video.volume,
                width: video.videoWidth,
                height: video.videoHeight,
                isYouTube: window.location.hostname.includes('youtube.com')
            };

            // For YouTube, get the video ID
            if (info.isYouTube) {
                const urlParams = new URLSearchParams(window.location.search);
                info.videoId = urlParams.get('v');
            } else {
                // For non-YouTube sites, try to get direct URL
                let src = video.src || video.currentSrc;

                // Skip blob URLs
                if (src && !src.startsWith('blob:')) {
                    info.directUrl = src;
                }

                // Try source elements
                if (!info.directUrl) {
                    const source = video.querySelector('source');
                    if (source && source.src && !source.src.startsWith('blob:')) {
                        info.directUrl = source.src;
                    }
                }
            }

            return info;
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self = self else { return }

            print("[PIP] Video info: \(String(describing: result))")

            if let info = result as? [String: Any] {
                let currentTime = info["currentTime"] as? Double ?? 0
                let volume = Float(info["volume"] as? Double ?? 1.0)
                let isYouTube = info["isYouTube"] as? Bool ?? false

                // Handle YouTube videos with YouTubeKit
                if isYouTube, let videoId = info["videoId"] as? String {
                    print("[PIP] YouTube video detected, using YouTubeKit for videoId: \(videoId)")
                    Task {
                        await self.extractYouTubeStream(videoId: videoId, startTime: currentTime, volume: volume, webView: webView)
                    }
                    return
                }

                // Try direct URL for non-YouTube
                if let directUrl = info["directUrl"] as? String,
                   let url = URL(string: directUrl) {
                    print("[PIP] Using direct video URL")
                    DispatchQueue.main.async {
                        self.isPIPActive = true
                        PIPWindowController.show(videoURL: url, startTime: currentTime, volume: volume, sourceWebView: webView)
                    }
                    return
                }

                print("[PIP] Could not extract playable video URL")
            }

            // Reset state
            DispatchQueue.main.async {
                self.isPIPActive = false
            }
        }
    }

    /// Extract YouTube stream URL using YouTubeKit
    private func extractYouTubeStream(videoId: String, startTime: Double, volume: Float, webView: WKWebView) async {
        do {
            print("[PIP] Fetching streams for YouTube video: \(videoId)")

            // Use local method only for faster extraction (skip remote fallback initially)
            let youtube = YouTube(videoID: videoId, methods: [.local])
            let streams = try await youtube.streams

            print("[PIP] Found \(streams.count) streams")

            // Filter for natively playable streams with video and audio
            let playableStreams = streams
                .filterVideoAndAudio()
                .filter { $0.isNativelyPlayable }

            print("[PIP] Playable streams: \(playableStreams.count)")

            // Get highest resolution stream
            if let bestStream = playableStreams.highestResolutionStream() {
                let codecDescription = bestStream.videoCodec.map { String(describing: $0) } ?? "unknown"
                print("[PIP] Selected stream: \(codecDescription) \(bestStream.videoResolution ?? 0)p")

                await MainActor.run {
                    self.isPIPActive = true
                    PIPWindowController.show(videoURL: bestStream.url, startTime: startTime, volume: volume, sourceWebView: webView)
                }
                return
            }

            // If no combined stream, try video-only with highest resolution
            let videoOnlyStreams = streams
                .filterVideoOnly()
                .filter { $0.isNativelyPlayable }

            if let bestVideoStream = videoOnlyStreams.highestResolutionStream() {
                print("[PIP] Using video-only stream: \(bestVideoStream.videoResolution ?? 0)p")

                await MainActor.run {
                    self.isPIPActive = true
                    PIPWindowController.show(videoURL: bestVideoStream.url, startTime: startTime, volume: volume, sourceWebView: webView)
                }
                return
            }

            print("[PIP] No playable streams found")
            await MainActor.run {
                self.isPIPActive = false
            }

        } catch {
            print("[PIP] YouTubeKit error: \(error)")
            await MainActor.run {
                self.isPIPActive = false
            }
        }
    }

    /// Close PIP
    func closePIP() {
        PIPWindowController.shared?.closePIP()
        isPIPActive = false
    }
}
