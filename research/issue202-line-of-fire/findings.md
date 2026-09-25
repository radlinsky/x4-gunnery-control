# Selected-target CLEAR LINE OF FIRE benchmark findings (#202)

Status: **OFFLINE inference**. Production MD unchanged since `cf459d0`; X4 9.00 build 611726
(`X4.exe` SHA-256 `19750a65…6ad6891` re-verified 2026-09-25). No new LIVE evidence. Simulated query
counts are `check_line_of_sight` calls, not frame cost.

## What the benchmark measures

The question is CLEAR LINE OF FIRE for the selected target: once a turret has turned toward the
target and settled, is the straight path from its firing origin to the point it is bearing on
unobstructed up to the target?

- **Truth** is that path. It runs from the **settled `barrelposition`** to the **X4 aim point the
  turret bears toward**, traced through real X4 collision geometry (`settled.py`, `geometry.py`).
- **Predictions** are the current and seven-point methods, each run from the pre-turn ("parked")
  muzzle and from the settled muzzle, and scored against that same truth.
- **The hand-written scenes** stay in `benchmark.py` as **decision-rule regression tests**
  (membership, blocker categories, guidance, zone, mutants). They are outside every accuracy total.

This replaces the previous truth, which followed each barrel's +Z projectile line and excluded
"grazing" and barrel-disagreement rows. That answered an impact-prediction question, not a line-of-
fire one. The projectile lines are now only a diagnostic, and they never define or exclude a row.

## Method

**Scene: the #202 LIVE ships.**

- Firing ship: the Boron Ray, `ship_bor_l_destroyer_01`, with its 14 real turret mounts. The 12 M
  mounts carry `turret_bor_m_railgun_02_mk1` and the 2 L mounts `turret_bor_l_disruptor_01_mk1`, as
  in the LIVE run.
- Target: an Osaka, `ship_ter_l_destroyer_01`, with a **stated** Terran loadout on all 34 mounts:
  M/L laser turrets, M/L standard shields, L all-round engines. The LIVE Osaka had a random
  level-1.0 loadout that was not logged.
- One shared obstacle per scene: the second Osaka.
- Three arrangements (Ray frame): the LIVE fixture (±900 m, 3.5 km ahead), a screened one (the other
  Osaka partly between), and high on the starboard beam. Four Osaka yaws each. Two starting yaws:
  parked at 0, and at rest after a target astern.
- 11,760 tests: 14 turrets × 35 targets (hull + 34 elements) × 3 arrangements × 4 yaws × 2 starts.
  About 6 min, one niced process.

**Geometry, from the installed catalogs.**

- X4's geometry loader (`0x140F51360`) loads a `-mesh` and a `-hull` Jolt shape per part (geometry
  `+0x20`/`+0x28`) plus the `-collision` XMF. Which shape the layer-3 ray query uses was not traced,
  so every path is cast against both:
  - **MESH**: the `-collision.xmf` triangles, two-sided;
  - **HULL**: the `-hull.jcs` convex pieces, solid. The Ray hull has 128 pieces and the Osaka 256.
- Layer-3 part filter: skip `nocollision`, `triggerpart` and `platformcollision`. On both Boron
  turrets **the rotator, gun and barrel are `nocollision`**, so a turret's only layer-3 mesh is its
  fixed socket. The ships' only colliding hull part is `part_main`; the Ray's dock area adds 8
  triangles.

**Truth, per test.**

1. **Aim point.** X4's selected aim point for the target: the element's nearest authored aim target
   from the turret origin (native selector), else the box centre. Every element in this loadout
   authors exactly one aim point, and the Osaka hull none, so it uses its box centre.
2. **CAN BEAR.** The accepted #176 scorer, on that aim point.
3. **Settling.** The #166 yaw gate, from rest at the starting yaw. The mover moves toward sign(g) and
   stops at the first attractor that way; the favorable rest is never picked. `check_settling()`
   asserts this on the #166 KB's two-rest geometry: from yaw ±3.0 it reaches 0, and only a start at
   π stays at −π.
