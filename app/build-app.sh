#!/bin/bash
# Build FacetX.app: compile via SwiftPM, wrap the binary into a code-signed
# .app bundle with EventKit usage strings + entitlements so macOS will grant
# Calendar/Reminders access (a bare binary is silently denied).
#
# Usage: ./build-app.sh [debug|release] [variant]
#   variant  optional; defaults to the current git branch (empty on main/master).
#            e.g. branch "feat/calendar" -> FacetX-feat-calendar.app with
#            bundle ID com.facetx.app.dev.feat-calendar and its own support dir.
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$APP_DIR/.." && pwd)"
source "$REPO/scripts/build-env.sh"
cd "$APP_DIR"

CONFIG="${1:-release}"
VARIANT_ARG="${2:-}"
VARIANT="$(facetx_detect_variant "$REPO" "$VARIANT_ARG")"
APP_NAME="$(facetx_app_name "$VARIANT")"
APP="${APP_NAME}.app"
BIN_NAME="FacetX"
BUNDLE_ID="$(facetx_bundle_id "$VARIANT")"
SUPPORT_NAME="$(facetx_support_name "$VARIANT")"
SIGN_IDENTITY="$(facetx_sign_identity)"

facetx_print_summary "$CONFIG" "$VARIANT" "$APP_NAME" "$BUNDLE_ID" "$SUPPORT_NAME" "$SIGN_IDENTITY"

echo "[1/4] swift build ($CONFIG)"
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$BIN_NAME"

echo "[2/4] assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $BIN_NAME" "$APP/Contents/Info.plist"
if /usr/libexec/PlistBuddy -c "Print :FacetXApplicationSupportName" "$APP/Contents/Info.plist" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Set :FacetXApplicationSupportName $SUPPORT_NAME" "$APP/Contents/Info.plist"
else
  /usr/libexec/PlistBuddy -c "Add :FacetXApplicationSupportName string $SUPPORT_NAME" "$APP/Contents/Info.plist"
fi
cp Resources/FacetX.icns "$APP/Contents/Resources/FacetX.icns"
cp Resources/FacetXMenuBarTemplate.png "$APP/Contents/Resources/FacetXMenuBarTemplate.png"
cp Resources/FacetXMenuBarTemplate@2x.png "$APP/Contents/Resources/FacetXMenuBarTemplate@2x.png"
# Prebuilt Milkdown note editor bundle (see web/note-editor). Vendored so the
# Swift build needs no Node toolchain; rebuild with `npm --prefix web/note-editor run build`.
cp -R Resources/NoteEditor "$APP/Contents/Resources/NoteEditor"

echo "[3/4] codesign (with entitlements)"
codesign --force --sign "$SIGN_IDENTITY" \
  --entitlements FacetX.entitlements \
  --options runtime \
  "$APP"

echo "[4/4] done -> $APP"
echo "run:  open -n ./$APP"
