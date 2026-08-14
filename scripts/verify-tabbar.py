#!/usr/bin/env python3
"""End-to-end verification for the tab bar and tab drag features.

Drives a running DEBUG build of kouke browser through the DebugAutomation
file-command harness and asserts:
  1. Normal style renders the tab bar (tab pixels differ from bare background).
  2. Compact style renders as well.
  3. Detaching a tab creates a second window (drag-out path).
  4. Transferring the tab back merges windows and closes the empty one.
  5. Detaching the LAST tab moves the window (source closes, no empty husk).
  6. Dragging a tab cannot move the window: system window dragging is off and
     the tab strip / drag regions own the right areas.
  7. The tab bar keeps rendering after a page load.

Usage: python3 scripts/verify-tabbar.py
Requires: a DEBUG build of kouke browser already running.
"""

import json
import os
import sys
import time

BUNDLE_ID = os.environ.get("KOUKE_BUNDLE_ID", "dev.koukeneko.kouke-browser")
DEBUG_DIR = os.path.expanduser(
    f"~/Library/Containers/{BUNDLE_ID}/Data/tmp/kouke-debug"
)
COMMAND_FILE = os.path.join(DEBUG_DIR, "command.json")
STATE_FILE = os.path.join(DEBUG_DIR, "state.json")
RESULT_TIMEOUT_SECONDS = 10

failures = []


def send(command: dict) -> dict:
    """Send one command to the harness and wait for its result."""
    seq_file = os.path.join(DEBUG_DIR, ".seq")
    last_seq = 0
    if os.path.exists(seq_file):
        with open(seq_file) as f:
            last_seq = int(f.read().strip() or 0)
    seq = last_seq + 1
    with open(seq_file, "w") as f:
        f.write(str(seq))

    command = dict(command, seq=seq)
    with open(COMMAND_FILE, "w") as f:
        json.dump(command, f)

    result_file = os.path.join(DEBUG_DIR, f"result-{seq}.json")
    deadline = time.time() + RESULT_TIMEOUT_SECONDS
    while time.time() < deadline:
        if os.path.exists(result_file):
            with open(result_file) as f:
                return json.load(f)
        time.sleep(0.1)
    raise TimeoutError(f"no result for seq {seq} ({command['cmd']})")


def read_state() -> dict:
    send({"cmd": "state"})
    # state.json is written by the app; retry briefly in case of partial writes
    deadline = time.time() + 3
    while time.time() < deadline:
        try:
            with open(STATE_FILE) as f:
                return json.load(f)
        except (json.JSONDecodeError, FileNotFoundError):
            time.sleep(0.2)
    raise RuntimeError("could not read state.json")


def browser_windows(state: dict) -> list:
    return [w for w in state["windows"] if "tabs" in w]


def check(label: str, condition: bool, detail: str = ""):
    status = "PASS" if condition else "FAIL"
    print(f"[{status}] {label}" + (f" — {detail}" if detail else ""))
    if not condition:
        failures.append(label)


def tab_strip_has_content(window_number: int) -> bool:
    """The tab strip band must not be a uniform background color."""
    from PIL import Image

    snapshot = os.path.join(DEBUG_DIR, f"snapshot-{window_number}.png")
    image = Image.open(snapshot).convert("RGB")
    scale = 2 if image.size[0] > 2000 else 1
    strip_top, strip_bottom = 4 * scale, 36 * scale
    strip_left, strip_right = 90 * scale, 400 * scale
    colors = set()
    for y in range(strip_top, strip_bottom, 4):
        for x in range(strip_left, strip_right, 10):
            colors.add(image.getpixel((x, y)))
    return len(colors) > 3


