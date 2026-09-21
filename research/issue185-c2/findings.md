# CANNOT BEAR exact-point benchmark findings

Status: **inference**, offline mechanical bearing/arc benchmark evidence.

The benchmark contains **2,304 cases**: the same eight supplied exact component-frame points for each of all 288 supported turrets. It performs no aim-point discovery and compares no candidate method, so no accuracy metric applies.

## Population

| source | cases |
|---|---:|
| official | 992 |
| swi | 1,312 |

| mechanical layout | cases |
|---|---:|
| ordinary_xy | 2,224 |
| bounded_traverse | 64 |
| reversed_xy | 8 |
| rotation_z | 8 |

| case category | cases |
|---|---:|
| normal supported | 576 |
| difficult supported | 1,440 |
| stress-only | 288 |

| accepted C1 result | cases |
|---|---:|
| CAN AIM | 1,579 |
| CANNOT BEAR | 529 |
| UNKNOWN | 196 |

## Unusual layouts

| layout | CAN AIM | CANNOT BEAR | UNKNOWN |
|---|---:|---:|---:|
| bounded_traverse | 30 | 12 | 22 |
| reversed_xy | 2 | 5 | 1 |
| rotation_z | 1 | 4 | 3 |

## Scorer UNKNOWN patterns

- 94: `ordinary_xy` / `UNKNOWN_none`
- 70: `ordinary_xy` / `UNKNOWN_none_trap`
- 14: `bounded_traverse` / `UNKNOWN_root_limit_unwrap`
- 8: `bounded_traverse` / `UNKNOWN_pivot`
- 6: `ordinary_xy` / `UNKNOWN_one_trap`
- 3: `rotation_z` / `UNKNOWN_none`
- 1: `reversed_xy` / `UNKNOWN_pivot`

## Scope

The two normal points cover routine forward/oblique bearings. The five difficult points cover astern and the four component axes, including exact 90-degree limits and poles. The component origin is reported only as stress. Applying this static set to every turret prevents the 278 ordinary X/Y turrets from substituting for the ten unusual-layout turrets.

The accepted #176 corpus and scorer are reused unchanged. This benchmark excludes aim-point uncertainty, range, firing solution, line of fire, firing permission, weapon readiness, projectile behavior, and final ENGAGEABLE. It adds no LIVE evidence.
