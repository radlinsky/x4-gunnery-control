# ENGAGEABLE scorer audit (offline)

Scope: `research/issue167-p3c/study.py` `geometry()` / `engageable()` at SHA
7584dd8, X4 9.00 build 611726 (`X4.exe` SHA-256 `19750a65…6ad6891`, verified).
All conclusions are **inference** from a static trace plus offline emulation. No
X4 launch, no production change.

```sh
python3 research/issue173-scorer-audit/audit.py   # ~20 min, 4 niced workers
```

Output goes to `.x4-research-cache/issue173-scorer-audit/result.json` and
includes every disagreement row with its exact inputs.

## Oracle (from the native code, not from `geometry()`)

It reuses only the accepted A9 segments, `joint_matrix`, and the trusted yaw
gate's resting yaws. After that it follows the decoded float32 pitch path:

| Step | RVA | Scorer |
|---|---|---|
| `d = (P - C(y)) / (‖·‖ + 1e-27f)`, zero `|d_i| < 1e-3f`, renormalize | `0x140e22416..60`, `0x140e2123e` | no zeroing |
| solver skipped when all `|d_i| < 1e-4f` | `0x140e2114a` | scores it anyway |
| target angle = reference angle (request 0) when `|u_y|,|u_z| < 1e-4f` | `0x140e21b7c..c2` | `atan2` of raw components |
| `x = fmod(t - ref, 2πf)`, `+2πf` if negative | `0x140e21d1b..44` | `remainder` to ±π |
| limits in float32 rad; skipped when both `< 1e-4f`; inside iff `wrap(x-lo) < wrap(hi-lo)` and `wrap(hi-x) < wrap(hi-lo)`, else clamp to the limit with smaller outward wrap | `0x140e21d49..e0f` | linear 4-dp degree compare |

"In arc" means the clamp leaves `x` unchanged. `EPS = 4·ulp32(2π) ≈ 1.9e-6 rad`
bounds X4's own float32 noise. The scorer's 4-dp window (8.7e-7 rad) falls
inside it.

## Populations and counts

- **ordinary**: all 92 corpus turrets × 1,050 P3c directions (radii cycled) = 96,600.
- **adversarial** (real turrets): each authored limit ± {0, 1e-7, 4e-7, ±4-dp
  edges 6.98e-7/1.05e-6, 2e-6, 1e-5, 1e-4, 5e-4, 9.99e-4, 1.001e-3, 1e-2} rad ×
  4 bearings × 2 ranges = 33,856.
- **stress** (synthetic turrets): pivot, near pivot, vertical, pitch axis parallel
  to the yaw axis, ±π wrap, NaN/inf, asymmetric/negative arcs, and a (-180,180)
  arc = 480.

| Population | Agree | Hidden-state (scorer UNKNOWN) | float32-indeterminate | missing zeroing | other buckets |
|---|---|---|---|---|---|
| ordinary | 96,569 | 26 | 5 | 0 | 0 |
| adversarial | 27,031 | 751 | 5,270 | **804** | 0 |
| stress | 331 | 45 | 6 | 2 | full_circle_arc 84, missing_projection_rule 8, pivot_skip 4 |

Hidden-state breakdown (resting-yaw arc results from the oracle):
- ordinary: several all_in 8, none_in 16; one+trap all_in 1, none_in 1.
- adversarial: several all_in 404, mixed 92, none_in 133; none+trap 122.
- stress: none 45.

In every hidden-state case the scorer returned False. No NaN or inf input
raised or scored ENGAGEABLE.

## Disagreements by cause

