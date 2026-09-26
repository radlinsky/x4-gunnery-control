# CLEAR LINE OF FIRE susceptibility: vanilla X4 9.00 and SWI 0.9.1 HF (#202)

Status: **offline inference** (shipped-source census plus offline geometry). Nothing here is LIVE-tested,
and offline simulation does not establish X4's runtime behaviour.

- **Production evaluated:** `d95e607`, the guarded-full method.
- **SWI:** Star Wars Interworlds 0.9.1 HF (`content.xml` version 091, 2025-12-24), read in place from the
  owner's copy at `/mnt/c/Users/PC/Documents/temp_swi_location/starwarsmod_m1_091hf/starwarsmod_m1`
  (not next to the X4 install).
- **Code:** `susceptibility.py`, with steps `census`, `sample` and `report`. Raw rows and the full tables
  are in `.x4-research-cache/issue202-susceptibility/`.
- **Moving targets are excluded throughout.** Lead against a moving target or from a moving ship cannot
  be observed by a script (see findings, "Runtime feasibility"), and none of these estimates covers it.

## 1. Inventory

**Ships.** Counts are distinct components; macro variants are in brackets. Source: the #184 census rows.

| | vanilla | SWI |
|---|---:|---:|
| ship models (variants) | 203 (285) | 226 (257) |
| large, no authored aim point: X4 may add the LargeTarget offset, so production uses the probe only | 36 (18 %) | 1 (`mandator`) |
| single authored aim point exactly at the origin: production aims at the box centre | 0 | 47 (21 %; 27 S, 20 M) |
| several aim points: needs the selection guard | 14 (7 %) | 128 (57 %) |
| aim point outside its own box: the length bound may fall short | 0 | 5 (2 %) |
| any of these flags | 50 (25 %) | 176 (78 %) |
| any flag other than "several aim points" | 36 (18 %) | 53 (23 %) |

**Named ship families.**

- **Vanilla large targets:** 29 of the 31 vanilla XL models, from `ship_arg_xl_builder_01` to
  `ship_spl_xl_ark_01_a`, plus 7 L models: `ship_pir_l_scavenger_01`, `ship_par_l_destroyer_02`,
  `ship_xen_l_terraformer_01`, `ship_bor_l_carrier_01`, `ship_pir_l_scrapper_01` and the
  `ship_arg_l_trans_container_03/04/05` freighters.
- **SWI origin-point ships:** fighters and small craft, for example `arc170`, `bwing`, `tie_echelon`,
  `yt1300_01` and `razorcrest`.
- **SWI aim points outside their box:** `cor_scrapper`, `quasar_imp`, `quasar_reb`,
  `ship_mando_s_n1_menu` and `yv666`.

**Surface-element component types.**

| | vanilla | SWI (MESH only) |
|---|---:|---:|
| types: turret / shield / engine | 142 / 67 / 71 | 119 / 31 / 111 |
| no collision body: X4 never hits it and permits only a genuine miss | 38 / 18 / 21 | 21 / 5 / 55 |
| aim point outside its own collision | 16 / 1 / 1 | 57 / 10 / 45 |
| no collision, or aim point off its own collision | 54 (38 %) / 19 (28 %) / 22 (31 %) | 78 (66 %) / 15 (48 %) / 100 (90 %) |
| single aim point at origin; several aim points | engines 2; 1 | engines 0; 2 |
| beam turret macros (bullet `attach="1"`, inference) | 35 of 115 (18 are mining) | 6 of 162 |
| mount slots over all ship models: turret / shield / engine | 1,134 / 1,282 / 463 | 4,714 / 1,732 / 694 |

- **Named off-mesh vanilla types:** 16 medium turrets, for example `turret_spl_m_*`, `turret_tel_m_gatling`
  and `turret_arg_m_beam`, plus `shield_xen_m_standard_02` and `engine_kha_xl_battleship_01`.
- **Installed instances are not determinable from source.** The shipped loadouts are scripted only, and X4
  equips NPC ships procedurally. Mount slots are the exposure measure.
- **SWI hull files do not parse.** SWI's `-hull.jcs` files, built for X4 8.00, do not read as 9.00 convex
  hulls, so SWI is scored MESH-only.
  - Its off-mesh counts use mesh parity and may be inflated by open meshes.
  - Whether X4 9.00 loads those hulls or falls back to `-collision.xmf` is a runtime question.
  - `mandator`'s main hull part has no collision file in SWI's catalogs, so it is excluded from the
    sample.

