# Issue #184 A7.2: the production stopping rule, cost bound and definite/UNKNOWN rule

Offline research, status **inference**. No X4 launch, no production change. Discovery is unchanged
from A7.1 - the same 8 outer firing corners, the same cheap rescue, the same near-target probe
placement on the target runtime box + 50 m, the same point confirmation, the same
`refine_points` containment rule, and the same 126 focused cases. A7.2 adds nothing to discovery.
It fixes when the search stops, what it may spend, and when a later turret position may be given a
definite aim point.

Run with `python3 research/issue184/aimpoint_map.py --a72`.

## The stopping rule

A7.1 tested every observable the search already computes - the largest remaining viewing-angle gap
and the number of consecutive asks that confirmed nothing new - over all 126 completed traces, and
no setting of either was both safe and cheaper than running to the limit. So **there is no early
stop**. The search continues while a valid next probe exists and ends at the **first** of:

- **S1, no valid next probe.** `angular_pick` returns nothing (no confirmed point is definitely the
  nearest known point anywhere on the probe box), or the position it picks has already been asked,
  or no point is confirmed at all. Nothing further can be observed by this placement rule.
- **S2, the angular stage is out of budget.** Fewer than 3 of its questions remain: one probe plus
  the two its along-ray confirmation may need. The moved-ask rescue of an unassigned probe draws on
  the same angular budget and keeps the same 3-question reserve.
- **S3, the whole search is out of budget.** Fewer than 3 of the total remain.

The old 12-primary-ask stop is dropped: it is not one of these three, it counts only
probes and not the confirmation and rescue questions they trigger, and A7.1 produced no evidence
for 12 as a boundary. Cases here spend 8-22 primary asks before S1 or S2 fires.

## The cost contract

One X4 question is one aim-point query at one probe position.

| stage | what it spends questions on | maximum |
|---|---|---:|
| initial | the 8 outer corners of the firing box, then 2 per along-ray confirmation attempt | 16 |
| cheap rescue | one moved ask per unassigned corner direction, plus the confirmations those trigger | 24 |
| near-target angular | one probe per chosen viewing direction, the moved-ask rescue of a probe that cannot be assigned, and 2 per confirmation attempt | 24 |
| **whole search** | | **64** |

Confirmation is not free and is not separately budgeted: `locate` spends exactly 2 questions per
candidate it tests, and they are charged to the stage that triggered them. That is why 8 starting
corners are not 8 questions - over the 126 cases the initial stage cost 10-12. The total is the sum of the
three ceilings, not a number tuned to this population.

| stage | measured min / med / max over the 126 cases |
|---|---|
| initial | 10 / 10 / 12 |
| cheap rescue | 0 / 0 / 7 |
| angular | 22 / 22 / 23 |
| total | 32 / 34 / 39 |

126 of 126 cases ended on S2, 0 on S1, none on S3. The angular ceiling is the binding one and
it is the smallest safe value this population supports: A7.1's earliest state as safe and useful
as the full result needed up to 23 angular-stage questions, so 24 is one question of
headroom over the worst case measured, not an inherited default.

## The definite-answer rule

**A later turret position gets a definite aim point when both hold, and UNKNOWN otherwise:**

1. the search confirmed at least one point, and
2. `nearest` is definite over the refined confirmed points: the winner's far bound is strictly
   nearer than every rival's near bound.

The rule does not depend on why the search stopped. **S1 means** the probe placement rule has
nothing left to look at, not that every aim point is found. **S2/S3 mean** the cost bound was
reached, which says nothing about completeness at all. Neither is proof of discovery, and the
rule claims none.

### Why no completeness condition is added

`nearest` alone cannot show that an *undiscovered* point would not have won, so the obvious
addition is the completeness guard `target_box_map` already uses: keep the answer definite only
where every region of the padded target box the empty balls have not cleared is farther away than
the winner's far bound. It costs no X4 question. It was measured on the retained search's own
final states and **it never answers**:

