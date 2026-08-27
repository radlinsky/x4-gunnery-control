#!/usr/bin/env bash
# Structural contract for EngageabilityCommit's arc-aim source (#69).
#
# Issue #55 moved the firing-arc check from the component origin to the
# hittable surface; issue #67 (commit 4e21cd0) live-proved origin bearing vs
# hittable aim point and switched to the weapon-local useaimtarget aim point;
# issue #69 is single sampled aim point vs the whole component box: useaimtarget
# samples ONE of the victim's many hittable points while X4 may fire at a
# different in-arc point of the same mesh, so the arc test must aim at the
# component bounding box (look_at_bbox, common.xsd:2616) and the single-aim-
# point sample must not return. This asserts the production MD shape, which
# the Lua tests cannot execute. It fails on the pre-#69 orientation.
set -euo pipefail
cd "$(dirname "$0")/.."

md=md/x4_gunnery_control.xml
fail=0
note() { echo "engageability arc contract: $1" >&2; fail=1; }

# The EngageabilityCommit block: from the cue open to its close.
block=$(awk '
  /<cue name="EngageabilityCommit"/ { grab = 1 }
  grab { print }
  grab && /<\/cue>/ { exit }
' "$md")

[ -n "$block" ] || { note "EngageabilityCommit cue not found in $md"; exit 1; }

# count($expression) over the whole MD must equal $expected.
expect_count() {
  local expected=$1 expression=$2 description=$3 actual
  actual=$(xmllint --xpath "$expression" "$md")
  if [ "$actual" != "$expected" ]; then
    note "$description: expected $expected, found $actual"
  fi
}

# 1. The arc test aims at the component bounding box from the weapon's mount
#    frame, inside the arcknown==1 gate. look_at_bbox already resolves the
#    refobject's box, so no useaimtarget: a sampled aim point would defeat #69.
expect_count 1 \
  "count(//cue[@name='EngageabilityCommit']//do_if[contains(@value, 'EngageabilityService.\$arcknown.{\$weaponindex} == 1')]/create_orientation[@name='\$aimorientation'][@orientation='look_at_bbox'][@refobject='\$target'][not(@useaimtarget)]/position[@object='\$weapon'][@space='\$weapon'])" \
  "weapon-local bounding-box orientation"

# 2. Exactly one such orientation exists in the whole MD, and the pre-#69
#    single-aim-point sample (look_at + useaimtarget) is gone everywhere.
expect_count 1 \
  "count(//create_orientation[@name='\$aimorientation'][@orientation='look_at_bbox'][@refobject='\$target'][not(@useaimtarget)])" \
  "whole-MD bounding-box orientation count"
expect_count 0 \
  "count(//create_orientation[@name='\$aimorientation'][@orientation='look_at'][@useaimtarget='true'])" \
  "pre-#69 single-aim-point sample reintroduced"

# 3. The component-origin arc bearing is absent (#67 guard).
if grep -Fq "\$target.relativeposition.{\$weapon}.rotation.pitch" "$md"; then
  note "component-origin firing-arc bearing reintroduced (#67)"
fi

# 4. The pitch assignment still reads the bounding-box orientation, and the
#    arc/range gate survives verbatim: exactly one $aimpitch do_if, whose
#    complete three-term comparison expression matches byte for byte. The
#    attribute is read from the source bytes, not through xmllint string(),
#    because this libxml build renders attribute newlines as spaces there and
#    would hide line-structure changes. Any added, removed, reordered or
#    flipped term — or any other alteration of the line — fails this check.
expect_count 1 \
  "count(//cue[@name='EngageabilityCommit']//set_value[@name='\$aimpitch'][@exact='\$aimorientation.pitch'])" \
  "aim pitch assignment from the bounding-box orientation"
expect_count 1 \
  "count(//cue[@name='EngageabilityCommit']//do_if[starts-with(@value, '\$aimpitch')])" \
  "arc/range gate do_if count"
gate_value=$(awk '
  !found && /<do_if value="\$aimpitch / { found = 1; buf = $0; sub(/^.*<do_if value="/, "", buf); next }
  found {
    p = index($0, "\"")
    if (p == 0) { buf = buf "\n" $0; next }
    buf = buf "\n" substr($0, 1, p - 1)
    print buf
    exit
  }
' "$md")
expected_gate="$(cat <<'ENGAGEABILITY_GATE'
$aimpitch ge (EngageabilityService.$arcmins.{$weaponindex} * 1deg)
                                  and $aimpitch le (EngageabilityService.$arcmaxs.{$weaponindex} * 1deg)
                                  and $weapon.bboxdistanceto.{$target} le $weapon.maxfirerange
ENGAGEABILITY_GATE
)"
[ "$gate_value" = "$expected_gate" ] || note "arc/range gate comparison expression is not byte-identical"

# 5. The orientation occurs only inside an arcknown==1 do_if, so an unknown or
#    modded arc (arcknown != 1) is never evaluated against the bounding box.
expect_count 1 \
  "count(//create_orientation[@name='\$aimorientation'][ancestor::do_if[contains(@value, 'EngageabilityService.\$arcknown.{\$weaponindex} == 1')]])" \
  "bounding-box orientation outside the arcknown==1 gate"

# 6. Both line-of-fire gates keep useaimtarget: the root probe and the
#    module-fallback probe (vanilla move.attack.object.capital behaviour).
expect_count 1 \
  "count(//cue[@name='EngageabilityCommit']//check_line_of_sight[@object='\$weapon'][@objectoffset='\$weapon.barrelposition'][@excludeself='\$weapon.class == class.missileturret'][@useaimtarget='true'][@target='\$target'])" \
  "root line-of-fire gate"
expect_count 1 \
  "count(//cue[@name='EngageabilityCommit']//check_line_of_sight[@object='\$weapon'][@objectoffset='\$weapon.barrelposition'][@excludeself='\$weapon.class == class.missileturret'][@useaimtarget='true'][@target='\$module'])" \
  "module-fallback line-of-fire gate"

# 7. The x4gce3 result protocol attribute is byte-identical. Pinned from the
#    opening param= quote through the closing quote, so a field appended
#    after $expectedmembers (or inserted before the first one) also fails.
grep -Fq "param=\"'x4gce3:' + \$nonce + ':' + EngageabilityService.\$targetids.{\$targetindex} + ':' + \$engageable + ':' + \$known + ':' + EngageabilityService.\$expectedmembers\"" "$md" \
  || note "x4gce3 result protocol attribute changed"

if [ "$fail" -ne 0 ]; then
  echo "engageability arc contract: FAILED" >&2
  exit 1
fi
echo "engageability arc contract: ok"
