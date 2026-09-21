# CANNOT BEAR exact-point benchmark (Issue #185 C2)

This research-only benchmark asks one question: can the selected turret
mechanically aim at the supplied exact aim point? It imports the accepted
288-turret corpus and truth scorer from `research/issue176-a4x/` directly.

Build the accepted corpus if its ignored cache is not already present, then run:

```sh
python3 research/issue176-a4x/corpus.py
python3 research/issue185-c2/benchmark.py
```

Every turret receives one normal oblique bearing at 100 m and 8,000 m, plus one
component-origin stress case. For every usable authored joint boundary, the
benchmark uses the accepted geometry to pose the joint 0.1 degrees inside and
outside its limit and supplies an exact point from that joint pivot along the
posed bore at both distances. A boundary is retained only when the scorer
observes a reachable/unreachable transition at one or both distances. This
keeps real per-turret reach limits without restoring the old many-scenario
benchmark.

The script writes raw reproducible rows to the ignored
`.x4-research-cache/issue185-c2/benchmark.jsonl.gz` and the concise tracked
result to `findings.md`. Each row retains turret/source/layout/category, the
supplied exact point, scorer state, and the C1 result. Limit rows also retain
distance, joint/axis, authored limit, edge, and side. The script fails on
corpus-count drift, missing coverage, incomplete limit pairs, or invalid results.

No point is discovered, reconstructed, probed, varied, or selected from turret
behavior. The benchmark does not model aim-point uncertainty, range, firing
solution, line of fire, firing permission, weapon readiness, projectile
behavior, or final ENGAGEABLE. Evidence is offline inference only.
