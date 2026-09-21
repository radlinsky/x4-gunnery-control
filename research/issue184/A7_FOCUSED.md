# Issue #184 A7.1: focused validation of the accepted method, and full stopping traces

Offline research, status **inference**. No X4 launch, no production change. The accepted A6
method is unchanged: the same 8 outer firing corners, the same cheap rescue, the same
near-target probe placement on the target runtime box + 50 m, the same point
confirmation and the same `refine_points` containment rule. Only the 12-primary-ask
experiment budget is lifted, so every case runs to the existing 24-ask angular-stage
hard limit and the whole trace exists. No stopping rule is implemented.

Run with `python3 research/issue184/aimpoint_map.py --a7`.

## Hidden truth: firing-ship-wide aimed muzzles

The shared aim-point result has to serve **later** turret positions on the firing ship, so the
benchmark cannot judge it against the one mount and turret a case happens to have chosen.
`ship_aimed_muzzles` builds the truth from every real mount on that same firing ship, paired
only with the corpus turrets `firing_mounts` already accepts for it. Each mount is placed by its
own frame through the case's unchanged ship position and rotation - never through the case
turret's origin or frame. Each such turret is aimed at each authored aim point; out-of-arc poses
are CANNOT BEAR and are discarded, resting poses are not tested, and the muzzle position after
aiming is fed to the accepted nearest-aim-point selection model. The points it selects are the
aim points this firing ship genuinely needs. None of this reaches the search: probe placement,
probe order, refinement, stopping and the ask budget are computed without it.

120,128 aimed muzzle positions over 126 cases (med/max 784/2.59e+03 per case), against 275 under the old single-turret truth - 437x more. They select 197 needed aim points over the 126 cases, out of 330 authored - so a third of the authored points are ones no turret on the firing ship can actually select against, and the benchmark no longer credits or blames the search for them.

## Population

126 cases, fixed before the run and never chosen from A7 results.

| group | geometries | cases | targets |
|---|---:|---:|---|
| hard | 19 | 57 | 6 distinct |
| ordinary | 23 | 69 | 23 distinct |

Ordinary targets (one deterministic non-boundary geometry each, reproduced at every gap):

- `engine_bor_l_travel_01_mk1` (engine, 1 authored point, case 3568)
- `engine_tfm_xl_carrier_02_allround_01_mk1` (engine, 1 authored point, case 4072)
- `engine_xen_xl_mothership_01_allround_mk1` (engine, 4 authored points, case 4168)
- `shield_bor_m_standard_02_mk3` (shield, 1 authored point, case 4432)
- `shield_xen_xl_standard_01_mk1` (shield, 1 authored point, case 5320)
- `ship_arg_l_destroyer_02` (whole, 3 authored points, case 5368)
- `ship_arg_xl_carrier_02` (whole, 4 authored points, case 5392)
- `ship_bor_l_miner_liquid_01` (whole, 2 authored points, case 5704)
- `ship_bor_l_miner_solid_01` (whole, 2 authored points, case 5728)
- `ship_gen_s_fightingdrone_01` (whole, 3 authored points, case 5776)
- `ship_kha_l_destroyer_01` (whole, 1 authored point, case 5800)
- `ship_par_l_expeditionary_01` (whole, 2 authored points, case 5824)
- `ship_pir_s_heavyfighter_01` (whole, 2 authored points, case 5992)
- `ship_tel_l_destroyer_01` (whole, 2 authored points, case 6232)
- `ship_tel_l_destroyer_02` (whole, 2 authored points, case 6256)
- `ship_tel_l_miner_liquid_02` (whole, 2 authored points, case 6280)
- `ship_tel_l_miner_solid_02` (whole, 2 authored points, case 6304)
- `ship_tel_l_trans_container_03` (whole, 2 authored points, case 6328)
- `ship_ter_xl_carrier_01` (whole, 3 authored points, case 6400)
- `ship_ter_xl_resupplier_01` (whole, 3 authored points, case 6424)
- `ship_xen_xs_pv_03_a` (whole, 1 authored point, case 6520)
- `turret_bor_m_arc_02_mk1` (turret, 1 authored point, case 7024)
- `turret_tel_l_laser_01_mk1` (turret, 1 authored point, case 8008)

Hard geometries: the 19 A4.3/A6 boundary cases (12155, 12157, 12160, 12163, 12169, 12177, 12196, 12197, 12360, 12362, 12365, 12366, 12368, 12369, 12388, 12390, 12199, 12234, 12376).

## Final result at the 24-ask angular limit

b = baseline, a = refined. Correct/wrong/UNKNOWN are over the hidden later aimed muzzles.

