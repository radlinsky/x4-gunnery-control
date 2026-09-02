#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

md=testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_observe.xml
scenario=testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_scenario.xml
loadouts=testlab/x4_gunnery_control_testlab/libraries/loadouts.xml
testlab_ui=testlab/x4_gunnery_control_testlab/ui/testlab.lua
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
fired_aim=$(printf '%s\n' "$fired_target" | grep -F 'AimTarget? and' | cut -d: -f1)
fired_soft=$(printf '%s\n' "$fired_target" | grep -F 'SoftTarget? and' | cut -d: -f1)
fired_player=$(printf '%s\n' "$fired_target" | grep -F 'player.target?' | cut -d: -f1)
if ! [[ "$fired_aim" -lt "$fired_soft" && "$fired_soft" -lt "$fired_player" ]]; then
  fail "FIRED target precedence is not AimTarget > soft target > player.target"
fi

# A firing event must measure the projectile's actual angular error to the
# selected component. Global UI aim state alone cannot identify a turret's
# engagement target, which is the ambiguity this diagnostic exists to remove.
grep -Fq "name=\"\$TargetBearing\" exact=\"if \$Aimed then \$Aimed.relativeposition.{event.param} else null\"" "$md" \
  || fail "FIRED observer lost projectile-local target bearing"
grep -Fq "name=\"\$TargetMountBearing\" exact=\"if \$Aimed then \$Aimed.relativeposition.{event.object} else null\"" "$md" \
  || fail "FIRED observer does not derive target bearing from the exact firing weapon"
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

# Scenario READY carries generic numeric census fields. Keep the persistent
# groups separate from their serialized counts so acknowledgements stay flat.
grep -Fq "name=\"\$SafeObjectCount\" exact=\"0\"" "$scenario" \
  || fail "safe-fixture numeric census is missing"
grep -Fq "':' + \$SafeObjectCount + ':' + \$SafeWeapons" "$scenario" \
  || fail "scenario acknowledgement does not serialize the numeric safe-fixture census"
if grep -Fq "':' + \$SafeObjects + ':' + \$SafeWeapons" "$scenario"; then
  fail "scenario acknowledgement serializes the safe-fixture group"
fi
grep -Fq "'x4gct9:'" "$scenario" \
  || fail "scenario acknowledgement does not use the current generic census protocol"
grep -Fq "':' + \$UnsafeWeapons + ':' + \$DefenceUnits + ':' + \$Hostiles + ':' + \$RepairObjectCount" "$scenario" \
  || fail "scenario acknowledgement omits reusable safety/repair counts"
grep -Fq "':' + \$ShooterCount + ':' + \$ShooterWeapons + ':' + \$ShooterTurrets + ':' + \$ShooterMissileTurrets" "$scenario" \
  || fail "scenario acknowledgement omits the generic shooter census"
grep -Fq "':' + (\$LoadoutFailures + \$UnsafeDormantShooterWeapons) + ':' + \$LocationFailures" "$scenario" \
  || fail "scenario acknowledgement omits loadout or placement failures"

# Reusable fixture safety and repair attribution must survive the simplification.
grep -Fq "groupname=\"ScenarioRoot.\$RepairObjects\" object=\"\$Ship\"" "$scenario" \
  || fail "repair-guard fixtures are not registered during spawn"
grep -Fq "groupname=\"ScenarioRoot.\$PlayerShooters\" object=\"player.ship\"" "$scenario" \
  || fail "local scenarios do not attribute repair hits to the current player ship"
grep -Fq "groupname=\"ScenarioRoot.\$PlayerShooters\" object=\"\$Ship\"" "$scenario" \
  || fail "remote scenarios do not attribute repair hits to their spawned shooter"
grep -Fq "<event_object_attacked_object group=\"ScenarioRoot.\$PlayerShooters\"/>" "$scenario" \
  || fail "repair guard is not driven by the unified local/remote shooter group"
grep -Fq '<set_object_hull object="event.param3.{1}" exact="100"/>' "$scenario" \
  || fail "repair guard does not restore the exact struck component"
grep -Fq "not (ScenarioRoot.\$Spawned? and ScenarioRoot.\$Spawned.indexof.{player.ship})" "$scenario" \
  || fail "scenario replacement and cleanup do not guard the occupied spawned ship"
grep -Fq '<cue name="ScenarioCommitOccupiedReject" instantiate="true">' "$scenario" \
  || fail "MD has no defensive rejection path for occupied-fixture replacement"
grep -Fq '<cue name="DespawnScenarioOccupiedReject" instantiate="true">' "$scenario" \
  || fail "MD has no defensive rejection path for occupied-fixture cleanup"

# A remote shooter remains dormant until the owner teleports, and placement is
# checked in sector coordinates against the authored remote anchor.
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
  || fail "remote placement validation does not compare sector-coordinate x against the expected position"
if grep -Fq "\$Ship.position.x lt ScenarioRoot.\$PendingAnchorX" "$scenario"; then
  fail "remote placement validation compares a zone-local ship position against the sector anchor"
fi

