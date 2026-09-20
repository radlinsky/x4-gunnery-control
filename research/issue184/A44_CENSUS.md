# A4.4 ship aim-point census — two separate games

Offline source research, status **inference** (from `shipped-source` and
`third-party-technique` XML). No X4 launch, no production change.

```sh
python3 research/issue184/extract_swi_assets.py <SWI 0.9.1 HF mod dir>  # once: assets/ and index/
python3 research/issue184/ship_aimpoint_census.py                       # ~6 min, both games
```

The command censuses **two independent populations** and writes one JSON row per
ship component to the ignored `.x4-research-cache/issue184/a44_census_vanilla.jsonl`
and `a44_census_swi.jsonl`. Exact authored coordinates live only there:
unpacked game and third-party mod source stays out of the repository, so the
tables below carry component identity, counts and layout structure.

## Question

Can Gunnery Control reconstruct a ship's aim points from authored ship data and
simple runtime-visible facts, instead of asking X4 repeatedly?

## Two games, never one population

SWI 0.9.1 HF is an overhaul. Its ships and a vanilla game's ships never coexist,
so a statistic pooled over both describes no real game and is not published here.

- **VANILLA** — pristine X4 9.00. No SWI file, patch, replacement, index entry
  or case alias is applied.
- **SWI** — X4 9.00 with SWI 0.9.1 HF applied. A SWI-game ship is any component
  behind a `ship_s`/`ship_m`/`ship_l`/`ship_xl` macro in the effective SWI
  index: SWI's own ships plus the official ships as SWI patches them.

The separation is structural, not a label on a row. `census(with_swi)` runs in
its own forked child from an unmutated parent, so the SWI overlay's index edits
cannot reach the vanilla child.

**Measured cost of the old contamination.** Comparing the 203 official
components across the two runs: no aim point differs, no box value differs, no
macro list differs, and exactly **one** row changes — `ship_xen_m_miner_01`,
whose runtime box is reconstructible in vanilla but not under SWI, because SWI
replaces its macro with one referencing a shield macro absent from 9.00. The
earlier pooled report was therefore right about vanilla *counts* but wrong to
present pooled *pattern* statistics as if they described either game; see
*What the split changed*.

## Which SWI catalogs the census reads

SWI 0.9.1 HF ships five catalogs. Only `ext_01` holds census input, audited by
entry rather than by name:

| catalog | entries | contents | relevant? |
|---|--:|---|---|
| `ext_01` | 26,630 | `assets/**` (25,526), `index/**` (2), plus voice, sfx, music, cutscenes, maps, legacy textures and 93 `extensions/<dlc>/**` files | **yes** — `assets/**.xml` and `index/**.xml` are read |
| `ext_02` | 345 | `md/`, `aiscripts/`, `libraries/`, `t/` | no — no `assets/`, no `index/`; all 64 library files are `<diff>` and none defines a component or macro |
| `subst_01` | 513 | 500 voice, 13 loading-screen textures | no — contains no XML at all |
| `subst_02` | 20 | `ui/addons/**.xpl` | no — contains no XML at all |
| `subst_03` | 20 | Timelines loading-screen `.jpg`/`.dds` | no — contains no XML at all |

`subst_*` catalogs can replace base-game files outright, so "no SWI `<diff>`
touches an `aimtarget`" would not on its own have settled them. It is settled by
their actual entries: none of the three carries a single XML file.

Within `ext_01`, the entries outside `assets/` and `index/` were checked too.
`maps/**` defines 2,278 macros, all `cluster`, `sector`, `zone` or `galaxy`
class. The 61 `extensions/<dlc>/assets/**.xml` files are station habitat,
defence, storage, production, dock-pier and cluster-background definitions and
diffs. No ship-class definition exists anywhere outside the extracted
`assets/**`. Decisively, instrumenting `sources.component`/`sources.macro`
across a full census run records 1,664 distinct names touched while resolving
every census ship and reconstructing every runtime box, against 2,483 names the
ignored catalogs define or patch: **the two sets do not intersect.**

`extract_swi_assets.py` re-runs the catalog half of this audit on every
extraction and fails if a future SWI release moves ship or index XML out of
`ext_01`.

## How SWI is applied

`aimpoint_map._index_swi_ships` skips SWI `<diff>` patches and same-name
replacements, which is sound for the benchmark but would make a *complete* SWI
census wrong. The SWI census applies them: 214 diff files patch an official file
at the same relative path (443 `<remove>`, 932 `<replace>`, 5 `<add>`
operations, mostly deleting or retagging connections that feed the runtime box),
and 23 SWI definitions replace an official one outright.

