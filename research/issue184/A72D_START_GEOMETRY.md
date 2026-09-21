# Issue #184 A7.2d: where the near-target-only search should start

Offline research, status **inference**. No X4 launch, no production change, no change to the
adaptive near-target search itself and no choice of a production sample budget. Run with
`python3 research/issue184/aimpoint_map.py --a72d`.

One **sample** is one X4 aim-direction lookup from one probe position.

## The question

Is there a simple generic starting geometry that establishes the first aim point faster and more
reliably than the current 4 alternating corners, without reducing recovery of the aim points the
firing ship actually needs?

The starting probes do not have to discover every aim point. Their whole job is to confirm one
genuine aim point accurately enough that the existing adaptive near-target search can begin; that
search is then responsible for the rest. So a candidate is judged on how cheaply and how reliably
it reaches the first confirmed point, never on how many points it happens to turn up on the way.

## What counts as a needed aim point

For each firing-ship/target scenario the **needed** aim points are the unique target aim points
X4's accepted selection model actually selects from at least one legal aimed muzzle position
available to that firing ship - every real mount, every compatible turret the benchmark accepts,
the barrel position after the turret aims, out-of-arc poses excluded as CANNOT BEAR, no resting
positions. An authored aim point that no legal aimed muzzle on that ship ever selects is not
needed, and not finding it is not a search failure. Authored-point discovery is kept below as a
clearly labelled secondary diagnostic only: it never decides PASS/FAIL and never picks a
candidate.

Two denominators, never mixed:

1. **aim-point discovery** - denominator is the needed aim points of that scenario, reported as
   needed found / needed total and needed missed;
2. **later-position choice accuracy** - denominator is the legal aimed muzzle positions used as
   hidden truth, reported as correct / wrong / UNKNOWN.

Hidden aim points and later turret positions are scoring truth only. They never touch probe
placement, the starting geometry, stopping or the budget.

## Deduplicating the startup population

The near-target starting probes are placed relative to the target, and every later step of this
search reads only the target's runtime box and X4's answers from positions on it. Two cases that
differ only by the firing ship's standoff therefore run the identical search and see the identical
observations - the A7.2c traces show it directly, with the same point confirmed at the same sample
count at 100 m, 1 km and 8 km. Counting those as three independent startup successes would weight
a geometry by how often it was repeated, so each **entry** below is one startup geometry, and it
carries its 100 m / 1 km / 8 km scenarios for the parts that really do depend on the firing ship:
the needed aim points and the later aimed muzzle positions.

## Population and split

85 startup entries: the 19 hard A6 boundary geometries plus one deterministic ordinary
geometry (bearing 0, 1 km gap, the rule `a7_ordinary` uses) for every target that authors more
than one aim point and every 4th one-point target by alphabetical rank. 202 of the 217
corpus targets author a single aim point and are startup-identical in shape, so sampling them keeps
box sizes and proportions varied without drowning the comparison in near-duplicates.

**Split rule, fixed before any candidate was scored and independent of every result:** rank the
target components alphabetically; even rank goes to the development set, odd rank to the holdout.
The split is by component, so one target never appears on both sides under a different distance,
bearing or rotation.

- development: 44 entries, 33 target components;
- holdout: 41 entries, 33 target components.

## The candidate starting geometries

All six were written down in full before any of them was scored, and none was added, removed,
reordered, rotated or retuned afterwards. Every rule uses only the target's runtime box grown by
the existing 50 m near-target pad, plus - where it says so - that box's own longest axis, ties
falling to the lowest axis index. No rule knows the target, the case, the firing ship or any
previous benchmark result, and each is defined for an unknown future or modded target.

| candidate | probes | geometric rule |
|---|---:|---|
| `T4` | 4 | the 4 alternating box corners (the current starting geometry, baseline) |
| `T4C` | 4 | the complementary 4 alternating box corners |
| `F6` | 6 | the 6 box face centres (the octahedron inscribed in the box) |
| `C8` | 8 | all 8 box corners |
| `E4L` | 4 | the 4 edge centres of the edges parallel to the box's longest axis |
| `T4F2L` | 6 | the 4 alternating box corners plus the 2 face centres normal to the box's longest axis |

## Development-set startup comparison

`first sample` is the sample count at which the first aim point became confirmed. `moved samples`
counts only the moved-probe continuation the search needs when the fixed starts alone confirm
nothing. `needed found` and the authored column are the **downstream** result of the whole search
at the 28-sample total, shown here as a secondary check that a startup geometry
does not harm discovery - they take no part in choosing the candidate.