# Deterministic equipment remains data. Protect the proven equipment semantics
# under descriptive library ids rather than historical issue-numbered branches.
python3 - "$loadouts" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()

def loadout(loadout_id):
    match = re.search(r'<loadout id="' + re.escape(loadout_id) + r'"[^>]*>(.*?)</loadout>', text, re.DOTALL)
    if not match:
        raise SystemExit(f"FAIL: missing deterministic loadout {loadout_id}")
    return match.group(1)

mixed = loadout("x4gc_testlab_par_l_destroyer_01_mixed_missiles")
expected = {
    'turret_par_m_guided_02_mk1_macro': 3,
    'turret_par_m_dumbfire_02_mk1_macro': 3,
    'turret_par_l_guided_01_mk1_macro': 2,
    'turret_par_l_dumbfire_01_mk1_macro': 1,
}
for macro, count in expected.items():
    actual = mixed.count(f'<turrets macro="{macro}"')
    if actual != count:
        raise SystemExit(f"FAIL: mixed-missile loadout {macro} count {actual}, expected {count}")
if mixed.count('<ammunition macro="missile_gen_') != 4 or mixed.count('exact="40"/>') != 4:
    raise SystemExit("FAIL: mixed-missile loadout no longer stocks four 40-round missile types")

dual = loadout("x4gc_testlab_par_l_destroyer_01_beam_plasma")
for entry in (
    '<turrets macro="turret_par_l_plasma_01_mk1_macro" group="group_front_up_mid2" exact="1"/>',
    '<turrets macro="turret_par_l_beam_01_mk1_macro" group="group_rear_down_mid" exact="1"/>',
):
    if entry not in dual:
        raise SystemExit(f"FAIL: beam/plasma deterministic loadout lost {entry}")
PY

grep -Fq 'expectedMemberMacros' "$testlab_ui" \
  || fail "Test Lab no longer accepts exact expected member macros"
grep -Fq "<param name=\"skipalignment\" value=\"\$Def.\$preserveorientation\"/>" "$scenario" \
  || fail "Wait fixtures no longer preserve authored orientation when requested"

# Raw observer contract: Lua owns the two auto-marks (initial on a
# newly accepted aim target, settled at 20 active seconds with paused time
# excluded), and the MD records stay raw and independent — the solution line
# keeps its own fields, not a derived verdict.
grep -Fq '<cue name="ObserveMark" instantiate="true">' "$md" \
  || fail "ObserveMark observer cue is missing"
grep -Fq '<cue name="ObserveFired" instantiate="true">' "$md" \
  || fail "ObserveFired observer cue is missing"
grep -Fq '<cue name="ObserveHit" instantiate="true">' "$md" \
  || fail "ObserveHit observer cue is missing"

# Lua: a newly accepted aim target (different from lastObservedAimTarget) emits
# the same observe_mark event the Mark button emits and logs auto_mark_initial.
grep -Fq 'and aimTarget ~= lastObservedAimTarget then' "$testlab_ui" \
  || fail "initial auto-mark no longer keys off lastObservedAimTarget"
[[ $(grep -Fc 'AddUITriggeredEvent("X4GunneryTestLabObserve", "observe_mark")' "$testlab_ui") -ge 2 ]] \
  || fail "observe_mark must be emitted for both the initial and the settled auto-mark"
grep -Fq 'log("observe", { action = "auto_mark_initial", target = aimTarget })' "$testlab_ui" \
  || fail "initial auto-mark does not log action=auto_mark_initial"
# Lua: the new target restarts the active-second clock, paused game time is
# excluded via bridge.isGamePaused, and at >= 20 active seconds the target is
# marked again, settled, with active_seconds logged.
grep -Fq 'observedAimActiveSeconds, observedAimLastTick, observedAimSettled = 0, now, false' "$testlab_ui" \
  || fail "does not restart the active-second clock for a new aim target"
grep -Fq 'if not (bridge.isGamePaused and bridge.isGamePaused()) then' "$testlab_ui" \
  || fail "active-second clock does not exclude paused game time via bridge.isGamePaused"
grep -Fq 'if observedAimActiveSeconds >= 20 then' "$testlab_ui" \
  || fail "settled auto-mark does not wait for 20 active seconds"
grep -Fq 'observedAimSettled = true' "$testlab_ui" \
  || fail "does not mark the aim target settled"
grep -Fq 'log("observe", { action = "auto_mark_settled", target = aimTarget, active_seconds = observedAimActiveSeconds })' "$testlab_ui" \
  || fail "settled auto-mark does not log action=auto_mark_settled with active_seconds"
observer_lua_line() { { grep -Fn "$1" "$testlab_ui" || true; } | head -n 1 | cut -d: -f1; }
observer_initial_line=$(observer_lua_line 'action = "auto_mark_initial"')
observer_threshold_line=$(observer_lua_line 'if observedAimActiveSeconds >= 20 then')
observer_settled_line=$(observer_lua_line 'action = "auto_mark_settled"')
[[ -n "$observer_initial_line" && -n "$observer_threshold_line" && -n "$observer_settled_line" && "$observer_initial_line" -lt "$observer_threshold_line" && "$observer_threshold_line" -lt "$observer_settled_line" ]] \
  || fail "auto-mark logs are not ordered initial -> 20 s threshold -> settled"

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
    || fail "ObserveMark solution record lost the raw field: $field"
