# Issue #67 — arc branch: redesign handoff

Status date: 2026-08-25. Branch: `feature/issue-67-arc-barrel-fixture`.
Live env: X4 9.00, log `C:\Users\PC\Documents\Egosoft\X4\51053644\debug.log`.

## 1. What issue #67 is actually asking (plain English)

The mod shows an **ENGAGEABLE** indicator: "can this turret actually shoot this
part of that enemy ship?" #67 asked whether two ways the game answers that could
make the mod's indicator wrong.

- **Goal 1 — origin vs. hittable point.** Every component on a ship has one
  reference point (its "origin") and also a 3D shape with many "hittable points."
  A turret can only swivel within limits (an arc). The mod checks whether the
  *origin* is inside the arc. But the game might instead aim at a *hittable
  point*. Near the edge of the arc these differ: the origin can be just outside
  while a hittable point is just inside. **Question: which does X4 use, and if
  the origin is outside the arc but a hittable point is inside, does the turret
  fire?** If X4 uses hittable points, the mod's origin check would be wrong.

- **Goal 2 — own-hull line of fire / zero barrel.** Each weapon reports where its
  barrel is (`barrelposition`). The mod uses that to check "does my shot pass
  through my own ship's hull?" **Question: does a zero/garbage barrelposition
  cause false 'blocked' reports, and will X4 fire a shot that clips its own
  hull?**

## 2. What is already settled — do NOT redo

Per the issue body's own status table and the r9/r11 live runs:

- **Goal 2 (zero barrel): resolved NEGATIVE.** The `_02` beam/plasma macros
  reported clearly nonzero `barrelposition` on both hulls. Do not build a
  zero-barrel workaround.
- **Conventional own-hull masking: resolved by r11.** X4's autoassist held fire
  on an own-hull-masked surface element, and the mod correctly reported 0/2
  ENGAGEABLE. The self-inclusive line-of-fire gate agrees with the engine. Keep
  it.
- **Only open item: Goal 1** — origin vs. hittable-aim-point arc check.
  "Existence observed, behavioral question still open." There is currently **no
  production ENGAGEABLE change required by #67**; the arc question is the last
  loose end.

## 3. Two fixture attempts and why they failed

- **r14, Behemoth E arc-survey (sol's pivot):** un-runnable. The Behemoth E has
  no gunner console, so the whole "teleport aboard → open Gunnery Control → Test
  Lab" flow is impossible (that console-less ingress is issue #68, not built).
  Separately, the Behemoth E rejects singular `<turret path>` loadout entries
  (empty ship). Abandoned.
- **r15, Colossus E arc-survey (this rebuild):** runs correctly and reproduces
  the intended geometry (live `rel_pitch`/`aim_pitch` match the offline ring
  math to ~0.01°), but the result is **inconclusive** for the reason in §4.

## 4. Why the arc-survey ring cannot answer Goal 1 (the decisive problem)

Two independent walls, both confirmed live:

**(a) The origin/aim gap is far too small.** For a distant Xenon element at
~3600 m, its origin and its nearest hittable point differ by only **~0.04° in
pitch**. The qualified r15 candidate: origin pitch −10.02°, aim pitch −9.98° —
i.e. the "split" straddles the −10° arc limit by ~0.02° on each side. That is
inside measurement/aim noise; you cannot tell "X4 checks the origin" apart from
"X4 checks a hittable point" at that margin.

**(b) The arc limit coincides with own-hull occlusion — the core issue.** A
top-mounted turret's −10° lower limit *is* the deck/hull plane. The arc limit
**exists to stop the turret firing into its own hull.** So "origin below −10°
(outside the arc)" is the *same physical region* as "behind the hull (line of
fire blocked)." You can never simultaneously get **origin-outside + aim-inside +
clear line of fire** on such a turret. Confirmed twice:
- r11: the single same-component pair that crossed −10° had its external line of
  fire blocked.
- r15: the qualified candidate's origin (−10.02°) is below the deck plane; the
  engine reported `engageable=0`, and (owner-observed) the shot is own-hull
  blocked.

So the ring returns `engageable=0` no matter which hull it runs on — not because
of coordinates, but because the experiment's premise (origin out, aim in, shot
clear) is geometrically impossible on a hull-protective arc.

