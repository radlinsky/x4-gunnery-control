# Selected-target CLEAR LINE OF FIRE benchmark findings (#202)

Status: **OFFLINE inference**. Production MD unchanged since `cf459d0`; X4 9.00 build 611726
(`X4.exe` SHA-256 `19750a65…6ad6891` re-verified 2026-09-25). No new LIVE evidence. Simulated query
counts are `check_line_of_sight` calls, not frame cost.

## What changed

The earlier benchmark scored each method against the line **that method tested**, on hand-written
hit lists. That cannot tell whether the answer matches what the turret will actually hit. The
source of truth is now the **settled shot**: the shot a turret fires after it has turned toward
the selected target and stopped, traced through real X4 collision geometry (`settled.py`,
`geometry.py`). The current and seven-point methods are predictions of that shot, scored from the
pre-turn ("parked") muzzle and from the settled muzzle against the same truth.

The hand-written scenes stay in `benchmark.py` as **decision-rule regression tests** (membership,
blocker categories, guidance, zone, mutants). They are outside every accuracy total below.

## Method

**Scene: the #202 LIVE ships.**

- Firing ship: the Boron Ray, `ship_bor_l_destroyer_01`, with its 14 real turret mounts. The 12 M
  mounts carry `turret_bor_m_railgun_02_mk1` (1 endpoint) and the 2 L mounts
  `turret_bor_l_disruptor_01_mk1` (3 endpoints), as in the LIVE run.
- Target: an Osaka, `ship_ter_l_destroyer_01`, with a **stated** Terran loadout on all 34 mounts:
  M/L laser turrets, M/L standard shields, L all-round engines. The LIVE Osaka had a random
  level-1.0 loadout that was not logged.
- One shared obstacle per scene: the second Osaka.
- Three arrangements (Ray frame): the LIVE fixture (±900 m, 3.5 km ahead), a screened one (the other
  Osaka partly between), and high on the starboard beam. Four Osaka yaws each. Two starting yaws:
  parked at 0, and at rest after a target astern.
- 11,760 tests: 14 turrets × 35 targets (hull + 34 elements) × 3 arrangements × 4 yaws × 2 starts.
  Run time 5 min, one niced process.

**Geometry, from the installed catalogs.**

- X4's geometry loader (`0x140F51360`) loads a `-mesh` and a `-hull` Jolt shape per part (geometry
  `+0x20`/`+0x28`) plus the `-collision` XMF. Which one the layer-3 ray body uses was not traced.
  Every ray is therefore cast twice:
  - **MESH**: the `-collision.xmf` triangles, two-sided;
  - **HULL**: the `-hull.jcs` convex pieces, solid. The Ray hull has 128 pieces and the Osaka 256.
  Truth requires both to agree.
- Layer-3 part filter: skip `nocollision`, `triggerpart` and `platformcollision`. On both Boron
  turrets **the rotator, gun and barrel are `nocollision`**, so a turret's only layer-3 mesh is its
  fixed socket, and no moving turret mesh needs posing. The ships' only colliding hull part is
  `part_main`; the Ray's dock area adds 8 triangles.

**Bearing and settling.**

- CAN BEAR comes from the accepted #176 scorer on the aim point. The aim point is the element's
  nearest authored aim target from the turret origin (native selector), or its box centre. The
  Osaka hull has no authored aim target, so its aim point is the box centre.
- Settling uses the #166 yaw gate. From rest at the starting yaw, the mover moves toward sign(g)
  and stops at the first attractor that way. A trap, a repeller start, or a settled yaw whose
  pitch is out of arc is UNKNOWN. The favorable rest is never picked. `check_settling()` asserts
  this on the #166 KB's two-rest geometry: from yaw ±3.0 it reaches 0, and only a start at π stays
  at −π.

**Truth.** Each per-shot endpoint fires along its own +Z at the settled pose. For the disruptor,
`barrelposition` is `con_laser_02`, then `_03`, `_01` in native hash order. The first hit, ignoring
only the firing turret's own meshes (as the native pre-fire gate does), is scored with the #202
membership rules. The row is excluded as UNKNOWN when:

- the MESH and HULL models disagree;
- the same barrel's line straight through the aim point disagrees (a **grazing shot**: the barrel's
  ~0.3 m offset from the aim line decides it, which spread would not respect);
- the barrels disagree.

**Candidates.** The unchanged `benchmark.candidate()` code is fed the physical first hit of each
tested segment: `current`, `seven`, `lazy` and `eight` (seven plus the old centre, tried last).

## Truth and exclusions

