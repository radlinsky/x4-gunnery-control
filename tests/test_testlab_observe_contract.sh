#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

md=testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_observe.xml
scenario=testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_scenario.xml
fail() { echo "FAIL: $1" >&2; exit 1; }

# A live Gunnery Control session's AimTarget is authoritative. The free-play
# fallback chain remains soft target, then player.target. Keep these checks
# adjacent to the two consumers so a future edit cannot silently make HIT and
# solution attribution disagree.
snapshot_target=$(awk '/<cue name="ObserveMark"/{inside=1} /<cue name="ObserveState"/{inside=0} inside && /AimTarget|SoftTarget|player\.target/{print NR ":" $0}' "$md")
hit_target=$(awk '/<cue name="ObserveHit"/{inside=1} /<cue name="ObserveCensus"/{inside=0} inside && /AimTarget|SoftTarget|player\.target/{print NR ":" $0}' "$md")
fired_target=$(awk '/<cue name="ObserveFired"/{inside=1} /<cue name="ObserveHit"/{inside=0} inside && /AimTarget|SoftTarget|player\.target/{print NR ":" $0}' "$md")
printf '%s\n' "$snapshot_target" | grep -q 'AimTarget' || fail "solution snapshot does not prefer AimTarget"
printf '%s\n' "$snapshot_target" | grep -q 'SoftTarget' || fail "solution snapshot lost soft-target fallback"
printf '%s\n' "$snapshot_target" | grep -q 'player.target' || fail "solution snapshot lost player.target fallback"
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
  fail "solution snapshot target precedence is not AimTarget > soft target > player.target"
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

# Reciprocal preferred-target tests need an automatic A -> B -> A boundary.
# Every selected-target change receives a monotonic epoch and an engine-time
# origin; FIRED and HIT records carry both so pre-switch rounds can be excluded
# from the settled post-switch evidence window.
grep -Fq "name=\"ObserveRoot.\$AimEpoch\" exact=\"ObserveRoot.\$AimEpoch + 1\"" "$md" \
  || fail "observer does not increment a target-switch epoch"
grep -Fq "'[X4GC TEST SWITCH] epoch='" "$md" \
  || fail "observer does not log target-switch boundaries"
grep -Fq "' epoch=' + ObserveRoot.\$AimEpoch" "$md" \
  || fail "observer fire/hit records do not carry the current switch epoch"
epoch_consumers=$(grep -Fc "' since_switch=' + (player.age - ObserveRoot.\$AimChangedAt)" "$md")
[[ "$epoch_consumers" -eq 2 ]] \
  || fail "expected FIRED and HIT to carry time since switch, found $epoch_consumers consumers"

# The candidate mechanical-arc bearing uses the target's weapon-consistent aim
# point in the turret mount's local frame; keep it diagnostic until live proof.
aimlocal=$(grep -Fc "<position object=\"\$Weapon\" space=\"\$Weapon\"/>" "$md")
[[ "$aimlocal" -eq 2 ]] || fail "expected local aim orientation in both weapon snapshot loops, found $aimlocal"

# A selected surface component is a valid aim target. The hit event carries
# both the victim object and the struck component; istgt must accept either
# representation rather than comparing only the victim root.
grep -Fq "event.param == \$Aimed or @event.param3.{1} == \$Aimed" "$md" \
  || fail "HIT attribution does not compare the selected component"

# The solution snapshot and the census are both denominators. Each must cover
# regular weapons/turrets and the separate missile-turret property list.
weapons=$(grep -Fc 'in="player.ship.weapons.operational.list"' "$md")
missiles=$(grep -Fc 'in="player.ship.missileturrets.operational.list"' "$md")
ship_weapons=$(grep -Fc "in=\"\$Ship.weapons.operational.list\"" "$md")
ship_missiles=$(grep -Fc "in=\"\$Ship.missileturrets.operational.list\"" "$md")
[[ "$weapons" -eq 1 ]] || fail "expected one player weapons snapshot loop, found $weapons"
[[ "$missiles" -eq 1 ]] || fail "expected one player missile-turret snapshot loop, found $missiles"
[[ "$ship_weapons" -eq 1 ]] || fail "expected one census weapons loop, found $ship_weapons"
[[ "$ship_missiles" -eq 1 ]] || fail "expected one census missile-turret loop, found $ship_missiles"

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
grep -Fq "'x4gct6:'" "$scenario" \
  || fail "scenario acknowledgement does not use repair-aware protocol x4gct6"
grep -Fq "':' + \$Hostiles + ':' + \$RepairObjectCount" "$scenario" \
  || fail "scenario acknowledgement omits the repair-guard census"
grep -Fq "groupname=\"ScenarioRoot.\$RepairObjects\" object=\"\$Ship\"" "$scenario" \
  || fail "repair-guard fixtures are not registered during spawn"
grep -Fq "<event_object_attacked_object object=\"\$Ship\"/>" "$scenario" \
  || fail "repair guard is not driven by attributed player-ship hits"
grep -Fq '<set_object_hull object="event.param3.{1}" exact="100"/>' "$scenario" \
  || fail "repair guard does not restore the exact struck component"

echo "testlab observability contract tests passed"
