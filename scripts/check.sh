#!/bin/bash
# Run the lightweight local validation suite for FacetX.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

cd "$REPO/app"

echo "[1/2] swift build -c debug"
swift build -c debug

echo "[2/2] swift run FacetXCoreChecks"
swift run FacetXCoreChecks
