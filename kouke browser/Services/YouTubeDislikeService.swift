//
//  YouTubeDislikeService.swift
//  kouke browser
//
//  Service for fetching YouTube dislike counts using Return YouTube Dislike API.
//

import Foundation
import WebKit

class YouTubeDislikeService {
    static let shared = YouTubeDislikeService()

    private let apiBaseURL = "https://returnyoutubedislikeapi.com"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    // MARK: - API Response

    struct VideoStats: Codable {
        let id: String
        let likes: Int
        let dislikes: Int
        let viewCount: Int
        let rating: Double?
    }

    // MARK: - Fetch Dislike Count

    /// Fetch video statistics from Return YouTube Dislike API
    func fetchVideoStats(videoId: String) async throws -> VideoStats {
        guard let url = URL(string: "\(apiBaseURL)/votes?videoId=\(videoId)") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(VideoStats.self, from: data)
    }

    // MARK: - JavaScript Injection

    /// Generate JavaScript to inject dislike count into YouTube page
    /// Based on the official Return YouTube Dislike userscript
    static func generateInjectionScript() -> String {
        return """
        (function() {
            'use strict';

            // Prevent duplicate injection
            if (window.__kouke_ryd_injected__) return;
            window.__kouke_ryd_injected__ = true;

            let isMobile = location.hostname === 'm.youtube.com';
            let isShorts = () => location.pathname.startsWith('/shorts');
            let currentVideoId = null;

            function cLog(text) {
                console.log('[Kouke RYD] ' + text);
            }

            function getVideoId() {
                const urlParams = new URLSearchParams(window.location.search);
                const id = urlParams.get('v');
                if (id) return id;
                // For shorts
                if (isShorts()) {
                    const match = location.pathname.match(/\\/shorts\\/([^/?]+)/);
                    return match ? match[1] : null;
                }
                return null;
            }

            function numberFormat(num) {
                if (num >= 1000000000) return (num / 1000000000).toFixed(1).replace(/\\.0$/, '') + 'B';
                if (num >= 1000000) return (num / 1000000).toFixed(1).replace(/\\.0$/, '') + 'M';
                if (num >= 1000) return (num / 1000).toFixed(1).replace(/\\.0$/, '') + 'K';
                return num.toLocaleString();
            }

            function getButtons() {
                if (isShorts()) {
                    let elements = document.querySelectorAll(
                        isMobile ? 'ytm-like-button-renderer' : '#like-button > ytd-like-button-renderer'
                    );
                    for (let element of elements) {
                        return element;
                    }
                }
                if (isMobile) {
                    return document.querySelector('.slim-video-action-bar-actions .segmented-buttons') ||
                           document.querySelector('.slim-video-action-bar-actions');
                }
                if (document.getElementById('menu-container')?.offsetParent === null) {
                    return document.querySelector('ytd-menu-renderer.ytd-watch-metadata > div') ||
                           document.querySelector('ytd-menu-renderer.ytd-video-primary-info-renderer > div');
                } else {
                    return document.getElementById('menu-container')?.querySelector('#top-level-buttons-computed');
                }
            }

            function getDislikeButton() {
                const buttons = getButtons();
                if (!buttons) return null;

                if (buttons.children[0]?.tagName === 'YTD-SEGMENTED-LIKE-DISLIKE-BUTTON-RENDERER') {
                    if (buttons.children[0].children[1] === undefined) {
                        return document.querySelector('#segmented-dislike-button');
                    } else {
                        return buttons.children[0].children[1];
                    }
                } else {
                    if (buttons.querySelector('segmented-like-dislike-button-view-model')) {
                        return buttons.querySelector('dislike-button-view-model');
                    } else {
                        return buttons.children[1];
                    }
                }
            }

            function getDislikeTextContainer() {
                const dislikeButton = getDislikeButton();
                if (!dislikeButton) return null;

                let result = dislikeButton.querySelector('#text') ||
                             dislikeButton.getElementsByTagName('yt-formatted-string')[0] ||
                             dislikeButton.querySelector('span[role="text"]');

                if (result === null) {
                    let textSpan = document.createElement('span');
                    textSpan.id = 'text';
                    textSpan.style.marginLeft = '6px';
                    const btn = dislikeButton.querySelector('button');
                    if (btn) {
                        btn.appendChild(textSpan);
                        btn.style.width = 'auto';
                    }
                    result = textSpan;
                }
                return result;
            }

            function setDislikes(dislikesCount) {
                const container = getDislikeTextContainer();
                if (container) {
                    container.removeAttribute('is-empty');
                    if (container.innerText !== dislikesCount) {
                        container.innerText = dislikesCount;
                    }
                }
            }

            function setState() {
                const videoId = getVideoId();
                if (!videoId) return;
                if (videoId === currentVideoId) return;
                currentVideoId = videoId;

                cLog('Fetching votes for: ' + videoId);

                fetch('https://returnyoutubedislikeapi.com/votes?videoId=' + videoId)
                    .then(response => response.json())
                    .then(data => {
                        if (data && data.dislikes !== undefined) {
                            cLog('Received dislikes: ' + data.dislikes);
                            setDislikes(numberFormat(data.dislikes));
                        }
                    })
                    .catch(error => {
                        cLog('Failed to fetch: ' + error);
                    });
            }

            function checkAndSetState() {
                if (getButtons() && getDislikeButton()) {
                    setState();
                } else {
                    setTimeout(checkAndSetState, 500);
                }
            }

            // Initial run
            if (location.pathname === '/watch' || isShorts()) {
                setTimeout(checkAndSetState, 1000);
            }

            // YouTube SPA navigation
            document.addEventListener('yt-navigate-finish', () => {
                currentVideoId = null;
                if (location.pathname === '/watch' || isShorts()) {
                    setTimeout(checkAndSetState, 500);
                }
            });

            // Fallback: observe URL changes
            let lastUrl = location.href;
            new MutationObserver(() => {
                if (location.href !== lastUrl) {
                    lastUrl = location.href;
                    currentVideoId = null;
                    if (location.pathname === '/watch' || isShorts()) {
                        setTimeout(checkAndSetState, 1000);
                    }
                }
            }).observe(document.body, { childList: true, subtree: true });

        })();
        """
    }

    /// Check if URL is a YouTube video page
    static func isYouTubeVideoPage(_ url: URL?) -> Bool {
        guard let url = url,
              let host = url.host else { return false }
        return (host.contains("youtube.com") || host.contains("youtu.be")) &&
               (url.path == "/watch" || host == "youtu.be")
    }

    /// Get the user script source for Return YouTube Dislike
    /// Based on the official userscript from https://github.com/Anarios/return-youtube-dislike
    static func getUserScript() -> String {
        return generateInjectionScript()
    }
}
