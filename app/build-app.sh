#!/bin/bash
# Build FacetX.app: compile via SwiftPM, wrap the binary into a code-signed
# .app bundle with EventKit usage strings + entitlements so macOS will grant
# Calendar/Reminders access (a bare binary is silently denied).
#
# Usage: ./build-app.sh [debug|release] && open ./FacetX.app
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="FacetX.app"
BIN_NAME="FacetX"

echo "[1/4] swift build ($CONFIG)"
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$BIN_NAME"

echo "[2/4] assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/FacetX.icns "$APP/Contents/Resources/FacetX.icns"
cp Resources/FacetXMenuBarTemplate.png "$APP/Contents/Resources/FacetXMenuBarTemplate.png"
cp Resources/FacetXMenuBarTemplate@2x.png "$APP/Contents/Resources/FacetXMenuBarTemplate@2x.png"

echo "[3/4] codesign (ad-hoc, with entitlements)"
codesign --force --sign - \
  --entitlements FacetX.entitlements \
  --options runtime \
  "$APP"

echo "[4/4] done -> $APP"
echo "run:  open ./$APP"