| candidate | probes | starts alone confirm | first sample med/p90/worst | moved samples med/p90/worst | startup failures | first-point radius med/worst (m) | needed total | needed found | needed missed | authored missed (diagnostic) |
|---|---:|---:|---|---|---:|---|---:|---:|---:|---:|
| `T4` | 4 | 57% | 6 / 8 / 10 | 3 / 5 / 6 | 0 | 0.00108 / 0.22 | 175 | 175 | 0 | 0 |
| `T4C` | 4 | 57% | 6 / 8 / 9 | 3 / 4 / 5 | 0 | 0.00109 / 0.134 | 175 | 175 | 0 | 0 |
| `F6` | 6 | 100% | 8 / 14 / 16 | 0 / 0 / 0 | 0 | 0.000549 / 0.00574 | 175 | 160 | 15 | 39 |
| `C8` | 8 | 100% | 10 / 12 / 12 | 0 / 0 / 0 | 0 | 0.00104 / 0.00825 | 175 | 166 | 9 | 27 |
| `E4L` | 4 | 64% | 6 / 7 / 7 | 3 / 3 / 3 | 0 | 0.00089 / 0.00814 | 175 | 175 | 0 | 3 |
| `T4F2L` | 6 | 89% | 8 / 10 / 11 | 5 / 5 / 5 | 0 | 0.00105 / 0.124 | 175 | 175 | 0 | 0 |

### Later-position choice accuracy on the development set

Denominator: the legal aimed muzzle positions, kept apart from aim-point discovery above.

| candidate | correct | wrong | UNKNOWN | invented | merged | duplicate | samples used | samples left after the last point was confirmed, med/worst |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| `T4` | 86506 | 0 | 53 | 0 | 0 | 0 | 1144 | 20 / 20 |
| `T4C` | 86513 | 0 | 46 | 0 | 0 | 0 | 1144 | 20 / 20 |
| `F6` | 77654 | 8873 | 32 | 0 | 0 | 0 | 1144 | 18 / 18 |
| `C8` | 82992 | 3524 | 43 | 0 | 0 | 0 | 1144 | 16 / 16 |
| `E4L` | 86396 | 0 | 163 | 0 | 0 | 0 | 1149 | 20 / 20 |
| `T4F2L` | 86510 | 0 | 49 | 0 | 0 | 0 | 1144 | 18 / 18 |

## The selected candidate

**Selection rule, fixed before the run:** drop any candidate that fails to confirm a first point
anywhere on the development set, then order by worst samples to the first confirmed point, then
p90, then median, then the number of fixed starting probes, then name. Robust worst case first,
typical cost next, simplest arrangement last. How many aim points a candidate happens to discover
during startup takes no part in it.

Selected: **`E4L`** - the 4 edge centres of the edges parallel to the box's longest axis.

Against the `T4` baseline on the development set: first confirmed point at
6 / 7 / 7 samples med/p90/worst against
6 / 8 / 10; the fixed starts alone confirm
it in 64% of entries against 57%;
0 startup failures against 0; needed aim points missed downstream
0 against 0, wrong later-position choices 0 against
0.

## Holdout

The choice above was frozen before anything on the holdout was run, and only the selected
candidate and the `T4` baseline were run there. Nothing was tuned against it. Same near-target-only
search, same 28-sample total - the smallest budget A7.2c already established as
SAFE on the focused population, so this measures whether the starting geometry harms discovery
rather than re-running the budget experiment.

| | `T4` | `E4L` |
|---|---:|---:|
| fixed starting probes | 4 | 4 |
| entries where the fixed starts alone confirm the first point | 26 of 41 | 31 of 41 |
| samples to the first confirmed point, med/p90/worst | 6/7/7 | 6/7/7 |
| moved-probe samples before the first confirmation, med/p90/worst | 3/3/3 | 3/3/3 |
| startup failures | 0 | 0 |
| first-point radius, med/worst (m) | 0.0011/0.00795 | 0.000877/0.00391 |
| needed aim points total | 151 | 151 |
| needed aim points found | 151 | 151 |
| needed aim points missed | 0 | 0 |
| wrong later-position choices | 0 | 0 |
| correct later-position choices | 73205 | 73195 |
| UNKNOWN later-position results | 5 | 15 |
| invented points | 0 | 0 |
| merged points | 0 | 0 |
| duplicate points | 0 | 0 |
| total samples used | 1066 | 1066 |
| samples left after the last point was confirmed, med/worst | 20/20 | 20/20 |
| authored aim points never found (diagnostic only) | 0 | 0 |

