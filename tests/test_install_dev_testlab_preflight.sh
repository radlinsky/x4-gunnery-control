#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
game="$tmp/X4 Foundations"
mkdir -p "$game/extensions" "$tmp/missing-source"
touch "$game/X4"

if X4GC_INSTALL_TESTLAB=1 X4GC_EXTRACTED_ROOT="$tmp/missing-source" \
  ./scripts/install-dev.sh "$game" >"$tmp/output" 2>&1; then
  echo "FAIL: Test Lab install continued after source preflight failure" >&2
  exit 1
fi
grep -Fq 'Test Lab turret preflight failed:' "$tmp/output"
grep -Fq 'required official X4 source sets are unavailable' "$tmp/output"
test ! -e "$game/extensions/x4_gunnery_control_testlab"

echo "Test Lab install preflight gate tests passed"
