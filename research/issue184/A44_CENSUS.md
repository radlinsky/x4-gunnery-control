# A4.4 ship aim-point census — vanilla X4 9.00 and SWI 0.9.1 HF

Offline source research, status **inference** (from `shipped-source` and
`third-party-technique` XML). No X4 launch, no production change.

```sh
python3 research/issue184/extract_swi_assets.py <SWI 0.9.1 HF mod dir>  # once: assets/ and index/
python3 research/issue184/ship_aimpoint_census.py                       # ~3 min
```

The command prints this analysis and writes one JSON row per ship component to
the ignored `.x4-research-cache/issue184/a44_census.jsonl`. Exact authored
coordinates live only there: unpacked game and third-party mod source stays out
of the repository, so the tables below carry component identity, counts and
layout structure rather than raw positions.

## Question

Can Gunnery Control reconstruct a ship's aim points from authored ship data and
simple runtime-visible facts, instead of asking X4 repeatedly?

## Population

Every unique ship component behind a `ship_s`/`ship_m`/`ship_l`/`ship_xl`
macro. This is the whole ship census, not the narrower A2 benchmark firing-ship
population, so ships no benchmark turret fits are included.

| source | ship_s | ship_m | ship_l | ship_xl | total |
|---|---:|---:|---:|---:|---:|
| official 9.00 | 69 | 54 | 49 | 31 | 203 |
| SWI 0.9.1 HF | 70 | 57 | 67 | 32 | 226 |

429 components, 542 macros, 834 authored aim points; the runtime box
reconstructs for 425 of them.

**SWI is an overhaul: its ships and vanilla ships are never in the same game.**
A vanilla game holds the 203 official components. A SWI game holds the 226 SWI
ones plus the official ones as SWI patches them. A reconstruction rule has to
hold inside one population on its own; a union statistic describes no real game.

### SWI is applied properly here, unlike in the benchmark

`aimpoint_map._index_swi_ships` skips SWI `<diff>` patches and same-name
replacements, which is sound for the benchmark but would make a *complete* SWI
census wrong. The census applies them: 214 diff files patch an official file at
the same relative path (443 `<remove>`, 932 `<replace>`, 5 `<add>` operations,
mostly deleting or retagging connections that feed the runtime box), and 23
SWI definitions replace an official one outright.

Measured while doing so, and relevant to any future SWI work:

- **No SWI diff anywhere touches an `aimtarget` connection.** Every SWI-visible
  aim point is authored in a full component definition, patched or not.
- SWI refers to four official assets with different capitalisation
  (`bridge_arg_Xl_01_macro`). X4 resolves those; an exact-name index does not.
- SWI defines 41 names in two files each. Six are census ships, all with a
  differing aim-point set; X4's own name index decides which one is real, see
  *Duplicate definitions and unresolved entries*.

## Aim-point count distribution

| points | official | SWI |
|---:|---:|---:|
| 0 | 184 | 4 |
| 1 | 5 | 97 |
| 2 | 9 | 21 |
| 3 | 4 | 29 |
| 4 | 1 | 27 |
| 5–9 | 0 | 41 |
| 11–14 | 0 | 5 |
| 57 | 0 | 2 |

**The dominant vanilla fact: 184 of 203 official ship components author no
`aimtarget` connection at all.** Only these 19 do:

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
explicitly does not characterize that branch. In a vanilla game this is 91% of
ships, so "reconstruct the authored points" is not even the main question
there — what the engine does with an empty collection is.

## Structural facts that do hold exactly

These have no counterexample in either population.

- **Aim points belong to the component, not the macro.** 110 components are
  used by more than one macro and every one of them has the identical ordered
  layout in all of its macros, by construction. The *box* is not: it varies by
  up to 25.2 m across a component's macros (3 components over 1 m).
- **No aim connection carries a `parent` attribute** (0 of 834). The authored
  offset is already the component-frame position, confirming the reference's
  "do not invent a parent transform" rule across the whole corpus.
- **Selection order is the native connection-name hash, not document order.**
  They differ for 112 of the 142 multi-point components, so anything reading
  these points geometrically or in file order gets the wrong index.

## One-point components (102: 5 official, 97 SWI)

Not the component origin, not the runtime-box centre, in either population.

