# A5: is a turret a sphere with outward-normal firing? — 2026-09-18

Scope: [Issue #176](https://github.com/radlinsky/x4-gunnery-control/issues/176)
A5. Starting SHA `25637fd`. Offline forward kinematics over the accepted
288-turret A4x corpus (124 official X4 9.00, 164 SWI 0.9.1 HF). Research only.
No hull, LOS, target solving or production change.

```sh
python3 research/issue176-a4x/corpus.py              # if the ignored corpus cache is missing
python3 research/issue176-a5/sphere_normal.py --check
python3 research/issue176-a5/sphere_normal.py        # ~25 s, prints every table below
```

## Method

- **Geometry.** `scorer.segments` gives T = L ∘ J_leaf ∘ G ∘ J_root ∘ H. The
  joints use `scorer.JOINT`, and the launch direction is the +Z row of the
  endpoint frame. This is the same machinery as A4x `scorer.py`. `--check`
  confirms that all 288 nearest-to-zero poses match `compare._reference_endpoint`
  bit for bit.
- **Endpoint.** One endpoint per turret: the corpus-selected reference endpoint.
- **Sampling.**
  - Each limited joint uses 37 evenly spaced angles, including both limits and 0.
  - An unlimited joint (yaw, or rotation-Z) uses 72 angles at 5° steps.
  - This is a full grid, so it includes every limit, every limit corner and the
    rest pose.
  - Total: 774,225 poses.
  - No pose is UNKNOWN. Every joint pair inside the authored limits is a legal
    pose. The scorer's UNKNOWN rules decide which pose X4 selects for a target,
    not whether a pose exists.
- **Fixed centers.**
  - `origin`: the turret component origin.
  - `root`: the yaw/root joint pivot.
  - `leaf`: the pitch pivot, taken at root angle 0.
  - `leaf_on_root_axis`: the pitch pivot projected onto the root rotation axis.
    It is a fixed, simple geometric center, but it needs the authored pivot
    position, which the runtime cannot read for an unknown turret
    (`runtime-restriction-access.md`). The universal shipped method cannot use it.
  - `fit_radius`: the least-squares sphere through the muzzle positions.
  - `fit_lines`: the least-squares point nearest every firing line.
  - `fit_minimax`: the best center found by a local compass search that tries
    to minimise the worst direction error. It is not a proven global optimum,
    and its cone is not a lower bound: another center could do better.
  - None of these centers moves with the turret.
- **Direction error** is the angle between (muzzle − center) and the launch
  direction. The **cone** for a turret is its worst sampled direction error.

**Mathematically guaranteed:** at every pose, the directed error is
atan2(|v × D|, v · D), where v = muzzle − center and D is the launch
direction. The script computes exactly this. The perpendicular distance from
the center to the firing line is d = |v × D|, so sin(error) = d / r with
r = |v|. That gives error = asin(d / r) only when the error is at most 90°,
meaning the barrel points outward (v · D ≥ 0). When the barrel points back
toward the center, the directed error is 180° − asin(d / r). A firing line
that passes d > 0 from the center is never radial, and for a fixed d the
error grows as the muzzle gets closer to the center.

## Headline numbers (observed on the current corpus)

### Worst direction error per turret, in degrees

| center | median | p90 | p95 | p99 | max |
|---|---:|---:|---:|---:|---:|
| origin | 32.2 | 58.7 | 74.8 | 80.2 | 135.6 |
| root | 24.3 | 46.3 | 64.4 | 67.0 | 90.0 |
| leaf | 18.2 | 64.8 | 69.2 | 79.7 | 177.7 |
| **leaf_on_root_axis** | **14.6** | **42.8** | **51.1** | **55.1** | **90.0** |
| fit_radius | 14.7 | 47.5 | 55.4 | 56.5 | 90.0 |
| fit_lines | 15.4 | 49.3 | 55.3 | 66.0 | 90.0 |
| fit_minimax (best found by search) | 13.4 | 37.1 | 51.1 | 55.1 | 55.1 |

### Turrets whose worst error fits within each cone half-angle (of 288)

| center | ≤1° | ≤2° | ≤5° | ≤10° | ≤15° | ≤20° | ≤30° |
|---|---:|---:|---:|---:|---:|---:|---:|
| origin | 4 | 4 | 6 | 41 | 57 | 73 | 141 |
| root | 5 | 5 | 17 | 67 | 97 | 112 | 194 |
| leaf | 9 | 12 | 29 | 82 | 126 | 169 | 200 |
| **leaf_on_root_axis** | 10 | 15 | 37 | 102 | 148 | 202 | 238 |
| fit_minimax | 12 | 17 | 37 | 103 | 150 | 206 | 247 |

### Worst direction error by weapon behavior (leaf_on_root_axis / fit_minimax)

| group | median | p90 | max |
|---|---:|---:|---:|
| conventional gun (252) | 12.2 / 12.1 | 29.9 / 26.5 | 90.0 / 50.0 |
| dumbfire missile (16) | 51.1 / 51.1 | 51.1 / 51.1 | 52.5 / 52.5 |
| guided missile (20) | 53.8 / 53.8 | 55.1 / 55.1 | 55.1 / 55.1 |
| official (124) | 16.6 / 15.6 | 52.1 / 51.1 | 67.1 / 55.1 |
| SWI (164) | 12.1 / 12.1 | 37.9 / 29.9 | 90.0 / 50.0 |

### Worst direction error by mechanical class (leaf_on_root_axis; best simple center)

| class | n | worst error |
|---|---:|---|
| ordinary_xy | 278 | median 15.6°, p90 42.8°, max 90° |
| bounded_traverse | 8 | 0–10.7° (seven at 8.5–10.7°); identical at every mechanical center |
| reversed_xy | 1 | 4.9° (0.15° at the best-fit center) |
| rotation_z (arrestor dish) | 1 | 0.4° |

### Radius spread (max − min) / mean radius

| center | median | p90 | max |
|---|---:|---:|---:|
| leaf_on_root_axis | 3.1 % (0.35 m) | 30.2 % (6.0 m) | 97 % |
| fit_radius (best sphere) | 1.6 % (0.17 m) | 16.7 % (3.1 m) | 104 % |

Pooled over all 774,225 poses, the direction error at leaf_on_root_axis has a
median of 12.1°, a p90 of 37.1° and a p99 of 54.8°. Per-center, per-class and
per-source tables, and the 40 worst turrets, are printed by the script.

## Worst real turrets and why

All failures come from one mechanism: **the firing line does not pass through
the center, and the muzzle is close to the center.** The cases below show the
concrete geometry.

1. **Official M missile turrets.** There are 20: the Argon, Split, Teladi,
   Terran and Paranid `m_guided_01/02` and `m_dumbfire_01/02`. The launch
   endpoint sits 4.5 m from the pitch pivot, but its launch line passes 4.1 m
   to the side of the pivot. The missile leaves roughly parallel to the arm,
   not along it. The error is 51–55° at every tested center, including the best center found by the search.
   These turrets are fundamentally non-radial. The L missile turrets
   (`spl_l_*` 52°, `par_l_*` 31–40°) behave the same way at larger scale.
2. **`swi:subjugator_ion_weapon_macro`.** The launch line is perpendicular to a
   94.6 m arm: the barrel fires tangentially. Every mechanical center gives
   exactly 90°. The best center the search found lies far away and reaches 50°.
3. **SWI Imperial dual turbolasers.** These are the eight `bella`/`exe`
   `dual_tl` colours. The pitch pivot is 19.9 m off the yaw axis, and the
   endpoint line misses it by 33 m. That gives 43° at leaf_on_root_axis and
   33° at the best center found by the search.
4. **Short-arm guns.** Examples: `arg_m_beam` (0.94 m barrel, 67°),
   `bor_m_railgun`, `gen_m_shieldpierce`, and SWI `vcx100_short*`. A small
   sideways offset over a barrel of 1–3 m gives a large angle. Of the 242
   ordinary-class guns, 54 exceed 20°. Across those guns, the median firing
   line passes 2.4 m from the pitch pivot. That is ordinary for twin- and
   multi-barrel layouts, where the selected endpoint is one barrel of the set.
5. **Bounded traverse (8).** Every mechanical center gives the same 0–10.7°,
   and the radius spread is 0. These are spherical, with a constant barrel
   offset.

The failures are not random. They follow sideways barrel offset relative to
barrel length. Missile launch tubes, pivots displaced from the yaw axis, and
tangential barrels are the extreme cases. Reversed joint order and rotation-Z
are not a problem in this corpus.

## Answers

1. **Is the muzzle path approximately spherical?** Mostly yes, observed on this
   corpus. Around the best-fit sphere, the median spread is 1.6 % of radius and
   the p90 is 16.7 %. Around leaf_on_root_axis the figures are 3.1 % and 30 %.
   A long tail exists where the pitch pivot is off the yaw axis or the arm is
   short.
2. **Is the firing direction approximately radial?** No. Even the best
   fixed center found by the search gives a median worst error of 13° and a p90 of 37°.
   Official missile turrets are about 51–55°. Only 37 of 288 turrets stay within 5°, and 103
   within 10°.
3. **Which fixed center works best?** `leaf_on_root_axis`, the pitch pivot
   projected onto the root axis. It is the best simple center for 215 of 288
   turrets. The component origin and the root pivot are clearly worse.
4. **Is a simple center nearly as good as the best fit?**
   Geometrically yes. leaf_on_root_axis is within 1–2° of the best center found
   by the search at the median and p95, and it covers 238 turrets within 30°
   against 247 for that center. It lies a median of 0.56 m from the line fit.
   It is not runtime-available. It needs the pitch pivot, which is authored
   geometry that the runtime cannot read for an unknown turret
   (`runtime-restriction-access.md`), so the universal shipped method cannot
   use it. The component origin is the only center
   plainly available, and it is the worst one (a median of 32°).
5. **What cone covers most turrets?** At the best simple center, 20° covers 202
   of 288 turrets (70 %) and 30° covers 238 (83 %). Covering all turrets took
   55° at the best center found by the search, and 90° at the simple center. For conventional
   guns alone, 30° covers 230 of 252 (91 %).
6. **Which classes break it?**
   - Official missile turrets (all 32). The 4 SWI missile tubes are only
     5.7°, so missile behavior alone is not the cause.
   - Tangential-barrel designs (Subjugator).
   - Pitch pivots displaced from the yaw axis (SWI Imperial dual turbolasers,
     Paranid L missiles).
   - Short-arm guns with a sideways barrel offset.
7. **Is it good enough to justify a hull-intersection task?** Not as a
   per-direction model. With a 20–30° cone plus an unknown center, a hull test
   could only rule out directions whose entire widened cone lies in the hull.
   That leaves a weak, conservative signal at best. Official missile turrets
   would need a cone of about 55°, which is almost no information. **Recommendation:** do
   not start the hull task on this model alone. It is worth pursuing only if a
   conservative "wide cone fully inside hull" rule is acceptable, and if
   official missile turrets are excluded or handled separately.

## What is established where

- **Mathematically guaranteed:** the directed error is
  atan2(|v × D|, v · D). It equals asin(line offset / radius) only up to 90°,
  and beyond that it is 180° minus that value. Any turret whose firing line misses the center is non-radial. No cone
  bound holds for an arbitrary turret, because a tangential barrel (90°) is
  mechanically legal.
- **Observed on the current 288-turret corpus:** every number above. The
  results are sampled on a 5°/37-step grid and use one endpoint per turret.
  fit_minimax is the best center found by a local search, not a proven
  optimum or lower bound.
- **Possible generalization, unproven:** future or mod turrets probably fall
  into the same mechanism classes, but nothing bounds their offsets. Treat
  every cone figure here as descriptive, not safe.
