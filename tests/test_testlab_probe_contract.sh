#!/usr/bin/env bash
# Structural contract for the PR3 diagnostic probe harness.
#
# Proves that the six probes exist, that NOOP contains no targeting/release
# action, that RELEASE_A is inlined (no ProbeRoot handoff) and does not
# double-release A/root(A), and that each narrow/wide probe contains exactly
# one corresponding set_turret_targets operation with the correct weaponmode
# scoping. Also proves the Test Lab menu routes to the probe menu.
set -euo pipefail
cd "$(dirname "$0")/.."

md=testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_probe.xml
lua=testlab/x4_gunnery_control_testlab/ui/probe.lua
testlab=testlab/x4_gunnery_control_testlab/ui/testlab.lua
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

# 3. RELEASE_A is inlined in ProbeInvoke (no separate ProbeReleaseA cue).
#    This proves $Ship/$A/$B come from the current invocation, not a
#    ProbeRoot handoff that was never populated.
if grep -q 'ProbeReleaseA' "$md"; then
  note "RELEASE_A must be inlined; no ProbeReleaseA cue should exist"
fi

# 4. RELEASE_A uses the current invocation's $Ship/$A (no ProbeRoot.$Probe* handoff).
release_a_branch=$(awk '
  /<do_elseif value="\$Op == '\''release_a'\''">/ { inside=1 }
  /<\/do_elseif>/ && inside { inside=0; exit }
  inside { print }
' "$md")
if [ -z "$release_a_branch" ]; then
  note "RELEASE_A branch not found in MD"
else
  # shellcheck disable=SC2016 # MD variables are literal XML text.
  if printf '%s\n' "$release_a_branch" | grep -q 'ProbeRoot\.\$Probe'; then
    note "RELEASE_A must not reference ProbeRoot.\$Probe* handoff variables"
  fi
  # Must use $Ship and $A directly (resolved by ProbeInvoke).
  # shellcheck disable=SC2016 # MD variables are literal XML text.
  if ! printf '%s\n' "$release_a_branch" | grep -q '\$Ship'; then
    note "RELEASE_A must use \$Ship from current invocation"
  fi
  # shellcheck disable=SC2016 # MD variables are literal XML text.
  if ! printf '%s\n' "$release_a_branch" | grep -q '\$A'; then
    note "RELEASE_A must use \$A from current invocation"
  fi
fi

# 5. RELEASE_A contains stop_firing_at_target actions but no set_turret_targets.
if [ -n "$release_a_branch" ]; then
  if ! printf '%s\n' "$release_a_branch" | grep -q '<stop_firing_at_target'; then
    note "RELEASE_A must contain stop_firing_at_target actions"
  fi
  if printf '%s\n' "$release_a_branch" | grep -q '<set_turret_targets'; then
    note "RELEASE_A must not contain set_turret_targets"
  fi
fi

# 6. RELEASE_A does not double-release A/root(A). For the Osaka fixture
#    A == root(A), so the capital-branch root release must be guarded
#    against $A to avoid a second stop_firing_at_target on the same component.
if [ -n "$release_a_branch" ]; then
  # Extract the capital hierarchy branch.
  capital_body=$(printf '%s\n' "$release_a_branch" | awk '
    /<do_if value=".*\$A.*isclass\.\[class\.ship_l, class\.ship_xl\]/ { depth=1; found=1; print; next }
    found {
      line=$0
      n = gsub(/<do_if/, "<do_if", line); depth += n
      n = gsub(/<\/do_if>/, "</do_if>", line); depth -= n
      print
      if (depth == 0) exit
    }
  ')
  # The root release inside the capital branch must be guarded against $A.
  # Production uses: do_if value="not $A or $A != $A"
  if [ -n "$capital_body" ]; then
    # shellcheck disable=SC2016 # MD variables are literal XML text.
    if printf '%s\n' "$capital_body" | grep -q 'stop_firing_at_target object="\$Ship" target="\$A"'; then
      # There is a root release; verify it is guarded.
      if ! printf '%s\n' "$capital_body" | awk '
        /<do_if.*value=/ { guard=$0 }
        /stop_firing_at_target object="\$Ship" target="\$A"/ {
          if (index(guard, "not $A or $A != $A") > 0) { print; exit }
        }
        /<\/do_if>/ { exit }
      ' | grep -q .; then
        note "RELEASE_A capital root release must be guarded against \$A to prevent double-release"
      fi
    fi
  fi
fi

# 7. NARROW_ANY_B contains exactly one set_turret_targets with target=[B] preferredtarget=B and NO weaponmode.
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
  # shellcheck disable=SC2016
  if ! printf '%s\n' "$narrow_any_body" | grep -q 'target="\[\$B\]"'; then
    note "NARROW_ANY_B must use target=[\$B]"
  fi
  # shellcheck disable=SC2016
  if ! printf '%s\n' "$narrow_any_body" | grep -q 'preferredtarget="\$B"'; then
    note "NARROW_ANY_B must use preferredtarget=\$B"
  fi
  if printf '%s\n' "$narrow_any_body" | grep -q 'weaponmode='; then
    note "NARROW_ANY_B must not pass weaponmode"
  fi
fi

# 8. WIDE_ANY_B contains exactly one set_turret_targets with target=$hostiles preferredtarget=B and NO weaponmode.
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
  # shellcheck disable=SC2016
  if ! printf '%s\n' "$wide_any_body" | grep -q 'target="\$Hostiles"'; then
    note "WIDE_ANY_B must use target=\$Hostiles"
  fi
  # shellcheck disable=SC2016
  if ! printf '%s\n' "$wide_any_body" | grep -q 'preferredtarget="\$B"'; then
    note "WIDE_ANY_B must use preferredtarget=\$B"
  fi
  if printf '%s\n' "$wide_any_body" | grep -q 'weaponmode='; then
    note "WIDE_ANY_B must not pass weaponmode"
  fi
fi

# 9. NARROW_ATTACKENEMIES_B contains exactly one set_turret_targets with target=[B] preferredtarget=B weaponmode=attackenemies.
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
  # shellcheck disable=SC2016
  if ! printf '%s\n' "$narrow_ae_body" | grep -q 'target="\[\$B\]"'; then
    note "NARROW_ATTACKENEMIES_B must use target=[\$B]"
  fi
  # shellcheck disable=SC2016
  if ! printf '%s\n' "$narrow_ae_body" | grep -q 'preferredtarget="\$B"'; then
    note "NARROW_ATTACKENEMIES_B must use preferredtarget=\$B"
  fi
  # shellcheck disable=SC2016
  if ! printf '%s\n' "$narrow_ae_body" | grep -q 'weaponmode="weaponmode.attackenemies"'; then
    note "NARROW_ATTACKENEMIES_B must use weaponmode=weaponmode.attackenemies"
  fi
fi

# 10. WIDE_ATTACKENEMIES_B contains exactly one set_turret_targets with target=$hostiles preferredtarget=B weaponmode=attackenemies.
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
  # shellcheck disable=SC2016
  if ! printf '%s\n' "$wide_ae_body" | grep -q 'target="\$Hostiles"'; then
    note "WIDE_ATTACKENEMIES_B must use target=\$Hostiles"
  fi
  # shellcheck disable=SC2016
  if ! printf '%s\n' "$wide_ae_body" | grep -q 'preferredtarget="\$B"'; then
    note "WIDE_ATTACKENEMIES_B must use preferredtarget=\$B"
  fi
  # shellcheck disable=SC2016
  if ! printf '%s\n' "$wide_ae_body" | grep -q 'weaponmode="weaponmode.attackenemies"'; then
    note "WIDE_ATTACKENEMIES_B must use weaponmode=weaponmode.attackenemies"
  fi
fi

# 11. Hostile list construction in WIDE_ANY_B and WIDE_ATTACKENEMIES_B matches
#     production Prefer Apply semantics: sector scan with kill-relation filter,
#     then append B if absent. NO mayattack guard — that belongs to DirectFallback.
for body_name in wide_any_body wide_ae_body; do
  body=$(eval printf '%s\n' "\$$body_name")
  if [ -n "$body" ]; then
    if ! printf '%s\n' "$body" | grep -q 'find_ship.*masstraffic="false"'; then
      note "${body_name} must use find_ship with masstraffic=false"
    fi
    if ! printf '%s\n' "$body" | grep -q 'match_relation_to.*relation="kill"'; then
      note "${body_name} must filter hostiles by kill relation"
    fi
    # Must NOT contain mayattack — that is from DirectFallback, not Prefer Apply.
    if printf '%s\n' "$body" | grep -q 'mayattack'; then
      note "${body_name} must not contain mayattack guard (belongs to DirectFallback, not Prefer)"
    fi
    # Must append B unconditionally when absent.
    # shellcheck disable=SC2016 # MD variables are literal XML text.
    if ! printf '%s\n' "$body" | grep -q 'append_to_list.*exact="\$B"'; then
      note "${body_name} must append \$B to hostiles when absent"
    fi
  fi
done

# 12. RELEASE_A mirrors production hierarchy release: capital (L/XL) and station
#     branches with stop_firing_at_target on root and all surface component lists.
if [ -n "$release_a_branch" ]; then
  # Capital branch guard.
  if ! printf '%s\n' "$release_a_branch" | grep -q 'isclass\.\[class\.ship_l, class\.ship_xl\]'; then
    note "RELEASE_A must guard capital hierarchy on L/XL class"
  fi
  # Station branch guard.
  if ! printf '%s\n' "$release_a_branch" | grep -q 'isclass\.station'; then
    note "RELEASE_A must guard station hierarchy on station class"
  fi
  # All four surface component lists for capital.
  for prop in 'turrets.operational.list' 'missileturrets.operational.list' 'shields.operational.list' 'engines.operational.list'; do
    if ! printf '%s\n' "$release_a_branch" | grep -q "do_for_each.*in=.*\$A\.${prop}"; then
      note "RELEASE_A must enumerate \$A.${prop} via do_for_each (capital)"
    fi
  done
  # Station modules + all four surface component lists.
  # shellcheck disable=SC2016
  if ! printf '%s\n' "$release_a_branch" | grep -q 'do_for_each.*in=.*\$A\.modules\.operational\.list'; then
    note "RELEASE_A must enumerate \$A.modules.operational.list via do_for_each (station)"
  fi
  for prop in 'turrets.operational.list' 'missileturrets.operational.list' 'shields.operational.list' 'engines.operational.list'; do
    if ! printf '%s\n' "$release_a_branch" | grep -q "do_for_each.*in=.*\$A\.${prop}"; then
      note "RELEASE_A must enumerate \$A.${prop} via do_for_each (station)"
    fi
  done
fi

# 13. Probe UI file exists and registers the menu.
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

# 14. ui.xml includes the probe.lua file.
uixml=testlab/x4_gunnery_control_testlab/ui.xml
if ! grep -q 'probe.lua' "$uixml"; then
  note "ui.xml must include probe.lua"
fi

# 15. The main Test Lab menu has a route to X4GunneryTestLabProbe.
if [ ! -f "$testlab" ]; then
  note "testlab.lua not found"
else
  if ! grep -q 'X4GunneryTestLabProbe' "$testlab"; then
    note "testlab.lua must have a route to X4GunneryTestLabProbe menu"
  fi
fi

# 16. Test Lab → Probe navigation uses established closeMenuAndOpenNewMenu contract.
#     The currently open Test Lab `menu` must be the first argument, not a retrieved menu object.
if [ ! -f "$testlab" ]; then
  note "testlab.lua not found"
else
  # Must use: Helper.closeMenuAndOpenNewMenu(menu, "X4GunneryTestLabProbe", ...)
  if ! grep -q 'Helper.closeMenuAndOpenNewMenu(menu, "X4GunneryTestLabProbe"' "$testlab"; then
    note "testlab.lua must call closeMenuAndOpenNewMenu(menu, \"X4GunneryTestLabProbe\", ...)"
  fi
  # Must NOT use Helper.getMenu as first argument.
  if grep -q 'Helper.getMenu("X4GunneryTestLabProbe")' "$testlab"; then
    note "testlab.lua must not pass Helper.getMenu(\"X4GunneryTestLabProbe\") as first argument"
  fi
fi

# 17. Probe → Test Lab navigation uses established closeMenuAndOpenNewMenu contract.
#     The currently open probe `menu` must be the first argument in both Return button and onCloseElement.
if [ ! -f "$lua" ]; then
  note "probe.lua not found at $lua"
else
  # Return button: must use Helper.closeMenuAndOpenNewMenu(menu, "X4GunneryTestLab", ...)
  if ! grep -q 'Helper.closeMenuAndOpenNewMenu(menu, "X4GunneryTestLab"' "$lua"; then
    note "probe.lua Return button must call closeMenuAndOpenNewMenu(menu, \"X4GunneryTestLab\", ...)"
  fi
  # Must NOT use Helper.getMenu as first argument in Return button.
  if grep -q 'Helper.getMenu("X4GunneryTestLab")' "$lua"; then
    note "probe.lua must not pass Helper.getMenu(\"X4GunneryTestLab\") as first argument"
  fi
  # onCloseElement: must use Helper.closeMenuAndOpenNewMenu(menu, "X4GunneryTestLab", ...)
  if ! grep -A2 'function menu.onCloseElement' "$lua" | grep -q 'Helper.closeMenuAndOpenNewMenu(menu, "X4GunneryTestLab"'; then
    note "probe.lua onCloseElement must call closeMenuAndOpenNewMenu(menu, \"X4GunneryTestLab\", ...)"
  fi
fi

# 18. The diagnostic route cannot call production Prefer behavior.
#     Verify that probe_invoke does not emit prefer_all_turrets or prefer_all_turrets_clear.
if grep -q 'prefer_all_turrets' "$md"; then
  note "probe MD must not reference production prefer_all_turrets events"
fi

# 19. probe.lua must NOT call find_object (unsupported UI-side world search).
#     The target resolution must use the scenario-MD-backed request/response path.
if grep -q 'find_object' "$lua"; then
  note "probe.lua must not call find_object (use scenario MD label lookup instead)"
fi

# 20. probe.lua must request probe target resolution from scenario MD.
if ! grep -q 'probe_target_resolve' "$lua"; then
  note "probe.lua must send probe_target_resolve event to scenario MD"
fi
# Shell-proven transport: MD raises two raw-component events (A and B)
# per request so Lua receives actual component objects, not packed strings.
if ! grep -q 'X4GunneryTestLab.ProbeTargetResolvedA' "$lua"; then
  note "probe.lua must register for X4GunneryTestLab.ProbeTargetResolvedA event"
fi
if ! grep -q 'X4GunneryTestLab.ProbeTargetResolvedB' "$lua"; then
  note "probe.lua must register for X4GunneryTestLab.ProbeTargetResolvedB event"
fi
if ! grep -q 'onProbeTargetResolved' "$lua"; then
  note "probe.lua must define onProbeTargetResolved handler"
fi
if ! grep -q 'requestProbeTargetResolution' "$lua"; then
  note "probe.lua must define requestProbeTargetResolution function"
fi

# 21. Scenario MD must handle probe_target_resolve and return resolved IDs.
scenario_md=testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_scenario.xml
if ! grep -q 'probe_target_resolve' "$scenario_md"; then
  note "scenario MD must handle probe_target_resolve event"
fi
# MD raises two raw-component events keyed by requestId for request correlation.
if ! grep -q 'X4GunneryTestLab.ProbeTargetResolvedA' "$scenario_md"; then
  note "scenario MD must raise X4GunneryTestLab.ProbeTargetResolvedA event"
fi
if ! grep -q 'X4GunneryTestLab.ProbeTargetResolvedB' "$scenario_md"; then
  note "scenario MD must raise X4GunneryTestLab.ProbeTargetResolvedB event"
fi
if ! grep -q 'ProbeTargetResolve' "$scenario_md"; then
  note "scenario MD must have ProbeTargetResolve cue"
fi

# 22. probe.lua must gate invocation on successful target resolution.
#     invokeProbe must check resolveProbeTargets() and fail closed if nil.
if ! grep -q 'resolveProbeTargets' "$lua"; then
  note "probe.lua must call resolveProbeTargets before invocation"
fi
# The menu must show resolving/unresolved status when targets are pending.
if ! grep -q 'resolving' "$lua" && ! grep -q 'unresolved' "$lua"; then
  note "probe.lua menu must show resolving or unresolved status when targets pending"
fi

# 23. Scenario MD must clear probe-label registry on despawn.
# shellcheck disable=SC2016
if ! grep -q 'ScenarioRoot\.\$ProbeLabels' "$scenario_md"; then
  note "scenario MD must create and manage ScenarioRoot.\$ProbeLabels registry"
fi
# Must NOT still reference dead ProbeResolvedA/B variables.
# shellcheck disable=SC2016
if grep -q '\$ProbeResolvedA\|\$ProbeResolvedB' "$scenario_md"; then
  note "scenario MD must not reference dead ProbeResolvedA/B variables"
fi
# Must clear $ProbeLabels on despawn (not just leave dangling references).
# shellcheck disable=SC2016
if ! grep -q 'remove_value.*ScenarioRoot\.\$ProbeLabels' "$scenario_md"; then
  note "scenario MD must remove ScenarioRoot.\$ProbeLabels on despawn"
fi

# 24. [STRENGTHENED] Lua→MD request must use flat scalar keys, not nested tables.
#     The proven contract is: specId, requestId, labelA, labelB as separate flat keys.
if [ -f "$lua" ]; then
  # Extract the AddUITriggeredEvent call for probe_target_resolve and check it.
  probe_event_call=$(awk '/AddUITriggeredEvent.*probe_target_resolve/ { found=1 } found { print } /end$/ && found { exit }' "$lua")
  # Must NOT send a nested labels table in the event call.
  if printf '%s\n' "$probe_event_call" | grep -q 'labels = '; then
    note "probe.lua must not send nested labels table in probe_target_resolve event; use flat scalar keys (labelA, labelB)"
  fi
  # Must send flat scalar keys: specId, requestId, labelA, labelB.
  if ! printf '%s\n' "$probe_event_call" | grep -q 'specId'; then
    note "probe.lua must send specId as a flat scalar in the resolution request"
  fi
  if ! printf '%s\n' "$probe_event_call" | grep -q 'labelA'; then
    note "probe.lua must send labelA as a flat scalar in the resolution request"
  fi
  if ! printf '%s\n' "$probe_event_call" | grep -q 'labelB'; then
    note "probe.lua must send labelB as a flat scalar in the resolution request"
  fi
fi

# 25. [STRENGTHENED] Menu onShowMenu body must call requestProbeTargetResolution.
if [ -f "$lua" ]; then
  # Extract the menu.onShowMenu function body and verify it calls the resolver.
  show_body=$(awk '/function menu\.onShowMenu\(\)/ { found=1; depth=1; print; next }
    found { line=$0; n=gsub(/<do_if/,"<do_if",line); depth+=n
            n=gsub(/<do_elseif/,"<do_elseif",line); depth+=n
            n=gsub(/<do_all/,"<do_all",line); depth+=n
            print; n=gsub(/\/do_if>/,"/do_if>",line); depth-=n
            n=gsub(/\/do_elseif>/,"/do_elseif>",line); depth-=n
            n=gsub(/\/do_all>/,"/do_all>",line); depth-=n
            if (depth==0) exit }' "$lua")
  # For Lua files, use a simpler extractor.
  if ! grep -q '^function menu.onShowMenu()' "$lua"; then
    show_body=$(awk '/^function menu\.onShowMenu\(\)/ { found=1; depth=1; print; next }
      found { line=$0; n=gsub(/function/,"function",line); depth+=n
              n=gsub(/end/,"end",line); depth-=n
              print; if (depth==0) exit }' "$lua")
  fi
  if ! printf '%s\n' "$show_body" | grep -q 'requestProbeTargetResolution'; then
    note "probe.lua menu.onShowMenu must call requestProbeTargetResolution"
  fi
fi

# 26. [STRENGTHENED] MD must read flat scalar label fields, not a nested labels list.
if [ -f "$scenario_md" ]; then
  # Must read $labelA and $labelB from event.param3.
  # shellcheck disable=SC2016
  if ! grep -q 'event\.param3\.\$labelA' "$scenario_md"; then
    note "scenario MD must read labelA flat scalar from event.param3"
  fi
  # shellcheck disable=SC2016
  if ! grep -q 'event\.param3\.\$labelB' "$scenario_md"; then
    note "scenario MD must read labelB flat scalar from event.param3"
  fi
  # Must NOT still use nested $labels list.
  # shellcheck disable=SC2016
  if grep -q 'event\.param3\.\$labels' "$scenario_md"; then
    note "scenario MD must not read nested labels list from event.param3"
  fi
fi

# 27. [STRENGTHENED] MD must use spawn-label registry with iteration, not associative access.
if [ -f "$scenario_md" ]; then
  # Must NOT compare knownname against label (that was the broken approach).
  # shellcheck disable=SC2016
  if grep -A50 'ProbeTargetResolve' "$scenario_md" | grep -q '\$Obj\.knownname == \$Label'; then
    note "scenario MD ProbeTargetResolve must not use knownname comparison; use spawn registry"
  fi
  # Must use the spawn-label registry.
  # shellcheck disable=SC2016
  if ! grep -q 'ScenarioRoot\.\$ProbeLabels' "$scenario_md"; then
    note "scenario MD must create and use ScenarioRoot.\$ProbeLabels registry"
  fi
  # Must NOT use associative table access on the list (the Starting SHA treated
  # a list-of-tables as an associative map, which is structurally invalid).
  # shellcheck disable=SC2016
  if grep -q 'ProbeLabels\.{' "$scenario_md"; then
    note "scenario MD must not use ProbeLabels.\{\$LabelA\} associative access; iterate registry entries instead"
  fi
  # Must iterate the registry with do_for_each over $Entry and compare $Entry.\$label.
  if ! grep -A50 'ProbeTargetResolve' "$scenario_md" | grep -q 'do_for_each.*\$Entry.*in=.*ScenarioRoot\.\$ProbeLabels'; then
    note "scenario MD ProbeTargetResolve must iterate ScenarioRoot.\$ProbeLabels with do_for_each"
  fi
  # Must compare each entry's stored exact label against $LabelA / $LabelB.
  if ! grep -A50 'ProbeTargetResolve' "$scenario_md" | grep -q '\$Entry\.\$label == \$LabelA'; then
    note "scenario MD ProbeTargetResolve must compare \$Entry.\$label against \$LabelA"
  fi
  # Registry append must store fixed-shape entries with $label and $object keys.
  if ! grep -q 'append_to_list.*ScenarioRoot\.\$ProbeLabels.*exact=.*table\[\$label.*\$object' "$scenario_md"; then
    note "scenario MD must append fixed-shape table[\$label, \$object] entries to ScenarioRoot.\$ProbeLabels"
  fi
fi

# 28. [STRENGTHENED] MD must validate specId to reject stale requests.
if [ -f "$scenario_md" ]; then
  # shellcheck disable=SC2016
  if ! grep -A40 'ProbeTargetResolve' "$scenario_md" | grep -q '\$SpawnedSpecId'; then
    note "scenario MD ProbeTargetResolve must validate specId against ScenarioRoot.\$SpawnedSpecId"
  fi
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "testlab probe contract tests passed"