- **No SWI diff anywhere touches an `aimtarget` connection.** Every SWI-visible
  aim point is authored in a full component definition, patched or not.
- SWI refers to four official assets with different capitalisation
  (`bridge_arg_Xl_01_macro`). X4 resolves those; an exact-name index does not.
- SWI defines 41 names in two files each; X4's name index decides which is
  effective, see *Duplicate definitions*.

---

# VANILLA — pristine X4 9.00

**203 unique ship components, 285 macros, 39 authored aim points.** Every
runtime box reconstructs; **nothing is unresolved.**

| class | components |
|---|--:|
| `ship_s` | 69 |
| `ship_m` | 54 |
| `ship_l` | 49 |
| `ship_xl` | 31 |

## Aim-point count distribution

| points | components |
|---:|--:|
| 0 | 184 |
| 1 | 5 |
| 2 | 9 |
| 3 | 4 |
| 4 | 1 |

**184 of 203 vanilla ship components author no `aimtarget` connection** —
independently reproduced from untouched official source. Only these 19 do:

`ship_arg_l_destroyer_02`, `ship_arg_xl_carrier_02`, `ship_bor_l_destroyer_01`,
`ship_bor_l_miner_liquid_01`, `ship_bor_l_miner_solid_01`,
`ship_bor_l_trans_container_01`, `ship_gen_s_fightingdrone_01`,
`ship_kha_l_destroyer_01`, `ship_par_l_expeditionary_01`,
`ship_pir_s_fighter_01`, `ship_pir_s_heavyfighter_01`,
`ship_tel_l_destroyer_01`, `ship_tel_l_destroyer_02`,
`ship_tel_l_miner_liquid_02`, `ship_tel_l_miner_solid_02`,
`ship_tel_l_trans_container_03`, `ship_ter_xl_carrier_01`,
`ship_ter_xl_resupplier_01`, `ship_xen_m_fighter_01`.

For the other 184 the authored data fixes no point whatsoever. The native
selector's empty-collection branch decides, and
[macro-box-aimtargets.md](../../.agents/skills/research-x4-modding/references/macro-box-aimtargets.md)
explicitly does not characterize that branch. **In a vanilla game this is 91% of
ships**, so "reconstruct the authored points" is not the main question there —
what the engine does with an empty collection is.

## One-point components (5)

| test | result |
|---|--:|
| exactly the component origin | **0 of 5** |
| exactly the runtime-box centre | **0 of 5** |
| `x` exactly 0 | 5 of 5 |
| inside its own runtime box | 5 of 5 |

They sit 5–207 m from their origin (median 107 m) and 159 m median from the box
centre — authored spots on the hull, nowhere near either candidate. Normalized
|n| reaches only (0.060, 0.447, 0.522), so none is near a box face either.

## Multi-point components (14)

| property | count |
|---|---|
| fully left/right symmetric | 9 / 14 exactly, 11 / 14 within 1 mm |
| all points on the `x = 0` centreline | 8 / 14 |
| all points at one `y` (flat) | 8 / 14 |
| every point at `y = 0` exactly | 6 / 14 |
| dominant spread along `z` | 12 / 14 (x 2) |
| distinct layouts | 12 (2 layouts shared) |
| **points outside their own runtime box** | **0 / 34** |
| `z` on an exact even grid (≥3 distinct z) | 0 / 3 eligible |

Asymmetric even at 1 mm: `ship_pir_s_heavyfighter_01`, `ship_ter_xl_carrier_01`,
`ship_ter_xl_resupplier_01`. Two more, `ship_arg_l_destroyer_02` and
`ship_arg_xl_carrier_02`, are mirrored only to 1 mm: their authored x values are
`115.116` against `-115.1163` and `406.3699` against `-406.3702`. That 0.3 mm
gap is in the source text, not float32 noise, so an *exact* symmetry rule has
counterexamples that a millimetre-tolerant one does not.

