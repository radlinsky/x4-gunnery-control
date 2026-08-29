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
[[ "$switch" == *'onlyExactGroupSelected(secondary)'* && "$switch" == *'far_group_select'* ]] || fail "FAR switch lacks exact post-selection verification/log"

far_handoff=$(awk '/local function handoffFarOriginDiscriminator\(request\)/{f=1} f{print} /-- Phase-two acknowledgement/{exit}' "$ui")
[[ "$far_handoff" == *'resolveExactGroup("secondary")'* && "$far_handoff" == *'secondary.shipID ~= request.selection.shipID'* ]] || fail "FAR-origin handoff does not revalidate the exact Beam group on the same shooter"
[[ "$far_handoff" == *'applyExactGroup(secondary)'* && "$far_handoff" == *'onlyExactGroupSelected(secondary)'* ]] || fail "FAR-origin handoff does not apply only the exact secondary group"
[[ "$far_handoff" == *'suggestTestEngagement(request.farOriginComponent'* ]] || fail "FAR-origin handoff does not mark the transported exact FAR surface"
[[ "$far_handoff" == *'combinedFixtureQualified = false'* && "$far_handoff" == *'overall_combined_qualified = "false"'* ]] || fail "FAR-origin handoff incorrectly qualifies the combined fixture"
[[ "$far_handoff" == *'event=far_origin_handoff'* || "$far_handoff" == *'log("far_origin_handoff"'* ]] || fail "FAR-origin handoff lacks a distinct audit event"
if [[ "$far_handoff" =~ SetSofttarget|set_softtarget|set_weapon_mode|select_target|selectTarget|directMode[[:space:]]*= ]]; then fail "FAR-origin handoff automates Direct-control designation"; fi
far_handlers=$(awk '/local function onFarOriginReadyTargetToken/{f=1} f{print} /local function handoffFarOriginDiscriminator/{exit}' "$ui")
[[ "$far_handlers" == *'tostring(token or "") ~= pendingQualify.requestId'* && "$far_handlers" == *'farOriginTokenAuthorized'* && "$far_handlers" == *'farOriginComponent = component'* ]] || fail "dedicated FAR component transport is not request-token-correlated"
geometry_handler=$(awk '/local function onGeometryQualified\(_, param\)/{f=1} f{print} /local function shipFields/{exit}' "$ui")
[[ "$geometry_handler" == *'request.issue69Combined and qualified == 0'* && "$geometry_handler" == *'request.farOriginComponent ~= nil'* && "$geometry_handler" == *'handoffFarOriginDiscriminator(request)'* ]] || fail "fallback handoff is not restricted to failed Issue69 combined plus FAR-origin-ready"
grep -Fq 'RegisterEvent("X4GunneryTestLab.FarOriginReadyTargetToken", onFarOriginReadyTargetToken)' "$ui" || fail "FAR-origin token event is not registered"
grep -Fq 'RegisterEvent("X4GunneryTestLab.FarOriginReadyTarget", onFarOriginReadyTarget)' "$ui" || fail "FAR-origin component event is not registered"

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
grep -Fq "<set_value name=\"\$FarQualified\" exact=\"\$FarMayAttack and \$FarInRange and \$FarArcPass and \$FarRangeRatio ge 0.65 and \$FarRangeRatio le 0.75 and (\$FarFastLosSelf or \$FarSampleClearSelf gt 0) and (\$FarFastLosEx or \$FarSampleClearEx gt 0) and \$FarSettledPoseValid and ScenarioRoot.\$Issue69RoleRepositionFailures == 0\"/>" "$scenario" || fail "FAR qualification expression changed"
far_origin_ready=$(grep -F "name=\"\$FarOriginReady\" exact=\"\$Issue69Beam ==" "$scenario")
[[ "$far_origin_ready" == *"\$Issue69Beam == ScenarioRoot.\$Issue69FarBeam"* && "$far_origin_ready" == *"\$FarRoleSurface == ScenarioRoot.\$Issue69FarSurface"* && "$far_origin_ready" == *"\$FarMayAttack and \$FarInRange and \$FarArcPass"* && "$far_origin_ready" == *"\$FarRangeRatio ge 0.65 and \$FarRangeRatio le 0.75"* && "$far_origin_ready" == *"\$FarSettledPoseValid and ScenarioRoot.\$Issue69RoleRepositionFailures == 0"* ]] || fail "FAR-origin-ready lacks its exact persisted pair and non-LOS gates"
if [[ "$far_origin_ready" =~ Los|LOS|Near|Blocker|ClearSelf|ClearEx ]]; then fail "FAR-origin-ready depends on LOS or NEAR/blocker geometry"; fi
far_origin_token_line=$(grep -nF "X4GunneryTestLab.FarOriginReadyTargetToken" "$scenario" | cut -d: -f1)
far_origin_component_line=$(grep -nF "X4GunneryTestLab.FarOriginReadyTarget'" "$scenario" | cut -d: -f1)
terminal_geometry_line=$(grep -nF "X4GunneryTestLab.GeometryQualified'" "$scenario" | tail -1 | cut -d: -f1)
[[ "$far_origin_token_line" -lt "$far_origin_component_line" && "$far_origin_component_line" -lt "$terminal_geometry_line" ]] || fail "dedicated FAR token/component pair is not emitted before terminal GeometryQualified"
grep -Fq "<do_if value=\"\$Issue69Combined and \$FarOriginReady\">" "$scenario" || fail "dedicated FAR transport is not gated on Issue69 combined readiness"
grep -Fq "name=\"'X4GunneryTestLab.FarOriginReadyTargetToken'\" param=\"\$RequestId\"" "$scenario" || fail "dedicated FAR transport lacks the current request token"
grep -Fq "name=\"'X4GunneryTestLab.FarOriginReadyTarget'\" param=\"ScenarioRoot.\$Issue69FarSurface\"" "$scenario" || fail "dedicated FAR transport does not carry the exact persisted surface"
grep -Fq "and \$NearQualified and \$FarQualified" "$scenario" || fail "combined qualifier does not fail closed on both controls"
grep -Fq "<set_value name=\"ScenarioRoot.\$Issue69RoleRepositionFailures\" exact=\"0\"/>" "$scenario" || fail "combined reposition failure counter is not initialized"
grep -Fq "\$EngineStraddleSurface != null and \$Issue69PlasmaCount == 1" "$scenario" || fail "combined role qualifier does not guard MID before distance correlation"
if grep -E 'SurfaceMaskPlacements.*(NearTarget|FarTarget|NearBlocker)' "$scenario"; then fail "unmarked roles entered MID objective placements"; fi
if grep -E 'GeometryQualifiedTarget.*(Near|Far)' "$scenario"; then fail "NEAR/FAR crossed the marked-objective bridge"; fi

