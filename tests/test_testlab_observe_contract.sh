#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

md=testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_observe.xml
scenario=testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_scenario.xml
loadouts=testlab/x4_gunnery_control_testlab/libraries/loadouts.xml
testlab_ui=testlab/x4_gunnery_control_testlab/ui/testlab.lua
scenario_spec=testlab/x4_gunnery_control_testlab/ui/scenario_spec.lua
fail() { echo "FAIL: $1" >&2; exit 1; }

# A live Gunnery Control session's AimTarget is authoritative. The free-play
# fallback chain remains soft target, then player.target. Keep these checks
# adjacent to the two consumers so a future edit cannot silently make HIT and
# engageability attribution disagree.
snapshot_target=$(awk '/<cue name="ObserveMark"/{inside=1} /<cue name="ObserveState"/{inside=0} inside && /AimTarget|SoftTarget|player\.target/{print NR ":" $0}' "$md")
hit_target=$(awk '/<cue name="ObserveHit"/{inside=1} /<cue name="ObserveCensus"/{inside=0} inside && /AimTarget|SoftTarget|player\.target/{print NR ":" $0}' "$md")
fired_target=$(awk '/<cue name="ObserveFired"/{inside=1} /<cue name="ObserveHit"/{inside=0} inside && /AimTarget|SoftTarget|player\.target/{print NR ":" $0}' "$md")
printf '%s\n' "$snapshot_target" | grep -q 'AimTarget' || fail "engageability snapshot does not prefer AimTarget"
printf '%s\n' "$snapshot_target" | grep -q 'SoftTarget' || fail "engageability snapshot lost soft-target fallback"
printf '%s\n' "$snapshot_target" | grep -q 'player.target' || fail "engageability snapshot lost player.target fallback"
printf '%s\n' "$hit_target" | grep -q 'AimTarget' || fail "HIT attribution does not prefer AimTarget"
printf '%s\n' "$hit_target" | grep -q 'SoftTarget' || fail "HIT attribution lost soft-target fallback"
printf '%s\n' "$hit_target" | grep -q 'player.target' || fail "HIT attribution lost player.target fallback"
printf '%s\n' "$fired_target" | grep -q 'AimTarget' || fail "FIRED attribution does not prefer AimTarget"
printf '%s\n' "$fired_target" | grep -q 'SoftTarget' || fail "FIRED attribution lost soft-target fallback"
printf '%s\n' "$fired_target" | grep -q 'player.target' || fail "FIRED attribution lost player.target fallback"
snapshot_aim=$(printf '%s\n' "$snapshot_target" | grep -F 'AimTarget? and' | cut -d: -f1)
snapshot_soft=$(printf '%s\n' "$snapshot_target" | grep -F 'SoftTarget? and' | cut -d: -f1)
snapshot_player=$(printf '%s\n' "$snapshot_target" | grep -F 'player.target?' | cut -d: -f1)
hit_aim=$(printf '%s\n' "$hit_target" | grep -F 'AimTarget? and' | cut -d: -f1)
hit_soft=$(printf '%s\n' "$hit_target" | grep -F 'SoftTarget? and' | cut -d: -f1)
hit_player=$(printf '%s\n' "$hit_target" | grep -F 'player.target?' | cut -d: -f1)
if ! [[ "$snapshot_aim" -lt "$snapshot_soft" && "$snapshot_soft" -lt "$snapshot_player" ]]; then
  fail "engageability snapshot target precedence is not AimTarget > soft target > player.target"
fi
if ! [[ "$hit_aim" -lt "$hit_soft" && "$hit_soft" -lt "$hit_player" ]]; then
  fail "HIT target precedence is not AimTarget > soft target > player.target"
fi

# A firing event must measure the projectile's actual angular error to the
# selected component. Global UI aim state alone cannot identify a turret's
# engagement target, which is the ambiguity this diagnostic exists to remove.
grep -Fq "name=\"\$TargetBearing\" exact=\"if \$Aimed then \$Aimed.relativeposition.{event.param} else null\"" "$md" \
  || fail "FIRED observer does not derive projectile-local target bearing"
grep -Fq "' aim_error_yaw='" "$md" || fail "FIRED observer does not log target yaw error"
grep -Fq "' aim_error_pitch='" "$md" || fail "FIRED observer does not log target pitch error"

# Missile hit payloads name the launcher ship, so own-hull clearance must be
# checked from the exact fired missile object before it disappears. A surviving
# missile farther from the ship after 500 ms is the direct dumbfire control.
grep -Fq '<cue name="ObserveMissileFlight" instantiate="true">' "$md" \
  || fail "missile-flight observer cue is missing"
[[ $(xmllint --xpath "count(//cue[@name='ObserveMissileFlight']/delay[@exact='500ms'])" "$md") == "1" ]] \
  || fail "missile-flight observer must have one cue-level 500 ms delay"
[[ $(xmllint --xpath "count(//actions/delay)" "$md") == "0" ]] \
  || fail "MD delay must be a cue modifier between conditions and actions, not an action node"
