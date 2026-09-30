# A6: near-target angular probing

Offline research, status **inference**. No X4 launch, no production change.
Two experiments over the same run: probe placement, then post-hoc refinement of
the points those probes found.

First question:

> Does the existing A4.3 angular-spread search work substantially better when
> its adaptive probes are placed near the target instead of around the firing
> ship?

Run with `python3 research/issue184/aimpoint_map.py --a6-near`.

## What changed

Only where the adaptive angular probes may be placed. `angular_probe` gained a
`near_target` pad; with it, `angular_pick` chooses candidates on the six faces
of the **target's runtime box grown by 50 m on every side**, in the target
frame, instead of on the class-expanded firing-ship box.

Everything else is the A4.3 phase 5 method unchanged: the same 8 outer firing
corners and the same accepted cheap rescue precede the angular stage, the same
`_definite`/`nearest` candidate rule, the same point confirmation, the same
`A43A_PRIMARY = 12` primary asks and the same `A43A_GUARD = 24` hard limit on
the angular stage's extra asks. No mechanical adjustment was needed.

The 50 m pad is a **probe-placement choice only**. It is not evidence that all
possible aim points lie inside that box. Current turret and muzzle positions
were not used to choose probes. Hidden aim points and later muzzle positions
are reporting truth only and never steered the search or the stopping.

## Cases

The 19 A4.3 hard boundary geometries (`A43_CASES`) reproduced at **100 m, 1 km
and 8 km**: 57 cases, 19 per distance. 20 km and 100 km are not meaningful
turret firing ranges for this purpose and were not tested.

`A43_CASES` is a hidden-truth-filtered subset of the boundary group, not a
generator, so `a6_near_variants` rebuilds each case at the other distances rather
than testing unrelated cases. Same target, same nearest-aim-point-pair
bisector bearing, same mount, turret and all three rotations; only the
along-bearing standoff changes. The ship is translated along its own bearing
by the gap difference, exactly as `cases` does when it builds the 100 m and
1 km members of the existing pair. The three distances are therefore the same
geometry at three ranges.

## Result

64 later aimed muzzles and 64 authored aim points per distance.

| method | gap | cases | asks med/p90/max | angular extra med/max | pts found | all needed exposed | all authored exposed | guard | wrong |
|---|---:|---:|---|---|---:|---:|---:|---:|---:|
| near | 100 m | 19 | 29 / 33 / 33 | 16 / 20 | 64 | 19 | 19 | 0 | 0 |
| near | 1 km | 19 | 29 / 33 / 35 | 16 / 22 | 64 | 19 | 19 | 0 | 0 |
| near | 8 km | 19 | 29 / 34 / 34 | 16 / 22 | 62 | 19 | 17 | 1 | 0 |
| firing | 100 m | 19 | 25 / 28 / 32 | 12 / 16 | 48 | 19 | 8 | 0 | 0 |
| firing | 1 km | 19 | 25 / 28 / 32 | 12 / 16 | 48 | 19 | 8 | 0 | 0 |
| firing | 8 km | 19 | 25 / 28 / 33 | 12 / 17 | 47 | 19 | 7 | 0 | 0 |

**1. Every needed aim point was exposed, by both methods, at all three
distances.** 0 of 57 cases ended with a needed point missing. The corners plus
the cheap rescue alone left 2 needed points missing at 100 m and 1 at each of
1 km and 8 km; the angular stage recovered all of them either way.

**2. Asks before the last needed point was exposed** (corners + rescue +
angular, all 19 cases at each distance):

| method | 100 m | 1 km | 8 km |
|---|---|---|---|
| near | 13 / 17.8 / 24 | 13 / 16 / 24 | 13 / 16 / 19 |
| firing | 13 / 17 / 19 | 13 / 16 / 19 | 13 / 16 / 17 |

med / p90 / max. The medians are identical; near-target costs a few asks more
in the tail (max 24 vs 19, cases 12376 at 100 m and 1 km).

**3. Largest remaining angular gap before each primary ask (degrees), the
important structural difference:**

| method | 100 m | 1 km | 8 km |
|---|---|---|---|
| near | 88.9 / 166 / 179 | 89.3 / 170 / 180 | 89.5 / 176 / 180 |
| firing | 17.3 / 38.9 / 86.8 | 14.6 / 25.4 / 51.1 | 5.45 / 9.31 / 19.2 |