| residual resolution | definite answers left | wrong | residual fraction of the padded box med/max |
|---:|---:|---:|---|
| GEO_DEPTH 4 | 0 of 120128 | 0 | 0.0066 / 0.3604 |
| GEO_DEPTH 8 | 0 of 120128 | 0 | 0.0000 / 0.2713 |

That is geometry, not resolution. Probing from outside the target can never empty the space
immediately around a confirmed point: every empty ball an ask assigned to point `w` proves has
`w` on its boundary, so a hypothetical point just beyond `w` from every probe direction is never
excluded, and it would beat `w` at some later turret position. Raising the resolution does not
close it and the target's size does not matter: on case 12155 at 100 m (a 496 x 505 x 139 m box,
27 empty balls) the residual fraction only falls 0.0366 -> 0.0043 -> 0.0017 -> 0.0013 from
GEO_DEPTH 4 to 10, and on case 5776 at 100 m (10 x 12 x 14 m, 29 balls) 0.0093 -> 0.0018 ->
0.0008 -> 0.0006, with 0 definite answers at every one of those resolutions in both, against 252
and 2,460 that `nearest` answers definitely. GEO_DEPTH 12 exhausts memory. A guard that always
returns UNKNOWN is not a safety rule, it is the absence of an answer, so the retained rule is
`nearest` alone and the residual risk is carried by the stopping rule and stated below.

## Evidence

Every state of every case is scored under the retained rule, not only the final state, so the
state an earlier stop would have landed in is judged too.

| group | cases | states | correct | wrong | UNKNOWN | states with a wrong answer |
|---|---:|---:|---:|---:|---:|---:|
| hard | 57 | 1077 | 1339559 | 14424 | 14168 | 38 |
| ordinary | 69 | 1345 | 915193 | 0 | 5781 | 0 |
| all | 126 | 2422 | 2254752 | 14424 | 19949 | 38 |

Every definite wrong answer in the whole population sits in an early prefix of 7 case
instances, where only part of the target's points is confirmed and `nearest` names a known point
confidently because the point that actually wins is not in the set yet. The retained stopping rule
never ends there, and the margin is what the rule rests on:

| case | gap (m) | last angular ask with a wrong answer | angular asks spent | margin | final wrong |
|---|---:|---:|---:|---:|---:|
| 12160 | 100 | 4 | 22 | 18 | 0 |
| 12160 | 1000 | 5 | 22 | 17 | 0 |
| 12160 | 8000 | 3 | 22 | 19 | 0 |
| 12234 | 100 | 4 | 22 | 18 | 0 |
| 12376 | 100 | 6 | 22 | 16 | 0 |
| 12376 | 1000 | 7 | 22 | 15 | 0 |
| 12376 | 8000 | 2 | 22 | 20 | 0 |

Smallest margin over the 7 affected case instances: 15 angular-stage questions.

## What each total limit buys

Each case is replayed to the last state its own trace reaches inside the limit. `needed missing`
counts aim points some later aimed muzzle on that firing ship really selects that the search never
found.

| total limit | cases reaching their full trace | correct | wrong | UNKNOWN | needed missing |
|---:|---:|---:|---:|---:|---:|
| 16 | 0 | 113977 | 2735 | 3416 | 7 |
| 24 | 0 | 119109 | 56 | 963 | 2 |
| 32 | 59 | 120012 | 0 | 116 | 0 |
| 36 | 104 | 120033 | 0 | 95 | 0 |
| 40 | 126 | 120033 | 0 | 95 | 0 |
| 48 | 126 | 120033 | 0 | 95 | 0 |
| 64 | 126 | 120033 | 0 | 95 | 0 |

Every case reaches its own full trace by a total limit of 40, and no limit at or above 32
produces a wrong answer. That does not make 40 the contract: it is this population's worst case,
not a bound, and the contract stays the structural 64, which is the sum of the three
stage ceilings. Cutting the total to 24 or 16 truncates the angular stage and is what actually
costs correctness, which is the same conclusion A7.1 reached about stopping early.

