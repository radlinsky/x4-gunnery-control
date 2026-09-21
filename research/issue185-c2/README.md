# CANNOT BEAR exact-point pilot (Issue #185 C2)

This research-only pilot asks one question: can the selected turret mechanically
aim at the supplied exact aim point? It imports the accepted 288-turret corpus
and mechanical truth scorer from `research/issue176-a4x/` directly. Aim points
are explicit coordinates in the turret component frame.

Build the accepted corpus if its ignored cache is not already present, then run
the pilot:

```sh
python3 research/issue176-a4x/corpus.py
python3 research/issue185-c2/pilot.py
```

The five deterministic cases are intentionally small. They keep normal
supported, difficult supported, and stress-only output separate while covering
official X4 and SWI plus ordinary X/Y, bounded traverse, reversed X/Y, and
rotation-Z layouts. The pilot fails if a selected corpus record, required
source/layout group, expected result, or case group is missing.

The only public results are `CAN AIM`, `CANNOT BEAR`, and `UNKNOWN`, translated
from the scorer's existing mechanical decision. This pilot does not discover,
choose, reconstruct, or vary an aim point. It does not model aim-point
uncertainty, range, firing solution, line of fire, firing permission, weapon
readiness, or final ENGAGEABLE. It is not the full C2 benchmark.
