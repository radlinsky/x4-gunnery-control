# Selected-target CLEAR LINE OF FIRE benchmark findings (#202)

Status: **OFFLINE inference**. Production MD unchanged since `cf459d0`. X4 9.00 build 611726, `X4.exe`
SHA-256 `19750a65…6ad6891`, re-verified 2026-09-25. No new LIVE evidence. Call counts are simulated
`check_line_of_sight` calls, not frame cost. The full report is `settled.py --report`; numbers below are
MESH unless stated.

## Answers

1. **Ship surface elements: yes, after settling, apart from one mechanism.** On 13,390 scored rows
   the settled `useaimtarget` probe has 0 false positives and 296 false negatives. Every false negative
   is a line whose first hit is the firing turret's own collision, which X4's pre-fire gate ignores. No
   number of box points fixes that: the seven-point scan misses the same 296 rows and adds 234 false
   CLEARs.
2. **Station surface elements: the same.** On 764 rows, 0 FP and 56 FN, all own-turret. A Xenon
   shield whose aim point is off its mesh adds 74 UNKNOWN rows; see "Where truth is undefined".
3. **Whole ships: the same.** On 1,550 rows, 0 FP and 296 FN, all own-turret. The LargeTarget offset
   moves the bearing point off the box centre on 64 rows. The probe still tests the box centre, but
   that caused no error here.
4. **Multi-aim-point targets: no special handling needed.** X4 and MD `useaimtarget` both pick the
   aim point nearest the **turret component origin**; the muzzle never selects it (native trace). The
   probe therefore tests the bearing point on every multi-point row. Across 928 scored multi-point rows
   its only errors are the own-turret ones. On 23 settled rows a muzzle-origin selector would pick
   another point; all are scored, and the probe is right on all 21 with defensible truth.
5. **Station roots: the turret bears on the union-box centre, often empty space.** The LargeTarget
   offset is never kept, because a modular station's own component has no collision geometry (native
   trace). On 108 of 224 settled rows the path to the centre, and past it, meets no geometry: X4 still
   fires, and the aimed line misses the station. Those rows are UNKNOWN. On the 116 scored rows the
   root probe has 0 FP and 26 own-turret FN. The production two-module lines have 8 FP, all blocked by
   the firing ship's own hull, and 32 FN. They also read CLEAR on 78 of the 108 empty-path rows, where
   X4's aimed line reaches nothing.
6. **Before settling**, the probe's errors come from where the barrel is parked:
   - FN: the firing turret's own collision (1,526), the firing ship's own hull (92);
   - FP: the parked line reaches the target, but the settled path is blocked by a sibling turret (59),
     the firing ship's own hull (36) or the satellite (2).
7. **After settling**, the only error left is the own-turret one: 674 FN and 0 FP over 15,820 rows.
8. **The six box points never pay off.**
   - Settled: they recover 0 false negatives and add 254 false CLEARs, mostly lines that reach the
     element past its own parent hull or a sibling element.
   - Parked: they recover 4 and add 205.
9. **No physical mechanism needs them** among scoreable rows. They say CLEAR on rows whose aimed line
   reaches no geometry (the off-mesh shield and station centre gaps), but there the truth is undefined.
10. **Smallest justified method: one `useaimtarget=true` probe from the settled `barrelposition`**,
    `excludeself="false"`, for every target class. The own-turret case needs its own handling:
    - Identify it with the existing `Q(W)` call and report UNKNOWN (`self`). This is what production
      does after its centre line.
    - Or retry that one line with `excludeself="true"` ("probe+ex"). That recovers all 674 false
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
| **CLEAR** | 1,368 | 4,570 | 220 | 104 | **6,262** |
| **NOT** | 182 | 8,820 | 544 | 12 | **9,558** |
| GUIDED (no obstruction check) | 72 | 240 | 48 | 12 | 372 |
| cannot bear the bearing point | 1,004 | 4,362 | 780 | 184 | 6,330 |
| LargeTarget offset inside the body depends on the shape model | 32 | 0 | 0 | 0 | 32 |
| shape models disagree | 22 | 704 | 14 | 0 | 740 |
| first-hit tie | 0 | 72 | 0 | 0 | 72 |
| path reaches no geometry | 0 | 0 | 74 | 108 | 182 |
| trap / repeller start / rest out of arc / scorer UNKNOWN | 0 | 0 | 0 | 0 | 0 |

- **Shape models disagree (740).** 398 are element-versus-parent-hull boundaries. 186 are hollow
  engines: MESH reaches no geometry inside the nozzle, while the solid HULL is hit. 144 involve the
  firing ship's own hull, and 12 are other. The HULL table gives the same conclusions as MESH.