| component | class | macros | pts | layout |
|---|---|---:|---:|---|
| `ship_arg_xl_carrier_02` | xl | 1 | 4 | sym to 1 mm, y-spread 244 m, 1 ±x pair(s) |
| `ship_arg_l_destroyer_02` | l | 1 | 3 | sym to 1 mm, y-spread 18 m, 1 ±x pair(s) |
| `ship_gen_s_fightingdrone_01` | s | 2 | 3 | sym, y-spread 0 m, 1 ±x pair(s) |
| `ship_ter_xl_carrier_01` | xl | 1 | 3 | **asym**, flat, 0 ±x pair(s) |
| `ship_ter_xl_resupplier_01` | xl | 1 | 3 | **asym**, y-spread 47 m, 0 ±x pair(s) |
| `ship_bor_l_miner_liquid_01` | l | 1 | 2 | sym, flat, all on x=0 |
| `ship_bor_l_miner_solid_01` | l | 2 | 2 | sym, flat, all on x=0 |
| `ship_par_l_expeditionary_01` | l | 1 | 2 | sym, y-spread 5 m, all on x=0 |
| `ship_pir_s_heavyfighter_01` | s | 1 | 2 | **asym**, y-spread 2 m, 0 ±x pair(s) |
| `ship_tel_l_destroyer_01` | l | 2 | 2 | sym, flat, all on x=0 |
| `ship_tel_l_destroyer_02` | l | 1 | 2 | sym, flat, all on x=0 |
| `ship_tel_l_miner_liquid_02` | l | 1 | 2 | sym, flat, all on x=0 |
| `ship_tel_l_miner_solid_02` | l | 1 | 2 | sym, flat, all on x=0 |
| `ship_tel_l_trans_container_03` | l | 1 | 2 | sym, flat, all on x=0 |

## Vanilla direct reconstruction

Of 39 authored points: 27 on the `x = 0` centreline, 2 in exact ±x twin pairs,
**10 neither** (6 neither at 1 mm tolerance). Box length against point count
gives Pearson r = 0.531, and the length buckets show why that is useless — the
0-versus-1 point split, which is the one that matters, is invisible:

| box length | components | point counts |
|---|--:|---|
| 0–100 m | 76 | 73 zero, 1, 1, 1 |
| 100–300 m | 47 | 46 zero, 1 |
| 300–1000 m | 37 | 29 zero, then 1–3 points |
| >1000 m | 43 | 36 zero, then 1–4 points |

---

# SWI — X4 9.00 with SWI 0.9.1 HF applied

**429 unique ship components, 542 macros, 834 authored aim points.** 425 boxes
reconstruct; 4 do not.

| definition origin | ship_s | ship_m | ship_l | ship_xl |
|---|--:|--:|--:|--:|
| official files, as SWI patches them | 69 | 54 | 49 | 31 |
| SWI files | 70 | 57 | 67 | 32 |

## Aim-point count distribution

| points | components | from official files | from SWI files |
|---:|--:|--:|--:|
| 0 | 185 | 184 | 1 |
| 1 | 102 | 5 | 97 |
| 2 | 30 | 9 | 21 |
| 3 | 33 | 4 | 29 |
| 4 | 28 | 1 | 27 |
| 5 | 11 | 0 | 11 |
| 6 | 13 | 0 | 13 |
| 7 | 11 | 0 | 11 |
| 8 | 5 | 0 | 5 |
| 9 | 4 | 0 | 4 |
| 11 | 2 | 0 | 2 |
| 12 | 1 | 0 | 1 |
| 13 | 1 | 0 | 1 |
| 14 | 1 | 0 | 1 |
| 57 | 2 | 0 | 2 |

A SWI game still has 185 ships that author nothing — 43% of its population,
far less dominant than vanilla's 91%, because SWI authors points on nearly all
of its own ships.

## One-point components (102)

| test | all 102 | from official files (5) | from SWI files (97) |
|---|--:|--:|--:|
| exactly the component origin | 47 | 0 | 47 |
| exactly the runtime-box centre | 18 | 0 | 18 |
| `x` exactly 0 | 102 | 5 | 97 |
| inside its own runtime box | 102 | 5 | 97 |

The SWI half looks origin-like only because 47 SWI ships are modelled about
their aim point; 50 are not, up to 49 m out. The single exact rule across the
whole population is `x = 0` — one coordinate of three.

## Multi-point components (142: 128 SWI-authored, 14 official)

| property | count |
|---|---|
| fully left/right symmetric | 136 / 142 exactly, 138 / 142 within 1 mm |
| all points on the `x = 0` centreline | 94 / 142 |
| all points at one `y` (flat) | 75 / 142 |
| every point at `y = 0` exactly | 57 / 142 |
| dominant spread along `z` | 131 / 142 (x 8, y 3) |
| distinct layouts | 101 (31 shared by more than one component) |
| **points outside their own runtime box** | **8 / 715** |
| `z` on an exact even grid (≥3 distinct z) | 9 / 100 eligible |

Asymmetric even at 1 mm: `cor_scrapper`, `ship_pir_s_heavyfighter_01`,
`ship_ter_xl_carrier_01`, `ship_ter_xl_resupplier_01`.

