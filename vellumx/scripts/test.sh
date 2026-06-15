#!/bin/bash
# Run the VellumX unit test suite.
# Any extra arguments are forwarded to swift test, e.g.:
#   scripts/test.sh --filter VenueScorerTests
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO/app"
exec swift test "$@"