- **No trap or multiple-rest case occurred.** Parked and astern starts always settled at the same yaw,
  including at 300 m.

## Accuracy against the settled line of fire

BLOCKED and UNKNOWN count as "not clear"; production UNKNOWN is also shown on its own.
`probe` is the first `useaimtarget=true` probe alone. `probe+ex` is the probe plus, only when its first
hit is the firing turret, the same line with `excludeself="true"`.

**All 15,820 scored rows:**

| method | phase | TP | FP | TN | FN | UNKNOWN (on CLEAR) | mean calls |
|---|---|---:|---:|---:|---:|---:|---:|
| probe | parked | 4,622 | 108 | 9,450 | 1,640 | — | 1 |
| **probe** | **settled** | **5,588** | **0** | **9,558** | **674** | — | **1** |
| probe+ex | parked | 6,131 | 423 | 9,135 | 131 | — | 1.96 |
| probe+ex | settled | 6,262 | 78 | 9,480 | 0 | — | 1.76 |
| current | parked | 3,345 | 102 | 9,456 | 2,917 | 4,415 (1,843) | 2.55 |
| current | settled | 4,076 | 38 | 9,520 | 2,186 | 2,088 (1,036) | 2.46 |
| seven | parked | 4,464 | 308 | 9,250 | 1,798 | 4,242 (1,680) | 12.74 |
| seven | settled | 5,386 | 254 | 9,304 | 876 | 1,912 (860) | 11.97 |
| lazy | settled | 5,386 | 254 | 9,304 | 876 | 1,912 (860) | 6.78 |
| eight | settled | 5,386 | 254 | 9,304 | 876 | 1,912 (860) | 13.77 |

- The anchor alone (9,836 rows) is unchanged: settled probe 0/0, seven 130 FP, current 1,182 FN.
- The broad population alone (5,984 rows): settled probe 0 FP / 674 FN, seven 124 FP / 876 FN,
  current 18 FP / 1,004 FN.
- Lazy never changed a status (integrity check). The eighth point (the old centre) gave totals
  identical to seven.

**Settled, by target class (FP / FN):**

| target class | scored | truth CLEAR | probe | probe+ex | current | seven |
|---|---:|---:|---:|---:|---:|---:|
| ship surface | 13,390 | 4,570 | 0 / 296 | 54 / 0 | 20 / 1,606 | 234 / 296 |
| station surface | 764 | 220 | 0 / 56 | 4 / 0 | 0 / 56 | 2 / 56 |
| whole ship | 1,550 | 1,368 | 0 / 296 | 20 / 0 | 10 / 492 | 10 / 492 |
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
| 0 | 692 | 0 / 98 | 8 / 104 | 8 / 104 |
| 1 | 14,200 | 0 / 388 | 20 / 1,744 | 236 / 434 |
| 2+, every origin picks the same point | 907 | 0 / 188 | 10 / 338 | 10 / 338 |
| 2+, selector origin matters | 21 | 0 / 0 | 0 / 0 | 0 / 0 |

**Settled, by firing turret, broad (probe FP / FN):**

| turret category | scored | probe | seven |
|---|---:|---:|---:|
| M unguided missile, multi endpoint (`arg_m_dumbfire_02`) | 1,594 | 0 / 610 | 4 / 612 |
| L unguided missile, multi endpoint (`par_l_dumbfire_01`) | 604 | 0 / 48 | 14 / 66 |
| M beam (`kha_m_beam_01`) | 1,514 | 0 / 16 | 34 / 94 |
| M unguided missile, single endpoint (`bor_m_dumbfire_01`) | 618 | 0 / 0 | 22 / 32 |
| M/L projectile, single and multi endpoint | 1,654 | 0 / 0 | 50 / 72 |

## What breaks `useaimtarget`

Blocker mechanisms by the first hit on the bearing path (all rows, settled, FP / FN):

| first hit on the bearing path | rows | probe | seven | current |
|---|---:|---:|---:|---:|
| the selected element (CLEAR) | 4,570 + 220 | 0 / 296 + 0 / 56 | 0 / 296 + 0 / 56 | 0 / 1,606 + 0 / 56 |
| the target hull, whole ship (CLEAR) | 1,308 | 0 / 294 | 0 / 490 | 0 / 490 |
| the target's own element, whole ship (CLEAR) | 60 | 0 / 2 | 0 / 2 | 0 / 2 |
| a station module, root (CLEAR) | 104 | 0 / 26 | 0 / 32 | 0 / 32 |
| parent hull of the selected element | 4,510 | 0 / 0 | 150 / 0 | 18 / 0 |
| sibling turret / shield / engine on the target | 1,282 / 100 / 350 | 0 / 0 | 76 / 0 | 0 / 0 |
| parent module / other module / sibling element, station | 210 / 250 / 74 | 0 / 0 | 2 / 0 | 0 / 0 |
| firing ship's own hull | 2,046 | 0 / 0 | 16 / 0 | 12 / 0 |
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
| `turret_par_l_dumbfire_01_mk1` | 48 | 276 |
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

