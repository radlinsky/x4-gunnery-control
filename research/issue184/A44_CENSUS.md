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

- **VANILLA — 203 vanilla ships.** Pristine X4 9.00. No SWI file, patch,
  replacement, index entry or case alias is applied.
- **SWI — 226 SWI ships.** A SWI-game ship is a component behind a
  `ship_s`/`ship_m`/`ship_l`/`ship_xl` macro **defined in a SWI file**.

The source environment and the census population are different things. Building
SWI ships needs the full effective environment, because they attach vanilla
docks, bridges and shields; so every vanilla definition stays loaded and
available as a dependency. It does not follow that a vanilla ship is a SWI-game
ship. Membership is the definition's own origin, which the index already records
per file — no target-name list. **There is no 429-component "SWI game"
population; that figure counted surviving vanilla ship macros.**

The separation is structural, not a label on a row. `census(with_swi)` runs in
its own forked child from an unmutated parent, so the SWI overlay's index edits
cannot reach the vanilla child.

**Measured cost of the old pooling.** The 203 vanilla components resolve
identically in both source environments — no aim point, box value or macro list
differs — with one exception: `ship_xen_m_miner_01`'s runtime box reconstructs
in vanilla but not under SWI, because SWI replaces its macro with one
referencing a shield macro absent from 9.00. So the vanilla *data* was never
corrupted. What the pooled run got wrong was the *populations*: it counted those
203 vanilla ships as SWI-game ships and reported pattern statistics over the
union, which describes no game. See *What the split changed*.

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

# SWI — 226 SWI ships

**226 unique ship components, 257 macros, 795 authored aim points.** 223 boxes
reconstruct; 3 do not. Vanilla definitions remain loaded as dependencies and are
not members.

| class | components |
|---|--:|
| `ship_s` | 70 |
| `ship_m` | 57 |
| `ship_l` | 67 |
| `ship_xl` | 32 |

## Aim-point count distribution

| points | components |
|---:|--:|
| 0 | 1 |
| 1 | 97 |
| 2 | 21 |
| 3 | 29 |
| 4 | 27 |
| 5 | 11 |
| 6 | 13 |
| 7 | 11 |
| 8 | 5 |
| 9 | 4 |
| 11 | 2 |
| 12 | 1 |
| 13 | 1 |
| 14 | 1 |
| 57 | 2 |

**SWI authors aim points on essentially every ship it ships: 225 of 226.** The
sole exception is `mandator`, a `ship_xl` roughly 10.1 km long whose runtime box
reconstructs but which carries no `aimtarget` connection. This is the exact
opposite of vanilla, where 184 of 203 ships author nothing, and it is why the
two games must never be pooled: the earlier "185 author nothing" SWI figure was
184 vanilla ships wearing a SWI label plus this one real case.

## One-point components (97)

| test | result |
|---|--:|
| exactly the component origin | 47 of 97 |
| exactly the runtime-box centre | 18 of 97 |
| `x` exactly 0 | **97 of 97** |
| inside its own runtime box | 97 of 97 |

Nearly half of SWI's one-point ships are modelled about their aim point, but 50
are not, up to 49.5 m out (`customs_corvette`), so the origin is not a rule. The
box centre is weaker still. Only `x = 0` holds without exception — one
coordinate of three.

## Multi-point components (128)

| property | count |
|---|---|
| fully left/right symmetric | **127 / 128**, exactly and within 1 mm |
| all points on the `x = 0` centreline | 86 / 128 |
| all points at one `y` (flat) | 67 / 128 |
| every point at `y = 0` exactly | 51 / 128 |
| dominant spread along `z` | 119 / 128 (x 6, y 3) |
| distinct layouts | 89 (29 shared by more than one component) |
| **points outside their own runtime box** | **8 / 681** |
| `z` on an exact even grid (≥3 distinct z) | 9 / 97 eligible |

The only asymmetric SWI ship is `cor_scrapper`. Unlike vanilla, SWI has no
"mirrored to 1 mm but not exactly" case: its symmetry is authored exactly.

Outside their own runtime box: `cor_scrapper` (2 points), `quasar_imp` (2),
`quasar_reb` (2), `ship_mando_s_n1_menu` (1), `yv666` (1), reaching a normalized
|n| of 3.17 on x. Vanilla has none, so this whole phenomenon is SWI-authored —
but it corroborates at corpus scale the reference's refusal to assume aim-point
containment.