## 5. The question that must be answered BEFORE building any fixture

**Does a turret exist whose arc limit is NOT coincident with own-hull
occlusion** — i.e. where just beyond the swivel limit is *open space*, not hull?

Candidates to investigate: turrets on a hull **edge, corner, sponson, or mast**,
where the mechanical gimbal stop is reached *before* the hull would block, or
where the limit faces outboard over the hull edge into open space.

- **If YES:** build the Goal-1 fixture on that turret (requirements in §6).
- **If NO** (arc limits are always authored to be hull-protective): **Goal 1 is
  moot.** It doesn't matter whether X4 checks the origin or a hittable point,
  because anything outside the arc is hull-blocked anyway — so the mod's
  origin-based ENGAGEABLE check is already safe. Close the arc branch with that
  conclusion and record it; no production change.

This is a **research task first**, not a fixture task. Answer it from extracted
turret/hull geometry plus the mount/limit telemetry the fixture already logs,
before spending another live run.

## 6. Requirements for a valid Goal-1 fixture (only if §5 finds a decoupled turret)

1. **Decoupled turret:** its relevant arc limit must have open space beyond it,
   so an out-of-arc direction is not automatically hull-blocked.
2. **Meaningful angular gap:** the target component's origin must be outside the
   limit and a hittable aim-point inside it by a **whole-degree** margin (≥ ~1°),
   not hundredths of a degree. That likely needs a physically large or nearer
   target element, not a small distant one.
3. **Genuinely clear line of fire** to the in-arc aim-point — verified by the
   turret actually being able to point there, not just `muzzle_los_ex=1`.
4. **Same component** qualified and designated (issue rule); keep the arc and
   line-of-fire branches independent so CANNOT BEAR is never confused with LINE
   OF FIRE BLOCKED.

## 7. Current working-tree state and recommendation

The r15 Colossus arc-survey rebuild is uncommitted in the working tree
(`scenario_spec.lua` id `issue-67-colossus-arc-survey-r15`, matching MD, census
guards, tests, `tests/test_issue67_arc_ring.sh`, plus skill + KB updates). It is
**known-flawed for Goal 1** per §4.

Keep vs. scrap:
- **Keep** (independent of the flawed ring): the spawn-skill hardening against
  singular `<turret>` mounting; the KB singular-turret finding; the reasoning
  that the `excludeself="false"` self-inclusive ray is always-blocked telemetry.
- **Scrap or shelve** the r15 arc-survey ring fixture itself. Last committed
  clean state is r11 (`78d3b95`), which holds the good conventional-masking
  result. Decide: revert the fixture to r11, or leave r15 in place `enabled =
  false` while §5 is researched.

## 8. Pointers

- Fixture spec: `testlab/x4_gunnery_control_testlab/ui/scenario_spec.lua`
- Qualifier MD: `testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_scenario.xml` (cue `GeometryQualifyMeasure`)
- Arc math + gate check: `tests/test_issue67_arc_ring.sh`
- Live telemetry tags: `[X4GC TEST QUALIFY SURFACE]` (per weapon×element: origin_pitch, aim_pitch, muzzle_los_ex/self, arc_split); `[X4GC TEST SOLUTION]` (mount_yaw/pitch/roll, barrel_x/y/z, rel_pitch, aim_pitch)
- Spawn skill: `.agents/skills/spawn-gunnery-scenario/SKILL.md`
- KB: `.agents/skills/research-x4-modding/references/md-ai.md`
- Platform constraint: **Colossus E only** (`ship_arg_xl_carrier_02_a_macro`);
  the Behemoth E has no gunner console (#68).
