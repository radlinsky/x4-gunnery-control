#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

fixture=$(mktemp)
trap 'rm -f "$fixture"' EXIT
printf '%s\n' \
  'unrelated line' \
  '[X4GC] transition event=menu_show lifecycle=owned phase=console' \
  '[X4GC TEST] turret_result ship=1' \
  '[X4GC TEST SCENARIO] capture done; owner=faction.player' \
  'Error x4_gunnery example' > "$fixture"

output=$(./scripts/filter-gunnery-log.sh "$fixture")
grep -Fq '[X4GC] transition event=menu_show' <<< "$output"
grep -Fq '[X4GC TEST] turret_result' <<< "$output"
grep -Fq '[X4GC TEST SCENARIO] capture done' <<< "$output"
grep -Fq 'Error x4_gunnery example' <<< "$output"
if grep -Fq 'unrelated line' <<< "$output"; then
  echo "filter retained an unrelated line" >&2
  exit 1
fi

echo "gunnery log filter checks passed"