| component | class | macros | pts | layout |
|---|---|---:|---:|---|
| `ship_imperial_xxl_executer_01` | xl | 2 | 57 | sym, flat, 18 ±x pair(s) |
| `ship_imperial_xxl_executer_proto` | xl | 1 | 57 | sym, flat, 18 ±x pair(s) |
| `bellator` | xl | 1 | 14 | sym, y-spread 460 m, 2 ±x pair(s) |
| `praetor` | xl | 1 | 13 | sym, flat, 2 ±x pair(s) |
| `mc80_homeone` | xl | 2 | 12 | sym, flat, all on x=0 |
| `hapan_l` | l | 1 | 11 | sym, y-spread 158 m, 3 ±x pair(s), box unresolved |
| `mc85` | xl | 1 | 11 | sym, flat, all on x=0 |
| `imp_cruiser_546` | l | 1 | 9 | sym, y-spread 76 m, 2 ±x pair(s) |
| `proclamator` | l | 1 | 9 | sym, y-spread 133 m, 2 ±x pair(s) |
| `ship_providence_carrier_01` | xl | 1 | 9 | sym, y-spread 125 m, all on x=0 |
| `subjugator_class` | xl | 1 | 9 | sym, flat, all on x=0 |
| `immobilizer_418` | l | 2 | 8 | sym, y-spread 82 m, 3 ±x pair(s) |
| `imp_light_cruiser` | l | 2 | 8 | sym, flat, 2 ±x pair(s) |
| `lucrehulk_a` | xl | 1 | 8 | sym, flat, 3 ±x pair(s) |
| `lucrehulk_b` | xl | 1 | 8 | sym, flat, 3 ±x pair(s) |
| `lucrehulk_f` | xl | 1 | 8 | sym, flat, 3 ±x pair(s) |
| `bff_01` | m | 1 | 7 | sym, y-spread 9 m, 2 ±x pair(s) |
| `c9979` | l | 1 | 7 | sym, y-spread 13 m, 2 ±x pair(s) |
| `heraklon_liquid` | l | 1 | 7 | sym, y-spread 98 m, 1 ±x pair(s) |
| `heraklon_solid` | l | 1 | 7 | sym, y-spread 98 m, 1 ±x pair(s) |
| `isd_1` | xl | 3 | 7 | sym, y-spread 424 m, 1 ±x pair(s) |
| `isd_2` | xl | 2 | 7 | sym, y-spread 424 m, 1 ±x pair(s) |
| `keldabe` | xl | 2 | 7 | sym, y-spread 47 m, 1 ±x pair(s) |
| `mc80` | xl | 2 | 7 | sym, flat, 1 ±x pair(s) |
| `mc80carrier` | xl | 1 | 7 | sym, flat, 1 ±x pair(s) |
| `procursator` | xl | 2 | 7 | sym, y-spread 190 m, 1 ±x pair(s) |
| `victory_2` | l | 1 | 7 | sym, y-spread 249 m, 1 ±x pair(s) |
| `cis_escort_carrier` | l | 1 | 6 | sym, y-spread 146 m, 2 ±x pair(s) |
| `enforcer` | l | 1 | 6 | sym, y-spread 89 m, 2 ±x pair(s) |
| `fulgor` | l | 1 | 6 | sym, y-spread 175 m, 1 ±x pair(s) |
| `harrower` | xl | 1 | 6 | sym, flat, 1 ±x pair(s) |
| `harrower_i` | xl | 1 | 6 | sym, flat, 1 ±x pair(s) |
| `kontos` | l | 1 | 6 | sym, flat, 1 ±x pair(s) |
| `mc40a` | l | 1 | 6 | sym, flat, 1 ±x pair(s) |
| `mc40b` | l | 1 | 6 | sym, flat, 1 ±x pair(s) |
| `recusant` | xl | 1 | 6 | sym, y-spread 174 m, all on x=0 |
| `valor_01` | l | 1 | 6 | sym, y-spread 214 m, all on x=0 |
| `valor_02` | l | 1 | 6 | sym, y-spread 214 m, all on x=0 |
| `vigilfinal` | l | 2 | 6 | sym, y-spread 42 m, 1 ±x pair(s) |
| `vindicator` | l | 2 | 6 | sym, y-spread 89 m, 2 ±x pair(s) |
| `cor_scrapper` | l | 1 | 5 | **asym**, y-spread 14 m, 1 ±x pair(s), **outside box** |
| `genosian_cruiser` | l | 1 | 5 | sym, y-spread 25 m, 1 ±x pair(s) |
| `mc75` | xl | 1 | 5 | sym, flat, all on x=0 |
| `mc80crain` | xl | 1 | 5 | sym, flat, all on x=0 |
| `mc80liner` | xl | 1 | 5 | sym, flat, all on x=0 |
| `mc80r` | xl | 2 | 5 | sym, flat, all on x=0 |
| `munificent_01` | xl | 1 | 5 | sym, y-spread 152 m, all on x=0 |
| `teroch` | l | 1 | 5 | sym, y-spread 100 m, all on x=0 |
| `venator_01` | xl | 2 | 5 | sym, y-spread 178 m, all on x=0 |
| `venator_ce` | xl | 1 | 5 | sym, y-spread 178 m, all on x=0 |
| `venator_hutt` | xl | 1 | 5 | sym, y-spread 178 m, all on x=0 |
| `acclamator1` | l | 1 | 4 | sym, flat, 1 ±x pair(s) |
| `acclamator2` | l | 1 | 4 | sym, flat, 1 ±x pair(s) |
| `allocator` | xl | 1 | 4 | sym, flat, all on x=0 |
| `cr90_01a` | m | 2 | 4 | sym, flat, all on x=0 |
| `cr90_01as` | m | 1 | 4 | sym, flat, all on x=0 |
| `cr90_01b` | m | 1 | 4 | sym, flat, all on x=0 |
| `cr90_01d` | m | 1 | 4 | sym, flat, all on x=0 |
| `hardcell_frigate` | l | 1 | 4 | sym, flat, all on x=0 |
| `hardcell_liquid` | l | 1 | 4 | sym, flat, all on x=0 |
| `hardcell_solid` | l | 1 | 4 | sym, flat, all on x=0 |
| `hardcell_trade` | l | 1 | 4 | sym, flat, all on x=0 |
| `lancerfrigate` | l | 2 | 4 | sym, flat, all on x=0 |
| `neutronstar` | l | 1 | 4 | sym, y-spread 19 m, all on x=0 |
| `neutronstar_builder` | l | 1 | 4 | sym, y-spread 19 m, all on x=0 |
| `neutronstar_trade` | l | 1 | 4 | sym, y-spread 19 m, all on x=0 |
| `pelta_01` | l | 1 | 4 | sym, flat, all on x=0 |
| `pelta_02` | l | 1 | 4 | sym, flat, all on x=0 |
| `praetorian_01` | l | 1 | 4 | sym, y-spread 8 m, all on x=0 |
| `praetorian_02` | l | 1 | 4 | sym, y-spread 8 m, all on x=0 |
| `quasar_imp` | l | 1 | 4 | sym, y-spread 19 m, 1 ±x pair(s), **outside box** |
| `quasar_reb` | l | 1 | 4 | sym, flat, 1 ±x pair(s), **outside box** |
| `responder_frigate_liquid` | l | 1 | 4 | sym, y-spread 49 m, all on x=0 |
| `responder_frigate_solid` | l | 1 | 4 | sym, y-spread 49 m, all on x=0 |
| `responder_frigate_trade` | l | 1 | 4 | sym, y-spread 49 m, all on x=0 |
| `ship_gen_resupplier_01` | xl | 1 | 4 | sym, flat, all on x=0 |
| `ship_mando_xl_kandosii_01` | xl | 2 | 4 | sym, y-spread 26 m, all on x=0 |
| `velox` | l | 1 | 4 | sym, flat, all on x=0 |
| `actioniv` | m | 1 | 3 | sym, y-spread 7 m, all on x=0 |
| `actioniv_gas` | m | 1 | 3 | sym, y-spread 7 m, all on x=0 |
| `actioniv_solid` | m | 1 | 3 | sym, y-spread 7 m, all on x=0 |
| `arquitens` | l | 1 | 3 | sym, flat, 1 ±x pair(s) |
| `arrestor_cruiser` | l | 1 | 3 | sym, flat, 1 ±x pair(s) |
| `cis_cruiser` | l | 1 | 3 | sym, flat, all on x=0 |
| `cis_refractory` | l | 1 | 3 | sym, y-spread 360 m, all on x=0 |
| `cis_repair` | m | 1 | 3 | sym, flat, all on x=0 |
| `cr70_01a` | m | 1 | 3 | sym, y-spread 2 m, all on x=0 |
| `cr70_01con` | m | 1 | 3 | sym, y-spread 2 m, all on x=0 |
| `crusader` | m | 1 | 3 | sym, y-spread 2 m, all on x=0 |
| `diamond_cruiser` | l | 1 | 3 | sym, y-spread 267 m, all on x=0 |
| `diamond_cruiser_civ` | l | 1 | 3 | sym, y-spread 267 m, all on x=0 |
| `dorean_corvette` | m | 1 | 3 | sym, flat, all on x=0 |
| `dreadnaught_alliance` | l | 1 | 3 | sym, flat, all on x=0, box unresolved |
| `dreadnaught_katana` | l | 1 | 3 | sym, flat, all on x=0, box unresolved |
| `eta_class_supply_barge` | l | 1 | 3 | sym, flat, all on x=0 |
| `gs80` | m | 1 | 3 | sym, flat, all on x=0 |
| `hammerheadcruiser` | l | 1 | 3 | sym, y-spread 4 m, all on x=0 |
| `hammerheadcruiser_red` | l | 2 | 3 | sym, y-spread 4 m, all on x=0 |
| `hapan_nova` | l | 1 | 3 | sym, flat, 1 ±x pair(s) |
| `interceptor_frigate` | l | 1 | 3 | sym, flat, all on x=0 |
| `mando_assault_ship` | l | 1 | 3 | sym, y-spread 73 m, all on x=0 |
| `overseer` | l | 1 | 3 | sym, flat, all on x=0 |
| `sith_destroyer` | l | 1 | 3 | sym, flat, all on x=0 |
| `sith_freighter` | l | 1 | 3 | sym, flat, all on x=0 |
| `sorosub3000` | m | 1 | 3 | sym, y-spread 2 m, all on x=0 |
| `storm` | l | 1 | 3 | sym, y-spread 55 m, all on x=0 |
| `terminus_ship` | l | 1 | 3 | sym, y-spread 54 m, all on x=0 |
| `aa9_liquid` | l | 1 | 2 | sym, flat, all on x=0 |
| `aa9_solid` | l | 1 | 2 | sym, flat, all on x=0 |
| `civ_l_transport` | l | 1 | 2 | sym, y-spread 18 m, all on x=0 |
| `defender_corvette` | m | 1 | 2 | sym, flat, all on x=0 |
| `hammerhead_corvette` | m | 1 | 2 | sym, y-spread 1 m, all on x=0 |
| `hwk_290_01` | s | 2 | 2 | sym, y-spread 1 m, all on x=0 |
| `laat` | s | 1 | 2 | sym, y-spread 3 m, all on x=0 |
| `nebulonb_01e` | l | 2 | 2 | sym, flat, all on x=0 |
| `nebulonb_01p` | l | 1 | 2 | sym, flat, all on x=0 |
| `nebulonc` | l | 1 | 2 | sym, y-spread 40 m, all on x=0 |
| `raider` | m | 1 | 2 | sym, flat, all on x=0 |
| `rebel_tanker` | m | 1 | 2 | sym, flat, all on x=0 |
| `rebel_tanker_liquid` | m | 1 | 2 | sym, flat, all on x=0 |
| `rebel_tanker_solid` | m | 1 | 2 | sym, flat, all on x=0 |
| `ship_mando_s_n1` | s | 1 | 2 | sym, flat, all on x=0 |
| `ship_mando_s_n1_menu` | s | 1 | 2 | sym, flat, all on x=0, **outside box** |
| `yv666` | m | 1 | 2 | sym, y-spread 13 m, all on x=0, **outside box** |
| `ywing_btla4` | s | 2 | 2 | sym, flat, all on x=0 |
| `ywing_btla4long` | s | 1 | 2 | sym, flat, all on x=0 |
| `ywing_btlbpm` | s | 1 | 2 | sym, flat, all on x=0 |
| `ywing_btlnr2` | s | 1 | 2 | sym, flat, all on x=0 |

