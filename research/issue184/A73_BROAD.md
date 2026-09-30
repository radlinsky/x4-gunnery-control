# Issue #184 A7.3: the frozen 40-sample near-target search on a representative population

Offline research, status **inference**. No X4 launch, no production change. The search, its
starting geometry and its 40-sample total are frozen inputs to this task and nothing here tunes
them. Run with `python3 research/issue184/aimpoint_map.py --a73`.

One **sample** is one X4 aim-direction lookup from one probe position.

## The frozen search

- start with the 8 fixed probes of the
  `C8` geometry: all 8 corners of the target's runtime box grown by the existing
  50 m near-target pad;
- the existing point-location and confirmation rules, unchanged;
- the existing moved-probe continuation where the fixed starts confirm nothing;
- then the existing adaptive near-target search on the largest missing viewing direction;
- then the existing post-search refinement, which spends no sample;
- hard total **40 samples**. The 8 starts count toward it, and moved probes,
  confirmation samples, adaptive probes and their confirmations all share what is left. The
  adaptive stage has no allowance of its own.

Hidden aim points and later aimed barrel positions are scoring truth only. They never touch probe
placement, stopping or the budget.

## Representative firing ships

Selection rule, fixed before anything was scored and computed from each ship's reconstructed
runtime box and the turret mounts a corpus turret fits - never from a search result. `mounts` is
how many such mounts the ship has; `spread` is the mean over the three axes of the standard
deviation of the mount positions, each axis normalised by the box extent. One extremal ship per
criterion, ties by macro name.

| | ship | class | source | rule | mounts | box diagonal (m) | spread | representative turret instances | why |
|---|---|---|---|---|---:|---:|---:|---:|---|
| `M1` | `ship_bor_m_trans_container_01_a_macro` | ship_m | official | ship_m official: min mounts (48 candidates) | 1 | 153 | 0.000 | 2 | fewest mounts: one concentrated mount position |
| `M2` | `cumulus_class_macro` | ship_m | swi | ship_m swi: max mounts (45 candidates) | 18 | 198 | 0.116 | 32 | most mounts: many mounts around a compact medium hull |
| `L1` | `ship_bor_l_miner_liquid_01_a_macro` | ship_l | official | ship_l official: min mounts (49 candidates) | 4 | 1038 | 0.154 | 8 | fewest mounts on a physically large hull |
| `L2` | `ship_spl_l_destroyer_01_a_macro` | ship_l | official | ship_l official: max mounts (49 candidates) | 18 | 917 | 0.191 | 36 | the vanilla L carrying the most mounts |
| `L3` | `cis_cruiser_macro` | ship_l | swi | ship_l swi: max mounts (62 candidates) | 63 | 1846 | 0.254 | 120 | most mounts on a very large hull |
| `L4` | `quasar_reb_macro` | ship_l | swi | ship_l swi: max spread (62 candidates) | 10 | 904 | 0.608 | 20 | mounts spread furthest around the hull: top, bottom and sides |
| `X1` | `ship_spl_xl_carrier_01_a_macro` | ship_xl | official | ship_xl official: max mounts (29 candidates) | 101 | 3092 | 0.214 | 202 | turret-heavy XL, included as a performance stress case |

`X1` is present as a performance stress case only; it is scored like every other ship.

## Representative turrets, not every compatible turret

Selection rule, fixed before anything was scored. A7.1/A7.2 expanded every mount into every
compatible corpus turret, which enumerates the equipment catalogue rather than a realistic ship.
A7.3 ranks each mount's compatible turrets by (muzzle offset at rest, widest arc first, key) and
keeps the two ends of that ranking: the shortest barrel with the broadest arc, and the longest
barrel with the narrowest arc. Those are the two geometries that decide where a later aimed
barrel position ends up, one turret cannot represent both, and nothing between them reaches a
barrel position outside the two. A mount whose compatible turrets share one geometry keeps a
single turret.