grep -Fq "name=\"\$Target\" exact=\"@\$Missile.target\"" "$md" \
  || fail "missile-flight observer does not retain the missile intended target"
grep -Fq "' shipdist_500ms='" "$md" \
  || fail "missile-flight observer does not log delayed distance from the firing ship"

# The candidate mechanical-arc bearing uses the target's weapon-consistent aim
# point in the turret mount's local frame; keep it diagnostic until live proof.
aimlocal=$(grep -Fc "<position object=\"\$Weapon\" space=\"\$Weapon\"/>" "$md")
[[ "$aimlocal" -eq 2 ]] || fail "expected local aim orientation in both weapon snapshot loops, found $aimlocal"

# A selected surface component is a valid aim target. The hit event carries
# both the victim object and the struck component; istgt must accept either
# representation rather than comparing only the victim root.
grep -Fq "event.param == \$Aimed or @event.param3.{1} == \$Aimed" "$md" \
  || fail "HIT attribution does not compare the selected component"

# The engageability snapshot and the census are both denominators. Each must cover
# regular weapons/turrets and the separate missile-turret property list.
weapons=$(grep -Fc 'in="player.ship.weapons.operational.list"' "$md")
missiles=$(grep -Fc 'in="player.ship.missileturrets.operational.list"' "$md")
ship_weapons=$(grep -Fc "in=\"\$Ship.weapons.operational.list\"" "$md")
ship_missiles=$(grep -Fc "in=\"\$Ship.missileturrets.operational.list\"" "$md")
[[ "$weapons" -eq 1 ]] || fail "expected one player weapons snapshot loop, found $weapons"
[[ "$missiles" -eq 1 ]] || fail "expected one player missile-turret snapshot loop, found $missiles"
[[ "$ship_weapons" -eq 1 ]] || fail "expected one census weapons loop, found $ship_weapons"
[[ "$ship_missiles" -eq 1 ]] || fail "expected one census missile-turret loop, found $ship_missiles"

# Issue #54 Task 2: inrange must mirror shipped combat-AI reachability —
# bounding-box distance under maxfirerange, no size term — in both snapshot
# loops, and the stale "distance plus half the target's size" framing is gone.
inrange=$(grep -Fc "(\$Weapon.bboxdistanceto.{\$Target} le \$Weapon.maxfirerange)" "$md" || true)
[[ "$inrange" -eq 2 ]] || fail "expected bboxdistanceto inrange in both snapshot loops, found $inrange"
bboxdist=$(grep -Fc "' bboxdist=' + \$Weapon.bboxdistanceto.{\$Target}" "$md" || true)
[[ "$bboxdist" -eq 2 ]] || fail "expected bboxdist diagnostic in both snapshot loops, found $bboxdist"
if grep -Fq "(\$Dist + (\$Target.size / 2) lt \$Weapon.maxfirerange)" "$md"; then
  fail "inrange still uses the old distanceto + target.size/2 predicate"
fi
if grep -Fq "distance plus half the target" "$md"; then
  fail "stale comment still claims distance plus half the target's size is the in-range definition"
fi

# The scenario owns both a persistent group of safe fixtures and a numeric
# acknowledgement count. Reusing one MD variable name for both would serialize
# the group into x4gct4, so Lua would reject the acknowledgement and never arm
# this observer—the exact failure this contract guards.
grep -Fq "name=\"\$SafeObjectCount\" exact=\"0\"" "$scenario" \
  || fail "safe-fixture numeric census is missing"
grep -Fq "':' + \$SafeObjectCount + ':' + \$SafeWeapons" "$scenario" \
  || fail "scenario acknowledgement does not serialize the numeric safe-fixture census"
if grep -Fq "':' + \$SafeObjects + ':' + \$SafeWeapons" "$scenario"; then
  fail "scenario acknowledgement serializes the safe-fixture group"
fi
grep -Fq "':' + \$UnsafeWeapons + ':' + \$DefenceUnits" "$scenario" \
  || fail "scenario acknowledgement omits the remaining defence-unit census"
grep -Fq "':' + \$DefenceUnits + ':' + \$Hostiles" "$scenario" \
  || fail "scenario acknowledgement omits the attackable-hostile census"
grep -Fq "'x4gct8:'" "$scenario" \
  || fail "scenario acknowledgement does not use geometry/shooter census protocol x4gct8"
grep -Fq "':' + \$Hostiles + ':' + \$RepairObjectCount" "$scenario" \
  || fail "scenario acknowledgement omits the repair-guard census"
grep -Fq "groupname=\"ScenarioRoot.\$RepairObjects\" object=\"\$Ship\"" "$scenario" \
  || fail "repair-guard fixtures are not registered during spawn"
grep -Fq "groupname=\"ScenarioRoot.\$PlayerShooters\" object=\"player.ship\"" "$scenario" \
  || fail "local scenarios do not attribute repair hits to the current player ship"
grep -Fq "groupname=\"ScenarioRoot.\$PlayerShooters\" object=\"\$Ship\"" "$scenario" \
  || fail "remote scenarios do not attribute repair hits to their spawned shooter"