- **FN 1,640:**
  - own turret collision: 1,526 (a parked barrel behind or inside its socket);
  - the firing ship's own hull: 92;
  - other: 22.
- **FP 108:** the parked line reaches the target while the settled path is blocked:
  - by a sibling turret on the firing ship: 59;
  - by the firing ship's own hull: 36;
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
  - Natively the ray is a genuine miss, which every supported turret permits. The turret fires along
    an aimed line that misses the station.
  - The truth is undefined and the rows are excluded. The two-module lines read CLEAR on 78 of them.
- **Scored rows: 116.**
  - probe: 0 FP, 26 FN (own turret);
  - current: 8 FP (own hull) and 32 FN.
- **Assumption behind root CLEAR:** the module-to-root `+0x70` link. It is untested LIVE, like
  cross-zone physics. Station-root results carry both caveats.

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
  `excludeself="true"` root ray, while the same turrets hit the station.
- **New offline evidence.** The turrets bear on the union-box centre. Where that path is empty, so is
  its continuation (36/36), so rounds aimed through the gap do not hit a stationary station.
- **So the centre gap alone does not explain the hits.** They need a path that meets a module. On
  such a path the muzzle root probe is true unless one of these holds:
  - the module-to-root link fails;
  - the zones differ;
  - the firing turret's own socket is first. This cannot explain the `excludeself="true"` ray.
- The #60 firing geometry was not retained. None of these is LIVE-proven, and none is excluded.

## Shape model

MESH and HULL are both still cast; which Jolt shape the layer-3 ray uses remains untraced. Every
conclusion above holds under HULL: settled probe 0 FP / 676 FN, probe+ex 56 FP / 0 FN, seven 166 FP /
852 FN. Disagreements are excluded, not resolved.

## Decision-rule tests and integrity

- `benchmark.py` is unchanged in substance. The drift signature passes, all 9 mutants are killed, and
  integrity is PASS. The standing rule FAIL remains: **missing missile guidance becomes unguided**.
- `runtime.lua`: 13 CODE checks pass. The 2 SPEC rows (#202 task 3) fail as expected. There are 2
  NOTEs.
- `settled.py` integrity checks, all PASS. They would catch:
  - truth depending on any candidate line;
  - an UNKNOWN candidate counted as CLEAR;
  - an UNKNOWN truth entering the matrix;
  - a station element CLEAR on its parent module, a sibling or another module;
  - a multi-point row without its three-origin selector record;
  - an alternate box point turning a blocked bearing path into a correct CLEAR;
  - lazy differing from seven.

## Evidence gaps

1. Which Jolt shape the layer-3 ray, and the LargeTarget point-inside test, use (740 and 32 rows
   excluded).
2. The module-to-root `+0x70` link, and cross-zone rays (station-root CLEAR assumes the link).
3. The `U::Turret` slot `+0x1BF0` predicate (`0x005BF690`). It matters only for a turret element with
   no authored point; none was in the population.
4. Whether any parameter file overrides the 500 m LargeTarget radius (no writer found besides the
   defaults).
5. A sibling engine on the firing ship, and an element on another station module, were never the
   first hit. Wrecks and removed bodies are covered by the accepted native rule, not simulated.
6. Hit prediction on off-mesh aim points and station-centre gaps (outside line of fire).
7. Frame cost of any method (not measured).
8. Earlier open rules: missing guidance, docked craft membership, a module dying mid-pass.

## Recommendation

Use **one `useaimtarget=true` probe from the turret's current `barrelposition`** as the CLEAR test for
selected elements, whole ships and station roots. Read it once the turret has turned toward the
selection. Do not add the six box points or the eighth point: on this population they never recover a
settled false negative, and they add 254 false CLEARs.

The one remaining error is the firing turret's own collision. The options:

- Report it as UNKNOWN through the existing `Q(W)` identification (2 calls when it happens). This is
  honest and conservative, and costs launcher turrets like `arg_m_dumbfire_02` most of their CLEARs.
- Or retry with `excludeself="true"` (3 calls). That recovers all 674 but can claim CLEAR through the
  firing ship's own hull (78 false CLEARs here). That is a product trade-off this benchmark measures
  but does not decide.

For station roots the probe tests the right point. The current two-module lines do not. Note that X4
itself fires at a station root through an empty centre.