issue69_matrix=$(awk '/<cue name="Issue69MatrixSampler"/{f=1} f{print} f && /^[[:space:]]*<\/cue>/{exit}' "$scenario")
issue69_timer_a=$(awk '/<cue name="Issue69MatrixTimerA"/{f=1} f{print} f && /^[[:space:]]*<\/cue>/{exit}' "$scenario")
issue69_timer_b=$(awk '/<cue name="Issue69MatrixTimerB"/{f=1} f{print} f && /^[[:space:]]*<\/cue>/{exit}' "$scenario")
issue69_timers="$issue69_timer_a$issue69_timer_b"
[[ "$issue69_matrix" == *"ScenarioRoot.\$Issue69StateActive? and ScenarioRoot.\$Issue69StateActive"* && "$issue69_matrix" == *"ScenarioRoot.\$Issue69StateRequestId == \$RequestId"* ]] || fail "Issue69 matrix persistence is not bounded by active state/current request"
[[ "$issue69_matrix" != *"<signal_cue cue=\"Issue69MatrixSampler\""* && "$issue69_matrix" != *"<signal_cue_instantly cue=\"Issue69MatrixSampler\""* ]] || fail "regression: e0e6ff active Issue69 matrix worker signals itself"
[[ "$issue69_matrix" != *"<reset_cue"* ]] || fail "Issue69 matrix worker resets itself"
[[ "$issue69_timers" != *"Issue69MatrixPeriodic"* && "$issue69_timers" != *"<check_value"* ]] || fail "regression: ea5e3c4 non-event Issue69 periodic condition remains"
[[ "$issue69_timers" != *"<reset_cue"* && "$issue69_timers" != *"checkinterval="* ]] || fail "Issue69 sibling timers use reset or polling recurrence"

