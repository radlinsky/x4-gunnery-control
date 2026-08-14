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

# 6. Apply reads and normalizes the optional previous-root field from Lua.
#    Task 3B: the Lua payload carries $previousroot alongside $previous so that
#    later hierarchy-release work can release the root without re-resolving it.
#    The MD cue must parse it here, using the same guarded component-conversion
#    pattern already used for $ship, $target, and $previous. No hierarchy walk
#    or additional stop_firing_at_target is required in this task — only safe
#    normalization of the incoming field.
# shellcheck disable=SC2016 # MD variables are literal XML text.
printf '%s\n' "$apply_body" | grep -Fq 'event.param3.$previousroot' \
  || note "Apply must read the previous-root field explicitly from Lua"
# shellcheck disable=SC2016 # MD variables are literal XML text.
printf '%s\n' "$apply_body" | grep -Fq 'typeof $previousroot != datatype.component and $previousroot' \
  || note "Apply must normalize a non-component previous-root with component.{}"
# shellcheck disable=SC2016 # MD variables are literal XML text.
printf '%s\n' "$apply_body" | grep -Fq 'component.{$previousroot}' \
  || note "Apply must convert previous-root to component when needed"
# The normalization block must sit in the payload-parsing section, before any
# target-application work (stop_firing_at_target or set_turret_targets).
# shellcheck disable=SC2016 # MD variables are literal XML text.
prevroot_norm_line=$(printf '%s\n' "$apply_body" | grep -F 'component.{$previousroot}' | head -1 | cut -d: -f1)
if [ -n "$prevroot_norm_line" ] && { [ -z "$stop_old" ] || [ "$prevroot_norm_line" -ge "$stop_old" ]; }; then
  note "previous-root normalization must precede the previous-target stop"
fi

# 7. Task 3C: capital-ship hierarchy release. When $previousroot is a present,
#    existing L or XL ship, Apply must release firing at the root itself and at
#    every direct installed turret/shield/engine surface component before the
#    replacement target is applied. Station roots must not execute this branch.
#    The existing exact $previous release (rule 3) remains; duplicates for the
#    same component are avoided by guarding each hierarchy release against
#    $previous.
# Extract just the Apply cue body as raw text (no line numbers) for structural
# greps that do not need positional checks.
apply_raw=$(awk '
  /<cue name="Apply" / { inside=1 }
  /<cue name="Release" / { inside=0 }
  inside { print }
' "$md")

# 7a. A capital-only hierarchy branch exists, guarded on $previousroot and the
#     L/XL class idiom verified from shipped source (e.g. move.attack.object.
#     capital.xml, interrupt.restock.xml). The guard must reference both
#     $previousroot presence/existence and the class check; a bare class check
#     without $previousroot would fire on every target including stations.
# shellcheck disable=SC2016 # MD variables are literal XML text.
if ! printf '%s\n' "$apply_raw" | grep -q '\$previousroot.*isclass\.\[class\.ship_l, class\.ship_xl\]'; then
  note "Apply must guard the capital hierarchy branch on \$previousroot and L/XL class"
fi
# 7b. The root itself is released inside that branch with stop_firing_at_target.
# shellcheck disable=SC2016 # MD variables are literal XML text.
if ! printf '%s\n' "$apply_raw" | grep -q 'stop_firing_at_target object="\$ship" target="\$previousroot"'; then
  note "Apply must release the previous capital root with stop_firing_at_target"
fi
# 7c. The three required surface-component lists are enumerated via do_for_each.
#     These property paths are shipped-source verified (scriptproperties.xml
#     :539, :251, :533). A grep for the bare words would be too loose; require
#     the full property path inside a do_for_each context.
for prop in 'turrets.operational.list' 'shields.operational.list' 'engines.operational.list'; do
  if ! printf '%s\n' "$apply_raw" | grep -q "do_for_each.*in=.*\$previousroot\.${prop}"; then
    note "Apply must enumerate \$previousroot.${prop} via do_for_each"
  fi
done
# 7d. Each enumerated hierarchy member is released with stop_firing_at_target.
#     Require the action inside a do_for_each block that iterates one of the
#     three verified lists; this ties the release to the enumeration rather
#     than to an unrelated call elsewhere in the file.
for prop in 'turrets.operational.list' 'shields.operational.list' 'engines.operational.list'; do
  # Use a two-pass approach: first find the do_for_each line for this prop,
  # then scan forward until </do_for_each> for a stop_firing_at_target call.
  if ! printf '%s\n' "$apply_raw" | awk -v p="$prop" '
    /do_for_each.*in=.*\$previousroot\./ && index($0, p) > 0 { found=1 }
    found && /stop_firing_at_target object="\$ship"/ { print; exit }
    /<\/do_for_each>/ { if (found) exit }
  ' | grep -q .; then
    note "Apply must stop firing at each enumerated member of \$previousroot.${prop}"
  fi
done
# 7e. The entire capital hierarchy release block sits before the first
#     replacement set_turret_targets call. Use line numbers inside Apply.
# shellcheck disable=SC2016 # MD variables are literal XML text.
first_settt_line=$(printf '%s\n' "$apply_body" | grep -F '<set_turret_targets object="$ship"' | head -1 | cut -d: -f1)
# shellcheck disable=SC2016 # MD variables are literal XML text.
prevroot_release_line=$(printf '%s\n' "$apply_body" | grep -F 'stop_firing_at_target object="$ship" target="$previousroot"' | head -1 | cut -d: -f1)
if [ -n "$prevroot_release_line" ] && { [ -z "$first_settt_line" ] || [ "$prevroot_release_line" -ge "$first_settt_line" ]; }; then
  note "capital hierarchy root release (line $prevroot_release_line) must precede the first replacement set_turret_targets (line $first_settt_line)"
fi
# 7f. Existing exact $previous release is preserved (re-check, rule 3).
#     Already covered by rule 3; assert it is still present after 3C edits.
if [ -z "$stop_old" ]; then
  note "existing exact \$previous stop_firing_at_target must be preserved by Task 3C"
fi
# 7g. Narrow call still precedes wide call (re-check, rule 4).
if [ -n "$narrow" ] && [ -n "$wide" ] && [ "$narrow" -ge "$wide" ]; then
  note "narrow-then-wide ordering must be preserved by Task 3C"
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "turret targets contract tests passed"
