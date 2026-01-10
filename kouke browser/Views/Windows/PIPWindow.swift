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

// MARK: - Danmaku (Barrage) System

/// Single danmaku comment
struct Danmaku: Codable {
    let text: String
    let time: Int      // Time in 10ms units
    let color: String  // Hex color like "#FFFFFF"
    let position: Int  // 0=scroll, 1=top, 2=bottom

    var timeInSeconds: Double {
        // Time is in 10ms units (centiseconds), divide by 100 to get seconds
        // But actual API seems to use different scale - testing with /10 (deciseconds)
        return Double(time) / 10.0
    }

    var nsColor: NSColor {
        // Parse hex color
        var hex = color.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6,
              let rgb = UInt64(hex, radix: 16) else {
            return .white
        }
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }
}

/// Danmaku overlay view that renders comments over video
class DanmakuOverlayView: NSView {
    private var danmakuList: [Danmaku] = []
    private var activeDanmaku: [(danmaku: Danmaku, layer: CATextLayer, startTime: Double)] = []
    private var displayLink: CVDisplayLink?
    private var currentTime: Double = 0
    private var lastProcessedIndex: Int = 0
    private var isPlaying: Bool = false

    // Display settings
    private let scrollDuration: Double = 8.0  // Time for danmaku to scroll across screen
    private let fontSize: CGFloat = 20.0
    private let lineHeight: CGFloat = 28.0
    private var topTracks: [Double] = []      // Track availability for top danmaku
    private var bottomTracks: [Double] = []   // Track availability for bottom danmaku
    private var scrollTracks: [(endTime: Double, endX: CGFloat)] = []  // Track for scroll danmaku collision

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.masksToBounds = true