| test | official (5) | SWI (97) |
|---|---:|---:|
| exactly the component origin | 0 | 47 |
| exactly the runtime-box centre | 0 | 18 |
| `x` exactly 0 | 5 | 97 |
| inside its own runtime box | 5 | 97 |

The five official one-point ships sit 5–207 m from their origin (median
107 m) — an authored spot on the hull, nowhere near either candidate. The SWI
half looks origin-like only because 47 SWI ships are modelled about their aim
point; 50 are not, up to 49 m out.

The single exact rule: **every one-point aim point is on the `x = 0`
centreline** (102 of 102). That constrains one coordinate of three, and cannot
place the point along the ship.

## Multi-point components (142: 14 official, 128 SWI)

| property | count |
|---|---|
| fully left/right symmetric (each off-centre point has a ±x twin at the same y,z) | 136 / 142 |
| all points on the `x = 0` centreline | 94 / 142 |
| all points at one `y` (flat layout) | 75 / 142 |
| every point at `y = 0` exactly | 57 / 142 |
| dominant spread along `z` (ship long axis) | 131 / 142 (x 8, y 3) |
| distinct layouts | 101 (31 layouts shared by more than one component) |
| `z` coordinates on an exact even grid (≥3 distinct z) | 9 / 100 eligible |

Counterexamples matter more than the majorities:

- **Not symmetric:** `cor_scrapper`, `ship_arg_l_destroyer_02`,
  `ship_arg_xl_carrier_02`, `ship_pir_s_heavyfighter_01`,
  `ship_ter_xl_carrier_01`, `ship_ter_xl_resupplier_01`. Four of the six are
  official — so in a vanilla game 4 of the 14 multi-point ships break the
  strongest pattern in the corpus.
- **Outside their own runtime box:** 8 points, on `cor_scrapper` (2),
  `quasar_imp` (2), `quasar_reb` (2), `ship_mando_s_n1_menu` (1), `yv666` (1),
  reaching |n| = 3.17 on x. This corroborates the reference's refusal to assume
  aim-point containment, now over a whole corpus rather than one turret sample.
- Spacing is authored art, not a rule: median z spread 442 m, and the two
  `ship_imperial_xxl_executer_*` components carry 57 points over 10 km.

Full list, normalization `n = (p - C) / H` where `C`/`H` are the reconstructed
runtime-box centre and half-extents in the component frame (`n = 0` is the box
centre, `|n| = 1` a box face). `C` is the reconstructed runtime box centre; the
census does not claim it is a centre of mass. Ordered positions are in the
ignored `a44_census.jsonl`.

