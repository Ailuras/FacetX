#!/bin/bash
# Remove local build and packaging artifacts.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

rm -rf "$REPO/app/.build"
rm -rf "$REPO/app/FacetX.app" "$REPO"/app/FacetX-*.app
rm -rf "$REPO/app/dmg-staging"
rm -f "$REPO"/app/*.dmg
rm -f "$REPO"/app/*.log

echo "cleaned local build artifacts"
