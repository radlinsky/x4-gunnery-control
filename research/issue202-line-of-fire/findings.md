# Selected-target CLEAR LINE OF FIRE benchmark findings (#202)

Status: **OFFLINE inference**. Production MD unchanged since `cf459d0`. X4 9.00 build 611726, `X4.exe`
SHA-256 `19750a65…6ad6891`, re-verified 2026-09-25. No new LIVE evidence. Call counts are simulated
`check_line_of_sight` calls, not frame cost. The full report is `settled.py --report`; numbers below are
MESH unless stated.

**2026-09-26:** "X4 pre-fire permission" below is the current truth and comparison
(`permission.py`, `X4.exe` SHA-256 re-verified). Every later section scores the older truth, the first
hit on the settled path by membership. It treated a path that reaches no geometry as undefined, and it
treated a beam like any other turret.

## X4 pre-fire permission

**Truth** is X4's own pre-fire obstruction decision for the settled turret, with every other firing
requirement assumed met. It is permission, not a launch or a hit. It comes from the native trace in the KB
(`weapon-path-obstruction-groups.md`, "Blocker categories" and "Beam ammunition casts along the barrel"),
and the firing turret's own meshes are ignored, as X4 does.

- **Non-beam turrets** cast from the muzzle to `muzzle + f × (bearing point − muzzle)`.
  - `f = 1 + min(1.1 R, 500) / R` against a whole ship or a ship engine; `f = 1` otherwise.
  - The turret fires when the ray hits nothing, the target, or one of its descendants.
  - A first hit on the element's own parent or sibling (result 0, surface elements only) sends a second
    ray to the element's origin. That ray must hit exactly the element.
  - Any other first hit withholds fire.
- **Beam turrets** (`kha_m_beam_01`, the only beam here) cast along the barrel for max fire range
  `R`. They fire only when the first hit is the target or a descendant. **A miss withholds fire.**
- **Guided** missile turrets skip the check.
- `R` per turret is the bullet's `range`, else speed × lifetime, or the missile's `range`. This is a
  source census, not the native getter. It only sets the beam length and `f`.

**Candidates** see what `check_line_of_sight` sees, including the firing turret's own socket:

- **current**: production at `cf459d0`. It tests box-centre endpoints, and for a station root the two
  nearest modules.
- **base**: the fresh-muzzle `useaimtarget=true` probe, then step and look back.
  - BLOCKED is claimed only when `Q(Z)` is true and `Q(W)` false on the muzzle-to-step stretch, and that
    first hit is neither a target member nor the element's own parent or sibling.
- **base+modules**: base, then current's module lines whenever base is undecided on a station root. This
  is the owner's hypothesis.
- **base+ext**: base, then the aimed line continued along the `create_orientation useaimtarget` direction
  `u` to 30 km. It starts from the muzzle, or from the step point when the look-back proved the socket.
  - CLEAR when `Q(T)` finds a target member on it.
  - CLEAR when a sector-declared check finds nothing at all (a genuine miss).
  - Otherwise UNKNOWN.
  - A beam skips the probe. `Q(W)` (plus the look-back), then `Q(T)` on the line to `R`, decide CLEAR or
    BLOCKED.

The bare `useaimtarget` probe alone is no longer compared.

Predicted CLEAR = TP + FP; predicted BLOCKED = TN + FN; UNKNOWN is split by truth and is never counted as
correct. Excluded = cannot bear; uncertain = no defensible truth (below).

**Station roots, broad population** (420 tests: 224 scored, 12 GUIDED, 184 cannot bear; MESH = HULL
except current):

| method | TP | FP | TN | FN | U on PERMIT | U on NOT | mean / max calls |
|---|---:|---:|---:|---:|---:|---:|---:|
| current | 108 | 50 (HULL 52) | 10 | 0 | 54 | 2 (HULL 0) | 2.49 / 6 |
| base | 84 | 20 | 12 | 0 | 78 | 30 | 2.54 / 4 |
| base+modules | 134 | 48 | 12 | 0 | 28 | 2 | 3.75 / 10 |
| **base+ext** | **162** | **0** | **62** | **0** | **0** | **0** | 3.22 / 6 |

**The 108 previously excluded empty-path rows** (72 `arg_shipyard`, 36 `xen_defence`). Truth: 78 PERMIT
(non-beam: a genuine miss) and 30 NOT (the beam: no station hit along its barrel within `R`).

| method | TP | FP | TN | FN | U on PERMIT | U on NOT | mean / max calls |
|---|---:|---:|---:|---:|---:|---:|---:|
| current | 50 | 28 | 2 | 0 | 28 | 0 | 2.50 / 6 |
| base | 0 | 0 | 0 | 0 | 78 | 30 | 3.26 / 4 |
| base+modules | 50 | 28 | 0 | 0 | 28 | 2 | 5.76 / 10 |
| **base+ext** | **78** | **0** | **30** | **0** | **0** | **0** | 4.43 / 6 |

- current and base+modules read CLEAR on 28 of the 30 beam rows, from a module line that is not the
  line X4 tests. Their U on PERMIT is `arg_m_dumbfire_02`, whose socket is the module lines' first hit.
- base+ext: 28 `arg_m_dumbfire_02` rows are CLEAR from the step point, and the other 50 non-beam rows
  from the muzzle. All 30 beam rows are BLOCKED.

**#60 representative `xen_defence` poses** (1,344 tests: 796 scored, 548 cannot bear; truth 728 PERMIT,
of which 140 are genuine misses and 238 hit a module past the centre, and 68 NOT):

| method | TP | FP | TN | FN | U on PERMIT | mean / max calls |
|---|---:|---:|---:|---:|---:|---:|
| current | 702 (HULL 706) | 10 (14) | 58 (54) | 26 (22) | 0 | 1.57 / 6 |
| base | 350 | 0 | 68 | 0 | 378 | 2.12 / 3 |
| base+modules | 716 | 0 | 68 | 0 | 12 | 2.69 / 9 |
| **base+ext** | **728** | **0** | **68** | **0** | **0** | 2.77 / 5 |

**Other target classes, broad population, MESH** (station surfaces are exact-element targets; they are not
part of the station-root membership):

| class (scored) | method | TP | FP | TN | FN | U on PERMIT | U on NOT | mean / max |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| station surface (840) | current | 106 | 60 | 398 | 0 | 112 | 164 | 2.54 / 3 |
| | base | 162 | 62 | 2 | 0 | 56 | 558 | 2.86 / 4 |
| | base+ext | 188 | 0 | 220 | 0 | 30 | 402 | 3.68 / 6 |
| whole ship (1,560) | current | 860 | 30 | 128 | 12 | 482 | 48 | 1.74 / 3 |
| | base | 1,354 | 20 | 132 | 0 | 0 | 54 | 1.84 / 4 |
| | base+ext | 1,354 | 0 | 154 | 0 | 0 | 52 | 2.01 / 6 |
| ship surface (13,578) | current | 3,002 | 24 | 7,960 | 1,130 | 606 | 856 | 2.53 / 3 |
| | base | 4,558 | 14 | 2,264 | 0 | 180 | 6,562 | 2.46 / 4 |
| | base+ext | 4,732 | 2 | 2,818 | 0 | 6 | 6,020 | 3.27 / 6 |