def check_window_drag_isolation():
    """A press on a tab must reach the tab, never the window-drag machinery."""
    # Pin a known width so the probe points are certain to be inside the window:
    # x=200 lands on the first tab, and near the right edge is past the strip.
    probe_width = 1200
    send({"cmd": "window_frame", "w": probe_width, "h": 800})
    time.sleep(0.3)

    result = send({"cmd": "hittest",
                   "points": [[200, 20], [probe_width - 60, 20]]})
    report = result["message"]
    on_tab, on_empty = report.split(" | ")

    check("tab press hits the tab, not a drag region",
          "TabDragSourceView" in on_tab, on_tab.split(" < ")[0])
    check("empty tab bar area is a window drag region",
          "WindowDragRegionView" in on_empty, on_empty.split(" < ")[0])

    moved = send({"cmd": "window_frame"})["message"]
    check("system window dragging is disabled", "isMovable=false" in moved, moved)


def check_bar_survives_navigation():
    """The tab bar must keep drawing after a page load.

    A bar exactly as tall as the window's title bar renders completely blank —
    its content is never composited — and a title change is what exposes it.
    """
    send({"cmd": "add_tab", "url": "https://example.com"})
    time.sleep(2.5)
    send({"cmd": "snapshot"})
    window_number = browser_windows(read_state())[0]["windowNumber"]
    check("tab strip still renders after a page load",
          tab_strip_has_content(window_number))


def main():
    if not os.path.isdir(DEBUG_DIR):
        print("error: harness directory missing — run a DEBUG build first")
        sys.exit(2)

    state = read_state()
    windows = browser_windows(state)
    check("exactly one browser window at start", len(windows) == 1,
          f"found {len(windows)}")

    # 1-2. Both tab bar styles must render visible tab content.
    for style in ("normal", "compact"):
        send({"cmd": "set_style", "value": style})
        time.sleep(1.0)
        send({"cmd": "snapshot"})
        # Resolve the window after the snapshot: an app relaunch between calls
        # would otherwise leave us checking a stale window number.
        window_number = browser_windows(read_state())[0]["windowNumber"]
        check(f"{style} style renders tab strip", tab_strip_has_content(window_number))

    send({"cmd": "set_style", "value": "normal"})
    time.sleep(1.0)
    home = browser_windows(read_state())[0]["windowNumber"]

    # 3. Detach: second-to-last tab -> new window appears.
    send({"cmd": "add_tab", "url": "kouke:blank"})
    time.sleep(0.5)
    send({"cmd": "detach_active"})
    time.sleep(1.5)
    windows = browser_windows(read_state())
    check("detach creates a second window", len(windows) == 2,
          f"found {len(windows)}")

    # 4. Transfer back: windows merge, empty window closes.
    if len(windows) == 2:
        source = next(w for w in windows if w["windowNumber"] != home)
        tab_id = source["tabs"][0]["id"]
        send({"cmd": "transfer", "from": source["windowNumber"],
              "to": home, "tab": tab_id})
        time.sleep(2.0)
        windows = browser_windows(read_state())
        check("transfer back merges windows", len(windows) == 1,
              f"found {len(windows)}")
        if len(windows) == 1:
            check("home window has both tabs", len(windows[0]["tabs"]) == 2,
                  f"found {len(windows[0]['tabs'])}")

    # 5. Detach last tab: window moves (old window closes, count stays equal).
    windows = browser_windows(read_state())
    if windows and len(windows[0]["tabs"]) == 2:
        send({"cmd": "detach_active", "window": home})
        time.sleep(1.5)
        windows = browser_windows(read_state())
        two_singles = (len(windows) == 2 and
                       all(len(w["tabs"]) == 1 for w in windows))
        check("state ready for last-tab detach", two_singles)
        if two_singles:
            lone = windows[0]["windowNumber"]
            send({"cmd": "detach_active", "window": lone})
            time.sleep(2.5)
            windows = browser_windows(read_state())
            husks = [w for w in windows if len(w["tabs"]) == 0]
            check("last-tab detach leaves no empty window",
                  len(husks) == 0 and len(windows) == 2,
                  f"windows={[(w['windowNumber'], len(w['tabs'])) for w in windows]}")

    check_window_drag_isolation()
    check_bar_survives_navigation()

    print()
    if failures:
        print(f"RESULT: FAIL ({len(failures)} failing checks)")
        sys.exit(1)
    print("RESULT: PASS")


if __name__ == "__main__":
    main()