## SWI direct reconstruction

Of 795 authored points: 601 on the centreline, 192 in ±x twin pairs, **2
neither** (both on `cor_scrapper`), unchanged at 1 mm tolerance. Box length
against point count gives Pearson r = 0.930, driven by the two 19 km executors.
The length buckets show it still cannot fix a count:

| box length | components | point counts |
|---|--:|---|
| 0–100 m | 90 | 80 one-point, 9 two, 1 three |
| 100–300 m | 36 | 17 one-point, then 2–7 |
| 300–1000 m | 43 | 2–9 points, no one-point ship |
| >1000 m | 54 | 3–57 points, plus the single zero-point ship |

Within a bucket the spread is 1–9 points, so length predicts an order of
magnitude, never a count, and never a position.

---

# Findings across both games

## Exact, source-backed, true in both populations

1. The ordered point list is a property of the **component** and identical
   across every macro that uses it. The *box* is not: it varies by up to 25.2 m
   between a component's macros.
2. **No aim connection carries a `parent` attribute** (0 of 39 vanilla, 0 of
   795 SWI). The authored offset is already the component-frame position.
3. **Selection order is the native connection-name hash, not document order.**
   They differ for most SWI multi-point components.
4. **Every one-point ship places its point on `x = 0`** (5/5 vanilla, 97/97
   SWI).

