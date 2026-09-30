# A2 offline three-ray geometry study

Scope: [Issue #176 A2](https://github.com/radlinsky/x4-gunnery-control/issues/176),
geometry only. All conclusions are **inference**, experimental surrogate evidence
for X4 9.00 build 611726. No X4 launch, production change, or ENGAGEABLE scoring.
The frozen P3c files and results are neither edited nor regenerated.

From the repository root, with Python 3 and NumPy:

```sh
python3 research/issue176-a2/simulate.py
python3 research/issue176-a2/report.py
```

Inputs: the existing ignored `issue167-p3c/corpus.pkl` (270 records, 38
macro-weighted pairs), and `issue172/cases.jsonl`, both beneath
`.x4-research-cache/`. Only load trusted local pickle files. If the latter is
absent, the script reconstructs exactly the 74 failures from the frozen study's
2,581,596 official trials; this is slower, not a substitute population. If the
corpus is absent, follow the P3c README's census prerequisites and command.
The script asserts 15 multi-point components and the 14/60 historical split,
and independently reproduces all 74 original failures before using their O.
Historical A/B positions are not used as the new candidate's lateral probes.

All output stays in ignored `.x4-research-cache/issue176-a2/`: compressed full
trials, summary slices, component inventory, diagnostic representatives, and
numerical audit. `report.py` verifies the complete output's query bound,
direction-error allowance, and same-selection reconstruction envelopes. No
permanent CI test encodes this temporary experiment's population.

## Sampling and observation model

- Ordinary: 15 unique components × 24 Fibonacci approach directions × five
  centre-distance scales (10, 100, 1,000, 10,000, 100,000 m) = 1,800 samples.
- Boundary: all 38 historical macro-weighted pairs × five scales × eight
  bisector azimuths × three normal offsets (−.01, 0, +.01 times scale) = 4,560.
  Other aim points may win; a pair bisector is not necessarily a Voronoi face.
- Known #172: 74 exact original origins, 14 ordinary and 60 adversarial.
- Synthetic: ten purposeful cases, described in the findings.

Ordinary/boundary samples cycle through identity and two oblique target
orientations (X/Z rotations .37 and 1.13 radians), rotating both origin and aim
points and rounding to binary32. This samples coordinate sensitivity without
claiming exhaustive coverage. Known cases retain their original coordinates.
Distances are generic rough centre scales, not the hidden selected-point range;
the simulator additionally multiplies estimates by .5, 1 and 2. A production
source for that rough scale remains outside this experiment. Origins are
prospective-muzzle inputs; no turret pose/arc model is invoked.

`study.Q` supplies the unchanged binary32 nearest-point selector and quantized
yaw/pitch direction surrogate (`q = 2^-18` radians). Authored identity is logged
only as research truth. No target names, boxes, selected point coordinates,
or identity enter `consensus`. The candidate layout uses O's observed direction
and rough distance only. Synthetic false-point witnesses are deliberately
constructed against each layout's spacing; they are feasibility counterexamples,
not independent random samples or gameplay frequency estimates.

## Candidate contract

A deterministic least-aligned Cartesian axis defines an orthonormal lateral
basis perpendicular to O's ray. A is one baseline away; B is the same distance
away at 60°, 90°, or 120°. O/A/B are non-collinear. Spacing is
`clamp(slope * rough_distance, minimum, maximum)`; all rules are in `RULES`.
No box is consulted.

For each of O/A, O/B, A/B, compute the two closest forward ray points and their
midpoint. Require finite inputs/results, positive distances, resolved angular
separation, bounded miss, and agreement of all three midpoint estimates.
Return the estimate with the tightest uncertainty envelope, checking its forward
projection and distance to all three observed rays too.

Numerical allowance:

- Binary32 unit roundoff `u = 2^-24`; yaw/pitch rounding gives angular allowance
  `q / sqrt(2)`, plus `8u` for the short binary32 direction arithmetic chain.
  This is a conservative surrogate model, not a proven engine error bound.
- `epsilon = q/sqrt(2) + 8u`; coordinate allowance
  `rho = 2u * max(1, absolute probe coordinates, absolute reconstructed point)`.
- For pair forward distances s/t and ray angle sine k, miss allowance is
  `T = 2rho + epsilon * (abs(s) + abs(t))`; positional envelope is `E = T/k`.
- Reject `k < 2epsilon/.01` or `E > .01 * max(abs(s),abs(t))`.
  One-percent distance resolution is the declared experimental usefulness
  threshold. This does not establish the accuracy needed for #173's scorer.
- Pair midpoint separation must be at most the sum of their envelopes. There
  is no hidden identity test or unexplained fixed metre consensus threshold.

`report.py` measures direction error against exact selected-point directions
and checks accepted same-selection error against E. This validates the allowance
on the sampled corpus only. Large translated coordinate frames, engine-native
precision, temporal motion, and different quantization need further validation.
Failure flags overlap; the exclusive primary status precedence is invalid,
forward, conditioning, miss, disagreement. Do not mistake zero *primary*
disagreement counts for absence of pair disagreement.

## Fourth observation experiment

After a failed valid triple, take exactly one more observation along the lateral
basis diagonal. For conditioning-only failure, quadruple spacing up to the cap;
otherwise quarter it down to the floor. Try O/A/C, then O/B/C, retaining the
first passing triple. O is always anchored, and each accepted triple still
checks all its pairs. The discarded failed observation is not required to agree;
this is recovery of an anchored subset, not four-ray consensus. There is no
retry loop. Query counts are three or four, including invalid synthetic inputs.
This policy is experimental; findings decide whether its recovery is useful.

False consensus is a passing mixed-selection triple whose reconstruction error
against O's selected research point exceeds its propagated envelope. Report all
mixed selections separately, including mixed passes inside that envelope.
Same-selection envelope misses are separately counted as wrong, and the audit
asserts none. No classification calls the old inferred pitch/arc scorer.
