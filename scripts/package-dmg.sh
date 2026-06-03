#!/bin/bash
# Package the canonical FacetX.app into a distributable .dmg.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO/app"
APP="$APP_DIR/FacetX.app"
VOL="FacetX"
STAGING="$APP_DIR/dmg-staging"

[ -d "$APP" ] || { echo "error: FacetX.app not found; run scripts/build.sh first"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 0)"
DMG="$APP_DIR/FacetX-$VERSION.dmg"

echo "[1/3] staging"
rm -rf "$STAGING" "$DMG"
mkdir "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "[2/3] building $(basename "$DMG")"
hdiutil create -volname "$VOL" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG" >/dev/null

echo "[3/3] cleanup"
rm -rf "$STAGING"

echo "done -> $DMG"
echo "Recipients: open the dmg, drag FacetX to Applications."
echo "Locally signed but not notarized; another Mac may require right-click > Open."