        // Initialize tracks
        let trackCount = 15
        topTracks = Array(repeating: 0, count: trackCount)
        bottomTracks = Array(repeating: 0, count: trackCount)
        scrollTracks = Array(repeating: (0, 0), count: trackCount)
    }

    func loadDanmaku(_ list: [Danmaku], startTime: Double = 0) {
        // Sort by time
        danmakuList = list.sorted { $0.time < $1.time }
        // Find starting index based on current playback time
        lastProcessedIndex = danmakuList.firstIndex { $0.timeInSeconds >= startTime } ?? danmakuList.count

        // Debug: show time distribution
        if let first = danmakuList.first, let last = danmakuList.last {
            print("[Danmaku] Loaded \(danmakuList.count) comments, time range: \(first.timeInSeconds)s - \(last.timeInSeconds)s")
            print("[Danmaku] Starting from index \(lastProcessedIndex) at playback time \(startTime)s")

            // Count how many danmaku are after startTime
            let remaining = danmakuList.filter { $0.timeInSeconds >= startTime }.count
            print("[Danmaku] Remaining danmaku after current time: \(remaining)")
        }
    }

    private var lastDebugPrintTime: Double = 0

    func updateTime(_ time: Double, isPlaying: Bool) {
        self.isPlaying = isPlaying

        // Handle seek - reset if time jumped backwards
        if time < currentTime - 1.0 {
            clearAllDanmaku()
            lastProcessedIndex = danmakuList.firstIndex { $0.timeInSeconds >= time } ?? 0
            print("[Danmaku] Seek detected, reset to index \(lastProcessedIndex)")
        }

        currentTime = time

        guard isPlaying else { return }

        // Debug print every 5 seconds
        if time - lastDebugPrintTime > 5.0 {
            lastDebugPrintTime = time
            print("[Danmaku] Time: \(String(format: "%.1f", time))s, index: \(lastProcessedIndex)/\(danmakuList.count), active: \(activeDanmaku.count)")
        }

        // Add new danmaku that should appear
        var addedCount = 0
        while lastProcessedIndex < danmakuList.count {
            let danmaku = danmakuList[lastProcessedIndex]
            if danmaku.timeInSeconds <= currentTime && danmaku.timeInSeconds > currentTime - 0.5 {
                addDanmaku(danmaku)
                lastProcessedIndex += 1
                addedCount += 1
            } else if danmaku.timeInSeconds > currentTime {
                break
            } else {
                lastProcessedIndex += 1
            }
        }

        if addedCount > 0 {
            print("[Danmaku] Added \(addedCount) danmaku at time \(String(format: "%.1f", time))s")
        }

        // Update positions of scroll danmaku
        updateScrollPositions()

        // Remove expired danmaku
        removeExpiredDanmaku()
    }

    private func addDanmaku(_ danmaku: Danmaku) {
        let textLayer = CATextLayer()
        textLayer.string = danmaku.text
        textLayer.font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        textLayer.fontSize = fontSize
        textLayer.foregroundColor = danmaku.nsColor.cgColor
        textLayer.alignmentMode = .center
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0

        // Add text shadow for better visibility
        textLayer.shadowColor = NSColor.black.cgColor
        textLayer.shadowOffset = CGSize(width: 1, height: -1)
        textLayer.shadowRadius = 2
        textLayer.shadowOpacity = 0.8

        // Calculate text size
        let textSize = (danmaku.text as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium)
        ])
        textLayer.frame = CGRect(x: 0, y: 0, width: textSize.width + 10, height: lineHeight)

        // Position based on type
        switch danmaku.position {
        case 1: // Top fixed
            if let track = findAvailableTrack(for: &topTracks, duration: 3.0) {
                textLayer.frame.origin = CGPoint(
                    x: (bounds.width - textLayer.frame.width) / 2,
                    y: bounds.height - CGFloat(track + 1) * lineHeight - 10
                )
                layer?.addSublayer(textLayer)
                activeDanmaku.append((danmaku, textLayer, currentTime))
            }

        case 2: // Bottom fixed
            if let track = findAvailableTrack(for: &bottomTracks, duration: 3.0) {
                textLayer.frame.origin = CGPoint(
                    x: (bounds.width - textLayer.frame.width) / 2,
                    y: CGFloat(track) * lineHeight + 50  // Leave space for video controls
                )
                layer?.addSublayer(textLayer)
                activeDanmaku.append((danmaku, textLayer, currentTime))
            }

        default: // Scroll (0 or others)
            if let track = findScrollTrack(textWidth: textLayer.frame.width) {
                textLayer.frame.origin = CGPoint(
                    x: bounds.width,
                    y: bounds.height - CGFloat(track + 1) * lineHeight - 10
                )
                layer?.addSublayer(textLayer)
                activeDanmaku.append((danmaku, textLayer, currentTime))
            }
        }
    }

    private func findAvailableTrack(for tracks: inout [Double], duration: Double) -> Int? {
        for (index, expireTime) in tracks.enumerated() {
            if currentTime >= expireTime {
                tracks[index] = currentTime + duration
                return index
            }
        }
        return nil
    }

    private func findScrollTrack(textWidth: CGFloat) -> Int? {
        let speed = (bounds.width + textWidth) / scrollDuration

        for (index, track) in scrollTracks.enumerated() {
            // Check if previous danmaku has cleared enough space
            if currentTime >= track.endTime || track.endX < bounds.width - 50 {
                let endTime = currentTime + scrollDuration
                scrollTracks[index] = (endTime, bounds.width + textWidth)
                return index
            }
        }
        return nil
    }

    private func updateScrollPositions() {
        for (index, item) in activeDanmaku.enumerated().reversed() {
            guard item.danmaku.position == 0 else { continue }

            let elapsed = currentTime - item.startTime
            let progress = elapsed / scrollDuration
            let totalDistance = bounds.width + item.layer.frame.width
            let newX = bounds.width - (totalDistance * progress)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            item.layer.frame.origin.x = newX
            CATransaction.commit()

            // Update track info
            if let trackIndex = scrollTracks.firstIndex(where: { $0.endTime == item.startTime + scrollDuration }) {
                scrollTracks[trackIndex].endX = newX + item.layer.frame.width
            }
        }
    }

    private func removeExpiredDanmaku() {
        activeDanmaku.removeAll { item in
            let duration: Double
            switch item.danmaku.position {
            case 1, 2: duration = 3.0  // Fixed danmaku
            default: duration = scrollDuration  // Scroll danmaku
            }

            if currentTime - item.startTime > duration {
                item.layer.removeFromSuperlayer()
                return true
            }
            return false
        }
    }

    private func clearAllDanmaku() {
        for item in activeDanmaku {
            item.layer.removeFromSuperlayer()
        }
        activeDanmaku.removeAll()
        topTracks = topTracks.map { _ in 0 }
        bottomTracks = bottomTracks.map { _ in 0 }
        scrollTracks = scrollTracks.map { _ in (0, 0) }
    }

    func cleanup() {
        clearAllDanmaku()
        danmakuList.removeAll()
    }
}