for timer_name in A B; do
  timer_var="issue69_timer_$(tr 'AB' 'ab' <<<"$timer_name")"
  timer=${!timer_var}
  [[ "$timer" == *"<cue name=\"Issue69MatrixTimer$timer_name\" instantiate=\"true\">"* ]] || fail "Issue69 Timer$timer_name is not instantiated"
  [[ "$timer" == *"<conditions>"* && "$timer" == *"<event_cue_signalled/>"* ]] || fail "Issue69 Timer$timer_name lacks an event condition"
  [[ "$timer" == *"<delay exact=\"1s\"/>"* ]] || fail "Issue69 Timer$timer_name lacks a real one-second delay"
  [[ "$timer" == *"ScenarioRoot.\$Issue69StateActive? and ScenarioRoot.\$Issue69StateActive and ScenarioRoot.\$Issue69StateRequestId == \$RequestId"* ]] || fail "Issue69 Timer$timer_name lacks its fail-closed state/token guard"
  [[ "$timer" == *"ScenarioRoot.\$Issue69MatrixTick\" operation=\"add\""* ]] || fail "Issue69 Timer$timer_name does not increment the monotonic tick"
  [[ "$timer" == *"signal_cue_instantly cue=\"Issue69MatrixSampler\" param=\"table[\$tick = ScenarioRoot.\$Issue69MatrixTick, \$requestId = \$RequestId]"* ]] || fail "Issue69 Timer$timer_name does not signal the matrix sampler"
done
[[ "$issue69_timer_a" == *"signal_cue_instantly cue=\"Issue69MatrixTimerB\" param=\"table[\$requestId = \$RequestId]"* && "$issue69_timer_a" != *"signal_cue_instantly cue=\"Issue69MatrixTimerA\""* ]] || fail "Issue69 TimerA does not wake only TimerB"
[[ "$issue69_timer_b" == *"signal_cue_instantly cue=\"Issue69MatrixTimerA\" param=\"table[\$requestId = \$RequestId]"* && "$issue69_timer_b" != *"signal_cue_instantly cue=\"Issue69MatrixTimerB\""* ]] || fail "Issue69 TimerB does not wake only TimerA"
for timer in "$issue69_timer_a" "$issue69_timer_b"; do
  guard_line=$(grep -nF "<do_if value=\"ScenarioRoot.\$Issue69StateActive?" <<<"$timer" | cut -d: -f1)
  tick_line=$(grep -nF "ScenarioRoot.\$Issue69MatrixTick\" operation=\"add\"" <<<"$timer" | cut -d: -f1)
  sampler_line=$(grep -nF 'signal_cue_instantly cue="Issue69MatrixSampler"' <<<"$timer" | cut -d: -f1)
  successor_line=$(grep -nF 'signal_cue_instantly cue="Issue69MatrixTimer' <<<"$timer" | cut -d: -f1)
  [[ "$guard_line" -lt "$tick_line" && "$tick_line" -lt "$sampler_line" && "$sampler_line" -lt "$successor_line" ]] || fail "Issue69 timer does not guard, increment, sample, then wake its sibling"
done