## Strong but with named counterexamples — not safe alone

5. Lateral symmetry. SWI authors it almost perfectly — 127 of 128 multi-point
   components, exactly — but **vanilla manages only 9 of 14 exactly** (11 within
   1 mm), with three genuinely asymmetric ships. The two games disagree sharply,
   and the vanilla figure is the one a vanilla game needs.
6. Containment in the runtime box. Vanilla: no exception. SWI: 8 points
   outside, up to |n| = 3.17.
7. Multi-point layouts spreading along `z`: 12 of 14 vanilla, 119 of 128 SWI.

## Coincidence, not usable

8. Box length against point count: r = 0.531 vanilla, 0.930 SWI. In vanilla it
   cannot separate zero-point from one-point ships; in SWI, where almost every
   ship authors points, it cannot fix a count either — each length bucket spans
   1 to 9 points.
9. Even `z` grids: 0 of 3 eligible vanilla, 9 of 97 SWI.

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
   governs 184 of 203 vanilla ships — 91% — and is currently uncharacterized. It
   is the highest-value question in A4.5, above any count discriminator. It
   barely matters in a SWI game (1 ship of 226), which is precisely why the
   question has to be asked per game.
2. **Can a normal mod read the aim connections of a target at runtime** (count,
   order or position)? If it can, reconstruction is a lookup, not a probe.
