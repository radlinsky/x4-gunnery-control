# CANNOT BEAR exact-point benchmark findings

Status: **inference**, offline mechanical bearing/arc benchmark evidence.

The benchmark contains **2,516 cases** over all 288 supported turrets. It performs no aim-point discovery and compares no candidate method, so no accuracy metric applies.

## Population

| source | cases |
|---|---:|
| official | 1,116 |
| swi | 1,400 |

| mechanical layout | cases |
|---|---:|
| ordinary_xy | 2,334 |
| bounded_traverse | 152 |
| reversed_xy | 19 |
| rotation_z | 11 |

| case category | cases |
|---|---:|
| normal supported | 576 |
| difficult supported | 1,652 |
| stress-only | 288 |

| accepted C1 result | cases |
|---|---:|
| CAN AIM | 1,400 |
| CANNOT BEAR | 1,107 |
| UNKNOWN | 9 |

## Unusual layouts

| layout | CAN AIM | CANNOT BEAR | UNKNOWN |
|---|---:|---:|---:|
| bounded_traverse | 80 | 64 | 8 |
| reversed_xy | 10 | 8 | 1 |
| rotation_z | 7 | 4 | 0 |

## Scorer UNKNOWN patterns

- 8: `bounded_traverse` / `UNKNOWN_pivot`
- 1: `reversed_xy` / `UNKNOWN_pivot`

These remaining UNKNOWN rows place the aim point exactly at the fixed joint pivot. X4 skips the zero-length direction solve there, so the accepted analysis cannot establish a usable stable position. No UNKNOWN row remains because of hidden current position, movement, traps, or a wide root limit.

## Geometry coverage

The retained nonzero distances are **100 m and 8,000 m**. The 100 m near case is an accepted #176 distance scale where offsets remain material; 8,000 m is a realistic distant-target control. Repeating the same normal bearing and every limit pair at both distances exposes offset-rotating-part effects without a large distance sweep. The accepted result or state changes with distance for **7** otherwise-identical constructions, confirming that the population is not direction-only.

The benchmark retains **413 usable authored joint boundaries** across **284 turrets**. For each boundary it poses the accepted geometry at 0.1 degrees inside and outside the authored limit and supplies a point from the joint pivot along that posed bore at both distances. A boundary is retained only when the accepted scorer observes a CAN AIM / OUT_OF_ARC transition at one or both distances. The four uncovered turrets are ordinary X/Y layouts with unlimited traverse and a -90/+90 degree leaf arc, so they have no reachable/unreachable mechanical transition to bracket.

Every turret also receives the two-distance normal bearing and one component-origin stress case. Unusual layouts retain their own generated limit cases and separate reporting rather than inheriting ordinary-X/Y evidence. This targeted population covers distance sensitivity and real reach transitions without recreating the 37,830-case #176 benchmark.

The accepted #176 corpus and corrected exact-point scorer are reused. This benchmark excludes aim-point uncertainty, range, firing solution, line of fire, firing permission, weapon readiness, projectile behavior, and final ENGAGEABLE. It adds no LIVE evidence.