grep -Fq "<event_object_attacked_object group=\"ScenarioRoot.\$PlayerShooters\"/>" "$scenario" \
  || fail "repair guard is not driven by the unified local/remote shooter group"
grep -Fq "not (ScenarioRoot.\$Spawned? and ScenarioRoot.\$Spawned.indexof.{player.ship})" "$scenario" \
  || fail "scenario replacement and cleanup do not guard the occupied spawned ship"
grep -Fq '<cue name="ScenarioCommitOccupiedReject" instantiate="true">' "$scenario" \
  || fail "MD has no defensive rejection path for occupied-fixture replacement"
grep -Fq '<cue name="DespawnScenarioOccupiedReject" instantiate="true">' "$scenario" \
  || fail "MD has no defensive rejection path for occupied-fixture cleanup"
grep -Fq "':' + \$ShooterCount + ':' + \$ShooterMissileTurrets" "$scenario" \
  || fail "scenario acknowledgement omits the spawned-shooter turret census"
grep -Fq "':' + \$ShooterGuided + ':' + \$ShooterDumbfire + ':' + \$ShooterAmmo" "$scenario" \
  || fail "scenario acknowledgement omits guided/dumbfire/ammunition census"
grep -Fq "':' + (\$StationLoadoutFailures + \$LoadoutFailures + \$UnsafeDormantShooterWeapons) + ':' + \$LocationFailures" "$scenario" \
  || fail "scenario acknowledgement omits loadout and exact-placement failures"
grep -Fq '<set_object_hull object="event.param3.{1}" exact="100"/>' "$scenario" \
  || fail "repair guard does not restore the exact struck component"

# Issue #65 remote fixture: the deterministic loadout must fill all 16
# Odysseus E turret slots with the intended 9/7 guided/dumbfire split and stock
# all four missile types to the ship's shipped 160-round capacity.
[[ $(grep -Fc '<turrets macro="turret_par_m_guided_02_mk1_macro"' "$scenario") -eq 3 ]] \
  || fail "issue #65 loadout does not define three two-slot M guided groups"
[[ $(grep -Fc '<turrets macro="turret_par_m_dumbfire_02_mk1_macro"' "$scenario") -eq 3 ]] \
  || fail "issue #65 loadout does not define three two-slot M dumbfire groups"
[[ $(grep -Fc '<turrets macro="turret_par_l_guided_01_mk1_macro"' "$scenario") -eq 2 ]] \
  || fail "issue #65 loadout does not define the 2+1 L guided groups"
[[ $(grep -Fc '<turrets macro="turret_par_l_dumbfire_01_mk1_macro"' "$scenario") -eq 1 ]] \
  || fail "issue #65 loadout does not define one L dumbfire group"
[[ $(grep -Fc '<ammunition macro="missile_gen_' "$scenario") -eq 4 ]] \
  || fail "issue #65 loadout must stock exactly four missile types"
[[ $(grep -Fc 'exact="40"/>' "$scenario") -eq 4 ]] \
  || fail "issue #65 loadout must split 160 missiles evenly across four types"
grep -Fq "<apply_loadout object=\"\$Ship\" loadout=\"\$Issue65OdysseusLoadout\"/>" "$scenario" \
  || fail "issue #65 fixed loadout is not applied to the spawned shooter"
grep -Fq "<set_value name=\"\$DormantShooterWeapons\" operation=\"add\"/>" "$scenario" \
  || fail "remote shooter is not held dormant while the owner teleports"
grep -Fq "<set_value name=\"\$UnsafeDormantShooterWeapons\" operation=\"add\"/>" "$scenario" \
  || fail "remote shooter HOLD FIRE failure is not part of readiness"
grep -Fq "<find_sector name=\"\$ScenarioSector\" macro=\"macro.{\$SectorMacroName}\"" "$scenario" \
  || fail "remote fixture does not resolve the exact requested sector macro"
grep -Fq "x=\"ScenarioRoot.\$PendingAnchorX + \$Def.\$x\"" "$scenario" \
  || fail "remote fixture does not use absolute sector-anchor placement"
grep -Fq "<create_position name=\"\$ShipSectorPosition\" object=\"\$Ship\" space=\"\$ScenarioSector\"/>" "$scenario" \
  || fail "remote placement validation does not convert the ship position to sector coordinates"
grep -Fq "\$ShipSectorPosition.x lt \$ExpectedSectorX - 10m" "$scenario" \
  || fail "remote placement validation does not compare sector-coordinate x against the expected sector position"
grep -Fq "\$ox        = if @event.param3.\$ox        then event.param3.\$ox        else 0" "$scenario" \
  || fail "scenario group payload does not transport ox"
grep -Fq "\$oy        = if @event.param3.\$oy        then event.param3.\$oy        else 0" "$scenario" \
  || fail "scenario group payload does not transport oy"
grep -Fq "\$oz        = if @event.param3.\$oz        then event.param3.\$oz        else 0" "$scenario" \
  || fail "scenario group payload does not transport oz"
grep -Fq "<set_value name=\"\$PStarWeaponMacro\" exact=\"@macro.{\$Def.\$geometryweaponmacro}\"/>" "$scenario" \
  || fail "PStar macro is not resolved from the transported geometry weapon macro"