med / p90 / max. **The near-target gap distribution is essentially identical
at all three ranges; the firing-box one collapses as range grows** — its
median falls 17.3° → 5.45° over the same geometry, purely because a distant
firing box subtends a smaller angle at the target. This is the clearest
evidence in the run: any threshold on the firing-box angular gap is a
range-dependent quantity measuring the firing box, whereas the near-target gap
measures the target. Choosing that threshold is deliberately left to later
work; the full per-ask trace is kept in `a6_near_rows.jsonl` so a rule can be
evaluated without rerunning.

**4. Distinct aim points confirmed:** near-target 64 / 64 / 62 of 64 authored,
firing box 48 / 48 / 47. No invented, merged or duplicate points in any of the
114 runs.

**5. No definite answer became wrong.** 0 wrong at every distance for both
methods. The correct/UNKNOWN split is identical between the two methods and
degrades with range for both: 33/31, 22/42, 3/61 correct/UNKNOWN at 100 m,
1 km and 8 km. Per-case, the UNKNOWN counts of the two methods are equal in
all 57 cases.

That is worth stating plainly: **near-target probing improves discovery, not
answer definiteness.** These are boundary geometries, so the muzzle sits on
the switching plane of the target's closest aim-point pair, and `nearest`
stays indefinite there no matter how many *other* points the search found. The
range dependence of the answer rate is a `nearest` definiteness effect, not a
discovery effect, and the probe-placement experiment does not address it. The
refinement experiment below does.

**6. The 24-ask hard limit** was hit once in 114 runs: case 12234 at 8 km,
near-target. It still exposed every needed point and every authored point. The
firing-box method never hit it.

**7. 100 m vs 1 km vs 8 km.** For near-target probing, 100 m and 1 km are
indistinguishable — same points found (64), same guard count (0), same
authored coverage (19 of 19 cases), same ask distribution. 8 km is slightly
worse: 62 points, 17 of 19 cases complete, one guard hit. For the firing box,
all three distances find far fewer points, and the degradation from 100 m to
8 km is small only because the method was already missing a third of the
authored points at 100 m.

**Stronger diagnostic — authored aim points never exposed** (reporting truth
only, never consulted by the search):

| method | 100 m | 1 km | 8 km |
|---|---|---|---|
| near | 0 of 64, in 0 cases | 0 of 64, in 0 cases | 2 of 64, in 2 cases |
| firing | 16 of 64, in 11 cases | 16 of 64, in 11 cases | 17 of 64, in 12 cases |

This is the result the muzzle-based pass/fail hides. Both methods expose every
point the existing hidden benchmark muzzles happen to select, so on that
measure they tie 19–19 everywhere. On complete discovery they do not: the
firing-box search leaves an authored point undiscovered in 11 or 12 of 19
cases at every range, the near-target search in 0, 0 and 2. The two undiscovered
cases at 8 km are 12163 (point 3) and 12366 (point 2).

## Answer

Yes. Near-target probing is substantially better at discovery — 64 of 64
authored points against 48 at short and medium range — for a median of 4 extra
asks, no wrong answers and one guard hit in 114 runs. Its per-ask angular gap
is range-independent over 100 m to 8 km while the firing-box one collapses by
3x, so discovery under near-target probing is largely independent of firing
range in the way the firing-box search is not.

Two limits this experiment does **not** establish:

- 8 km is not quite free: 2 authored points and 1 guard hit appear there and
  at no shorter range. Whether that is the range or those two geometries is
  not settled by 19 cases.
- Answer definiteness is untouched. Every UNKNOWN in the firing-box run is
  still UNKNOWN in the near-target run. Discovery was the question asked here;
  the `nearest` boundary problem is taken up by the refinement experiment below.

No stopping rule is chosen here. [A6_ANGULAR_STOP.md](A6_ANGULAR_STOP.md)
shows only that one threshold could not both avoid premature stopping and make
every case stop inside the fixed 12-primary trace. It does not reject a smaller
threshold combined with the 24-ask hard limit. This experiment changes what the
gap measures by moving the adaptive probes near the target.

## Post-hoc point refinement from the same observations

Second experiment, same run, one question:

> Can the near-target probe lines already collected locate the discovered aim
> points more precisely, with no additional X4 asks, so later turret positions
> produce fewer UNKNOWN answers without introducing wrong answers?

### Method

The A6 near-target search is unchanged: same corner asks, same cheap rescue,
same near-target probe positions, same 50 m target-box pad, same 12 primary
asks, same 24-ask angular-stage limit, same 19 geometries at 100 m, 1 km and
8 km, same probe order and same total ask count. Refinement runs **after** the
search has finished and never feeds back into probe placement, so the baseline
and refined estimates are computed from byte-identical observations.