4. **The path.** The segment from the settled `barrelposition` (endpoint element 0) to that same aim
   point. The firing turret's own meshes are ignored, as X4's pre-fire gate ignores them.
5. **Classification.** The first hit is scored with the #202 membership rules: a target member is
   CLEAR, anything else NOT CLEAR.

**Candidates.** The unchanged `benchmark.candidate()` code is fed the physical first hit of each
tested segment: `current`, `seven`, `lazy` and `eight` (seven plus the old centre, tried last).
The first `useaimtarget=true` probe is also reported on its own.

## Truth and exclusions

| truth | engine | hull | shield | turret | total |
|---|---:|---:|---:|---:|---:|
| **CLEAR** | 114 | 240 | 1,390 | 1,870 | **3,614** |
| **NOT CLEAR** | 358 | 56 | 3,900 | 1,908 | **6,222** |
| cannot bear the aim point (excluded) | 80 | 40 | 754 | 518 | 1,392 |
| shape models disagree (excluded) | 120 | 0 | 340 | 72 | 532 |
| settling not established: trap, repeller start, rest out of arc, scorer UNKNOWN | 0 | 0 | 0 | 0 | 0 |
| aim path reaches no geometry (no first hit to classify) | 0 | 0 | 0 | 0 | 0 |

9,836 tests are scored. Each exclusion is a line-of-fire reason:

- **Cannot bear the aim point (1,392).** The turret cannot point at X4's aim point, so no settled
  path exists to test. These are mostly mounts facing away from the Osaka.
- **Shape models disagree (532).** The answer depends on which X4 collision shape the ray query
  uses, which was not traced:
  - 350 are element-versus-parent boundaries, where a convex hull piece of the Osaka or the Ray
    bulges over, or falls short of, a shield or turret mounted flush on the hull;
  - 116 are engines, where the MESH path ends inside the hollow nozzle with no hit and the solid
    HULL engine is hit;
  - 66 involve the firing Ray's own hull.
- **Settling not established (0).** Every turret that could bear settled at a single state-
  independent rest.
- **No geometry (0).** Every aim path hit something before the aim point.

What the 6,222 NOT CLEAR paths hit first:

- the target Osaka's hull (2,494) or a sibling element (1,690);
- the firing Ray's own hull (1,730);
- a sibling Ray turret socket (308).

## Accuracy against the settled line of fire

MESH shape model. BLOCKED and UNKNOWN count as "not clear"; UNKNOWN is also shown on its own.

| method | phase | TP | FP | TN | FN | UNKNOWN (of which truth CLEAR) | mean calls |
|---|---|---:|---:|---:|---:|---:|---:|
| current | parked | 2,144 | 39 | 6,183 | 1,470 | 1,578 (548) | 2.54 |
| current | settled | 2,432 | 20 | 6,202 | **1,182** | 176 (176) | 2.48 |
| seven | parked | 3,178 | 160 | 6,062 | 436 | 1,407 (385) | 12.82 |
| **seven** | **settled** | **3,614** | **130** | **6,092** | **0** | **0** | 12.15 |
| lazy | parked | 3,178 | 160 | 6,062 | 436 | 1,407 (385) | 7.65 |
| **lazy** | **settled** | 3,614 | 130 | 6,092 | 0 | 0 | **5.96** |
| eight | settled | 3,614 | 130 | 6,092 | 0 | 0 | 13.99 |
| `useaimtarget` probe alone | parked | 3,177 | 49 | 6,173 | 437 | — | 1 |
| **`useaimtarget` probe alone** | **settled** | **3,614** | **0** | **6,222** | **0** | — | **1** |

- **HULL model sensitivity.** The HULL table gives:
  - seven settled: TP 3,614, FP 72, FN 0;
  - current settled: FN 1,372;
  - probe settled: exact again.

  The conclusions do not depend on the shape model.
