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

Buckets are `cause|yaw class:rest pattern|direction`. The rest pattern is the
oracle's arc result over all resting yaws (`all_in`, `mixed`, `none_in`).

### Before (417e9b0, scorer = one state-independent yaw, no zeroing)

| Population | Agree | Hidden-state (scorer UNKNOWN) | float32-indeterminate | missing zeroing | other buckets |
|---|---|---|---|---|---|
| ordinary | 96,569 | 26 | 5 | 0 | 0 |
| adversarial | 27,031 | 751 | 5,270 | 804 | 0 |
| stress | 331 | 45 | 6 | 2 | full_circle_arc 84, missing_projection_rule 8, pivot_skip 4 |

### After (this commit)

| Population | Agree (one / several all_in / mixed / none_in) | Hidden-state (traps or no rest) | float32-indeterminate | missing zeroing | other buckets |
|---|---|---|---|---|---|
| ordinary | 96,569 + 8 + 0 + 16 = 96,593 | 2 (one+trap) | 5 | 0 | 0 |
| adversarial | 27,694 + 404 + 92 + 109 = 28,299 | 122 (none+trap) | 5,435 | **0** | 0 |
| stress | 333 | 45 (none) | 6 | 0 | full_circle_arc 84, missing_projection_rule 8, pivot_skip 4 |

- **Zeroing.** All 804 real-turret `missing_component_zeroing` disagreements
  and both stress ones are gone. `turret_xen_m_beam_02_mk1_macro` with target
  `(0, 1000, -0.3)` now scores exactly 90.0° IN_ARC and agrees with the oracle.
- **Several yaws.** Every several-rest case agrees: 412 all_in (ENGAGEABLE),
  92 mixed (ENGAGEABLE), 125 none_in (not ENGAGEABLE).
- **False ENGAGEABLE.** No supported (ordinary or adversarial) false ENGAGEABLE
  is outside the float32-indeterminate band.
  - 5,432 adversarial and 5 ordinary cases are within EPS of a limit (max
    1.9e-6 rad), where the accepted 4-dp rule is looser than strict float32.

  - 8 adversarial cases are the native far-limit clamp quirk one ulp inside
    `turret_kha_m_beam_01_mk1_macro`'s upper limit.
  - No non-indeterminate supported counterexample exists, so the 4-dp policy is
    unchanged.
- **Stress.** Stress-only false ENGAGEABLE (full circle 84, pivot skip 4) and
  false NOT ENGAGEABLE (projection rule 8) are documented limits and are not
  implemented.

## Scorer corrections (`study.geometry`)

1. Pitch now zeroes components of `P - C(y)` below `1e-3f·|P - C(y)|` in
   component space before rotating into the pitch frame. The second
   normalization is omitted because `atan2` is scale-invariant.
2. #176 any-solution: when there are no traps, every resting yaw is scored and
   any in-arc rest makes the point IN_ARC. The result's `yaws` field records
   `one`/`several`. Traps or no rest return `UNKNOWN_<class>[_trap]`.

## Yaw + pitch and several solutions

- Reference geometry (asserted in `yaw_cases`):
  - `several_mixed` (rest −π out, rest 0 in) → IN_ARC;
  - `several_all_in` → IN_ARC;
  - `several_all_out` → OUT_OF_ARC;
  - `one_trap` (rest in arc) → UNKNOWN_one_trap;
  - `none` → UNKNOWN_none_trap.
- `engageable()` is asserted over every permutation of:
  - empty → False;
  - one_in + one_out → True;
  - one_out + failed-status one_in → False;
  - several_mixed + one_out → True;
  - several_all_out + one_out + failed-status several_mixed → False;
  - several_all_out + several_all_in + one_out → True.
  Trap-only and no-rest solution sets are never ENGAGEABLE.
- **One + trap stays conservative.** The gate reference establishes that a trap
  can hold the turret indefinitely from reachable prior states (the
  0.9 rad oscillation example). #176's "bounded hidden yaw alternatives" does
  not say whether a rest that the mover may never reach counts as an accepted
  solution. That is a product decision, not source evidence, so traps (with one
  or several rests) remain UNKNOWN. This affects 2 ordinary cases here.

## Known limits (not corrected, stress-only or indeterminate)

- 1e-4f pitch projection rule: needs a pitch axis parallel to the yaw axis; no corpus turret.
- Target at the pivot: X4 skips the solve; the scorer still scores it.
- Full-circle (−180, 180) arc: X4 wraps it to span 0; no authored arc.
- float32 boundary: the 4-dp rule vs strict float32 compare, and the
  far-limit clamp quirk one ulp inside a limit.
- The degrees→float32 radians conversion, native `atan2`/`fmod` bits, and the
  pitch sign convention inherited from #166 (`turret_xen_xl_battleship_01`,
  reference 18°, arc 18..89) are not re-audited.

## LIVE

No LIVE test is needed. Zeroing is the traced caller code the yaw gate already
uses, and the several-yaw rule is policy over already validated rests. The
optional discriminator is unchanged: a beam_02 turret with a static target 1 km
overhead and 0.3 m aft should settle at yaw 0 / pitch 90° and fire.

## Verdict

**PASS** for supported geometry after this correction. Every remaining supported
disagreement is float32-indeterminate. Stress-only limits and the one+trap
policy question are documented above.
