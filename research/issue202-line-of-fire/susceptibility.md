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
| **exact endpoint for the miss check** | off-mesh aim points; the length bound overshooting the aim point | vanilla surfaces 36 → 0 false UNKNOWN; SWI surfaces 25 → 3 | 0 / 0 | unchanged (max 6 / 3) |
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

## 4. Recommendation

The next implementation experiment:

1. **Exact endpoint for the miss check.** It is zero-cost and recovers essentially all off-mesh and
   no-collision element UNKNOWNs in both games.
2. **The large-target dual check,** only for whole-ship targets that fail the collection test and have a
   recovered box radius over 500 m. That covers 36 vanilla models, among them 29 of the 31 XL, and
   `mandator`.
   - It recovers about half of permitted shots at nearly every vanilla XL ship.
   - It costs up to about 11 rays for those turrets.
   - An early exit when both probes agree on CLEAR keeps the common case at 2 rays.
   - The owner must accept exceeding the 6-ray cap for these targets.

**Smallest LIVE test.** Stationary shooter and target, with the per-turret log (`event=line_of_fire`)
correlated against FIRED:

- a destroyer with about 6 turrets against a vanilla XL large-target ship such as
  `ship_arg_xl_carrier_01`, where production reads mostly UNKNOWN;
- the same shooter against one off-mesh element, such as a `turret_spl_m_*` turret or
  `shield_xen_m_standard_02`.

These verify that the UNKNOWN turrets really fire, and that the fixes' CLEAR matches FIRED. The SWI
hull-loading question needs SWI installed, and it is not.