base+modules equals base off station roots.

**What the numbers say:**

1. **Every remaining false CLEAR of base, and of base+modules outside the empty path, is the beam.** The
   `useaimtarget` endpoint can lie past `R`, where X4's barrel ray stops. base+ext tests the beam's
   own line and removes all of them except 2 grazing ship-surface rows. Examples of such endpoints: a
   module behind the empty centre, a whole ship's box centre, or a station element beyond `R`. There the probe line reaches the
   element while the barrel reaches its parent hull first.
2. **The module fallback is not justified.** Off the empty path it adds no correct answer that base+ext
   lacks. On the empty path it is right for a different reason than X4's: it finds another line to a
   module, so it reads CLEAR on 28 beam rows that X4 refuses.
3. **The genuine-miss check matters.** 78 broad and 140 `#60` PERMIT rows reach no geometry on X4's
   line. Only base+ext's sector-declared check proves them. Another 238 `#60` rows are permitted through
   the empty centre by a module past it. The extended `Q(T)` proves those; the probe, which stops at the
   centre, cannot.
4. **The result-0 second ray never permits in this population.** Every surface row whose first hit is
   the element's own parent or sibling is refused by X4's second ray: 5,706 ship-surface and 394
   station-surface rows. base+ext leaves them UNKNOWN, never CLEAR; they are nearly all of its U on NOT.
   That the second ray never permits is a population result, not a rule, so the method still must not
   call such a hit BLOCKED.
5. The 30 station-surface U on PERMIT are the off-mesh Xenon shield aim points. X4's line misses the
   aim point and its continuation meets the parent module, so X4 permits a miss. From the extended line
   alone this reads as a module hit.

**Uncertain truth, not scored** (shown per class above as "uncertain"):

- shape models disagree: 528 ship-surface, 24 whole-ship and 12 station-surface rows;
- first-hit ties within 1 cm: 58 ship-surface rows;
- the answer changes between `f = 1` and the census `R`: 2 ship-surface rows.

No station-root row is uncertain.

**Beyond the model:** these hold for the benchmark's geometry only.

- Other-zone bodies, wrecks, docked craft, construction modules, pair collision filters and the Timelines
  `lenientfireallowance` beam are not simulated.
- `R` is a census value; `f` changed the truth on 2 rows.

**Cost.** Worst case per turret per pass:

- base+ext: 6 `check_line_of_sight` calls (the own-socket branch: probe, `Q(W)`, forward, back, `Q(T)`,
  sector), a beam 3, a guided turret 0;
- current: 3, or 6 for a station root;
- base: 4.

base+ext also needs one `create_orientation` and one `bboxdistanceto` read. It makes those only when
the probe fails, and before any probe for a beam. Calls per scored settled row: 1 call 5,594; 2 calls
1,588; 3 calls 2,536; 4 calls 1,404; 5 calls 5,766; 6 calls 734. The 30 km lines are longer than
current's, so each ray's broad-phase cost may be higher. None of this is measured frame time.

**Soundness conditions, all offline:**

- the extension must reach past X4's endpoint wherever a miss is claimed. The largest such endpoint here
  is 10.75 km; the integrity check enforces it per row;
- `u` is taken toward the aim point nearest the muzzle, which differs from X4's point only near an
  aim-point switch on multi-point targets;
- a sector-declared call and `create_orientation useaimtarget` from an offset origin are statically
  traced but never run LIVE.

## Answers

1. **Ship surface elements: yes, after settling, apart from one mechanism.** On 13,390 scored rows
   the settled `useaimtarget` probe has 0 false positives and 296 false negatives. Every false negative
   is a line whose first hit is the firing turret's own collision, which X4's pre-fire gate ignores. No
   number of box points fixes that: the seven-point scan misses the same 296 rows and adds 234 false
   CLEARs.
2. **Station surface elements: the same.** On 764 rows, 0 FP and 56 FN, all own-turret. A Xenon
   shield whose aim point is off its mesh adds 74 UNKNOWN rows; see "Where truth is undefined".
3. **Whole ships: the same.** On 1,558 rows, 0 FP and 298 FN, all own-turret. The LargeTarget offset
   moves the bearing point off the box centre on 72 scored rows. The probe still tests the box centre, but
   that caused no error here.
4. **Multi-aim-point targets: no special handling needed.** X4 and MD `useaimtarget` both pick the
   aim point nearest the **turret component origin**; the muzzle never selects it (native trace). The
   probe therefore tests the bearing point on every multi-point row. Across 928 scored multi-point rows
   its only errors are the own-turret ones. On 23 settled rows a muzzle-origin selector would pick
   another point; all are scored, and the probe is right on all 21 with defensible truth.
5. **Station roots: the turret bears on the union-box centre, often empty space.** The LargeTarget
   offset is never kept, because a modular station's own component has no collision geometry (native
   trace). On 108 of 224 settled rows the path to the centre, and past it, meets no geometry: X4 still
   permits fire, and the aimed line misses the station. Those rows are UNKNOWN. On the 116 scored rows the
   root probe has 0 FP and 26 own-turret FN. The production two-module lines have 8 FP, all blocked by
   the firing ship's own hull, and 32 FN. They also read CLEAR on 78 of the 108 empty-path rows, where
   X4's aimed line reaches nothing. That the continuation misses is true of these views, not in general.
   In the #60 reconstruction, the settled barrel's projectile path through the empty `xen_defence`
   centre often reaches a module behind it (see "Historical witnesses").
6. **Before settling**, the probe's errors come from where the barrel is parked:
   - FN: the firing turret's own collision (1,528), the firing ship's own hull (93);
   - FP: the parked line reaches the target, but the settled path is blocked by a sibling turret (59),
     the firing ship's own hull (39) or the satellite (2).
7. **After settling**, the only error left is the own-turret one: 676 FN and 0 FP over 15,828 rows.
8. **The six extra surface box points never pay off on scored cases.**
   - Settled: on selected surfaces they recover 0 false negatives and add 236 false CLEARs (234 ship
     surfaces, 2 station surfaces). The full seven-point strategy has 254 false CLEARs; the other 18
     come from the unchanged whole-ship and station-root checks.
   - Parked: on surfaces they recover 4 false negatives and add 205 false CLEARs. Across all target
     classes, the full strategy has 200 more false CLEARs than the single probe (311 versus 111).
9. **No physical mechanism needs them** among scoreable rows. They say CLEAR on rows whose aimed line
   reaches no geometry (the off-mesh shield and station centre gaps), but there the truth is undefined.
