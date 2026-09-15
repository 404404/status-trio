#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="$ROOT/release.json"

read_config() {
    ruby -rjson -e 'value = JSON.parse(File.read(ARGV[0])); ARGV[1].split(".").each { |key| value = value.fetch(key) }; print value' "$CONFIG_PATH" "$1"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || { echo "Error: required command '$1' is not available." >&2; exit 1; }
}

for command in ruby swift hdiutil shasum plutil ditto file lipo otool /usr/bin/codesign /usr/bin/xcrun; do require_command "$command"; done
cd "$ROOT"

APP_NAME="${APP_NAME:-$(read_config app_name)}"
BUNDLE_ID="${BUNDLE_ID:-$(read_config bundle_id)}"
RELEASE_REPO="${RELEASE_REPO:-$(read_config github_repo)}"
RELEASE_BRANCH="${RELEASE_BRANCH:-$(read_config git_branch)}"
MINIMUM_SYSTEM_VERSION="${MINIMUM_SYSTEM_VERSION:-$(read_config min_system_version)}"
APPCAST_FILE="${APPCAST_FILE:-$(read_config appcast_file)}"
DMG_BASENAME="$(read_config dmg_name)"
DMG_BASENAME="${DMG_BASENAME%.dmg}"
SPARKLE_ENABLED_DEFAULT="$(read_config sparkle_enabled)"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)}"
FORK_REVISION="${FORK_REVISION:-$(/usr/libexec/PlistBuddy -c 'Print :StatusTrioForkRevision' Support/Info.plist)}"
BUILD="${BUILD:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Support/Info.plist)}"
TAG="${TAG:-v$VERSION-fork.$FORK_REVISION}"
PUBLISH="${PUBLISH:-true}"
PUBLISH_APPCAST="${PUBLISH_APPCAST:-$SPARKLE_ENABLED_DEFAULT}"
UNIVERSAL_BUILD="${UNIVERSAL_BUILD:-1}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/dist}"
RELEASE_TARGET="${RELEASE_TARGET:-$(git rev-parse HEAD)}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
KEYCHAIN_PATH="${KEYCHAIN_PATH:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"
SU_FEED_URL="${SU_FEED_URL:-}"

[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "Error: VERSION must contain dot-separated numbers." >&2; exit 2; }
[[ "$FORK_REVISION" =~ ^[0-9]+$ && "$FORK_REVISION" != "0" ]] || { echo "Error: FORK_REVISION must be a positive integer." >&2; exit 2; }
[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "Error: BUILD must contain only digits." >&2; exit 2; }
EXPECTED_TAG="v${VERSION}-fork.${FORK_REVISION}"
[[ "$TAG" == "$EXPECTED_TAG" ]] || { echo "Error: TAG must be $EXPECTED_TAG." >&2; exit 2; }
case "$PUBLISH" in true|false) ;; *) echo "Error: PUBLISH must be true or false." >&2; exit 2 ;; esac
case "$PUBLISH_APPCAST" in true|false) ;; *) echo "Error: PUBLISH_APPCAST must be true or false." >&2; exit 2 ;; esac
case "$UNIVERSAL_BUILD" in 0|1) ;; *) echo "Error: UNIVERSAL_BUILD must be 0 or 1." >&2; exit 2 ;; esac
if [[ -n "$NOTARY_PROFILE" && "$CODE_SIGN_IDENTITY" == "-" ]]; then echo "Error: NOTARY_PROFILE requires Developer ID signing." >&2; exit 2; fi
if ! git rev-parse --verify "$RELEASE_TARGET^{commit}" >/dev/null 2>&1; then echo "Error: RELEASE_TARGET is not a checkout commit." >&2; exit 2; fi
RELEASE_TARGET="$(git rev-parse "$RELEASE_TARGET^{commit}")"

