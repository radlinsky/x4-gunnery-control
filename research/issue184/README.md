# Issue #184 aim-point map: A2 benchmark foundation

Offline research, status **inference**. No X4 launch, no production change.
CANNOT BEAR, LINE OF FIRE BLOCKED, range, firing solution and ENGAGEABLE are
out of scope. **The two search methods are not built yet: that is A3.** A2
provides the cases, the hidden truth, the two box inputs and the scorer they
will run against.

```sh
python3 research/issue184/extract_swi_assets.py <SWI 0.9.1 HF mod dir>  # once
python3 research/issue184/aimpoint_map.py             # A2 summary (~11 min)
python3 research/issue184/aimpoint_map.py --selftest  # ~45 s
```

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
paired, which also keeps size classes compatible: no pair falls outside the A1
class size set. Source rule: an official ship takes official turrets only; an
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

**Firing-ship box**, `firing_box(ship box, A1 class margin)`, tested in the
ship frame:

| group | inside | outside |
|---|---:|---:|
| close | 2,274 | 6 |
| ordinary | 3,510 | 8 |
| boundary | 398 | 0 |
| stress | 2,330 | 0 |
| artificial | 7,057 | 26 |

The misses break A1's assumption that every mount lies inside the runtime ship
box. As currently measured (the attached turret-frame origin on the mount),
173 of the 5,442 mounts do not: 159 SWI and 14 official (12 XL, 2 L). The worst
is 540.48 m outside (SWI Providence carrier `con_m_turret_left-pdls_5`), then
327 m (SWI ISD). 14 mounts lie farther outside than their whole class margin.
See **Open**.

**Target box**, `target_box(C, H)`: the runtime box plus `TARGET_PAD_Y =
8.86 m` on +Y only. 68 of 217 targets have an aim point above their box, and
none is outside it in any other direction. The worst is
`turret_kha_m_beam_01_mk1`, which needs 8.85 m.

| rule | covers all | search-volume growth |
|---|---|---|
| proportional scale 3.57× | yes | ×45.6 for every target |
| +Y pad 8.86 m | yes | median ×2.72, max ×11.48 |

The +Y pad is carried forward. The target-box search itself is A3 work.

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

## Open

- **SWI mounts outside the reconstructed ship box.** The #168 box
  reconstruction was validated on official ships only. Up to 540 m of mount
  excursion on SWI capital ships suggests it misses SWI hull geometry. It is
  also possible those ships really mount turrets on outriggers. Until that is
  resolved, the firing-ship method either needs a margin that also covers
  mount-outside-box, or must return UNKNOWN for those ships. That choice is
  A3/A4 work; A2 only measures it.
- **A3:** the discovery searches: 8 box corners first, then only the queries
  that add information, reusing the #176 ray-location and confirmation code.
  The target-box method also needs its rule for when a discovered set is
  complete enough.
