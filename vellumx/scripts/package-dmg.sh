#!/bin/bash
# Package the current VellumX app variant into a distributable DMG.
#
# Usage: scripts/package-dmg.sh [variant]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO/scripts/lib/vellumx-build.sh"

VARIANT_ARG="${1:-}"
VARIANT="$(vellumx_detect_variant "$REPO" "$VARIANT_ARG")"
APP_NAME="$(vellumx_app_name "$VARIANT")"
APP_PATH="$REPO/app/${APP_NAME}.app"
STAGING="$REPO/app/dmg-staging"

[ -d "$APP_PATH" ] || { echo "error: $APP_PATH not found; run scripts/build.sh first"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo 0)"
DMG="$REPO/app/${APP_NAME}-${VERSION}.dmg"

echo "[1/3] staging $APP_NAME"
rm -rf "$STAGING" "$DMG"
mkdir "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "[2/3] building $(basename "$DMG")"
hdiutil create -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG" >/dev/null

echo "[3/3] cleanup"
rm -rf "$STAGING"

echo "done -> $DMG"
