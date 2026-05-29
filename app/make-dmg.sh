#!/bin/bash
# Package FacetX.app into a distributable .dmg containing the app plus a
# symlink to /Applications, so a recipient just drags the app across.
#
# Prereq: build the app first (./build-app.sh). Then: ./make-dmg.sh
#
# NOTE: the app is ad-hoc signed (not notarized). On another Mac, Gatekeeper
# will block the first launch — the recipient must right-click > Open, or allow
# it in System Settings > Privacy & Security. Functionality is unaffected.
set -euo pipefail
cd "$(dirname "$0")"

APP="FacetX.app"
VOL="FacetX"
DMG="FacetX.dmg"
STAGING="dmg-staging"

[ -d "$APP" ] || { echo "error: $APP not found — run ./build-app.sh first"; exit 1; }

# Read the version from the bundle for a nicer dmg name.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 0)"
DMG="FacetX-$VERSION.dmg"

echo "[1/3] staging"
rm -rf "$STAGING" "$DMG"
mkdir "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"   # drag-to-install target

echo "[2/3] building $DMG"
hdiutil create -volname "$VOL" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG" >/dev/null

echo "[3/3] cleanup"
rm -rf "$STAGING"

echo "done -> $DMG"
echo "Recipients: open the dmg, drag FacetX to Applications."
echo "(ad-hoc signed: first launch needs right-click > Open on another Mac.)"