| component | source | class | macros | pts | layout |
|---|---|---|---|---:|---|
| `ship_arg_xl_carrier_02` | official | xl | 1 | 4 | **asym**, y-spread 244m, 0 ±x pair(s) |
| `ship_arg_l_destroyer_02` | official | l | 1 | 3 | **asym**, y-spread 18m, 0 ±x pair(s) |
| `ship_gen_s_fightingdrone_01` | official | s | 2 | 3 | sym, y-spread 0m, 1 ±x pair(s) |
| `ship_ter_xl_carrier_01` | official | xl | 1 | 3 | **asym**, flat, 0 ±x pair(s) |
| `ship_ter_xl_resupplier_01` | official | xl | 1 | 3 | **asym**, y-spread 47m, 0 ±x pair(s) |
| `ship_bor_l_miner_liquid_01` | official | l | 1 | 2 | sym, flat, on x=0 |
| `ship_bor_l_miner_solid_01` | official | l | 2 | 2 | sym, flat, on x=0 |
| `ship_par_l_expeditionary_01` | official | l | 1 | 2 | sym, y-spread 5m, on x=0 |
| `ship_pir_s_heavyfighter_01` | official | s | 1 | 2 | **asym**, y-spread 2m, 0 ±x pair(s) |
| `ship_tel_l_destroyer_01` | official | l | 2 | 2 | sym, flat, on x=0 |
| `ship_tel_l_destroyer_02` | official | l | 1 | 2 | sym, flat, on x=0 |
| `ship_tel_l_miner_liquid_02` | official | l | 1 | 2 | sym, flat, on x=0 |
| `ship_tel_l_miner_solid_02` | official | l | 1 | 2 | sym, flat, on x=0 |
| `ship_tel_l_trans_container_03` | official | l | 1 | 2 | sym, flat, on x=0 |
| `ship_imperial_xxl_executer_01` | swi | xl | 2 | 57 | sym, flat, 18 ±x pair(s) |
| `ship_imperial_xxl_executer_proto` | swi | xl | 1 | 57 | sym, flat, 18 ±x pair(s) |
| `bellator` | swi | xl | 1 | 14 | sym, y-spread 460m, 2 ±x pair(s) |
| `praetor` | swi | xl | 1 | 13 | sym, flat, 2 ±x pair(s) |
| `mc80_homeone` | swi | xl | 2 | 12 | sym, flat, on x=0 |
| `hapan_l` | swi | l | 1 | 11 | sym, y-spread 158m, 3 ±x pair(s) |
| `mc85` | swi | xl | 1 | 11 | sym, flat, on x=0 |
| `imp_cruiser_546` | swi | l | 1 | 9 | sym, y-spread 76m, 2 ±x pair(s) |
| `proclamator` | swi | l | 1 | 9 | sym, y-spread 133m, 2 ±x pair(s) |
| `ship_providence_carrier_01` | swi | xl | 1 | 9 | sym, y-spread 125m, on x=0 |
| `subjugator_class` | swi | xl | 1 | 9 | sym, flat, on x=0 |
| `immobilizer_418` | swi | l | 2 | 8 | sym, y-spread 82m, 3 ±x pair(s) |
| `imp_light_cruiser` | swi | l | 2 | 8 | sym, flat, 2 ±x pair(s) |
| `lucrehulk_a` | swi | xl | 1 | 8 | sym, flat, 3 ±x pair(s) |
| `lucrehulk_b` | swi | xl | 1 | 8 | sym, flat, 3 ±x pair(s) |
| `lucrehulk_f` | swi | xl | 1 | 8 | sym, flat, 3 ±x pair(s) |
| `bff_01` | swi | m | 1 | 7 | sym, y-spread 9m, 2 ±x pair(s) |
| `c9979` | swi | l | 1 | 7 | sym, y-spread 13m, 2 ±x pair(s) |
| `heraklon_liquid` | swi | l | 1 | 7 | sym, y-spread 98m, 1 ±x pair(s) |
| `heraklon_solid` | swi | l | 1 | 7 | sym, y-spread 98m, 1 ±x pair(s) |
| `isd_1` | swi | xl | 3 | 7 | sym, y-spread 424m, 1 ±x pair(s) |
| `isd_2` | swi | xl | 2 | 7 | sym, y-spread 424m, 1 ±x pair(s) |
| `keldabe` | swi | xl | 2 | 7 | sym, y-spread 47m, 1 ±x pair(s) |
| `mc80` | swi | xl | 2 | 7 | sym, flat, 1 ±x pair(s) |
| `mc80carrier` | swi | xl | 1 | 7 | sym, flat, 1 ±x pair(s) |
| `procursator` | swi | xl | 2 | 7 | sym, y-spread 190m, 1 ±x pair(s) |
| `victory_2` | swi | l | 1 | 7 | sym, y-spread 249m, 1 ±x pair(s) |
| `cis_escort_carrier` | swi | l | 1 | 6 | sym, y-spread 146m, 2 ±x pair(s) |
| `enforcer` | swi | l | 1 | 6 | sym, y-spread 89m, 2 ±x pair(s) |
| `fulgor` | swi | l | 1 | 6 | sym, y-spread 175m, 1 ±x pair(s) |
| `harrower` | swi | xl | 1 | 6 | sym, flat, 1 ±x pair(s) |
| `harrower_i` | swi | xl | 1 | 6 | sym, flat, 1 ±x pair(s) |
| `kontos` | swi | l | 1 | 6 | sym, flat, 1 ±x pair(s) |
| `mc40a` | swi | l | 1 | 6 | sym, flat, 1 ±x pair(s) |
| `mc40b` | swi | l | 1 | 6 | sym, flat, 1 ±x pair(s) |
| `recusant` | swi | xl | 1 | 6 | sym, y-spread 174m, on x=0 |
| `valor_01` | swi | l | 1 | 6 | sym, y-spread 214m, on x=0 |
| `valor_02` | swi | l | 1 | 6 | sym, y-spread 214m, on x=0 |
| `vigilfinal` | swi | l | 2 | 6 | sym, y-spread 42m, 1 ±x pair(s) |
| `vindicator` | swi | l | 2 | 6 | sym, y-spread 89m, 2 ±x pair(s) |
| `cor_scrapper` | swi | l | 1 | 5 | **asym**, y-spread 14m, 1 ±x pair(s), outside box |
| `genosian_cruiser` | swi | l | 1 | 5 | sym, y-spread 25m, 1 ±x pair(s) |
| `mc75` | swi | xl | 1 | 5 | sym, flat, on x=0 |
| `mc80crain` | swi | xl | 1 | 5 | sym, flat, on x=0 |
| `mc80liner` | swi | xl | 1 | 5 | sym, flat, on x=0 |
| `mc80r` | swi | xl | 2 | 5 | sym, flat, on x=0 |
| `munificent_01` | swi | xl | 1 | 5 | sym, y-spread 152m, on x=0 |
| `teroch` | swi | l | 1 | 5 | sym, y-spread 100m, on x=0 |
| `venator_01` | swi | xl | 2 | 5 | sym, y-spread 178m, on x=0 |
| `venator_ce` | swi | xl | 1 | 5 | sym, y-spread 178m, on x=0 |
| `venator_hutt` | swi | xl | 1 | 5 | sym, y-spread 178m, on x=0 |
| `acclamator1` | swi | l | 1 | 4 | sym, flat, 1 ±x pair(s) |
| `acclamator2` | swi | l | 1 | 4 | sym, flat, 1 ±x pair(s) |
| `allocator` | swi | xl | 1 | 4 | sym, flat, on x=0 |
| `cr90_01a` | swi | m | 2 | 4 | sym, flat, on x=0 |
| `cr90_01as` | swi | m | 1 | 4 | sym, flat, on x=0 |
| `cr90_01b` | swi | m | 1 | 4 | sym, flat, on x=0 |
| `cr90_01d` | swi | m | 1 | 4 | sym, flat, on x=0 |
| `hardcell_frigate` | swi | l | 1 | 4 | sym, flat, on x=0 |
| `hardcell_liquid` | swi | l | 1 | 4 | sym, flat, on x=0 |
| `hardcell_solid` | swi | l | 1 | 4 | sym, flat, on x=0 |
| `hardcell_trade` | swi | l | 1 | 4 | sym, flat, on x=0 |
| `lancerfrigate` | swi | l | 2 | 4 | sym, flat, on x=0 |
| `neutronstar` | swi | l | 1 | 4 | sym, y-spread 19m, on x=0 |
| `neutronstar_builder` | swi | l | 1 | 4 | sym, y-spread 19m, on x=0 |
| `neutronstar_trade` | swi | l | 1 | 4 | sym, y-spread 19m, on x=0 |
| `pelta_01` | swi | l | 1 | 4 | sym, flat, on x=0 |
| `pelta_02` | swi | l | 1 | 4 | sym, flat, on x=0 |
| `praetorian_01` | swi | l | 1 | 4 | sym, y-spread 8m, on x=0 |
| `praetorian_02` | swi | l | 1 | 4 | sym, y-spread 8m, on x=0 |
| `quasar_imp` | swi | l | 1 | 4 | sym, y-spread 19m, 1 ±x pair(s), outside box |
| `quasar_reb` | swi | l | 1 | 4 | sym, flat, 1 ±x pair(s), outside box |
| `responder_frigate_liquid` | swi | l | 1 | 4 | sym, y-spread 49m, on x=0 |
| `responder_frigate_solid` | swi | l | 1 | 4 | sym, y-spread 49m, on x=0 |
| `responder_frigate_trade` | swi | l | 1 | 4 | sym, y-spread 49m, on x=0 |
| `ship_gen_resupplier_01` | swi | xl | 1 | 4 | sym, flat, on x=0 |
| `ship_mando_xl_kandosii_01` | swi | xl | 2 | 4 | sym, y-spread 26m, on x=0 |
| `velox` | swi | l | 1 | 4 | sym, flat, on x=0 |
| `actioniv` | swi | m | 1 | 3 | sym, y-spread 7m, on x=0 |
| `actioniv_gas` | swi | m | 1 | 3 | sym, y-spread 7m, on x=0 |
| `actioniv_solid` | swi | m | 1 | 3 | sym, y-spread 7m, on x=0 |
| `arquitens` | swi | l | 1 | 3 | sym, flat, 1 ±x pair(s) |
| `arrestor_cruiser` | swi | l | 1 | 3 | sym, flat, 1 ±x pair(s) |
| `cis_cruiser` | swi | l | 1 | 3 | sym, flat, on x=0 |
| `cis_refractory` | swi | l | 1 | 3 | sym, y-spread 360m, on x=0 |
| `cis_repair` | swi | m | 1 | 3 | sym, flat, on x=0 |
| `cr70_01a` | swi | m | 1 | 3 | sym, y-spread 2m, on x=0 |
| `cr70_01con` | swi | m | 1 | 3 | sym, y-spread 2m, on x=0 |
| `crusader` | swi | m | 1 | 3 | sym, y-spread 2m, on x=0 |
| `diamond_cruiser` | swi | l | 1 | 3 | sym, y-spread 267m, on x=0 |
| `diamond_cruiser_civ` | swi | l | 1 | 3 | sym, y-spread 267m, on x=0 |
| `dorean_corvette` | swi | m | 1 | 3 | sym, flat, on x=0 |
| `dreadnaught_alliance` | swi | l | 1 | 3 | sym, flat, on x=0 |
| `dreadnaught_katana` | swi | l | 1 | 3 | sym, flat, on x=0 |
| `eta_class_supply_barge` | swi | l | 1 | 3 | sym, flat, on x=0 |
| `gs80` | swi | m | 1 | 3 | sym, flat, on x=0 |
| `hammerheadcruiser` | swi | l | 1 | 3 | sym, y-spread 4m, on x=0 |
| `hammerheadcruiser_red` | swi | l | 2 | 3 | sym, y-spread 4m, on x=0 |
| `hapan_nova` | swi | l | 1 | 3 | sym, flat, 1 ±x pair(s) |
| `interceptor_frigate` | swi | l | 1 | 3 | sym, flat, on x=0 |
| `mando_assault_ship` | swi | l | 1 | 3 | sym, y-spread 73m, on x=0 |
| `overseer` | swi | l | 1 | 3 | sym, flat, on x=0 |
| `sith_destroyer` | swi | l | 1 | 3 | sym, flat, on x=0 |
| `sith_freighter` | swi | l | 1 | 3 | sym, flat, on x=0 |
| `sorosub3000` | swi | m | 1 | 3 | sym, y-spread 2m, on x=0 |
| `storm` | swi | l | 1 | 3 | sym, y-spread 55m, on x=0 |
| `terminus_ship` | swi | l | 1 | 3 | sym, y-spread 54m, on x=0 |
| `aa9_liquid` | swi | l | 1 | 2 | sym, flat, on x=0 |
| `aa9_solid` | swi | l | 1 | 2 | sym, flat, on x=0 |
| `civ_l_transport` | swi | l | 1 | 2 | sym, y-spread 18m, on x=0 |
| `defender_corvette` | swi | m | 1 | 2 | sym, flat, on x=0 |
| `hammerhead_corvette` | swi | m | 1 | 2 | sym, y-spread 1m, on x=0 |
| `hwk_290_01` | swi | s | 2 | 2 | sym, y-spread 1m, on x=0 |
| `laat` | swi | s | 1 | 2 | sym, y-spread 3m, on x=0 |
| `nebulonb_01e` | swi | l | 2 | 2 | sym, flat, on x=0 |
| `nebulonb_01p` | swi | l | 1 | 2 | sym, flat, on x=0 |
| `nebulonc` | swi | l | 1 | 2 | sym, y-spread 40m, on x=0 |
| `raider` | swi | m | 1 | 2 | sym, flat, on x=0 |
| `rebel_tanker` | swi | m | 1 | 2 | sym, flat, on x=0 |
| `rebel_tanker_liquid` | swi | m | 1 | 2 | sym, flat, on x=0 |
| `rebel_tanker_solid` | swi | m | 1 | 2 | sym, flat, on x=0 |
| `ship_mando_s_n1` | swi | s | 1 | 2 | sym, flat, on x=0 |
| `ship_mando_s_n1_menu` | swi | s | 1 | 2 | sym, flat, on x=0, outside box |
| `yv666` | swi | m | 1 | 2 | sym, y-spread 13m, on x=0, outside box |
| `ywing_btla4` | swi | s | 2 | 2 | sym, flat, on x=0 |
| `ywing_btla4long` | swi | s | 1 | 2 | sym, flat, on x=0 |
| `ywing_btlbpm` | swi | s | 1 | 2 | sym, flat, on x=0 |
| `ywing_btlnr2` | swi | s | 1 | 2 | sym, flat, on x=0 |

