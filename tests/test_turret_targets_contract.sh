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

# 2. The ship-wide override reaches EVERY turret, whatever its mode. The
#    weaponmode attribute is optional and "defaults to any" (common.xsd:36223),
#    so omitting it is what makes that true -- and it is the only way to reach
#    autoassist and holdfire turrets at all, since neither is a member of
#    weaponmodelookup (common.xsd:2419) and neither can be named in the
#    attribute. An earlier version excluded six modes; that is the behaviour
#    this rule now forbids.
if grep -q "mode != weaponmode\." "$md"; then
  note "PreferAllTurrets must not filter by mode; found a 'mode != weaponmode.' guard"
fi

# 2b. Per-cue: Apply and Release must omit weaponmode, DirectFallback must keep
#     it. DirectFallback is scoped on purpose -- the console binds the checkbox
#     to attackenemies, so that selector is what limits it to the ticked groups.
#     Without the per-cue split, rule 2 alone would pass a file that had quietly
#     dropped the selector from DirectFallback too.
cue_report=$(awk '
  /<cue name="/ { match($0, /name="[^"]*"/); cue = substr($0, RSTART + 6, RLENGTH - 7) }
  /<set_turret_targets/ { print cue "\t" $0 }
' "$md")

while IFS=$'\t' read -r cue call; do
  [ -n "$cue" ] || continue
  case $cue in
    Apply|Release)
      case $call in
        *weaponmode=*) note "$cue must not pass weaponmode (it would skip modes): $call" ;;
      esac
      ;;
    DirectFallback)
      case $call in
        *'weaponmode="weaponmode.attackenemies"'*) ;;
        *) note "DirectFallback must scope to attackenemies (the ticked groups): $call" ;;
      esac
      ;;
  esac
done <<< "$cue_report"

for required in Apply Release DirectFallback; do
  if ! grep -q "^$required	" <<< "$cue_report"; then
    note "expected at least one <set_turret_targets> inside the $required cue; found none"
  fi
done

# 3. Apply issues the narrow call before the wide one. stopshootingold only drops
#    targets absent from the new list, so a list containing the turret's current
#    target can never dislodge it: the narrow list of one forces the switch, and
#    the wide list restores a fallback for turrets with no shot at the preferred
#    target. Order is the whole point; reversed, the narrow call wins and the
#    fallback is lost.
narrow=$(grep -n $'target="\\[\\$target\\]"' "$md" | head -1 | cut -d: -f1)
wide=$(grep -n $'target="\\$hostiles" preferredtarget=' "$md" | head -1 | cut -d: -f1)
if [ -z "$narrow" ] || [ -z "$wide" ]; then
  note "Apply must issue both a narrow (target=[\$target]) and a wide (target=\$hostiles) call"
elif [ "$narrow" -ge "$wide" ]; then
  note "narrow call (line $narrow) must precede the wide call (line $wide)"
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "turret targets contract tests passed"