`refine_points` assigns each collected ray to a point when the ray passes
through exactly one current estimate's ball — the ownership rule `_search`
already uses. For a point with two or more assigned rays, the tightest pairwise
crossing under the unchanged `crossing` rule (with its miss allowance, forward
check and poor-angle rejection) becomes a candidate, given the same radius
formula `_search.locate` uses. It replaces the estimate only when all three
hold:

1. it is strictly tighter;
2. its whole ball lies inside the original ball;
3. every assigned ray still passes through it.

Condition 2 is what preserves identity. A refined estimate is a subset of the
one it replaces, so it cannot drift onto a neighbouring aim point or grow to
swallow two, and no estimate is ever added or dropped. Point *confirmation* is
untouched: refinement only tightens points the current conservative rules had
already confirmed, never promotes weaker evidence into a new point. This is the
reason the old `mapper.py` `shrink()` idea is safe here and was not safe there —
`shrink()` re-centred a point on whatever pair crossed most tightly, with only
an "all assigned rays still hit" check and no containment, so a refined ball
could move off its own point.

Hidden authored aim points and hidden aimed muzzle positions are used for
scoring and for the error column only.

### Result

Near-target runs, 64 authored points and 64 later aimed muzzles per distance,
b = baseline, a = refined.

| gap | pts | refined | correct b/a | wrong b/a | UNKNOWN b/a | radius med/max b → a (m) | error med/max b → a (m) |
|---|---:|---:|---|---|---|---|---|
| 100 m | 64 | 60 | 33 / 58 | 0 / 0 | 31 / 6 | 0.0576 / 0.531 → 0.00245 / 0.117 | 0.00797 / 0.236 → 0.000349 / 0.0409 |
| 1 km | 64 | 59 | 22 / 58 | 0 / 0 | 42 / 6 | 0.0841 / 0.700 → 0.00234 / 0.113 | 0.0120 / 0.225 → 0.000402 / 0.0522 |
| 8 km | 62 | 60 | 3 / 51 | 0 / 0 | 61 / 13 | 0.326 / 3.39 → 0.00244 / 0.246 | 0.0406 / 0.879 → 0.000360 / 0.0156 |

- **Total X4 asks are identical**, case by case: 29 / 33 / 33 at 100 m, 29 /
  33 / 35 at 1 km, 29 / 34 / 34 at 8 km (med / p90 / max), the same numbers as
  the baseline table above. Refinement spends no asks.
- **No wrong answer appeared at any distance.** No case lost a correct answer
  either: refined `correct` is never below baseline `correct` in any of the 57
  cases.
- **UNKNOWN falls by 81 %, 86 % and 79 %** at 100 m, 1 km and 8 km. These are
  boundary geometries, where the muzzle sits on the switching plane of the
  target's closest aim-point pair, so `nearest` was indefinite purely because
  the two estimates' radii overlapped the decision. Tighter radii separate
  them.
- **Point identity is unchanged in all 57 cases.** 0 estimates changed which
  authored point they cover, 0 invented, 0 merged, 0 duplicate. `missed` is 2
  at 8 km before and after — the same two points the search never discovered
  (12163 point 3, 12366 point 2); refinement neither recovers nor loses a
  point.
- **179 of 190 points were refined** (60 / 59 / 60). The 11 that were not all
  failed the same check: the tightest available crossing was not strictly
  inside the current ball, so the candidate was discarded and the original
  conservative estimate kept. Every case refined at least one point.

**The range dependence of answer definiteness largely disappears.** Baseline
correct answers collapse with range, 33 → 22 → 3, because the conditioning
limit scales point radius with distance. After refinement they are 58 / 58 /
51. The remaining 8 km shortfall is the two undiscovered points plus their
cases' boundary muzzles, not the precision of what was found.

### Answer

Yes. Refinement from already-collected probe lines is the cheapest improvement
found in A6 so far: zero extra asks, a 20–110× reduction in point-position
error, a 25–130× reduction in reported uncertainty, 79–86 % fewer UNKNOWN
answers, and no wrong answer, no identity change, no invented, merged or
duplicate point at any distance.

Two limits this does **not** establish:

- It is scored on 19 boundary geometries only. Boundary cases are exactly where
  overlapping radii dominate UNKNOWN, so this is the group refinement should
  help most; the gain on ordinary geometries is untested here.
- Containment is a sufficient safety condition, not a proven-optimal one. The
  11 unrefined points show it does reject usable-looking candidates; whether a
  weaker condition is still sound was not tested, and weakening point
  confirmation to chase smaller radii remains rejected.
