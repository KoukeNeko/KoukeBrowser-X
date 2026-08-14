#!/bin/bash
# Build a DEBUG kouke browser, launch it with a clean session, and run the
# tab bar / tab dragging verification suite.
#
# Usage: scripts/run-tabbar-verification.sh [derived-data-path]

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${1:-$PROJECT_DIR/.build/DerivedData}"
APP="$DERIVED_DATA/Build/Products/Debug/kouke browser.app"
DEBUG_DIR="$HOME/Library/Containers/dev.koukeneko.kouke-browser/Data/tmp/kouke-debug"
BUNDLE_ID="dev.koukeneko.kouke-browser"
READY_POLL_LIMIT=40

echo "==> Building"
xcodebuild -project "$PROJECT_DIR/kouke browser.xcodeproj" \
    -scheme "kouke browser" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    build 2>&1 | grep -E "^\*\* BUILD|error:" || true

if [ ! -d "$APP" ]; then
    echo "error: build produced no app at $APP" >&2
    exit 1
fi

echo "==> Restarting app with a clean session"
pkill -9 -f "kouke browser.app" 2>/dev/null
for _ in $(seq 1 30); do
    pgrep -f "kouke browser.app" > /dev/null || break
    sleep 0.5
done
defaults delete "$BUNDLE_ID" browserSession 2>/dev/null
rm -f "$DEBUG_DIR"/command.json "$DEBUG_DIR"/.seq
rm -f "$DEBUG_DIR"/result-*.json "$DEBUG_DIR"/snapshot-*.png
open "$APP"

echo "==> Waiting for the harness to report a window"
for _ in $(seq 1 $READY_POLL_LIMIT); do
    if "$PROJECT_DIR/scripts/kouke-debug.sh" '{"cmd": "state"}' > /dev/null 2>&1; then
        WINDOW_COUNT=$(python3 -c "
import json
print(len([w for w in json.load(open('$DEBUG_DIR/state.json'))['windows'] if 'tabs' in w]))
" 2>/dev/null || echo 0)
        [ "$WINDOW_COUNT" = "1" ] && break
    fi
    sleep 0.5
done

echo "==> Verifying"
python3 "$PROJECT_DIR/scripts/verify-tabbar.py"
