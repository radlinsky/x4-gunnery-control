# Issue #184 aim-point map: A2 benchmark, A3 mappers

Offline research, status **inference**. No X4 launch, no production change.
CANNOT BEAR, LINE OF FIRE BLOCKED, range, firing solution and ENGAGEABLE are
out of scope. A2 provides the cases, the hidden truth, the two box inputs and
the scorer; A3 builds the smallest reliable version of each method and runs
both on those cases.

```sh
python3 research/issue184/extract_swi_assets.py <SWI 0.9.1 HF mod dir>  # once
python3 research/issue184/aimpoint_map.py             # A2 summary (~15 min)
python3 research/issue184/aimpoint_map.py --selftest  # ~4 min
python3 research/issue184/aimpoint_map.py --a3        # A3 benchmark (~3 h, 4 niced workers)
python3 research/issue184/aimpoint_map.py --a3 --every 20   # deterministic pilot (~13 min)
python3 research/issue184/aimpoint_map.py --a43       # A4.3 phase 1, 19 boundary cases
python3 research/issue184/aimpoint_map.py --a43r      # A4.3 phase 2 rescue, same 19 cases
python3 research/issue184/aimpoint_map.py --a43f      # A4.3 phase 3 fallback, same 19 cases
python3 research/issue184/aimpoint_map.py --a43h      # A4.3 phase 4 coverage map, same 19 cases
python3 research/issue184/aimpoint_map.py --a43a      # A4.3 phase 5 angular search, same 19 cases
python3 research/issue184/ship_aimpoint_census.py     # A4.4 ship aim-point census, both games (~6 min)
```

A4.4 is written up separately in [A44_CENSUS.md](A44_CENSUS.md). It censuses
pristine vanilla 9.00 and SWI 0.9.1 HF as two independent games — SWI is an
overhaul, so a pooled statistic describes neither — and applies the SWI
`<diff>` patches, name index and same-name replacements this benchmark
deliberately skips. A4.5, the native empty-aim-point trace and the direct-path
decision table, is in [A45_DIRECT_PATH.md](A45_DIRECT_PATH.md).

Needs the ignored #176 caches (`python3 research/issue176-a4x/corpus.py`, the
#167 study corpus) and the SWI asset XML extracted from the owner's
`starwarsmod_m1/ext_01.cat` into `.x4-research-cache/issue184/swi_assets/`.

## Reused, unchanged

- A4x 288-turret corpus and ordered `ops` (`issue176-a4x/corpus.py`, `scorer.py`).
- #167/#173 `study.Q`, `select`, `geometry`: native quantised query, binary32
  nearest-point selection, and the accepted yaw-rest/pitch solve. Its
  selected-endpoint position is the hidden aimed muzzle.
- #167 `sources.macro_box` runtime-box reconstruction and `conn_world`
  connection frames, used for both firing ships and target hosts.
- #167 `study.SYN` synthetic targets for the artificial group, and
  `pair_frame` for the boundary bearings.
- The accepted turret-to-ship compatibility rule: a turret fits a mount when
  its mating-connection tags, minus `component`, are a subset of the mount's
  tags.

The A2/A4/A5 #176 ray methods stay where they are. A3 imports them when needed.

## Firing ships

Real ships from official X4 9.00 and SWI 0.9.1 HF, one macro per component,
classes `ship_s` to `ship_xl`. Each ship contributes its reconstructed runtime
box and every turret mount a corpus turret fits. Only compatible turrets are
paired. Source rule: an official ship takes official turrets only; an
SWI ship takes official or SWI turrets. That drops 2,087 SWI-turret pairs from
official mounts. The turret frame on the ship is
`inverse(turret mating) ∘ ship mount`, the same rule `macro_box` uses for
children.

Official XML stays vanilla. SWI `<diff>` patches (216) and SWI files that
replace an official definition (23 names) are not applied. SWI ships resolve
against the remaining SWI asset XML plus official.

**Inference:** 92 SWI turrets omit the `component` token on their mating
connection (`swi-091-turret-geometry.md`). For those, the unique
`turret`-tagged connection is the mating connection. 77 paired turrets rely on
this.