## Direct reconstruction: what the authored data can and cannot support

**Exact, source-backed:**

1. The ordered point list is a property of the component and identical across
   all its macros.
2. The authored offset needs no parent transform (0 of 834 parented).
3. Selection order is the native connection-name hash.
4. Every one-point aim point is on `x = 0` (102 / 102).

**Strong but with named counterexamples — not safe alone:**

5. Lateral symmetry: 822 of 834 points are on the centreline or in a ±x twin
   pair, but 6 components including 4 official ones are asymmetric.
6. Points lie inside the runtime box: 8 exceptions, up to |n| = 3.17.
7. Multi-point layouts spread along `z`: 11 exceptions.

**Coincidence, not usable:**

8. Box length against point count looks correlated (Pearson r = 0.93) but is
   driven by the two 19 km executors, and it cannot separate the cases that
   matter: among 166 components under 100 m long, 73 have zero points and 81
   have exactly one.
9. Even `z` grids: 9 of 100 eligible components.

**Verdict: the authored data contains no general rule that reconstructs aim
point positions.** They are hand-placed art constants. Nothing derives them
from the runtime box, the origin, the class or the size; the only exact
positional rule fixes one of three coordinates. Reconstruction from source is
possible only as a per-component lookup table built from ship XML — exactly
what A4.6 is told not to bake in for unknown DLC and mod ships — and even a
complete table answers nothing for the 184 vanilla ships that author no points.