| truth | engine | hull | shield | turret | total |
|---|---:|---:|---:|---:|---:|
| **CLEAR** | 230 | 240 | 824 | 1,856 | **3,150** |
| **NOT CLEAR** | 358 | 56 | 3,840 | 1,858 | **6,112** |
| CANNOT BEAR (excluded) | 80 | 40 | 754 | 518 | 1,392 |
| grazing shot (excluded) | 0 | 0 | 706 | 60 | 766 |
| shape models disagree (excluded) | 4 | 0 | 258 | 76 | 338 |
| barrels disagree (excluded) | 0 | 0 | 2 | 0 | 2 |
| trap, repeller start, rest out of arc, scorer UNKNOWN | 0 | 0 | 0 | 0 | 0 |

9,262 tests are scored. What the 6,112 NOT CLEAR shots hit first:

- the target Osaka's hull (2,412) or a sibling element (1,668): the element faces away or sits
  behind structure;
- the firing Ray's own hull (1,724);
- a sibling Ray turret socket (308);
- nothing: none. The 262 shield shots that missed everything before the grazing rule were all
  grazing, and are excluded.

## Accuracy against the settled shot (MESH; binary scoring)

BLOCKED and UNKNOWN count as "not clear". UNKNOWN is also shown on its own. Positive means CLEAR.

| method | phase | TP | FP | TN | FN | UNKNOWN (of which truth CLEAR) | mean calls |
|---|---|---:|---:|---:|---:|---:|---:|
| current | parked | 1,784 | 35 | 6,077 | 1,366 | 1,590 (575) | 2.58 |
| current | settled | 2,008 | 16 | 6,096 | **1,142** | 292 (292) | 2.53 |
| seven | parked | 2,792 | 146 | 5,966 | 358 | 1,317 (309) | 13.22 |
| **seven** | **settled** | **3,150** | **112** | **6,000** | **0** | **0** | 12.66 |
| lazy | parked | 2,792 | 146 | 5,966 | 358 | 1,317 (309) | 7.82 |
| **lazy** | **settled** | 3,150 | 112 | 6,000 | 0 | 0 | **6.20** |
| eight | settled | 3,150 | 112 | 6,000 | 0 | 0 | 14.59 |

- **HULL model sensitivity.** The same table on the HULL shapes gives:
  - seven settled: TP 3,150, FP 68, FN 0;
  - current settled: FN 1,180.

  The conclusions do not depend on the shape model.
- **Hull targets (240 CLEAR / 56 NOT).** current and seven are the same method, and both score
  every hull row correctly from the settled muzzle. All the difference is on element targets
  (8,966 scored rows).
- **Aim probe alone** (settled, 1 call): TP 2,794, FP 0, FN 116. The six box points turn those
  116 FN into TP at the price of 112 FP.

**Where the errors come from.**

- **current FN (1,142).**
  - 614 turret and 88 shield rows: the centre line hits the Osaka hull first;
  - 126 turret and 22 shield rows: the centre line hits a sibling element first;
  - 176 turret and 116 engine rows: the centre line misses (UNKNOWN), because the centre is inside
    a hollow.
- **seven FP (112).** A side point of the element's box is visible, but the turret aims at X4's aim
  point, and that shot hits the parent hull (52), a sibling element (56), the Ray's hull (2) or a
  sibling socket (2). The method answers
  "part of this element is straight-line reachable", which is weaker than "the settled shot lands".
- **seven FN: none** after grazing rows are excluded. It had 56 before the grazing rule, all
  sub-metre cases.

## Parked versus settled muzzle

Same rows, same truth, MESH:

| method | FN eliminated by settling | FN introduced | FP eliminated | FP introduced |
|---|---:|---:|---:|---:|
| current | 226 | 2 | 21 | 2 |
| seven / lazy / eight | 358 | 0 | 52 | 18 |

From the parked muzzle, the seven-point scan reads UNKNOWN on 1,317 rows, 309 of them truly
CLEAR. Every one of the 1,317 has reason `self`: the line from the parked barrel crosses the turret's
own socket. That clears once the turret has turned. A result taken before the turret has turned
toward the selection is the main remaining source of seven-point false negatives.

## Starting state and multiple rests

At these ranges (≥ 2 km), every settled yaw was state-independent. Parked and astern starts settled
at the same yaw in all pairs, so the starting yaw changed only the parked-phase origin. No trap or
several-rest case occurred. The rule for choosing between rests is implemented and checked
(`check_settling`), but this population never exercises it. It matters only for targets within a
few metres of a turret pivot.

## barrelposition versus per-shot firing points

On the 1,192 robust disruptor rows, barrel 0 (`barrelposition`) was CLEAR while another barrel was
not in 2 rows, and never the reverse. Before the grazing rule this was 108 / 18, all of them within
the 0.34 m barrel spread. At 2–4 km, a 3-barrel L turret's barrels do not disagree except on
grazing shots. `barrelposition` is an adequate origin for this question.

## Eighth point (the old centre)

Adding the centre after the seven points changed **no status** in either phase, and costs 3 more
calls (median 22 against 19). The regression boundary in the decision-rule tests
(`only-centre-clear`) never occurs physically here. Do not add it.