Outside their own runtime box: `cor_scrapper` (2 points), `quasar_imp` (2),
`quasar_reb` (2), `ship_mando_s_n1_menu` (1), `yv666` (1), reaching a normalized
|n| of 3.17 on x. **Every one of these is SWI-authored** — vanilla has none —
but they corroborate at corpus scale the reference's refusal to assume
aim-point containment.

| component | origin | class | macros | pts | layout |
|---|---|---|---:|---:|---|
| `ship_arg_xl_carrier_02` | official | xl | 1 | 4 | sym to 1 mm, y-spread 244 m, 1 ±x pair(s) |
| `ship_arg_l_destroyer_02` | official | l | 1 | 3 | sym to 1 mm, y-spread 18 m, 1 ±x pair(s) |
| `ship_gen_s_fightingdrone_01` | official | s | 2 | 3 | sym, y-spread 0 m, 1 ±x pair(s) |
| `ship_ter_xl_carrier_01` | official | xl | 1 | 3 | **asym**, flat, 0 ±x pair(s) |
| `ship_ter_xl_resupplier_01` | official | xl | 1 | 3 | **asym**, y-spread 47 m, 0 ±x pair(s) |
| `ship_bor_l_miner_liquid_01` | official | l | 1 | 2 | sym, flat, all on x=0 |
| `ship_bor_l_miner_solid_01` | official | l | 2 | 2 | sym, flat, all on x=0 |
| `ship_par_l_expeditionary_01` | official | l | 1 | 2 | sym, y-spread 5 m, all on x=0 |
| `ship_pir_s_heavyfighter_01` | official | s | 1 | 2 | **asym**, y-spread 2 m, 0 ±x pair(s) |
| `ship_tel_l_destroyer_01` | official | l | 2 | 2 | sym, flat, all on x=0 |
| `ship_tel_l_destroyer_02` | official | l | 1 | 2 | sym, flat, all on x=0 |
| `ship_tel_l_miner_liquid_02` | official | l | 1 | 2 | sym, flat, all on x=0 |
| `ship_tel_l_miner_solid_02` | official | l | 1 | 2 | sym, flat, all on x=0 |
| `ship_tel_l_trans_container_03` | official | l | 1 | 2 | sym, flat, all on x=0 |
| `ship_imperial_xxl_executer_01` | swi | xl | 2 | 57 | sym, flat, 18 ±x pair(s) |
| `ship_imperial_xxl_executer_proto` | swi | xl | 1 | 57 | sym, flat, 18 ±x pair(s) |
| `bellator` | swi | xl | 1 | 14 | sym, y-spread 460 m, 2 ±x pair(s) |
| `praetor` | swi | xl | 1 | 13 | sym, flat, 2 ±x pair(s) |
| `mc80_homeone` | swi | xl | 2 | 12 | sym, flat, all on x=0 |
| `hapan_l` | swi | l | 1 | 11 | sym, y-spread 158 m, 3 ±x pair(s), box unresolved |
| `mc85` | swi | xl | 1 | 11 | sym, flat, all on x=0 |
| `imp_cruiser_546` | swi | l | 1 | 9 | sym, y-spread 76 m, 2 ±x pair(s) |
| `proclamator` | swi | l | 1 | 9 | sym, y-spread 133 m, 2 ±x pair(s) |
| `ship_providence_carrier_01` | swi | xl | 1 | 9 | sym, y-spread 125 m, all on x=0 |
| `subjugator_class` | swi | xl | 1 | 9 | sym, flat, all on x=0 |
| `immobilizer_418` | swi | l | 2 | 8 | sym, y-spread 82 m, 3 ±x pair(s) |
| `imp_light_cruiser` | swi | l | 2 | 8 | sym, flat, 2 ±x pair(s) |
| `lucrehulk_a` | swi | xl | 1 | 8 | sym, flat, 3 ±x pair(s) |
| `lucrehulk_b` | swi | xl | 1 | 8 | sym, flat, 3 ±x pair(s) |
| `lucrehulk_f` | swi | xl | 1 | 8 | sym, flat, 3 ±x pair(s) |
| `bff_01` | swi | m | 1 | 7 | sym, y-spread 9 m, 2 ±x pair(s) |
| `c9979` | swi | l | 1 | 7 | sym, y-spread 13 m, 2 ±x pair(s) |
| `heraklon_liquid` | swi | l | 1 | 7 | sym, y-spread 98 m, 1 ±x pair(s) |
| `heraklon_solid` | swi | l | 1 | 7 | sym, y-spread 98 m, 1 ±x pair(s) |
| `isd_1` | swi | xl | 3 | 7 | sym, y-spread 424 m, 1 ±x pair(s) |
| `isd_2` | swi | xl | 2 | 7 | sym, y-spread 424 m, 1 ±x pair(s) |
| `keldabe` | swi | xl | 2 | 7 | sym, y-spread 47 m, 1 ±x pair(s) |
| `mc80` | swi | xl | 2 | 7 | sym, flat, 1 ±x pair(s) |
| `mc80carrier` | swi | xl | 1 | 7 | sym, flat, 1 ±x pair(s) |
| `procursator` | swi | xl | 2 | 7 | sym, y-spread 190 m, 1 ±x pair(s) |
| `victory_2` | swi | l | 1 | 7 | sym, y-spread 249 m, 1 ±x pair(s) |
| `cis_escort_carrier` | swi | l | 1 | 6 | sym, y-spread 146 m, 2 ±x pair(s) |
| `enforcer` | swi | l | 1 | 6 | sym, y-spread 89 m, 2 ±x pair(s) |
| `fulgor` | swi | l | 1 | 6 | sym, y-spread 175 m, 1 ±x pair(s) |
| `harrower` | swi | xl | 1 | 6 | sym, flat, 1 ±x pair(s) |
| `harrower_i` | swi | xl | 1 | 6 | sym, flat, 1 ±x pair(s) |
| `kontos` | swi | l | 1 | 6 | sym, flat, 1 ±x pair(s) |
| `mc40a` | swi | l | 1 | 6 | sym, flat, 1 ±x pair(s) |
| `mc40b` | swi | l | 1 | 6 | sym, flat, 1 ±x pair(s) |
| `recusant` | swi | xl | 1 | 6 | sym, y-spread 174 m, all on x=0 |
| `valor_01` | swi | l | 1 | 6 | sym, y-spread 214 m, all on x=0 |
| `valor_02` | swi | l | 1 | 6 | sym, y-spread 214 m, all on x=0 |
| `vigilfinal` | swi | l | 2 | 6 | sym, y-spread 42 m, 1 ±x pair(s) |
| `vindicator` | swi | l | 2 | 6 | sym, y-spread 89 m, 2 ±x pair(s) |
| `cor_scrapper` | swi | l | 1 | 5 | **asym**, y-spread 14 m, 1 ±x pair(s), **outside box** |
| `genosian_cruiser` | swi | l | 1 | 5 | sym, y-spread 25 m, 1 ±x pair(s) |
| `mc75` | swi | xl | 1 | 5 | sym, flat, all on x=0 |
| `mc80crain` | swi | xl | 1 | 5 | sym, flat, all on x=0 |
| `mc80liner` | swi | xl | 1 | 5 | sym, flat, all on x=0 |
| `mc80r` | swi | xl | 2 | 5 | sym, flat, all on x=0 |
| `munificent_01` | swi | xl | 1 | 5 | sym, y-spread 152 m, all on x=0 |
| `teroch` | swi | l | 1 | 5 | sym, y-spread 100 m, all on x=0 |
| `venator_01` | swi | xl | 2 | 5 | sym, y-spread 178 m, all on x=0 |
| `venator_ce` | swi | xl | 1 | 5 | sym, y-spread 178 m, all on x=0 |
| `venator_hutt` | swi | xl | 1 | 5 | sym, y-spread 178 m, all on x=0 |
| `acclamator1` | swi | l | 1 | 4 | sym, flat, 1 ±x pair(s) |
| `acclamator2` | swi | l | 1 | 4 | sym, flat, 1 ±x pair(s) |
| `allocator` | swi | xl | 1 | 4 | sym, flat, all on x=0 |
| `cr90_01a` | swi | m | 2 | 4 | sym, flat, all on x=0 |
| `cr90_01as` | swi | m | 1 | 4 | sym, flat, all on x=0 |
| `cr90_01b` | swi | m | 1 | 4 | sym, flat, all on x=0 |
| `cr90_01d` | swi | m | 1 | 4 | sym, flat, all on x=0 |
| `hardcell_frigate` | swi | l | 1 | 4 | sym, flat, all on x=0 |
| `hardcell_liquid` | swi | l | 1 | 4 | sym, flat, all on x=0 |
| `hardcell_solid` | swi | l | 1 | 4 | sym, flat, all on x=0 |
| `hardcell_trade` | swi | l | 1 | 4 | sym, flat, all on x=0 |
| `lancerfrigate` | swi | l | 2 | 4 | sym, flat, all on x=0 |
| `neutronstar` | swi | l | 1 | 4 | sym, y-spread 19 m, all on x=0 |
| `neutronstar_builder` | swi | l | 1 | 4 | sym, y-spread 19 m, all on x=0 |
| `neutronstar_trade` | swi | l | 1 | 4 | sym, y-spread 19 m, all on x=0 |
| `pelta_01` | swi | l | 1 | 4 | sym, flat, all on x=0 |
| `pelta_02` | swi | l | 1 | 4 | sym, flat, all on x=0 |
| `praetorian_01` | swi | l | 1 | 4 | sym, y-spread 8 m, all on x=0 |
| `praetorian_02` | swi | l | 1 | 4 | sym, y-spread 8 m, all on x=0 |
| `quasar_imp` | swi | l | 1 | 4 | sym, y-spread 19 m, 1 ±x pair(s), **outside box** |
| `quasar_reb` | swi | l | 1 | 4 | sym, flat, 1 ±x pair(s), **outside box** |
| `responder_frigate_liquid` | swi | l | 1 | 4 | sym, y-spread 49 m, all on x=0 |
| `responder_frigate_solid` | swi | l | 1 | 4 | sym, y-spread 49 m, all on x=0 |
| `responder_frigate_trade` | swi | l | 1 | 4 | sym, y-spread 49 m, all on x=0 |
| `ship_gen_resupplier_01` | swi | xl | 1 | 4 | sym, flat, all on x=0 |
| `ship_mando_xl_kandosii_01` | swi | xl | 2 | 4 | sym, y-spread 26 m, all on x=0 |
| `velox` | swi | l | 1 | 4 | sym, flat, all on x=0 |
| `actioniv` | swi | m | 1 | 3 | sym, y-spread 7 m, all on x=0 |
| `actioniv_gas` | swi | m | 1 | 3 | sym, y-spread 7 m, all on x=0 |
| `actioniv_solid` | swi | m | 1 | 3 | sym, y-spread 7 m, all on x=0 |
| `arquitens` | swi | l | 1 | 3 | sym, flat, 1 ±x pair(s) |
| `arrestor_cruiser` | swi | l | 1 | 3 | sym, flat, 1 ±x pair(s) |
| `cis_cruiser` | swi | l | 1 | 3 | sym, flat, all on x=0 |
| `cis_refractory` | swi | l | 1 | 3 | sym, y-spread 360 m, all on x=0 |
| `cis_repair` | swi | m | 1 | 3 | sym, flat, all on x=0 |
| `cr70_01a` | swi | m | 1 | 3 | sym, y-spread 2 m, all on x=0 |
| `cr70_01con` | swi | m | 1 | 3 | sym, y-spread 2 m, all on x=0 |
| `crusader` | swi | m | 1 | 3 | sym, y-spread 2 m, all on x=0 |
| `diamond_cruiser` | swi | l | 1 | 3 | sym, y-spread 267 m, all on x=0 |
| `diamond_cruiser_civ` | swi | l | 1 | 3 | sym, y-spread 267 m, all on x=0 |
| `dorean_corvette` | swi | m | 1 | 3 | sym, flat, all on x=0 |
| `dreadnaught_alliance` | swi | l | 1 | 3 | sym, flat, all on x=0, box unresolved |
| `dreadnaught_katana` | swi | l | 1 | 3 | sym, flat, all on x=0, box unresolved |
| `eta_class_supply_barge` | swi | l | 1 | 3 | sym, flat, all on x=0 |
| `gs80` | swi | m | 1 | 3 | sym, flat, all on x=0 |
| `hammerheadcruiser` | swi | l | 1 | 3 | sym, y-spread 4 m, all on x=0 |
| `hammerheadcruiser_red` | swi | l | 2 | 3 | sym, y-spread 4 m, all on x=0 |
| `hapan_nova` | swi | l | 1 | 3 | sym, flat, 1 ±x pair(s) |
| `interceptor_frigate` | swi | l | 1 | 3 | sym, flat, all on x=0 |
| `mando_assault_ship` | swi | l | 1 | 3 | sym, y-spread 73 m, all on x=0 |
| `overseer` | swi | l | 1 | 3 | sym, flat, all on x=0 |
| `sith_destroyer` | swi | l | 1 | 3 | sym, flat, all on x=0 |
| `sith_freighter` | swi | l | 1 | 3 | sym, flat, all on x=0 |
| `sorosub3000` | swi | m | 1 | 3 | sym, y-spread 2 m, all on x=0 |
| `storm` | swi | l | 1 | 3 | sym, y-spread 55 m, all on x=0 |
| `terminus_ship` | swi | l | 1 | 3 | sym, y-spread 54 m, all on x=0 |
| `aa9_liquid` | swi | l | 1 | 2 | sym, flat, all on x=0 |
| `aa9_solid` | swi | l | 1 | 2 | sym, flat, all on x=0 |
| `civ_l_transport` | swi | l | 1 | 2 | sym, y-spread 18 m, all on x=0 |
| `defender_corvette` | swi | m | 1 | 2 | sym, flat, all on x=0 |
| `hammerhead_corvette` | swi | m | 1 | 2 | sym, y-spread 1 m, all on x=0 |
| `hwk_290_01` | swi | s | 2 | 2 | sym, y-spread 1 m, all on x=0 |
| `laat` | swi | s | 1 | 2 | sym, y-spread 3 m, all on x=0 |
| `nebulonb_01e` | swi | l | 2 | 2 | sym, flat, all on x=0 |
| `nebulonb_01p` | swi | l | 1 | 2 | sym, flat, all on x=0 |
| `nebulonc` | swi | l | 1 | 2 | sym, y-spread 40 m, all on x=0 |
| `raider` | swi | m | 1 | 2 | sym, flat, all on x=0 |
| `rebel_tanker` | swi | m | 1 | 2 | sym, flat, all on x=0 |
| `rebel_tanker_liquid` | swi | m | 1 | 2 | sym, flat, all on x=0 |
| `rebel_tanker_solid` | swi | m | 1 | 2 | sym, flat, all on x=0 |
| `ship_mando_s_n1` | swi | s | 1 | 2 | sym, flat, all on x=0 |
| `ship_mando_s_n1_menu` | swi | s | 1 | 2 | sym, flat, all on x=0, **outside box** |
| `yv666` | swi | m | 1 | 2 | sym, y-spread 13 m, all on x=0, **outside box** |
| `ywing_btla4` | swi | s | 2 | 2 | sym, flat, all on x=0 |
| `ywing_btla4long` | swi | s | 1 | 2 | sym, flat, all on x=0 |
| `ywing_btlbpm` | swi | s | 1 | 2 | sym, flat, all on x=0 |
| `ywing_btlnr2` | swi | s | 1 | 2 | sym, flat, all on x=0 |