## What A4.5 now has to ask

1. **What does the engine do when the defaults collection is empty?** This
   governs 91% of vanilla ships and is currently uncharacterized. It is the
   highest-value question in A4.5, above any count discriminator.
2. **Can a normal mod read the aim connections of a target at runtime**
   (count, order or position)? If it can, reconstruction is a lookup, not a
   probe. If it cannot, source-side knowledge cannot be transferred into
   production generically.
3. **Is there any runtime-visible fact that separates zero-point from
   one-point from multi-point ships?** The census says size class, box and box
   length do not: every class and every length bucket contains all three.

Probing is not ruled out by this census — it is made more likely.

## Duplicate definitions and unresolved entries

Nothing in the intended population was silently dropped.

**Duplicate component definitions, resolved (6 census ships).** SWI defines
these components in two files each, with a differing aim-point set. X4 does not
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

In every case the unused copy is a `backup/` duplicate or a `*_data/` folder
copy, and the index names the primary ship file. No census total or finding
depends on this any more: it is established, not assumed.

**Unresolved (8).**

| entry | why | effect on the census |
|---|---|---|
| `n1pi` | SWI macro `n1pi_macro` references a component no source set defines | the only ship component missing entirely: 1 of 430 |
| `dreadnaught_alliance`, `dreadnaught_katana`, `hapan_l` | their SWI macros attach a dock child through a parent connection their own component does not define | aim points recorded; runtime box unresolved |
| `ship_xen_m_miner_01` | SWI replaces the vanilla macro with one referencing `ishield_xen_m_miner_01_a_macro`, absent from 9.00 | aim points recorded; runtime box unresolved |
| `swi/assets/structures/habitat/deathstar_01.xml` | malformed XML (mismatched tag, line 89) | class `habitation`, not a ship |
| 2 SWI diff files with no official file at their path | `fx/weaponFx/backup/…`, `structures/dock/macros/dockarea_arg_m_01_tradestation_01_macro.xml` | neither is a ship or a ship's box child |

**The census is complete for aim points** — all 430 ship components except
`n1pi` are represented, and the 4 box-unresolved ships still contribute their
authored points, which is the census subject. It is complete for the runtime
box in 425 of 430.