## 2. How often it goes wrong (stationary geometry)

**Populations:**

- **Saved vanilla benchmark:** 16,202 scored rows, plus 796 from the #60 reconstruction.
- **New targeted sample:** 3,366 tests.
  - Hosts: 4 vanilla large-target ships picked by radius rank, plus 8 SWI ships, three each from the
    origin-point and several-aim-point families and two from the outside-box family. `mandator` could
    not be simulated.
  - Attackers: the 4 vanilla size classes M1, L1, L2 and X1, loadout A, 1–6 turrets each, from a parked
    start.
  - Views: two ordinary bearings at 1.5 km and the same bearings at 300 m, plus the aim-point-switch
    bearings for several-aim-point targets.
  - Targets: each host as a whole ship, and on L/XL hosts its smallest and largest selectable turret,
    shield and engine.
- **Excluded:** CANNOT BEAR rows and rows with uncertain truth.

**Production (`d95e607`) outcomes:**

| configuration | false UNKNOWN among shots X4 permits | false CLEAR | notes |
|---|---:|---:|---|
| vanilla large-target whole ships, sample | 80 / 142 (56 %) | 0 | equally at 1.5 km and 300 m: **ordinary engagements** |
| vanilla large-target whole ships, saved (scavenger, Ark) | 40 / 120 (33 %) | 0 | ordinary 1.5 km views |
| vanilla off-mesh station shields, saved | 30 / 218 station-surface permits (14 %) | 0 | extended line meets the parent module just past the aim point |
| SWI surface elements on sample hosts | 25 / 194 (13 %) | 0 | same mechanism, off-mesh SWI elements |
| SWI whole ships, sample | 4 / 355 (≈ 1 %) | 0 | outside-box family only |
| everything else (vanilla surfaces, ships, stations) | ≈ 0.1 % | 2 / ≈ 7,100 CLEAR claims (0.03 %) | the two are grazing-beam rows at 300 m |

- **False CLEAR is rare.** The sample makes about 980 CLEAR claims with no false CLEAR, which puts the
  sample rate below about 0.3 % (95 %).
- **UNKNOWN on refused shots.** Almost every surface UNKNOWN is a shot X4 refuses, because the element's
  own parent hull is hit first and X4's second ray then refuses. That is the intended outcome, since it
  is not counted.
- **SWI origin-point and several-aim-point ships were right on every sampled shot.** The probe decides
  almost all of them. The box-centre direction on the origin-point fighters therefore happened to work;
  it is not proven.
- **Approximate ranges:**
  - large-target whole ships: roughly a third to three-quarters of permitted shots read UNKNOWN;
  - off-mesh elements: 10–15 % of permitted shots;
  - SWI whole ships: about 1 %;
  - false CLEAR: under 0.1 % overall.

## 3. Fixes tested

All fixes are scored on the same rows. Costs are `check_line_of_sight` rays per turret.

| method | what it fixes | result on its rows | new false CLEAR / BLOCKED | rays |
|---|---|---|---|---|
| **exact endpoint for the miss check** (section 3b) | off-mesh aim points; the length bound overshooting the aim point | vanilla surfaces 36 → 0 false UNKNOWN; SWI surfaces 25 → 3 | 0 / 0 | max unchanged (6 / 3); mean up to +0.5 on off-mesh rows |
| **large-target dual check** | large-target whole ships | sample 80 → 1 false UNKNOWN (141 of 142 permitted CLEAR) | 0 / 0 | only on those targets: mean ≈ 6, max 11 (was 1) |
| large-target metadata (ideal known offset) | same | 80 → 0 | 0 / 0 | mean ≈ 2.7, max 5 |
| origin-point metadata | SWI origin-point ships | no change in the sample | 0 / 0 | 0 |

**Exact endpoint for the miss check.**

- The change: the miss claim uses X4's own endpoint instead of the conservative bound.
  - The aim-point distance comes from the box centre, or from the guard's intersection point for authored
    aim points.
  - The factor `f` is 1 unless the target can move, which only a whole ship or a ship engine can
    (`turret-fire-range-gate.md`).
- Every value is already available where the aim direction is established. No new ray is needed.

**Large-target dual check.**

- The offset is script-computable from the firing ship's box, the turret's position in it and the target's
  recovered box. X4's inside-the-hull test is not script-visible.
- So the check evaluates both the box centre and the offset point and accepts only an answer they agree
  on; otherwise it reports UNKNOWN.
- It needs no metadata, but it exceeds the current 6-ray cap on these targets only.

