#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
OPEN_APP="${2:-open}"

case "$OPEN_APP" in
    open|no-open) ;;
    *)
        echo "Usage: $0 [configuration] [open|no-open]" >&2
        exit 2
        ;;
esac

cd "$ROOT"

swift build -c "$CONFIGURATION"
BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$ROOT/dist/StatusTrio.app"
CONTENTS="$APP_DIR/Contents"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_PATH/StatusTrio" "$CONTENTS/MacOS/StatusTrio"
cp "$ROOT/Support/Info.plist" "$CONTENTS/Info.plist"

chmod +x "$CONTENTS/MacOS/StatusTrio"
codesign --force --sign - "$APP_DIR"

echo "Built $APP_DIR"

if [[ "$OPEN_APP" == "open" ]]; then
    osascript -e 'tell application id "com.lingsmbp.StatusTrio" to quit' >/dev/null 2>&1 || true

    for _ in {1..20}; do
        if [[ -z "$(lsappinfo find bundleID=com.lingsmbp.StatusTrio 2>/dev/null || true)" ]]; then
            break
        fi
        sleep 0.1
    done

    if [[ -n "$(lsappinfo find bundleID=com.lingsmbp.StatusTrio 2>/dev/null || true)" ]]; then
        echo "Error: Status Trio (com.lingsmbp.StatusTrio) is still running after the graceful quit wait; refusing to open the rebuilt bundle." >&2
        exit 1
    fi

    open "$APP_DIR"
fi