- **Hull targets (240 CLEAR / 56 NOT).** current and seven are the same method, and both score
  every hull row correctly from the settled muzzle. All the difference is on element targets
  (9,540 scored rows).

**The `useaimtarget` probe.** After the turret has settled, the probe traces nearly the same segment
as the truth: the same origin to the same aim point. It matches the truth on all 9,836 rows, under
both shape models. The two differ in only two ways, and neither occurred:

- the probe also sees the firing turret's own socket;
- the probe selects its aim point from the muzzle rather than the turret origin, which matters only
  for targets with several aim points (none here).

From the parked muzzle, the probe's 486 mismatches all come from the different origin:

- 385 truly CLEAR rows where the path crosses the turret's own socket;
- 47 rows where it crosses the Ray's hull, 3 a sibling socket, and 2 the Osaka hull;
- 49 truly NOT CLEAR rows that reach the element only from the parked position.

**Errors of the methods (settled muzzle).**

- **current FN (1,182).** The box-centre line is blocked, or misses, while the aim-point path is
  clear:
  - 624 turret and 194 shield rows: the centre line hits the Osaka hull first;
  - 130 turret and 58 shield rows: it hits a sibling element first;
  - 176 turret rows: it misses (UNKNOWN).
- **seven FP (130).** The aim probe fails, but one of the six box points is reachable while the path
  to X4's aim point is blocked. The blocker is:
  - the Osaka hull (54);
  - a sibling element (72);
  - the Ray's hull (2);
  - a sibling socket (2).

  The six points answer "part of this element is straight-line reachable", which is broader than
  the aim-point line of fire.
- **seven FN: none.** When the aim-point path is clear, the first probe finds it.

## Parked versus settled muzzle

Same rows, same truth, MESH:

| method | FN eliminated by settling | FN introduced | FP eliminated | FP introduced |
|---|---:|---:|---:|---:|
| current | 290 | 2 | 21 | 2 |
| seven / lazy / eight | 436 | 0 | 53 | 23 |

From the parked muzzle, the seven-point scan reads UNKNOWN on 1,407 rows, 385 of them truly CLEAR.
All 1,407 have reason `self`: the line from the parked barrel crosses the turret's own socket. That
clears once the turret has turned. A result taken before the turret has turned toward the selection
is the only remaining source of seven-point false negatives.

## Starting state and multiple rests

At these ranges (≥ 2 km), every settled yaw was state-independent. Parked and astern starts settled
at the same yaw in all pairs, so the starting yaw changed only the parked-phase origin. No trap or
several-rest case occurred. The rule for choosing between rests is implemented and checked
(`check_settling`), but this population never exercises it.

## Diagnostic only: settled +Z projectile paths

This is a different question (where a round flies), and it neither defines nor excludes any row.

- On the 9,836 scored rows, barrel 0's +Z path disagrees with the line-of-fire truth in 530 (5.4%).
  These are mostly shots that pass the aim point by the barrel's ~0.3 m offset from the bore.
- On the 1,318 disruptor rows, another barrel's +Z path disagrees with barrel 0 in 132.

Spread, lead and barrel cycling are outside this benchmark.

## Eighth point (the old centre)

Adding the centre after the seven points changed **no status** in either phase, and costs 3 more
calls (median 22 against 19). Do not add it.

## Query cost (simulated calls, settled turrets)

| method | per turret median / p90 / max | 14-turret pass median / max |
|---|---|---|
| current | 3 / 3 / 3 | 27 / 42 |
| seven (eager) | 19 / 19 / 19 | 171 / 266 |
| **seven (lazy)** | **9 / 9 / 9** (settled), 9 / 19 / 19 (parked) | **81 / 126** (settled), 81 / 186 (parked) |
| eight | 22 / 22 / 22 | 198 / 308 |

The median is high because most selected elements are genuinely NOT CLEAR, and those pay for every
point. A CLEAR aim probe costs 1 call. Lazy classification never changed a status. The #202 LIVE
figure of a 42-call pass taking a 184 ms median (one turret per frame) is not ray cost. The frame
cost of a 126-call pass remains unmeasured.

