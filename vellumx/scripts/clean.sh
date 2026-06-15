#!/bin/bash
# Remove local build and packaging artifacts.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"

rm -rf "$REPO/app/.build"
rm -rf "$REPO/app"/*.app
rm -rf "$REPO/app"/*.dmg
rm -rf "$REPO/app/dmg-staging"

echo "cleaned VellumX build artifacts"
