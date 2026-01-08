//
//  ReaderModeService.swift
//  kouke browser
//
//  Service for extracting and displaying article content in reader mode.
//

import Foundation
import WebKit

// MARK: - Reader Mode Article

struct ReaderArticle {
    let title: String
    let byline: String?
    let content: String
    let textContent: String
    let siteName: String?
    let publishedDate: String?
    let estimatedReadTime: Int // in minutes

    var isEmpty: Bool {
        textContent.trimmingCharacters(in: .whitespacesAndNewlines).count < 100
    }
}

// MARK: - Reader Mode Service

class ReaderModeService {
    static let shared = ReaderModeService()

    private init() {}

    /// JavaScript to check if page is suitable for reader mode
    static let checkReadabilityJS = """
    (function() {
        // Check for article-like content
        var article = document.querySelector('article');
        var main = document.querySelector('main');
        var content = document.querySelector('[role="main"], .post-content, .article-content, .entry-content, .content, #content');

        // Check text density
        var bodyText = document.body ? document.body.innerText : '';
        var wordCount = bodyText.split(/\\s+/).length;

        // Check for common article indicators
        var hasArticle = !!article;
        var hasMain = !!main;
        var hasContent = !!content;
        var hasEnoughText = wordCount > 200;

        // Check for paragraph density
        var paragraphs = document.querySelectorAll('p');
        var longParagraphs = Array.from(paragraphs).filter(function(p) {
            return p.innerText.split(/\\s+/).length > 20;
        });
        var hasGoodParagraphs = longParagraphs.length >= 3;

        return {
            isReadable: (hasArticle || hasMain || hasContent || hasGoodParagraphs) && hasEnoughText,
            wordCount: wordCount,
            hasArticle: hasArticle,
            hasMain: hasMain,
            paragraphCount: longParagraphs.length
        };
    })();
    """

    /// JavaScript to extract article content
    static let extractArticleJS = """
    (function() {
        function getMetaContent(name) {
            var meta = document.querySelector('meta[name="' + name + '"], meta[property="' + name + '"]');
            return meta ? meta.getAttribute('content') : null;
        }

        function cleanHTML(html) {
            // Remove scripts, styles, iframes, ads
            var temp = document.createElement('div');
            temp.innerHTML = html;

            var removeSelectors = ['script', 'style', 'iframe', 'noscript', 'nav', 'header', 'footer',
                                   'aside', '.ad', '.ads', '.advertisement', '.social', '.share',
                                   '.comments', '.comment', '.related', '.sidebar', '[role="navigation"]',
                                   '[role="banner"]', '[role="contentinfo"]', '.newsletter'];

            removeSelectors.forEach(function(selector) {
                temp.querySelectorAll(selector).forEach(function(el) { el.remove(); });
            });

            return temp.innerHTML;
        }

        // Get title
        var title = document.querySelector('h1')?.innerText ||
                    getMetaContent('og:title') ||
                    document.title;

        // Get byline/author
        var byline = getMetaContent('author') ||
                     getMetaContent('article:author') ||
                     document.querySelector('.author, .byline, [rel="author"]')?.innerText;

        // Get site name
        var siteName = getMetaContent('og:site_name') ||
                       document.querySelector('.site-name, .logo')?.innerText ||
                       window.location.hostname;

        // Get published date
        var publishedDate = getMetaContent('article:published_time') ||
                           getMetaContent('datePublished') ||
                           document.querySelector('time')?.getAttribute('datetime') ||
                           document.querySelector('.date, .published')?.innerText;

        // Get main content
        var contentEl = document.querySelector('article') ||
                        document.querySelector('[role="main"]') ||
                        document.querySelector('main') ||
                        document.querySelector('.post-content, .article-content, .entry-content, .content, #content');

        if (!contentEl) {
            // Fallback: find the element with the most text
            var allElements = document.querySelectorAll('div, section');
            var maxLength = 0;
            allElements.forEach(function(el) {
                var text = el.innerText || '';
                if (text.length > maxLength && text.length < 100000) {
                    maxLength = text.length;
                    contentEl = el;
                }
            });
        }

        var content = contentEl ? cleanHTML(contentEl.innerHTML) : '';
        var textContent = contentEl ? contentEl.innerText : '';

        // Calculate read time (average 200 words per minute)
        var wordCount = textContent.split(/\\s+/).length;
        var readTime = Math.max(1, Math.ceil(wordCount / 200));

        return {
            title: title || 'Untitled',
            byline: byline,
            content: content,
            textContent: textContent,
            siteName: siteName,
            publishedDate: publishedDate,
            estimatedReadTime: readTime
        };
    })();
    """

    /// Check if a page is suitable for reader mode
    func checkReadability(webView: WKWebView, completion: @escaping (Bool) -> Void) {
        webView.evaluateJavaScript(Self.checkReadabilityJS) { result, error in
            if let dict = result as? [String: Any],
               let isReadable = dict["isReadable"] as? Bool {
                completion(isReadable)
            } else {
                completion(false)
            }
        }
    }

    /// Extract article content from a webpage
    func extractArticle(webView: WKWebView, completion: @escaping (ReaderArticle?) -> Void) {
        webView.evaluateJavaScript(Self.extractArticleJS) { result, error in
            guard let dict = result as? [String: Any],
                  let title = dict["title"] as? String,
                  let content = dict["content"] as? String,
                  let textContent = dict["textContent"] as? String else {
                completion(nil)
                return
            }

            let article = ReaderArticle(
                title: title,
                byline: dict["byline"] as? String,
                content: content,
                textContent: textContent,
                siteName: dict["siteName"] as? String,
                publishedDate: dict["publishedDate"] as? String,
                estimatedReadTime: dict["estimatedReadTime"] as? Int ?? 1
            )

            // Only return if there's meaningful content
            if article.isEmpty {
                completion(nil)
            } else {
                completion(article)
            }
        }
    }
}