grep -Fq "<create_position name=\"\$PStar\" object=\"\$GeometryWeapon\" space=\"\$ScenarioSector\"/>" "$scenario" \
  || fail "PStar is not created from the matched geometry weapon in ScenarioSector"
grep -Fq '[X4GC TEST SCENARIO PSTAR]' "$scenario" \
  || fail "PStar calibration line is missing"
grep -Fq "if \$Def.\$geometryrole == 'surface_mask' then \$PStar.x + \$Def.\$ox else ScenarioRoot.\$PendingAnchorX + \$Def.\$x" "$scenario" \
  || fail "surface_mask remote x placement does not use PStar+ox"
grep -Fq "if \$Def.\$geometryrole == 'surface_mask' then \$PStar.y + \$Def.\$oy else ScenarioRoot.\$PendingAnchorY + \$Def.\$y" "$scenario" \
  || fail "surface_mask remote y placement does not use PStar+oy"
grep -Fq "if \$Def.\$geometryrole == 'surface_mask' then \$PStar.z + \$Def.\$oz else ScenarioRoot.\$PendingAnchorZ + \$Def.\$distance" "$scenario" \
  || fail "surface_mask remote z placement does not use PStar+oz"
grep -Fq 'reason=pstar_unresolved' "$scenario" \
  || fail "surface_mask fail-closed diagnostic is missing"
grep -Fq "name=\"\$ExpectedSectorX\" exact=\"if \$Def.\$geometryrole == 'surface_mask' then \$PStar.x + \$Def.\$ox else ScenarioRoot.\$PendingAnchorX + \$Def.\$x\"" "$scenario" \
  || fail "location validation does not compute expected sector x from PStar for surface_mask"
grep -Fq "name=\"\$ExpectedSectorY\" exact=\"if \$Def.\$geometryrole == 'surface_mask' then \$PStar.y + \$Def.\$oy else ScenarioRoot.\$PendingAnchorY + \$Def.\$y\"" "$scenario" \
  || fail "location validation does not compute expected sector y from PStar for surface_mask"
grep -Fq "name=\"\$ExpectedSectorZ\" exact=\"if \$Def.\$geometryrole == 'surface_mask' then \$PStar.z + \$Def.\$oz else ScenarioRoot.\$PendingAnchorZ + \$Def.\$distance\"" "$scenario" \
  || fail "location validation does not compute expected sector z from PStar for surface_mask"
grep -Fq "\$ShipSectorPosition.x lt \$ExpectedSectorX - 10m" "$scenario" \
  || fail "location validation does not compare x against the computed expected sector position"
if grep -Fq "\$Ship.position.x lt ScenarioRoot.\$PendingAnchorX" "$scenario"; then
  fail "remote placement validation compares a zone-local ship position against the sector anchor"
fi

# Issue #67 r15: the active fixture mounts two Argon Colossus E plasma turrets via a
# group-targeted entry (group_front_right_up), guarding against a regression to
# singular <turret> mounting.
grep -Fq '<loadout id="x4gc_testlab_issue67_colossus_arc_barrel" macro="ship_arg_xl_carrier_02_a_macro">' "$loadouts" \
  || fail "r15 static loadout does not bind the exact Colossus E macro"
grep -Fq '<turrets macro="turret_arg_m_plasma_02_mk1_macro" group="group_front_right_up" exact="2"/>' "$loadouts" \
  || fail "r15 Colossus E loadout does not mount its Plasma group via group_front_right_up"
[[ $(grep -Fc '<loadout ref="x4gc_testlab_issue67_colossus_arc_barrel"/>' "$scenario") -eq 2 ]] \
  || fail "r15 static Colossus E loadout is not used in remote and local creation branches"
grep -Fq "\$geometryweaponmacro = if @event.param3.\$geometryWeaponMacro" "$scenario" \
  || fail "r15 geometry weapon macro is not transported into MD"
grep -Fq "\$expectedgeometryweapons = if @event.param3.\$expectedGeometryWeapons" "$scenario" \
  || fail "r15 expected geometry count is not transported into MD"
grep -Fq "ScenarioRoot.\$GeometryWeaponMacroName" "$scenario" \
  || fail "r15 does not persist the exact geometry macro for phase two"
grep -Fq "exact=\"@macro.{\$GeometryWeaponMacroName}\"" "$scenario" \
  || fail "r15 does not resolve the transported geometry macro fail-closed"
grep -Fq 'reason=geometry_weapon_macro_unresolved' "$scenario" \
  || fail "r15 does not log unresolved geometry macro failure"
grep -Fq "\$GeometryWeapon.macro == \$GeometryWeaponMacro" "$scenario" \
  || fail "r15 qualifier still hardcodes plasma instead of transported Plasma macro"
grep -Fq "'X4GunneryTestLab.GeometryQualifiedTargetToken'" "$scenario" \
  || fail "qualified component transport lacks its request-token event"