| group | gap (m) | cases | asks med/p90/max | angular med/max | guard | stalled | pts | authored missing | needed missing | correct b/a | wrong b/a | UNKNOWN b/a | radius med/max a (m) | error med/max a (m) |
|---|---:|---:|---|---|---:|---:|---:|---:|---:|---|---|---|---|---|
| hard | 100 | 19 | 35 / 38 / 39 | 22 / 22 / 22 | 19 | 0 | 64 | 0 of 64 | 0 | 22400 / 22633 | 0 / 0 | 248 / 15 | 0.00219/0.0273 | 0.000346/0.0123 |
| hard | 1000 | 19 | 35 / 38 / 38 | 22 / 22 / 22 | 19 | 0 | 64 | 0 of 64 | 0 | 22770 / 23165 | 0 / 0 | 406 / 11 | 0.00208/0.0462 | 0.000328/0.013 |
| hard | 8000 | 19 | 35 / 38 / 38 | 22 / 22 / 22 | 19 | 0 | 63 | 1 of 64 | 0 | 22227 / 24170 | 0 / 0 | 2012 / 69 | 0.00209/0.0363 | 0.000306/0.00828 |
| ordinary | 100 | 23 | 32 / 35 / 35 | 22 / 22 / 22 | 23 | 0 | 46 | 0 of 46 | 0 | 16253 / 16433 | 0 / 0 | 180 / 0 | 0.00207/0.372 | 0.000261/0.148 |
| ordinary | 1000 | 23 | 32 / 32 / 35 | 22 / 22 / 23 | 23 | 0 | 46 | 0 of 46 | 0 | 16362 / 16638 | 0 / 0 | 276 / 0 | 0.00193/0.114 | 0.0003/0.00571 |
| ordinary | 8000 | 23 | 32 / 32 / 35 | 22 / 22 / 22 | 23 | 0 | 46 | 0 of 46 | 0 | 16421 / 16994 | 0 / 0 | 573 / 0 | 0.00183/0.146 | 0.000275/0.0496 |

## Refinement safety

Every failure class counted over every reconstructed state of every case, not only the final
one, so a prefix refinement would have damaged is caught too. `wrong b/a` is the baseline and
refined wrong count at the same state; `caused by refinement` is the part refinement added,
which is the number this experiment is actually testing.

| group | states | wrong b/a | caused by refinement | identity changed | invented | merged | duplicate | correct -> UNKNOWN | points refined |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|
| hard | 1077 | 14424 / 14424 | 0 | 0 | 0 | 0 | 0 | 0 | 2693 |
| ordinary | 1345 | 0 / 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1964 |
| all | 2422 | 14424 / 14424 | 0 | 0 | 0 | 0 | 0 | 0 | 4657 |

The wrong answers are identical before and after refinement and all sit in early prefixes of 7 case instances (12160 @100 m, 12160 @1000 m, 12160 @8000 m, 12234 @100 m, 12376 @100 m, 12376 @1000 m, 12376 @8000 m), where only part of the target's aim points has been confirmed and `nearest` names a known point confidently because the point that actually wins is not yet in the set. They are a discovery-completeness effect, not a refinement effect, and every one of them is gone by the final state. They are also exactly why a prefix is scored as unsafe below.

## Earliest state as safe and useful as the final 24-ask result

A state qualifies when its refined result has no wrong answer, no identity change and no
invented, merged or duplicate point, is not below the final result on correct answers, not
above it on UNKNOWN or missed points, and represents every needed aim point the final result
represents. `gap` is the largest viewing-angle gap still open at that state - an observable
quantity the search already computes.

| group | gap (m) | cases | earliest angular asks med/max | earliest total asks med/max | gap at earliest med/max (deg) | never safe |
|---|---:|---:|---|---|---|---:|
| hard | 100 | 19 | 13/20 | 26/33 | 118/179 | 0 |
| hard | 1000 | 19 | 10/21 | 26/34 | 89.7/179 | 0 |
| hard | 8000 | 19 | 13/22 | 27/35 | 89.3/179 | 0 |
| ordinary | 100 | 23 | 0/22 | 13/32 | 155/179 | 0 |
| ordinary | 1000 | 23 | 5/23 | 15/33 | 158/179 | 0 |
| ordinary | 8000 | 23 | 5/19 | 15/29 | 177/179 | 0 |

## Candidate observable stopping rules

`stop when the largest remaining viewing-angle gap <= T`, evaluated against the completed
traces. A state with no definite candidate left counts as gap 0. The 24-ask limit
remains the backstop in every row.

