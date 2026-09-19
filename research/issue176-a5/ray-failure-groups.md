# A5 ray-method failure groups on accepted A4x — 2026-09-18

Scope: [Issue #176](https://github.com/radlinsky/x4-gunnery-control/issues/176)
A5, turrets with known geometry only. Offline, status **inference**. Reads the
accepted A4x rows (`.x4-research-cache/issue176-a4x/trials.jsonl.gz`, scorer
`4dafbf0`) unchanged. No X4 launch, no production change. Range, line of fire,
firing solution, readiness and authorization are out of scope. Unknown-turret
limits are closed (accepted `25637fd`, `bc43f7b`) and not revisited.

```sh
python3 research/issue176-a5/ray_failure_groups.py
```

Counts below are factor 1, truth-known, `feasible_realistic` unless stated.
Synthetic stress is reported separately because it is built to break methods.

## Answer

**Largest correctable group: same-ray `bracket_disagree`, 359 rows.** The
ladder brackets the aim-point distance only to about 2× (for example
`[100, 213] m`), and the turret's pitch limit is crossed inside that bracket.
The two ends score differently, so same-ray returns UNKNOWN. The truth is
decided in every one of these rows (the A5 same-ray audit found one real
transition inside each bracket, at a pitch limit).

The fix is to find the distance more precisely **on the same anchor ray**.
Moving the query origin sideways (triangulation) does not remove the part of
this group that is still failing.

## Why it happens

Same-ray asks "is the aim point still ahead?" from 0.5×, 1× and 2× the rough
distance. That gives a bracket, never a distance. Close to a big target, the
elevation the turret needs changes quickly with distance, so a 2× bracket often
contains a pitch-limit crossing. Same-ray then cannot tell which side the true
point is on and says UNKNOWN. This is conservative and correct, but it is a
coverage loss we can fix: the limit crossing is at one distance, and the true
point is decidedly on one side of it.

## Which methods it affects

| method | effect on the 359 rows |
|---|---|
| `same_ray` | all 359 UNKNOWN |
| `three_ray4` (displaced-origin triangulation) | recovers 280 (`pass`, correct). Fails on **79** with status `forward` and **mixed selections** in all 79: the sideways origins pick a different aim point on 2–4-point targets (Paranid L expeditionary, Xenon XL mothership, Argon L destroyer), so the rays do not meet ahead |
| `direction` | scores the far point, not P, so it is wrong whenever the near-point answer differs |
| chain `three_ray4 > same_ray > direction` | the realistic residual is **15 rows, every one from these 79**: 9 false NOT ENGAGEABLE, 1 UNKNOWN, and **5 decided false ENGAGEABLE** from the direction fallback |

The remaining 79 split across 44 scenarios and 38 turrets (73 SWI, 6 official).
**On the anchor ray, 76 of the 79 read no aim-point switch.** Queries along the
ray keep the selected point, while sideways queries lose it. This is the
important result for displaced-origin triangulation. A three_ray-style
triangulation is already benchmarked. It already recovers what it can recover,
and it fails on exactly this remainder, because moving the origin sideways
changes which aim point the selector picks. More lateral origins would not help
these rows. Smaller lateral spacing might, but it gets worse conditioning
(A2 `conditioning`) and is a second-order option.

Other same-ray groups, for ranking:

- `no_lower_bound` 36 (factor 1). Rough overestimate. three_ray4 passes 30 of
  them. At factor 2 this is 11,807 rows, but factor 2 is a stress construct
  (same-ray audit, bucket 4), not a gameplay frequency.
- Decided wrong, 2 rows. `13132:22` is the known open-bracket flip-back
  (`[20, 1e9]`). **`2979:99` is wrong with a closed bracket, `[50, 106] m`.**
  So in A4x a 2×-wide closed bracket can also flip back. Agreeing ends are not
  proof for a coarse bracket of either kind. This keeps the accepted open-bracket
  result and extends it.
- Synthetic stress: `no_lower_bound` 560 and `invalid` 277 (no anchor
  direction). These come from the stress construction, not correctable ray
  quality. They are not prioritised.

## Smallest improvement worth benchmarking

**`same_ray_refine`: the same anchor-ray query, bracket narrowed adaptively.**
The CANNOT BEAR contract does not change: a narrow bracket whose ends agree
decides the answer, and anything else is UNKNOWN.

1. Run the existing 0.5/1/2 ladder unchanged.
2. If the bracket is open (all forward), double outward until a probe reads
   non-forward. That always happens past P.
3. If there is no lower bound, halve inward until a probe reads forward.
4. Bisect the bracket (geometric midpoint) until `hi/lo − 1 ≤ w`, or until the
   query budget `N` runs out.
5. Score both ends. Decide only if they agree **and** `hi/lo − 1 ≤ w`.
   Otherwise return UNKNOWN. This drops "open or coarse agreement decides",
   which both 13132:22 and 2979:99 show is unsafe.

Every query stays on the ray through P. It uses the same forward/non-forward
classification and slack upper bound already accepted in same-ray. Runtime
evidence: an anchor-ray origin is the same unproven offset-origin
`useaimtarget` primitive that same-ray already assumes
(`runtime-aim-query-survey.md` §1a). It adds nothing new to prove live.

## Focused benchmark to run next

Offline, on the accepted A4x cases, scorer and rows. No corpus or scenario
change.

- **Rows:** all 113,490 rows. The report focuses on (a) the 359
  `bracket_disagree` realistic rows at factor 1, split into three_ray4 `pass`
  (280) and `forward` (79); (b) the 2 decided-wrong rows; (c) factors 0.5 and 2
  as sensitivity.
- **Methods:** `same_ray` (control), `same_ray_refine` with `w ∈ {0.1, 0.01,
  0.001}` × `N ∈ {6, 8, 12, 16}`. Also the chain `three_ray4 > same_ray_refine
  > direction` and the same chain with `direction` removed.
- **Primary metrics:** decided false ENGAGEABLE must be 0 on realistic rows,
  with each non-zero listed by case. Also: rows recovered among the 79 and the
  359, residual chain false ENGAGEABLE (currently 5), and mean and max queries.
- **Safety screen:** for every decided `same_ray_refine` row, densely scan
  the final bracket with the same-ray audit's scan (log-spaced, bisect label
  changes to 1e-7 relative) and report any interior label change. This is the
  flip-back check. It chooses `w`.
- **Switch check:** count refinement probes that read `switched`/`reversed`
  before the upper bound, and hidden switches (the same-ray audit's bucket 8
  definition).
- **Pass bar for going further:** 0 decided false ENGAGEABLE, 0 interior flips
  at the chosen `w`, and most of the 79 recovered within `N ≤ 12`.

Not included: lateral-spacing sweeps for three_ray4, and any runtime check.