## SWI direct reconstruction

Of 834 authored points: 628 on the centreline, 194 in exact ±x twin pairs, 12
neither (8 at 1 mm). Box length against point count gives Pearson r = 0.926,
driven by the two 19 km executors and still unable to separate the cases that
matter: among 166 components under 100 m long, 73 have zero points and 81 have
exactly one.

---

# Findings across both games

## Exact, source-backed, true in both populations

1. The ordered point list is a property of the **component** and identical
   across every macro that uses it. The *box* is not: it varies by up to 25.2 m
   between a component's macros.
2. **No aim connection carries a `parent` attribute** (0 of 39 vanilla, 0 of
   834 SWI). The authored offset is already the component-frame position.
3. **Selection order is the native connection-name hash, not document order.**
   They differ for 112 of the 142 SWI multi-point components.
4. **Every one-point ship places its point on `x = 0`** (5/5 vanilla, 102/102
   SWI).

## Strong but with named counterexamples — not safe alone

5. Lateral symmetry. In SWI it covers 136 of 142 multi-point components, but in
   **vanilla only 9 of 14 exactly** (11 within 1 mm), with three genuinely
   asymmetric ships. The pooled figure flattered this badly.
6. Containment in the runtime box. Vanilla: no exception. SWI: 8 points
   outside, up to |n| = 3.17.
