#!/bin/bash
# Run the lightweight local validation suite for FacetX.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

cd "$REPO/app"

echo "[1/3] swift build -c debug"
swift build -c debug

echo "[2/3] swift run FacetXCoreChecks"
swift run FacetXCoreChecks

echo "[3/3] repository document and SQLite checks"
swiftc \
  -parse-as-library \
  Sources/FacetX/App/AppSupport.swift \
  Sources/FacetX/Stores/ItemStore.swift \
  Sources/FacetX/Services/LocalGitRepository.swift \
  Sources/FacetX/Services/RepositoryDocumentStore.swift \
  Checks/FacetXDataChecks/main.swift \
  -lsqlite3 \
  -o .build/FacetXDataChecks
.build/FacetXDataChecks
