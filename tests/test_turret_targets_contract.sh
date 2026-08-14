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

# 3. A changed ship-wide preference explicitly releases the previous target
#    before applying the replacement. X4's shoot controller can remain latched
#    to a still-valid old hostile even after the narrow-then-wide pair is
#    reissued. Vanilla uses stop_firing_at_target when it removes one target;
#    unlike cease_fire, this leaves other firing and every turret mode intact.
apply_body=$(awk '
  /<cue name="Apply" / { inside=1 }
  /<cue name="Release" / { inside=0 }
  inside { print NR ":" $0 }
' "$md")
# shellcheck disable=SC2016 # MD variables are literal XML text.
stop_old=$(printf '%s\n' "$apply_body" | grep -F 'stop_firing_at_target object="$ship" target="$previous"' | cut -d: -f1)
# shellcheck disable=SC2016 # MD variables are literal XML text.
first_apply=$(printf '%s\n' "$apply_body" | grep -F '<set_turret_targets object="$ship"' | head -1 | cut -d: -f1)
if [ -z "$stop_old" ]; then
  note "Apply must stop firing at the previous preferred target before retargeting"
elif [ -z "$first_apply" ] || [ "$stop_old" -ge "$first_apply" ]; then
  note "previous-target stop (line $stop_old) must precede the replacement target calls"
fi
# shellcheck disable=SC2016 # MD variables are literal XML text.
printf '%s\n' "$apply_body" | grep -Fq 'event.param3.$previous' \
  || note "Apply must read the previous target explicitly from Lua"
# shellcheck disable=SC2016 # MD variables are literal XML text.
printf '%s\n' "$apply_body" | grep -Fq '$previous != $target' \
  || note "previous-target stop must run only when the preferred target changes"

# 4. Apply still issues the narrow call before the wide one. The first call
#    establishes the requested target; the second restores the fallback set.
# shellcheck disable=SC2016 # $target and $hostiles are MD variable names in the
# XML being searched, not shell expansions.
narrow=$(grep -n 'target="\[\$target\]"' "$md" | head -1 | cut -d: -f1)
# shellcheck disable=SC2016
wide=$(grep -n 'target="\$hostiles" preferredtarget=' "$md" | head -1 | cut -d: -f1)
if [ -z "$narrow" ] || [ -z "$wide" ]; then
  note "Apply must issue both a narrow (target=[\$target]) and a wide (target=\$hostiles) call"
elif [ "$narrow" -ge "$wide" ]; then
  note "narrow call (line $narrow) must precede the wide call (line $wide)"
fi

# 5. Apply and Release remain free of broad cease-fire/mode mutations.
release_body=$(awk '
  /<cue name="Release" / { inside=1 }
  /<cue name="DirectFallback" / { inside=0 }
  inside { print }
' "$md")
if printf '%s\n' "$apply_body$release_body" | grep -Eq '<cease_fire|<set_weapon_mode'; then
  note "preferred-target switching must not use cease_fire or mutate turret modes"
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "turret targets contract tests passed"