## What this decides

**Is there a simple generic starting geometry that establishes the first aim point faster and
more reliably than the current 4 alternating corners, without reducing recovery of the aim points
the firing ship actually needs?**

Partly. `E4L` never reaches the first confirmed point later than `T4` on any entry on either
side of the split - 10 of 44 development entries sooner and 0 later, 5 of
41 holdout entries sooner and 0 later. Every one of those entries is an L or XL
target authoring 2 or 4 aim points, where the 4 alternating corners need the moved-probe
continuation and the 4 long-axis edge centres do not.

But the win barely shows in the holdout summary: both geometries read
6 / 7 / 7 samples to
the first confirmed point, median / p90 / worst. The holdout's 5 wins are all 7 samples down to
6, too small to move any of those three figures. The large development margin
(10 worst against 7) came entirely from the XL four-point
geometries where `T4` costs 8 to 10 samples, and the alphabetical split put all of those on the
development side. The holdout contains no target of that shape, so the part of the advantage the
selection rule actually acted on was never tested outside the set it was chosen on.

What the holdout does confirm: `E4L` confirms the first point from its fixed starts alone more
often (31 of 41 entries against 26 of
41) and locates it more tightly (0.00391 m worst radius against
0.00795 m).

Safety is unchanged: on the holdout both geometries find every needed aim point, make no
wrong later-position choice, and invent, merge and duplicate nothing.
The one measured cost is UNKNOWN: `E4L` returns 15 against
5 on the holdout and 163 against 53 on the
development set, concentrated in 3 entries of 85 where a first point
located on fewer independent starting directions leaves two estimates too wide to separate
everywhere. UNKNOWN is safe, but it is a loss, and it is the only measurement that runs against
the candidate.

**The evidence does not support replacing the current four starting corners.** The candidate's
decisive advantage was never tested on the population it was not chosen on, it costs a little more
UNKNOWN on both, and it changes nothing the search needs at this total: needed aim points found
and wrong later-position choices are identical everywhere. The two larger arrangements are worse
than either - `F6` and `C8` confirm the first point later despite their extra fixed probes, and
at the same total they lose needed aim points downstream, because probes spent before the
adaptive search can steer them are probes the adaptive search no longer has. A7.3 should run on
the unchanged `T4` starts.

Worth recording for later: the entries `E4L` wins are exactly the L and XL multi-aim-point
targets, which is also where the near-target-only search has the least room left at the tested
total. If a future experiment needs startup cost back on those geometries specifically, the
long-axis edge centres are where it was found - but that would be a targeted change on a known
class, not the generic improvement this task looked for.

This measures starting geometry only. It chooses no production sample budget, changes no
production code, alters nothing about the adaptive near-target search, and adds no new stopping
rule.

## Per entry, development set