done
[[ $(printf '%s\n' "$mark_cue" | grep -Fc "' inrange=' + (\$Weapon.bboxdistanceto.{\$Target} le \$Weapon.maxfirerange)") -eq 2 ]] \
  || fail "ObserveMark must log the raw inrange/bbox solution in both snapshot loops"

# MD ObserveFired: listens on the armed firing-weapon group and logs the exact
# emitter (event.object), the aimed target, and the exact aim error.
printf '%s\n' "$fired_cue" | grep -Fq "<event_weapon_fired group=\"\$FiringWeapons\"/>" \
  || fail "ObserveFired no longer listens to event_weapon_fired on \$FiringWeapons"
printf '%s\n' "$fired_cue" | grep -Fq "+ ' weapon=' + event.object" \
  || fail "FIRED does not log the exact emitter as weapon=event.object"
printf '%s\n' "$fired_cue" | grep -Fq "+ ' aimed=' + (if \$Aimed then \$Aimed else 'none')" \
  || fail "FIRED does not log the aimed target"
printf '%s\n' "$fired_cue" | grep -Fq "+ ' aim_error_yaw=' + (if \$TargetBearing then \$TargetBearing.rotation.yaw else 'none')" \
  || fail "FIRED lost the exact yaw aim-error field"
printf '%s\n' "$fired_cue" | grep -Fq "+ ' aim_error_pitch=' + (if \$TargetBearing then \$TargetBearing.rotation.pitch else 'none')" \
  || fail "FIRED lost the exact pitch aim-error field"

# FIRED must capture the two raw runtime measurements needed for the later
# controlled discriminator: the exact firing weapon's barrel position and the
# aimed target's bearing in that weapon's local/mount frame. Keep target fields
# survivable when the fallback chain resolves to no target.
printf '%s\n' "$fired_cue" | grep -Fq "<set_value name=\"\$Barrel\" exact=\"event.object.barrelposition\"/>" \
  || fail "FIRED does not read the exact firing weapon barrelposition"
printf '%s\n' "$fired_cue" | grep -Fq "<set_value name=\"\$Aimed\" exact=\"null\"/>" \
  || fail "FIRED does not initialize its aimed target for the no-target fallback"
printf '%s\n' "$fired_cue" | grep -Fq "<set_value name=\"\$TargetBearing\" exact=\"if \$Aimed then \$Aimed.relativeposition.{event.param} else null\"/>" \
  || fail "FIRED lost projectile-local target bearing"
printf '%s\n' "$fired_cue" | grep -Fq "<set_value name=\"\$TargetMountBearing\" exact=\"if \$Aimed then \$Aimed.relativeposition.{event.object} else null\"/>" \
  || fail "FIRED does not derive aimed-target bearing from the exact firing weapon"
for field in \
  "+ ' barrel_x=' + \$Barrel.x" \
  "+ ' barrel_y=' + \$Barrel.y" \
  "+ ' barrel_z=' + \$Barrel.z" \
  "+ ' target_mount_yaw=' + (if \$TargetMountBearing then \$TargetMountBearing.rotation.yaw else 'none')" \
  "+ ' target_mount_pitch=' + (if \$TargetMountBearing then \$TargetMountBearing.rotation.pitch else 'none')"; do
  printf '%s\n' "$fired_cue" | grep -Fq "$field" \
    || fail "FIRED lost required raw measurement field: $field"
done

# MD ObserveHit: one line per hit on the exact armed ship, attributing the
# weapon, the exact struck component, the aimed target, and istgt.
printf '%s\n' "$hit_cue" | grep -Fq "<event_object_attacked_object object=\"\$Ship\"/>" \
  || fail "ObserveHit no longer listens to event_object_attacked_object on \$Ship"
printf '%s\n' "$hit_cue" | grep -Fq "<set_value name=\"\$Weapon\" exact=\"@event.param3.{2}\"/>" \
  || fail "HIT no longer attributes the weapon from event.param3.{2}"
printf '%s\n' "$hit_cue" | grep -Fq "+ ' weapon=' + (if \$Weapon then \$Weapon else 'none')" \
  || fail "HIT does not log the attributed weapon"
printf '%s\n' "$hit_cue" | grep -Fq "+ ' hitcomp=' + (if @event.param3.{1} then event.param3.{1} else 'none')" \
  || fail "HIT does not log the exact struck component"
printf '%s\n' "$hit_cue" | grep -Fq "+ ' aimed=' + (if \$Aimed then \$Aimed else 'none')" \
  || fail "HIT does not log the aimed target"
printf '%s\n' "$hit_cue" | grep -Fq "+ ' istgt=' + (\$Aimed? and (event.param == \$Aimed or @event.param3.{1} == \$Aimed))" \
  || fail "HIT istgt is not component-aware"

echo "testlab observability contract tests passed"
