#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
OPEN_APP="${2:-open}"
BUNDLE_ID="${BUNDLE_ID:-com.lingsmbp.StatusTrio}"
APP_NAME="${APP_NAME:-Status Trio}"

case "$OPEN_APP" in
    open|no-open) ;;
    *)
        echo "Usage: $0 [configuration] [open|no-open]" >&2
        exit 2
        ;;
esac

if [[ ! "$BUNDLE_ID" =~ ^[A-Za-z0-9.-]+$ ]]; then
    echo "Error: BUNDLE_ID may contain only letters, numbers, periods, and hyphens." >&2
    exit 2
fi

if [[ -z "$APP_NAME" ]]; then
    echo "Error: APP_NAME must not be empty." >&2
    exit 2
fi

cd "$ROOT"

swift build -c "$CONFIGURATION"
BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$ROOT/dist/StatusTrio.app"
CONTENTS="$APP_DIR/Contents"
ICON_SOURCE="$ROOT/Support/AppIcon.svg"
ICONSET_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrio.XXXXXX")"
ICONSET_DIR="$ICONSET_ROOT/AppIcon.iconset"

trap 'rm -rf "$ICONSET_ROOT"' EXIT

sips -s format png -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_ROOT/AppIcon.png" >/dev/null
mkdir -p "$ICONSET_DIR"

while read -r pixel filename; do
    sips -z "$pixel" "$pixel" "$ICONSET_ROOT/AppIcon.png" --out "$ICONSET_DIR/$filename" >/dev/null
done <<'SIZES'
16 icon_16x16.png
32 icon_16x16@2x.png
32 icon_32x32.png
64 icon_32x32@2x.png
128 icon_128x128.png
256 icon_128x128@2x.png
256 icon_256x256.png
512 icon_256x256@2x.png
512 icon_512x512.png
1024 icon_512x512@2x.png
SIZES

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_PATH/StatusTrio" "$CONTENTS/MacOS/StatusTrio"
cp "$ROOT/Support/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$CONTENTS/Info.plist"
iconutil --convert icns --output "$CONTENTS/Resources/AppIcon.icns" "$ICONSET_DIR"

chmod +x "$CONTENTS/MacOS/StatusTrio"
codesign --force --sign - "$APP_DIR"

echo "Built $APP_DIR (bundle id: $BUNDLE_ID)"

if [[ "$OPEN_APP" == "open" ]]; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true

    for _ in {1..20}; do
        if [[ -z "$(lsappinfo find bundleID="$BUNDLE_ID" 2>/dev/null || true)" ]]; then
            break
        fi
        sleep 0.1
    done

    if [[ -n "$(lsappinfo find bundleID="$BUNDLE_ID" 2>/dev/null || true)" ]]; then
        echo "Error: $APP_NAME ($BUNDLE_ID) is still running after the graceful quit wait; refusing to open the rebuilt bundle." >&2
        exit 1
    fi

    open "$APP_DIR"
fi