token_line=$(grep -Fn "GeometryQualifiedTargetToken" "$scenario" | tail -n1 | cut -d: -f1)
target_line=$(grep -Fn "GeometryQualifiedTarget'" "$scenario" | tail -n1 | cut -d: -f1)
q8_line=$(grep -Fn "'x4gcq9:'" "$scenario" | tail -n1 | cut -d: -f1)
[[ "$token_line" -lt "$target_line" && "$target_line" -lt "$q8_line" ]] \
  || fail "qualified transport must emit token, typed component, then q9"
grep -Fq 'onGeometryQualifiedTargetToken' "$testlab_ui" \
  || fail "Lua does not register target-token authorization"
grep -Fq 'targetTokenAuthorized' "$testlab_ui" \
  || fail "Lua does not consume one-shot typed-target authorization"
grep -Fq "\$Measured == \$ExpectedGeometryWeapons" "$scenario" \
  || fail "r15 MD qualifier does not require transported exact measured count"
grep -Fq 'measured == 1' "$testlab_ui" \
  || fail "r16 UI does not require exactly one measured Plasma"
grep -Fq 'request.expectedGeometryWeapons == 1' "$testlab_ui" \
  || fail "r16 UI does not retain transported expected-count guard"
grep -Fq 'geometryWeaponMacro = group.geometryWeaponMacro' "$testlab_ui" \
  || fail "r15 Lua does not retain geometry macro during validation"
grep -Fq 'expectedGeometryWeapons = group.expectedGeometryWeapons' "$testlab_ui" \
  || fail "r15 Lua does not retain expected geometry count during validation"
grep -Fq 'expectedMemberMacros' "$testlab_ui" \
  || fail "r15 Lua does not accept the authoritative expectedMemberMacros setup field"
[[ $(grep -Fc 'actual_yaw=' "$scenario") -ge 2 ]] \
  || fail "r15 does not log actual orientation at spawn and qualification"
grep -Fq 'authored_yaw=' "$scenario" \
  || fail "r15 spawn telemetry does not log authored orientation"
grep -Fq "actual_yaw=' + \$Target.rotation.yaw" "$scenario" \
  || fail "r15 qualification telemetry does not capture settled target orientation"
grep -Fq 'preserveOrientation = true' "$scenario_spec" \
  || fail "r15 survey targets do not preserve authored orientation"

# The qualifier remains settled, case-specific, and fail-closed. LOS stays
# independent telemetry and must not suppress the geometric candidates.
grep -Fq "<create_group groupname=\"ScenarioRoot.\$SurfaceMaskTargets\"/>" "$scenario" \
  || fail "r15 does not retain its exact surface candidate targets"
grep -Fq "<param name=\"skipalignment\" value=\"\$Def.\$preserveorientation\"/>" "$scenario" \
  || fail "r15 Wait targets do not preserve authored pitch/roll"
for gate in "\$SurfaceRelative.rotation.pitch gt 80deg" \
  "\$SurfaceAimLocal.pitch ge -5deg and \$SurfaceAimLocal.pitch le 80deg" \
  "\$SurfaceRange ge 250m" \
  "\$SurfaceRange le \$GeometryWeapon.maxfirerange" \
  "target=\"\$Surface\" excludeself=\"true\" useaimtarget=\"true\"" \
  "target=\"\$Surface\" excludeself=\"false\" useaimtarget=\"true\"" \
  "exact=\"@\$Shooter.mayattack.{\$Surface}\""; do
  grep -Fq "$gate" "$scenario" || fail "r15 qualifier lost gate: $gate"
done
grep -Fq "exact=\"\$GeometryCase == 'arc_split' and \$Separated and \$SurfaceArcSplit and \$SurfaceInRange and \$SurfaceMayAttack\"" "$scenario" \
  || fail "r32 arc-split qualifier lost its non-LOS gates"
grep -Fq "exact=\"\$GeometryCase == 'positive_control' and \$Separated and \$SurfacePositiveControl and \$SurfaceInRange and \$SurfaceMayAttack\"" "$scenario" \
  || fail "r32 positive-control qualifier lost its non-LOS gates"
grep -Fq "\$Surface.macro == macro.turret_arg_l_beam_01_mk1_macro" "$scenario" \
  || fail "r32 qualifier does not filter the exact Argon L Beam surface macro"
# $SurfaceMuzzleLosSelf (excludeself=false) must NOT gate qualification: md-ai.md:359
# shows it reads blocked 7252/7252 from a hull-mounted turret, so gating on it makes
# qualification unreachable. It stays as a telemetry check + log field only.
if grep -Fq "\$SurfaceMuzzleLosSelf and \$SurfaceMayAttack" "$scenario"; then
  fail "r15 qualifier must not gate on the always-blocked excludeself=false ray"
fi
grep -Fq 'bridge.suggestTestEngagement(request.designatedComponent' "$testlab_ui" \
  || fail "r15 Test Lab does not mark the qualified surface"
grep -Fq 'direct_mode = "manual_pending"' "$testlab_ui" \
  || fail "r15 qualified log claims a Direct-control mode before the owner clicks it"
if grep -Eq 'queueTestEngagement|attemptQueuedTestEngagement|SetSofttarget|engageTarget|X4GunneryState.setDirectMode' "$testlab_ui"; then
  fail "Test Lab must not automate target/root/surface selection"
