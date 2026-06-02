#!/bin/bash
# Build from the repo root (convenience wrapper around app/build-app.sh).
# Auto-detects variant from the current git branch unless explicitly provided.
#
# Usage: scripts/build.sh [debug|release] [variant]
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
exec "$REPO/app/build-app.sh" "$@"
