#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
loadouts=testlab/x4_gunnery_control_testlab/libraries/loadouts.xml
scenario=testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_scenario.xml
ui=testlab/x4_gunnery_control_testlab/ui/testlab.lua
fail() { echo "issue69 combined fixture contract: $*" >&2; exit 1; }
lua_bin=$(command -v lua5.1 || command -v lua || true)
[[ -n "$lua_bin" ]] || fail "Lua 5.1 interpreter not found"

python3 - "$loadouts" <<'PY'
import hashlib, sys, xml.etree.ElementTree as ET
path = sys.argv[1]
root = ET.parse(path).getroot()
byid = {x.get('id'): x for x in root.findall('loadout')}
new = byid.get('x4gc_testlab_issue69_paranid_dual_family')
assert new is not None and new.get('macro') == 'ship_par_l_destroyer_01_a_macro'
turrets = new.findall('./groups/turrets')
assert len(turrets) == 2
groups = [x.get('group') for x in turrets]
assert groups == ['group_front_up_mid2', 'group_rear_down_mid']
assert len(set(groups)) == 2
assert [(x.get('macro'), x.get('exact')) for x in turrets] == [
    ('turret_par_l_plasma_01_mk1_macro', '1'),
    ('turret_par_l_beam_01_mk1_macro', '1'),
]
assert all('missile' not in (x.get('macro') or '') for x in turrets)
assert not new.findall('./macros/weapon')
def canonical(node):
    for child in node.iter():
        child.tail = None
    return ET.tostring(node)
old_hashes = {
    'x4gc_testlab_issue67_colossus_arc_barrel': '6d5c3f233e26e621ce29370d10bd95cc18f97529123c79cf1acc08e7be412133',
    'x4gc_testlab_issue67_paranid_sky_survey': 'd7352f809fe7261392fb821bcab2201131f532f2bc3b9ff7a9f613577e83da55',
    'x4gc_testlab_issue67_argon_sky_target': '3067c6738f1320937d2be824c8be1022ca1f996df8a656d815e5c5e30ba3181b',
}
for ident, digest in old_hashes.items():
    assert ident in byid, ident
    actual = hashlib.sha256(canonical(byid[ident])).hexdigest()
    assert actual == digest, f'pre-existing loadout changed: {ident}'
PY

"$lua_bin" <<'LUA'
local s = dofile('testlab/x4_gunnery_control_testlab/ui/scenario_spec.lua')
assert(s.enabled == false)
assert(s.id == 'issue-69-combined-three-role-r2')
assert(s.setup.selectAll == false)
assert(s.setup.turretGroup == 'group_front_up_mid2' and s.setup.expectedTurrets == 1)
assert(s.setup.expectedMemberMacros[1] == 'turret_par_l_plasma_01_mk1_macro')
assert(s.setup.secondaryTurretGroup == 'group_rear_down_mid')
assert(s.setup.secondaryExpectedTurrets == 1)
assert(s.setup.secondaryExpectedMemberMacros[1] == 'turret_par_l_beam_01_mk1_macro')
local role, hostile, labels = {}, 0, {}
for _, g in ipairs(s.groups) do
  assert(not labels[g.label]); labels[g.label] = true
  if g.fixtureRole then role[g.fixtureRole] = (role[g.fixtureRole] or 0) + 1 end
  if g.hostile and g.fixtureRole then hostile = hostile + 1 end