fi

# Testlab geometry qualification contract: the MD slice persists exact
# placement records, repositions from qualification-time PStar, measures the
# post-warp result, and hard-gates success on both reposition and placement
# counters.
grep -Fq "<set_value name=\"ScenarioRoot.\$SurfaceMaskPlacements\" exact=\"[]\"/>" "$scenario" \
  || fail "surface-mask placement list is not initialized empty"
grep -Fq "<append_to_list name=\"ScenarioRoot.\$SurfaceMaskPlacements\" exact=\"table[\$target = \$Ship, \$label = \$Def.\$label, \$case = \$Def.\$geometrycase, \$ox = \$Def.\$ox, \$oy = \$Def.\$oy, \$oz = \$Def.\$oz]\"/>" "$scenario" \
  || fail "surface-mask placement record does not persist target, label, case, and exact offsets"
[[ $(grep -Fc "<signal_cue cue=\"GeometryQualifyReposition\"/>" "$scenario") -eq 1 ]] \
  || fail "GeometryQualifyReposition signal cue is not unique"
[[ $(grep -Fc "<cue name=\"GeometryQualifyReposition\" instantiate=\"true\">" "$scenario") -eq 1 ]] \
  || fail "GeometryQualifyReposition cue is not unique"
[[ $(grep -Fc "<cue name=\"GeometryQualifyMeasure\" instantiate=\"true\">" "$scenario") -eq 1 ]] \
  || fail "GeometryQualifyMeasure cue is not unique"
[[ $(grep -Fc "<signal_cue cue=\"GeometryQualifyMeasure\"/>" "$scenario") -eq 1 ]] \
  || fail "GeometryQualifyMeasure signal cue is not unique"
grep -Fq "<set_value name=\"ScenarioRoot.\$GeometryQualifyRepositioned\" exact=\"0\"/>" "$scenario" \
  || fail "GeometryQualifyRepositioned counter is not initialized"
grep -Fq "<set_value name=\"ScenarioRoot.\$GeometryQualifyRepositionFailures\" exact=\"0\"/>" "$scenario" \
  || fail "GeometryQualifyRepositionFailures counter is not initialized"
grep -Fq "reason=placement_records_missing" "$scenario" \
  || fail "placement_records_missing failure marker is missing"
grep -Fq "reason=reposition_missing" "$scenario" \
  || fail "reposition_missing failure marker is missing"
grep -Fq "reason=post_warp_mismatch" "$scenario" \
  || fail "post_warp_mismatch failure marker is missing"
grep -Fq "<position x=\"\$CurrentPStar.x + \$Record.\$ox\"" "$scenario" \
  || fail "reposition warp does not use the exact PStar+ox position"
grep -Fq "<rotation value=\"\$PreservedRotation\"/>" "$scenario" \
  || fail "reposition warp does not preserve the target rotation"
if grep -Fq "<set_value name=\"\$Target.rotation\" exact=\"\$PreservedRotation\"/>" "$scenario"; then
  fail "reposition warp still uses the old target.rotation assignment"
fi
grep -Fq "[X4GC TEST QUALIFY REPOSITION]" "$scenario" \
  || fail "reposition success marker is missing"
grep -Fq "in=\"ScenarioRoot.\$SurfaceMaskPlacements\"" "$scenario" \
  || fail "Measure no longer iterates placement records"
grep -Fq "name=\"\$Target\" exact=\"\$Record.\$target\"" "$scenario" \
  || fail "Measure does not rebind each placement record target"
grep -Fq "name=\"\$MeasurePStar\" exact=\"\$QualWeaponSectorPos\"" "$scenario" \
  || fail "Measure does not capture the exact weapon PStar"
grep -Fq "placement_records=" "$scenario" \
  || fail "preserved_object_missing no longer reports placement-record count"
grep -Fq "repositioned=' + ScenarioRoot.\$GeometryQualifyRepositioned" "$scenario" \
  || fail "QUALIFY summary omits the repositioned counter"
grep -Fq "reposition_failures=' + ScenarioRoot.\$GeometryQualifyRepositionFailures" "$scenario" \
  || fail "QUALIFY summary omits the reposition failure counter"
grep -Fq "post_warp_location_failures=' + \$PostWarpLocationFailures" "$scenario" \
  || fail "QUALIFY summary omits the post-warp failure counter"
grep -Fq "ScenarioRoot.\$GeometryQualifyRepositioned == 2" "$scenario" \
  || fail "final qualification no longer requires two successful repositions"
grep -Fq "ScenarioRoot.\$GeometryQualifyRepositionFailures == 0" "$scenario" \
  || fail "final qualification no longer requires zero reposition failures"
grep -Fq "\$PostWarpLocationFailures == 0" "$scenario" \
  || fail "final qualification no longer requires zero post-warp failures"
grep -Fq "<remove_value name=\"ScenarioRoot.\$SurfaceMaskPlacements\"/>" "$scenario" \
  || fail "cleanup does not remove the placement list"
