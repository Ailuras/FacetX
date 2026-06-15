#!/bin/bash
# Build from the repo root (convenience wrapper around app/build-app.sh).
# Auto-detects variant from VELLUMX_VARIANT, an explicit arg, or the current branch.
#
# Usage: scripts/build.sh [debug|release] [variant]
set -euo pipefail
exec "$(dirname "$0")/../app/build-app.sh" "$@"
