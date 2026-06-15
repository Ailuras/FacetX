#!/bin/bash
# Build VellumX in debug mode and run the unit test suite.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"

cd "$REPO/app"
swift build -c debug
swift test "$@"
