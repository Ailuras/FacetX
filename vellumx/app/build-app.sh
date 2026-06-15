#!/bin/bash
# Build VellumX.app via SwiftPM and wrap it into a code-signed app bundle.
#
# Usage: ./build-app.sh [debug|release] [variant]
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$APP_DIR/.." && pwd)"
source "$REPO/scripts/lib/vellumx-build.sh"
cd "$APP_DIR"

CONFIG="${1:-release}"
VARIANT_ARG="${2:-}"
VARIANT="$(vellumx_detect_variant "$REPO" "$VARIANT_ARG")"
APP_NAME="$(vellumx_app_name "$VARIANT")"
APP="${APP_NAME}.app"
BIN_NAME="VellumX"
BUNDLE_ID="$(vellumx_bundle_id "$VARIANT")"
SUPPORT_NAME="$(vellumx_support_name "$VARIANT")"
SIGN_IDENTITY="$(vellumx_sign_identity)"

set_plist_string() {
    local key="$1"
    local value="$2"
    local plist="$3"

    if /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null 2>&1; then
        /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist"
    else
        /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
    fi
}

vellumx_print_summary "$CONFIG" "$VARIANT" "$APP_NAME" "$BUNDLE_ID" "$SUPPORT_NAME" "$SIGN_IDENTITY"

echo "[1/4] swift build ($CONFIG)"
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$BIN_NAME"

echo "[2/4] assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
cp Info.plist "$APP/Contents/Info.plist"
set_plist_string "CFBundleIdentifier" "$BUNDLE_ID" "$APP/Contents/Info.plist"
set_plist_string "CFBundleName" "$APP_NAME" "$APP/Contents/Info.plist"
set_plist_string "CFBundleDisplayName" "$APP_NAME" "$APP/Contents/Info.plist"
set_plist_string "VellumXApplicationSupportName" "$SUPPORT_NAME" "$APP/Contents/Info.plist"
[ -f Resources/VellumX.icns ] && cp Resources/VellumX.icns "$APP/Contents/Resources/VellumX.icns"
[ -f Resources/MenuBarIcon.png ] && cp Resources/MenuBarIcon.png "$APP/Contents/Resources/MenuBarIcon.png"
[ -f Resources/MenuBarIcon@2x.png ] && cp "Resources/MenuBarIcon@2x.png" "$APP/Contents/Resources/MenuBarIcon@2x.png"

echo "[3/4] codesign (with entitlements)"
codesign --force --sign "$SIGN_IDENTITY" \
  --entitlements VellumX.entitlements \
  --options runtime \
  "$APP"

echo "[4/4] done -> $APP"
echo "run:  open -n ./$APP"