grep -Fq "<remove_value name=\"ScenarioRoot.\$GeometryQualifyRepositioned\"/>" "$scenario" \
  || fail "cleanup does not remove GeometryQualifyRepositioned"
grep -Fq "<remove_value name=\"ScenarioRoot.\$GeometryQualifyRepositionFailures\"/>" "$scenario" \
  || fail "cleanup does not remove GeometryQualifyRepositionFailures"
grep -Fq "'x4gcq9:'" "$scenario" \
  || fail "geometry-qualified q9 token no longer uses x4gcq9"

[[ $(grep -Fc "<set_value name=\"\$QualifySector\" exact=\"\$Shooter.sector\"/>" "$scenario") -eq 2 ]] \
  || fail "QualifySector binding count is not exactly two"

reposition_block=$(awk '/<cue name="GeometryQualifyReposition" instantiate="true">/{flag=1} flag{print} /<\/cue>/{if(flag){exit}}' "$scenario")
measure_block=$(awk '/<cue name="GeometryQualifyMeasure" instantiate="true">/{flag=1} flag{print} /<\/cue>/{if(flag){exit}}' "$scenario")
reposition_bind_line=$(printf '%s\n' "$reposition_block" | grep -nF "<set_value name=\"\$QualifySector\" exact=\"\$Shooter.sector\"/>" | head -n1 | cut -d: -f1)
reposition_use_line=$(printf '%s\n' "$reposition_block" | grep -nF "space=\"\$QualifySector\"" | head -n1 | cut -d: -f1)
[[ -n "$reposition_bind_line" && -n "$reposition_use_line" && "$reposition_bind_line" -lt "$reposition_use_line" ]] \
  || fail "GeometryQualifyReposition does not bind QualifySector before first use"
if grep -Fq "\$ScenarioSector" <<<"$reposition_block"; then
  fail "GeometryQualifyReposition still references ScenarioSector"
fi
measure_bind_line=$(printf '%s\n' "$measure_block" | grep -nF "<set_value name=\"\$QualifySector\" exact=\"\$Shooter.sector\"/>" | head -n1 | cut -d: -f1)
measure_use_line=$(printf '%s\n' "$measure_block" | grep -nF "space=\"\$QualifySector\"" | head -n1 | cut -d: -f1)
[[ -n "$measure_bind_line" && -n "$measure_use_line" && "$measure_bind_line" -lt "$measure_use_line" ]] \
  || fail "GeometryQualifyMeasure does not bind QualifySector before first use"
if grep -Fq "\$ScenarioSector" <<<"$measure_block"; then
  fail "GeometryQualifyMeasure still references ScenarioSector"
fi

# Issue #67 r12 observer contract: Lua owns the two auto-marks (initial on a
# newly accepted aim target, settled at 20 active seconds with paused time
# excluded), and the MD records stay raw and independent — the solution line
# keeps its own fields, not a derived verdict.
grep -Fq '<cue name="ObserveMark" instantiate="true">' "$md" \
  || fail "r12 ObserveMark observer cue is missing"
grep -Fq '<cue name="ObserveFired" instantiate="true">' "$md" \
  || fail "r12 ObserveFired observer cue is missing"
grep -Fq '<cue name="ObserveHit" instantiate="true">' "$md" \
  || fail "r12 ObserveHit observer cue is missing"

# Lua: a newly accepted aim target (different from lastObservedAimTarget) emits
# the same observe_mark event the Mark button emits and logs auto_mark_initial.
grep -Fq 'and aimTarget ~= lastObservedAimTarget then' "$testlab_ui" \
  || fail "r12 initial auto-mark no longer keys off lastObservedAimTarget"
[[ $(grep -Fc 'AddUITriggeredEvent("X4GunneryTestLabObserve", "observe_mark")' "$testlab_ui") -ge 2 ]] \
  || fail "r12 observe_mark must be emitted for both the initial and the settled auto-mark"
grep -Fq 'log("observe", { action = "auto_mark_initial", target = aimTarget })' "$testlab_ui" \
  || fail "r12 initial auto-mark does not log action=auto_mark_initial"
# Lua: the new target restarts the active-second clock, paused game time is
# excluded via bridge.isGamePaused, and at >= 20 active seconds the target is
# marked again, settled, with active_seconds logged.
grep -Fq 'observedAimActiveSeconds, observedAimLastTick, observedAimSettled = 0, now, false' "$testlab_ui" \
  || fail "r12 does not restart the active-second clock for a new aim target"
grep -Fq 'if not (bridge.isGamePaused and bridge.isGamePaused()) then' "$testlab_ui" \
  || fail "r12 active-second clock does not exclude paused game time via bridge.isGamePaused"
grep -Fq 'if observedAimActiveSeconds >= 20 then' "$testlab_ui" \
  || fail "r12 settled auto-mark does not wait for 20 active seconds"
grep -Fq 'observedAimSettled = true' "$testlab_ui" \
  || fail "r12 does not mark the aim target settled"
grep -Fq 'log("observe", { action = "auto_mark_settled", target = aimTarget, active_seconds = observedAimActiveSeconds })' "$testlab_ui" \
  || fail "r12 settled auto-mark does not log action=auto_mark_settled with active_seconds"
