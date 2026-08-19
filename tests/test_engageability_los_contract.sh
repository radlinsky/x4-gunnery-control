#!/usr/bin/env bash
# Structural contract for EngageabilityCommit's line-of-fire probe (issue #60).
#
# A large ship/station root's useaimtarget line-of-sight resolves to the bbox
# centre, which sits inside the hull and self-blocks the ray, so the root probe
# alone false-negatives even while selected turrets fire at surface modules.
# Vanilla move.attack.object.capital (9.00) handles this with a per-module
# line-of-fire fallback. This asserts that fallback stays present in the MD,
# which the Lua tests cannot execute. It fails on the pre-#60 root-only probe.
set -euo pipefail
cd "$(dirname "$0")/.."

md=md/x4_gunnery_control.xml
fail=0
note() { echo "engageability los contract: $1" >&2; fail=1; }

# The EngageabilityCommit block: from the cue open to its close.
block=$(awk '
  /<cue name="EngageabilityCommit"/ { grab = 1 }
  grab { print }
  grab && /<\/cue>/ { exit }
' "$md")

[ -n "$block" ] || { note "EngageabilityCommit cue not found in $md"; exit 1; }

# Substring present anywhere in the cue. Patterns are double-quoted with escaped
# '$' so they stay literal MD text (no shell expansion, no SC2016).
has() { printf '%s\n' "$block" | grep -Fq "$1"; }

# 1. The root line-of-fire probe still exists (the existing behaviour).
has "check_line_of_sight" || note "no check_line_of_sight in EngageabilityCommit"
has "target=\"\$target\"" || note "root check_line_of_sight against \$target is missing"

# 2. Module fallback is gated like vanilla: root ray failed, target is modular
#    with more than one operational module.
has "not \$lineoffireclear" \
  || note "module fallback must be gated on 'not \$lineoffireclear' (root failed)"
has "\$target.defensible.ismodular" \
  || note "module fallback must be gated on \$target.defensible.ismodular"
has "\$target.defensible.modules.operational.count" \
  || note "module fallback must guard on modules.operational.count"

# 3. The fallback iterates the target's modules and casts line of fire at a
#    per-module variable (not the root), with useaimtarget like vanilla.
has "\$target.defensible.modules.operational.list" \
  || note "module fallback must iterate defensible.modules.operational.list"
has "target=\"\$module\"" \
  || note "module fallback must check_line_of_sight against \$module"

# 4. The module scan is bounded (no unbounded per-target cost inside the batch).
{ has "\$moduleindex" && has "<break/>"; } \
  || note "module scan must be bounded by a counter break"

# 5. Per-module range still reuses the #54 bbox predicate (no size term / no
#    reintroduction of the pre-#54 component-distance predicate for modules).
has "\$weapon.bboxdistanceto.{\$module} le \$weapon.maxfirerange" \
  || note "module range gate must reuse bboxdistanceto le maxfirerange (#54)"

if [ "$fail" -ne 0 ]; then
  echo "engageability los contract: FAILED" >&2
  exit 1
fi
echo "engageability los contract: ok"