| T (deg) | cases stopped early | unsafe stops | angular asks med/max | worst loss |
|---:|---:|---:|---|---|
| 90 | 126 | 68 | 3/17 | case 12376 @8000 m: correct 1135 vs 2124, needed missing 1 vs 0 |
| 60 | 92 | 11 | 15/23 | case 5776 @100 m: correct 2436 vs 2460, needed missing 0 vs 0 |
| 45 | 35 | 1 | 22/23 | case 5776 @100 m: correct 2436 vs 2460, needed missing 0 vs 0 |
| 30 | 7 | 0 | 22/23 | none |
| 20 | 0 | 0 | 22/23 | none |
| 15 | 0 | 0 | 22/23 | none |
| 10 | 0 | 0 | 22/23 | none |
| 5 | 0 | 0 | 22/23 | none |
| 2 | 0 | 0 | 22/23 | none |
| 1 | 0 | 0 | 22/23 | none |

`stop after k consecutive angular asks that confirmed no new point`, the other observable
the search already has:

| k | cases stopped early | unsafe stops | angular asks med/max |
|---:|---:|---:|---|
| 2 | 126 | 66 | 2/18 |
| 4 | 124 | 56 | 4/22 |
| 6 | 118 | 30 | 11/22 |
| 8 | 113 | 20 | 13/23 |
| 10 | 100 | 9 | 15/23 |
| 12 | 85 | 4 | 17/23 |
| 14 | 80 | 2 | 19/23 |
| 16 | 70 | 0 | 21/23 |
| 18 | 46 | 0 | 22/23 |
| 20 | 46 | 0 | 22/23 |

## Verdict

**No simple observable rule buys anything here.** The largest gap threshold that is safe on every one of the 126 cases is T = 43.5 deg, and it spends 22/23 angular-stage asks (med/max) against 22/23 for the unrestricted run - no saving. The quiet-ask rule is the same story: the smallest safe k is 16, at 21/23 asks.

The reason is visible in the gap distributions: states that are **not** yet as good as the final result span 43.5 to 180 deg, while the earliest safe state of each case sits between 45.8 and 179 deg. The two ranges overlap almost completely, so the largest remaining viewing angle does not separate a state that is already good enough from one that is not.

The headroom is real and unclaimed: with hindsight the earliest safe state needs only 7.5/23 angular-stage asks (med/max) against 22/23 actually spent. No observable tested here finds it. **The existing 24-ask angular-stage limit remains the fallback stopping condition**, and A7 implements no rule.

## Limitations

- 126 cases, not the full #184 benchmark. The ordinary half is one deterministic geometry per target and one bearing, so it measures target variety, not bearing variety.
- The 'as safe and useful as the final result' test compares each case against its own 24-ask result. It cannot see a point no state of that case ever discovered.
- Every case now carries aimed muzzles (8 at the least), so all 126 contribute answer evidence; under the old single-turret truth 27 of them contributed none.
- Every case here ran to the 24-ask limit by construction, so the ask counts in this note are the cost of collecting the trace, not the cost of the accepted method under its own 12-primary-ask budget.
- The containment rule in `refine_points` was not weakened, so the points it skips are still skipped; whether a weaker condition stays sound is untested.

## Per case

