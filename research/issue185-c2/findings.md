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
| CANNOT BEAR | 1,012 |
| UNKNOWN | 104 |

## Unusual layouts

| layout | CAN AIM | CANNOT BEAR | UNKNOWN |
|---|---:|---:|---:|
| bounded_traverse | 80 | 64 | 8 |
| reversed_xy | 10 | 8 | 1 |
| rotation_z | 7 | 3 | 1 |

## Scorer UNKNOWN patterns

- 54: `ordinary_xy` / `UNKNOWN_none`
- 38: `ordinary_xy` / `UNKNOWN_none_trap`
- 8: `bounded_traverse` / `UNKNOWN_pivot`
- 2: `ordinary_xy` / `UNKNOWN_one_trap`
- 1: `rotation_z` / `UNKNOWN_none`
- 1: `reversed_xy` / `UNKNOWN_pivot`

## Geometry coverage

The retained nonzero distances are **100 m and 8,000 m**. The 100 m near case is an accepted #176 distance scale where offsets remain material; 8,000 m is a realistic distant-target control. Repeating the same normal bearing and every limit pair at both distances exposes offset-rotating-part effects without a large distance sweep. The accepted result or state changes with distance for **7** otherwise-identical constructions, confirming that the population is not direction-only.

The benchmark retains **413 usable authored joint boundaries** across **284 turrets**. For each boundary it poses the accepted geometry at 0.1 degrees inside and outside the authored limit and supplies a point from the joint pivot along that posed bore at both distances. A boundary is retained only when the accepted scorer observes a CAN AIM / CANNOT BEAR transition at one or both distances; UNKNOWN remains unchanged. The four uncovered turrets are ordinary X/Y layouts with unlimited traverse and a -90/+90 degree leaf arc, so they have no reachable/unreachable mechanical transition to bracket.

Every turret also receives the two-distance normal bearing and one component-origin stress case. Unusual layouts retain their own generated limit cases and separate reporting rather than inheriting ordinary-X/Y evidence. This targeted population covers distance sensitivity and real reach transitions without recreating the 37,830-case #176 benchmark.

The accepted #176 corpus and scorer are reused unchanged. This benchmark excludes aim-point uncertainty, range, firing solution, line of fire, firing permission, weapon readiness, projectile behavior, and final ENGAGEABLE. It adds no LIVE evidence.