| source | class | ships | mounts | turrets in cases |
|---|---|---:|---:|---:|
| official | ship_m | 48 | 122 | 6 |
| official | ship_l | 49 | 431 | 15 |
| official | ship_xl | 29 | 562 | 17 |
| swi | ship_s | 2 | 2 | 5 |
| swi | ship_m | 45 | 161 | 29 |
| swi | ship_l | 62 | 1248 | 57 |
| swi | ship_xl | 28 | 2916 | 75 |

Mount, turret and ship rotation (`study.ROT`) cycle with the case id, so each
of the 5,442 mounts appears about 3 times. Not every compatible turret appears
on every mount. The cases use 26 distinct official and 115 distinct SWI
turrets.

## Targets

The A1 population, unchanged: 217 official components (50 whole ships, 88
turret, 49 shield and 30 engine surfaces), 240 authored aim points. Surfaces
now use their **real mounted orientation**: the frame of the first compatible
official L/XL-ship or station-module connection, sorted by name. Whole ships
use identity. Each case then applies one of the 24 axis rotations.

## Groups

The firing ship is placed so its whole runtime box clears the target's
bounding sphere by at least the gap. Case construction never looks at a muzzle.

| group | placement | cases |
|---|---|---:|
| close | 8 bearings × gap 10, 100 m | 3,472 |
| ordinary | 8 bearings × gap 1, 2.5, 5 km | 5,208 |
| boundary | 8 bearings in the bisector plane of the target's nearest aim-point pair × gap 100 m, 1 km (targets with ≥2 points) | 240 |
| stress | 8 bearings × gap 20, 100 km | 3,472 |
| artificial | all 4,320 `study.SYN` two-point synthetic targets, mount at the synthetic query position; not a supported case | 4,320 |

Hidden aimed muzzles come only from IN_ARC poses of ordinary_xy turrets. An
out-of-arc request is CANNOT BEAR territory. Cases with no IN_ARC muzzle stay
in the group: close 1,413, ordinary 2,042, boundary 83, stress 1,356,
artificial 775.

## Box inputs for A3

**Firing-ship box**, `firing_box(ship box, class margin)`: the runtime ship
box grown by one scalar per class. Production still gets only the ship class
and runtime box. The margins below are derived offline from real ships.

For every real ship of a class, every turret mount on it, and every
compatible turret on that mount, the turret is swept through its whole legal
joint range on a 0.5° grid. Each sampled muzzle is placed on the ship through
the real mount transform, and the code measures how far it lies outside the
ship's runtime box along any axis. That is exactly the scalar `firing_box`
must grow by. The class margin is the largest such overflow plus that
turret's between-grid allowance, `joints × Σ|fixed t| × 0.25°`. No legal pose
lies farther than the allowance from a sampled one, and mounting the turret
rigidly doesn't change that distance. The margin therefore bounds the full
sweep, not only the grid points.

| class | old A1 margin | new margin | sampled overflow | set by (ship, mount, turret) |
|---|---:|---:|---:|---|
| ship_s | 17.10 m | 2.55 m | 2.53 m | SWI `scurrg_h6_macro` `con_weapon_08` `turret_vcx100_short` |
| ship_m | 43.77 m | 26.40 m | 26.32 m | SWI `defender_corvette_macro` `con_m_turret_ltb_1` `turret_m_ltbdual_green` |
| ship_l | 84.17 m | 261.49 m | 261.43 m | SWI `nebulonc_macro` `con_m_turret_pd-back_3` `turret_m_quadlaser_blue_02` |
| ship_xl | 609.59 m | 547.06 m | 547.00 m | SWI `ship_providence_carrier_01_macro` `con_m_turret_left-pdls_5` `turret_m_quadlaser_blue_02` |

The old A1 margin was the turret's reach from its own origin, and it assumed
the mount lay inside the ship box. A2 showed that assumption is wrong. As
supporting evidence only, 173 of the 5,442 turret origins lie outside their
ship box: 159 SWI and 14 official. The worst is 540.48 m on the Providence
carrier, and none lies beyond the new class margin. Every margin is set by an
SWI mount of that kind.

Hidden aimed muzzles against the new margins, tested in the ship frame:

| group | inside | outside |
|---|---:|---:|
| close | 2,280 | 0 |
| ordinary | 3,518 | 0 |
| boundary | 398 | 0 |
| stress | 2,330 | 0 |
| artificial | 7,083 | 0 |