sampler_start_line=$(grep -nF "cue=\"Issue69MatrixSampler\" param=\"table[\$tick = 0" "$scenario" | cut -d: -f1)
timer_a_start_line=$(grep -nF "cue=\"Issue69MatrixTimerA\" param=\"table[\$requestId = \$RequestId]" "$scenario" | head -1 | cut -d: -f1)
far_gate_line=$(grep -nF "name=\"\$FarQualified\" exact=\"\$FarMayAttack" "$scenario" | tail -1 | cut -d: -f1)
[[ "$sampler_start_line" -lt "$timer_a_start_line" && "$timer_a_start_line" -lt "$far_gate_line" && "$timer_a_start_line" -lt "$far_origin_token_line" ]] || fail "Issue69 synchronous tick zero/TimerA start does not precede designation transport"
[[ "$issue69_matrix" != *observe_state* && "$issue69_matrix" != *aimtgt* ]] || fail "Issue69 matrix still depends on owner designation"
if grep -Eq 'Issue69(StateLog|ObserveState|PostBurstIssued)' "$scenario"; then fail "bounded designation-triggered Issue69 burst remains"; fi
if [[ "$issue69_matrix$issue69_timers" == *"\$delay = 500ms"* || "$issue69_matrix$issue69_timers" == *"\$delay = 2s"* || "$issue69_matrix$issue69_timers" == *"\$delay = 3s"* ]]; then fail "Issue69 matrix retains a fixed burst endpoint"; fi

[[ "$issue69_matrix" == *"in=\"\$Shooter.turrets.operational.list\""* ]] || fail "Issue69 matrix does not enumerate every live operational shooter turret"
for role in MID NEAR FAR; do
  [[ "$issue69_matrix" == *"table[\$role = '$role', \$root = "* ]] || fail "Issue69 matrix does not enumerate the $role target root"
done
[[ "$issue69_matrix" == *"find_object_component name=\"\$LiveSurfaces\" object=\"\$TargetRoot\" surfaceelement=\"true\" multiple=\"true\" state=\"componentstate.operational\""* && "$issue69_matrix" == *"in=\"\$LiveSurfaces\""* ]] || fail "Issue69 matrix does not rediscover every operational surface live on each role root"

for field in request_id= tick= t= weapon= weapon_macro= mode= ready= mount_shooter= mount_yaw= mount_pitch= mount_roll= barrel_raw= muzzle_shooter= target_root= role= surface= surface_macro= surface_class= bbox_range= maxrange= inrange= relative_yaw= relative_pitch= relative_roll= bbox_yaw= bbox_pitch= bbox_roll= aim_yaw= aim_pitch= aim_roll= mayattack= barrel_fast_self= barrel_fast_ex= implicit_fast_self= implicit_fast_ex= zero_fast_self= zero_fast_ex=; do
  [[ "$issue69_matrix" == *"$field"* ]] || fail "Issue69 matrix record missing $field"
done
[[ $(grep -cF '[X4GC TEST ISSUE69 MATRIX]' "$scenario") -eq 1 ]] || fail "Issue69 matrix must emit one compact base record per pair source path"
[[ "$issue69_matrix" == *"value=\"\$Barrel\""* ]] || fail "Issue69 matrix does not transform current barrelposition into shooter space"
for self in false true; do
  [[ "$issue69_matrix" == *"object=\"\$Weapon\" objectoffset=\"\$Weapon.barrelposition\" target=\"\$Surface\" useaimtarget=\"true\" excludeself=\"$self\""* ]] || fail "matrix lost barrel-origin fast LOS excludeself=$self"
  implicit_line=$(grep -F "object=\"\$Weapon\" target=\"\$Surface\" useaimtarget=\"true\" excludeself=\"$self\"" <<<"$issue69_matrix" || true)
  [[ -n "$implicit_line" && "$implicit_line" != *objectoffset=* ]] || fail "matrix implicit fast LOS must omit objectoffset for excludeself=$self"
  [[ "$issue69_matrix" == *"object=\"\$Weapon\" objectoffset=\"position.[0m,0m,0m]\" target=\"\$Surface\" useaimtarget=\"true\" excludeself=\"$self\""* ]] || fail "matrix explicit-zero fast LOS missing excludeself=$self"
