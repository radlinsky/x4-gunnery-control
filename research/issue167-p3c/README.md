# Issue #167 P3c approximation-rate study

Offline research harness for the frozen P3c contract in
https://github.com/radlinsky/x4-gunnery-control/issues/167#issuecomment-5685758987
(AABB-assisted near-target triangulation). Research only: not loaded by the mod,
not a production dependency. Rates are surrogate-precision rates, not bit-exact
X4 rates.

Inputs (ignored, never committed): official X4 9.00 XML source sets in
`.x4-research-cache/official-source-sets/` and ANI resources in
`.x4-research-cache/issue72-a2-ani-resources/`. All outputs go to
`.x4-research-cache/issue167-p3c/`.

Run from the repository root:

```sh
python3 research/issue167-p3c/sources.py   # prints the five LIVE discriminator boxes
cd research/issue167-p3c
python3 census.py                          # asserts corpus counts, writes corpus.pkl
python3 study.py                           # all 2,585,916 trials, one process per core (~4 h on 24 cores)
python3 report.py                          # rate tables + invariants
python3 report.py result.pkl --inspect     # first three trial IDs per bucket
```

`python3 study.py N` runs only the first N 2,000-trial chunks, as a pilot.

- `sources.py`: source index and `macro.boundingbox` reconstruction (half-extents,
  origin inclusion, collision filtering with referenced-connection tags, recursive
  child macros).
- `census.py`: aim-target records in native hash order, macro-weighted pairs,
  and the 92 chain turrets' geometry and arc limits.
- `study.py`: frozen algorithm, direction-query surrogate, scoring, and the
  conditional yaw-gate/pitch-arc decision.
- `report.py`: tables, invariants, inspection.

The pitch-arc half of the decision uses the joint inverse of the #166 split
(`T = L∘Rx(-x)∘G∘Ry(y)∘H`) at the gate's resting yaw. That is an inference,
not the decoded X4 pitch solver.