**Target box**, `target_box(C, H)`: the runtime box plus `TARGET_PAD_Y =
8.86 m` on +Y only. 68 of 217 targets have an aim point above their box, and
none is outside it in any other direction. The worst is
`turret_kha_m_beam_01_mk1`, which needs 8.85 m.

| rule | covers all | search-volume growth |
|---|---|---|
| proportional scale 3.57× | yes | ×45.6 for every target |
| +Y pad 8.86 m | yes | median ×2.72, max ×11.48 |

The +Y pad is carried forward; the A3 target-box search uses it.

## Scoring (for A3 results)

A mapper sees only `view(case)`: the oracle, the target box, and the ship
class, box, position and rotation. Aim points, turret, mount and muzzles are
hidden. `score(case, result, aimed_muzzles(case))` takes
`{"located": [(label, centre, radius)], "answer": muzzle -> label | UNKNOWN, "queries": n}`
and reports:

- `correct`, `wrong` and `unknown` answers over the hidden muzzles;
- `missed`, `invented`, `merged` and `duplicate` aim points;
- point-location `radius` and actual `error`;
- muzzle coverage, as (correct + wrong) / muzzles;
- `queries`.

`nearest(located, muzzle)` is the A1 definite nearest-point rule.

## Excluded

- 69 official and 65 SWI `ship_s`, 6 official and 12 SWI `ship_m`, 2 official
  and 1 SWI `ship_xl`, and 1 SWI `ship_l`: no mount any corpus turret fits.
- 11 SWI ships whose runtime box or mounts do not resolve. The causes are
  duplicate component definitions (MC80 variants, X-wings), a missing part
  macro, and unresolved dock connections.
- 1 SWI asset XML (`deathstar_01.xml`) does not parse.
- 10 turrets that are not ordinary_xy: no accepted aimed-muzzle truth.
- 33 turrets that fit no real ship mount under the source rule.

## A3 mappers

Both methods start from the eight outer corners of their box and share one
search. A leaf whose eight corners all select the same located point lies
inside that point's Voronoi cell, because those cells are convex; every
position in it then selects that point, and no other aim point lies in it.
A leaf that fails is split, to `MAX_DEPTH = 2` (a 5x5x5 corner grid at most).
`CAP = 128` queries per mapper run is a research cap, not the production limit
(A6).

**Locating a point** reuses the accepted #176 work unchanged in spirit: the A2
crossing envelope, its forward and poor-angle rejection (1% of depth), and the
A5 along-ray bracket. A point is accepted only when *two* other rays cross an
anchor ray at agreeing depths inside the padded target box and the bracket on
the anchor confirms it (forward just short of the crossing, non-forward just
past it). Both halves are load-bearing:

- Without the bracket, the #176 A2 witness passes: rays that each select a
  different point all meet at a point that does not exist.
- Without the second crossing, a ray to another point crossing just past the
  anchor's own point passes, because the bracket only resolves ~`SLACK` (7%)
  of depth. On #184 case 12352 that invented two points 180 m from any real
  one. Both cases are in `--selftest`.

**Firing-ship box** maps `firing_box(ship box, class margin)` and answers a
later muzzle only inside a pure leaf: outside the box, or in a leaf it could
not prove, the answer is UNKNOWN.

**Target box** locates the points inside `target_box(C, H)` and answers with
the A1 `nearest` rule, but only when no unproven region could hold a point
nearer to the muzzle than the winner's far bound. A region is proven when it
is pure, or when it lies inside the *empty ball* of a queried position (radius
`|c - located point| - r`: nothing is nearer to `c` than what it selects).
Empty balls can never cover a located point itself, so each point also gets a
small pure cube. Leaves are then split query-free (`GEO_DEPTH = 4`) against
those balls; what survives is the unproven set.

### Results

Full run, all 16,712 cases, 2 h 57 min on 4 niced workers.