// MARK: - PIP Window Controller

class PIPWindowController: NSWindowController {
    private var playerView: AVPlayerView?
    private var player: AVPlayer?
    private var pipController: AVPictureInPictureController?
    private weak var sourceWebView: WKWebView?
    private var currentTime: Double = 0
    private var volume: Float = 1.0
    private var videoSizeObserver: NSKeyValueObservation?
    private var timeObserver: Any?

    // Danmaku support
    private var danmakuOverlay: DanmakuOverlayView?
    private var episodeSn: String?

    static var shared: PIPWindowController?

    private var httpHeaders: [String: String]?

    convenience init(videoURL: URL, startTime: Double, volume: Float, sourceWebView: WKWebView?, headers: [String: String]? = nil, episodeSn: String? = nil) {
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
        self.httpHeaders = headers
        self.episodeSn = episodeSn

        setupWindow()
        setupPlayer(with: videoURL, startTime: startTime, volume: volume, headers: headers)

        // Load danmaku if episode SN is available and feature is enabled
        if let sn = episodeSn, BrowserSettings.shared.enableDanmaku {
            Task {
                await loadDanmaku(sn: sn)
            }
        }
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
        // Don't set fixed aspect ratio - will be updated when video loads
        window.delegate = self
    }

    private func setupPlayer(with url: URL, startTime: Double, volume: Float, headers: [String: String]? = nil) {
        guard let window = window else { return }

        let playerItem: AVPlayerItem

        if let headers = headers, !headers.isEmpty {
            // Use AVURLAsset with custom headers for streams that require authentication
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            playerItem = AVPlayerItem(asset: asset)
        } else {
            playerItem = AVPlayerItem(url: url)
        }

        player = AVPlayer(playerItem: playerItem)

        // Set volume to match source video
        player?.volume = volume

        playerView = AVPlayerView()
        playerView?.player = player
        playerView?.controlsStyle = .floating
        playerView?.frame = window.contentView?.bounds ?? .zero
        playerView?.autoresizingMask = [.width, .height]

        window.contentView?.addSubview(playerView!)

        // Setup danmaku overlay
        setupDanmakuOverlay()

        // Observe video size to adjust window aspect ratio
        videoSizeObserver = playerItem.observe(\.presentationSize, options: [.new]) { [weak self] item, _ in
            guard let self = self, let window = self.window else { return }
            let size = item.presentationSize
            if size.width > 0 && size.height > 0 {
                DispatchQueue.main.async {
                    // Update window aspect ratio to match video
                    window.aspectRatio = size

                    // Resize window to fit the new aspect ratio while keeping width
                    let currentFrame = window.frame
                    let newHeight = currentFrame.width * (size.height / size.width)
                    let newFrame = NSRect(
                        x: currentFrame.origin.x,
                        y: currentFrame.origin.y + (currentFrame.height - newHeight),
                        width: currentFrame.width,
                        height: newHeight
                    )
                    window.setFrame(newFrame, display: true, animate: true)
                }
            }
        }

        // Setup time observer for danmaku sync
        setupTimeObserver()

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

    private func setupDanmakuOverlay() {
        guard let window = window, let contentView = window.contentView else { return }

        // Only setup danmaku overlay if feature is enabled
        guard BrowserSettings.shared.enableDanmaku else { return }

        danmakuOverlay = DanmakuOverlayView(frame: contentView.bounds)
        danmakuOverlay?.autoresizingMask = [.width, .height]
        danmakuOverlay?.wantsLayer = true
        danmakuOverlay?.layer?.zPosition = 1000  // Ensure it's above video
        contentView.addSubview(danmakuOverlay!, positioned: .above, relativeTo: playerView)

        print("[Danmaku] Overlay setup completed, frame: \(contentView.bounds)")
    }

    private func setupTimeObserver() {
        // Update danmaku every 0.016 seconds (60fps)
        let interval = CMTime(seconds: 1.0/60.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let currentTime = time.seconds
            let isPlaying = self.player?.rate != 0
            self.danmakuOverlay?.updateTime(currentTime, isPlaying: isPlaying)
        }
    }

    private func loadDanmaku(sn: String) async {
        print("[Danmaku] Loading danmaku for sn: \(sn)")

        guard let url = URL(string: "https://ani.gamer.com.tw/ajax/danmuGet.php") else {
            print("[Danmaku] Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://ani.gamer.com.tw/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.httpBody = "sn=\(sn)".data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            print("[Danmaku] Response received, data size: \(data.count) bytes")

            // Debug: print first 500 chars of response
            if let responseStr = String(data: data.prefix(500), encoding: .utf8) {
                print("[Danmaku] Response preview: \(responseStr)")
            }

            let danmakuList = try JSONDecoder().decode([Danmaku].self, from: data)
            print("[Danmaku] Decoded \(danmakuList.count) danmaku items")

            await MainActor.run {
                // Get current playback time to start from correct position
                let currentTime = self.player?.currentTime().seconds ?? 0
                self.danmakuOverlay?.loadDanmaku(danmakuList, startTime: currentTime)
                print("[Danmaku] Loaded into overlay, overlay exists: \(self.danmakuOverlay != nil), currentTime: \(currentTime)")
            }
        } catch {
            print("[Danmaku] Failed to load: \(error)")
            // Print raw response for debugging
            if let data = try? await URLSession.shared.data(for: request).0,
               let str = String(data: data, encoding: .utf8) {
                print("[Danmaku] Raw response: \(str.prefix(1000))")
            }
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

        // Cleanup danmaku
        danmakuOverlay?.cleanup()
        danmakuOverlay?.removeFromSuperview()
        danmakuOverlay = nil

        // Remove time observer
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }

        videoSizeObserver?.invalidate()
        videoSizeObserver = nil
        player?.pause()
        player = nil
        pipController = nil
        window?.close()
        PIPWindowController.shared = nil

        Task { @MainActor in
            PIPManager.shared.isPIPActive = false
        }
    }

    static func show(videoURL: URL, startTime: Double, volume: Float, sourceWebView: WKWebView?, headers: [String: String]? = nil, episodeSn: String? = nil) {
        shared?.closePIP()

        let controller = PIPWindowController(videoURL: videoURL, startTime: startTime, volume: volume, sourceWebView: sourceWebView, headers: headers, episodeSn: episodeSn)
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

        // Cleanup danmaku
        danmakuOverlay?.cleanup()
        danmakuOverlay?.removeFromSuperview()
        danmakuOverlay = nil

        // Remove time observer
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }

        videoSizeObserver?.invalidate()
        videoSizeObserver = nil
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

        // For blob URLs (HLS streams), we need to call requestPictureInPicture()
        // in the SAME JavaScript execution to maintain user gesture context.
        // So we do detection and activation in one call.
        tryPIPWithFallback(from: webView)
    }

    /// Try PIP with automatic fallback to native browser PIP for blob URLs
    private func tryPIPWithFallback(from webView: WKWebView) {
        let script = """
        (function() {
            const videos = Array.from(document.querySelectorAll('video'));
            if (videos.length === 0) return { type: 'no_video' };

            // Find the best video candidate
            let bestVideo = null;
            let bestScore = -1;

            for (const video of videos) {
                let score = 0;
                if (!video.paused && video.currentTime > 0) score += 1000;
                if (video.duration && video.duration > 60) score += 100;
                if (video.videoWidth > 0 && video.videoHeight > 0) {
                    score += 50 + (video.videoWidth * video.videoHeight) / 10000;
                }
                if (video.currentTime > 0) score += 20;
                if (video.readyState >= 2) score += 10;

                if (score > bestScore) {
                    bestScore = score;
                    bestVideo = video;
                }
            }

            if (!bestVideo) bestVideo = videos[0];
            const video = bestVideo;
            const src = video.src || video.currentSrc;
            const isBlobUrl = src && src.startsWith('blob:');
            const hostname = window.location.hostname;

            // Site-specific: ani.gamer.com.tw (Bahamut Animation)
            // This site uses HLS with encrypted streams, requiring API calls to get m3u8 URL
            if (hostname.includes('ani.gamer.com.tw')) {
                console.log('[Kouke PIP] Detected ani.gamer.com.tw');

                // Extract SN (episode number) from URL
                const urlParams = new URLSearchParams(window.location.search);
                const sn = urlParams.get('sn');

                if (sn) {
                    console.log('[Kouke PIP] Found sn:', sn);
                    return {
                        type: 'ani_gamer_api',
                        sn: sn,
                        currentTime: video.currentTime,
                        duration: video.duration,
                        volume: video.muted ? 0 : video.volume
                    };
                } else {
                    console.log('[Kouke PIP] No sn parameter found in URL');
                }
            }

            // For blob URLs, try native PIP
            if (isBlobUrl) {
                // Force-remove PIP disable attribute if present
                if (video.disablePictureInPicture) {
                    video.disablePictureInPicture = false;
                    video.removeAttribute('disablePictureInPicture');
                }

                if (document.pictureInPictureElement === video) {
                    document.exitPictureInPicture();
                    return { type: 'native_pip', action: 'exited' };
                }

                if (document.pictureInPictureEnabled) {
                    video.requestPictureInPicture()
                        .then(() => console.log('[Kouke PIP] Native PIP activated'))
                        .catch(err => console.error('[Kouke PIP] Native PIP failed:', err));
                    return { type: 'native_pip', action: 'requested' };
                } else {
                    return { type: 'native_pip', action: 'failed', error: 'PIP not supported' };
                }
            }

            // For non-blob URLs, return video info for AVPlayer handling
            const info = {
                type: 'extract_url',
                currentTime: video.currentTime,
                duration: video.duration,
                volume: video.muted ? 0 : video.volume,
                isYouTube: window.location.hostname.includes('youtube.com')
            };

            if (info.isYouTube) {
                const urlParams = new URLSearchParams(window.location.search);
                info.videoId = urlParams.get('v');
            } else if (src && !src.startsWith('blob:')) {
                info.directUrl = src;
            } else {
                const source = video.querySelector('source');
                if (source && source.src && !source.src.startsWith('blob:')) {
                    info.directUrl = source.src;
                }
            }

            return info;
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self = self else { return }

            print("[PIP] Result: \(String(describing: result))")

            guard let info = result as? [String: Any],
                  let type = info["type"] as? String else {
                print("[PIP] No video found or invalid response")
                return
            }

            switch type {
            case "native_pip":
                let action = info["action"] as? String ?? "unknown"
                print("[PIP] Native PIP \(action)")
                // Native PIP is browser-managed, we don't track state

            case "ani_gamer_api":
                // ani.gamer.com.tw requires API calls to get m3u8 URL
                guard let sn = info["sn"] as? String else {
                    print("[PIP] Missing sn for ani.gamer.com.tw")
                    return
                }
                let currentTime = info["currentTime"] as? Double ?? 0
                let volume = Float(info["volume"] as? Double ?? 1.0)

                print("[PIP] ani.gamer.com.tw - Fetching m3u8 for sn: \(sn)")
                Task {
                    await self.extractAniGamerStream(sn: sn, startTime: currentTime, volume: volume, webView: webView)
                }

            case "extract_url":
                let currentTime = info["currentTime"] as? Double ?? 0
                let volume = Float(info["volume"] as? Double ?? 1.0)
                let isYouTube = info["isYouTube"] as? Bool ?? false

                if isYouTube, let videoId = info["videoId"] as? String {
                    print("[PIP] YouTube video, using YouTubeKit")
                    Task {
                        await self.extractYouTubeStream(videoId: videoId, startTime: currentTime, volume: volume, webView: webView)
                    }
                } else if let directUrl = info["directUrl"] as? String,
                          let url = URL(string: directUrl) {
                    print("[PIP] Using direct video URL")
                    DispatchQueue.main.async {
                        self.isPIPActive = true
                        PIPWindowController.show(videoURL: url, startTime: currentTime, volume: volume, sourceWebView: webView)
                    }
                } else {
                    print("[PIP] Could not extract playable video URL")
                }

            default:
                print("[PIP] Unknown type: \(type)")
            }
        }
    }

    private func extractVideoInfo(from webView: WKWebView) {
        // Improved video selection: find the active/playing video, not just the first one
        let script = """
        (function() {
            const videos = Array.from(document.querySelectorAll('video'));
            if (videos.length === 0) return null;

            // Find the best video candidate
            // Priority: playing video > video with progress > largest video > first video
            let bestVideo = null;
            let bestScore = -1;

            for (const video of videos) {
                let score = 0;

                // Strongly prefer videos that are currently playing
                if (!video.paused && video.currentTime > 0) score += 1000;

                // Prefer videos with actual content (has duration, not super short)
                if (video.duration && video.duration > 60) score += 100;

                // Prefer videos with visible dimensions (actual content)
                if (video.videoWidth > 0 && video.videoHeight > 0) {
                    score += 50;
                    // Larger videos are more likely to be the main content
                    score += (video.videoWidth * video.videoHeight) / 10000;
                }

                // Prefer videos with some playback progress
                if (video.currentTime > 0) score += 20;

                // Prefer videos that are ready to play
                if (video.readyState >= 2) score += 10;

                if (score > bestScore) {
                    bestScore = score;
                    bestVideo = video;
                }
            }

            if (!bestVideo) bestVideo = videos[0];

            const video = bestVideo;
            let src = video.src || video.currentSrc;

            const info = {
                currentTime: video.currentTime,
                duration: video.duration,
                paused: video.paused,
                volume: video.muted ? 0 : video.volume,
                width: video.videoWidth,
                height: video.videoHeight,
                isYouTube: window.location.hostname.includes('youtube.com'),
                isBlobUrl: src && src.startsWith('blob:'),
                videoIndex: videos.indexOf(video)
            };

            // For YouTube, get the video ID
            if (info.isYouTube) {
                const urlParams = new URLSearchParams(window.location.search);
                info.videoId = urlParams.get('v');
            } else if (!info.isBlobUrl) {
                // For non-YouTube sites with direct URLs
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
                let isBlobUrl = info["isBlobUrl"] as? Bool ?? false
                let videoIndex = info["videoIndex"] as? Int ?? 0

                // Handle YouTube videos with YouTubeKit
                if isYouTube, let videoId = info["videoId"] as? String {
                    print("[PIP] YouTube video detected, using YouTubeKit for videoId: \(videoId)")
                    Task {
                        await self.extractYouTubeStream(videoId: videoId, startTime: currentTime, volume: volume, webView: webView)
                    }
                    return
                }

                // For blob URLs (HLS streams like ani.gamer.com.tw), use native browser PIP
                if isBlobUrl {
                    print("[PIP] Blob URL detected (HLS stream), using native browser PIP")
                    self.tryNativePIP(from: webView, videoIndex: videoIndex)
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

    /// Use the browser's native Picture-in-Picture API for blob/HLS streams
    private func tryNativePIP(from webView: WKWebView, videoIndex: Int) {
        let script = """
        (function() {
            const videos = Array.from(document.querySelectorAll('video'));
            const video = videos[\(videoIndex)] || videos[0];
            if (!video) return { success: false, error: 'No video found' };

            // Check if PIP is supported
            if (!document.pictureInPictureEnabled) {
                return { success: false, error: 'PIP not supported' };
            }

            // Check if video can enter PIP
            if (video.disablePictureInPicture) {
                return { success: false, error: 'PIP disabled on video' };
            }

            // If already in PIP, exit
            if (document.pictureInPictureElement === video) {
                document.exitPictureInPicture();
                return { success: true, action: 'exited' };
            }

            // Request PIP
            video.requestPictureInPicture()
                .then(() => console.log('[Kouke PIP] Native PIP activated'))
                .catch(err => console.error('[Kouke PIP] Native PIP failed:', err));

            return { success: true, action: 'requested' };
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                print("[PIP] Native PIP error: \(error)")
            }

            if let info = result as? [String: Any] {
                let success = info["success"] as? Bool ?? false
                let action = info["action"] as? String
                let errorMsg = info["error"] as? String

                if success {
                    print("[PIP] Native PIP \(action ?? "completed")")
                    // Note: We don't set isPIPActive here because native PIP is managed by the browser
                } else {
                    print("[PIP] Native PIP failed: \(errorMsg ?? "unknown error")")
                }
            }

            DispatchQueue.main.async {
                // Reset our state since native PIP is browser-managed
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

    /// Extract ani.gamer.com.tw stream URL using their API
    private func extractAniGamerStream(sn: String, startTime: Double, volume: Float, webView: WKWebView) async {
        do {
            print("[PIP] ani.gamer.com.tw - Step 1: Getting device ID")

            // Step 1: Get device ID
            guard let deviceIdUrl = URL(string: "https://ani.gamer.com.tw/ajax/getdeviceid.php") else {
                print("[PIP] Invalid device ID URL")
                return
            }

            var deviceIdRequest = URLRequest(url: deviceIdUrl)
            deviceIdRequest.setValue("https://ani.gamer.com.tw/", forHTTPHeaderField: "Referer")
            deviceIdRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

            let (deviceIdData, _) = try await URLSession.shared.data(for: deviceIdRequest)

            guard let deviceIdJson = try JSONSerialization.jsonObject(with: deviceIdData) as? [String: Any],
                  let deviceId = deviceIdJson["deviceid"] as? String else {
                print("[PIP] Failed to parse device ID response")
                return
            }

            print("[PIP] ani.gamer.com.tw - Got device ID: \(deviceId)")

            // Step 2: Get m3u8 URL
            print("[PIP] ani.gamer.com.tw - Step 2: Getting m3u8 URL")
            guard let m3u8ApiUrl = URL(string: "https://ani.gamer.com.tw/ajax/m3u8.php?sn=\(sn)&device=\(deviceId)") else {
                print("[PIP] Invalid m3u8 API URL")
                return
            }

            var m3u8Request = URLRequest(url: m3u8ApiUrl)
            m3u8Request.setValue("https://ani.gamer.com.tw/animeVideo.php?sn=\(sn)", forHTTPHeaderField: "Referer")
            m3u8Request.setValue("https://ani.gamer.com.tw", forHTTPHeaderField: "Origin")
            m3u8Request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

            // Get cookies from WebView to include authentication
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            let cookieHeader = cookies
                .filter { $0.domain.contains("gamer.com.tw") }
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")

            if !cookieHeader.isEmpty {
                m3u8Request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
                print("[PIP] ani.gamer.com.tw - Using cookies for auth")
            }

            let (m3u8Data, _) = try await URLSession.shared.data(for: m3u8Request)

            guard let m3u8Json = try JSONSerialization.jsonObject(with: m3u8Data) as? [String: Any] else {
                print("[PIP] Failed to parse m3u8 response")
                if let responseStr = String(data: m3u8Data, encoding: .utf8) {
                    print("[PIP] Response: \(responseStr)")
                }
                return
            }

            print("[PIP] ani.gamer.com.tw - m3u8 response: \(m3u8Json)")

            // Check for error
            if let error = m3u8Json["error"] as? Int, error != 0 {
                let errorMsg = m3u8Json["msg"] as? String ?? "Unknown error"
                print("[PIP] ani.gamer.com.tw API error: \(errorMsg)")
                return
            }

            // Extract m3u8 URL from response
            var m3u8UrlString = m3u8Json["src"] as? String

            // Handle the case where src might be empty or contain a placeholder
            if m3u8UrlString == nil || m3u8UrlString?.isEmpty == true || m3u8UrlString?.contains("welcome_to_anigamer") == true {
                print("[PIP] ani.gamer.com.tw - No valid m3u8 URL in response (may require authentication or ad viewing)")
                return
            }

            // Ensure URL has proper protocol
            if m3u8UrlString?.hasPrefix("//") == true {
                m3u8UrlString = "https:" + m3u8UrlString!
            }

            guard let m3u8UrlString = m3u8UrlString,
                  let m3u8Url = URL(string: m3u8UrlString) else {
                print("[PIP] Invalid m3u8 URL")
                return
            }

            print("[PIP] ani.gamer.com.tw - Got m3u8 URL: \(m3u8Url)")

            // Prepare headers for HLS playback
            let headers: [String: String] = [
                "Referer": "https://ani.gamer.com.tw/",
                "Origin": "https://ani.gamer.com.tw",
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
            ]

            await MainActor.run {
                self.isPIPActive = true
                PIPWindowController.show(videoURL: m3u8Url, startTime: startTime, volume: volume, sourceWebView: webView, headers: headers, episodeSn: sn)
            }

        } catch {
            print("[PIP] ani.gamer.com.tw error: \(error)")
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