end
assert(#s.groups == 5 and hostile == 3)
assert(role.mid_engine == 1 and role.near_blocked == 1 and role.far_clear == 1 and role.near_blocker == 1)
local mid = s.groups[2]
assert(mid.label == 'ISSUE ENGINE STRADDLE ARGON')
assert(mid.macro == 'ship_arg_l_destroyer_02_a_macro')
assert(mid.ox == -40.345 and mid.oy == 670.435 and mid.oz == -45.015)
assert(mid.yaw == 213 and mid.pitch == 81 and mid.roll == 132 and mid.preserveOrientation == true)
assert(mid.geometryRole == 'surface_mask' and mid.geometryCase == 'engine_straddle')
assert(s.groups[3].loadout == 'issue67_argon_sky_target' and s.groups[4].loadout == 'issue67_argon_sky_target')
assert(s.groups[3].fixtureRole == 'near_blocked' and s.groups[4].fixtureRole == 'far_clear'
    and s.groups[3].geometryRole == nil and s.groups[4].geometryRole == nil)
assert(s.groups[5].hostile == false and s.groups[5].repairGuard == true)
LUA

switch=$(awk '/local function selectFarTestGroup\(\)/{f=1} f{print} /local function createTestScenario\(\)/{exit}' "$ui")
[[ "$switch" == *'resolveExactGroup("secondary")'* ]] || fail "FAR switch does not revalidate secondary exact group"
[[ "$switch" == *'applyExactGroup(secondary)'* ]] || fail "FAR switch does not reuse exact-group selection"
[[ "$switch" != *'toggleAllGroups'* && "$switch" != *'selectAll'* ]] || fail "FAR switch uses select-all path"
[[ "$switch" == *'checkedCount ~= 1'* && "$switch" == *'far_group_select'* ]] || fail "FAR switch lacks exact post-selection verification/log"

grep -Fq "\$fixturerole = if @event.param3.\$fixtureRole" "$scenario" || fail "fixtureRole is not transported"
sparse_remote=$(awk "/<do_elseif value=\"\\\$Def.\\\$loadout == 'issue67_argon_sky_target'.*near_blocked/{f=1} f{print} f && /<\\/do_elseif>/{exit}" "$scenario")
[[ "$sparse_remote" == *"if \$Def.\$geometryrole == 'surface_mask' then \$PStar.x + \$Def.\$ox else ScenarioRoot.\$PendingAnchorX + \$Def.\$x"* \
   && "$sparse_remote" == *"if \$Def.\$geometryrole == 'surface_mask' then \$PStar.y + \$Def.\$oy else ScenarioRoot.\$PendingAnchorY + \$Def.\$y"* \
   && "$sparse_remote" == *"if \$Def.\$geometryrole == 'surface_mask' then \$PStar.z + \$Def.\$oz else ScenarioRoot.\$PendingAnchorZ + \$Def.\$distance"* ]] \
  || fail "remote surface_mask spawn must restore its historical PStar+ox/oy/oz while NEAR/FAR keep anchor positions"
grep -Fq "near_formula=plasma_local_z_450 far_formula=beam_local_z_-0.70_maxrange blocker_formula=plasma_local_z_180" "$scenario" || fail "role placement formulas missing"
settle=$(awk '/<cue name="GeometryQualifySettle"/{f=1} f{print} f && /^[[:space:]]*<\/cue>/{exit}' "$scenario")
measure=$(awk '/<cue name="GeometryQualifyMeasure"/{f=1} f{print} f && /^[[:space:]]*<\/cue>/{exit}' "$scenario")
[[ "$settle" == *"<delay exact=\"if event.param.\$settleIssue69 then 3s else 0s\"/>"* ]] || fail "combined fixture lacks its three-second settled measurement boundary"
[[ "$settle" == *"ScenarioRoot.\$GeometryQualifyRequestId == \$RequestId"* && "$settle" == *"action=stale_ignored"* ]] || fail "delayed qualification release is not guarded against stale requests"
[[ "$measure" == *"ScenarioRoot.\$GeometryQualifyRequestId == \$RequestId"* && "$measure" == *"action=stale_ignored"* ]] || fail "released measurement is not guarded against a replaced request"
delay_line=$(grep -nF "<delay exact=\"if event.param.\$settleIssue69 then 3s else 0s\"/>" "$scenario" | cut -d: -f1)
release_line=$(grep -nF "<signal_cue cue=\"GeometryQualifyMeasure\"/>" "$scenario" | cut -d: -f1)
near_los_line=$(grep -nF "name=\"\$NearFastLosSelf\"" "$scenario" | cut -d: -f1)
near_final_line=$(grep -nF "name=\"\$NearQualified\" exact=\"\$NearMayAttack" "$scenario" | cut -d: -f1)
far_final_line=$(grep -nF "name=\"\$FarQualified\" exact=\"\$FarMayAttack" "$scenario" | cut -d: -f1)
[[ "$delay_line" -lt "$release_line" && "$release_line" -lt "$near_los_line" && "$near_los_line" -lt "$near_final_line" && "$near_final_line" -lt "$far_final_line" ]] || fail "post-warp LOS/final role gates are not downstream of settling"
[[ $(grep -c "name=\"\$NearQualified\"" "$scenario") -eq 2 && $(grep -c "name=\"\$FarQualified\"" "$scenario") -eq 2 ]] || fail "an immediate alternate NEAR/FAR qualification path exists"
grep -Fq "z=\"\$BeamWeapon.maxfirerange * -0.70\"" "$scenario" || fail "FAR is not placed from live Beam max range"
if grep -Fq "and \$NearRange le \$MidRange * 0.75" "$scenario"; then fail "NEAR must not require a relative distance to MID"; fi
grep -Fq "\$NearBboxLocal.pitch ge -5deg and \$NearBboxLocal.pitch le 80deg" "$scenario" || fail "NEAR bbox arc gate missing"
grep -Fq "name=\"\$NearFastLosSelf\" object=\"\$Issue69Plasma\" objectoffset=\"\$Issue69Plasma.barrelposition\" target=\"\$NearRoleSurface\" useaimtarget=\"true\" excludeself=\"false\"" "$scenario" || fail "NEAR production fast LOS negative missing"
grep -Fq "name=\"\$NearSampleLosSelf\" object=\"\$Issue69Plasma\" objectoffset=\"\$Issue69Plasma.barrelposition\" target=\"\$NearRoleSurface\" targetoffset=\"\$NearSample\" useaimtarget=\"false\" excludeself=\"false\"" "$scenario" || fail "NEAR production fallback samples missing"
grep -Fq "name=\"\$NearSampleLosEx\" object=\"\$Issue69Plasma\" objectoffset=\"\$Issue69Plasma.barrelposition\" target=\"\$NearRoleSurface\" targetoffset=\"\$NearSample\" useaimtarget=\"false\" excludeself=\"true\"" "$scenario" || fail "NEAR external-obstruction controls missing"
for list in '[0.25, 0.75, 0.50, 0.50, 0.50, 0.50]' '[0.50, 0.50, 0.25, 0.75, 0.50, 0.50]' '[0.50, 0.50, 0.50, 0.50, 0.25, 0.75]'; do
  grep -Fq "$list" "$scenario" || fail "missing production six-sample fraction list $list"
done
grep -Fq "\$NearSampleClearSelf == 0 and \$NearSampleClearEx == 0" "$scenario" || fail "NEAR does not require all six production/external rays blocked"
grep -Fq "not \$NearFastLosSelf and not \$NearFastLosEx" "$scenario" || fail "NEAR gate does not require both fast LOS rays blocked"
[[ "$measure" != *"<warp "* ]] || fail "settled measurement repositions objects"
[[ "$settle" == *"name=\"\$RequestId\" exact=\"event.param.\$requestId\""* ]] || fail "settle guard does not use the signalled request token"
grep -Fq "<create_position name=\"\$NearSettledPlasmaLocal\" object=\"\$NearRoleSurface\" space=\"\$Issue69Plasma\"/>" "$scenario" || fail "settled NEAR surface is not measured in Plasma space"
grep -Fq "<create_position name=\"\$BlockerSettledPlasmaLocal\" object=\"ScenarioRoot.\$NearBlocker\" space=\"\$Issue69Plasma\"/>" "$scenario" || fail "settled blocker root is not measured in Plasma space"
grep -Fq "<create_position name=\"\$FarSettledBeamLocal\" object=\"\$FarRoleSurface\" space=\"\$Issue69Beam\"/>" "$scenario" || fail "settled FAR surface is not measured in Beam space"
grep -Fq "[X4GC TEST QUALIFY FAR FRAME]" "$scenario" || fail "FAR Beam frame telemetry line missing"
grep -Fq "x=\"0m\" y=\"0m\" z=\"100m\" space=\"ScenarioRoot.\$GeometryShooter\"" "$scenario" || fail "FAR +Z frame probe missing"
grep -Fq "x=\"0m\" y=\"0m\" z=\"-100m\" space=\"ScenarioRoot.\$GeometryShooter\"" "$scenario" || fail "FAR -Z frame probe missing"
grep -Fq "<set_value name=\"\$Issue69PoseTolerance\" exact=\"10m\"/>" "$scenario" || fail "settled pose tolerance is not small and explicit"
grep -Fq "\$NearSettledPlasmaLocal.z ge 450m - \$Issue69PoseTolerance" "$scenario" || fail "settled NEAR is not checked against plasma-local 450m"
grep -Fq "\$BlockerSettledPlasmaLocal.z ge 180m - \$Issue69PoseTolerance" "$scenario" || fail "settled blocker is not checked against plasma-local 180m"
grep -Fq "<set_value name=\"\$FarSettledExpectedZ\" exact=\"\$Issue69Beam.maxfirerange * -0.70\"/>" "$scenario" || fail "settled FAR is not checked against live -0.70 max range"
grep -Fq "[X4GC TEST QUALIFY SETTLED POSE]" "$scenario" || fail "settled pose measurement is not logged"
grep -Fq "\$NearSettledPoseValid and \$BlockerSettledPoseValid" "$scenario" || fail "NEAR final gate lacks settled position checks"
grep -Fq "<set_value name=\"\$BlockerShooterDistance\" exact=\"ScenarioRoot.\$NearBlocker.bboxdistanceto.{ScenarioRoot.\$GeometryShooter}\"/>" "$scenario" || fail "blocker-shooter clearance distance is not computed"
grep -Fq "<set_value name=\"\$BlockerNearDistance\" exact=\"ScenarioRoot.\$NearBlocker.bboxdistanceto.{ScenarioRoot.\$NearTarget}\"/>" "$scenario" || fail "blocker-NEAR clearance distance is not computed"
grep -Fq "' blocker_shooter_distance=' + \$BlockerShooterDistance + ' blocker_near_distance=' + \$BlockerNearDistance" "$scenario" || fail "blocker clearance distances are not logged"
grep -Fq "\$FarSettledPoseValid and ScenarioRoot.\$Issue69RoleRepositionFailures" "$scenario" || fail "FAR final gate lacks settled position check"
grep -Fq "\$FarRangeRatio ge 0.65 and \$FarRangeRatio le 0.75" "$scenario" || fail "FAR live-range tolerance missing"
grep -Fq 'turret_par_l_beam_01_mk1.xml:187-192 authors rotation_x' "$scenario" || fail "Beam arc lacks shipped-source evidence"
grep -Fq "name=\"\$FarArcPass\" exact=\"\$FarBboxLocal.pitch ge -5deg and \$FarBboxLocal.pitch le 80deg\"" "$scenario" || fail "FAR does not use the authored Beam -5..80 degree arc"
grep -Fq "(\$FarFastLosSelf or \$FarSampleClearSelf gt 0)" "$scenario" || fail "FAR production clear-path gate missing"
grep -Fq "and \$NearQualified and \$FarQualified" "$scenario" || fail "combined qualifier does not fail closed on both controls"
grep -Fq "<set_value name=\"ScenarioRoot.\$Issue69RoleRepositionFailures\" exact=\"0\"/>" "$scenario" || fail "combined reposition failure counter is not initialized"
grep -Fq "\$EngineStraddleSurface != null and \$Issue69PlasmaCount == 1" "$scenario" || fail "combined role qualifier does not guard MID before distance correlation"
if grep -E 'SurfaceMaskPlacements.*(NearTarget|FarTarget|NearBlocker)' "$scenario"; then fail "unmarked roles entered MID objective placements"; fi
if grep -E 'GeometryQualifiedTarget.*(Near|Far)' "$scenario"; then fail "NEAR/FAR crossed the marked-objective bridge"; fi

issue69_state=$(awk '/<cue name="Issue69ObserveState"/{f=1} f{print} /<cue name="Issue69StateLog"/{g=1} g{print} g && /<\/cue>/{exit}' "$scenario")
[[ "$issue69_state" == *'control="'"'observe_state'"'"'* ]] || fail "Issue69 post trigger does not consume Observer state"
[[ "$issue69_state" == *"@event.param3.\$aimtgt == ScenarioRoot.\$Issue69FarSurface"* ]] || fail "Issue69 post trigger is not exact FAR-surface aimtgt equality"
[[ "$issue69_state" == *"not ScenarioRoot.\$Issue69PostBurstIssued"* && "$issue69_state" == *"ScenarioRoot.\$Issue69PostBurstIssued\" exact=\"true\""* ]] || fail "Issue69 post trigger is not deduplicated"
for delay in '0s' '500ms' '1s' '2s' '3s'; do
  [[ "$issue69_state" == *"\$phase = 'after', \$delay = $delay"* ]] || fail "Issue69 post burst missing $delay sample"
done
grep -Fq "cue=\"Issue69StateLog\" param=\"table[\$phase = 'before', \$delay = 0s" "$scenario" || fail "Issue69 settled pre-designation state missing"
state_before_line=$(grep -nF "cue=\"Issue69StateLog\" param=\"table[\$phase = 'before'" "$scenario" | cut -d: -f1)
far_gate_line=$(grep -nF "name=\"\$FarQualified\" exact=\"\$FarMayAttack" "$scenario" | tail -1 | cut -d: -f1)
[[ "$state_before_line" -lt "$far_gate_line" ]] || fail "Issue69 before state is not emitted before FAR LOS qualification"
for field in weapon= weapon_macro= surface= surface_macro= mode= ready= mount_base= mount_yaw= mount_pitch= mount_roll= barrel_raw= muzzle_base= bbox_range= maxrange= bbox_pitch= fast_los_self= fast_los_ex= six_clear_self= six_clear_ex=; do
  [[ "$issue69_state" == *"$field"* ]] || fail "Issue69 state record missing $field"
done
[[ "$issue69_state" == *"value=\"\$Barrel\""* ]] || fail "Issue69 state does not transform the raw barrel position when schema-supported"
[[ "$issue69_state" == *"object=\"\$Weapon\" objectoffset=\"\$Weapon.barrelposition\" target=\"\$Surface\" useaimtarget=\"true\" excludeself=\"false\""* ]] || fail "Issue69 state lost self-inclusive fast LOS"
[[ "$issue69_state" == *"object=\"\$Weapon\" objectoffset=\"\$Weapon.barrelposition\" target=\"\$Surface\" targetoffset=\"\$Sample\" useaimtarget=\"false\" excludeself=\"false\""* ]] || fail "Issue69 state lost self-inclusive fallback LOS"
if grep -E 'Issue69(StateLog|ObserveState).*\.idcode' "$scenario"; then fail "Issue69 state uses forbidden surface idcode"; fi
if [[ "$issue69_state" =~ SetSofttarget|set_softtarget|set_weapon_mode|\.mode[[:space:]]*=|select_target|selectTarget ]]; then fail "Issue69 telemetry mutates target or weapon mode"; fi
grep -Fq "ScenarioRoot.\$Issue69FarBeam\" exact=\"\$Issue69Beam\"" "$scenario" || fail "exact FAR Beam is not persisted"
grep -Fq "ScenarioRoot.\$Issue69FarSurface\" exact=\"\$FarRoleSurface\"" "$scenario" || fail "exact FAR surface is not persisted"

echo "issue69 combined fixture contract passed"
