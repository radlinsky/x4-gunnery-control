# Handoff: Issue #69 — generalize the prospective-muzzle LOS via a per-turret geometry table

**Branch:** `feature/issue-69-aim-point-multiplicity`
**Goal:** Replace the single hardcoded turret block in the engageability predicate with a
data-driven, per-macro turret-muzzle geometry table so the "can this turret engage *before
its barrels move*" check works for every articulated turret, not just one Paranid beam.

---

## Why this exists (the problem)

`md/x4_gunnery_control.xml`, cue `EngageabilityCommit`, decides per weapon/target whether a
turret is ENGAGEABLE. Issue #69's live-proven symptom: a large articulated turret (Paranid L
Beam) **fires at and hits the exact designated target component while ENGAGEABLE reports 0/1**
and the MD `check_line_of_sight` returns false.

Root of the disagreement: `check_line_of_sight` uses `weapon.barrelposition`, which is the
turret's **current, articulated** muzzle position. At rest it can be tucked/self-masked by the
turret housing or hull. Once the turret rotates to aim, the muzzle swings to a clear position
and the shot lands. We must predict that **deployed** muzzle position *before* the barrels move.

X4 exposes **no** aimed-muzzle property (tested dead ends: `predictedposition`, `intercept`,
`leadposition`, `aimposition` — none exist on the weapon). The only runtime data is the
articulated `weapon.barrelposition` and the aim bearing from `create_orientation`. MD **cannot**
walk the component bone tree at runtime. Therefore the deployed muzzle must be reconstructed
from **offline-extracted component geometry**, embedded as a per-macro table.

## Current state of the code (3 layers, all in `EngageabilityCommit`, ~lines 198–354)

- **Layer 1 (KEEP):** line ~213 — arc/bearing gate uses `orientation="look_at_bbox"` (aims at
  target bbox, not one sampled hittable point). `common.xsd:2616`. Accepted as an improvement.
- **Layer 2 (KEEP):** lines ~293–314 — bounded surface-element LOS fallback. For a child surface
  element (`$target != $target.defensible`) on a conventional turret, probe 6 interior bbox
  points (2 per axis at 0.25/0.75, others centred) from `weapon.barrelposition`, accept on first
  clear ray. Known caveat: samples are off-centre but the arc gate was computed for bbox-centre,
  so it can over-report on turrets whose sample bearing exceeds arc limits. Acceptable for now.
- **Layer 3 (REPLACE — this task):** lines ~314–349 — hardcoded `do_if $weapon.macro ==
  macro.turret_par_l_beam_01_mk1_macro`. Reconstructs the deployed muzzle via forward kinematics
  `O + Ry(aim yaw) * (P + Rx(-aim pitch) * D)` using constants hardcoded for ONE turret, then
  LOS from that muzzle. **It works and the approach is correct** — it is the single-turret proof.
  It only covers one macro. This is the thing to generalize.

## Key finding: Layer 3's constants are authored component geometry, not fudge factors

Source: `.x4-research-cache/platform-sweep-9.00/assets/props/WeaponSystems/energy/turret_par_l_beam_01_mk1.xml`

| Layer 3 constant | Component source |
|---|---|
| `2.018104m` (yaw origin y) | `Connection01` socket offset, line 16 |
| `y +2.926126, z -16.11956, x -1.730653e-6` | `Connection04` (anim_gun) offset, line 195 — **exact verbatim** |
| `-0.361773…m` | `con_laser` muzzle offset, line 275 |
| `1.877547e-6`, `-1.043081e-5` | real authored micro-offsets (NOT tuning noise) |

The rig chain: `part_socket` (yaw base) → `part_rotator` (yaw, Connection03) →
`anim_gun` (pitch, Connection04) → `anim_barrel` → `con_laser_01/02` (muzzle).

## The hard part: rigs are NOT uniform across turrets

Verified part-name presence:

| turret | parts present |
|---|---|
| `par_l_beam` | socket, rotator, gun, barrel, con_laser |
| `arg_l_beam` | socket, con_laser (no named rotator/gun) |
| `ter_l_laser` | socket, rotator, barrel, con_laser |
| `ter_l_dumbfire` | socket, rotator (no barrel/laser) |

