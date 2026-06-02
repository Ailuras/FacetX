#!/bin/bash
# Stream OS log output from running FacetX instances.
#
# Usage: scripts/log.sh [debug|info|default]   (default: debug)
set -euo pipefail
LEVEL="${1:-debug}"
exec log stream --predicate 'process == "FacetX"' --level "$LEVEL"