7. Multi-point layouts spreading along `z`: 12 of 14 vanilla, 131 of 142 SWI.

## Coincidence, not usable

8. Box length against point count: r = 0.531 vanilla, 0.926 SWI, and in neither
   game does length separate zero-point from one-point ships.
9. Even `z` grids: 0 of 3 eligible vanilla, 9 of 100 SWI.

## Verdict

**The authored data contains no general rule that reconstructs aim-point
positions, in either game.** They are hand-placed art constants. Nothing derives
them from the runtime box, the origin, the class or the size; the only exact
positional rule fixes one of three coordinates. Reconstruction from source is
possible only as a per-component lookup table built from ship XML — exactly what
A4.6 is told not to bake in for unknown DLC and mod ships — and in a vanilla
game even a complete table answers nothing for the 184 ships that author no
points.

## What A4.5 now has to ask

1. **What does the engine do when the defaults collection is empty?** This
   governs 91% of vanilla ships and 43% of SWI ships and is currently
   uncharacterized. It is the highest-value question in A4.5, above any count
   discriminator.
2. **Can a normal mod read the aim connections of a target at runtime** (count,
   order or position)? If it can, reconstruction is a lookup, not a probe.
3. **Is there any runtime-visible fact that separates zero-point from one-point
   from multi-point ships?** Neither census supports size class, box or box
   length: every class and every length bucket contains all three.