There is no single "read offsets X/Y/Z" rule. The extractor must, per turret, identify: the yaw
pivot part, the pitch pivot part, the rotation axis + sign of each, and the muzzle connection
(`con_laser_*` — multi-barrel turrets have several). This part identification is the real work.

---

## Task

### Step 1 — Offline extractor (start here; this is the go/no-go)
Write a script (Python, standalone, no game deps) that parses turret component `.xml` files and
resolves per macro: `{ yaw_origin (x,y,z), yaw_axis+sign, pitch_pivot (x,y,z), pitch_axis+sign,
muzzle_offset (x,y,z) }` by walking the `<connections>` → parented `<part>` → `<offset><position>`
hierarchy and the `tags="... aimtarget"` / `con_laser` connections.

Component sources (already unpacked, no game needed):
- `.x4-research-cache/extracted/issue69-all-turret-components-9.00/assets/props/WeaponSystems/`
  — **79 turret component xmls** across dumbfire/energy/guided/heavy/mining/standard.
- `.x4-research-cache/platform-sweep-9.00/assets/props/WeaponSystems/` — 35 more.

**Go/no-go deliverable:** report how many of the 79 resolve cleanly vs. need special handling.
Cross-check the extractor's output for `par_l_beam` against the known-good hardcoded constants
in Layer 3 — it MUST reproduce them (socket 2.018104, gun 2.926126/-16.11956, laser -0.361773).
That's the correctness anchor. If the extractor can't reproduce the one turret we've live-proven,
stop and rethink before touching MD.

### Step 2 — Embed the table + generic MD reconstruction
- Emit the table into a form MD can read by `$weapon.macro`. Reuse the existing forward-kinematic
  construction currently in Layer 3 (`create_rotation` pitch/yaw + `transform_position`), driven
  by the table row instead of literals.
- Turrets NOT in the table (modded/unknown, or non-articulated ones whose resting
  `barrelposition` already clears): fall through to Layer 2 / mark UNKNOWN. **Never guess.**
- Delete the hardcoded `turret_par_l_beam_01_mk1_macro` block once the generic path reproduces it.

### Step 3 — Live-validate before trusting fleet-wide
The "reconstructed deployed muzzle == engine's real firing origin" equivalence is proven for
**one** turret. Before shipping, live-test at least `arg_l_beam` + one more family (`ter_l_beam`,
`spl_l_beam`, or `tel_l_beam`) in the Test Lab. Use/extend the existing Issue #69 fixture
(`x4gc_testlab_issue69_paranid_dual_family` in
`testlab/x4_gunnery_control_testlab/libraries/loadouts.xml`) and confirm ENGAGEABLE flips to true
only when the turret actually fires+hits (`hitcomp == aimed`, `istgt=1`).

---

## Guardrails / project conventions (read before editing)
- **MD reload after editing `md/x4_gunnery_control.xml`:** run `scripts/install-dev.sh "<game
  path>"`, then in-game sit at a gunnery console → Test Lab button → **Reload MD**, re-trigger the
  cue. See `docs/RELOADING.md`. The dev launcher re-copies Test Lab from the main repo tree each
  launch — install from the main tree, not a worktree.
- **Bug-fix order:** branch → prove root cause → file/att issue → implement → update KB.
- **No AI attribution in git** (no Co-Authored-By / Claude footers; Caleb is sole author).
- **Delegate implementation edits to sonnet subagents; orchestrate + review in Opus.**
- **`look_at_bbox`** is the arc primitive (`common.xsd:2616`); schema copy at
  `.x4-research-cache/extracted/schemas-9.00/libraries/common.xsd`.
- Do not re-assert #69's *cause* as proven. The durable boundary: MD-LOS/projectile disagreement
  is real and characterized; the reconstruction is a geometry model validated on one turret so far.
- Leave a runnable check behind (the extractor's par_l_beam self-check is the natural one).

## First commands for the fresh session
```
git checkout feature/issue-69-aim-point-multiplicity
sed -n '198,355p' md/x4_gunnery_control.xml      # read the 3 layers
sed -n '1,320p' .x4-research-cache/platform-sweep-9.00/assets/props/WeaponSystems/energy/turret_par_l_beam_01_mk1.xml
ls .x4-research-cache/extracted/issue69-all-turret-components-9.00/assets/props/WeaponSystems/
```
