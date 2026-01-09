//
//  GMAPIPolyfill.swift
//  kouke browser
//
//  Provides Greasemonkey/Tampermonkey API polyfill for userscript support.
//

import Foundation

/// Generates JavaScript polyfill for GM_* and GM.* APIs used by userscripts
struct GMAPIPolyfill {

    /// Generate the full GM API polyfill script
    /// This should be injected at document-start before any userscripts run
    static func generatePolyfill(scriptId: String) -> String {
        return """
        (function() {
            'use strict';

            // Prevent duplicate injection
            if (window.__kouke_gm_api_initialized__) return;
            window.__kouke_gm_api_initialized__ = true;

            // Storage key prefix for this script
            const STORAGE_PREFIX = 'kouke_gm_\(scriptId)_';

            // GM_* style APIs (synchronous where possible)

            // Storage APIs using localStorage
            window.GM_getValue = function(key, defaultValue) {
                try {
                    const value = localStorage.getItem(STORAGE_PREFIX + key);
                    if (value === null) return defaultValue;
                    try {
                        return JSON.parse(value);
                    } catch {
                        return value;
                    }
                } catch (e) {
                    console.warn('[Kouke GM] GM_getValue error:', e);
                    return defaultValue;
                }
            };

            window.GM_setValue = function(key, value) {
                try {
                    localStorage.setItem(STORAGE_PREFIX + key, JSON.stringify(value));
                } catch (e) {
                    console.warn('[Kouke GM] GM_setValue error:', e);
                }
            };

            window.GM_deleteValue = function(key) {
                try {
                    localStorage.removeItem(STORAGE_PREFIX + key);
                } catch (e) {
                    console.warn('[Kouke GM] GM_deleteValue error:', e);
                }
            };

            window.GM_listValues = function() {
                try {
                    const keys = [];
                    for (let i = 0; i < localStorage.length; i++) {
                        const key = localStorage.key(i);
                        if (key && key.startsWith(STORAGE_PREFIX)) {
                            keys.push(key.substring(STORAGE_PREFIX.length));
                        }
                    }
                    return keys;
                } catch (e) {
                    console.warn('[Kouke GM] GM_listValues error:', e);
                    return [];
                }
            };

            // DOM manipulation APIs
            window.GM_addStyle = function(css) {
                try {
                    const style = document.createElement('style');
                    style.type = 'text/css';
                    style.textContent = css;
                    (document.head || document.documentElement).appendChild(style);
                    return style;
                } catch (e) {
                    console.warn('[Kouke GM] GM_addStyle error:', e);
                    return null;
                }
            };

            window.GM_addElement = function(parentNode, tagName, attributes) {
                // Handle overloaded signature: GM_addElement(tagName, attributes)
                if (typeof parentNode === 'string') {
                    attributes = tagName;
                    tagName = parentNode;
                    parentNode = document.head || document.documentElement;
                }

                try {
                    const element = document.createElement(tagName);
                    if (attributes) {
                        for (const [key, value] of Object.entries(attributes)) {
                            if (key === 'textContent') {
                                element.textContent = value;
                            } else {
                                element.setAttribute(key, value);
                            }
                        }
                    }
                    parentNode.appendChild(element);
                    return element;
                } catch (e) {
                    console.warn('[Kouke GM] GM_addElement error:', e);
                    return null;
                }
            };

            // XMLHttpRequest wrapper for cross-origin requests
            // Note: This uses standard fetch which has CORS limitations
            // Full GM_xmlhttpRequest would require native bridge support
            window.GM_xmlhttpRequest = function(details) {
                const {
                    method = 'GET',
                    url,
                    headers = {},
                    data,
                    onload,
                    onerror,
                    onprogress,
                    ontimeout,
                    timeout,
                    responseType
                } = details;

                const controller = new AbortController();
                const signal = controller.signal;

                let timeoutId;
                if (timeout) {
                    timeoutId = setTimeout(() => {
                        controller.abort();
                        if (ontimeout) ontimeout({ status: 0, statusText: 'Timeout' });
                    }, timeout);
                }

                const fetchOptions = {
                    method,
                    headers,
                    signal,
                    mode: 'cors',
                    credentials: 'omit'
                };

                if (data && method !== 'GET' && method !== 'HEAD') {
                    fetchOptions.body = data;
                }

                fetch(url, fetchOptions)
                    .then(async response => {
                        if (timeoutId) clearTimeout(timeoutId);

                        let responseData;
                        if (responseType === 'json') {
                            responseData = await response.json();
                        } else if (responseType === 'blob') {
                            responseData = await response.blob();
                        } else if (responseType === 'arraybuffer') {
                            responseData = await response.arrayBuffer();
                        } else {
                            responseData = await response.text();
                        }

                        const responseObj = {
                            status: response.status,
                            statusText: response.statusText,
                            responseHeaders: [...response.headers].map(([k, v]) => k + ': ' + v).join('\\r\\n'),
                            response: responseData,
                            responseText: typeof responseData === 'string' ? responseData : JSON.stringify(responseData),
                            finalUrl: response.url
                        };

                        if (onload) onload(responseObj);
                    })
                    .catch(error => {
                        if (timeoutId) clearTimeout(timeoutId);
                        if (error.name === 'AbortError') return;
                        console.warn('[Kouke GM] GM_xmlhttpRequest error:', error);
                        if (onerror) onerror({ status: 0, statusText: error.message });
                    });

                return { abort: () => controller.abort() };
            };

            // Tab APIs
            window.GM_openInTab = function(url, options) {
                const openInBackground = typeof options === 'boolean' ? options : options?.active === false;
                window.open(url, '_blank');
                return { close: () => {} };
            };

            // Menu command (no-op in this implementation)
            window.GM_registerMenuCommand = function(name, callback, accessKey) {
                // Menu commands not supported yet
                console.log('[Kouke GM] Menu command registered (not displayed):', name);
                return Math.random();
            };

            window.GM_unregisterMenuCommand = function(menuCmdId) {
                // No-op
            };

            // Resource APIs (no-op, would require preloading resources)
            window.GM_getResourceText = function(name) {
                console.warn('[Kouke GM] GM_getResourceText not supported:', name);
                return '';
            };

            window.GM_getResourceURL = function(name) {
                console.warn('[Kouke GM] GM_getResourceURL not supported:', name);
                return '';
            };

            // Logging
            window.GM_log = function(...args) {
                console.log('[Kouke GM]', ...args);
            };

            // Info object
            window.GM_info = {
                script: {
                    name: 'User Script',
                    version: '1.0',
                    namespace: '',
                    description: ''
                },
                scriptHandler: 'Kouke Browser',
                version: '1.0'
            };

            // Clipboard (requires user gesture)
            window.GM_setClipboard = function(data, type) {
                try {
                    navigator.clipboard.writeText(data);
                } catch (e) {
                    console.warn('[Kouke GM] GM_setClipboard error:', e);
                }
            };

            // Notification (uses browser notification API)
            window.GM_notification = function(details, ondone) {
                if (typeof details === 'string') {
                    details = { text: details };
                }
                try {
                    if (Notification.permission === 'granted') {
                        new Notification(details.title || 'Notification', {
                            body: details.text,
                            icon: details.image
                        });
                    } else if (Notification.permission !== 'denied') {
                        Notification.requestPermission().then(permission => {
                            if (permission === 'granted') {
                                new Notification(details.title || 'Notification', {
                                    body: details.text,
                                    icon: details.image
                                });
                            }
                        });
                    }
                } catch (e) {
                    console.warn('[Kouke GM] GM_notification error:', e);
                }
                if (ondone) ondone();
            };

            // GM.* style APIs (Promise-based)
            window.GM = {
                getValue: function(key, defaultValue) {
                    return Promise.resolve(GM_getValue(key, defaultValue));
                },
                setValue: function(key, value) {
                    GM_setValue(key, value);
                    return Promise.resolve();
                },
                deleteValue: function(key) {
                    GM_deleteValue(key);
                    return Promise.resolve();
                },
                listValues: function() {
                    return Promise.resolve(GM_listValues());
                },
                addStyle: function(css) {
                    return Promise.resolve(GM_addStyle(css));
                },
                addElement: function(parentNode, tagName, attributes) {
                    return Promise.resolve(GM_addElement(parentNode, tagName, attributes));
                },
                xmlHttpRequest: GM_xmlhttpRequest,
                openInTab: function(url, options) {
                    return Promise.resolve(GM_openInTab(url, options));
                },
                registerMenuCommand: function(name, callback, accessKey) {
                    return Promise.resolve(GM_registerMenuCommand(name, callback, accessKey));
                },
                getResourceText: function(name) {
                    return Promise.resolve(GM_getResourceText(name));
                },
                getResourceUrl: function(name) {
                    return Promise.resolve(GM_getResourceURL(name));
                },
                setClipboard: function(data, type) {
                    GM_setClipboard(data, type);
                    return Promise.resolve();
                },
                notification: function(details, ondone) {
                    GM_notification(details, ondone);
                    return Promise.resolve();
                },
                info: GM_info
            };

            // Also expose as globalThis for some scripts
            if (typeof globalThis !== 'undefined') {
                globalThis.GM = window.GM;
                globalThis.GM_getValue = window.GM_getValue;
                globalThis.GM_setValue = window.GM_setValue;
                globalThis.GM_deleteValue = window.GM_deleteValue;
                globalThis.GM_listValues = window.GM_listValues;
                globalThis.GM_addStyle = window.GM_addStyle;
                globalThis.GM_addElement = window.GM_addElement;
                globalThis.GM_xmlhttpRequest = window.GM_xmlhttpRequest;
                globalThis.GM_openInTab = window.GM_openInTab;
                globalThis.GM_registerMenuCommand = window.GM_registerMenuCommand;
                globalThis.GM_unregisterMenuCommand = window.GM_unregisterMenuCommand;
                globalThis.GM_getResourceText = window.GM_getResourceText;
                globalThis.GM_getResourceURL = window.GM_getResourceURL;
                globalThis.GM_log = window.GM_log;
                globalThis.GM_info = window.GM_info;
                globalThis.GM_setClipboard = window.GM_setClipboard;
                globalThis.GM_notification = window.GM_notification;
            }

            console.log('[Kouke GM] Greasemonkey API polyfill initialized');
        })();
        """
    }
}