## What the split changed

Separating the games did not move a single ship row: the aim points, boxes and
macro lists are identical to the pooled run apart from `ship_xen_m_miner_01`'s
box. What it changed is which statistics are honest.

- Pooled "822 of 834 points are on the centreline or in a ±x twin" was a SWI
  statistic wearing both games' clothes. Vanilla's own figure is 29 of 39.
- Pooled "8 points outside their own box" attributed an entirely SWI-authored
  phenomenon to the corpus as a whole. Vanilla has none.
- Pooled "184 of 203 official ship components author no aimtarget" **survived**
  and is now reproduced from pristine source, with all 203 boxes resolving.
- Pooled symmetry counts hid a 0.3 mm authoring asymmetry on two vanilla ships,
  which the exact/1 mm split now states.

Unchanged: every exact rule above, the one-point result, the multi-point
component lists, and the verdict on direct reconstruction.

---

## Duplicate definitions and unresolved entries

**Duplicate component definitions, resolved (6 SWI ships).** SWI defines these
components in two files each, with a differing aim-point set. X4 does not
discover a component by scanning files: it resolves a name to exactly one file
through `index/components.xml`, and SWI adds its own entries there. The census
reads that index and keeps the file it names.

| component | file X4's index resolves it to | points | other definition, unused |
|---|---|---:|---|
| `mc80crain` | `assets/units/size_xl/mc80crain.xml` | 5 | `assets/units/size_xl/backup/mc80crain - Copy.xml` (0) |
| `mc80liner` | `assets/units/size_xl/mc80liner.xml` | 5 | `assets/units/size_xl/backup/mc80liner - Copy.xml` (0) |
| `mc80r` | `assets/units/size_xl/mc80r.xml` | 5 | `assets/units/size_xl/backup/mc80r - Copy.xml` (0) |
| `t65b_xwing` | `assets/units/size_s/t65b_xwing.xml` | 1 | `assets/units/size_s/t65xj3_xwing_data/t65b_xwing.xml` (0) |
| `t65b_xwing_01` | `assets/units/size_s/t65b_xwing_01.xml` | 1 | `assets/units/size_s/t65xj3_xwing_data/t65b_xwing_01.xml` (0) |
| `t65xj3_xwing` | `assets/units/size_s/t65xj3_xwing.xml` | 1 | `assets/units/size_s/t65xj3_xwing_data/t65xj3_xwing.xml` (0) |