## Query cost (simulated calls, settled turrets)

| method | per turret median / p90 / max | 14-turret pass median / max |
|---|---|---|
| current | 3 / 3 / 3 | 27 / 42 |
| seven (eager) | 19 / 19 / 19 | 171 / 266 |
| **seven (lazy)** | **9 / 9 / 9** (settled), 9 / 19 / 19 (parked) | **81 / 126** (settled), 81 / 186 (parked) |
| eight | 22 / 22 / 22 | 198 / 308 |

The median is high because most selected elements are genuinely NOT CLEAR, and those pay for every
point. Lazy classification never changed a status. From the settled muzzle a lazy failure always
costs 9 calls, because the first classification finds a real blocker. The #202 LIVE figure of a
42-call pass taking a 184 ms median (one turret per frame) is not ray cost. The frame cost of a
126-call pass remains unmeasured.

## Reassessments

**#202 Osaka 0/14.** In the fixture arrangement, **20 element/orientation pairs** reproduce the LIVE
signature:

- current reads 0–2/14;
- for the turret elements, the centre line's first hit is the Osaka hull or a neighbouring
  element, giving Q(T) false, Q(Z) true, Q(W) false, i.e. BLOCKED, exactly as logged;
- 7–13 turrets' settled shots land on the element;
- seven reads 10–13/14 there.

On the Terran M laser turret element:

- the box contains only the socket, since the rotator and gun are `nocollision`;
- its centre is 1.5 m above the mount;
- from the Ray the line to it meets hull structure 44–58 m short;
- the authored aim point 5.4 m up, where X4 aims, is visible.

For engines the centre sits in the hollow nozzle, and the line reads UNKNOWN (miss) instead.

This supports the witness hypothesis "centre occluded, aim point clear" with source geometry. It is
**not LIVE-proven**: the LIVE loadout, Osaka orientation and the type of `0x17c090` were not logged.
The per-turret logging planned in #202 task 2 would settle it.

**#60 Xenon Defence Platform 0/14.** Built from the shipped `xen_defence` plan with the real module
meshes. The root `useaimtarget` endpoint, the live union-box centre, is at (0, −319, 0): in open
space below the hub, inside no module under either model. Of 200 lines from 4 km toward it, 106
(MESH) or 105 (HULL) reach it without touching any module. The old root probe returns false there
whatever the module-to-root link does. The other half first hit a module, and read CLEAR only if
that link works.

The "centre gap" explanation is therefore physically real for about half of all approach
directions. It is not LIVE-proven for #60, whose firing geometry was not retained. The link-null
and cross-zone hypotheses are not excluded. The current module-declared method does not use this
endpoint.

## Decision-rule regression tests (`benchmark.py`, `runtime.lua`)

Unchanged in substance.

- The drift signature against `md/x4_gunnery_control.xml` passes, all 9 mutants are killed, and
  integrity is PASS.
- The standing rule FAIL remains: **missing missile guidance becomes unguided** (production checks
  only for absent ammunition; #202 requires UNKNOWN).
- `runtime.lua`: 13 CODE checks pass. The 2 SPEC rows (#202 task 3: GUIDED in the count, ASCII
  colon) fail as expected. There are 2 NOTEs (stale `Clear.text` window; one silent turret keeps
  "scanning").
- **GUIDED** stays separate. The Ray carries no missile turret, so the physical set has 0 GUIDED
  rows. GUIDED behavior is covered only by the decision-rule tests, and needs no ray.

## Evidence gaps

1. Which Jolt shape (`-mesh.jcs` or `-hull.jcs`) the layer-3 body uses, and XPhys's back-face and
   solid-convex settings. Handled by requiring agreement; 338 rows are excluded.
2. The shoot controller's aim point for elements (`LargeTargetShootController`), the selector's
   origin, and projectile spread and lead. Handled by the grazing rule; 766 rows are excluded.
3. Which endpoint the native pre-fire gate casts from per shot.
4. The LIVE Osaka loadout and orientation, and the type of `0x17c090`.
5. Part offsets are ignored (the #167 box rule) and animated parts stay in their default pose.
6. Station plan identity and firing geometry for #60.
7. Frame cost of a 126-call pass.
8. Earlier rule gaps still open: missing guidance, docked craft membership, wrecked modules, a
   module dying mid-pass.

## Recommendation for the mod

The lazy seven-point scan is the right method. It should be read from a turret that is aimed at
the selection. Across 9,262 scored settled shots on real geometry, it produced:

- 0 false negatives and 0 UNKNOWN;
- 1.8% false CLEAR (112 of 6,112 truly NOT CLEAR rows);
- 81 calls per 14-turret pass at the median.

The current centre ray missed 36% of truly CLEAR turrets (1,142 of 3,150). Parked-muzzle results
should be treated as provisional, because the turret's own socket blocks many of their lines. Do
not add the eighth point.
