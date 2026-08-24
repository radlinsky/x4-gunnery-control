#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

md=testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_observe.xml
scenario=testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_scenario.xml
loadouts=testlab/x4_gunnery_control_testlab/libraries/loadouts.xml
arclimits=ui/turret_arc_limits.lua
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
grep -Fq "\$ShipSectorPosition.x lt ScenarioRoot.\$PendingAnchorX + \$Def.\$x - 10m" "$scenario" \
  || fail "remote placement validation does not compare sector-coordinate x against the anchor"
if grep -Fq "\$Ship.position.x lt ScenarioRoot.\$PendingAnchorX" "$scenario"; then
  fail "remote placement validation compares a zone-local ship position against the sector anchor"
fi

# Issue #67 reusable prerequisites: per-group conventional loadout, and
# fail-closed control census.  Station-B (aim_split) was removed in the r2
# refactor; the fixture now spawns in Hatikvah's Choice I for the Q1 arc test.
[[ $(grep -Fc '<turrets macro="turret_arg_m_beam_02_mk1_macro" group="group_front_left_up" exact="2"/>' "$loadouts") -eq 1 ]] \
  || fail "issue #67 loadout does not install 2 beam turrets in group_front_left_up"
[[ $(grep -Fc '<turrets macro="turret_arg_m_plasma_02_mk1_macro" group="group_front_right_up" exact="2"/>' "$loadouts") -eq 1 ]] \
  || fail "issue #67 loadout does not install 2 plasma turrets in group_front_right_up"
grep -Fq '<loadout id="x4gc_testlab_issue67_colossus_arc_barrel" macro="ship_arg_xl_carrier_02_a_macro">' "$loadouts" \
  || fail "issue #67 static loadout does not bind itself to the exact Colossus E macro"
[[ $(grep -Fc '<loadout ref="x4gc_testlab_issue67_colossus_arc_barrel"/>' "$scenario") -eq 2 ]] \
  || fail "issue #67 static loadout ref is not used in both remote and local creation paths"
if grep -Fq 'Issue67ColossusLoadout' "$scenario"; then
  fail "issue #67 fixture regressed to a live-proven-unreliable transient loadout"
fi
grep -Fq 'issue67 loadout_transport=static_ref' "$scenario" \
  || fail "issue #67 fixture does not log its source-backed loadout transport"
grep -Fq 'slot_paths=con_turret_m_06,con_turret_m_14,con_turret_m_08,con_turret_m_16' "$scenario" \
  || fail "issue #67 fixture does not log the shipped Colossus slot paths"
grep -Fq "\$Control.\$role == 'clear_arc'" "$scenario" \
  || fail "clear in-arc control has no fail-closed geometry preflight"
grep -Fq "\$Control.\$role == 'below_arc'" "$scenario" \
  || fail "true CANNOT BEAR control has no fail-closed geometry preflight"
grep -Fq "':' + \$ShooterWeapons + ':' + \$ShooterTurrets + ':' + \$ShooterBeam + ':' + \$ShooterPlasma + ':' + \$PreflightFailures + ':' + \$GeometrySplits" "$scenario" \
  || fail "READY omits ordinary-shooter and geometry-preflight census"

# Issue #67 arc preflight is anchored to the production-generated elevation
# limits for the EXACT turret macros the fixture mounts. The MD hardcodes the
# -10/90 stops; they must stay equal to ui/turret_arc_limits.lua's generated
# bounds for the chosen beam and plasma, or the in-arc/below-arc controls stop
# exercising the real production arc gate. This is a shipped-source/generated
# offline lock, not a live-mount claim.
for arc_macro in turret_arg_m_beam_02_mk1_macro turret_arg_m_plasma_02_mk1_macro; do
  grep -Fq "[\"$arc_macro\"] = { -10, 90 }" "$arclimits" \
    || fail "generated arc limits for $arc_macro are not { -10, 90 }; #67 preflight bounds would drift"
done
[[ $(grep -Fc 'ge -10deg and $RootRelative.rotation.pitch le 90deg' "$scenario") -eq 1 ]] \
  || fail "#67 root-arc preflight is not gated on the generated -10/90 elevation stops"
[[ $(grep -Fc 'ge -10deg and $AimLocal.pitch le 90deg' "$scenario") -eq 1 ]] \
  || fail "#67 aim-arc preflight is not gated on the generated -10/90 elevation stops"
