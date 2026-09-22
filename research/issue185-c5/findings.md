# C5 aim-point-uncertainty benchmark findings

Status: **inference**, offline mechanical bearing/arc benchmark evidence.

The benchmark contains **329 scenarios** from the retained #184 focused population. Each scenario is one definite recovered aim point, its unchanged #184 uncertainty ball, and the case's real selected turret and mount. Hidden authored points are used only for exact truth and audit.

## Comparison

| exact truth | C5 result | scenarios |
|---|---|---:|
| CAN AIM | CAN AIM | 274 |
| CAN AIM | CANNOT BEAR | 0 |
| CAN AIM | UNKNOWN | 0 |
| CANNOT BEAR | CAN AIM | 0 |
| CANNOT BEAR | CANNOT BEAR | 55 |
| CANNOT BEAR | UNKNOWN | 0 |

Genuine exact geometry UNKNOWN: **0**.

## Exact CANNOT BEAR becoming C5 CAN AIM

None.

All 55 exact CANNOT BEAR scenarios are ordinary-X/Y OUT_OF_ARC cases beyond a real authored pitch limit. None is near enough for the recovered uncertainty to touch that limit: the closest uncertainty ball remains **2.28556 m** clear (limit surface 2.28797 m from the recovered centre versus a 0.00241583 m #184 radius, 947x the radius).

Closest five exact CANNOT BEAR cases to a real limit:

| case | gap (m) | turret | limit | radius (m) | centre to limit (m) | clearance (m) |
|---|---:|---|---:|---:|---:|---:|
| 6280 | 100 | `swi:turret_m_llaser_green_02_macro` | -10° | 0.00241583 | 2.28797 | 2.28556 |
| 5992 | 100 | `swi:turret_m_llaser_green_macro` | -10° | 0.000578826 | 68.113 | 68.1124 |
| 5992 | 100 | `swi:turret_m_llaser_green_macro` | -10° | 0.000628627 | 79.4041 | 79.4035 |
| 6520 | 100 | `swi:turret_m_duallaser_green_02_macro` | -10° | 0.000552746 | 87.0099 | 87.0094 |
| 6520 | 1000 | `swi:turret_m_duallaser_green_02_macro` | -10° | 0.000532119 | 183.858 | 183.858 |

## UNKNOWN and exclusions

- No genuine exact geometry UNKNOWN scenario.
- 0 recovered estimates were not definite: their uncertainty ball covered zero or multiple hidden points.

## Scope

For an ordinary-X/Y recovered centre outside the pitch arc, the C5 evaluation minimizes distance to both real authored pitch-limit aiming surfaces over the complete unlimited-yaw circle. The periodic minimization partitions yaw 2,048 ways, refines every local minimum, and rechecks every overlap witness with the accepted exact-point scorer. This is search resolution, not an aim-point uncertainty or precision margin. Other negative geometry returns UNKNOWN rather than claiming complete coverage.

It does not change the retained #185 scorer, #184 discovery, production code, range, firing solution, line of fire, firing permission, weapon readiness, projectile behavior, or final ENGAGEABLE.
