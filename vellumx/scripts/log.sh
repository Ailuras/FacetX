#!/bin/bash
# Stream OS log output from any running VellumX instance (all variants).
#
# Usage: scripts/log.sh [debug|info|default]   (default: debug)
LEVEL="${1:-debug}"
exec log stream --predicate 'process == "VellumX"' --level "$LEVEL"
