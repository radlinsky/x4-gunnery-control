#!/usr/bin/env bash
# Structural contract for our <set_turret_targets> calls.
#
# Every rule here is a bug that reached a live session on 2026-08-09 and had to
# be found by hand, in game, one at a time. None of them are visible to the Lua
# tests, because they live in MD XML. This asserts them as text so the same
# class of mistake cannot come back silently.
set -euo pipefail
cd "$(dirname "$0")/.."

md=md/x4_gunnery_control.xml
fail=0
note() { echo "turret targets contract: $1" >&2; fail=1; }

calls=$(grep -c "<set_turret_targets" "$md")
if [ "$calls" -eq 0 ]; then
  note "no <set_turret_targets> calls found in $md; test is not checking anything"
  exit 1
fi

# 1. target is mandatory in practice. Omitting it makes the action evaluate null
#    for its target list and throw "Evaluated value 'null' is not of type list",
#    so nothing is applied at all. This shipped broken and went unnoticed because
#    the failure is a log line, not a visible error. All 24 shipped calls that
#    pass preferredtarget also pass target.
while IFS= read -r call; do
  case $call in
    *' target="'*) ;;
    *) note "call without a target list (throws on a null list): $call" ;;
  esac
done < <(grep -o "<set_turret_targets[^>]*>" "$md")

# 2. DirectFallback is the sole writer, and it must scope to attackenemies.
#    Since #38 removed Prefer My Target, DirectFallback is the only cue that may
#    call <set_turret_targets>; any other cue introducing one is a new, unreviewed
#    turret writer. The attackenemies selector is what limits it to the ticked
#    groups (the console binds the checkbox to attackenemies).
cue_report=$(awk '
  /<cue name="/ { match($0, /name="[^"]*"/); cue = substr($0, RSTART + 6, RLENGTH - 7) }
  /<set_turret_targets/ { print cue "\t" $0 }
' "$md")

while IFS=$'\t' read -r cue call; do
  [ -n "$cue" ] || continue
  case $cue in
    DirectFallback)
      case $call in
        *'weaponmode="weaponmode.attackenemies"'*) ;;
        *) note "DirectFallback must scope to attackenemies (the ticked groups): $call" ;;
      esac
      ;;
    *)
      note "only DirectFallback may call <set_turret_targets>; found one in cue '$cue': $call"
      ;;
  esac
done <<< "$cue_report"

if ! grep -q "^DirectFallback	" <<< "$cue_report"; then
  note "expected at least one <set_turret_targets> inside the DirectFallback cue; found none"
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "turret targets contract tests passed"