done
[[ "$issue69_matrix" == *"name=\"\$FastSignature\""* && "$issue69_matrix" == *"name=\"\$PreviousSignature\""* && "$issue69_matrix" == *"name=\"\$Changed\" exact=\"\$HadPrevious and \$PreviousSignature != \$FastSignature\""* ]] || fail "matrix does not compare all six fast-origin results with the preceding tick"

[[ "$issue69_matrix" == *"name=\"\$ExactFarPair\" exact=\"\$Weapon == ScenarioRoot.\$Issue69FarBeam and \$Surface == ScenarioRoot.\$Issue69FarSurface\""* && "$issue69_matrix" == *"name=\"\$Detailed\" exact=\"\$ExactFarPair or \$Changed\""* && "$issue69_matrix" == *"<do_if value=\"\$Detailed\">"* ]] || fail "full six-witness expansion is not every-tick FAR plus changed-pair only"
for list in '[0.25, 0.75, 0.50, 0.50, 0.50, 0.50]' '[0.50, 0.50, 0.25, 0.75, 0.50, 0.50]' '[0.50, 0.50, 0.50, 0.50, 0.25, 0.75]'; do
  [[ "$issue69_matrix" == *"$list"* ]] || fail "Issue69 detailed matrix six-sample list changed: $list"
done
for self in false true; do
  [[ "$issue69_matrix" == *"object=\"\$Weapon\" objectoffset=\"\$Weapon.barrelposition\" target=\"\$Surface\" targetoffset=\"\$Sample\" useaimtarget=\"false\" excludeself=\"$self\""* ]] || fail "detailed matrix lost barrel witnesses excludeself=$self"
  implicit_line=$(grep -F "object=\"\$Weapon\" target=\"\$Surface\" targetoffset=\"\$Sample\" useaimtarget=\"false\" excludeself=\"$self\"" <<<"$issue69_matrix" || true)
  [[ -n "$implicit_line" && "$implicit_line" != *objectoffset=* ]] || fail "detailed implicit witnesses must omit objectoffset for excludeself=$self"
  [[ "$issue69_matrix" == *"object=\"\$Weapon\" objectoffset=\"position.[0m,0m,0m]\" target=\"\$Surface\" targetoffset=\"\$Sample\" useaimtarget=\"false\" excludeself=\"$self\""* ]] || fail "detailed explicit-zero witnesses missing excludeself=$self"
done
for name in BarrelWitnessSelf BarrelWitnessEx ImplicitWitnessSelf ImplicitWitnessEx ZeroWitnessSelf ZeroWitnessEx; do
  [[ "$issue69_matrix" == *"append_to_list name=\"\$$name\""* ]] || fail "Issue69 detailed matrix does not retain all six $name results"
done
for field in barrel_witness_self= barrel_witness_ex= implicit_witness_self= implicit_witness_ex= zero_witness_self= zero_witness_ex= six_clear_self= six_clear_ex= implicit_six_self= implicit_six_ex= zero_six_self= zero_six_ex=; do
  [[ "$issue69_matrix" == *"$field"* ]] || fail "Issue69 detailed matrix record missing $field"
done
[[ $(grep -cF '[X4GC TEST ISSUE69 MATRIX CHANGE]' "$scenario") -eq 1 && "$issue69_matrix" == *"<do_if value=\"\$Changed\">"* && "$issue69_matrix" == *previous_signature=* ]] || fail "changed pair does not emit exactly one detailed MATRIX CHANGE record"
if [[ "$issue69_matrix" =~ SetSofttarget|set_softtarget|set_weapon_mode|\.mode[[:space:]]*=|select_target|selectTarget ]]; then fail "Issue69 matrix mutates target or weapon mode"; fi
grep -Fq "ScenarioRoot.\$Issue69FarBeam\" exact=\"\$Issue69Beam\"" "$scenario" || fail "exact FAR Beam is not persisted"
grep -Fq "ScenarioRoot.\$Issue69FarSurface\" exact=\"\$FarRoleSurface\"" "$scenario" || fail "exact FAR surface is not persisted"

echo "issue69 combined fixture contract passed"
