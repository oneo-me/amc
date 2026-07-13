#!/bin/zsh

set -euo pipefail
ROOT_DIR="${0:A:h:h}"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="AltMissionControl"
APP_BUNDLE="$ROOT_DIR/.build/$APP_NAME.app"

cd "$ROOT_DIR"
BUILD_OPTIONS=(-c "$CONFIGURATION")
if [[ "${SWIFTPM_DISABLE_SANDBOX:-0}" == "1" ]]; then
    BUILD_OPTIONS+=(--disable-sandbox)
fi

swift build "${BUILD_OPTIONS[@]}"
BIN_DIR="$(swift build "${BUILD_OPTIONS[@]}" --show-bin-path)"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BIN_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Support/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
codesign --force --sign "$SIGN_IDENTITY" \
    --identifier dev.oneo.AltMissionControl \
    "$APP_BUNDLE"

echo "$APP_BUNDLE"