10. **Smallest justified method: one `useaimtarget=true` probe from the settled `barrelposition`**,
    `excludeself="false"`, for every target class. The own-turret case needs its own handling:
    - Identify it with the existing `Q(W)` call and report UNKNOWN (`self`). This is what production
      does after its centre line.
    - Or retry that one line with `excludeself="true"` ("probe+ex"). That recovers all 676 false
      negatives but adds 78 false CLEARs where the firing ship's own hull blocks, because `true` drops
      it (settled: 0 FN, 78 FP, 1.76 mean calls).

    The three target types do not need different point sets. Station roots differ in what the bearing
    point is, not in how to test it.

## What changed since the Ray/Osaka-only benchmark

- **Native: which origin selects the aim point.** The shoot controller passes the weapon component
  to `0x00520FC0` (`0x007E76AA`); `CheckLineOfSightAction` passes its `object` (`0x00BCBAFF`). The
  selector uses that component's own origin, so neither uses the muzzle or `objectoffset`. The old
  code selected the probe's point from the muzzle. Truth and probe now both use the turret origin.
  Recorded in `macro-box-aimtargets.md`.
- **Native: where a turret bears on a whole ship or station.** Recorded in
  `selected-target-line-of-fire.md`:
  - a ship with no authored point and box radius > 500 m gets the LargeTarget offset;
  - the offset is kept only if it lies inside the ship's own body (`0x0051BEB0`);
  - a station root always falls back to its union-box centre.
- **Population:**
  - 4 official A7.3 firing ships, beside the Ray;
  - 12 whole-ship targets chosen by aim-point count and size;
  - 64 ship and 12 station surface elements;
  - three shipped stations;
  - external blockers.
- **One bug found and fixed during the run.** The whole-ship probe must end at the authored point; it
  had used the box centre.

## Population

Every rule reads source metadata only and is fixed before scoring (`scenes.py`). SWI is excluded
because its collision geometry is not installed.

**Firing ships:** the #184 A7.3 official rows.

| | ship | mounts used | loadout variants |
|---|---|---|---|
| M1 | `ship_bor_m_trans_container_01` | 1 of 1 | A: `par_m_shotgun_01`; B: `bor_m_laser_01` |
| L1 | `ship_bor_l_miner_liquid_01` | 4 of 4 | A: `bor_m_dumbfire_01`; B: `bor_m_laser_02` |
| L2 | `ship_spl_l_destroyer_01` | 6 of 18 | A: `arg_m_dumbfire_02`, `par_l_dumbfire_01`; B: `kha_m_beam_01`, `spl_l_laser_01`; C: `arg_l_guided_01` |
| X1 | `ship_spl_xl_carrier_01` | 6 of 101 | A: `arg_m_dumbfire_02`; B: `kha_m_beam_01` |
| Ray | `ship_bor_l_destroyer_01` (anchor) | 14 of 14 | 12 `bor_m_railgun_02`, 2 `bor_l_disruptor_01` |

- Mounts are the extremes along ±x, ±y and ±z.
- Loadouts use the A7.3 rule per mount: the shortest barrel with the broadest arc, and the longest with
  the narrowest.
- Guided turrets are ranked out, because they never run the obstruction check. One guided variant is
  kept to count GUIDED (372 rows, no rays).
- Non-firing mounts, shields and engines carry a stated compatible macro of the ship's faction, so
  siblings exist.
- Categories covered: M and L; beam and projectile; single- and multi-endpoint; unguided missiles.

**Targets:**

- **Whole ships (12).** For each aim-point count, the smallest and largest official ship with a
  collision body. For no aim point, also the median and the smallest above 500 m.

  | aim points | ships |
  |---|---|
  | 0 | `arg_s_trans_container_02`, `ter_m_corvette_01`, `pir_l_scavenger_01` (578 m), `spl_xl_ark_01` (6 km) |
  | 1 | `pir_s_fighter_01`, `kha_l_destroyer_01` |
  | 2 | `pir_s_heavyfighter_01`, `bor_l_miner_solid_01` |
  | 3 | `gen_s_fightingdrone_01`, `ter_xl_resupplier_01` |
  | 4 | `arg_xl_carrier_02` |

  The Osaka anchor is the twelfth.
- **Ship surface (64).** On every L/XL host, per kind, the smallest and largest selectable element.
  The Xenon mothership hosts the only multi-point element, `engine_xen_xl_mothership_01_allround_mk1`
  (4 points), on its real hull of child structures. Stated equipment elsewhere.
