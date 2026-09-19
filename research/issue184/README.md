# Issue #184 aim-point map: A1 foundation

Offline research, status **inference**. No X4 launch, no production change.
CANNOT BEAR, LINE OF FIRE BLOCKED, range, firing solution and ENGAGEABLE are
out of scope.

```sh
python3 research/issue184/aimpoint_map.py             # class margins (~20 s)
python3 research/issue184/aimpoint_map.py --selftest
```

Needs the ignored #176 caches: `python3 research/issue176-a4x/corpus.py` and
the #167 study corpus.

## Kept from #176, unchanged

- A4x 288-turret corpus and ordered `ops` (`issue176-a4x/corpus.py`, `scorer.py`):
  the only accepted turret kinematics.
- #167/#173 `study.Q`, `select` and `geometry`: the native quantised query,
  binary32 nearest-point selection, and the accepted yaw-rest/pitch solve. The
  selected-endpoint position it returns is the hidden aimed muzzle.
- #167 authored aim points with target box centre `C` and half-extents `H`,
  plus `fibonacci`, `ROT`, and A2's 10 m to 100 km distances.

The A2/A4/A5 ray methods (`consensus`, `crossing`, `along`, adaptive probing)
stay where they are. A3 imports them when a method needs one; they are not
copied here.

## The two methods (A1)

The mapper under test receives only `oracle(case)` (direction to the selected
aim point from a query position), the target box, and the firing-ship class
and box. `case["points"]` and `aimed_muzzles()` are scoring truth only.

**Firing-ship box.** `firing_box(ship_lo, ship_hi, margin[class])`. A later
muzzle outside it is UNKNOWN (`inside`). The margin for each class is derived
offline:

1. Mount size comes from the authored size tag on the turret component's
   `turret` connection. All 288 turrets resolve to exactly one size.
2. `reach` sweeps every joint over its authored limits on a 0.5° grid and
   takes the maximum endpoint distance from the mount. It then adds
   `joints × Σ|fixed t| × step/2`, so the result stays an upper bound between
   grid points. This covers aimed poses, not only the rest pose.
3. A class margin is the largest `reach` over the turret sizes that class may
   mount. Inference: each class mounts its own size and every smaller size.
   That set is conservative, but it is not a slot census.

| class | margin | set by |
|---|---:|---|
| ship_s | 17.10 m | swi:turret_s_imp_exe_quad_tl_red_macro |
| ship_m | 43.77 m | swi:turret_arrestor_dish_macro |
| ship_l | 84.17 m | official:turret_par_l_plasma_01_mk1_macro |
| ship_xl | 609.59 m | swi:subjugator_ion_turret_macro |

The margin assumes the mount lies inside the runtime ship box. For now the
case builder uses the mount point as the ship box, which is a lower bound on a
real hull. A sample of every 7th case gave 2,178 IN_ARC hidden muzzles; none
fell outside their class box or beyond their own turret's reach.

**Target box.** Search `target_box(C, H, scale)`, which keeps the target
box's proportions. `nearest(located, muzzle)` applies X4's nearest-point rule
to `[(label, centre, radius)]` and returns a label only when the winner's
farthest possible distance is strictly less than every rival's closest
possible distance. Otherwise it returns UNKNOWN.

**Target population.** `targets()` keeps only targets Gunnery Control can ask
ENGAGEABLE about, using the generic #168/#169 rule on the #167 corpus:

- Whole ships: all kept (50 components).
- Turret, missile turret, shield and engine surfaces: kept when the tags on
  their unique `component` mating connection, minus `component` itself, are a
  subset of a connection on some macro-referenced L/XL ship or station module,
  and their macro (following `ref`) is not `hull integrated`. That keeps 88
  turret, 49 shield and 30 engine components.
- Excluded: 28 records whose mating tags require `unhittable`, which only
  M-ship sockets carry. That is 27 turret `_01` records (the 21 #168 zero-box
  turrets plus 6 nonzero-box ones) and the shield video macro. Also excluded:
  1 with no compatible host (`turret_bor_m_mining_02`) and 3 `hull integrated`
  (the Kha'ak L beam, the Xenon XL battleship turret, and a Kha'ak destroyer
  engine). The Kha'ak
  scenario beam overrides `integrated="0"` and is kept.
- A zero box on an in-scope target raises. None occurs in X4 9.00.

Authored aim points do not always lie inside the target box (#169). Every
whole ship, shield and engine fits. 68 of the 88 in-scope turret surfaces have
their aim point above the box, always along +Y only, so no 1.2× box contains
them. The worst is `turret_kha_m_beam_01_mk1`: 8.85 m above a box 3.44 m in
half-height, which needs 3.57× proportional scale. A2 chooses `scale`, or a pad
on the Y axis, from the benchmark.

## Remaining

- **A2:** real firing-ship hull boxes and mounts, and target-box `scale`. Add
  stratified close, boundary, stress and artificial cases on top of `cases()`,
  then score both methods for wrong answers, UNKNOWN, missed, invented, merged
  and duplicate points, uncertainty, muzzle coverage and query cost.
- **A3:** the discovery searches: 8 box corners first, then only the queries
  that add information, reusing the #176 ray-location and confirmation code.
  The target-box method also needs its "set complete enough" rule.
