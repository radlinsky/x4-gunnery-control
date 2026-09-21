# CANNOT BEAR exact-point benchmark (Issue #185 C2)

This research-only benchmark asks one question: can the selected turret
mechanically aim at the supplied exact aim point? It imports the accepted
288-turret corpus and truth scorer from `research/issue176-a4x/` directly.

Build the accepted corpus if its ignored cache is not already present, then run:

```sh
python3 research/issue176-a4x/corpus.py
python3 research/issue185-c2/benchmark.py
```

Every turret receives the same eight explicit component-frame points. Two
normal points cover straightforward forward and oblique bearings. Five
difficult points cover the four component axes and astern, exposing pitch
poles, exact 90-degree limits, bounded traverse, reversed axes, and rotation-Z
without tailoring a point to a turret. The component origin is stress-only: it
deliberately exercises degenerate/pivot and hidden-rest handling without
distorting the supported-case report. This 2,304-case cross product is the
smallest set retained after checking that it produces both accepted decisions,
naturally occurring `UNKNOWN`, and distinct results for every unusual layout.

The script writes raw reproducible rows to the ignored
`.x4-research-cache/issue185-c2/benchmark.jsonl.gz` and the concise tracked
result to `findings.md`. Each row retains turret/source/layout/category, the
supplied exact point, scorer state, and the C1 result. It fails on corpus-count
drift, missing coverage, invalid results, or a turret without all eight cases.

No point is discovered, reconstructed, probed, varied, or selected from turret
behavior. The benchmark does not model aim-point uncertainty, range, firing
solution, line of fire, firing permission, weapon readiness, projectile
behavior, or final ENGAGEABLE. Evidence is offline inference only.