- **Stations (3 shipped plans).**
  - `xen_defence`: compact, 5 modules (#60);
  - `arg_tradestation`: 19 modules on long struts;
  - `arg_shipyard`: 37 modules.
  - Plus 12 station turret and shield elements. No station module has an engine slot.
- **Views.** Two ordinary #184 bearings per host, plus two aim-point-switch bearings for multi-point
  targets. Gaps are 1,500 m and 300 m. Every view uses all four firing ships and their variants.
- **External blockers.** One scene each for another ship, a station module, an ice asteroid and a
  satellite, on the `bor_l_miner_solid` host.
  - Wrecks are not simulated. The accepted native rule gives a fresh, persistent or restored ship wreck
    and a station-module wreck the same body, so the ship and module rows stand for them.
  - A body destroyed without a wreck is not a blocker, which is the no-blocker scene.

23,548 tests: 11,760 anchor and 11,788 broad. About 11 minutes, one niced process.

## Truth

1. **Bearing point.** See "Answers" 4 and 5 and the KB record for the full table.
2. **CAN BEAR.** The #176 scorer on that point.
3. **Settling.** The #166 rest reached from the starting yaw.
4. **The path.** The segment from the settled `barrelposition` to the bearing point, ignoring only the
   firing turret's own meshes.
5. **Classification.** The first hit, by the #202 membership rules:
   - a selected element counts only itself;
   - a whole ship counts its hull and its elements;
   - a station root counts any module or module element.

   UNKNOWN when the MESH and HULL models disagree, the path hits nothing, or the two closest hits on
   different bodies lie within 1 cm and differ in membership.

No candidate line enters truth, and an integrity check re-derives truth with every candidate line
replaced.

| truth | whole ship | ship surface | station surface | station root | total |
|---|---:|---:|---:|---:|---:|
| **CLEAR** | 1,372 | 4,570 | 220 | 104 | **6,266** |
| **NOT** | 186 | 8,820 | 544 | 12 | **9,562** |
| GUIDED (no obstruction check) | 72 | 240 | 48 | 12 | 372 |
| cannot bear the bearing point | 1,024 | 4,362 | 780 | 184 | 6,350 |
| LargeTarget body not reconstructable (`nocollision_jolt` part) | 0 | 0 | 0 | 0 | 0 |
| shape models disagree | 26 | 704 | 14 | 0 | 744 |
| first-hit tie | 0 | 72 | 0 | 0 | 72 |
| path reaches no geometry | 0 | 0 | 74 | 108 | 182 |
| trap / repeller start / rest out of arc / scorer UNKNOWN | 0 | 0 | 0 | 0 | 0 |

- **Shape models disagree (744).** 402 are element-versus-parent boundaries. 190 are paths where MESH
  reaches the point with no hit while the solid HULL is hit: 186 hollow engine nozzles and 4
  offset points inside the scavenger. 144 involve the firing ship's own hull, and 8 are other. The HULL table gives the same conclusions as MESH.
- **No trap or multiple-rest case occurred.** Parked and astern starts always settled at the same yaw,
  including at 300 m.

## LargeTarget point-inside test: the layer-0/1 body

The LargeTarget offset is kept only when `0x0051BEB0` finds the offset point inside the target's
layer-0/1 body (`+0x260`). Until `539fd05` the benchmark tested it against the layer-3 line-of-fire
parts under both shape models, and excluded disagreement.

**What the layer-0/1 body is (native, inference; KB "The layer-0/1 and layer-3 bodies differ in shape,
part filter and geometry slot").** It uses the same member walk as layer 3, so it contains the hull,
the attached elements and the `Destructible`/`DockingBay` children. The builder flag changes three
things:

- **shape:** the convex `-hull` shape (geometry `+0x28`) instead of the `-mesh` triangles;
- **part filter:** `nocollision_jolt` parts are also dropped;
- **geometry slot:** always slot 0.

**Equivalence for this population.**

- **Shape: not equivalent.** The MESH parity test is not what X4 does.
- **Parts: equivalent.** No affected target has a `nocollision_jolt` part:
  - checked on `pir_l_scavenger_01` and `spl_xl_ark_01`, their macro children and their stated
    elements;
  - and on all 36 official ships with no authored aim point and a radius over 500 m.

  Every part ships exactly one `-hull.jcs`, so slot 0 is the file the benchmark already reads.

**Correction.** `bearing_point` now tests the point with the HULL model only, over the target's
hull, children and elements. The old disagreement exclusion is gone. A focused guard keeps any row
UNKNOWN whose target body carries a `nocollision_jolt` part (`geometry.Body.jolt`), because that body
is not reconstructed; no row triggers it.

**Rows that changed: exactly the 32 previously excluded ones.** The row-by-row diff against `539fd05`
changes no other record. In all 32 the offset point is inside the HULL body, so the offset is kept:

| target | rows | now |
|---|---:|---|
| `pir_l_scavenger_01` | 4 | NOT (bearing path blocked by the firing ship's own hull) |
| `pir_l_scavenger_01` | 4 | line of fire excluded: MESH reaches the offset point with no hit, HULL hits the hull |
| `spl_xl_ark_01` | 20 | CANNOT BEAR the offset point |
| `spl_xl_ark_01` | 4 | CLEAR |

The 8 newly scored rows, settled:

- probe: 2 TP, 4 TN, 2 FN (own-turret socket, `arg_m_dumbfire_02`);
- probe+ex: 4 TP, 4 TN;
- current and seven: 2 TP, 4 TN, 2 FN.

Parked, the probe adds 3 FP (own hull) and 3 FN (2 own socket, 1 own hull). No conclusion changes: the settled
probe still has 0 false CLEARs, and every settled error is still the firing turret's own collision.

## Accuracy against the settled line of fire

BLOCKED and UNKNOWN count as "not clear"; production UNKNOWN is also shown on its own.
`probe` is the first `useaimtarget=true` probe alone. `probe+ex` is the probe plus, only when its first
hit is the firing turret, the same line with `excludeself="true"`.

**All 15,828 scored rows:**

| method | phase | TP | FP | TN | FN | UNKNOWN (on CLEAR) | mean calls |
|---|---|---:|---:|---:|---:|---:|---:|
| probe | parked | 4,623 | 111 | 9,451 | 1,643 | — | 1 |
| **probe** | **settled** | **5,590** | **0** | **9,562** | **676** | — | **1** |
| probe+ex | parked | 6,134 | 426 | 9,136 | 132 | — | 1.96 |
| probe+ex | settled | 6,266 | 78 | 9,484 | 0 | — | 1.76 |
| current | parked | 3,346 | 105 | 9,457 | 2,920 | 4,417 (1,845) | 2.55 |
| current | settled | 4,078 | 38 | 9,524 | 2,188 | 2,090 (1,038) | 2.46 |
| seven | parked | 4,465 | 311 | 9,251 | 1,801 | 4,244 (1,682) | 12.73 |
| seven | settled | 5,388 | 254 | 9,308 | 878 | 1,914 (862) | 11.97 |
| lazy | settled | 5,388 | 254 | 9,308 | 878 | 1,914 (862) | 6.78 |
| eight | settled | 5,388 | 254 | 9,308 | 878 | 1,914 (862) | 13.76 |

- The anchor alone (9,836 rows) is unchanged: settled probe 0/0, seven 130 FP, current 1,182 FN.
- The broad population alone (5,992 rows): settled probe 0 FP / 676 FN, seven 124 FP / 878 FN,
  current 18 FP / 1,006 FN.
- Lazy never changed a status (integrity check). The eighth point (the old centre) gave totals
  identical to seven.

**Settled, by target class (FP / FN):**

| target class | scored | truth CLEAR | probe | probe+ex | current | seven |
|---|---:|---:|---:|---:|---:|---:|
| ship surface | 13,390 | 4,570 | 0 / 296 | 54 / 0 | 20 / 1,606 | 234 / 296 |
| station surface | 764 | 220 | 0 / 56 | 4 / 0 | 0 / 56 | 2 / 56 |
| whole ship | 1,558 | 1,372 | 0 / 298 | 20 / 0 | 10 / 494 | 10 / 494 |
| station root | 116 | 104 | 0 / 26 | 0 / 0 | 8 / 32 | 8 / 32 |

For whole ships and station roots, "seven" is the current method: the scan applies only to elements.

**Settled, by surface type (FP / FN):**

| surface | probe | seven |
|---|---:|---:|
| ship turret (4,966) | 0 / 146 | 90 / 146 |
| ship shield (6,684) | 0 / 110 | 66 / 110 |
| ship engine (1,740) | 0 / 40 | 78 / 40 |
| station turret (420) | 0 / 44 | 0 / 44 |
| station shield (344) | 0 / 12 | 2 / 12 |

**Settled, by aim-point count (FP / FN):**

| aim points | scored | probe | current | seven |
|---|---:|---:|---:|---:|
| 0 | 700 | 0 / 100 | 8 / 106 | 8 / 106 |
| 1 | 14,200 | 0 / 388 | 20 / 1,744 | 236 / 434 |
| 2+, every origin picks the same point | 907 | 0 / 188 | 10 / 338 | 10 / 338 |
| 2+, selector origin matters | 21 | 0 / 0 | 0 / 0 | 0 / 0 |

**Settled, by firing turret, broad (probe FP / FN):**

| turret category | scored | probe | seven |
|---|---:|---:|---:|
| M unguided missile, multi endpoint (`arg_m_dumbfire_02`) | 1,594 | 0 / 610 | 4 / 612 |
| L unguided missile, multi endpoint (`par_l_dumbfire_01`) | 606 | 0 / 50 | 14 / 68 |
| M beam (`kha_m_beam_01`) | 1,514 | 0 / 16 | 34 / 94 |
| M unguided missile, single endpoint (`bor_m_dumbfire_01`) | 618 | 0 / 0 | 22 / 32 |
| M/L projectile, single and multi endpoint | 1,660 | 0 / 0 | 50 / 72 |

## What breaks `useaimtarget`

Blocker mechanisms by the first hit on the bearing path (all rows, settled, FP / FN):

| first hit on the bearing path | rows | probe | seven | current |
|---|---:|---:|---:|---:|
| the selected element (CLEAR) | 4,570 + 220 | 0 / 296 + 0 / 56 | 0 / 296 + 0 / 56 | 0 / 1,606 + 0 / 56 |
| the target hull, whole ship (CLEAR) | 1,312 | 0 / 296 | 0 / 492 | 0 / 492 |
| the target's own element, whole ship (CLEAR) | 60 | 0 / 2 | 0 / 2 | 0 / 2 |
| a station module, root (CLEAR) | 104 | 0 / 26 | 0 / 32 | 0 / 32 |
| parent hull of the selected element | 4,510 | 0 / 0 | 150 / 0 | 18 / 0 |
| sibling turret / shield / engine on the target | 1,282 / 100 / 350 | 0 / 0 | 76 / 0 | 0 / 0 |
| parent module / other module / sibling element, station | 210 / 250 / 74 | 0 / 0 | 2 / 0 | 0 / 0 |
| firing ship's own hull | 2,050 | 0 / 0 | 16 / 0 | 12 / 0 |
| sibling turret / shield on the firing ship | 590 / 8 | 0 / 0 | 8 / 0 | 6 / 0 |
| other ship / station module / asteroid (external) | 16 / 34 / 84 | 0 / 0 | 0 / 0 | 0 / 0 |
| satellite (external small object) | 4 | 0 / 0 | 2 / 0 | 2 / 0 |

Every settled probe error is on a truly CLEAR path (the first four rows), and every one has the same cause: **the firing
turret's own collision is the first hit on the probe line**. X4 ignores it; MD `excludeself="false"`
does not. It is concentrated on three turrets whose sockets enclose, or nearly enclose, their launch
points (KB, "Some launcher sockets enclose their own launch points"):

| firing turret | probe first hits its own turret | truth-CLEAR settled rows |
|---|---:|---:|
| `turret_arg_m_dumbfire_02_mk1` | 610 | 670 |
| `turret_par_l_dumbfire_01_mk1` | 50 | 278 |
| `turret_kha_m_beam_01_mk1` | 16 | 676 |
| every other benchmark turret | 0 | |

All lines share the barrel origin, so every candidate fails on these rows; the seven-point and current
methods report them as UNKNOWN (`self`).

No external blocker, sibling, parent hull or parent module ever produced a settled probe error.
Mechanisms never the first hit on a scored bearing path: a sibling engine on the firing ship (engines
sat aft of every view), and an element on another station module. The satellite blocks only when it
sits on one turret's own bearing path: placed 50 m short of the target, lines from turrets tens of
metres apart all passed around it.

## Before settling (parked muzzle)

The probe's parked errors, by first hit on its own line:

- **FN 1,643:**
  - own turret collision: 1,528 (a parked barrel behind or inside its socket);
  - the firing ship's own hull: 93;
  - other: 22.
- **FP 111:** the parked line reaches the target while the settled path is blocked:
  - by a sibling turret on the firing ship: 59;
  - by the firing ship's own hull: 39;
  - by the satellite: 2;
  - other: 11.

Settled, the probe has no false positives and 966 fewer false negatives. The six box points parked:
+4 recovered, +205 false CLEARs.

## Multi-aim-point targets

- Scored multi-point rows: 928, from 1,728 multi-point tests (1,022 settled).
- Settled rows where the turret origin, parked muzzle and settled muzzle all pick the same point: 999.
  Rows where the origin matters: 23.
  - 18 differ between the turret origin and the parked muzzle, 10 between the turret origin and the
    settled muzzle.
  - Of the 21 with defensible truth, 19 are `bor_l_miner_solid_01` views on the aim-point switch
    plane, and one each are on the fighting drone and the Xenon engine.
- The selector origin is resolved natively (turret component origin, for X4 and for MD), so all of
  them are scored. The probe is correct on all 21 with defensible truth.
- If a future build changed MD to select from `objectoffset`, only rows like these 23 would move.

## Station roots

- **Bearing point:** the live union-box centre. It lies:
  - inside no module for `xen_defence` (0, −319, 0) and `arg_shipyard`;
  - inside a module for `arg_tradestation`.
- **Lines from outside toward the centre (200 per plan) that meet no module first:**
  - `xen_defence`: 106;
  - `arg_shipyard`: 165;
  - `arg_tradestation`: 0.
- **Settled rows whose path reaches no geometry: 108** (72 `arg_shipyard`, 36 `xen_defence`).
  - Continued past the centre to 30 km, every one still hits nothing.
  - Natively the ray is a genuine miss, which every supported turret permits. The permitted aimed line
    misses the station.
  - The truth is undefined and the rows are excluded. The two-module lines read CLEAR on 78 of them.
- **Scored rows: 116.**
  - probe: 0 FP, 26 FN (own turret);
  - current: 8 FP (own hull) and 32 FN.
- **Root CLEAR membership is statically traced.** The root probe counts a module or module-element
  hit as CLEAR, and so does X4's pre-fire. Both walk the hit's `+0x70` parent chain to the station.
  Shipped scripts' `.object` and `.container` rely on the same chain. See KB "A station-root check
  accepts a module hit, exactly as X4's pre-fire does". This is inference, not LIVE-tested.
- **Zones do not split the collision world.** Every zone of an active sector shares one physics world,
  and X4 refuses a target in another sector (native trace, KB "Physics worlds belong to active
  sectors, not zones"). No zone boundary hides station geometry from either check.

## Where truth is undefined

182 rows reach no geometry at the bearing point. They are where extra points could claim a CLEAR, and
they cannot be scored:

| target | rows | probe CLEAR | seven CLEAR | first hit past the aim point |
|---|---:|---:|---:|---|
| station root `arg_shipyard` | 72 | 0 | 52 | none |
| station root `xen_defence` | 36 | 0 | 26 | none |
| `shield_xen_m_standard_02_mk1` on Xenon modules | 74 | 0 | 56 | selected shield 34, parent module 40 |

The Xenon shield's authored aim point lies off its collision mesh. Whether X4's round, flying through
that point, then strikes the shield is a hit-prediction question, not the line of fire. The
continuation says it would on 34 of 74 rows.

## Historical witnesses

**#202 Ray/two-Osaka (anchor, unchanged).**

- **Reproduced (geometry and signature).** In the fixture arrangement, 18 element/orientation pairs
  match the LIVE pattern: current reads 0–2/14 while 7–13 turrets have a truly clear settled line. The
  centre line's first hit is the Osaka hull or a neighbouring element; on the L turret element it
  misses. The probe matches the truth on every anchor row.
- **Retained LIVE facts (#202 issue):**
  - 0/14 BLOCKED on element `0x17c090` over 28 passes (42 calls each);
  - 11 confirmed railgun hits on that exact element;
  - three turrets that hit it read clear on an earlier aim-target check.
- **Unlogged, stated here:**
  - the Osaka loadout (stated Terran);
  - Osaka orientation (four yaws);
  - the component type of `0x17c090`.

  "Centre occluded, aim point clear" therefore stays a source-geometry explanation, **not LIVE-proven**.

**#60 Xenon Defence Platform.**

- **Retained:** 0/14 from the muzzle `excludeself="false"` root ray and from the turret-origin
  `excludeself="true"` root ray, while the same turrets fired and hit the station. Not retained: the
  firing ship, the geometry, each turret's aim or barrel direction, and which component each round
  struck. `FIRED aimed` copied the mod's selection; `HIT istgt` only compared it with the hit object or
  component.
- **Ruled out (static):** separate zone physics worlds. **Contradicted (static):** a module whose
  `+0x70` chain misses the station root.
- **Reconstruction (`settled.py --sixty`).**
  - **Setup.** The owner's Boron Ray, the #202 anchor, stands in for the unlogged firing ship. The 14
    mounts, macros and settling are real. All 96 station poses are a representative grid: 24 bearings ×
    4 station yaws, with the Ray 1,500 m outside the station box.
  - **Lines.** Both original probes and X4's pre-fire segment end at the union-box centre. The
    projectile path is a separate line along the settled barrel's +Z. It is geometry only: not actual
    firing, weapon readiness, spread, lead or post-launch behavior.
  - **Turrets that cannot bear** are probed from the parked barrel, and no firing path is evaluated for
    them.

  Per turret placement, by primary mechanism. The primary mechanism is the muzzle probe's first hit.
  X4 permission and the projectile are observations within that row, never a second mechanism.
  Denominator 1,344 per model; cells are MESH / HULL.

  | primary mechanism | turrets | X4 permits | projectile path hits station |
  |---|---:|---:|---:|
  | unobstructed line through the empty centre | 378 / 378 | 378 / 378 | 234 / 238 |
  | station module before the centre | 350 / 350 | 350 / 350 | 350 / 350 |
  | firing turret's own collision | 0 / 0 | – | – |
  | firing ship hull | 64 / 64 | 0 / 0 | 0 / 0 |
  | other obstruction (sibling turret) | 4 / 4 | 0 / 0 | 0 / 0 |
  | cannot bear | 548 / 548 | – | – |

  - **The two probes separately:** the muzzle probe is CLEAR on 356 / 366 placements and the origin
    probe on 638 / 642.
    - The origin probe's CLEARs are the 350 station-first rows, plus 26 / 30 of the 64 hull-first rows
      (it drops the firing hull), plus 262 of the 548 turrets that cannot bear.
    - It starts at the turret component origin, so it reads the same whether or not the barrel has
      turned.
  - **Projectile paths where X4 permits:** 728 / 728. Of those, 584 / 588 hit the station and
    144 / 140 miss.
  - **The settled barrel's +Z lies within 0.008° of the muzzle-to-centre line** (median 0.005°). Casting
    the projectile along the barrel rather than the line therefore changes only 4 MESH rows.
  - **The own-socket mechanism never occurs here.** These Ray railguns and disruptors never hit their
    own socket from the settled muzzle.

  Per station arrangement (denominator 96 poses; both models agree on every pose):

  | pose class | poses |
  |---|---:|
  | both probes 0/14, X4 permits, some projectile path hits the station | 34 |
  | both probes 0/14, X4 permits, every projectile path misses | 14 |
  | some probe CLEAR | 48 |

  - **The 34 poses.** Every permitted turret's segment to the centre meets nothing, and the projectile
    path continues past the centre into a module behind it. The first such pose is `sixty:b0:y0`, the
    station above the Ray: 7 turrets bear and all 7 projectile paths hit.
  - **Poses where all 14 bear.** There are 8, all on horizontal bearings. The 4 with both probes at 0/14
    have every projectile path missing, matching the broad-population result below. The 34 therefore
    depend on the parked-barrel assumption for the turrets that cannot bear.
  - The per-mount table is in the `--report` output.
- **Correction.** The earlier "where the centre path is empty, so is its continuation (36/36)" holds only
  for the broad population's views. In representative geometry, **the recorded pattern is geometrically
  possible**: both probes 0/14 while X4 permits and projectile paths reach station modules.
- **Positive control:** the settled muzzle to the nearest module's box centre hits that module on 692
  MESH / 704 HULL rows. There the root-declared and module-declared checks both read CLEAR and X4
  permits.
- **Unresolved.** The reconstruction does not show what happened in #60 and does not explain its
  recorded hits. That needs a LIVE run logging, per FIRED shot, the muzzle, barrel direction, union-box
  centre, struck component and both probes.
- `benchmark.py` states the same arrangements by hand:
  - centre gap with a module behind or with nothing behind;
  - own socket, then the gap;
  - own hull first: the origin probe CLEAR while X4 refuses;
  - the module-first positive control.

## Shape model

MESH and HULL are both still cast; which Jolt shape the layer-3 ray uses remains untraced. Every
conclusion above holds under HULL: settled probe 0 FP / 678 FN, probe+ex 56 FP / 0 FN, seven 166 FP /
854 FN. Disagreements are excluded, not resolved.

## Decision-rule tests and integrity

- `benchmark.py`: the drift signature passes, all 9 mutants are killed, and integrity is PASS. The
  standing rule FAIL remains: **missing missile guidance becomes unguided**.
  - Removed: the module-link-null and cross-zone #60 hypotheses, and the three `link` scenes. Both are
    contradicted by the native trace.
  - Replaced: the unscored "cross-zone blocker unseen" scene. It is now `other-zone-blocker`, a
    same-sector body under another zone: the production answer is UNKNOWN `miss`, never CLEAR.
  - The #60 witness now checks five stated arrangements.
- `runtime.lua`: 13 CODE checks pass. The 2 SPEC rows (#202 task 3) fail as expected. There are 2
  NOTEs.
- `settled.py` integrity checks, all PASS. They would catch:
  - truth depending on any candidate line;
  - an UNKNOWN candidate counted as CLEAR;
  - an UNKNOWN truth entering the matrix;
  - a station element CLEAR on its parent module, a sibling or another module;
  - a multi-point row without its three-origin selector record;
  - an alternate box point turning a blocked bearing path into a correct CLEAR;
  - lazy differing from seven;
  - (#60 reconstruction) a saved reconstruction that is missing, empty or incomplete (all 96 poses × 14
    turrets, every line under both models), including under `--report`;
  - X4's segment disagreeing with the muzzle probe where only the firing turret differs;
  - a barrel direction that is not a unit vector;
  - stored first hits that differ from a re-cast of their stored lines (every 6th pose, both models);
  - a missing positive control.

## Rescue probes for the own-turret case

When the settled probe's first hit is the firing turret itself, the conservative answer is UNKNOWN
(`self`). This is the probe plus a `Q(W)` call: 676 MESH / 678 HULL settled FN, 0 FP. The rescue methods
below retry only those rows. Source: `settled.py` "Rescue probes". The established tables are unchanged.

What the mod can use:

- `check_line_of_sight` with any `objectoffset`. The aim point is still selected from the turret
  component origin, so moving the start keeps the same endpoint.
- The turret's `macro.boundingbox` (`center`, `max` = half-extents).
- The direction to the engine's aim point, from `create_orientation useaimtarget` at the turret
  origin. This is inference, not yet LIVE-checked.

What it cannot use:

- the first hit's position or identity;
- collision meshes;
- a per-turret current target;
- an authored aim point's position.

Results, settled phase (cells MESH / HULL):

| method | implementable | recovered FN | FP | self left UNKNOWN on CLEAR | mean / max calls |
|---|---|---:|---:|---:|---:|
| conservative (probe, `Q(W)`) | yes | – | 0 / 0 | 676 / 678 | 1.65 / 2 |
| `excludeself=true` retry | yes | 676 / 678 | 78 / 56 | 0 / 0 | 1.76 / 3 |
| restart just past the own-turret hit | no: hit position not exposed | 676 / 678 | 0 / 0 | 0 / 0 | 1.76 / 3 |
| advance past the turret's `macro.boundingbox` | yes | 6 / 6 | 0 / 0 | 670 / 672 | 1.76 / 3 |
| advance past the turret's collision-mesh bounds | only with prebuilt per-turret data | 676 / 678 | 0 / 0 | 0 / 0 | 1.76 / 3 |
| reverse from the aim point to the muzzle, target `excludeself=true`, aim point assumed known | no | 676 / 678 | 546 / 550 | 0 / 0 | 1.76 / 3 |
| reverse, whole ships whose aim point is the box centre | partly | 74 / 74 | 0 / 0 | 602 / 604 | 1.65 / 3 |
| `excludeself=true` retry guarded by the advance or the whole-ship reverse | as its guard | same as its guard | 0 / 0 | same | +1 call |
| **step and look back**: `Q(W)` to a step toward the aim point, then forward and back (below) | script actions only; not LIVE-checked | 676 / 678 | 0 / 0 | 0 / 0 | 1.81 / 4 |

Parked (MESH):

- conservative 111 FP / 1,643 FN;
- `excludeself=true` retry 426 / 132;
- restart past the hit 136 / 141;
- advance past the collision bounds 138 / 140;
- advance past `macro.boundingbox` 111 / 1,622;
- step and look back 136 / 143 (HULL 112 / 243), within 2 rows of the ideal restart.

Parked FPs are mostly sibling turrets and the firing hull, which the parked line crosses but the
settled line does not.

**1. Advance past the own turret, without excluding the firing ship.** The idea works; the
script-visible box does not.

- `macro.boundingbox` is the union of authored part sizes, not the socket's collision mesh. For
  `turret_arg_m_dumbfire_02` the box reaches 3.0 m above the mount and the socket 8.1 m. The
  `par_l_dumbfire_01` and `kha_m_beam_01` sockets also overhang their boxes.
- So on 1,700 of the settled self rows (MESH), the advanced probe's first hit is still the firing
  turret's socket.
- Advanced past the real collision bounds, the same probe matches the ideal restart exactly on settled
  rows. That needs a shipped per-macro extent table, which is prebuilt data.
- Skipped segments:
  - For the `macro.boundingbox` advance, no obstruction lay on the skipped muzzle-to-start segment in
    this population.
  - The collision-bounds advance's skipped segments were not recorded separately. It has the same
    settled FPs as the ideal restart (0), and 2 more parked MESH FPs (138 against 136), which is the
    upper bound on what its skipping cost.
  - Both are population results, not guarantees.

**2. A guarded `excludeself=true` retry.** The mod has no signal that the firing hull is off the path.

- The only guards available are the advance and the reverse probe. Each already proves CLEAR by
  itself, so adding the `excludeself=true` retry costs a call and changes nothing.

**3. A probe from where the first probe stopped.** Impossible as stated.

- `check_line_of_sight` returns only a boolean.
- `find_object_surface` returns a point but is randomized and unverified (see the KB record).
- The feasible variant runs the other way: from the aim point back to the muzzle with
  `object=$target excludeself=true`. It is CLEAR only when its first hit is the firing turret.
- On a surface element, `excludeself=true` also drops the element's parent hull or module. The probe
  then misses a parent that blocks: 546 incorrect CLEARs, 428 of them `arg_m_dumbfire_02` against a
  ship surface.
- It is sound only when the whole target is excluded, which means whole ships and station roots. It
  also needs the aim point's position:
  - Whole ships with no authored aim point have it at the macro box centre. That assumes the runtime
    box is the macro box; the ship override families are untested.
  - Station roots need a live union box that is not script-visible.
  - A mod can detect "no authored point" only by comparing the `create_orientation useaimtarget`
    direction with the direction to the box centre. That is inference.

**5. Step and look back.** In the benchmark it matches the ideal restart, using only script actions. It
is inference: none of the four calls has been run LIVE in this combination. After a probe that is not
CLEAR:

1. **Direction:** from the barrelposition toward the aim point, via `create_orientation useaimtarget`
   with the barrelposition as origin.
2. **Step:** along that direction by half of `$target.bboxdistanceto.{$weapon}`.
3. **`Q(W)`:** from the barrelposition to the step point, `object=$weapon`, declared target `$weapon`,
   explicit `targetoffset`, `excludeself=false`. The firing turret must be first; otherwise the row stays
   NOT.
4. **Forward:** from the step point to the aim point, `useaimtarget=true`, `excludeself=false`. The
   target must be first.
5. **Back:** from the step point to the barrelposition, declared target `$weapon`. The firing turret
   must be the first thing seen.

It is CLEAR only when steps 3–5 all hold.

- The checks cover the whole line except the stretch between the first and last own-turret hits, which
  is inside the socket.
- Anything the step skipped (hull, sibling, external) is the first thing the back check sees, so the
  row stays UNKNOWN.
- A step that stays inside the socket fails `Q(W)` or the back check.

**Identifying the own-turret case.**

- An exact `Q(W)` on the probe's own line needs the probe's endpoint as an explicit `targetoffset`. That
  endpoint is X4's selected aim point, which scripts cannot read for a target with authored aim points.
- It can be computed only when the aim point is the target's box centre (`macro.boundingbox.center`) on
  a ship or surface element. It cannot be computed on a station root, whose live union box centre is
  not script-visible.
- So the method uses `Q(W)` on the probe line's first stretch, from the barrelposition to the step
  point, which it can place.
- Benchmarked against the probe's actual first hit, over every row where the probe is not CLEAR:
  - `Q(W)` is true on all 1,726 / 1,688 settled own-socket rows and false on every settled row blocked
    by anything else: the firing hull, siblings, the target's parent or elements, other modules,
    asteroids, other ships and satellites.
  - Parked, at the half step, it misses 1 MESH own-socket row and never reads true on another
    obstruction. That confusion table covers the half step only.
  - At the 50 m step, 4 parked MESH rows lose the own-turret label; the step stays inside the socket
    on 19 parked rows.
  - A miss leaves the row NOT, never CLEAR.
- `Q(W)` and the probe share their first stretch exactly when the aim point nearest the barrelposition
  (what `create_orientation` returns) is X4's point, chosen from the turret origin. They differ only on
  multi-point targets near a switch boundary.

**Step distance.**

- The benchmark's step distance is the turret component origin to the target's own oriented box. That is
  `$target.bboxdistanceto.{$weapon}` (KB "MD `bboxdistanceto` geometry"), apart from its approximate
  square root (±7e-4 relative).
- The reverse form `$weapon.bboxdistanceto.{$target}` is different. It measures the turret box to the
  target's centre, minus the half-diagonal on ships and stations, and to an element's origin on surface
  elements. Use the target-first form.
- Where the step lands, over every row where the probe is not CLEAR, at either step length and under
  both models:
  - it never lands inside the target box or past the first target hit;
  - at 50 m it stays inside the firing turret's collision on 19 parked rows, and none became CLEAR;
  - it skipped a real obstruction on 2,091–3,088 rows, depending on step, phase and model, and none of
    those became CLEAR.

**Results with the actual identification and step distance.**

- **Settled:** 676 / 678 recovered, 0 / 0 FP, and no UNKNOWN left on a CLEAR row, at either step length.
  This is unchanged from the simulated-identity run: `Q(W)` agrees on every settled row.
- **Parked:**
  - half step: 136 / 143 MESH FP / FN (HULL 112 / 243), 1,500 / 1,393 recovered;
  - 50 m step: 136 / 151 (HULL 112 / 251).
- **What changed from the previous run:** only labels. The few parked rows where `Q(W)` misses the socket
  now read NOT instead of UNKNOWN (UNKNOWN 2,565 → 2,564 at the half step, 2,573 → 2,569 at 50 m, MESH).
  TP, FP and FN are unchanged.
- **Cost:** 1.81 mean and 4 worst-case `check_line_of_sight` calls, plus one `create_orientation` and
  the position conversions.

The step direction must start at the muzzle.

- A first version stepped along the direction from the turret component origin. Its step point sat
  beside the muzzle-to-target line.
- Objects on the true line then slipped between the checks: 12 MESH / 12 HULL settled false CLEARs.
- Stepping from the muzzle removed all of them.

Evidence that is still missing (LIVE):

1. **`create_orientation useaimtarget` from an offset origin.** It is assumed to return the direction to
   the aim point nearest that origin (KB inference, never run).
2. **`$target.bboxdistanceto.{$weapon}` on real targets.** The ship box override families and the live
   station union box are native inference; the benchmark uses macro boxes and module-box unions.
3. **How X4's ray treats a start inside a body, and back faces.** Both offline models report the body
   (MESH two-sided, HULL solid). Jolt's default ray settings ignore triangle back faces, and X4's
   settings are untraced.
   - If X4 ignores back faces, a muzzle inside its socket may not see the socket at all, and the
     own-turret case itself looks different.
   - The step method's back check meets the socket's outer face either way.
4. **The socket-interior blind spot.** It produced no error in this population.

**4. Other routes.**

- `event_weapon_fired` with `bullet.launcher` and `.rotation` shows that X4 permitted a shot and its
  bore. That comes only after the turret fires, and the turret's own target is not readable, so it
  cannot predict CLEAR. It is a LIVE corroboration signal, not a probe.
- `find_object_surface` with `object=$weapon` could in principle return the own-turret hit point for
  the ideal restart. Its retries, jitter and lattice entry are unresolved. It needs a LIVE check before
  any use.

Conclusion:

- **Step and look back** is the best rescue built from script actions. It uses no prebuilt data and no
  `excludeself=true`. With its own `Q(W)` identification, it recovers every settled own-turret row
  (676 MESH / 678 HULL) with no incorrect CLEAR offline, matching the ideal restart, at up to 4 calls.
  Whether it holds in X4 depends on the three LIVE questions above.
- The alternatives are weaker:
  - the unguarded `excludeself=true` retry recovers the same rows but claims CLEAR through the firing
    hull (78 / 56);
  - an advance past `macro.boundingbox` recovers 6;
  - the whole-ship reverse probe recovers 74.
- Everything above is offline inference, not LIVE. The first LIVE check should be
  `create_orientation useaimtarget` from the barrelposition. Then compare `$target.bboxdistanceto.{$weapon}`
  with a known geometry, and test one own-socket case such as `arg_m_dumbfire_02`.

## Evidence gaps

1. Which triangle source the layer-3 ray uses: geometry `+0x20` (`-mesh`), at a geometry slot from a
   member virtual (`+0x15D8`), with a `-collision` XMF fallback. 744 rows excluded where MESH and HULL
   disagree. The LargeTarget point-inside test is resolved: layer 0/1, `-hull` only (see below).
2. A LIVE check of root-declared versus module-declared rays. The module-to-root `+0x70` membership is
   statically traced. The code that writes a module's parent, and modules under construction, are not
   traced. Separate zone worlds are ruled out statically. The remaining zone limit is on the MD side:
   `Q(weapon.zone)` cannot recognise a blocker under another zone of the same sector, so that line
   reads UNKNOWN `miss`, never CLEAR.
3. The `U::Turret` slot `+0x1BF0` predicate (`0x005BF690`). It matters only for a turret element with
   no authored point; none was in the population.
4. Whether any parameter file overrides the 500 m LargeTarget radius (no writer found besides the
   defaults).
5. A sibling engine on the firing ship, and an element on another station module, were never the
   first hit. Wrecks and removed bodies are covered by the accepted native rule, not simulated.
6. Hit prediction on off-mesh aim points and station-centre gaps (outside line of fire).
7. Frame cost of any method (not measured).
8. Earlier open rules: missing guidance, a module dying mid-pass. Docked craft on a selected station
   hull are decided: a docked-ship first hit counts as CLEAR for firing permission, not as a hit on
   station geometry (owner decision, #202).

## Recommendation

Use **one `useaimtarget=true` probe from the turret's current `barrelposition`** as the CLEAR test for
selected elements, whole ships and station roots. Read it once the turret has turned toward the
selection. Do not add the six box points or the eighth point: on this population they never recover a
settled false negative on selected surfaces, where they add 236 false CLEARs. The full strategy's
254 false CLEARs include 18 from the unchanged whole-target checks.

The one remaining error is the firing turret's own collision. The options:

- Report it as UNKNOWN through the existing `Q(W)` identification (2 calls when it happens). This is
  honest and conservative, and costs launcher turrets like `arg_m_dumbfire_02` most of their CLEARs.
- Or retry with `excludeself="true"` (3 calls). That recovers all 676 but can claim CLEAR through the
  firing ship's own hull (78 false CLEARs here). That is a product trade-off this benchmark measures
  but does not decide.

For station roots the probe tests the right point. The current two-module lines do not. Note that X4
itself permits fire at a station root through an empty centre.
