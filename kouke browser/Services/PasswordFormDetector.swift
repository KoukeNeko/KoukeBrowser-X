//
//  PasswordFormDetector.swift
//  kouke browser
//
//  Generates the page-side half of password autofill.
//
//  Follows the existing injected-service convention (see SponsorBlockService)
//  of exposing the script as a string from a `getUserScript()`-style call.
//
//  The script only ever reports and fills on request. It never decides which
//  credentials exist, never learns the origin it is running on, and never
//  submits a form — those decisions belong to the native side, because a page
//  can rewrite anything in its own JavaScript context.
//

import Foundation

enum PasswordFormDetector {

    /// Namespace the page script installs itself under.
    static let namespace = "__koukeAutofill"

    /// Message handler name registered on the WKWebView.
    static let messageHandlerName = "koukeAutofill"

    /// Smallest rendered size, in CSS pixels, for a field to count as visible.
    ///
    /// Credential-stealing pages hide a login form with clipping or a 1px box
    /// and wait for a password manager to fill it.
    private static let minimumVisibleDimension = 8

    static func getUserScript() -> String {
        """
        (() => {
          'use strict';
          if (window.\(namespace)) { return; }

          const MIN_VISIBLE = \(minimumVisibleDimension);
          const HANDLER = '\(messageHandlerName)';

          function post(payload) {
            try {
              window.webkit.messageHandlers[HANDLER].postMessage(payload);
            } catch (error) {
              // No handler on this frame; reporting is best effort.
            }
          }

          // A field the user cannot see is a field the user cannot have meant
          // to fill, so hidden inputs are treated as traps rather than targets.
          //
          // Checking the field's own box is not enough. A page hides a form by
          // styling an ancestor — clipping it to a pixel, or fading it to zero
          // opacity — while the input inside keeps its natural size and its own
          // computed opacity of 1. Both cases have to be caught by walking up.
          function isClippedByAncestor(element) {
            const rect = element.getBoundingClientRect();

            for (let parent = element.parentElement; parent; parent = parent.parentElement) {
              const style = window.getComputedStyle(parent);
              if (style.overflow === 'visible' && style.overflowX === 'visible') { continue; }

              const parentRect = parent.getBoundingClientRect();
              if (parentRect.width < MIN_VISIBLE || parentRect.height < MIN_VISIBLE) { return true; }

              const overlapWidth = Math.min(rect.right, parentRect.right) - Math.max(rect.left, parentRect.left);
              const overlapHeight = Math.min(rect.bottom, parentRect.bottom) - Math.max(rect.top, parentRect.top);
              if (overlapWidth < MIN_VISIBLE || overlapHeight < MIN_VISIBLE) { return true; }
            }
            return false;
          }

          function isFadedByAncestor(element) {
            for (let node = element; node; node = node.parentElement) {
              if (parseFloat(window.getComputedStyle(node).opacity) === 0) { return true; }
            }
            return false;
          }

          function isVisible(element) {
            if (!element || element.type === 'hidden' || element.disabled) { return false; }

            // Resolves display, visibility and ancestor opacity in one call
            // where supported; the explicit walks below cover the rest.
            if (typeof element.checkVisibility === 'function') {
              if (!element.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true })) {
                return false;
              }
            }

            const rect = element.getBoundingClientRect();
            if (rect.width < MIN_VISIBLE || rect.height < MIN_VISIBLE) { return false; }

            const style = window.getComputedStyle(element);
            if (style.visibility === 'hidden' || style.display === 'none') { return false; }

            if (isFadedByAncestor(element)) { return false; }
            if (isClippedByAncestor(element)) { return false; }

            return true;
          }

          const USERNAME_SELECTOR = [
            'input[autocomplete="username"]',
            'input[type="email"]',
            'input[name*="user" i]',
            'input[name*="email" i]',
            'input[id*="user" i]',
            'input[id*="email" i]',
            'input[type="text"]'
          ].join(',');

          // Preferred over document order: the username box for a password is
          // the visible text field closest above it, even on pages that hold
          // several forms.
          function findUsernameField(passwordField) {
            const scope = passwordField.form || document;
            const candidates = [...scope.querySelectorAll(USERNAME_SELECTOR)].filter(isVisible);
            if (candidates.length === 0) { return null; }

            const preceding = candidates.filter(candidate =>
              passwordField.compareDocumentPosition(candidate) & Node.DOCUMENT_POSITION_PRECEDING);

            return preceding.length > 0 ? preceding[preceding.length - 1] : candidates[0];
          }

          function findLoginForm() {
            const passwordField = [...document.querySelectorAll('input[type="password"]')]
              .find(isVisible);
            if (!passwordField) { return null; }
            return { passwordField, usernameField: findUsernameField(passwordField) };
          }

          function describe() {
            const form = findLoginForm();
            if (!form) { return { hasLoginForm: false }; }
            return {
              hasLoginForm: true,
              hasUsernameField: form.usernameField !== null,
              usernameValue: form.usernameField ? form.usernameField.value : ''
            };
          }

          // Frameworks track their own state and ignore direct value writes, so
          // each field is set through its native setter and then told the value
          // changed the same way a keystroke would.
          function setFieldValue(field, value) {
            const prototype = Object.getPrototypeOf(field);
            const descriptor = Object.getOwnPropertyDescriptor(prototype, 'value');
            if (descriptor && descriptor.set) {
              descriptor.set.call(field, value);
            } else {
              field.value = value;
            }
            field.dispatchEvent(new Event('input', { bubbles: true }));
            field.dispatchEvent(new Event('change', { bubbles: true }));
          }

          function fill(username, password) {
            const form = findLoginForm();
            if (!form) { return { filled: false, reason: 'no-login-form' }; }

            if (form.usernameField && typeof username === 'string' && username.length > 0) {
              setFieldValue(form.usernameField, username);
            }
            setFieldValue(form.passwordField, password);

            // Deliberately does not submit: sending the form is the user's
            // decision, never the browser's.
            return { filled: true, submitted: false };
          }

          function reportSubmission() {
            const form = findLoginForm();
            if (!form || !form.passwordField.value) { return; }
            post({
              type: 'submit',
              username: form.usernameField ? form.usernameField.value : '',
              password: form.passwordField.value
            });
          }

          document.addEventListener('submit', reportSubmission, true);

          // Many sign-in flows never fire a real submit event, so a click on the
          // button that holds the password field is treated the same way.
          document.addEventListener('click', (event) => {
            const target = event.target.closest('button, input[type="submit"]');
            if (target) { reportSubmission(); }
          }, true);

          window.\(namespace) = { describe, fill };

          function reportDetection() {
            const description = describe();
            if (description.hasLoginForm) {
              post({ type: 'detected', ...description });
            }
          }

          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', reportDetection);
          } else {
            reportDetection();
          }
        })();
        """
    }

    /// Expression evaluated natively to fill a credential.
    ///
    /// Values are passed as JSON literals so a password containing quotes or
    /// newlines cannot terminate the expression and run as code.
    static func fillExpression(username: String, password: String) -> String? {
        guard let usernameLiteral = jsonLiteral(username),
              let passwordLiteral = jsonLiteral(password) else {
            return nil
        }
        return "JSON.stringify(window.\(namespace).fill(\(usernameLiteral), \(passwordLiteral)))"
    }

    /// Expression evaluated natively to inspect the current page.
    static var describeExpression: String {
        "JSON.stringify(window.\(namespace) ? window.\(namespace).describe() : {hasLoginForm:false})"
    }

    private static func jsonLiteral(_ value: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let array = String(data: data, encoding: .utf8) else {
            return nil
        }
        return String(array.dropFirst().dropLast())
    }
}