| method | group | cases | queries | med/p90/max | capped | muzzles | correct | wrong | UNKNOWN | missed | invented | merged | error med/max (m) | radius med/max (m) |
|---|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| firing | close | 3,472 | 45,894 | 10/10/128 | 3 | 2,280 | 2,210 | 0 | 70 | 208 | 0 | 0 | 0.0022 / 0.5 | 0.015 / 1.4 |
| firing | ordinary | 5,208 | 60,424 | 10/10/128 | 2 | 3,518 | 3,460 | 0 | 58 | 440 | 0 | 0 | 0.0081 / 5.7 | 0.057 / 13 |
| firing | boundary | 240 | 21,058 | 88/114/128 | 10 | 398 | 66 | 0 | 332 | 118 | 0 | 0 | 0.0054 / 0.17 | 0.036 / 0.84 |
| firing | stress | 3,472 | 35,981 | 10/10/125 | 0 | 2,330 | 2,318 | 11 | 1 | 336 | 0 | 11 | 0.38 / 160 | 4.1 / 470 |
| firing | artificial | 4,320 | 408,160 | 125/127/128 | 22 | 7,083 | 1,742 | 172 | 5,169 | 5,390 | 20 | 102 | 0.0062 / 3,000 | 0.04 / 5,000 |
| target | close | 3,472 | 84,832 | 18/18/128 | 80 | 2,280 | 2,210 | 0 | 70 | 0 | 0 | 0 | 3.2e-05 / 0.0027 | 0.00019 / 0.0092 |
| target | ordinary | 5,208 | 127,248 | 18/18/128 | 120 | 3,518 | 3,395 | 0 | 123 | 0 | 0 | 0 | 3.2e-05 / 0.0027 | 0.00019 / 0.0092 |
| target | boundary | 240 | 26,656 | 104/128/128 | 80 | 398 | 192 | 0 | 206 | 0 | 0 | 0 | 0.00045 / 0.0027 | 0.0029 / 0.0092 |
| target | stress | 3,472 | 84,832 | 18/18/128 | 80 | 2,330 | 2,286 | 0 | 44 | 0 | 0 | 0 | 3.2e-05 / 0.0027 | 0.00019 / 0.0092 |
| target | artificial | 4,320 | 202,824 | 18/104/128 | 126 | 7,083 | 2,183 | 4,500 | 400 | 2,820 | 0 | 0 | 0.0001 / 0.0042 | 0.00027 / 0.017 |

No duplicate points in any group. Every hidden aimed muzzle was inside the
class-expanded firing box (0 outside, all five groups), so the firing method's
UNKNOWNs are unproven leaves, never an out-of-box muzzle. Target-box UNKNOWNs
that came from an unproven region rather than from `nearest`: close 70 (30
cases), ordinary 123 (48), boundary 194 (85), stress 44 (20), artificial 400
(202).

### Failures, by cause

- **Target box, 4,500 artificial wrong answers, all on the 2,820 cases whose
  synthetic target has an aim point outside the padded box.** The corners
  correctly select the inside point and nothing in the box can observe the
  outside one, so the completeness proof rests on a premise those synthetic
  targets break. On real targets the premise holds (A2 measured it) and the
  method is wrong 0 times in close, ordinary, boundary and stress.
- **Firing box, 11 stress and 172 artificial wrong answers: a merged label.**
  At 20–100 km the 1%-of-depth conditioning limit allows a radius of hundreds
  of metres, which swallows both aim points; the answer names a region holding
  two points, which the scorer counts wrong. No sound threshold exists without
  a known minimum aim-point separation, so this is A4 work.
- **Firing box misses most aim points** (208–5,390 per group): it only ever
  locates what the ship's own box can triangulate, which is the point its
  corners select. That is by design; its answers do not depend on a complete
  set.
- **Boundary is the expensive group for both** (88–128 queries median): the
  ship sits in the bisector plane of the nearest aim-point pair, so leaves
  straddle the cell boundary and never go pure.
- **Query cap.** 37 firing and 486 target runs hit `CAP = 128`. A capped run
  keeps its remaining leaves unproven, so it loses answers, never soundness.

## Open

- **SWI mounts outside the reconstructed ship box** set every class margin. The
  #168 reconstruction was validated on official ships only. If it misses SWI
  hull geometry, fixing it would shrink the ship_l and ship_xl margins. The
  margins stay conservative either way.
- **A4:** the merged-label wrongs at stress range, the boundary-group query
  cost, and whether the target method's unproven regions can be shrunk without
  a large new confirmation system.