**VANILLA unresolved: none.** All 203 components resolve and all 203 runtime
boxes reconstruct.

**SWI unresolved (8).**

| entry | why | effect |
|---|---|---|
| `n1pi` | SWI macro `n1pi_macro` references a component no source set defines | the only ship component missing entirely: 1 of 430 |
| `dreadnaught_alliance`, `dreadnaught_katana`, `hapan_l` | their SWI macros attach a dock child through a parent connection their own component does not define | aim points recorded; runtime box unresolved |
| `ship_xen_m_miner_01` | SWI replaces the vanilla macro with one referencing `ishield_xen_m_miner_01_a_macro`, absent from 9.00 | aim points recorded; runtime box unresolved. **Resolves normally in vanilla** |
| `swi/assets/structures/habitat/deathstar_01.xml` | malformed XML (mismatched tag, line 89) | class `habitation`, not a ship |
| 2 SWI diff files with no official file at their path | `fx/weaponFx/backup/…`, `structures/dock/macros/dockarea_arg_m_01_tradestation_01_macro.xml` | neither is a ship or a ship's box child |

The SWI census is complete for aim points at 429 of 430 components, and for the
runtime box at 425 of 430.

## Reconciliation with the earlier 50-ship figure

The #184 benchmark records **50 vanilla whole-ship target components with
authored aim points**; this census finds **19**. Both are correct — they count
different populations, and the difference is exact:

The 50 is the #167 corpus rule: components whose **own `class` attribute**
starts with `ship_`, that carry an `aimtarget` connection, and that some macro
references. Its class breakdown is `ship_xs` 31, `ship_l` 12, `ship_s` 3,
`ship_xl` 3, `ship_m` 1.

A4.4 scopes to the four classes Gunnery Control supports, `ship_s` through
`ship_xl`, excluding `ship_xs` — drones, cargo drones, boarding pods,
lasertowers and police vessels.

**50 − 31 `ship_xs` = 19**, and the 19 are the same components. No other
definitional difference contributes: both count components rather than macros,
both require a macro reference, and the macro-class and component-class routes
select the identical 19 ships here. Nothing is missing from either figure.
