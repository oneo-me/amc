#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C
export LANG=C

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$ROOT_DIR/source/AMC.xcodeproj"
SCHEME="AMC"
CONFIGURATION="Release"
PRODUCT_NAME="AMC"
APP_NAME="$PRODUCT_NAME.app"

DERIVED_DATA_DIR="$ROOT_DIR/DerivedData/ReleaseDMG"
DIST_DIR="$ROOT_DIR/dist"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/amc-dmg.XXXXXX")"
STAGING_DIR="$WORK_DIR/staging"
MOUNT_DIR=""
RW_DMG="$WORK_DIR/read-write.dmg"

cleanup() {
    if [[ -n "$MOUNT_DIR" ]]; then
        hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

log() {
    printf '\n==> %s\n' "$1"
}

command -v xcodebuild >/dev/null || {
    printf 'Error: xcodebuild was not found. Install Xcode first.\n' >&2
    exit 1
}

command -v hdiutil >/dev/null || {
    printf 'Error: hdiutil was not found. This script requires macOS.\n' >&2
    exit 1
}

log "Building $PRODUCT_NAME ($CONFIGURATION)"
rm -rf "$DERIVED_DATA_DIR"

xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -quiet \
    clean build \
    "$@"

APP_PATH="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME"
if [[ ! -d "$APP_PATH" ]]; then
    printf 'Error: the built application was not found at %s\n' "$APP_PATH" >&2
    exit 1
fi

VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP_PATH/Contents/Info.plist")"
VOLUME_NAME="$PRODUCT_NAME $VERSION"
OUTPUT_DMG="$DIST_DIR/$PRODUCT_NAME-$VERSION.dmg"

log "Preparing DMG contents"
mkdir -p "$DIST_DIR" "$STAGING_DIR"
rm -f "$OUTPUT_DMG"
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

log "Creating writable disk image"
hdiutil create \
    -ov \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -format UDRW \
    -srcfolder "$STAGING_DIR" \
    "$RW_DMG"

ATTACH_OUTPUT="$(hdiutil attach \
    "$RW_DMG" \
    -readwrite \
    -noverify \
    -noautoopen \
    2>&1)"

MOUNT_DIR="$(printf '%s\n' "$ATTACH_OUTPUT" | sed -n 's#^.*\(/Volumes/.*\)$#\1#p' | tail -n 1)"
if [[ -z "$MOUNT_DIR" ]]; then
    printf 'Error: could not determine the DMG mount point.\n%s\n' "$ATTACH_OUTPUT" >&2
    exit 1
fi
MOUNT_VOLUME_NAME="${MOUNT_DIR##*/}"

log "Configuring drag-to-install window"
osascript - "$MOUNT_VOLUME_NAME" "$APP_NAME" <<'APPLESCRIPT'
on run argv
    set volumeName to item 1 of argv
    set appName to item 2 of argv

    tell application "Finder"
        tell disk volumeName
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set bounds of container window to {100, 100, 700, 480}
            tell icon view options of container window
                set arrangement to not arranged
                set icon size to 112
                set text size to 14
            end tell
            set position of item appName of container window to {150, 180}
            set position of item "Applications" of container window to {450, 180}
            update without registering applications
            delay 2
            close
        end tell
    end tell
end run
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR" -quiet
MOUNT_DIR=""

log "Compressing DMG"
hdiutil convert \
    "$RW_DMG" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$OUTPUT_DMG"

hdiutil verify "$OUTPUT_DMG" >/dev/null

printf '\nDone: %s\n' "$OUTPUT_DMG"
