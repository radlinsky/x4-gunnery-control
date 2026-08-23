#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

md=testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_observe.xml
scenario=testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_scenario.xml
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
grep -Fq "'x4gct7:'" "$scenario" \
  || fail "scenario acknowledgement does not use remote-shooter census protocol x4gct7"
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

echo "testlab observability contract tests passed"
