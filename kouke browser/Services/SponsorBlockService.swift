//
//  SponsorBlockService.swift
//  kouke browser
//
//  Service for fetching and applying SponsorBlock segments to skip sponsors in YouTube videos.
//  API documentation: https://wiki.sponsor.ajay.app/w/API_Docs
//

import Foundation

class SponsorBlockService {
    static let shared = SponsorBlockService()

    private let apiBaseURL = "https://sponsor.ajay.app"
    private let session: URLSession

    // Cache for segments to avoid repeated API calls
    private var segmentCache: [String: [SponsorSegment]] = [:]
    private let cacheQueue = DispatchQueue(label: "dev.koukeneko.sponsorblock.cache")

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    // MARK: - Models

    /// Categories of segments that can be skipped
    enum SegmentCategory: String, Codable, CaseIterable {
        case sponsor = "sponsor"
        case selfpromo = "selfpromo"
        case interaction = "interaction"  // Subscribe reminders, etc.
        case intro = "intro"
        case outro = "outro"
        case preview = "preview"
        case musicOfftopic = "music_offtopic"
        case filler = "filler"

        var displayName: String {
            switch self {
            case .sponsor: return "Sponsor"
            case .selfpromo: return "Self-Promotion"
            case .interaction: return "Interaction Reminder"
            case .intro: return "Intro"
            case .outro: return "Outro"
            case .preview: return "Preview"
            case .musicOfftopic: return "Non-Music Section"
            case .filler: return "Filler"
            }
        }
    }

    /// Action type for a segment
    enum ActionType: String, Codable {
        case skip = "skip"
        case mute = "mute"
        case full = "full"  // Full video label
        case poi = "poi"    // Point of interest (highlight)
        case chapter = "chapter"
    }

    /// A sponsor segment returned from the API
    struct SponsorSegment: Codable {
        let segment: [Double]  // [startTime, endTime]
        let UUID: String
        let category: String
        let videoDuration: Double?
        let actionType: String?
        let locked: Int?
        let votes: Int?
        let description: String?

        var startTime: Double { segment[0] }
        var endTime: Double { segment[1] }

        var categoryEnum: SegmentCategory? {
            SegmentCategory(rawValue: category)
        }

        var actionTypeEnum: ActionType {
            ActionType(rawValue: actionType ?? "skip") ?? .skip
        }
    }

    // MARK: - API Methods