grep -Fq '$RootRelative.rotation.pitch lt -10deg and $AimLocal.pitch lt -10deg' "$scenario" \
  || fail "#67 below-arc control does not require both bearings below the generated -10 stop"

# Issue #67 staged get_loadout probe. Shipped source proves the get_loadout
# syntax and one successful use, but NOT what a missing ID leaves in result
# (null, absent, or an aborted action list), so the live run must be readable
# from the LAST reached marker. Therefore the shipped, known-good control is
# probed FIRST (a custom-ID abort must never hide its own result), each lookup
# is followed by its own stage/result log, a marker is emitted immediately
# before the custom lookup, and the optional summary only after both returned.
# Interpretation of the last reached marker:
#   no control result log             -> control lookup did not return; probe invalid
#   control ok, no custom result log  -> failure is at the custom lookup stage
#   both results, custom not_resolved -> custom registration/lookup failure
#   both resolved                     -> lookup fine; failure is later create/apply
# The probe never branches on its results, and the -eq 2 check above keeps
# pinning both <loadout ref> creation sites, which must stay unchanged.
scenario_probe_line() { { grep -Fn "$1" "$scenario" || true; } | head -n 1 | cut -d: -f1; }
[[ $(grep -Fc "<get_loadout result=\"\$Issue67ProbeControl\" loadout=\"'scenario_combat_arg_carrier_02'\" macro=\"macro.{\$Def.\$macro}\"/>" "$scenario") -eq 1 ]] \
  || fail "issue #67 probe does not query the shipped control loadout ID with the Colossus macro"
[[ $(grep -Fc "<get_loadout result=\"\$Issue67ProbeCustom\" loadout=\"'x4gc_testlab_issue67_colossus_arc_barrel'\" macro=\"macro.{\$Def.\$macro}\"/>" "$scenario") -eq 1 ]] \
  || fail "issue #67 probe does not query the custom loadout ID with the Colossus macro"
grep -Fq "stage=control_result control=' + (if \$Issue67ProbeControlOk then 'resolved' else 'not_resolved')" "$scenario" \
  || fail "issue #67 probe does not log the control lookup result"
grep -Fq "stage=custom_start" "$scenario" \
  || fail "issue #67 probe does not mark the custom lookup start"
grep -Fq "stage=custom_result custom=' + (if \$Issue67ProbeCustomOk then 'resolved' else 'not_resolved')" "$scenario" \
  || fail "issue #67 probe does not log the custom lookup result"
ctl_lookup_line=$(scenario_probe_line "<get_loadout result=\"\$Issue67ProbeControl\"")
ctl_result_line=$(scenario_probe_line "stage=control_result")
cust_start_line=$(scenario_probe_line "stage=custom_start")
cust_lookup_line=$(scenario_probe_line "<get_loadout result=\"\$Issue67ProbeCustom\"")
cust_result_line=$(scenario_probe_line "stage=custom_result")
first_ref_line=$(scenario_probe_line '<loadout ref="x4gc_testlab_issue67_colossus_arc_barrel"/>')
[[ -n "$ctl_lookup_line" && -n "$ctl_result_line" && -n "$cust_start_line" && -n "$cust_lookup_line" && -n "$cust_result_line" && -n "$first_ref_line" ]] \
  || fail "issue #67 probe is missing one of its stage markers"
[[ "$ctl_lookup_line" -lt "$ctl_result_line" && "$ctl_result_line" -lt "$cust_start_line" && "$cust_start_line" -lt "$cust_lookup_line" && "$cust_lookup_line" -lt "$cust_result_line" && "$cust_result_line" -lt "$first_ref_line" ]] \
  || fail "issue #67 probe stages are not ordered control -> control result -> custom start -> custom lookup -> custom result -> create"
summary_count=$(grep -Fc "stage=summary" "$scenario" || true)
if [[ "$summary_count" -gt 0 ]]; then
  summary_line=$(scenario_probe_line "stage=summary")
  grep -Fq "stage=summary macro=" "$scenario" \
    || fail "issue #67 summary must name the probed Colossus macro"
  grep -Fq "' custom=' + (if \$Issue67ProbeCustomOk then 'resolved' else 'not_resolved') + ' control='" "$scenario" \
    || fail "issue #67 summary must report both lookup results"
  [[ "$cust_result_line" -lt "$summary_line" && "$summary_line" -lt "$first_ref_line" ]] \
    || fail "issue #67 summary must follow both result logs and precede the create"
fi

echo "testlab observability contract tests passed"