| | mounts | compatible turret instances (A7.1 truth) | representative instances | reduction |
|---|---:|---:|---:|---:|
| `M1` | 1 | 32 | 2 | 16.0x |
| `M2` | 18 | 46 | 32 | 1.4x |
| `L1` | 4 | 24 | 8 | 3.0x |
| `L2` | 18 | 612 | 36 | 17.0x |
| `L3` | 63 | 515 | 120 | 4.3x |
| `L4` | 10 | 90 | 20 | 4.5x |
| `X1` | 101 | 3742 | 202 | 18.5x |

## Representative targets and views

Target rule, fixed before anything was scored and read from authored aim-point count and box size
only: for each authored aim-point count, the smallest and the largest target by bounding-sphere
reach `|H|`, plus the median one-point target. Ties by component name.

View rule: two ordinary bearings (`cases` ordinary bearings 0, 3) for every chosen target, plus two difficult bearings
in the perpendicular bisector plane of the target's nearest authored aim-point pair (`cases`
boundary bearings 0, 4) for every multi-point target. The target
rotation varies with the bearing exactly as `cases` defines it.

| target | authored points | bounding-sphere reach (m) | views |
|---|---:|---:|---|
| `engine_xen_xl_mothership_01_allround_mk1` | 4 | 357 | ordinary/b0, ordinary/b3, boundary/b0, boundary/b4 |
| `shield_bor_l_standard_01_mk2` | 1 | 17 | ordinary/b0, ordinary/b3 |
| `shield_bor_m_standard_02_mk3` | 1 | 4 | ordinary/b0, ordinary/b3 |
| `ship_arg_xl_carrier_02` | 4 | 1315 | ordinary/b0, ordinary/b3, boundary/b0, boundary/b4 |
| `ship_bor_l_miner_solid_01` | 2 | 519 | ordinary/b0, ordinary/b3, boundary/b0, boundary/b4 |
| `ship_gen_s_fightingdrone_01` | 3 | 9 | ordinary/b0, ordinary/b3, boundary/b0, boundary/b4 |
| `ship_kha_l_destroyer_01` | 1 | 788 | ordinary/b0, ordinary/b3 |
| `ship_pir_s_heavyfighter_01` | 2 | 24 | ordinary/b0, ordinary/b3, boundary/b0, boundary/b4 |
| `ship_ter_xl_resupplier_01` | 3 | 1232 | ordinary/b0, ordinary/b3, boundary/b0, boundary/b4 |

Standoffs: 100 m, 1000 m, 8000 m. Firing-ship rotation is `study.ROT[(6 x ship index + view index) mod 24]`, giving 24 distinct firing-ship rotations. The target rotation follows the bearing index, so the views cover 3 target rotations over 24 target/bearing combinations.

## Work reused, and expensive work removed

The near-target-only search reads only the target's runtime box and X4's answers from probe
positions on that box. It never sees the firing ship, so every scenario sharing a view runs the
identical search and sees the identical observations. Each view is searched **once** and the
finished map is reused for all 21 of its scenarios: 30 searches serve 630 scenarios. Sample cost is therefore reported per
search and correctness per scenario; the 100 m / 1 km / 8 km runs of one view are one search,
not three.

The A7.3 loading path skips `class_margins()`, the full mounted-turret movement sweep that finds
each ship class's search-box margin. The frozen search uses neither the firing-ship search box nor
its margin, and neither does the scoring. Measured on this machine, that sweep costs **155.8 s**
against **18.2 s** for the rest of the load, so it was 90% of the old setup cost. Older
experiments are untouched and still load it.

## Correctness

- firing ships tested: 7 (2 M, 4 L, 1 XL; 4 vanilla, 3 SWI)
- representative turret instances across them: 420
- target components tested: 9
- distinct searches: 30; scenarios: 630
- distances: 100 m, 1000 m, 8000 m
- ordinary views: 18; difficult (selection-boundary) views: 12
- distinct firing-ship rotations: 24

| aim-point discovery (denominator: the needed aim points of each scenario) | |
|---|---:|
| needed aim points total | 802 |
| needed aim points found | 802 |
| **needed aim points missed** | **0** |
| scenarios with any needed aim point missed | 0 |

