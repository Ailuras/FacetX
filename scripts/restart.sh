#!/bin/bash
# Stop the running FacetX variant for the current branch, rebuild, and relaunch.
#
# Usage: scripts/restart.sh [debug|release] [variant]   (default: debug)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO/scripts/lib/facetx-build.sh"

CONFIG="${1:-debug}"
VARIANT_ARG="${2:-}"
VARIANT="$(facetx_detect_variant "$REPO" "$VARIANT_ARG")"
APP_NAME="$(facetx_app_name "$VARIANT")"
BUNDLE_ID="$(facetx_bundle_id "$VARIANT")"
APP_PATH="$REPO/app/${APP_NAME}.app"

echo "[1/3] stopping $APP_NAME"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
sleep 0.8
pkill -f "${APP_NAME}.app/Contents/MacOS/FacetX" 2>/dev/null || true

echo "[2/3] building"
"$REPO/app/build-app.sh" "$CONFIG" "$VARIANT"

echo "[3/3] launching $APP_PATH"
open -n "$APP_PATH"
