#!/usr/bin/env python3
"""
WebAuthn capability check.

Records what the browser can actually do with WebAuthn, so that the effect of
the Web Browser Public Key Credential entitlement can be measured rather than
assumed. Without that entitlement the API is present but no platform
authenticator is reachable, which is a state that looks identical to a broken
integration unless the baseline was captured first.

Two groups:

  * API surface — present today, and a regression if it ever disappears.
  * Platform authenticator — false today. Once Apple grants the entitlement and
    it is added to the entitlements file, these must flip to true. That flip is
    the acceptance test for passkey support.

Registration and assertion are deliberately not exercised: both need a user
gesture and raise system UI (Touch ID), which cannot be driven from a script
and should not be triggered on someone's machine by a test run.

Usage: scripts/verify-webauthn.py [--expect-entitlement] [--keep-running]
"""

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from spike_harness import (
    AppSession, SpikeFailure, check,
    GREEN, RED, RESET,
)

# WebAuthn is gated on a secure context, so the probe has to run against a real
# https origin rather than a local file.
PROBE_URL = "https://example.com"

PAGE_SETTLE_SECONDS = 2.0
ASYNC_POLL_ATTEMPTS = 20
ASYNC_POLL_INTERVAL_SECONDS = 0.5

# evaluateJavaScript cannot return a Promise, so async answers are parked on
# window and collected by a second, synchronous evaluation.
ASYNC_RESULT_GLOBAL = "__koukeWebAuthnProbe"
PENDING = "pending"

SURFACE_SCRIPT = """JSON.stringify({
  secureContext: window.isSecureContext,
  publicKeyCredential: typeof window.PublicKeyCredential,
  credentials: typeof navigator.credentials,
  create: typeof (navigator.credentials && navigator.credentials.create),
  get: typeof (navigator.credentials && navigator.credentials.get)
})"""

PLATFORM_SCRIPT = f"""
window.{ASYNC_RESULT_GLOBAL} = '{PENDING}';
Promise.all([
  PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable()
    .catch(e => 'error: ' + e),
  (PublicKeyCredential.isConditionalMediationAvailable
     ? PublicKeyCredential.isConditionalMediationAvailable().catch(e => 'error: ' + e)
     : 'absent')
]).then(([platform, conditional]) => {{
  window.{ASYNC_RESULT_GLOBAL} = JSON.stringify({{
    platformAuthenticator: platform,
    conditionalMediation: conditional
  }});
}}).catch(e => {{ window.{ASYNC_RESULT_GLOBAL} = 'error: ' + e; }});
'started'
"""


def load_probe_page(client):
    client.send("load_page", url=PROBE_URL)
    # The page has to finish enough of its load for window to be the real one;
    # the checks below read globals rather than DOM, so this is brief.
    time.sleep(PAGE_SETTLE_SECONDS)


def read_api_surface(client):
    return json.loads(client.send("eval_js", script=SURFACE_SCRIPT))


def read_platform_support(client):
    """Runs the async availability checks and waits for the parked answer."""
    client.send("eval_js", script=PLATFORM_SCRIPT)

    for _ in range(ASYNC_POLL_ATTEMPTS):
        time.sleep(ASYNC_POLL_INTERVAL_SECONDS)
        raw = client.send("eval_js", script=f"String(window.{ASYNC_RESULT_GLOBAL})")
        if raw != PENDING:
            if raw.startswith("error:"):
                raise SpikeFailure(f"platform availability check failed: {raw}")
            return json.loads(raw)

    raise SpikeFailure("platform availability check never resolved")


def verify_api_surface(client):
    """The WebAuthn API WKWebView hands to pages. Present without any entitlement."""
    print(f"\n{GREEN}1. WebAuthn API surface{RESET}")
    surface = read_api_surface(client)

    return [
        check("page is a secure context", surface["secureContext"] is True,
              f"got {surface['secureContext']}"),
        check("PublicKeyCredential is exposed",
              surface["publicKeyCredential"] == "function",
              f"got {surface['publicKeyCredential']}"),
        check("navigator.credentials is exposed",
              surface["credentials"] == "object",
              f"got {surface['credentials']}"),
        check("credentials.create is callable", surface["create"] == "function",
              f"got {surface['create']}"),
        check("credentials.get is callable", surface["get"] == "function",
              f"got {surface['get']}"),
    ]


def verify_platform_authenticator(client, expect_entitlement):
    """Reachability of iCloud Keychain passkeys — what the entitlement changes."""
    heading = ("2. Platform authenticator (entitlement expected)"
               if expect_entitlement
               else "2. Platform authenticator (baseline, no entitlement)")
    print(f"\n{GREEN}{heading}{RESET}")

    support = read_platform_support(client)
    platform = support["platformAuthenticator"]
    conditional = support["conditionalMediation"]

    if expect_entitlement:
        return [
            check("a platform authenticator is available", platform is True,
                  f"got {platform}"),
            check("conditional mediation is available", conditional is True,
                  f"got {conditional}"),
        ]

    return [
        check("no platform authenticator yet", platform is False,
              f"got {platform}"),
        check("no conditional mediation yet", conditional is False,
              f"got {conditional}"),
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expect-entitlement", action="store_true",
                        help="Assert passkeys ARE reachable. Use after Apple "
                             "grants com.apple.developer.web-browser."
                             "public-key-credential and it is added to the "
                             "entitlements file.")
    parser.add_argument("--keep-running", action="store_true",
                        help="Leave the app open after the run")
    args = parser.parse_args()

    session = AppSession()

    try:
        client = session.start()
        load_probe_page(client)
        results = verify_api_surface(client)
        results += verify_platform_authenticator(client, args.expect_entitlement)
    except SpikeFailure as error:
        print(f"\n{RED}HARNESS ERROR{RESET}: {error}", file=sys.stderr)
        return 2
    finally:
        if not args.keep_running:
            session.stop()

    passed = sum(1 for result in results if result)
    total = len(results)
    print(f"\n{'=' * 46}")
    if passed == total:
        print(f"{GREEN}WEBAUTHN CHECKS PASSED{RESET}  {passed}/{total}")
        return 0
    print(f"{RED}WEBAUTHN CHECKS FAILED{RESET}  {passed}/{total}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