| later-position choice accuracy (denominator: the legal aimed barrel positions on the representative loadout) | |
|---|---:|
| legal aimed barrel positions | 63864 |
| correct | 63795 |
| **wrong** | **0** |
| UNKNOWN | 69 |

| point-set safety (denominator: the distinct searches; the map is shared per view) | |
|---|---:|
| **invented points** | **0** |
| **merged points** | **0** |
| **duplicate points** | **0** |
| **refinement identity changes** | **0** |
| points confirmed | 78 |
| points tightened by refinement | 78 |
| authored aim points never found (diagnostic only) | 0 of 78 |

Authored aim points are diagnostic only: an authored point that no legal aimed barrel position on
the representative loadout ever selects is not needed, and not finding it is not a failure.

## Search cost

| | |
|---|---|
| samples used: median / p90 / worst | 38/38/38 |
| searches reaching the 40-sample limit | 30 of 30 |
| searches stopping because no useful next probe exists | 0 of 30 |
| searches ending with no confirmed point | 0 |

| stop reason | searches |
|---|---:|
| budget | 30 |

`last needed point at` is the sample count at which the last aim point any scenario of that
view actually needs became confirmed, so `samples used - that` is the room the safety of those
scenarios had left over.

- sample at which the last needed aim point was confirmed: median / p90 / worst 12/29/30
- samples remaining after it: median / p10 / worst 26 / 8 / 8

| smallest remaining margin | target | view | authored | samples used | last needed point at | margin |
|---:|---|---|---:|---:|---:|---:|
| 1 | `engine_xen_xl_mothership_01_allround_mk1` | ordinary/b0 | 4 | 38 | 30 | 8 |
| 2 | `engine_xen_xl_mothership_01_allround_mk1` | boundary/b0 | 4 | 38 | 30 | 8 |
| 3 | `engine_xen_xl_mothership_01_allround_mk1` | boundary/b4 | 4 | 38 | 30 | 8 |
| 4 | `ship_arg_xl_carrier_02` | ordinary/b0 | 4 | 38 | 29 | 9 |
| 5 | `ship_arg_xl_carrier_02` | ordinary/b3 | 4 | 38 | 29 | 9 |

## Timing

Offline Python timings on this machine, single process and niced, **not** live X4 runtime
timings. One sample here is a Python call into the accepted query model, not an engine call, so
these numbers measure where this benchmark spends its time, not what Gunnery Control would cost
in game.

Hidden truth exists only to check the answers. Gunnery Control never computes it: in game the
later barrel positions come from the engine. It is excluded from the production-like figure.