**Large-target metadata.**

- An ideal known offset needs X4's inside-the-hull test per offset point.
- On an 8 × 8 × 16 grid over the offset region, only 65 % of cells are pure (37–99 % per ship). The other
  third would still need the dual check.
- It would also need about 9 KB of generated per-model data. Not worth it.

**Origin-point metadata** (a table of 51 models, Lua-side): nothing gained in the sample, so it is not
justified yet.

## 3b. Exact endpoint for the miss check

`susceptibility.py endpoint` scores the variant on every cached row: the saved vanilla benchmark
(re-scored through the production MD model), the vanilla and SWI sample, and the beam supplement. MESH
model.

**Only information the mod has.**

- **Where it applies.** Only where production has already established the aim direction, and only for
  the non-beam extended line. There the aim point is known: a no-collection target's recovered box
  centre, or the authored point both orientations select.
- **Distance.** The dot product of the muzzle-to-point offset with the unit `rotation.forward` the MD
  already builds. `.length` and `distanceto` are approximate.
- **Factor `f`.** 1 unless the target can move, which only a whole ship or a ship engine can; then the
  conservative maximum.
- **Line length:** `f × distance × (1 + 1e-4) + 1 m`.

**Precision.** In-game positions and MD arithmetic are lower precision than this model, and X4 computes
its own endpoint independently.

- The margin must be positive and exceed that error. A larger margin is only more conservative: the
  line sees more.
- In every recovered row the blocking hit lies 5.5 m or more past X4's endpoint (median 9 m).
- All 58 recoveries survive any margin up to 5 m absolute or 1e-4 relative; a 0.1 % relative margin
  loses 2.
- 1 m + 1e-4 is chosen as far above plausible in-game rounding while staying inside that gap. This is
  an offline population result, not a guarantee.

| rows (MESH) | production U on PERMIT | exact endpoint U on PERMIT | recovered as correct CLEAR | new false CLEAR / BLOCKED |
|---|---:|---:|---:|---:|
| vanilla station surface, non-beam | 30 | 0 | 30 | 0 / 0 |
| vanilla ship surface, non-beam | 6 | 0 | 6 | 0 / 0 |
| SWI ship surface, non-beam | 25 | 3 | 22 | 0 / 0 |
| all other classes, and every beam row | unchanged | unchanged | 0 | 0 / 0 |

- **Every recovery is an off-mesh shot:** X4's line reaches the aim point without touching the element,
  and the old line went on to hit the parent module or hull just past it.
- **Ordinary shots, where X4's line meets the element, are unchanged in every class.**
- **Beams are untouched.** Their line is X4's own barrel line to R: 302 / 2 / 636 on vanilla ship
  surfaces, 277 / 0 / 20 with 16 U on vanilla whole ships, all identical.
- **Rays.** No new ray type, and the worst case stays 6. The mean rises slightly where a shorter line no
  longer meets a target member past the aim point and so also needs the sector check: vanilla ship
  surface off-mesh 4.14 → 4.42, station root off-mesh 4.54 → 5.06, other groups unchanged.
- **The 3 remaining SWI UNKNOWNs** (`nebulonc`, 2 missile-turret types) are shots X4 permits through its
  result-0 second ray: the parent hull is hit first, then the re-cast to the element's origin hits the
  element. The vanilla benchmark never showed this. The mod cannot see which way that second ray goes, so
  UNKNOWN is correct here.

**Exceptions: the endpoint cannot safely be known** (these rows keep the conservative bound or the
probe):

- **Large-target whole ships:** vanilla 38 saved and 80 sample U on PERMIT. X4 may aim at the LargeTarget
  offset (section 3a).
- **SWI whole ships with an ambiguous direction** (outside-box family): 4 U on PERMIT, 3 U on NOT.
- **SWI single aim point at the origin:** 3 U on NOT. The mod reads these as no collection and would aim
  at the box centre, while X4 aims at the origin.
- **No-collision elements:** not in any cached row, because the benchmark selects only elements with a
  body. X4 can only miss them, so the exact endpoint is exactly the case they need; it is unmeasured.

## 3a. Dual check only when the guarded check returns UNKNOWN

`susceptibility.py compare` scores three strategies on the same saved rows: the large-target whole-ship
rows of the sample, plus a 16-scene beam supplement (`susceptibility.py beams`). That is L2's beam
loadout, `kha_m_beam_01`, against the same four vanilla hosts, because the sample's loadout A carried no
beam. There are 175 scored turret results, 27 of them beams. MESH model.

