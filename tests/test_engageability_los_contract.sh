#!/usr/bin/env bash
# Structural contract for EngageabilityCommit's line-of-fire probes (#60, #65).
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

# 1. Guided missile turrets bypass direct line of fire after the shared bearing
#    and range gates. The guidance discriminator must require both the missile-
#    turret class and guided loaded ammunition; absent guidance data therefore
#    stays on the conservative unguided path.
has "\$weapon.class == class.missileturret and \$weapon.ammo.macro and \$weapon.ammo.macro.isguided" \
  || note "guided missile-turret discriminator is missing or no longer ammo-aware"
has "<do_if value=\"\$guidedmissileturret\">" \
  || note "guided missile-turret branch is missing"
has "<set_value name=\"\$lineoffireclear\" exact=\"true\"/>" \
  || note "guided missile-turret branch must accept bearing + range without a direct LOS gate"

# 2. The root line-of-fire probe still exists for conventional and unguided
#    weapons. Missile turrets exclude the firing ship from this ray; ordinary
#    turrets continue to include it.
has "check_line_of_sight" || note "no check_line_of_sight in EngageabilityCommit"
has "target=\"\$target\"" || note "root check_line_of_sight against \$target is missing"
has "excludeself=\"\$weapon.class == class.missileturret\"" \
  || note "line-of-fire probes must exclude own hull only for missile turrets"

# 3. Module fallback is gated like vanilla: root ray failed, target is the whole
#    defensible root (not a player-selected surface element, #62), and modular
#    with more than one operational module.
has "not \$lineoffireclear" \
  || note "module fallback must be gated on 'not \$lineoffireclear' (root failed)"
has "\$target == \$target.defensible" \
  || note "module fallback must be gated on \$target == \$target.defensible (whole-root only, #62)"
has "\$target.defensible.ismodular" \
  || note "module fallback must be gated on \$target.defensible.ismodular"
has "@\$target.canhaveattackablemodules" \
  || note "module fallback must also admit ships with attackable defence modules (@\$target.canhaveattackablemodules)"
has "\$target.defensible.modules.operational.count" \
  || note "module fallback must guard on modules.operational.count"

# 4. The fallback iterates the target's modules and casts line of fire at a
#    per-module variable (not the root), with useaimtarget like vanilla.
has "\$target.defensible.modules.operational.list" \
  || note "module fallback must iterate defensible.modules.operational.list"
has "target=\"\$module\"" \
  || note "module fallback must check_line_of_sight against \$module"

# 5. The scan breaks on the first visible in-range module and does NOT cap the
#    module count: shipped move.attack.object.capital's 10-module cap is an NPC
#    nearest-first performance heuristic, not a correctness guarantee, so a
#    shootable module later in the list must not be ignored. That leaves exactly
#    one break in the cue (the first-visible-module break); a reintroduced index
#    cap adds a second and fails here.
breaks=$(printf '%s\n' "$block" | grep -Fc "<break/>")
[ "$breaks" -eq 1 ] \
  || note "module fallback must break only on the first visible in-range module (found $breaks breaks; an arbitrary module cap is not shipped-source-supported)"

# 6. Per-module range still reuses the #54 bbox predicate (no size term / no
#    reintroduction of the pre-#54 component-distance predicate for modules).
has "\$weapon.bboxdistanceto.{\$module} le \$weapon.maxfirerange" \
  || note "module range gate must reuse bboxdistanceto le maxfirerange (#54)"

# 7. Issue diagnostics must not ship in the production service.
for diagnostic in diag_engage "\$diaglos" "\$diaglosnoaim" "\$diaglosnoself"; do
  if has "$diagnostic"; then
    note "temporary issue #65 diagnostic remains: $diagnostic"
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "engageability los contract: FAILED" >&2
  exit 1
fi
echo "engageability los contract: ok"
