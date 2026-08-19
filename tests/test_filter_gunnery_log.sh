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
  '[X4GC TEST HIT] t=1234.5 weapon=99 mode=weaponmode.defend istgt=true prefer=true' \
  '[X4GC TEST CENSUS] t=1234.5 pilot=attackobject modes=99=weaponmode.defend,' \
  '[X4GC TEST SOLUTION] label=mark_1 t=1234.5 weapon=99 los_ex=true inrange=true' \
  '[X4GC TEST OBSERVE] enabled=true t=1234.5' \
  '[X4GC TEST MARK] label=hold_fire_shot t=1234.5' \
  'Error x4_gunnery example' > "$fixture"

output=$(./scripts/filter-gunnery-log.sh "$fixture")
grep -Fq '[X4GC] transition event=menu_show' <<< "$output"
grep -Fq '[X4GC TEST] turret_result' <<< "$output"
grep -Fq '[X4GC TEST SCENARIO] capture done' <<< "$output"
# The fire-control observability prefixes. These are the regression guard for
# the open-ended TEST branch in the pattern; if someone narrows it back to an
# enumeration, these three fail rather than silently vanishing from captures.
grep -Fq '[X4GC TEST HIT] t=1234.5' <<< "$output"
grep -Fq '[X4GC TEST CENSUS] t=1234.5' <<< "$output"
grep -Fq '[X4GC TEST SOLUTION] label=mark_1' <<< "$output"
grep -Fq '[X4GC TEST OBSERVE] enabled=true' <<< "$output"
grep -Fq '[X4GC TEST MARK] label=hold_fire_shot' <<< "$output"
grep -Fq 'Error x4_gunnery example' <<< "$output"
if grep -Fq 'unrelated line' <<< "$output"; then
  echo "filter retained an unrelated line" >&2
  exit 1
fi

echo "gunnery log filter checks passed"