if [[ "$PUBLISH_APPCAST" == "true" ]]; then
    [[ "$PUBLISH" == "true" ]] || { echo "Error: PUBLISH_APPCAST=true requires PUBLISH=true." >&2; exit 2; }
    [[ -n "$SPARKLE_PRIVATE_KEY" && -n "$SPARKLE_PUBLIC_KEY" ]] || { echo "Error: signed Sparkle publication requires SPARKLE_PRIVATE_KEY and SPARKLE_PUBLIC_KEY." >&2; exit 2; }
    SU_FEED_URL="${SU_FEED_URL:-https://raw.githubusercontent.com/$RELEASE_REPO/$RELEASE_BRANCH/$APPCAST_FILE}"
    [[ "$SU_FEED_URL" == https://* ]] || { echo "Error: SU_FEED_URL must use HTTPS." >&2; exit 2; }
elif [[ -n "$SU_FEED_URL" ]]; then
    echo "Error: SU_FEED_URL is valid only when PUBLISH_APPCAST=true." >&2
    exit 2
fi

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioRelease.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT
APPCAST_PATH="$TEMP_ROOT/appcast.xml"
APPCAST_SHA=""

if [[ "$PUBLISH" == "true" ]]; then
    require_command gh
    if [[ -z "${GH_TOKEN:-}" ]] && ! gh auth status >/dev/null 2>&1; then echo "Error: gh is not authenticated." >&2; exit 1; fi
    RELEASE_REPO="$RELEASE_REPO" BUNDLE_ID="$BUNDLE_ID" BUILD="$BUILD" ruby "$ROOT/scripts/validate-release-history.rb"
fi
if [[ "$PUBLISH_APPCAST" == "true" ]]; then
    require_command xmllint
    [[ "$(gh repo view "$RELEASE_REPO" --json visibility --jq .visibility)" == "PUBLIC" ]] || { echo "Error: signed Sparkle updates require a public repository." >&2; exit 1; }
    APPCAST_SHA="$(gh api "repos/$RELEASE_REPO/contents/$APPCAST_FILE?ref=$RELEASE_BRANCH" --jq .sha)"
    gh api "repos/$RELEASE_REPO/contents/$APPCAST_FILE?ref=$RELEASE_BRANCH" -H "Accept: application/vnd.github.raw" > "$APPCAST_PATH"
    ruby -e 'build = ARGV[0].to_i; max = File.read(ARGV[1]).scan(%r{<sparkle:version>\s*(\d+)\s*</sparkle:version>}).flatten.map(&:to_i).max || 0; abort("Error: build must exceed the latest Sparkle build.") unless build > max' "$BUILD" "$APPCAST_PATH"
fi

if [[ -z "${RELEASE_NOTES_FILE:-}" ]]; then RELEASE_NOTES_FILE="$TEMP_ROOT/release-notes.md"; printf "%s\n" "- Release v$VERSION-fork.$FORK_REVISION." > "$RELEASE_NOTES_FILE"; fi
RELEASE_BODY_FILE="${RELEASE_BODY_FILE:-$RELEASE_NOTES_FILE}"
[[ -f "$RELEASE_NOTES_FILE" && -f "$RELEASE_BODY_FILE" ]] || { echo "Error: release notes file does not exist." >&2; exit 1; }
if [[ "$PUBLISH_APPCAST" == "true" ]]; then
    APPCAST_RELEASE_NOTES_FILE="${APPCAST_RELEASE_NOTES_FILE:-$RELEASE_BODY_FILE}"
    [[ -f "$APPCAST_RELEASE_NOTES_FILE" ]] || { echo "Error: appcast release notes file does not exist." >&2; exit 1; }
    UPDATE_MODE=1
else
    UPDATE_MODE=0
fi

mkdir -p "$OUTPUT_DIR"
echo "Building $APP_NAME $VERSION ($BUILD) for $RELEASE_REPO..."
env -u GH_TOKEN -u SPARKLE_PRIVATE_KEY APP_VERSION="$VERSION" FORK_REVISION="$FORK_REVISION" BUILD_NUMBER="$BUILD" SU_FEED_URL="$SU_FEED_URL" SPARKLE_PUBLIC_KEY="$SPARKLE_PUBLIC_KEY" AUTOMATIC_UPDATES_ENABLED="$UPDATE_MODE" UNIVERSAL_BUILD="$UNIVERSAL_BUILD" BUNDLE_ID="$BUNDLE_ID" APP_NAME="$APP_NAME" CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" KEYCHAIN_PATH="$KEYCHAIN_PATH" bash "$ROOT/scripts/build-app.sh" release no-open

STAGING_DIR="$TEMP_ROOT/dmg"
mkdir -p "$STAGING_DIR"
ditto "$ROOT/dist/StatusTrio.app" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
DMG_PATH="$OUTPUT_DIR/$DMG_BASENAME-$VERSION-fork.$FORK_REVISION.dmg"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
hdiutil verify "$DMG_PATH"
MOUNT_POINT="$TEMP_ROOT/mount"
mkdir -p "$MOUNT_POINT"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$DMG_PATH"
if [[ ! -d "$MOUNT_POINT/$APP_NAME.app" || ! -L "$MOUNT_POINT/Applications" || "$(readlink "$MOUNT_POINT/Applications")" != "/Applications" ]]; then
    hdiutil detach -quiet "$MOUNT_POINT" || true
    echo "Error: DMG must contain $APP_NAME.app and an Applications shortcut." >&2
    exit 1
fi
hdiutil detach -quiet "$MOUNT_POINT"
if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
fi

ED_SIGNATURE=""
DMG_LENGTH=""
if [[ "$PUBLISH_APPCAST" == "true" ]]; then
    SIGN_UPDATE="${SIGN_UPDATE:-$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update}"
    [[ -x "$SIGN_UPDATE" ]] || { echo "Error: Sparkle sign_update was not found." >&2; exit 1; }
    SIGN_OUTPUT="$(printf "%s" "$SPARKLE_PRIVATE_KEY" | env -u SPARKLE_PRIVATE_KEY "$SIGN_UPDATE" --ed-key-file - "$DMG_PATH")"
    ED_SIGNATURE="$(printf "%s\n" "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
    DMG_LENGTH="$(printf "%s\n" "$SIGN_OUTPUT" | sed -n 's/.*length="\([0-9][0-9]*\)".*/\1/p')"
    [[ -n "$ED_SIGNATURE" && -n "$DMG_LENGTH" ]] || { echo "Error: could not parse Sparkle signature output." >&2; exit 1; }
fi

DMG_FILENAME="$(basename "$DMG_PATH")"
(cd "$OUTPUT_DIR" && shasum -a 256 "$DMG_FILENAME" > "$DMG_FILENAME.sha256")
APP_PLIST="$ROOT/dist/StatusTrio.app/Contents/Info.plist"
ACTUAL_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PLIST")"
ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PLIST")"
ACTUAL_BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PLIST")"
[[ "$ACTUAL_BUNDLE_ID" == "$BUNDLE_ID" && "$ACTUAL_VERSION" == "$VERSION" && "$ACTUAL_BUILD" == "$BUILD" ]] || { echo "Error: built app metadata does not match release inputs." >&2; exit 1; }
DMG_SHA256="$(cut -d " " -f 1 "$DMG_PATH.sha256")"
METADATA_PATH="$OUTPUT_DIR/$DMG_FILENAME.release-metadata.json"
ruby -rjson -e 'puts JSON.generate(schema_version: 1, bundle_id: ARGV[0], version: ARGV[1], fork_revision: ARGV[2], build: ARGV[3], source_sha: ARGV[4], dmg_filename: ARGV[5], sha256: ARGV[6])' "$ACTUAL_BUNDLE_ID" "$ACTUAL_VERSION" "$FORK_REVISION" "$ACTUAL_BUILD" "$RELEASE_TARGET" "$DMG_FILENAME" "$DMG_SHA256" > "$METADATA_PATH"
DMG_URL="https://github.com/$RELEASE_REPO/releases/download/$TAG/$DMG_FILENAME"
{
    printf "VERSION=%q\n" "$VERSION"
    printf "FORK_REVISION=%q\n" "$FORK_REVISION"
    printf "BUILD=%q\n" "$BUILD"
    printf "TAG=%q\n" "$TAG"
    printf "RELEASE_TARGET=%q\n" "$RELEASE_TARGET"
    printf "PUBLISH_APPCAST=%q\n" "$PUBLISH_APPCAST"
    printf "APP_NAME=%q\n" "$APP_NAME"
    printf "BUNDLE_ID=%q\n" "$BUNDLE_ID"
    printf "RELEASE_REPO=%q\n" "$RELEASE_REPO"
    printf "SU_FEED_URL=%q\n" "$SU_FEED_URL"
    printf "DMG_PATH=%q\n" "$DMG_PATH"
    printf "DMG_URL=%q\n" "$DMG_URL"
    printf "ED_SIGNATURE=%q\n" "$ED_SIGNATURE"
    printf "DMG_LENGTH=%q\n" "$DMG_LENGTH"
} > "$OUTPUT_DIR/release.env"

if [[ "$PUBLISH" == "false" ]]; then echo "Built $DMG_PATH without publishing (Sparkle: $PUBLISH_APPCAST)."; exit 0; fi
if gh release view "$TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then echo "Error: GitHub Release $TAG already exists." >&2; exit 1; fi
if gh api "repos/$RELEASE_REPO/git/ref/tags/$TAG" >/dev/null 2>&1; then echo "Error: Git tag $TAG already exists; refusing to reuse or move it." >&2; exit 1; fi

RELEASE_REPO="$RELEASE_REPO" BUNDLE_ID="$BUNDLE_ID" BUILD="$BUILD" ruby "$ROOT/scripts/validate-release-history.rb"
gh release create "$TAG" "$DMG_PATH" "$DMG_PATH.sha256" "$METADATA_PATH" --repo "$RELEASE_REPO" --target "$RELEASE_TARGET" --title "$APP_NAME $VERSION — Fork $FORK_REVISION" --latest --notes-file "$RELEASE_BODY_FILE"
PUBLISHED_TAG_SHA="$(gh api "repos/$RELEASE_REPO/git/ref/tags/$TAG" --jq .object.sha)"
[[ "$PUBLISHED_TAG_SHA" == "$RELEASE_TARGET" ]] || { echo "Error: release tag does not point to the built commit." >&2; exit 1; }

if [[ "$PUBLISH_APPCAST" == "true" ]]; then
    ruby "$ROOT/scripts/update-appcast.rb" "$VERSION" "$BUILD" "$MINIMUM_SYSTEM_VERSION" "$DMG_URL" "$ED_SIGNATURE" "$DMG_LENGTH" "$APPCAST_RELEASE_NOTES_FILE" "$APPCAST_PATH"
    xmllint --noout "$APPCAST_PATH"
    ruby -rjson -rbase64 -e 'puts JSON.generate(message: ARGV[0], content: Base64.strict_encode64(File.binread(ARGV[1])), sha: ARGV[2], branch: ARGV[3])' "Release $TAG appcast" "$APPCAST_PATH" "$APPCAST_SHA" "$RELEASE_BRANCH" | gh api --method PUT "repos/$RELEASE_REPO/contents/$APPCAST_FILE" -H "Accept: application/vnd.github+json" --input - >/dev/null
    gh api "repos/$RELEASE_REPO/contents/$APPCAST_FILE?ref=$RELEASE_BRANCH" -H "Accept: application/vnd.github.raw" | grep -Fq "<sparkle:version>$BUILD</sparkle:version>" || { echo "Error: published appcast does not contain build $BUILD." >&2; exit 1; }
    echo "Published $DMG_URL with signed Sparkle appcast $SU_FEED_URL"
else
    echo "Published $DMG_URL (GitHub Release only; Sparkle disabled)."
fi
