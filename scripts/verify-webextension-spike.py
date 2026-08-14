#!/usr/bin/env python3
"""
Phase 0 spike verification.

Answers one question automatically: can a Manifest V3 extension load into this
browser and do what a password manager needs — inject a content script, find a
login form, fill it, and talk to its background service worker?

Exits 0 only if every check passes.

Usage:
  scripts/verify-webextension-spike.py
  scripts/verify-webextension-spike.py --extension-bundle \\
      /Applications/Bitwarden.app/Contents/PlugIns/safari.appex
"""

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from spike_harness import (
    AppSession, FixtureServer, SpikeFailure, check,
    FIXTURES_DIR, GREEN, RED, YELLOW, RESET,
)

CONTENT_SCRIPT_SETTLE_SECONDS = 5

# Counts DOM nodes a browser extension injected. Extensions cannot reach the
# page without content scripts, so any custom element or extension-scheme node
# is evidence that injection reached this document.
INJECTION_PROBE_JS = """
(() => {
  const customElements = [...document.querySelectorAll('*')]
    .filter(node => node.tagName.includes('-')).length;
  const extensionFrames = [...document.querySelectorAll('iframe')]
    .filter(frame => (frame.src || '').includes('-extension://')).length;
  return `customElements=${customElements} extensionFrames=${extensionFrames}`;
})()
"""


def verify_third_party_extension(client, report, page_url, results):
    """A third-party extension has its own UI and vault state, so the probe's
    DOM marker never appears. What can be checked without signing in is that it
    loads cleanly and that a page still loads with it active.
    """
    print(f"\n{YELLOW}2. Loading login page{RESET}")
    loaded = json.loads(client.send("load_page", url=page_url, timeout=90))
    results.append(check("page loaded with extension active", True,
                         loaded.get("loaded", "")))

    print(f"\n{YELLOW}3. Looking for injected content (informational){RESET}")
    time.sleep(CONTENT_SCRIPT_SETTLE_SECONDS)
    injected = client.send("eval_js", script=INJECTION_PROBE_JS, timeout=30)
    print(f"  DOM probe: {injected}")
    print("  Note: a locked vault injects no visible UI, so this is reported")
    print("  but not asserted. Signing in is out of scope for an automated run.")
    return results


def verify_probe_extension(client, report, page_url, results):
    results.append(check("manifest v3", report.get("manifestVersion") == 3,
                         f"got {report.get('manifestVersion')}"))

    print(f"\n{YELLOW}2. Loading login page{RESET}")
    loaded = json.loads(client.send("load_page", url=page_url))
    results.append(check("fixture page loaded", True, loaded.get("loaded", "")))

    print(f"\n{YELLOW}3. Reading content script result{RESET}")
    try:
        marker = json.loads(client.send("read_spike_result"))
        print(json.dumps(marker, indent=2))
    except SpikeFailure as error:
        results.append(check("content script published a result", False, str(error)))
        return results

    results.extend([
        check("content script ran", marker.get("contentScriptRan") is True),
        check("login form found", marker.get("formFound") is True),
        check("username field filled", marker.get("usernameFilled") is True),
        check("password field filled", marker.get("passwordFilled") is True),
        check("background service worker reachable", marker.get("backgroundReachable") is True,
              str(marker.get("backgroundDetail"))),
        check("no content script error", marker.get("error") is None,
              str(marker.get("error"))),
    ])
    return results


def run_spike(client, extension_argument, page_url, is_probe_extension):
    print(f"\n{YELLOW}1. Loading extension{RESET}")
    report = json.loads(client.send("load_extension", timeout=90, **extension_argument))
    print(json.dumps(report, indent=2))

    results = [
        check("extension parsed without errors", not report["parseErrors"],
              "; ".join(report["parseErrors"])),
        check("declares background content", report["hasBackgroundContent"]),
        check("declares injected content", report["hasInjectedContent"]),
        check("background content started", report.get("backgroundLoadError") is None,
              report.get("backgroundLoadError") or ""),
    ]

    if is_probe_extension:
        return verify_probe_extension(client, report, page_url, results)
    return verify_third_party_extension(client, report, page_url, results)


def resolve_extension_argument(args):
    """Returns (command kwargs, is_probe_extension, description)."""
    if args.extension_bundle:
        bundle_path = Path(args.extension_bundle).expanduser().resolve()
        if not bundle_path.exists():
            raise SpikeFailure(f"no bundle at {bundle_path}")
        return {"bundle": str(bundle_path)}, False, f"{bundle_path} (app extension bundle)"

    extension_source = Path(args.extension).expanduser().resolve()
    if not (extension_source / "manifest.json").exists():
        raise SpikeFailure(f"no manifest.json in {extension_source}")
    return {"path": str(extension_source)}, True, str(extension_source)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--extension",
        default=str(FIXTURES_DIR / "test-extension"),
        help="Path to an unpacked extension directory (defaults to the spike probe)",
    )
    parser.add_argument(
        "--extension-bundle",
        help="Path to a Safari app extension bundle (.appex) to load instead, "
             "e.g. /Applications/Bitwarden.app/Contents/PlugIns/safari.appex",
    )
    parser.add_argument("--keep-running", action="store_true",
                        help="Leave the app open after the run")
    args = parser.parse_args()

    try:
        extension_argument, is_probe_extension, description = resolve_extension_argument(args)
    except SpikeFailure as error:
        print(f"{RED}ERROR{RESET}: {error}", file=sys.stderr)
        return 2

    print(f"Extension under test: {description}")

    session = AppSession()
    server = FixtureServer(FIXTURES_DIR / "pages").start()
    page_url = f"{server.base_url}/standard-login.html"
    print(f"Serving fixtures at: {server.base_url}")

    try:
        client = session.start()
        results = run_spike(client, extension_argument, page_url, is_probe_extension)
    except SpikeFailure as error:
        print(f"\n{RED}HARNESS ERROR{RESET}: {error}", file=sys.stderr)
        return 2
    finally:
        server.stop()
        if not args.keep_running:
            session.stop()

    passed = sum(1 for result in results if result)
    total = len(results)
    print(f"\n{'=' * 46}")
    if passed == total:
        print(f"{GREEN}SPIKE PASSED{RESET}  {passed}/{total} checks")
        return 0
    print(f"{RED}SPIKE FAILED{RESET}  {passed}/{total} checks")
    return 1


if __name__ == "__main__":
    sys.exit(main())
