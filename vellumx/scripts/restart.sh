#!/bin/bash
# Stop the running VellumX variant, test, rebuild, and relaunch.
#
# Usage: scripts/restart.sh [debug|release] [variant]   (default: debug)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO/scripts/lib/vellumx-build.sh"

CONFIG="${1:-debug}"
VARIANT_ARG="${2:-}"
VARIANT="$(vellumx_detect_variant "$REPO" "$VARIANT_ARG")"
APP_NAME="$(vellumx_app_name "$VARIANT")"
BUNDLE_ID="$(vellumx_bundle_id "$VARIANT")"
APP_PATH="$REPO/app/${APP_NAME}.app"

echo "[1/4] stopping $APP_NAME"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
sleep 0.8
pkill -f "${APP_NAME}.app/Contents/MacOS" 2>/dev/null || true

echo "[2/4] testing"
(cd "$REPO/app" && swift test)

echo "[3/4] building"
"$REPO/app/build-app.sh" "$CONFIG" "$VARIANT"

echo "[4/4] launching $APP_PATH"
defaults write "$BUNDLE_ID" launchOnRightScreen -bool true
open -n "$APP_PATH"
