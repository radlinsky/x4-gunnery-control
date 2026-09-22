# C5 aim-point-uncertainty benchmark findings

Status: **inference**, offline mechanical bearing/arc benchmark evidence.

The benchmark contains **330 scenarios** from the retained #184 focused population. Each scenario is one definite recovered aim point, its unchanged #184 uncertainty ball, and the case's real selected turret and mount. Hidden authored points are used only for exact truth and audit.

## C5.2 firing-origin movement

This measures movement caused solely by the unchanged recovered aim-point uncertainty; it is **not prediction error**.

- C5 CAN AIM scenarios measured: **275**
- Recovered centre has at least one CAN AIM muzzle: **275**
- CAN AIM exists only off centre: **0**
- Movement median / p90 / p99 / maximum: **1.77446004e-06 / 1.46585431e-05 / 2.74848373e-05 / 3.28047623e-05 m**

The worst case is **12177**, `swi:turret_l_mando_double_ion_macro`, ordinary_xy, 100 m engagement distance: #184 radius **0.00179534634 m**, 1 centre muzzle(s), maximum movement **3.28047623e-05 m** (**0.0182721081x** the radius).

### Mechanical layout

| layout | scenarios | median (m) | p90 (m) | p99 (m) | maximum (m) |
|---|---:|---:|---:|---:|---:|
| ordinary_xy | 275 | 1.77446004e-06 | 1.46585431e-05 | 2.74848373e-05 | 3.28047623e-05 |
| bounded_traverse | 0 | — | — | — | — |
| reversed_xy | 0 | — | — | — | — |
| rotation_z | 0 | — | — | — | — |

### Settled-position branches

Scenarios whose valid settled-muzzle count changes in the ball: **0**. Scenarios where a new branch appears beyond those represented at the centre: **0**.

### Numerical-search stability

The nested coarse search maximum was **3.22148558e-05 m**; adding the denser whole-ball samples gave **3.25459445e-05 m**; final constrained pattern refinement gave **3.28047623e-05 m**. Fine sampling increased the coarse maximum by **3.31e-07 m** and final refinement increased the fine sampled maximum by **2.59e-07 m**.

Each valid muzzle at every point is compared with its nearest centre-predicted muzzle; muzzles are never paired by list order. The deterministic search covers the centre, interior radial shells, the full spherical boundary, and constrained local refinement.

## C5.1 comparison

| exact truth | C5 result | scenarios |
|---|---|---:|
| CAN AIM | CAN AIM | 275 |
| CAN AIM | CANNOT BEAR | 0 |
| CAN AIM | UNKNOWN | 0 |
| CANNOT BEAR | CAN AIM | 0 |
| CANNOT BEAR | CANNOT BEAR | 55 |
| CANNOT BEAR | UNKNOWN | 0 |

Genuine exact geometry UNKNOWN: **0**.

## Exact CANNOT BEAR becoming C5 CAN AIM

None.

All 55 exact CANNOT BEAR scenarios are ordinary-X/Y OUT_OF_ARC cases beyond a real authored pitch limit. None is near enough for the recovered uncertainty to touch that limit: the closest uncertainty ball remains **2.28599 m** clear (limit surface 2.28776 m from the recovered centre versus a 0.00176801 m #184 radius, 1294x the radius).

Closest five exact CANNOT BEAR cases to a real limit:

| case | gap (m) | turret | limit | radius (m) | centre to limit (m) | clearance (m) |
|---|---:|---|---:|---:|---:|---:|
| 6280 | 100 | `swi:turret_m_llaser_green_02_macro` | -10° | 0.00176801 | 2.28776 | 2.28599 |
| 5992 | 100 | `swi:turret_m_llaser_green_macro` | -10° | 0.000569712 | 68.1129 | 68.1123 |
| 5992 | 100 | `swi:turret_m_llaser_green_macro` | -10° | 0.000554677 | 79.4041 | 79.4035 |
| 6520 | 100 | `swi:turret_m_duallaser_green_02_macro` | -10° | 0.000508728 | 87.0099 | 87.0093 |
| 6520 | 1000 | `swi:turret_m_duallaser_green_02_macro` | -10° | 0.000508728 | 183.858 | 183.858 |

## UNKNOWN and exclusions

- No genuine exact geometry UNKNOWN scenario.
- 0 recovered estimates were not definite: their uncertainty ball covered zero or multiple hidden points.

## Scope

For an ordinary-X/Y recovered centre outside the pitch arc, the C5 evaluation minimizes distance to both real authored pitch-limit aiming surfaces over the complete unlimited-yaw circle. The periodic minimization partitions yaw 2,048 ways, refines every local minimum, and rechecks every overlap witness with the accepted exact-point scorer. This is search resolution, not an aim-point uncertainty or precision margin. Other negative geometry returns UNKNOWN rather than claiming complete coverage.

It does not change the retained #185 scorer, #184 discovery, production code, range, firing solution, line of fire, firing permission, weapon readiness, projectile behavior, or final ENGAGEABLE.