## Reassessments

**#202 Osaka 0/14.** In the fixture arrangement, **18 element/orientation pairs** reproduce the LIVE
signature:

- current reads 0–2/14;
- the centre line's first hit is the Osaka hull or a neighbouring element, giving Q(T) false,
  Q(Z) true, Q(W) false, i.e. BLOCKED, exactly as logged. On the L turret, the line misses instead;
- 7–13 turrets have a truly clear settled line of fire;
- seven reads 10–13/14 there.

On the Terran M laser turret element:

- the box contains only the socket, since the rotator and gun are `nocollision`;
- its centre is 1.5 m above the mount;
- from the Ray the line to it meets hull structure 44–58 m short;
- the authored aim point 5.4 m up is visible.

This supports the witness hypothesis "centre occluded, aim point clear" with source geometry. It is
**not LIVE-proven**: the LIVE loadout, Osaka orientation and the type of `0x17c090` were not logged.

**#60 Xenon Defence Platform 0/14.** Built from the shipped `xen_defence` plan with the real module
meshes. The root `useaimtarget` endpoint, the live union-box centre, is at (0, −319, 0): in open
space below the hub, inside no module under either model. Of 200 lines from 4 km toward it, 106
(MESH) or 105 (HULL) reach it without touching any module, and read false whatever the
module-to-root link does. The other half read CLEAR only if that link works.

The "centre gap" is physically real for about half of all directions. It is not LIVE-proven for #60,
whose firing geometry was not retained, and link-null and cross-zone are not excluded.

## Decision-rule regression tests (`benchmark.py`, `runtime.lua`)

Unchanged.

- The drift signature against `md/x4_gunnery_control.xml` passes, all 9 mutants are killed, and
  integrity is PASS.
- The standing rule FAIL remains: **missing missile guidance becomes unguided**.
- `runtime.lua`: 13 CODE checks pass. The 2 SPEC rows (#202 task 3: GUIDED in the count, ASCII
  colon) fail as expected. There are 2 NOTEs.
- **GUIDED** stays separate. The Ray carries no missile turret, so the physical set has 0 GUIDED
  rows. GUIDED behavior is covered only by the decision-rule tests.

## Evidence gaps

1. Which Jolt shape (`-mesh.jcs` or `-hull.jcs`) the layer-3 query uses, and XPhys's back-face and
   solid-convex settings. Handled by requiring agreement; 532 rows are excluded.
2. The shoot controller's aim point for elements (`LargeTargetShootController`) and the selector's
   origin. This benchmark assumes the #184 nearest-authored-point selector.
3. The LIVE Osaka loadout and orientation, and the type of `0x17c090`.
4. Part offsets are ignored (the #167 box rule) and animated parts stay in their default pose.
5. Station plan identity and firing geometry for #60.
6. Frame cost of a 126-call pass.
7. Earlier rule gaps still open: missing guidance, docked craft membership, wrecked modules, a
   module dying mid-pass.

## Recommendation for the mod

The lazy seven-point scan is the right method, read from a turret that is aimed at the selection.
On 9,836 settled rows on real geometry it produced:

- 0 false negatives and 0 UNKNOWN;
- 2.1% false CLEAR (130 of 6,222 truly NOT CLEAR rows), all from the six box points;
- 81 calls per 14-turret pass at the median.

The current centre ray missed 33% of truly CLEAR turrets (1,182 of 3,614). After settling, the first
`useaimtarget` probe matched the truth exactly, in one call.

On this population the six box points added only false CLEARs:

- 130 settled;
- 111 more than the probe alone when parked, where they recovered a single false negative.

They would matter only where the aim-point path reaches no geometry (a hidden or off-mesh aim
point), and this population had none. Keeping them is therefore a product choice this benchmark
cannot settle. Parked results remain provisional because the turret's own socket blocks many of
their lines. Do not add the eighth point.