| entry | set | target | authored | needed | `T4` first / samples / needed missed | `T4C` first / samples / needed missed | `F6` first / samples / needed missed | `C8` first / samples / needed missed | `E4L` first / samples / needed missed | `T4F2L` first / samples / needed missed |
|---|---|---|---:|---:|---|---|---|---|---|---|
| 3472 | broad | `engine_arg_l_allround_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 3664 | broad | `engine_par_l_travel_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 3856 | broad | `engine_tel_l_allround_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 4048 | broad | `engine_ter_xl_travel_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 4168 | broad | `engine_xen_xl_mothership_01_allround_mk1` | 4 | 3 | 9 / 26 / 0 | 8 / 26 / 0 | 14 / 26 / 0 | 10 / 26 / 0 | 7 / 26 / 0 | 11 / 26 / 0 |
| 4360 | broad | `shield_bor_l_standard_01_mk3` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 4552 | broad | `shield_kha_m_standard_03_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 4744 | broad | `shield_spl_m_standard_02_mk2` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 4936 | broad | `shield_ter_m_standard_02_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 5128 | broad | `shield_xen_l_standard_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 5320 | broad | `shield_xen_xl_standard_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 5392 | broad | `ship_arg_xl_carrier_02` | 4 | 3 | 7 / 26 / 0 | 8 / 26 / 0 | 8 / 26 / 3 | 10 / 26 / 3 | 7 / 26 / 0 | 8 / 26 / 0 |
| 5560 | broad | `ship_arg_xs_pv_04_a` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 5704 | broad | `ship_bor_l_miner_liquid_01` | 2 | 3 | 7 / 26 / 0 | 7 / 26 / 0 | 8 / 26 / 0 | 12 / 26 / 0 | 6 / 26 / 0 | 10 / 26 / 0 |
| 5776 | broad | `ship_gen_s_fightingdrone_01` | 3 | 5 | 7 / 26 / 0 | 7 / 26 / 0 | 8 / 26 / 0 | 12 / 26 / 0 | 7 / 26 / 0 | 8 / 26 / 0 |
| 5848 | broad | `ship_par_xs_police_01_a` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 5992 | broad | `ship_pir_s_heavyfighter_01` | 2 | 3 | 7 / 26 / 0 | 7 / 26 / 0 | 10 / 26 / 0 | 12 / 26 / 0 | 7 / 26 / 0 | 10 / 26 / 0 |
| 6160 | broad | `ship_spl_xs_pv_03_a` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 6256 | broad | `ship_tel_l_destroyer_02` | 2 | 3 | 7 / 26 / 0 | 7 / 26 / 0 | 8 / 26 / 0 | 12 / 26 / 0 | 6 / 26 / 0 | 10 / 26 / 0 |
| 6304 | broad | `ship_tel_l_miner_solid_02` | 2 | 3 | 7 / 26 / 0 | 7 / 26 / 0 | 8 / 26 / 0 | 12 / 26 / 0 | 6 / 26 / 0 | 10 / 26 / 0 |
| 6376 | broad | `ship_tel_xs_pv_02_b` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 6424 | broad | `ship_ter_xl_resupplier_01` | 3 | 3 | 7 / 26 / 0 | 7 / 26 / 0 | 8 / 26 / 3 | 12 / 26 / 0 | 7 / 26 / 0 | 10 / 26 / 0 |
| 6616 | broad | `turret_arg_l_guided_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 6808 | broad | `turret_arg_m_guided_02_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 7000 | broad | `turret_bor_l_mining_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 7192 | broad | `turret_par_l_beam_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 7384 | broad | `turret_par_m_gatling_02_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 7576 | broad | `turret_spl_l_beam_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 7768 | broad | `turret_spl_m_flak_02_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 7960 | broad | `turret_tel_l_dumbfire_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 8152 | broad | `turret_tel_m_guided_02_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 8344 | broad | `turret_ter_l_guided_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 8536 | broad | `turret_ter_m_laser_04_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 6 / 26 / 0 | 8 / 26 / 0 |
| 12155 | hard | `engine_xen_xl_mothership_01_allround_mk1` | 4 | 6 | 7 / 26 / 0 | 8 / 26 / 0 | 14 / 26 / 0 | 10 / 26 / 0 | 7 / 26 / 0 | 9 / 26 / 0 |
| 12157 | hard | `engine_xen_xl_mothership_01_allround_mk1` | 4 | 6 | 10 / 26 / 0 | 7 / 26 / 0 | 16 / 26 / 3 | 10 / 26 / 0 | 7 / 26 / 0 | 11 / 26 / 0 |
| 12160 | hard | `engine_xen_xl_mothership_01_allround_mk1` | 4 | 9 | 9 / 26 / 0 | 8 / 26 / 0 | 14 / 26 / 0 | 10 / 26 / 3 | 7 / 26 / 0 | 11 / 26 / 0 |
| 12163 | hard | `engine_xen_xl_mothership_01_allround_mk1` | 4 | 6 | 9 / 26 / 0 | 9 / 26 / 0 | 14 / 26 / 3 | 10 / 26 / 3 | 7 / 26 / 0 | 11 / 26 / 0 |
| 12196 | hard | `ship_arg_xl_carrier_02` | 4 | 6 | 8 / 26 / 0 | 8 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 7 / 28 / 0 | 8 / 26 / 0 |
| 12197 | hard | `ship_arg_xl_carrier_02` | 4 | 6 | 8 / 26 / 0 | 8 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 7 / 28 / 0 | 8 / 26 / 0 |
| 12199 | hard | `ship_arg_xl_carrier_02` | 4 | 8 | 8 / 26 / 0 | 7 / 26 / 0 | 8 / 26 / 0 | 10 / 26 / 0 | 7 / 27 / 0 | 8 / 26 / 0 |
| 12234 | hard | `ship_gen_s_fightingdrone_01` | 3 | 6 | 7 / 26 / 0 | 7 / 26 / 0 | 8 / 26 / 0 | 12 / 26 / 0 | 7 / 26 / 0 | 8 / 26 / 0 |
| 12376 | hard | `ship_ter_xl_resupplier_01` | 3 | 9 | 7 / 26 / 0 | 7 / 26 / 0 | 8 / 26 / 3 | 12 / 26 / 0 | 7 / 26 / 0 | 10 / 26 / 0 |
| 12388 | hard | `ship_ter_xl_resupplier_01` | 3 | 6 | 7 / 26 / 0 | 7 / 26 / 0 | 8 / 26 / 0 | 12 / 26 / 0 | 7 / 26 / 0 | 10 / 26 / 0 |
| 12390 | hard | `ship_ter_xl_resupplier_01` | 3 | 6 | 7 / 26 / 0 | 7 / 26 / 0 | 8 / 26 / 0 | 12 / 26 / 0 | 7 / 26 / 0 | 10 / 26 / 0 |

## Per entry, holdout

| entry | target | authored | needed | `T4` first / samples / needed missed | `E4L` first / samples / needed missed |
|---|---|---:|---:|---|---|
| 3568 | `engine_bor_l_travel_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 3760 | `engine_spl_l_allround_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 3952 | `engine_ter_l_allround_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 4144 | `engine_xen_xl_allround_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 4264 | `shield_arg_m_standard_02_mk2` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 4456 | `shield_bor_xl_standard_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 4648 | `shield_pir_xl_battleship_01_standard_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 4840 | `shield_ter_l_standard_01_mk3` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 5032 | `shield_ter_m_standard_04_mk2` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 5224 | `shield_xen_m_standard_02_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 5368 | `ship_arg_l_destroyer_02` | 3 | 3 | 7 / 26 / 0 | 7 / 26 / 0 |
| 5464 | `ship_arg_xs_pv_01_b` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 5656 | `ship_arg_xs_pv_05_c` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 5728 | `ship_bor_l_miner_solid_01` | 2 | 3 | 7 / 26 / 0 | 6 / 26 / 0 |
| 5824 | `ship_par_l_expeditionary_01` | 2 | 3 | 7 / 26 / 0 | 6 / 26 / 0 |
| 5944 | `ship_par_xs_pv_04_a` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 6064 | `ship_spl_xs_police_01_a` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 6232 | `ship_tel_l_destroyer_01` | 2 | 3 | 7 / 26 / 0 | 6 / 26 / 0 |
| 6280 | `ship_tel_l_miner_liquid_02` | 2 | 3 | 7 / 26 / 0 | 6 / 26 / 0 |
| 6328 | `ship_tel_l_trans_container_03` | 2 | 3 | 7 / 26 / 0 | 6 / 26 / 0 |
| 6400 | `ship_ter_xl_carrier_01` | 3 | 3 | 7 / 26 / 0 | 7 / 26 / 0 |
| 6520 | `ship_xen_xs_pv_03_a` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 6712 | `turret_arg_m_beam_02_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 6904 | `turret_arg_m_shotgun_02_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 7096 | `turret_bor_m_laser_02_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 7288 | `turret_par_l_mining_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 7480 | `turret_par_m_plasma_02_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 7672 | `turret_spl_l_mining_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 7864 | `turret_spl_m_mining_02_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 8056 | `turret_tel_l_plasma_01_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 8248 | `turret_tel_m_shotgun_02_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 8440 | `turret_ter_m_dumbfire_02_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 8632 | `turret_xen_m_gatling_02_mk1` | 1 | 3 | 6 / 26 / 0 | 6 / 26 / 0 |
| 12169 | `ship_arg_l_destroyer_02` | 3 | 7 | 7 / 26 / 0 | 7 / 26 / 0 |
| 12177 | `ship_arg_l_destroyer_02` | 3 | 9 | 7 / 26 / 0 | 7 / 26 / 0 |
| 12360 | `ship_ter_xl_carrier_01` | 3 | 6 | 7 / 26 / 0 | 7 / 26 / 0 |
| 12362 | `ship_ter_xl_carrier_01` | 3 | 6 | 7 / 26 / 0 | 7 / 26 / 0 |
| 12365 | `ship_ter_xl_carrier_01` | 3 | 6 | 7 / 26 / 0 | 7 / 26 / 0 |
| 12366 | `ship_ter_xl_carrier_01` | 3 | 6 | 7 / 26 / 0 | 7 / 26 / 0 |
| 12368 | `ship_ter_xl_carrier_01` | 3 | 6 | 7 / 26 / 0 | 7 / 26 / 0 |
| 12369 | `ship_ter_xl_carrier_01` | 3 | 6 | 7 / 26 / 0 | 7 / 26 / 0 |