## Limitations that remain for A7.3

- **The rule is evidence, not proof.** No completeness condition is available to a search that
  probes only from outside the target, as measured above, so a definite answer can still be wrong
  if discovery missed the point that wins. Nothing in these 126 cases does, at the chosen stop.
- The margin table is the whole of that safety argument and it comes from one bearing per ordinary
  target. A7.3 must run the broad population under exactly this stopping rule and answer rule and
  report the margin again, and any case whose margin is small or negative is a real failure, not a
  number to tune around.
- The initial stage's ceiling is the first hard limit anything places on confirmation questions.
  It never bound here (max 12), so its behaviour when it does bind is specified, not tested.
- No case reached S3, so the interaction between an exhausted total and the angular stage's own
  reserve is specified, not exercised.
- Targets with zero authored aim points are A7.4; none appear in this corpus.

## Per case

| case | group | gap (m) | asks | initial | rescue | angular | primary | end | worst prefix wrong | final correct | final wrong | final UNKNOWN |
|---|---|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|
| 12155 | hard | 100 | 35 | 10 | 3 | 22 | 14 | S2 | 0 | 252 | 0 | 0 |
| 12155 | hard | 1000 | 35 | 10 | 3 | 22 | 12 | S2 | 0 | 252 | 0 | 0 |
| 12155 | hard | 8000 | 35 | 10 | 3 | 22 | 14 | S2 | 0 | 252 | 0 | 0 |
| 12157 | hard | 100 | 35 | 10 | 3 | 22 | 14 | S2 | 0 | 372 | 0 | 0 |
| 12157 | hard | 1000 | 35 | 10 | 3 | 22 | 14 | S2 | 0 | 396 | 0 | 0 |
| 12157 | hard | 8000 | 35 | 10 | 3 | 22 | 14 | S2 | 0 | 408 | 0 | 0 |
| 12160 | hard | 100 | 39 | 10 | 7 | 22 | 19 | S2 | 28 | 294 | 0 | 0 |
| 12160 | hard | 1000 | 38 | 10 | 6 | 22 | 18 | S2 | 28 | 338 | 0 | 0 |
| 12160 | hard | 8000 | 38 | 10 | 6 | 22 | 18 | S2 | 28 | 484 | 0 | 0 |
| 12163 | hard | 100 | 35 | 10 | 3 | 22 | 14 | S2 | 0 | 332 | 0 | 4 |
| 12163 | hard | 1000 | 35 | 10 | 3 | 22 | 14 | S2 | 0 | 336 | 0 | 0 |
| 12163 | hard | 8000 | 35 | 10 | 3 | 22 | 14 | S2 | 0 | 336 | 0 | 0 |
| 12169 | hard | 100 | 38 | 10 | 6 | 22 | 22 | S2 | 0 | 313 | 0 | 0 |
| 12169 | hard | 1000 | 38 | 10 | 6 | 22 | 22 | S2 | 0 | 337 | 0 | 0 |
| 12169 | hard | 8000 | 38 | 12 | 4 | 22 | 22 | S2 | 0 | 361 | 0 | 0 |
| 12177 | hard | 100 | 38 | 10 | 6 | 22 | 22 | S2 | 0 | 1956 | 0 | 0 |
| 12177 | hard | 1000 | 38 | 10 | 6 | 22 | 22 | S2 | 0 | 2062 | 0 | 0 |
| 12177 | hard | 8000 | 38 | 10 | 6 | 22 | 22 | S2 | 0 | 2076 | 0 | 0 |
| 12196 | hard | 100 | 35 | 10 | 3 | 22 | 14 | S2 | 0 | 1344 | 0 | 0 |
| 12196 | hard | 1000 | 35 | 10 | 3 | 22 | 14 | S2 | 0 | 1344 | 0 | 0 |
| 12196 | hard | 8000 | 35 | 10 | 3 | 22 | 13 | S2 | 0 | 1344 | 0 | 0 |
| 12197 | hard | 100 | 35 | 10 | 3 | 22 | 14 | S2 | 0 | 1436 | 0 | 2 |
| 12197 | hard | 1000 | 35 | 10 | 3 | 22 | 14 | S2 | 0 | 1438 | 0 | 2 |
| 12197 | hard | 8000 | 35 | 10 | 3 | 22 | 13 | S2 | 0 | 1436 | 0 | 4 |
| 12199 | hard | 100 | 38 | 10 | 6 | 22 | 18 | S2 | 0 | 1346 | 0 | 0 |
| 12199 | hard | 1000 | 37 | 12 | 3 | 22 | 18 | S2 | 0 | 1344 | 0 | 0 |
| 12199 | hard | 8000 | 38 | 10 | 6 | 22 | 18 | S2 | 0 | 1344 | 0 | 0 |
| 12234 | hard | 100 | 34 | 12 | 0 | 22 | 18 | S2 | 573 | 1008 | 0 | 0 |
| 12234 | hard | 1000 | 38 | 10 | 6 | 22 | 22 | S2 | 0 | 1008 | 0 | 0 |
| 12234 | hard | 8000 | 34 | 12 | 0 | 22 | 9 | S2 | 0 | 957 | 0 | 51 |
| 12360 | hard | 100 | 38 | 10 | 6 | 22 | 22 | S2 | 0 | 1384 | 0 | 0 |
| 12360 | hard | 1000 | 38 | 10 | 6 | 22 | 22 | S2 | 0 | 1394 | 0 | 0 |
| 12360 | hard | 8000 | 38 | 10 | 6 | 22 | 22 | S2 | 0 | 1470 | 0 | 0 |
| 12362 | hard | 100 | 35 | 10 | 3 | 22 | 18 | S2 | 0 | 1327 | 0 | 0 |
| 12362 | hard | 1000 | 35 | 10 | 3 | 22 | 18 | S2 | 0 | 1327 | 0 | 0 |
| 12362 | hard | 8000 | 35 | 10 | 3 | 22 | 18 | S2 | 0 | 1480 | 0 | 0 |
| 12365 | hard | 100 | 35 | 10 | 3 | 22 | 18 | S2 | 0 | 2139 | 0 | 0 |
| 12365 | hard | 1000 | 35 | 10 | 3 | 22 | 18 | S2 | 0 | 2161 | 0 | 0 |
| 12365 | hard | 8000 | 35 | 10 | 3 | 22 | 18 | S2 | 0 | 2190 | 0 | 0 |
| 12366 | hard | 100 | 35 | 10 | 3 | 22 | 18 | S2 | 0 | 1252 | 0 | 0 |
| 12366 | hard | 1000 | 35 | 10 | 3 | 22 | 18 | S2 | 0 | 1255 | 0 | 0 |
| 12366 | hard | 8000 | 35 | 10 | 3 | 22 | 21 | S2 | 0 | 1298 | 0 | 0 |
| 12368 | hard | 100 | 38 | 10 | 6 | 22 | 22 | S2 | 0 | 1326 | 0 | 0 |
| 12368 | hard | 1000 | 38 | 10 | 6 | 22 | 22 | S2 | 0 | 1345 | 0 | 0 |
| 12368 | hard | 8000 | 38 | 10 | 6 | 22 | 22 | S2 | 0 | 1421 | 0 | 5 |
| 12369 | hard | 100 | 38 | 10 | 6 | 22 | 22 | S2 | 0 | 2133 | 0 | 0 |
| 12369 | hard | 1000 | 38 | 10 | 6 | 22 | 22 | S2 | 0 | 2179 | 0 | 0 |
| 12369 | hard | 8000 | 38 | 10 | 6 | 22 | 22 | S2 | 0 | 2261 | 0 | 0 |
| 12376 | hard | 100 | 34 | 12 | 0 | 22 | 17 | S2 | 495 | 1829 | 0 | 9 |
| 12376 | hard | 1000 | 34 | 12 | 0 | 22 | 18 | S2 | 585 | 1958 | 0 | 9 |
| 12376 | hard | 8000 | 34 | 12 | 0 | 22 | 18 | S2 | 998 | 2124 | 0 | 9 |
| 12388 | hard | 100 | 35 | 10 | 3 | 22 | 18 | S2 | 0 | 1226 | 0 | 0 |
| 12388 | hard | 1000 | 35 | 10 | 3 | 22 | 18 | S2 | 0 | 1300 | 0 | 0 |
| 12388 | hard | 8000 | 35 | 10 | 3 | 22 | 18 | S2 | 0 | 1392 | 0 | 0 |
| 12390 | hard | 100 | 35 | 10 | 3 | 22 | 18 | S2 | 0 | 1364 | 0 | 0 |
| 12390 | hard | 1000 | 35 | 10 | 3 | 22 | 18 | S2 | 0 | 1391 | 0 | 0 |
| 12390 | hard | 8000 | 35 | 10 | 3 | 22 | 18 | S2 | 0 | 1536 | 0 | 0 |
| 3568 | ordinary | 100 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 624 | 0 | 0 |
| 3568 | ordinary | 1000 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 624 | 0 | 0 |
| 3568 | ordinary | 8000 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 600 | 0 | 0 |
| 4072 | ordinary | 100 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 228 | 0 | 0 |
| 4072 | ordinary | 1000 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 228 | 0 | 0 |
| 4072 | ordinary | 8000 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 228 | 0 | 0 |
| 4168 | ordinary | 100 | 32 | 10 | 0 | 22 | 9 | S2 | 0 | 1439 | 0 | 0 |
| 4168 | ordinary | 1000 | 33 | 10 | 0 | 23 | 11 | S2 | 0 | 1442 | 0 | 0 |
| 4168 | ordinary | 8000 | 32 | 10 | 0 | 22 | 10 | S2 | 0 | 1447 | 0 | 0 |
| 4432 | ordinary | 100 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 266 | 0 | 0 |
| 4432 | ordinary | 1000 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 266 | 0 | 0 |
| 4432 | ordinary | 8000 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 266 | 0 | 0 |
| 5320 | ordinary | 100 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 280 | 0 | 0 |
| 5320 | ordinary | 1000 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 290 | 0 | 0 |
| 5320 | ordinary | 8000 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 290 | 0 | 0 |
| 5368 | ordinary | 100 | 32 | 10 | 0 | 22 | 14 | S2 | 0 | 705 | 0 | 0 |
| 5368 | ordinary | 1000 | 32 | 10 | 0 | 22 | 14 | S2 | 0 | 705 | 0 | 0 |
| 5368 | ordinary | 8000 | 32 | 10 | 0 | 22 | 14 | S2 | 0 | 705 | 0 | 0 |
| 5392 | ordinary | 100 | 32 | 10 | 0 | 22 | 8 | S2 | 0 | 940 | 0 | 0 |
| 5392 | ordinary | 1000 | 32 | 10 | 0 | 22 | 10 | S2 | 0 | 940 | 0 | 0 |
| 5392 | ordinary | 8000 | 32 | 10 | 0 | 22 | 10 | S2 | 0 | 940 | 0 | 0 |
| 5704 | ordinary | 100 | 34 | 12 | 0 | 22 | 22 | S2 | 0 | 1400 | 0 | 0 |
| 5704 | ordinary | 1000 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 1512 | 0 | 0 |
| 5704 | ordinary | 8000 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 1728 | 0 | 0 |
| 5728 | ordinary | 100 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 1736 | 0 | 0 |
| 5728 | ordinary | 1000 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 1736 | 0 | 0 |
| 5728 | ordinary | 8000 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 1728 | 0 | 0 |
| 5776 | ordinary | 100 | 35 | 10 | 3 | 22 | 18 | S2 | 0 | 2460 | 0 | 0 |
| 5776 | ordinary | 1000 | 35 | 10 | 3 | 22 | 18 | S2 | 0 | 2508 | 0 | 0 |
| 5776 | ordinary | 8000 | 35 | 10 | 3 | 22 | 18 | S2 | 0 | 2592 | 0 | 0 |
| 5800 | ordinary | 100 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 872 | 0 | 0 |
| 5800 | ordinary | 1000 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 868 | 0 | 0 |
| 5800 | ordinary | 8000 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 864 | 0 | 0 |
| 5824 | ordinary | 100 | 35 | 10 | 3 | 22 | 22 | S2 | 0 | 1652 | 0 | 0 |
| 5824 | ordinary | 1000 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 1680 | 0 | 0 |
| 5824 | ordinary | 8000 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 1728 | 0 | 0 |
| 5992 | ordinary | 100 | 35 | 10 | 3 | 22 | 22 | S2 | 0 | 8 | 0 | 0 |
| 5992 | ordinary | 1000 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 8 | 0 | 0 |
| 5992 | ordinary | 8000 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 8 | 0 | 0 |
| 6232 | ordinary | 100 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 151 | 0 | 0 |
| 6232 | ordinary | 1000 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 156 | 0 | 0 |
| 6232 | ordinary | 8000 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 156 | 0 | 0 |
| 6256 | ordinary | 100 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 434 | 0 | 0 |
| 6256 | ordinary | 1000 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 437 | 0 | 0 |
| 6256 | ordinary | 8000 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 440 | 0 | 0 |
| 6280 | ordinary | 100 | 34 | 12 | 0 | 22 | 22 | S2 | 0 | 437 | 0 | 0 |
| 6280 | ordinary | 1000 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 440 | 0 | 0 |
| 6280 | ordinary | 8000 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 440 | 0 | 0 |
| 6304 | ordinary | 100 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 437 | 0 | 0 |
| 6304 | ordinary | 1000 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 434 | 0 | 0 |
| 6304 | ordinary | 8000 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 437 | 0 | 0 |
| 6328 | ordinary | 100 | 34 | 12 | 0 | 22 | 22 | S2 | 0 | 440 | 0 | 0 |
| 6328 | ordinary | 1000 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 440 | 0 | 0 |
| 6328 | ordinary | 8000 | 32 | 10 | 0 | 22 | 18 | S2 | 0 | 440 | 0 | 0 |
| 6400 | ordinary | 100 | 32 | 10 | 0 | 22 | 14 | S2 | 0 | 657 | 0 | 0 |
| 6400 | ordinary | 1000 | 32 | 10 | 0 | 22 | 14 | S2 | 0 | 654 | 0 | 0 |
| 6400 | ordinary | 8000 | 32 | 10 | 0 | 22 | 14 | S2 | 0 | 657 | 0 | 0 |
| 6424 | ordinary | 100 | 35 | 10 | 3 | 22 | 18 | S2 | 0 | 657 | 0 | 0 |
| 6424 | ordinary | 1000 | 32 | 10 | 0 | 22 | 14 | S2 | 0 | 657 | 0 | 0 |
| 6424 | ordinary | 8000 | 32 | 10 | 0 | 22 | 14 | S2 | 0 | 657 | 0 | 0 |
| 6520 | ordinary | 100 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 85 | 0 | 0 |
| 6520 | ordinary | 1000 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 85 | 0 | 0 |
| 6520 | ordinary | 8000 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 76 | 0 | 0 |
| 7024 | ordinary | 100 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 433 | 0 | 0 |
| 7024 | ordinary | 1000 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 436 | 0 | 0 |
| 7024 | ordinary | 8000 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 475 | 0 | 0 |
| 8008 | ordinary | 100 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 92 | 0 | 0 |
| 8008 | ordinary | 1000 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 92 | 0 | 0 |
| 8008 | ordinary | 8000 | 32 | 10 | 0 | 22 | 22 | S2 | 0 | 92 | 0 | 0 |