1. **Missing component zeroing: current scorer bug (806; 804 on real turrets).**
   All 804 real-turret cases come from the 24 turrets with an upper limit of 90°,
   reference angle 0, and a near-zero pivot offset, with the target inside the
   1e-3 cone around vertical. Zeroing turns the direction into exactly `(0,1,0)`.
   The yaw gate then gives one resting yaw at 0 (state-independent), and X4
   requests exactly 90°, which is in arc. The scorer measures up to ~90.06°
   and returns OUT_OF_ARC. Every case is scorer False and native True: a false
   NOT-ENGAGEABLE, never a false ENGAGEABLE. The ordinary grid has no such case
   because its only vertical direction is exact.
   Smallest real counterexample: `turret_xen_m_beam_02_mk1_macro`, target
   `(0, 1000, -0.3)` in component space (1 km overhead, 30 cm aft). The scorer
   returns OUT_OF_ARC at 90.0173°. The oracle gives yaw 0 and `x = f32(π/2)` = the limit, IN.
   The earlier `issue173-flips` P3c cases on vertical targets are the same mechanism.
   **Correction:** before the pitch `atan2`, normalize `P - C(y)` in component
   space, zero components `< 1e-3f`, and renormalize, exactly as the yaw gate
   already does.
2. **float32-indeterminate (5,281).** `x` lies within EPS of a limit, or a
   component lies within 1e-9 of a threshold. This includes a native quirk: one
   ulp inside the upper limit, the float32 `wrap(x-lo)` can equal the span, and
   X4 then clamps to the far limit (`turret_kha_m_beam_01_mk1_macro`,
   hi − 1e-7). The 5 ordinary cases are exact vertical targets on the beam_02
   family, whose reference angle is −0.0. X4 cannot resolve these reliably
   either, so they are not scorer bugs.
3. **Missing projection rule (8, stress only).** These need the pitch axis
   parallel to the yaw axis (R_G = Rz 90°), and no corpus turret has that. For
   example, `pitchaxis(-60,-5)` with target `(1e-5, 1000, 1e-5)`: the scorer
   says IN, but X4 requests 0 and it is out of arc. **Correction** (for
   completeness): use request 0 when `|u_y|, |u_z| < 1e-4f`.
4. **Pivot skip (4, stress only).** For a target `(0, 1e-30, 0)` at the pivot,
   the scorer says IN_ARC but X4 skips the solve. The correct result is UNKNOWN.
5. **Full-circle arc (84, stress only).** `(-180, 180)` wraps to a span of 0 in
   X4, so everything clamps. No authored arc is like this (all 92 spans are
   <180°).

## Yaw + pitch and several solutions

- Several resting yaws can disagree on pitch arc: reference geometry
  `several_mixed` (rest −π OUT, rest 0 IN), plus 92 adversarial `mixed` cases.
  The #79/#176 "any valid solution" rule applies to *passing target-point
  solutions*, not to hidden yaw alternatives. "Any rest" would be unsound for
  `mixed`, so the scorer's UNKNOWN (False) is the correct conservative result.
- Known conservative UNKNOWN, not a bug: 412 `several` + `all_in` cases (8
  ordinary). Offline mover emulation always settled at one of the resting yaws
  when there was no trap (522/522), so every such rest is in arc and these
  cases could soundly be ENGAGEABLE. That is a possible policy upgrade, not
  something source behavior forces.
- `engageable()` was checked over every permutation of: empty → False;
  valid+valid → True; out + in-but-failed-status → False; only one of three
  engageable → True; several_mixed + several_all_in → False; several + trap +
  none + one in-arc point → True. The result is order-independent in all of
  them.

## Unproven / LIVE

- Authored degrees → float32 radians conversion path, native `atan2`/`fmod` bit
  behavior, and float32 world positions: these only move results inside EPS.
- The sign convention of pitch versus authored limits is inherited from #166
  and was not re-audited. `turret_xen_xl_battleship_01` (reference 18°, arc
  18..89) is the case worth a second look.
- No LIVE test is needed for the correction. The zeroing is the same traced
  caller code the yaw gate already depends on. If one is ever wanted, the
  smallest discriminator is a beam_02 turret with a static target 1 km
  directly overhead, offset 0.3 m aft. X4 should settle at yaw 0 and pitch
  exactly 90° (turret fires), while the current scorer predicts out of arc.

## Verdict

**CORRECTION REQUIRED.** Add the 1e-3f component zeroing before the pitch angle.
The 1e-4f projection rule and pivot skip → UNKNOWN only affect stress geometry.
The error is conservative (false NOT-ENGAGEABLE only) and confined to
near-vertical targets on 90°-limit turrets. It does not affect #176 A4 any
further than that.