r12_lua_line() { { grep -Fn "$1" "$testlab_ui" || true; } | head -n 1 | cut -d: -f1; }
r12_initial_line=$(r12_lua_line 'action = "auto_mark_initial"')
r12_threshold_line=$(r12_lua_line 'if observedAimActiveSeconds >= 20 then')
r12_settled_line=$(r12_lua_line 'action = "auto_mark_settled"')
[[ -n "$r12_initial_line" && -n "$r12_threshold_line" && -n "$r12_settled_line" && "$r12_initial_line" -lt "$r12_threshold_line" && "$r12_threshold_line" -lt "$r12_settled_line" ]] \
  || fail "r12 auto-mark logs are not ordered initial -> 20 s threshold -> settled"

# MD ObserveMark: the solution record keeps raw, independent fields; nothing
# may replace them with a derived verdict.
mark_cue=$(awk '/<cue name="ObserveMark"/{inside=1} inside{print} /<\/cue>/{if (inside) exit}' "$md")
fired_cue=$(awk '/<cue name="ObserveFired"/{inside=1} inside{print} /<\/cue>/{if (inside) exit}' "$md")
hit_cue=$(awk '/<cue name="ObserveHit"/{inside=1} inside{print} /<\/cue>/{if (inside) exit}' "$md")
for field in "+ ' weapon=' + \$Weapon" \
  "+ ' macro=' + \$Weapon.macro" \
  "+ ' mode=' + \$Weapon.mode" \
  "+ ' ready=' + \$Weapon.isreadytofire" \
  "+ ' rel_pitch=' + \$Relative.rotation.pitch" \
  "+ ' aim_pitch=' + \$AimLocal.pitch" \
  "+ ' muzzle_los_ex=' + \$MuzzleLosEx" \
  "+ ' muzzle_los_self=' + \$MuzzleLosSelf"; do
  printf '%s\n' "$mark_cue" | grep -Fq "$field" \
    || fail "r12 ObserveMark solution record lost the raw field: $field"
done
[[ $(printf '%s\n' "$mark_cue" | grep -Fc "' inrange=' + (\$Weapon.bboxdistanceto.{\$Target} le \$Weapon.maxfirerange)") -eq 2 ]] \
  || fail "r12 ObserveMark must log the raw inrange/bbox solution in both snapshot loops"

# MD ObserveFired: listens on the armed firing-weapon group and logs the exact
# emitter (event.object), the aimed target, and the exact aim error.
printf '%s\n' "$fired_cue" | grep -Fq "<event_weapon_fired group=\"\$FiringWeapons\"/>" \
  || fail "r12 ObserveFired no longer listens to event_weapon_fired on \$FiringWeapons"
printf '%s\n' "$fired_cue" | grep -Fq "+ ' weapon=' + event.object" \
  || fail "r12 FIRED does not log the exact emitter as weapon=event.object"
printf '%s\n' "$fired_cue" | grep -Fq "+ ' aimed=' + (if \$Aimed then \$Aimed else 'none')" \
  || fail "r12 FIRED does not log the aimed target"
printf '%s\n' "$fired_cue" | grep -Fq "+ ' aim_error_yaw=' + (if \$TargetBearing then \$TargetBearing.rotation.yaw else 'none')" \
  || fail "r12 FIRED lost the exact yaw aim-error field"
printf '%s\n' "$fired_cue" | grep -Fq "+ ' aim_error_pitch=' + (if \$TargetBearing then \$TargetBearing.rotation.pitch else 'none')" \
  || fail "r12 FIRED lost the exact pitch aim-error field"

# MD ObserveHit: one line per hit on the exact armed ship, attributing the
# weapon, the exact struck component, the aimed target, and istgt.
printf '%s\n' "$hit_cue" | grep -Fq "<event_object_attacked_object object=\"\$Ship\"/>" \
  || fail "r12 ObserveHit no longer listens to event_object_attacked_object on \$Ship"
printf '%s\n' "$hit_cue" | grep -Fq "<set_value name=\"\$Weapon\" exact=\"@event.param3.{2}\"/>" \
  || fail "r12 HIT no longer attributes the weapon from event.param3.{2}"
printf '%s\n' "$hit_cue" | grep -Fq "+ ' weapon=' + (if \$Weapon then \$Weapon else 'none')" \
  || fail "r12 HIT does not log the attributed weapon"
printf '%s\n' "$hit_cue" | grep -Fq "+ ' hitcomp=' + (if @event.param3.{1} then event.param3.{1} else 'none')" \
  || fail "r12 HIT does not log the exact struck component"
printf '%s\n' "$hit_cue" | grep -Fq "+ ' aimed=' + (if \$Aimed then \$Aimed else 'none')" \
  || fail "r12 HIT does not log the aimed target"
printf '%s\n' "$hit_cue" | grep -Fq "+ ' istgt=' + (\$Aimed? and (event.param == \$Aimed or @event.param3.{1} == \$Aimed))" \
  || fail "r12 HIT istgt is not component-aware"

echo "testlab observability contract tests passed"