| case | group | target | gap (m) | asks | angular | primary | guard | stalled | pts | authored missing | correct | wrong | UNKNOWN | earliest safe primary / angular / gap (deg) |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 12155 | hard | `engine_xen_xl_mothership_01_allround_mk1` | 100 | 35 | 22 | 14 | 1 | 0 | 4 | 0 | 252 | 0 | 0 | 5 / 13 / 160 |
| 12155 | hard | `engine_xen_xl_mothership_01_allround_mk1` | 1000 | 35 | 22 | 12 | 1 | 0 | 4 | 0 | 252 | 0 | 0 | 6 / 16 / 148 |
| 12155 | hard | `engine_xen_xl_mothership_01_allround_mk1` | 8000 | 35 | 22 | 14 | 1 | 0 | 4 | 0 | 252 | 0 | 0 | 13 / 21 / 89.6 |
| 12157 | hard | `engine_xen_xl_mothership_01_allround_mk1` | 100 | 35 | 22 | 14 | 1 | 0 | 4 | 0 | 372 | 0 | 0 | 12 / 20 / 118 |
| 12157 | hard | `engine_xen_xl_mothership_01_allround_mk1` | 1000 | 35 | 22 | 14 | 1 | 0 | 4 | 0 | 396 | 0 | 0 | 10 / 18 / 86.3 |
| 12157 | hard | `engine_xen_xl_mothership_01_allround_mk1` | 8000 | 35 | 22 | 14 | 1 | 0 | 4 | 0 | 408 | 0 | 0 | 8 / 16 / 105 |
| 12160 | hard | `engine_xen_xl_mothership_01_allround_mk1` | 100 | 39 | 22 | 19 | 1 | 0 | 4 | 0 | 294 | 0 | 0 | 5 / 8 / 118 |
| 12160 | hard | `engine_xen_xl_mothership_01_allround_mk1` | 1000 | 38 | 22 | 18 | 1 | 0 | 4 | 0 | 338 | 0 | 0 | 6 / 10 / 178 |
| 12160 | hard | `engine_xen_xl_mothership_01_allround_mk1` | 8000 | 38 | 22 | 18 | 1 | 0 | 4 | 0 | 484 | 0 | 0 | 9 / 13 / 89.6 |
| 12163 | hard | `engine_xen_xl_mothership_01_allround_mk1` | 100 | 35 | 22 | 14 | 1 | 0 | 4 | 0 | 332 | 0 | 4 | 5 / 13 / 172 |
| 12163 | hard | `engine_xen_xl_mothership_01_allround_mk1` | 1000 | 35 | 22 | 14 | 1 | 0 | 4 | 0 | 336 | 0 | 0 | 13 / 21 / 87.5 |
| 12163 | hard | `engine_xen_xl_mothership_01_allround_mk1` | 8000 | 35 | 22 | 14 | 1 | 0 | 4 | 0 | 336 | 0 | 0 | 14 / 22 / 171 |
| 12169 | hard | `ship_arg_l_destroyer_02` | 100 | 38 | 22 | 22 | 1 | 0 | 3 | 0 | 313 | 0 | 0 | 0 / 0 / 169 |
| 12169 | hard | `ship_arg_l_destroyer_02` | 1000 | 38 | 22 | 22 | 1 | 0 | 3 | 0 | 337 | 0 | 0 | 0 / 0 / 173 |
| 12169 | hard | `ship_arg_l_destroyer_02` | 8000 | 38 | 22 | 22 | 1 | 0 | 3 | 0 | 361 | 0 | 0 | 9 / 9 / 89.3 |
| 12177 | hard | `ship_arg_l_destroyer_02` | 100 | 38 | 22 | 22 | 1 | 0 | 3 | 0 | 1956 | 0 | 0 | 0 / 0 / 155 |
| 12177 | hard | `ship_arg_l_destroyer_02` | 1000 | 38 | 22 | 22 | 1 | 0 | 3 | 0 | 2062 | 0 | 0 | 5 / 5 / 89.7 |
| 12177 | hard | `ship_arg_l_destroyer_02` | 8000 | 38 | 22 | 22 | 1 | 0 | 3 | 0 | 2076 | 0 | 0 | 6 / 6 / 89.9 |
| 12196 | hard | `ship_arg_xl_carrier_02` | 100 | 35 | 22 | 14 | 1 | 0 | 4 | 0 | 1344 | 0 | 0 | 10 / 18 / 86.2 |
| 12196 | hard | `ship_arg_xl_carrier_02` | 1000 | 35 | 22 | 14 | 1 | 0 | 4 | 0 | 1344 | 0 | 0 | 11 / 19 / 86.7 |
| 12196 | hard | `ship_arg_xl_carrier_02` | 8000 | 35 | 22 | 13 | 1 | 0 | 4 | 0 | 1344 | 0 | 0 | 11 / 20 / 87.6 |
| 12197 | hard | `ship_arg_xl_carrier_02` | 100 | 35 | 22 | 14 | 1 | 0 | 4 | 0 | 1436 | 0 | 2 | 11 / 19 / 149 |
| 12197 | hard | `ship_arg_xl_carrier_02` | 1000 | 35 | 22 | 14 | 1 | 0 | 4 | 0 | 1438 | 0 | 2 | 10 / 18 / 161 |
| 12197 | hard | `ship_arg_xl_carrier_02` | 8000 | 35 | 22 | 13 | 1 | 0 | 4 | 0 | 1436 | 0 | 4 | 10 / 19 / 91.4 |
| 12199 | hard | `ship_arg_xl_carrier_02` | 100 | 38 | 22 | 18 | 1 | 0 | 4 | 0 | 1346 | 0 | 0 | 7 / 11 / 89.1 |
| 12199 | hard | `ship_arg_xl_carrier_02` | 1000 | 37 | 22 | 18 | 1 | 0 | 4 | 0 | 1344 | 0 | 0 | 6 / 10 / 89.3 |
| 12199 | hard | `ship_arg_xl_carrier_02` | 8000 | 38 | 22 | 18 | 1 | 0 | 4 | 0 | 1344 | 0 | 0 | 9 / 13 / 88.9 |
| 12234 | hard | `ship_gen_s_fightingdrone_01` | 100 | 34 | 22 | 18 | 1 | 0 | 3 | 0 | 1008 | 0 | 0 | 6 / 10 / 81.2 |
| 12234 | hard | `ship_gen_s_fightingdrone_01` | 1000 | 38 | 22 | 22 | 1 | 0 | 3 | 0 | 1008 | 0 | 0 | 10 / 10 / 61.6 |
| 12234 | hard | `ship_gen_s_fightingdrone_01` | 8000 | 34 | 22 | 9 | 1 | 0 | 3 | 0 | 957 | 0 | 51 | 6 / 10 / 81.5 |
| 12360 | hard | `ship_ter_xl_carrier_01` | 100 | 38 | 22 | 22 | 1 | 0 | 3 | 0 | 1384 | 0 | 0 | 4 / 4 / 88.7 |
| 12360 | hard | `ship_ter_xl_carrier_01` | 1000 | 38 | 22 | 22 | 1 | 0 | 3 | 0 | 1394 | 0 | 0 | 4 / 4 / 89.1 |
| 12360 | hard | `ship_ter_xl_carrier_01` | 8000 | 38 | 22 | 22 | 1 | 0 | 3 | 0 | 1470 | 0 | 0 | 6 / 6 / 89.4 |
| 12362 | hard | `ship_ter_xl_carrier_01` | 100 | 35 | 22 | 18 | 1 | 0 | 3 | 0 | 1327 | 0 | 0 | 7 / 11 / 179 |
| 12362 | hard | `ship_ter_xl_carrier_01` | 1000 | 35 | 22 | 18 | 1 | 0 | 3 | 0 | 1327 | 0 | 0 | 6 / 10 / 179 |
| 12362 | hard | `ship_ter_xl_carrier_01` | 8000 | 35 | 22 | 18 | 1 | 0 | 3 | 0 | 1480 | 0 | 0 | 10 / 14 / 83.4 |
| 12365 | hard | `ship_ter_xl_carrier_01` | 100 | 35 | 22 | 18 | 1 | 0 | 3 | 0 | 2139 | 0 | 0 | 10 / 14 / 81.5 |
| 12365 | hard | `ship_ter_xl_carrier_01` | 1000 | 35 | 22 | 18 | 1 | 0 | 3 | 0 | 2161 | 0 | 0 | 7 / 11 / 86.9 |
| 12365 | hard | `ship_ter_xl_carrier_01` | 8000 | 35 | 22 | 18 | 1 | 0 | 3 | 0 | 2190 | 0 | 0 | 7 / 11 / 88.8 |
| 12366 | hard | `ship_ter_xl_carrier_01` | 100 | 35 | 22 | 18 | 1 | 0 | 3 | 0 | 1252 | 0 | 0 | 9 / 13 / 179 |
| 12366 | hard | `ship_ter_xl_carrier_01` | 1000 | 35 | 22 | 18 | 1 | 0 | 3 | 0 | 1255 | 0 | 0 | 3 / 7 / 179 |
| 12366 | hard | `ship_ter_xl_carrier_01` | 8000 | 35 | 22 | 21 | 1 | 0 | 2 | 1 | 1298 | 0 | 0 | 6 / 6 / 83.8 |
| 12368 | hard | `ship_ter_xl_carrier_01` | 100 | 38 | 22 | 22 | 1 | 0 | 3 | 0 | 1326 | 0 | 0 | 10 / 10 / 82.2 |
| 12368 | hard | `ship_ter_xl_carrier_01` | 1000 | 38 | 22 | 22 | 1 | 0 | 3 | 0 | 1345 | 0 | 0 | 10 / 10 / 80.8 |
| 12368 | hard | `ship_ter_xl_carrier_01` | 8000 | 38 | 22 | 22 | 1 | 0 | 3 | 0 | 1421 | 0 | 5 | 16 / 16 / 64.1 |
| 12369 | hard | `ship_ter_xl_carrier_01` | 100 | 38 | 22 | 22 | 1 | 0 | 3 | 0 | 2133 | 0 | 0 | 10 / 10 / 83.2 |
| 12369 | hard | `ship_ter_xl_carrier_01` | 1000 | 38 | 22 | 22 | 1 | 0 | 3 | 0 | 2179 | 0 | 0 | 10 / 10 / 85.9 |
| 12369 | hard | `ship_ter_xl_carrier_01` | 8000 | 38 | 22 | 22 | 1 | 0 | 3 | 0 | 2261 | 0 | 0 | 7 / 7 / 89.6 |
| 12376 | hard | `ship_ter_xl_resupplier_01` | 100 | 34 | 22 | 17 | 1 | 0 | 3 | 0 | 1829 | 0 | 9 | 8 / 13 / 99.8 |
| 12376 | hard | `ship_ter_xl_resupplier_01` | 1000 | 34 | 22 | 18 | 1 | 0 | 3 | 0 | 1958 | 0 | 9 | 10 / 14 / 89.8 |
| 12376 | hard | `ship_ter_xl_resupplier_01` | 8000 | 34 | 22 | 18 | 1 | 0 | 3 | 0 | 2124 | 0 | 9 | 18 / 22 / 54.5 |
| 12388 | hard | `ship_ter_xl_resupplier_01` | 100 | 35 | 22 | 18 | 1 | 0 | 3 | 0 | 1226 | 0 | 0 | 11 / 15 / 179 |
| 12388 | hard | `ship_ter_xl_resupplier_01` | 1000 | 35 | 22 | 18 | 1 | 0 | 3 | 0 | 1300 | 0 | 0 | 11 / 15 / 179 |
| 12388 | hard | `ship_ter_xl_resupplier_01` | 8000 | 35 | 22 | 18 | 1 | 0 | 3 | 0 | 1392 | 0 | 0 | 9 / 13 / 179 |
| 12390 | hard | `ship_ter_xl_resupplier_01` | 100 | 35 | 22 | 18 | 1 | 0 | 3 | 0 | 1364 | 0 | 0 | 10 / 14 / 179 |
| 12390 | hard | `ship_ter_xl_resupplier_01` | 1000 | 35 | 22 | 18 | 1 | 0 | 3 | 0 | 1391 | 0 | 0 | 11 / 15 / 179 |
| 12390 | hard | `ship_ter_xl_resupplier_01` | 8000 | 35 | 22 | 18 | 1 | 0 | 3 | 0 | 1536 | 0 | 0 | 9 / 13 / 85.9 |
| 3568 | ordinary | `engine_bor_l_travel_01_mk1` | 100 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 624 | 0 | 0 | 0 / 0 / 159 |
| 3568 | ordinary | `engine_bor_l_travel_01_mk1` | 1000 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 624 | 0 | 0 | 0 / 0 / 160 |
| 3568 | ordinary | `engine_bor_l_travel_01_mk1` | 8000 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 600 | 0 | 0 | 0 / 0 / 166 |
| 4072 | ordinary | `engine_tfm_xl_carrier_02_allround_01_mk1` | 100 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 228 | 0 | 0 | 0 / 0 / 121 |
| 4072 | ordinary | `engine_tfm_xl_carrier_02_allround_01_mk1` | 1000 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 228 | 0 | 0 | 0 / 0 / 144 |
| 4072 | ordinary | `engine_tfm_xl_carrier_02_allround_01_mk1` | 8000 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 228 | 0 | 0 | 0 / 0 / 170 |
| 4168 | ordinary | `engine_xen_xl_mothership_01_allround_mk1` | 100 | 32 | 22 | 9 | 1 | 0 | 4 | 0 | 1439 | 0 | 0 | 8 / 21 / 149 |
| 4168 | ordinary | `engine_xen_xl_mothership_01_allround_mk1` | 1000 | 33 | 23 | 11 | 1 | 0 | 4 | 0 | 1442 | 0 | 0 | 11 / 23 / 158 |
| 4168 | ordinary | `engine_xen_xl_mothership_01_allround_mk1` | 8000 | 32 | 22 | 10 | 1 | 0 | 4 | 0 | 1447 | 0 | 0 | 4 / 16 / 177 |
| 4432 | ordinary | `shield_bor_m_standard_02_mk3` | 100 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 266 | 0 | 0 | 0 / 0 / 121 |
| 4432 | ordinary | `shield_bor_m_standard_02_mk3` | 1000 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 266 | 0 | 0 | 0 / 0 / 156 |
| 4432 | ordinary | `shield_bor_m_standard_02_mk3` | 8000 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 266 | 0 | 0 | 0 / 0 / 175 |
| 5320 | ordinary | `shield_xen_xl_standard_01_mk1` | 100 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 280 | 0 | 0 | 0 / 0 / 107 |
| 5320 | ordinary | `shield_xen_xl_standard_01_mk1` | 1000 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 290 | 0 | 0 | 0 / 0 / 131 |
| 5320 | ordinary | `shield_xen_xl_standard_01_mk1` | 8000 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 290 | 0 | 0 | 0 / 0 / 168 |
| 5368 | ordinary | `ship_arg_l_destroyer_02` | 100 | 32 | 22 | 14 | 1 | 0 | 3 | 0 | 705 | 0 | 0 | 3 / 11 / 179 |
| 5368 | ordinary | `ship_arg_l_destroyer_02` | 1000 | 32 | 22 | 14 | 1 | 0 | 3 | 0 | 705 | 0 | 0 | 3 / 11 / 179 |
| 5368 | ordinary | `ship_arg_l_destroyer_02` | 8000 | 32 | 22 | 14 | 1 | 0 | 3 | 0 | 705 | 0 | 0 | 5 / 13 / 178 |
| 5392 | ordinary | `ship_arg_xl_carrier_02` | 100 | 32 | 22 | 8 | 1 | 0 | 4 | 0 | 940 | 0 | 0 | 6 / 20 / 155 |
| 5392 | ordinary | `ship_arg_xl_carrier_02` | 1000 | 32 | 22 | 10 | 1 | 0 | 4 | 0 | 940 | 0 | 0 | 8 / 20 / 179 |
| 5392 | ordinary | `ship_arg_xl_carrier_02` | 8000 | 32 | 22 | 10 | 1 | 0 | 4 | 0 | 940 | 0 | 0 | 7 / 19 / 178 |
| 5704 | ordinary | `ship_bor_l_miner_liquid_01` | 100 | 34 | 22 | 22 | 1 | 0 | 2 | 0 | 1400 | 0 | 0 | 0 / 0 / 137 |
| 5704 | ordinary | `ship_bor_l_miner_liquid_01` | 1000 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 1512 | 0 | 0 | 2 / 6 / 150 |
| 5704 | ordinary | `ship_bor_l_miner_liquid_01` | 8000 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 1728 | 0 | 0 | 1 / 5 / 179 |
| 5728 | ordinary | `ship_bor_l_miner_solid_01` | 100 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 1736 | 0 | 0 | 1 / 5 / 179 |
| 5728 | ordinary | `ship_bor_l_miner_solid_01` | 1000 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 1736 | 0 | 0 | 1 / 5 / 179 |
| 5728 | ordinary | `ship_bor_l_miner_solid_01` | 8000 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 1728 | 0 | 0 | 1 / 5 / 179 |
| 5776 | ordinary | `ship_gen_s_fightingdrone_01` | 100 | 35 | 22 | 18 | 1 | 0 | 3 | 0 | 2460 | 0 | 0 | 15 / 19 / 45.8 |
| 5776 | ordinary | `ship_gen_s_fightingdrone_01` | 1000 | 35 | 22 | 18 | 1 | 0 | 3 | 0 | 2508 | 0 | 0 | 6 / 10 / 69.6 |
| 5776 | ordinary | `ship_gen_s_fightingdrone_01` | 8000 | 35 | 22 | 18 | 1 | 0 | 3 | 0 | 2592 | 0 | 0 | 8 / 12 / 66.5 |
| 5800 | ordinary | `ship_kha_l_destroyer_01` | 100 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 872 | 0 | 0 | 0 / 0 / 155 |
| 5800 | ordinary | `ship_kha_l_destroyer_01` | 1000 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 868 | 0 | 0 | 0 / 0 / 158 |
| 5800 | ordinary | `ship_kha_l_destroyer_01` | 8000 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 864 | 0 | 0 | 0 / 0 / 167 |
| 5824 | ordinary | `ship_par_l_expeditionary_01` | 100 | 35 | 22 | 22 | 1 | 0 | 2 | 0 | 1652 | 0 | 0 | 0 / 0 / 166 |
| 5824 | ordinary | `ship_par_l_expeditionary_01` | 1000 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 1680 | 0 | 0 | 2 / 6 / 179 |
| 5824 | ordinary | `ship_par_l_expeditionary_01` | 8000 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 1728 | 0 | 0 | 1 / 5 / 179 |
| 5992 | ordinary | `ship_pir_s_heavyfighter_01` | 100 | 35 | 22 | 22 | 1 | 0 | 2 | 0 | 8 | 0 | 0 | 0 / 0 / 169 |
| 5992 | ordinary | `ship_pir_s_heavyfighter_01` | 1000 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 8 | 0 | 0 | 1 / 5 / 179 |
| 5992 | ordinary | `ship_pir_s_heavyfighter_01` | 8000 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 8 | 0 | 0 | 1 / 5 / 175 |
| 6232 | ordinary | `ship_tel_l_destroyer_01` | 100 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 151 | 0 | 0 | 1 / 5 / 159 |
| 6232 | ordinary | `ship_tel_l_destroyer_01` | 1000 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 156 | 0 | 0 | 1 / 5 / 179 |
| 6232 | ordinary | `ship_tel_l_destroyer_01` | 8000 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 156 | 0 | 0 | 1 / 5 / 172 |
| 6256 | ordinary | `ship_tel_l_destroyer_02` | 100 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 434 | 0 | 0 | 1 / 5 / 179 |
| 6256 | ordinary | `ship_tel_l_destroyer_02` | 1000 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 437 | 0 | 0 | 1 / 5 / 179 |
| 6256 | ordinary | `ship_tel_l_destroyer_02` | 8000 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 440 | 0 | 0 | 1 / 5 / 179 |
| 6280 | ordinary | `ship_tel_l_miner_liquid_02` | 100 | 34 | 22 | 22 | 1 | 0 | 2 | 0 | 437 | 0 | 0 | 0 / 0 / 126 |
| 6280 | ordinary | `ship_tel_l_miner_liquid_02` | 1000 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 440 | 0 | 0 | 2 / 6 / 152 |
| 6280 | ordinary | `ship_tel_l_miner_liquid_02` | 8000 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 440 | 0 | 0 | 1 / 5 / 179 |
| 6304 | ordinary | `ship_tel_l_miner_solid_02` | 100 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 437 | 0 | 0 | 1 / 5 / 179 |
| 6304 | ordinary | `ship_tel_l_miner_solid_02` | 1000 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 434 | 0 | 0 | 1 / 5 / 179 |
| 6304 | ordinary | `ship_tel_l_miner_solid_02` | 8000 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 437 | 0 | 0 | 1 / 5 / 179 |
| 6328 | ordinary | `ship_tel_l_trans_container_03` | 100 | 34 | 22 | 22 | 1 | 0 | 2 | 0 | 440 | 0 | 0 | 0 / 0 / 121 |
| 6328 | ordinary | `ship_tel_l_trans_container_03` | 1000 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 440 | 0 | 0 | 1 / 5 / 179 |
| 6328 | ordinary | `ship_tel_l_trans_container_03` | 8000 | 32 | 22 | 18 | 1 | 0 | 2 | 0 | 440 | 0 | 0 | 1 / 5 / 178 |
| 6400 | ordinary | `ship_ter_xl_carrier_01` | 100 | 32 | 22 | 14 | 1 | 0 | 3 | 0 | 657 | 0 | 0 | 14 / 22 / 167 |
| 6400 | ordinary | `ship_ter_xl_carrier_01` | 1000 | 32 | 22 | 14 | 1 | 0 | 3 | 0 | 654 | 0 | 0 | 11 / 19 / 179 |
| 6400 | ordinary | `ship_ter_xl_carrier_01` | 8000 | 32 | 22 | 14 | 1 | 0 | 3 | 0 | 657 | 0 | 0 | 2 / 10 / 178 |
| 6424 | ordinary | `ship_ter_xl_resupplier_01` | 100 | 35 | 22 | 18 | 1 | 0 | 3 | 0 | 657 | 0 | 0 | 1 / 5 / 179 |
| 6424 | ordinary | `ship_ter_xl_resupplier_01` | 1000 | 32 | 22 | 14 | 1 | 0 | 3 | 0 | 657 | 0 | 0 | 3 / 11 / 144 |
| 6424 | ordinary | `ship_ter_xl_resupplier_01` | 8000 | 32 | 22 | 14 | 1 | 0 | 3 | 0 | 657 | 0 | 0 | 10 / 18 / 177 |
| 6520 | ordinary | `ship_xen_xs_pv_03_a` | 100 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 85 | 0 | 0 | 0 / 0 / 94.3 |
| 6520 | ordinary | `ship_xen_xs_pv_03_a` | 1000 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 85 | 0 | 0 | 0 / 0 / 151 |
| 6520 | ordinary | `ship_xen_xs_pv_03_a` | 8000 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 76 | 0 | 0 | 0 / 0 / 175 |
| 7024 | ordinary | `turret_bor_m_arc_02_mk1` | 100 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 433 | 0 | 0 | 0 / 0 / 138 |
| 7024 | ordinary | `turret_bor_m_arc_02_mk1` | 1000 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 436 | 0 | 0 | 0 / 0 / 144 |
| 7024 | ordinary | `turret_bor_m_arc_02_mk1` | 8000 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 475 | 0 | 0 | 0 / 0 / 164 |
| 8008 | ordinary | `turret_tel_l_laser_01_mk1` | 100 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 92 | 0 | 0 | 0 / 0 / 93.9 |
| 8008 | ordinary | `turret_tel_l_laser_01_mk1` | 1000 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 92 | 0 | 0 | 0 / 0 / 155 |
| 8008 | ordinary | `turret_tel_l_laser_01_mk1` | 8000 | 32 | 22 | 22 | 1 | 0 | 1 | 0 | 92 | 0 | 0 | 0 / 0 / 175 |
