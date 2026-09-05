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

# Substring present anywhere in the cue. A here-string avoids the SIGPIPE that
# grep -q can give a printf producer under pipefail after an early match.
# Patterns are double-quoted with escaped '$' so they stay literal MD text.
has() { grep -Fq -- "$1" <<< "$block"; }

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
#    one break inside the module scan (the first-visible-module break); a
#    reintroduced index cap adds a second inside that loop and fails here. Scope
#    the count to the module do_for_each so the separate surface-element sample
#    break (checked at 8f) is not miscounted as a module cap.
module_scan=$(printf '%s\n' "$block" | awk '
  /<do_for_each name="\$module" in="\$modules">/ { grab = 1 }
  grab { print }
  grab && /<\/do_for_each>/ { exit }
')
[ -n "$module_scan" ] || note "module fallback do_for_each not found"
breaks=$(printf '%s\n' "$module_scan" | grep -Fc "<break/>")
[ "$breaks" -eq 1 ] \
  || note "module fallback must break only on the first visible in-range module (found $breaks breaks in the module scan; an arbitrary module cap is not shipped-source-supported)"

# 6. Per-module range still reuses the #54 bbox predicate (no size term / no
#    reintroduction of the pre-#54 component-distance predicate for modules).
has "\$weapon.bboxdistanceto.{\$module} le \$weapon.maxfirerange" \
  || note "module range gate must reuse bboxdistanceto le maxfirerange (#54)"

# 8. Issue #69 bounded surface-element bbox LOS fallback. The production
#    useaimtarget=true root ray remains the FIRST query (asserted above at 2).
#    When it is blocked and the target is a child surface element (not its own
#    defensible root) on a conventional (non-missileturret) weapon, probe a fixed
#    set of six interior bbox points and accept on the first clear one.
#
# 8a. The fallback is gated on a blocked root ray, a conventional (non-missile)
#     weapon, and a surface element (target is NOT its own defensible root). This
#     is the complement of the modular-root fallback ($target == $target.defensible).
has "not \$lineoffireclear" \
  || note "surface-element fallback must be gated on a blocked root ray (not \$lineoffireclear)"
has "\$target != \$target.defensible" \
  || note "surface-element fallback must be gated on \$target != \$target.defensible (child surface element only)"
has "\$weapon.class != class.missileturret" \
  || note "surface-element fallback must exclude missile turrets (\$weapon.class != class.missileturret)"

# 8b. bbox min per axis uses the repo idiom min = 2*center - max, on
#     $target.macro.boundingbox.
for axis in x y z; do
  has "2 * \$target.macro.boundingbox.center.$axis - \$target.macro.boundingbox.max.$axis" \
    || note "surface-element fallback must derive bbox min.$axis as 2*center - max"
done

# 8c. Exactly six normalized interior samples with the specified fractions,
#     carried as parallel fraction lists (the established .{counter} idiom).
has "[0.25, 0.75, 0.50, 0.50, 0.50, 0.50]" \
  || note "surface-element fallback x-fraction list must be [0.25, 0.75, 0.50, 0.50, 0.50, 0.50]"
has "[0.50, 0.50, 0.25, 0.75, 0.50, 0.50]" \
  || note "surface-element fallback y-fraction list must be [0.50, 0.50, 0.25, 0.75, 0.50, 0.50]"
has "[0.50, 0.50, 0.50, 0.50, 0.25, 0.75]" \
  || note "surface-element fallback z-fraction list must be [0.50, 0.50, 0.50, 0.50, 0.25, 0.75]"

# 8d. Each sample is a target-local position built from the indexed fractions.
has "object=\"\$target\" space=\"\$target\"" \
  || note "surface-element fallback samples must be target-local positions (object=\$target space=\$target)"

# 8e. Every fallback LOS uses the muzzle origin, an explicit interior targetoffset,
#     useaimtarget=false, and excludeself=false (production conventional policy).
has "targetoffset=\"\$surfacesample\" useaimtarget=\"false\" excludeself=\"false\"" \
  || note "surface-element fallback LOS must use the interior sample offset with useaimtarget=false excludeself=false"

# 8f. The current-origin scan stops on its first clear sample. Scope the break
#     assertion to this loop; the Beam-only prospective loop has its own break.
current_surface_scan=$(printf '%s\n' "$block" | awk '
  /<do_for_each name="\$surfacefrac" in="\$surfacexfracs"/ { grab = 1 }
  grab { print }
  grab && /<\/do_for_each>/ { exit }
')
[ -n "$current_surface_scan" ] || note "current-origin surface witness loop not found"
current_surface_breaks=$(printf '%s\n' "$current_surface_scan" | grep -Fc "<break/>")
[ "$current_surface_breaks" -eq 1 ] \
  || note "current-origin surface witness loop must break only on its first clear sample (found $current_surface_breaks)"

# 9. Issue #69 production prospective origin. It is a second, Beam-only chance
#    after the unchanged current-barrel fast ray and all six current-barrel
#    witnesses remain blocked. Unsupported conventional macros must never enter
#    this asset-specific geometry.
prospective_gate="not \$lineoffireclear and \$weapon.macro == macro.turret_par_l_beam_01_mk1_macro and EngageabilityService.\$muzzleknown.{\$weaponindex} == 1"
has "$prospective_gate" \
  || note "exact blocked + Paranid-L-Beam-only + generated-geometry-known prospective gate is missing"
macro_mentions=$(printf '%s\n' "$block" | grep -Fc 'macro.turret_par_l_beam_01_mk1_macro')
[ "$macro_mentions" -eq 1 ] \
  || note "prospective geometry must have exactly one exact Beam macro gate (found $macro_mentions mentions)"

# 9a. The accepted construction is applied to the GENERATED per-weapon geometry
#     only (#74 A2): a separate weapon-local fast-target bearing, then the O/P/D
#     vectors streamed as flat scalars (EngageabilityService.$muzzle*), applying
#     runtime pitch and then runtime yaw. This must not alter or reuse the
#     production look_at_bbox arc orientation.
has "name=\"\$prospectivebearing\" orientation=\"look_at\" refobject=\"\$target\" useaimtarget=\"true\"" \
  || note "prospective origin requires a separate weapon-local look_at + useaimtarget bearing"
has "<position object=\"\$weapon\" space=\"\$weapon\"/>" \
  || note "prospective bearing must be weapon-local"
has "<create_rotation name=\"\$prospectivepitchrotation\" pitch=\"\$prospectivebearing.pitch\"/>" \
  || note "prospective construction must apply the accepted runtime pitch"
has "<create_rotation name=\"\$prospectiveyawrotation\" yaw=\"\$prospectivebearing.yaw\"/>" \
  || note "prospective construction must apply the accepted runtime yaw"
# The downstream vector D, yaw origin O, and elevation pivot P must come from the
# streamed generated scalars, not hand-copied literals.
has "x=\"EngageabilityService.\$muzzledx.{\$weaponindex} * 1m\"" \
  || note "prospective downstream D must read the generated \$muzzledx scalar"
has "name=\"\$prospectiveyaworigin\" x=\"EngageabilityService.\$muzzleox.{\$weaponindex} * 1m\"" \
  || note "prospective yaw origin O must read the generated \$muzzleox scalar"
has "x=\"\$prospectivepitcheddownstream.x + EngageabilityService.\$muzzlepx.{\$weaponindex} * 1m\"" \
  || note "prospective elevation pivot P must read the generated \$muzzlepx scalar"
# The A1 hardcoded Beam literals must no longer exist anywhere in production.
# Patterns are double-quoted with escaped '$' so they stay literal MD text.
for literal in \
  "x=\"-0.36177411330546533m\" y=\"0.4829345992763463m\" z=\"55.87084740617998m\"" \
  "x=\"1.877547e-6m\" y=\"2.018104m + 6.145042419433594m\" z=\"-1.043081e-5m\"" \
  "z=\"\$prospectivepitcheddownstream.z - 16.11956m\""; do
  if grep -Fq -- "$literal" "$md"; then
    note "hardcoded Beam geometry literal must be removed from production: $literal"
  fi
done

# 9b. From that origin, retain conventional own-hull collision: fast aim-target
#     first, then (only if blocked) the same six target-local witnesses.
has "objectoffset=\"\$prospectivemuzzle\" target=\"\$target\" useaimtarget=\"true\" excludeself=\"false\"" \
  || note "prospective fast LOS must use the prospective muzzle with useaimtarget=true excludeself=false"
has "<do_if value=\"not \$lineoffireclear\">" \
  || note "prospective six-witness retry must be gated on a blocked prospective fast ray"
has "name=\"\$prospectivesample\" object=\"\$target\" space=\"\$target\"" \
  || note "prospective witnesses must remain target-local"
has "objectoffset=\"\$prospectivemuzzle\" target=\"\$target\" targetoffset=\"\$prospectivesample\" useaimtarget=\"false\" excludeself=\"false\"" \
  || note "prospective witness LOS must use the prospective muzzle with useaimtarget=false excludeself=false"
prospective_scan=$(printf '%s\n' "$block" | awk '
  /<do_for_each name="\$prospectivefrac" in="\$surfacexfracs"/ { grab = 1 }
  grab { print }
  grab && /<\/do_for_each>/ { exit }
')
[ -n "$prospective_scan" ] || note "prospective six-witness loop not found"
prospective_breaks=$(printf '%s\n' "$prospective_scan" | grep -Fc "<break/>")
[ "$prospective_breaks" -eq 1 ] \
  || note "prospective witness loop must break only on its first clear sample (found $prospective_breaks)"

# 9c. Ordering is contractual: current fast, current six, Beam gate/construction,
#     prospective fast, prospective six. The arrays above are shared unchanged.
line_of() { grep -nF -- "$1" <<< "$block" | head -n 1 | cut -d: -f1; }
current_fast_line=$(line_of "objectoffset=\"\$weapon.barrelposition\" target=\"\$target\" excludeself=\"\$weapon.class == class.missileturret\" useaimtarget=\"true\"")
current_six_line=$(line_of "<do_for_each name=\"\$surfacefrac\" in=\"\$surfacexfracs\"")
prospective_gate_line=$(line_of "$prospective_gate")
prospective_fast_line=$(line_of "objectoffset=\"\$prospectivemuzzle\" target=\"\$target\" useaimtarget=\"true\" excludeself=\"false\"")
prospective_six_line=$(line_of "<do_for_each name=\"\$prospectivefrac\" in=\"\$surfacexfracs\"")
if [ -z "$current_fast_line" ] || [ -z "$current_six_line" ] || [ -z "$prospective_gate_line" ] || [ -z "$prospective_fast_line" ] || [ -z "$prospective_six_line" ] \
   || ! [ "$current_fast_line" -lt "$current_six_line" ] \
   || ! [ "$current_six_line" -lt "$prospective_gate_line" ] \
   || ! [ "$prospective_gate_line" -lt "$prospective_fast_line" ] \
   || ! [ "$prospective_fast_line" -lt "$prospective_six_line" ]; then
  note "LOS ordering must be current fast -> current six -> Beam gate -> prospective fast -> prospective six"
fi

# 9d. The x4gce3 per-target and x4gce2c batch result protocol is unchanged.
has "'x4gce3:' + \$nonce + ':' + EngageabilityService.\$targetids.{\$targetindex} + ':' + \$engageable + ':' + \$known + ':' + EngageabilityService.\$expectedmembers" \
  || note "x4gce3 per-target result protocol changed"
has "'x4gce2c:' + \$nonce + ':' + EngageabilityService.\$targets.count + ':' + \$completed" \
  || note "x4gce2c batch-complete protocol changed"

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
