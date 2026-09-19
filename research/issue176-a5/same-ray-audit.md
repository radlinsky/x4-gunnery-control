# A5 same-ray audit: buckets 2, 3, 4 and 8 — 2026-09-17

Scope: [Issue #176](https://github.com/radlinsky/x4-gunnery-control/issues/176)
A5 buckets 2, 3, 4 and 8, audited together. Offline surrogate evidence for X4
9.00 build 611726, status **inference** unless a line says otherwise. No X4
launch, no production change, no model ranking.

Starts from accepted A4 at `5117efe`. A4 code and raw rows are unchanged; this
audit only reads `.x4-research-cache/issue176-a4/trials.jsonl.gz` and rebuilds
each case with the same A4 inputs. Reproduce with (~16 min, 4 niced workers):

```sh
python3 research/issue176-a5/same_ray_audit.py
```

"Scan" below means scoring the #173 scorer at points `O + t·d0` on the anchor
ray, log-spaced, with each label change bisected to 1e-7 relative. A scan can
miss an island narrower than its grid.

## Summary

| Bucket | Cause | Class | Correction before comparison |
|---|---|---|---|
| 2 `bracket_disagree` | One real ENGAGEABLE transition inside the bracket, almost always where required elevation crosses an authored pitch limit | real supported-model limitation (bracket resolution); conservative | No. Report as model UNKNOWN |
| 3 decided false ENGAGEABLE | All three probes forward, so the "bracket" is `[2×rough, ∞)`. Elevation crosses the limit and comes back inside it | wrong model assumption (no flip-back inside an open bracket) | Yes. Open-ended agreement is unsound |
| 4 rough-distance dependence | The 0.5× probe overshoots once rough ≥ ~1.88× the aim-point distance; an underestimate creates the open brackets of bucket 3 | real limitation; the factors and the centre reference are test constructs | Yes. Stop reading factor coverage as gameplay frequency |
| 8 hidden switch | Probe 50–75 km short picks a neighbour 4.13 m away at the same depth; 5.4–8.4e-5 rad < 1e-4 | numerical/selector-boundary mechanism, harmless in supported geometry; collinear case is a real but tiny-measure limitation | No |

## Bucket 3 — the two decided false ENGAGEABLE rows

Both rows are exact A4 rows, rebuilt with the A4 body origin and anchor ray.
The on-ray point at the true distance lies 6.8e-5 m and 4.6e-4 m from the
selected aim point and scores the same as the truth point, so this is not a
reconstruction slip.

**Normal, case 10719:** `ship_xen_m_fighter_01` (1 aim point) ×
`turret_spl_l_plasma_01_mk1_macro`, rotation 20, arc −5°…80°, reference
muzzle offset 60.94 m. Rough 10 m, selected aim point 37.477 m away. Wrong at
factors 0.5 and 1.

- Probes at 5/10/20 m are all `forward` with the same aim point, and the
  bracket is `[20, 1e9]`. It holds, and no probe switched.
- Truth is OUT_OF_ARC: one resting yaw −21.23°, pitch −6.1517°, 1.15° below
  the limit. Ends: 20 m YES (pitch −1.70°), 1e9 m YES (pitch −4.38°).
- Scan over 0.5 m…1e9 m: YES → **NO at 34.416 m** → **YES at 412.42 m**. Both
  transitions sit on the −5° limit (−5.0000 / −5.0001), with one resting yaw
  throughout. No UNKNOWN, no yaw-solution change, no aim-point switch.

**Difficult, case 1815:** `engine_xen_xl_mothership_01_allround_mk1` (4 aim
points, anchor 2) × `turret_tel_m_laser_01_mk1_macro`, rotation 19, arc
−10°…89°, muzzle offset 5.18 m. Rough 10 m, aim point 207.372 m away. Wrong
at every factor.

- Probes are all `forward` on aim point 2. The brackets are `[10|20|40, 1e9]`
  and all hold. No switch.
- Truth is OUT_OF_ARC: one yaw −151.73°, pitch 89.484°, 0.48° above the limit.
  Ends are YES (76.85° at 20 m, 88.05° at 1e9 m).
- Scan: YES → **NO at 105.19 m** → **YES at 316.77 m** on the 89° limit, plus a
  0.23 m `UNKNOWN_one_trap` island at 694.9 m.

Why: the scorer aims from the turret's pivot, not from the muzzle O. As the
point moves out along the muzzle ray, the resting yaw swings (−4° to −172°
in 10719), which moves the pitch pivot. Required elevation along the ray
therefore does not change monotonically: it passes the limit and comes back.
Both brackets are correct and contain the truth. The two end scores agree
because the out-of-arc stretch lies strictly inside `[2×rough, ∞)`.

This proves the "ends agree ⇒ whole bracket agrees" assumption false for
open-ended brackets. It is not float noise: the truth is 0.48–1.15° outside
the arc, while the scorer's limit comparison rounds to 1e-4°. Both origins are
10 m from a reference centre with the aim point 37–207 m away. Whether that
geometry is plausible in combat is bucket 1's question and is not decided here.

## Bucket 2 — `bracket_disagree` (factor 1: 115 normal, 38 difficult)

Every row was scanned across its own bracket: 150 samples when closed, 400
when open.

- 152 of 153 rows have exactly one transition at scan resolution. The
  remaining row (12699) is UNKNOWN_none_trap at both ends, and its truth is
  UNKNOWN.
- Mechanisms: 134 at the lower pitch limit, 10 at the upper pitch limit, and 8
  at a scorer `UNKNOWN_none_trap` boundary (bucket 10's population). There is
  **no yaw-solution change and no aim-point switch** among them. The 4 rows
  with a probe switch read it as non-forward, which supplied the upper bound,
  and their brackets still hold.
- Every bracket contains the true distance, and the truth always lies on the
  side of the transition the scan predicts.
- Close range dominates: 130 of 153 rows are at 10 m. 46 of the 153 brackets
  are open (all-forward). At >10 m the bracket spans 50–106 m or 100–213 m and
  the truth sits near a real limit crossing.

Flip-back screen inside closed brackets that agree: 3,643 factor-1 rows at
10/100 m, 24 samples each. None flips YES↔NO↔YES. Three rows at 10 m (9248,
10444, 12427) change and change back only through thin `UNKNOWN_none_trap`
islands, and none of them changes a decided truth-known answer. Row 12427 has
UNKNOWN truth.

Disposition: correct, conservative UNKNOWN. The bracket (≥2× wide) cannot
resolve a real limit crossing. **Real supported-model limitation.** No
correction needed.

## Bucket 4 — rough-distance dependence

The A4 rough distance is a test construct. It is the distance from O to the
macro box centre (single-point), to the aim-point mean (multi-point), to the
pair midpoint (boundary), or the #172 trial radius. It is not the aim-point
distance. At factor 1, aim-point distance / rough is:

- about 1 from 10 km up (e.g. single-point 10 km: 0.98–1.021, 47% below 1);
  mostly near 1 at 1 km, with outliers down to 0.21 (multi-point) and 0.13
  (boundary);
- widely spread at 10 m. Single-point runs 0.39–25.6, and multi-point and
  boundary medians are 15.1 and 15.6. At 10 m the aim point is often much
  farther than the reference centre.

Where the first probe (0.5 × factor × rough) lands relative to the aim point:

| population, factor | beyond | short by < 6.5% | short |
|---|---:|---:|---:|
| normal 0.5 / 1 / 2 | 1 / 16 / 4,202 | 0 / 2 / 3,245 | 8,789 / 8,772 / 1,343 |
| difficult 0.5 / 1 / 2 | 3 / 15 / 1,057 | 0 / 3 / 1,874 | 4,631 / 4,616 / 1,703 |

At factor 2 the first probe sits at 1× rough, which is about the aim point
itself at range. It lands beyond the point (4,202 normal) or just short. Just
short reads non-forward by design, because the quantization angle
`EPS·s/(D−s)` exceeds 1e-4 inside the up-to-6.4% slack gap (2,773 normal, 1,618
difficult). Both cases leave no lower bound.

Loss by group: every range from 10 km up loses nearly all rows (normal 3,514
of 3,516; boundary 1,818 of 1,824). At 1 km single-point loses 1,346/1,398 and
multi-point 353/360. At 10 m the loss is smaller (single-point 576/1,398,
multi-point 41/360, boundary 68/912) because the aim point there is often well
beyond the reference centre.

Direction of the error matters:

- **Overestimate** of about 1.9× or more gives no lower bound, so the answer is
  UNKNOWN. Safe.
- **Underestimate** makes every probe forward and gives an open bracket, which
  is the source of bucket 3's wrong answers.

At factor 1: 503 normal and 1,110 difficult known-truth rows have open
brackets.

What production can obtain (no X4 launch in this audit):

- `distanceto.{component}` is "Distance to other component", and
  `bboxdistanceto` is box-to-box distance. **shipped-source**,
  `libraries/scriptproperties.xml` 9.00, recorded in
  `.agents/skills/research-x4-modding/references/md-ai.md`. Egosoft notes that
  bboxdistanceto accuracy "depends on which object is bigger".
- `GetDistanceBetween(UniverseID, UniverseID)` is already declared and called
  from `ui/gunnery_control.lua:188,318,1743` with the player ship as the first
  argument. Which reference points it measures (component origins or boxes) is
  **unverified**. There is no KB record, and vanilla Lua is not in the local
  source cache.
- **Inference:** none of these measures from the prospective muzzle to the
  selected aim point. A component-origin distance is off by up to roughly the
  own-ship-to-muzzle offset plus the target-origin-to-aim-point offset. That is
  a small relative error at km range and a large one at ranges comparable to
  ship size. `bboxdistanceto` is at most the centre distance and can be 0 for
  overlapping boxes, so it is biased toward the underestimate that opens
  brackets.
- **design-choice:** the A4 factors 0.5/1/2 are stress multipliers, not
  measured gameplay error. No frequency claim follows from them.

Disposition: a **real limitation**, since the fixed ladder needs rough within
about (0, 1.88)× of the aim-point distance and must be bounded above. The
factor-2 collapse is an **out-of-production test population** for long range.
Production's real bias remains unmeasured.

## Bucket 8 — hidden same-ray aim-point switch

The supported occurrences are all `ship_gen_s_fightingdrone_01`, boundary pairs
18/19/21/22 at 100 km:

- 20 hidden probe readings over factors 0.5 and 1: cases 4057, 4060, 4063,
  4066, 4177, 4192, 4417, 4420, 4423, 4426, 4537, 4552. Each origin appears
  twice because two macros share the component.
- The origin sits on the selector bisector of two aim points 4.134 m apart at
  **equal depth** along the ray. A probe 50–75 km short picks the neighbour
  after float32 position rounding.
- The neighbour's angle from the anchor ray is lateral/range = 5.4e-5–8.4e-5
  rad, below the 1e-4 forward tolerance.
- The anchor aim point is still 50,000–75,000 m ahead of the probe, so the lower
  bound stays true. All brackets hold, and the answers match truth (14 YES,
  6 NO).

Sensitivity: a switch hides when `lateral separation / range to the selected
point < 1e-4` (plus quantization). At 50 km that is a 5 m lateral separation;
at 500 m it is 5 cm. The quantization floor is `EPS ≈ 3.2e-6` rad plus
`2u·|U|/range`.

- Lowering the tolerance to about 1e-5 would expose these drone switches.
- It would also widen the near-point non-forward gap `EPS/tol` from 6.4% to
  64%, costing lower bounds and loosening upper bounds.
- No tolerance above the noise floor exposes an exactly collinear neighbour.

When a hidden switch can break the bracket: the probe must have overshot the
anchor point by δ, and the selected point must be deeper along the ray, closer
to the probe than δ, and within `1e-4 × range` laterally. For aim points Δ
apart along an axis, the muzzle must lie within about `1e-4·R/Δ` rad of that
axis line, e.g. within ~5 cm of it at 1 km for Δ = 100 m and R = 50 m.

- The corpus has axis-collinear aim-point pairs on 12 of 15 multi-point
  components, so this is **possible in supported geometry**.
- It has vanishing solid angle and is not demonstrated by A4's supported rows.
- If it happened, the lower bound would be false, and the answer could change
  only if the wrong bracket spans a limit crossing.

The stress `collinear_replacement` row is the exact-alignment limit of this
case and remains stress-only evidence.

Disposition:

- Drone case: **numerical/selector-boundary mechanism**, harmless.
- Collinear overshoot: **real supported-model limitation of tiny measure**.

No correction needed before comparison.

## Candidate fix A (tested, not adopted)

Candidate A treats an all-forward ladder, which has no upper bound, as UNKNOWN
instead of scoring the far point. Supported rows with known truth:

| factor | normal coverage, decided errors | difficult coverage, decided errors |
|---|---|---|
| 0.5 | 0.982, 1 → 0.7865, 0 | 0.984, 1 → 0.5742, 0 |
| 1 | 0.9853, 1 → 0.9303, 0 | 0.9873, 1 → 0.7533, 0 |
| 2 | 0.2016, 0 → 0.1639, 0 | 0.4184, 1 → 0.243, 0 |

It removes every decided same-ray error in A4's supported populations at a
large coverage cost. No two-point test can certify an open interval: 10719 is
YES at both 20 m and 1e9 m with NO between. So the open bracket must be closed
by another query or rejected; which is the owner's model choice, not this
audit's. A4 numbers are not rewritten.

## Required before later comparison

1. Do not count same-ray `bracket_agree` answers from an open bracket as sound.
   Report them apart or apply candidate A.
2. Do not read factor 0.5/1/2 coverage as gameplay frequency.

## Still unknown

- The rough-distance source production would use, and its real bias against
  aim-point distance. `GetDistanceBetween`'s reference points need
  shipped-source or live evidence.
- Whether a YES↔NO flip-back can occur inside a closed ≤2.13× bracket. The
  mechanism allows it, but none appeared at 24 samples on 10/100 m rows, and
  ≥1 km rows were not screened.
- Whether the 10 m origins are plausible combat geometry (bucket 1).
- The L-class muzzle offsets (47–61 m in the accepted #166/#173 turret data)
  drive the close-range parallax. They were not re-audited here.
