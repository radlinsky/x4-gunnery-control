#!/usr/bin/env bash
# Structural contract for the PR3 diagnostic probe harness.
#
# Proves that the six probes exist, that NOOP contains no targeting/release
# action, that RELEASE_A contains release actions but no set_turret_targets,
# and that each narrow/wide probe contains exactly one corresponding
# set_turret_targets operation with the correct weaponmode scoping.
set -euo pipefail
cd "$(dirname "$0")/.."

md=testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_probe.xml
lua=testlab/x4_gunnery_control_testlab/ui/probe.lua
fail=0
note() { echo "probe contract: $1" >&2; fail=1; }

# 1. All six probe operations exist as MD cues or event controls.
for op in noop release_a narrow_any_b wide_any_b narrow_attackenemies_b wide_attackenemies_b; do
  if ! grep -q "'$op'" "$md"; then
    note "probe operation '$op' not found in MD"
  fi
done

# 2. NOOP contains no targeting/release action.
# Extract just the noop do_if branch from ProbeInvoke.
noop_body=$(awk '
  /<do_if value="\$Op == '\''noop'\''">/ { inside=1; depth=1; print; next }
  inside {
    line=$0
    n = gsub(/<do_if/, "<do_if", line); depth += n
    n = gsub(/<do_elseif/, "<do_elseif", line); depth += n
    n = gsub(/<do_all/, "<do_all", line); depth += n
    n = gsub(/<do_while/, "<do_while", line); depth += n
    print
    n = gsub(/<\/do_if>/, "</do_if>", line); depth -= n
    n = gsub(/<\/do_elseif>/, "</do_elseif>", line); depth -= n
    n = gsub(/<\/do_all>/, "</do_all>", line); depth -= n
    n = gsub(/<\/do_while>/, "</do_while>", line); depth -= n
    if (depth == 0) exit
  }
' "$md")
if printf '%s\n' "$noop_body" | grep -Eq '<set_turret_targets|<stop_firing_at_target|<cease_fire'; then
  note "NOOP must contain no targeting or release actions"
fi

# 3. RELEASE_A contains stop_firing_at_target actions but no set_turret_targets.
release_a_body=$(awk '
  /<cue name="ProbeReleaseA"/ { inside=1 }
  /<\/cue>/ && inside { inside=0; exit }
  inside { print }
' "$md")
if [ -z "$release_a_body" ]; then
  note "RELEASE_A cue not found in MD"
else
  if ! printf '%s\n' "$release_a_body" | grep -q '<stop_firing_at_target'; then
    note "RELEASE_A must contain stop_firing_at_target actions"
  fi
  if printf '%s\n' "$release_a_body" | grep -q '<set_turret_targets'; then
    note "RELEASE_A must not contain set_turret_targets"
  fi
fi

# 4. NARROW_ANY_B contains exactly one set_turret_targets with target=[B] preferredtarget=B and NO weaponmode.
narrow_any_body=$(awk '
  /<do_elseif value="\$Op == '\''narrow_any_b'\''"/ { inside=1 }
  /<\/do_elseif>/ && inside { inside=0; exit }
  inside { print }
' "$md")
if [ -z "$narrow_any_body" ]; then
  note "NARROW_ANY_B branch not found in MD"
else
  count=$(printf '%s\n' "$narrow_any_body" | grep -c '<set_turret_targets' || true)
  if [ "$count" -ne 1 ]; then
    note "NARROW_ANY_B must contain exactly one set_turret_targets; found $count"
  fi
  if ! printf '%s\n' "$narrow_any_body" | grep -q 'target="\[\$B\]"'; then
    note "NARROW_ANY_B must use target=[\$B]"
  fi
  if ! printf '%s\n' "$narrow_any_body" | grep -q 'preferredtarget="\$B"'; then
    note "NARROW_ANY_B must use preferredtarget=\$B"
  fi
  if printf '%s\n' "$narrow_any_body" | grep -q 'weaponmode='; then
    note "NARROW_ANY_B must not pass weaponmode"
  fi
fi

# 5. WIDE_ANY_B contains exactly one set_turret_targets with target=$hostiles preferredtarget=B and NO weaponmode.
wide_any_body=$(awk '
  /<do_elseif value="\$Op == '\''wide_any_b'\''"/ { inside=1 }
  /<\/do_elseif>/ && inside { inside=0; exit }
  inside { print }
' "$md")
if [ -z "$wide_any_body" ]; then
  note "WIDE_ANY_B branch not found in MD"
else
  count=$(printf '%s\n' "$wide_any_body" | grep -c '<set_turret_targets' || true)
  if [ "$count" -ne 1 ]; then
    note "WIDE_ANY_B must contain exactly one set_turret_targets; found $count"
  fi
  if ! printf '%s\n' "$wide_any_body" | grep -q 'target="\$Hostiles"'; then
    note "WIDE_ANY_B must use target=\$Hostiles"
  fi
  if ! printf '%s\n' "$wide_any_body" | grep -q 'preferredtarget="\$B"'; then
    note "WIDE_ANY_B must use preferredtarget=\$B"
  fi
  if printf '%s\n' "$wide_any_body" | grep -q 'weaponmode='; then
    note "WIDE_ANY_B must not pass weaponmode"
  fi
fi

# 6. NARROW_ATTACKENEMIES_B contains exactly one set_turret_targets with target=[B] preferredtarget=B weaponmode=attackenemies.
narrow_ae_body=$(awk '
  /<do_elseif value="\$Op == '\''narrow_attackenemies_b'\''"/ { inside=1 }
  /<\/do_elseif>/ && inside { inside=0; exit }
  inside { print }
' "$md")
if [ -z "$narrow_ae_body" ]; then
  note "NARROW_ATTACKENEMIES_B branch not found in MD"
else
  count=$(printf '%s\n' "$narrow_ae_body" | grep -c '<set_turret_targets' || true)
  if [ "$count" -ne 1 ]; then
    note "NARROW_ATTACKENEMIES_B must contain exactly one set_turret_targets; found $count"
  fi
  if ! printf '%s\n' "$narrow_ae_body" | grep -q 'target="\[\$B\]"'; then
    note "NARROW_ATTACKENEMIES_B must use target=[\$B]"
  fi
  if ! printf '%s\n' "$narrow_ae_body" | grep -q 'preferredtarget="\$B"'; then
    note "NARROW_ATTACKENEMIES_B must use preferredtarget=\$B"
  fi
  if ! printf '%s\n' "$narrow_ae_body" | grep -q 'weaponmode="weaponmode.attackenemies"'; then
    note "NARROW_ATTACKENEMIES_B must use weaponmode=weaponmode.attackenemies"
  fi
fi

# 7. WIDE_ATTACKENEMIES_B contains exactly one set_turret_targets with target=$hostiles preferredtarget=B weaponmode=attackenemies.
wide_ae_body=$(awk '
  /<do_elseif value="\$Op == '\''wide_attackenemies_b'\''"/ { inside=1 }
  /<\/do_elseif>/ && inside { inside=0; exit }
  inside { print }
' "$md")
if [ -z "$wide_ae_body" ]; then
  note "WIDE_ATTACKENEMIES_B branch not found in MD"
else
  count=$(printf '%s\n' "$wide_ae_body" | grep -c '<set_turret_targets' || true)
  if [ "$count" -ne 1 ]; then
    note "WIDE_ATTACKENEMIES_B must contain exactly one set_turret_targets; found $count"
  fi
  if ! printf '%s\n' "$wide_ae_body" | grep -q 'target="\$Hostiles"'; then
    note "WIDE_ATTACKENEMIES_B must use target=\$Hostiles"
  fi
  if ! printf '%s\n' "$wide_ae_body" | grep -q 'preferredtarget="\$B"'; then
    note "WIDE_ATTACKENEMIES_B must use preferredtarget=\$B"
  fi
  if ! printf '%s\n' "$wide_ae_body" | grep -q 'weaponmode="weaponmode.attackenemies"'; then
    note "WIDE_ATTACKENEMIES_B must use weaponmode=weaponmode.attackenemies"
  fi
fi

# 8. Hostile list construction in WIDE_ANY_B and WIDE_ATTACKENEMIES_B uses the same
#    production semantics: sector scan with kill-relation filter, then append B
#    if mayattack holds.
for body_name in wide_any_body wide_ae_body; do
  body=$(eval printf '%s\n' "\$$body_name")
  if [ -n "$body" ]; then
    if ! printf '%s\n' "$body" | grep -q 'find_ship.*masstraffic="false"'; then
      note "${body_name} must use find_ship with masstraffic=false"
    fi
    if ! printf '%s\n' "$body" | grep -q 'match_relation_to.*relation="kill"'; then
      note "${body_name} must filter hostiles by kill relation"
    fi
    if ! printf '%s\n' "$body" | grep -q 'mayattack'; then
      note "${body_name} must guard B insertion on mayattack"
    fi
  fi
done

# 9. RELEASE_A mirrors production hierarchy release: capital (L/XL) and station
#    branches with stop_firing_at_target on root and all surface component lists.
if [ -n "$release_a_body" ]; then
  # Capital branch guard.
  if ! printf '%s\n' "$release_a_body" | grep -q 'isclass\.\[class\.ship_l, class\.ship_xl\]'; then
    note "RELEASE_A must guard capital hierarchy on L/XL class"
  fi
  # Station branch guard.
  if ! printf '%s\n' "$release_a_body" | grep -q 'isclass\.station'; then
    note "RELEASE_A must guard station hierarchy on station class"
  fi
  # All four surface component lists for capital.
  for prop in 'turrets.operational.list' 'missileturrets.operational.list' 'shields.operational.list' 'engines.operational.list'; do
    if ! printf '%s\n' "$release_a_body" | grep -q "do_for_each.*in=.*\$A\.${prop}"; then
      note "RELEASE_A must enumerate \$A.${prop} via do_for_each (capital)"
    fi
  done
  # Station modules + all four surface component lists.
  if ! printf '%s\n' "$release_a_body" | grep -q 'do_for_each.*in=.*\$A\.modules\.operational\.list'; then
    note "RELEASE_A must enumerate \$A.modules.operational.list via do_for_each (station)"
  fi
  for prop in 'turrets.operational.list' 'missileturrets.operational.list' 'shields.operational.list' 'engines.operational.list'; do
    if ! printf '%s\n' "$release_a_body" | grep -q "do_for_each.*in=.*\$A\.${prop}"; then
      note "RELEASE_A must enumerate \$A.${prop} via do_for_each (station)"
    fi
  done
fi

# 10. Probe UI file exists and registers the menu.
if [ ! -f "$lua" ]; then
  note "probe.lua not found at $lua"
else
  if ! grep -q 'X4GunneryTestLabProbe' "$lua"; then
    note "probe.lua must register menu X4GunneryTestLabProbe"
  fi
  # All six probe ops must be referenced in the UI.
  for op in noop release_a narrow_any_b wide_any_b narrow_attackenemies_b wide_attackenemies_b; do
    if ! grep -q "\"$op\"" "$lua"; then
      note "probe.lua must reference op '$op'"
    fi
  done
fi

# 11. ui.xml includes the probe.lua file.
uixml=testlab/x4_gunnery_control_testlab/ui.xml
if ! grep -q 'probe.lua' "$uixml"; then
  note "ui.xml must include probe.lua"
fi

# 12. The diagnostic route cannot call production Prefer behavior.
#     Verify that probe_invoke does not emit prefer_all_turrets or prefer_all_turrets_clear.
if grep -q 'prefer_all_turrets' "$md"; then
  note "probe MD must not reference production prefer_all_turrets events"
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "testlab probe contract tests passed"
