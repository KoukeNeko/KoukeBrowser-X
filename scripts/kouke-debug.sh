#!/bin/bash
# Send a command to the DEBUG automation harness inside kouke browser and print the result.
# Usage: kouke-debug.sh '{"cmd": "snapshot"}'
# The seq number is managed automatically.

set -euo pipefail

DEBUG_DIR="$HOME/Library/Containers/dev.koukeneko.kouke-browser/Data/tmp/kouke-debug"
SEQ_FILE="$DEBUG_DIR/.seq"
RESULT_TIMEOUT_SECONDS=5

if [ ! -d "$DEBUG_DIR" ]; then
    echo "error: $DEBUG_DIR missing - is a DEBUG build of kouke browser running?" >&2
    exit 1
fi

LAST_SEQ=$(cat "$SEQ_FILE" 2>/dev/null || echo 0)
NEXT_SEQ=$((LAST_SEQ + 1))
echo "$NEXT_SEQ" > "$SEQ_FILE"

COMMAND_JSON=$(echo "$1" | python3 -c "
import json, sys
payload = json.load(sys.stdin)
payload['seq'] = $NEXT_SEQ
print(json.dumps(payload))
")

echo "$COMMAND_JSON" > "$DEBUG_DIR/command.json"

RESULT_FILE="$DEBUG_DIR/result-$NEXT_SEQ.json"
for _ in $(seq 1 $((RESULT_TIMEOUT_SECONDS * 10))); do
    if [ -f "$RESULT_FILE" ]; then
        cat "$RESULT_FILE"
        echo
        exit 0
    fi
    sleep 0.1
done

echo "error: no result for seq $NEXT_SEQ within ${RESULT_TIMEOUT_SECONDS}s" >&2
exit 1
