#!/bin/bash
# Build EventKitProbe.app — a minimal bundled app so macOS will present the
# privacy authorization prompts (a bare CLI binary cannot get EventKit access).
#
# Usage: ./build-app.sh && open ./EventKitProbe.app
# Output (the grouped dump) is written to the file passed as PROBE_OUT, or to
# ~/eventkit-probe-output.txt by default, since a .app has no attached stdout.
set -euo pipefail
cd "$(dirname "$0")"

APP="EventKitProbe.app"
BIN_NAME="EventKitProbe"
BUNDLE_ID="com.docsbot.eventkitprobe"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${BIN_NAME}</string>
  <key>CFBundleDisplayName</key><string>EventKit Probe</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>${BIN_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSRemindersFullAccessUsageDescription</key>
  <string>DocsBot reads your reminders to build a project-oriented view.</string>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>DocsBot reads your calendar to build a project-oriented view.</string>
</dict>
</plist>
PLIST

swiftc app-main.swift -o "$APP/Contents/MacOS/${BIN_NAME}"

# Ad-hoc sign so TCC has a stable code identity to attach the grant to.
codesign --force --deep --sign - "$APP"

echo "Built $APP"
echo "Run:  open ./$APP    (output → ~/eventkit-probe-output.txt)"