3. **Is there any runtime-visible fact that separates zero-point from one-point
   from multi-point ships?** Neither census supports size class, box or box
   length: in vanilla every class and length bucket contains all three, and in
   SWI every bucket spans a wide point count.

## What the split changed

Separating the games did not change a single ship's data. Every aim point, box
and macro list is what it was; what changed is which ships belong to which
population and therefore which statistics are honest.

- The "SWI game" was 429 components. 203 of those were vanilla ships whose
  macros merely survived in the source environment. The SWI population is
  **226**.
- "185 SWI ships author no aim point" is gone. The real figure is **1 of 226**
  (`mandator`). The 185 was 184 vanilla ships plus that one.
- Pooled "822 of 834 points on the centreline or in a ±x twin" was a SWI
  statistic wearing both games' clothes. Vanilla's own figure is 29 of 39;
  SWI's is 793 of 795.
- Pooled "8 points outside their own box" attributed an entirely SWI-authored
  phenomenon to the corpus as a whole. Vanilla has none.
- Pooled symmetry hid both the 0.3 mm authoring asymmetry on two vanilla ships
  and how much better SWI's symmetry is: 127 of 128 exactly, against vanilla's
  9 of 14.
- "184 of 203 vanilla ship components author no aimtarget" **survived** and is
  reproduced from pristine source, with all 203 boxes resolving.

Unchanged: every exact rule above, the one-point `x = 0` result, the per-game
multi-point component lists, and the verdict on direct reconstruction.

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

**SWI unresolved (7).**

| entry | why | effect |
|---|---|---|
| `n1pi` | SWI macro `n1pi_macro` references a component no source set defines | the only SWI ship missing entirely: 1 of 227 |
| `dreadnaught_alliance`, `dreadnaught_katana`, `hapan_l` | their SWI macros attach a dock child through a parent connection their own component does not define | aim points recorded; runtime box unresolved |
| `swi/assets/structures/habitat/deathstar_01.xml` | malformed XML (mismatched tag, line 89) | class `habitation`, not a ship |
| 2 SWI diff files with no official file at their path | `fx/weaponFx/backup/…`, `structures/dock/macros/dockarea_arg_m_01_tradestation_01_macro.xml` | neither is a ship or a ship's box child |

The SWI census is complete for aim points at **226 of the 227** SWI ship
components, and for the runtime box at 223 of 227. `ship_xen_m_miner_01`, whose
box SWI breaks, is a vanilla ship and is no longer a SWI census member; it is
recorded in the vanilla census, where its box resolves.

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