| measurement | mean | median | p90 | worst |
|---|---:|---:|---:|---:|
| production-like calculation, ms (shared search + applying the map to that ship's barrels) | 52.2 | 51.1 | 59.7 | 60.3 |
| aim-point search alone, ms (search + refinement, per search) | 51.7 | 50.4 | 59.6 | 60.0 |
| hidden truth, ms (research only) | 3837.7 | 1137.9 | 12876.6 | 27495.0 |
| scoring, ms (research only) | 2.3 | 0.8 | 6.2 | 31.3 |
| applying the map to one ship's barrels, ms | 0.4 | 0.2 | 1.2 | 5.4 |
| full research scenario, ms | 3892.3 | 1194.8 | 12930.2 | 27572.7 |

One-off corpus/setup: **18.6 s** (SWI index, corpus load, mount resolution, ship and
loadout selection, target and view population).

| phase | total (s) | share of the scenario work |
|---|---:|---:|
| hidden truth (research only) | 2417.8 | 99.9% |
| corpus/setup (one-off) | 18.6 | n/a |
| aim-point search (shared, per search) | 1.6 | 0.1% |
| scoring (research only) | 1.5 | 0.1% |
| applying the map to the firing ship's barrels | 0.3 | 0.0% |

**Slowest measured phase: hidden truth (research only).**

Slowest single scenario: view 26 (`ship_arg_xl_carrier_02` ordinary/b0, 4 authored points) against `ship_spl_xl_carrier_01_a_macro` (`X1`, 101 mounts, 202 representative turret instances, 681 legal aimed barrel positions) at 1000 m, 27573 ms: search 49 ms, hidden truth 27495 ms, applying the map 5 ms, scoring 23 ms. The measured cause is **generating the hidden benchmark truth**, at 99.7% of that scenario. Hidden-truth cost is mounts x representative turrets x authored aim points: this is the firing ship with the most representative turret instances against a target authoring the most aim points. The standoff does not change it.

## Decision

**PASS.** PASS on this representative population requires 0
wrong later-position choices, 0 needed aim points missed, 0 invented, 0 merged, 0 duplicate
points and 0 unsafe refinement identity changes. UNKNOWN is allowed and is reported separately.

- wrong later-position choices: 0
- needed aim points missed: 0
- invented / merged / duplicate points: 0 / 0 / 0
- refinement identity changes: 0
- UNKNOWN later-position results: 69 of 63864

This measures the frozen search on a deliberately small representative population. It is not an
exhaustive vanilla/SWI ship or turret matrix, it changes no production code, and it chooses
nothing: the starting geometry and the 40-sample total were frozen before the run.

## Per search

| view | target | group/bearing | authored | points | samples | end | needed (all scenarios) | needed missed | wrong | UNKNOWN | search ms |
|---:|---|---|---:|---:|---:|---|---:|---:|---:|---:|---:|
| 0 | `shield_bor_m_standard_02_mk3` | ordinary/b0 | 1 | 1 | 38 | budget | 21 | 0 | 0 | 0 | 60 |
| 1 | `shield_bor_m_standard_02_mk3` | ordinary/b3 | 1 | 1 | 38 | budget | 21 | 0 | 0 | 0 | 60 |
| 2 | `shield_bor_l_standard_01_mk2` | ordinary/b0 | 1 | 1 | 38 | budget | 18 | 0 | 0 | 0 | 60 |
| 3 | `shield_bor_l_standard_01_mk2` | ordinary/b3 | 1 | 1 | 38 | budget | 18 | 0 | 0 | 0 | 59 |
| 4 | `ship_kha_l_destroyer_01` | ordinary/b0 | 1 | 1 | 38 | budget | 21 | 0 | 0 | 0 | 60 |
| 5 | `ship_kha_l_destroyer_01` | ordinary/b3 | 1 | 1 | 38 | budget | 21 | 0 | 0 | 0 | 59 |
| 6 | `ship_pir_s_heavyfighter_01` | ordinary/b0 | 2 | 2 | 38 | budget | 24 | 0 | 0 | 0 | 54 |
| 7 | `ship_pir_s_heavyfighter_01` | ordinary/b3 | 2 | 2 | 38 | budget | 19 | 0 | 0 | 0 | 52 |
| 8 | `ship_pir_s_heavyfighter_01` | boundary/b0 | 2 | 2 | 38 | budget | 39 | 0 | 0 | 9 | 52 |
| 9 | `ship_pir_s_heavyfighter_01` | boundary/b4 | 2 | 2 | 38 | budget | 39 | 0 | 0 | 22 | 51 |
| 10 | `ship_bor_l_miner_solid_01` | ordinary/b0 | 2 | 2 | 38 | budget | 21 | 0 | 0 | 0 | 51 |
| 11 | `ship_bor_l_miner_solid_01` | ordinary/b3 | 2 | 2 | 38 | budget | 21 | 0 | 0 | 0 | 50 |
| 12 | `ship_bor_l_miner_solid_01` | boundary/b0 | 2 | 2 | 38 | budget | 36 | 0 | 0 | 0 | 52 |
| 13 | `ship_bor_l_miner_solid_01` | boundary/b4 | 2 | 2 | 38 | budget | 42 | 0 | 0 | 2 | 50 |
| 14 | `ship_gen_s_fightingdrone_01` | ordinary/b0 | 3 | 3 | 38 | budget | 24 | 0 | 0 | 0 | 51 |
| 15 | `ship_gen_s_fightingdrone_01` | ordinary/b3 | 3 | 3 | 38 | budget | 20 | 0 | 0 | 0 | 50 |
| 16 | `ship_gen_s_fightingdrone_01` | boundary/b0 | 3 | 3 | 38 | budget | 43 | 0 | 0 | 18 | 51 |
| 17 | `ship_gen_s_fightingdrone_01` | boundary/b4 | 3 | 3 | 38 | budget | 25 | 0 | 0 | 0 | 50 |
| 18 | `ship_ter_xl_resupplier_01` | ordinary/b0 | 3 | 3 | 38 | budget | 18 | 0 | 0 | 0 | 49 |
| 19 | `ship_ter_xl_resupplier_01` | ordinary/b3 | 3 | 3 | 38 | budget | 20 | 0 | 0 | 0 | 48 |
| 20 | `ship_ter_xl_resupplier_01` | boundary/b0 | 3 | 3 | 38 | budget | 36 | 0 | 0 | 2 | 48 |
| 21 | `ship_ter_xl_resupplier_01` | boundary/b4 | 3 | 3 | 38 | budget | 41 | 0 | 0 | 3 | 52 |
| 22 | `engine_xen_xl_mothership_01_allround_mk1` | ordinary/b0 | 4 | 4 | 38 | budget | 23 | 0 | 0 | 0 | 47 |
| 23 | `engine_xen_xl_mothership_01_allround_mk1` | ordinary/b3 | 4 | 4 | 38 | budget | 21 | 0 | 0 | 0 | 47 |
| 24 | `engine_xen_xl_mothership_01_allround_mk1` | boundary/b0 | 4 | 4 | 38 | budget | 48 | 0 | 0 | 8 | 46 |
| 25 | `engine_xen_xl_mothership_01_allround_mk1` | boundary/b4 | 4 | 4 | 38 | budget | 43 | 0 | 0 | 5 | 48 |
| 26 | `ship_arg_xl_carrier_02` | ordinary/b0 | 4 | 4 | 38 | budget | 18 | 0 | 0 | 0 | 49 |
| 27 | `ship_arg_xl_carrier_02` | ordinary/b3 | 4 | 4 | 38 | budget | 20 | 0 | 0 | 0 | 49 |
| 28 | `ship_arg_xl_carrier_02` | boundary/b0 | 4 | 4 | 38 | budget | 20 | 0 | 0 | 0 | 49 |
| 29 | `ship_arg_xl_carrier_02` | boundary/b4 | 4 | 4 | 38 | budget | 21 | 0 | 0 | 0 | 48 |

## Per firing ship, over every scenario

| | ship | scenarios | legal aimed barrel positions | needed | needed missed | correct | wrong | UNKNOWN | hidden truth ms med/worst | apply ms med/worst |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| `M1` | `ship_bor_m_trans_container_01_a_macro` | 90 | 201 | 49 | 0 | 193 | 0 | 8 | 210/321 | 0/0 |
| `M2` | `cumulus_class_macro` | 90 | 4585 | 117 | 0 | 4564 | 0 | 21 | 349/505 | 0/1 |
| `L1` | `ship_bor_l_miner_liquid_01_a_macro` | 90 | 1169 | 117 | 0 | 1153 | 0 | 16 | 701/1009 | 0/0 |
| `L2` | `ship_spl_l_destroyer_01_a_macro` | 90 | 4777 | 122 | 0 | 4772 | 0 | 5 | 3365/4734 | 0/1 |
| `L3` | `cis_cruiser_macro` | 90 | 18769 | 133 | 0 | 18755 | 0 | 14 | 4818/6862 | 1/2 |
| `L4` | `quasar_reb_macro` | 90 | 3284 | 129 | 0 | 3282 | 0 | 2 | 1661/2354 | 0/0 |
| `X1` | `ship_spl_xl_carrier_01_a_macro` | 90 | 31079 | 135 | 0 | 31076 | 0 | 3 | 19413/27495 | 1/5 |