    /// Fetch skip segments for a video
    /// - Parameters:
    ///   - videoId: YouTube video ID
    ///   - categories: Categories to fetch (defaults to all skip categories)
    /// - Returns: Array of sponsor segments
    func fetchSegments(
        for videoId: String,
        categories: [SegmentCategory] = [.sponsor, .selfpromo, .interaction, .intro, .outro, .preview]
    ) async throws -> [SponsorSegment] {
        // Check cache first
        if let cached = getCachedSegments(for: videoId) {
            return cached
        }

        // Build URL with categories
        var components = URLComponents(string: "\(apiBaseURL)/api/skipSegments")!
        var queryItems = [
            URLQueryItem(name: "videoID", value: videoId)
        ]

        // Add category parameters
        for category in categories {
            queryItems.append(URLQueryItem(name: "category", value: category.rawValue))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // 404 means no segments found (not an error)
        if httpResponse.statusCode == 404 {
            cacheSegments([], for: videoId)
            return []
        }

        guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let segments = try JSONDecoder().decode([SponsorSegment].self, from: data)
        cacheSegments(segments, for: videoId)
        return segments
    }

    // MARK: - Cache

    private func getCachedSegments(for videoId: String) -> [SponsorSegment]? {
        cacheQueue.sync {
            segmentCache[videoId]
        }
    }

    private func cacheSegments(_ segments: [SponsorSegment], for videoId: String) {
        cacheQueue.async {
            self.segmentCache[videoId] = segments
        }
    }

    func clearCache() {
        cacheQueue.async {
            self.segmentCache.removeAll()
        }
    }

    // MARK: - JavaScript Injection

    /// Generate JavaScript to inject SponsorBlock functionality into YouTube
    static func generateInjectionScript() -> String {
        return """
        (function() {
            'use strict';

            // Prevent duplicate injection
            if (window.__kouke_sponsorblock_injected__) return;
            window.__kouke_sponsorblock_injected__ = true;

            const API_URL = 'https://sponsor.ajay.app';
            const CATEGORIES = ['sponsor', 'selfpromo', 'interaction', 'intro', 'outro', 'preview', 'filler'];

            // Category colors matching official SponsorBlock
            const CATEGORY_COLORS = {
                'sponsor': '#00d400',      // Green
                'selfpromo': '#ffff00',    // Yellow
                'interaction': '#cc00ff',  // Purple
                'intro': '#00ffff',        // Cyan
                'outro': '#0202ed',        // Blue
                'preview': '#008fd6',      // Light blue
                'music_offtopic': '#ff9900', // Orange
                'filler': '#7300FF',       // Violet
                'poi_highlight': '#ff1684', // Pink (point of interest)
                'chapter': '#ffd679'       // Gold (chapters)
            };

            const CATEGORY_NAMES = {
                'sponsor': 'Sponsor',
                'selfpromo': 'Unpaid/Self Promotion',
                'interaction': 'Interaction Reminder',
                'intro': 'Intermission/Intro',
                'outro': 'Endcards/Credits',
                'preview': 'Preview/Recap',
                'music_offtopic': 'Non-Music Section',
                'filler': 'Filler Tangent',
                'poi_highlight': 'Highlight',
                'chapter': 'Chapter'
            };

            let currentVideoId = null;
            let segments = [];
            let video = null;
            let progressBar = null;
            let skipNotification = null;
            let skipButton = null;
            let lastSkipTime = 0;
            let lastSkippedSegment = null;
            let unskipTimeout = null;
            let barSegments = [];
            let skipCount = 0;
            let autoSkipEnabled = true;

            function cLog(text) {
                console.log('[Kouke SponsorBlock] ' + text);
            }

            function getVideoId() {
                const urlParams = new URLSearchParams(window.location.search);
                const id = urlParams.get('v');
                if (id) return id;
                // For shorts
                if (location.pathname.startsWith('/shorts/')) {
                    const match = location.pathname.match(/\\/shorts\\/([^/?]+)/);
                    return match ? match[1] : null;
                }
                return null;
            }

            function formatTime(seconds) {
                const mins = Math.floor(seconds / 60);
                const secs = Math.floor(seconds % 60);
                return `${mins}:${secs.toString().padStart(2, '0')}`;
            }

            // Create segment markers on the progress bar
            function createBarSegments() {
                // Remove old segments
                barSegments.forEach(el => el.remove());
                barSegments = [];

                if (!video || !video.duration || segments.length === 0) return;

                // Find the progress bar
                progressBar = document.querySelector('.ytp-progress-bar-container .ytp-progress-list');
                if (!progressBar) {
                    progressBar = document.querySelector('.ytp-progress-bar');
                }
                if (!progressBar) return;

                const duration = video.duration;

                for (const segment of segments) {
                    const [start, end] = segment.segment;
                    const actionType = segment.actionType || 'skip';

                    // Calculate position and width as percentages
                    const left = (start / duration) * 100;
                    const width = ((end - start) / duration) * 100;

                    const marker = document.createElement('div');
                    marker.className = 'kouke-sb-segment';
                    marker.dataset.category = segment.category;
                    marker.dataset.start = start;
                    marker.dataset.end = end;

                    const color = CATEGORY_COLORS[segment.category] || '#00d400';

                    marker.style.cssText = `
                        position: absolute;
                        height: 100%;
                        left: ${left}%;
                        width: ${width}%;
                        background-color: ${color};
                        opacity: 0.7;
                        z-index: 33;
                        pointer-events: auto;
                        cursor: pointer;
                    `;

                    // Tooltip on hover
                    marker.title = `${CATEGORY_NAMES[segment.category] || segment.category}\\n${formatTime(start)} - ${formatTime(end)}`;

                    // Click to skip to segment
                    marker.addEventListener('click', (e) => {
                        e.stopPropagation();
                        if (video) {
                            video.currentTime = start;
                        }
                    });

                    progressBar.appendChild(marker);
                    barSegments.push(marker);
                }

                cLog(`Created ${barSegments.length} segment markers on progress bar`);
            }

            function createSkipNotification() {
                if (skipNotification) return skipNotification;

                skipNotification = document.createElement('div');
                skipNotification.id = 'kouke-sb-notification';
                skipNotification.style.cssText = `
                    position: absolute;
                    bottom: 80px;
                    left: 12px;
                    background: rgba(0, 0, 0, 0.9);
                    color: white;
                    padding: 10px 16px;
                    border-radius: 8px;
                    font-size: 13px;
                    font-family: 'YouTube Sans', 'Roboto', sans-serif;
                    z-index: 1000;
                    opacity: 0;
                    transition: opacity 0.2s;
                    pointer-events: auto;
                    display: flex;
                    align-items: center;
                    gap: 12px;
                    box-shadow: 0 4px 12px rgba(0,0,0,0.4);
                `;

                const content = document.createElement('div');
                content.style.cssText = 'display: flex; align-items: center; gap: 8px;';

                const categoryDot = document.createElement('span');
                categoryDot.id = 'kouke-sb-dot';
                categoryDot.style.cssText = `
                    width: 10px;
                    height: 10px;
                    border-radius: 50%;
                    flex-shrink: 0;
                `;

                const text = document.createElement('span');
                text.id = 'kouke-sb-text';

                content.appendChild(categoryDot);
                content.appendChild(text);

                const unskipBtn = document.createElement('button');
                unskipBtn.id = 'kouke-sb-unskip';
                unskipBtn.textContent = 'Unskip';
                unskipBtn.style.cssText = `
                    background: rgba(255,255,255,0.2);
                    border: none;
                    color: white;
                    padding: 6px 12px;
                    border-radius: 4px;
                    cursor: pointer;
                    font-size: 12px;
                    font-family: inherit;
                    transition: background 0.2s;
                `;
                unskipBtn.addEventListener('mouseenter', () => {
                    unskipBtn.style.background = 'rgba(255,255,255,0.3)';
                });
                unskipBtn.addEventListener('mouseleave', () => {
                    unskipBtn.style.background = 'rgba(255,255,255,0.2)';
                });
                unskipBtn.addEventListener('click', (e) => {
                    e.stopPropagation();
                    if (lastSkippedSegment && video) {
                        video.currentTime = lastSkippedSegment.segment[0];
                        hideNotification();
                    }
                });

                skipNotification.appendChild(content);
                skipNotification.appendChild(unskipBtn);

                return skipNotification;
            }

            function createSkipButton() {
                if (skipButton) return skipButton;

                skipButton = document.createElement('button');
                skipButton.id = 'kouke-sb-skip-btn';
                skipButton.style.cssText = `
                    position: absolute;
                    bottom: 80px;
                    right: 12px;
                    background: rgba(0, 0, 0, 0.9);
                    color: white;
                    padding: 10px 20px;
                    border-radius: 8px;
                    font-size: 14px;
                    font-family: 'YouTube Sans', 'Roboto', sans-serif;
                    font-weight: 500;
                    z-index: 1000;
                    opacity: 0;
                    transition: opacity 0.2s, transform 0.2s;
                    pointer-events: auto;
                    cursor: pointer;
                    border: 2px solid;
                    display: flex;
                    align-items: center;
                    gap: 8px;
                    box-shadow: 0 4px 12px rgba(0,0,0,0.4);
                `;

                skipButton.addEventListener('mouseenter', () => {
                    skipButton.style.transform = 'scale(1.05)';
                });
                skipButton.addEventListener('mouseleave', () => {
                    skipButton.style.transform = 'scale(1)';
                });

                return skipButton;
            }

            function hideNotification() {
                if (skipNotification) {
                    skipNotification.style.opacity = '0';
                }
                if (unskipTimeout) {
                    clearTimeout(unskipTimeout);
                    unskipTimeout = null;
                }
            }

            function hideSkipButton() {
                if (skipButton) {
                    skipButton.style.opacity = '0';
                    skipButton.style.pointerEvents = 'none';
                }
            }

            function showSkipNotification(segment) {
                const notification = createSkipNotification();
                const textEl = notification.querySelector('#kouke-sb-text');
                const dotEl = notification.querySelector('#kouke-sb-dot');

                const categoryName = CATEGORY_NAMES[segment.category] || segment.category;
                const color = CATEGORY_COLORS[segment.category] || '#00d400';

                textEl.textContent = `Skipped ${categoryName}`;
                dotEl.style.backgroundColor = color;

                // Ensure notification is in the player
                const playerContainer = document.querySelector('.html5-video-container');
                if (playerContainer && !playerContainer.contains(notification)) {
                    playerContainer.appendChild(notification);
                }

                notification.style.opacity = '1';
                lastSkippedSegment = segment;

                // Clear previous timeout
                if (unskipTimeout) clearTimeout(unskipTimeout);

                // Hide after 4 seconds
                unskipTimeout = setTimeout(() => {
                    notification.style.opacity = '0';
                    lastSkippedSegment = null;
                }, 4000);
            }

            function showManualSkipButton(segment) {
                const btn = createSkipButton();
                const categoryName = CATEGORY_NAMES[segment.category] || segment.category;
                const color = CATEGORY_COLORS[segment.category] || '#00d400';

                btn.innerHTML = `<span style="font-size: 16px;">⏭</span> Skip ${categoryName}`;
                btn.style.borderColor = color;
                btn.dataset.segmentEnd = segment.segment[1];

                btn.onclick = (e) => {
                    e.stopPropagation();
                    if (video) {
                        video.currentTime = parseFloat(btn.dataset.segmentEnd);
                        skipCount++;
                        hideSkipButton();
                        showSkipNotification(segment);
                    }
                };

                const playerContainer = document.querySelector('.html5-video-container');
                if (playerContainer && !playerContainer.contains(btn)) {
                    playerContainer.appendChild(btn);
                }

                btn.style.opacity = '1';
                btn.style.pointerEvents = 'auto';
            }

            async function fetchSegments(videoId) {
                try {
                    const params = new URLSearchParams();
                    params.append('videoID', videoId);
                    CATEGORIES.forEach(cat => params.append('category', cat));

                    const response = await fetch(`${API_URL}/api/skipSegments?${params}`);

                    if (response.status === 404) {
                        cLog('No segments found for video: ' + videoId);
                        return [];
                    }

                    if (!response.ok) {
                        throw new Error('API error: ' + response.status);
                    }

                    const data = await response.json();
                    cLog('Found ' + data.length + ' segments for video: ' + videoId);
                    return data;
                } catch (error) {
                    cLog('Error fetching segments: ' + error.message);
                    return [];
                }
            }

            let currentSegmentIndex = -1;

            function checkForSkip() {
                if (!video || segments.length === 0) return;

                const currentTime = video.currentTime;
                const now = Date.now();

                let inSegment = false;
                let activeSegment = null;

                for (let i = 0; i < segments.length; i++) {
                    const segment = segments[i];
                    const [start, end] = segment.segment;
                    const actionType = segment.actionType || 'skip';

                    // Only handle skip action type
                    if (actionType !== 'skip') continue;

                    // Check if we're in a segment
                    if (currentTime >= start - 0.3 && currentTime < end - 0.5) {
                        inSegment = true;
                        activeSegment = segment;

                        // Auto-skip if enabled and not recently skipped
                        if (autoSkipEnabled && currentTime >= start && now - lastSkipTime > 500) {
                            cLog(`Skipping ${segment.category} segment: ${start.toFixed(1)}s - ${end.toFixed(1)}s`);
                            video.currentTime = end;
                            lastSkipTime = now;
                            skipCount++;
                            showSkipNotification(segment);
                            hideSkipButton();
                        } else if (!autoSkipEnabled && currentSegmentIndex !== i) {
                            // Show manual skip button
                            showManualSkipButton(segment);
                            currentSegmentIndex = i;
                        }
                        break;
                    }
                }

                if (!inSegment) {
                    currentSegmentIndex = -1;
                    hideSkipButton();
                }
            }

            function setupVideo() {
                video = document.querySelector('video.html5-main-video');
                if (!video) {
                    setTimeout(setupVideo, 500);
                    return;
                }

                // Remove old listener if exists
                video.removeEventListener('timeupdate', checkForSkip);
                video.addEventListener('timeupdate', checkForSkip);

                // Create bar segments when duration is known
                if (video.duration) {
                    createBarSegments();
                } else {
                    video.addEventListener('loadedmetadata', createBarSegments, { once: true });
                    video.addEventListener('durationchange', createBarSegments, { once: true });
                }

                cLog('Video element found and listener attached');
            }

            function cleanup() {
                barSegments.forEach(el => el.remove());
                barSegments = [];
                if (skipNotification) {
                    skipNotification.remove();
                    skipNotification = null;
                }
                if (skipButton) {
                    skipButton.remove();
                    skipButton = null;
                }
                segments = [];
                currentSegmentIndex = -1;
            }

            async function init() {
                const videoId = getVideoId();
                if (!videoId) return;
                if (videoId === currentVideoId) return;

                cleanup();
                currentVideoId = videoId;
                lastSkipTime = 0;
                lastSkippedSegment = null;

                cLog('Initializing for video: ' + videoId);

                segments = await fetchSegments(videoId);
                setupVideo();
            }

            // Initial run
            if (location.pathname === '/watch' || location.pathname.startsWith('/shorts/')) {
                setTimeout(init, 1000);
            }

            // YouTube SPA navigation
            document.addEventListener('yt-navigate-finish', () => {
                currentVideoId = null;
                cleanup();
                if (location.pathname === '/watch' || location.pathname.startsWith('/shorts/')) {
                    setTimeout(init, 500);
                }
            });

            // Fallback: observe URL changes
            let lastUrl = location.href;
            new MutationObserver(() => {
                if (location.href !== lastUrl) {
                    lastUrl = location.href;
                    currentVideoId = null;
                    cleanup();
                    if (location.pathname === '/watch' || location.pathname.startsWith('/shorts/')) {
                        setTimeout(init, 1000);
                    }
                }
            }).observe(document.body, { childList: true, subtree: true });

            // Re-create bar segments when progress bar is recreated (fullscreen, etc.)
            new MutationObserver(() => {
                if (segments.length > 0 && barSegments.length === 0) {
                    createBarSegments();
                }
            }).observe(document.body, { childList: true, subtree: true });

            cLog('SponsorBlock script loaded');
        })();
        """
    }

    /// Get the user script for SponsorBlock integration
    static func getUserScript() -> String {
        return generateInjectionScript()
    }
}
