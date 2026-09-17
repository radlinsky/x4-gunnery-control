# A4 initial ENGAGEABLE diagnostic comparison

Scope: [Issue #176 A4](https://github.com/radlinsky/x4-gunnery-control/issues/176).
Offline surrogate evidence for X4 9.00 build 611726, status **inference**. No X4
launch and no production change. This is a raw diagnostic run: it does not rank
models, choose a winner or say what error is acceptable. A5 audits the failure
groups before anyone uses these numbers.

From the repository root, with Python 3 and NumPy:

```sh
python3 research/issue176-a4/compare.py      # ~12 min, 4 niced workers (Pool(4))
python3 research/issue176-a4/report.py       # tables, failure groups, metrics.json
python3 research/issue176-a4/compare.py 50   # pilot: every 50th case
```

Inputs are the same as A2: the ignored `issue167-p3c/corpus.pkl` and
`issue172/cases.jsonl` under `.x4-research-cache/`. Load only trusted local
pickles. Outputs stay in the ignored `.x4-research-cache/issue176-a4/`:
`trials.jsonl.gz`, with one row per case and rough-distance factor, and
`metrics.json`.

## What is reused

- The query surrogate is P3c `study.Q`: the binary32 nearest-aimtarget selector
  plus quantized yaw/pitch (`q = 2^-18`).
- Truth and every prediction are scored by the accepted #173 scorer,
  `study.geometry`, through final scorer SHA `a72cf7e`. `IN_ARC` counts as YES,
  `OUT_OF_ARC` as NO, and any `UNKNOWN_*` state (a trap, or no resting yaw) as
  UNKNOWN.
- The truth point is the aim point that the selector picks from the case origin
  O. The scorer places the turret component origin at O. Turret and rotation
  cycle as in P3c: turret `i % 92`, axis rotation `(i // 92) % 24`.
- The A2 corpus (`simulate.corpus`), the medium three-ray rule
  (`.03 × rough`, 1–128 m, 90°) and `simulate.consensus` are used unchanged.
  So are the A2 rough-distance multipliers of .5, 1 and 2.

## Populations

| Population | Subgroup | Cases | Construction |
|---|---|---:|---|
| normal | single-point | 6,990 | All 233 single-aimpoint ship/surface components × 6 Fibonacci directions × radii 10, 100, 1,000, 10,000 and 100,000 m from the macro box centre. The rough distance is that centre distance, not the aim-point distance. |
| normal | multi-point | 1,800 | A2 ordinary: the 15 multi-aimpoint components. |
| difficult | boundary | 4,560 | A2 boundary: origins placed on pair bisectors, where the selector switches. |
| difficult | known172 | 74 | The historical #172 switch failures (14 ordinary and 60 adversarial by origin), kept together because they were selected by failure. |
| stress | synthetic | 11 × 92 turrets | A2's ten synthetic cases, plus `collinear_replacement`. Each is scored against every turret. |

`collinear_replacement` has aim points at 60 m and 130 m on one ray from O,
with a rough distance of 100 m. The same-ray probe at 100 m selects the second
point, which lies straight ahead, so the switch cannot be seen. Exact
collinearity with the attacker is measure-zero, so the case is stress only.

Truth-UNKNOWN rows are excluded from TP/FP/TN/FN and from the derived rates.

## Methods

Every method starts from the anchor query `d0 = Q(O)`. An invalid anchor makes
every method UNKNOWN at a cost of one query.

- **direction**: direction-only, the known weak baseline. It scores the point
  `O + 1e9 m · d0`, which is the "infinitely far" reading of the direction.
  Cost: 1 query.
- **three_ray**: the A2 medium triple. A pass scores the consensus point; any
  other status is UNKNOWN. Cost: 3 queries.
- **three_ray4**: `three_ray`, plus the one inward fourth probe retained in A2,
  after a failed valid triple. The probe sits on the lateral diagonal at
  `max(1 m, spacing / 4)`. Triples O/A/C and then O/B/C are tried, and the first
  pass is scored. A2's outward conditioning branch is not retained: when A2's
  `run` takes that branch, the fourth query is redone inward. Cost: 3 or 4
  queries.
- **same_ray**: the new bounded same-ray bracket, described below. Cost: 4
  queries.

### Same-ray bracket contract

The nearest-point cell of the selected aim point P is convex and contains both
O and P. Every point on the segment from O to P therefore selects P, so a probe
placed short of P on the anchor ray returns `d0` again. A probe can select
another aim point only after it passes P. This holds in exact arithmetic; binary32
ties and probe-origin rounding are the only exceptions. A forward probe therefore proves the
distance is beyond the probe, and a non-forward probe proves the probe has
overshot. That is the whole information content of same-ray queries: they
bracket the unknown distance λ but do not measure it.

1. Issue exactly three probes, non-adaptively, at `U_m = F32(O + m · r · d0)`
   for `m ∈ {1/2, 1, 2}`. Here r is the rough distance, the same input the
   three-ray spacing uses. There are no retries, no search and no branching;
   the hard maximum is 4 queries.
2. Classify each probe:
   - **forward**: `d · d0 > 0` and `|d × d0| ≤ 1e-4 rad`.
   - **reversed**: `d · d0 < 0` within the same tolerance.
   - **switched**: any other direction.
   - **at_point**: the direction is undefined.

   Only forward counts as "not yet reached".
3. The forward flags must form a prefix, such as F F N. Any other pattern, such
   as F N F, returns **UNKNOWN (inconsistent)**. A forward probe after an
   overshoot shows that a replacement point was selected.
4. If no probe is forward, return **UNKNOWN (no lower bound)**.
5. Build the bracket.
   - The lower end is the distance of the last forward probe.
   - The upper end is the first non-forward probe's distance times
     `1 + 2(ε + ρ/s)/1e-4`. Here ε is A2's per-query angular allowance and ρ is
     A2's coordinate rounding allowance. The widening exists because a probe
     just short of P sees the anchor's quantization as a large angle, which can
     read as non-forward.
   - If every probe is forward, the upper end is the far point.
6. Score both bracket ends with the accepted scorer. If both give the same
   known answer, return it. Otherwise return **UNKNOWN (bracket disagree)**.
   This assumes the answer does not change inside the bracket and flip back.
   That assumption is not proven and is an A5 audit item.

Diagnostics recorded per row:

- `probes`: the scale, class and selected identity of each probe;
- `probe_switch`: some probe selected a different aim point;
- `hidden_switch`: a switched probe still read as forward;
- `bracket_holds`: the true distance is inside the bracket.

A wrong bracket is not by itself a prediction error. Only the final answer is
scored.

## Stacks and metrics

A stack tries its methods in order and returns the first non-UNKNOWN answer.
The anchor query is shared, so each fallback that is actually used adds its
query count minus one. Direction-only fallback therefore costs nothing extra.
`report.py` builds the stacks from the per-method answers:

- `three_ray > same_ray`
- `three_ray4 > same_ray`
- `same_ray > three_ray4`
- `three_ray4 > direction`
- `same_ray > direction`
- `three_ray4 > same_ray > direction`

The reported counts are player-view: an UNKNOWN prediction is shown as
NOT ENGAGEABLE.

- TP, FP, TN and FN are counted over truth-known rows only, with UNKNOWN
  predictions folded into TN or FN.
- `unknown_on_yes` and `unknown_on_no` give the UNKNOWN share of FN and TN.
- `model_unknown` counts every UNKNOWN prediction, including those on
  truth-UNKNOWN rows.
- Coverage is decided / truth-known.
- `decided_accuracy` is the accuracy over decided rows only.
- Query columns give the mean and maximum per row for the whole stack.
