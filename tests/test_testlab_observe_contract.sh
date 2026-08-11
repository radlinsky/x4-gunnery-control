#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

md=testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_observe.xml
fail() { echo "FAIL: $1" >&2; exit 1; }

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

echo "testlab observability contract tests passed"