- **Guarded check:** production. The direction is ambiguous, so it runs only the probe, and a beam's
  probe counts only when the aim point is surely within R.
- **Conditional dual:** the guarded check first; the dual check runs only if that returns UNKNOWN. A
  non-beam dual reuses the probe already cast as its centre chain's first ray.

| strategy | turrets | TP | FP | TN | FN | U on PERMIT | U on NOT | mean rays | observed max | theoretical max |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| production | non-beam (148) | 62 | 0 | 0 | 0 | 80 | 6 | 1.00 | 1 | 1 |
| | beam (27) | 11 | 0 | 0 | 0 | 14 | 2 | 0.96 | 1 | 1 |
| always dual | non-beam | 141 | 0 | 6 | 0 | 1 | 0 | 6.13 | 11 | 12 |
| | beam | 19 | 0 | 1 | 0 | 6 | 1 | 4.63 | 6 | 6 |
| **conditional dual** | non-beam | 141 | 0 | 6 | 0 | 1 | 0 | **5.24** | 11 | 12 |
| | beam | 19 | 0 | 1 | 0 | 6 | 1 | **3.96** | 7 | 7 |

- **Accuracy is identical.** Accepting the first probe's CLEAR never disagrees with always-dual: every
  first-probe CLEAR is also the always-dual answer. No row gains a false CLEAR or a false BLOCKED.
- **Coverage.** The conditional dual recovers 79 of 80 non-beam and 8 of 14 beam false UNKNOWNs.
  - The 6 remaining beam UNKNOWNs are cases where the centre and offset lines disagree along the barrel.
  - The 1 remaining non-beam UNKNOWN is the same kind of disagreement.
- **Cost:**
  - The dual runs on 102 of 175 turret results; the other 73 end at the first probe.
  - Mean rays fall by 0.9 (non-beam) and 0.7 (beam) against always-dual.
  - A beam's worst case is one ray more (7 against 6), because the conditional casts the probe first.
- **Theoretical maximum** is 12 rays for a non-beam turret: the shared probe, then the rest of both
  chains (the centre chain's 5 remaining rays plus the offset chain's 6). For a beam it is 7: the probe,
  then two chains of 3. The sample's observed maxima are 11 and 7.
- **Other work.** Rays are not the whole cost.
  - Only the 4-orientation collection test tells a script that a target is a large-target one.
    Production and the conditional run it (and need the recovered target box) for 113 of 175 turrets:
    beams, and non-beams after a failed probe.
    Always-dual must run it for all 175 before it can choose its method.
  - Box recovery stays once per target per pass, 19 property reads.
  - Only when the dual runs, the offset adds: the turret's position in the firing ship's frame (one
    position conversion), the firing ship's box (its macro box, or one more 19-read recovery per pass)
    and a few position conversions. There are no extra orientations.

**Evidence supports the conditional dual.** It matches always-dual's accuracy on every sampled row. It
costs fewer rays on average and skips the orientation and box work wherever the first probe already
decides. Its only cost above always-dual is one extra ray in a beam's worst case.

## 4. Recommendation

The next implementation experiment:

1. **Exact endpoint for the miss check** (section 3b). It needs no new ray and recovers every measured
   off-mesh element UNKNOWN in vanilla and 22 of 25 in SWI, with no false result. Use a positive margin
   of about 1 m + 1e-4 × distance for in-game precision.
2. **The large-target dual check, run conditionally** (section 3a): only when the guarded check returns
   UNKNOWN, for whole-ship targets that fail the collection test and have a recovered box radius over
   500 m. That covers 36 vanilla models, among them 29 of the 31 XL, and
   `mandator`.
   - It recovers about half of permitted shots at nearly every vanilla XL ship.
   - It costs up to 12 rays (non-beam) or 7 (beam) for those turrets, theoretically; the observed maxima
     are 11 and 7.
   - The owner must accept exceeding the 6-ray cap for these targets.

**Smallest LIVE test.** Stationary shooter and target, with the per-turret log (`event=line_of_fire`)
correlated against FIRED:

- a destroyer with about 6 turrets against a vanilla XL large-target ship such as
  `ship_arg_xl_carrier_01`, where production reads mostly UNKNOWN;
- the same shooter against one off-mesh element, such as a `turret_spl_m_*` turret or
  `shield_xen_m_standard_02`.

These verify that the UNKNOWN turrets really fire, and that the fixes' CLEAR matches FIRED. The SWI
hull-loading question needs SWI installed, and it is not.
