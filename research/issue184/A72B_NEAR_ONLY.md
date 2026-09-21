# Issue #184 A7.2b: one near-target-only search at 24 total questions, against the accepted three-stage A7.2 result

Offline research, status **inference**. No X4 launch, no production change, and the accepted #184
method is NOT changed by this file: it is an experiment to decide whether A7.2's three stages must
survive. Run with `python3 research/issue184/aimpoint_map.py --a72n`.

## The candidate

The firing-ship corner search and the cheap rescue stage are deleted. The search starts from 4
fixed probe positions - the alternating corners of the target's runtime box grown by the existing
50 m near-target pad, the tetrahedron inscribed in that box - and then continues with the
unchanged adaptive near-target placement, which each time probes the largest missing viewing
direction of a confirmed point. One budget of **24 X4 questions** covers everything: the 4 starting
probes, every along-ray confirmation ask, every moved ask, and every adaptive probe. It stops at the
first of: no valid next probe, or fewer than 3 questions left (one probe plus its possible
confirmation). The 'all four saw the same point' shortcut is deliberately NOT part of this.

Both methods are scored by the same code on the same 126 focused A7.1/A7.2 cases, against the same
hidden firing-ship-wide truth: every real mount on the firing ship, every compatible turret the
benchmark accepts, aimed muzzle positions only, out-of-arc poses excluded, no resting positions.
Hidden aim points and later turret positions are scoring truth only and never touch placement,
stopping or budget.

## Head to head

| | candidate, 24 total, near-target only | accepted A7.2, three stages |
|---|---:|---:|
| needed aim points missed | 6 | 0 |
| final wrong aim-point choices | 704 | 0 |
| final correct | 119355 | 120033 |
| final UNKNOWN | 69 | 95 |
| invented points | 0 | 0 |
| merged points | 0 | 0 |
| duplicate points | 0 | 0 |
| authored points never discovered | 12 | 1 |
| points confirmed | 318 | 329 |
| points tightened by refinement | 240 | 321 |
| identity changes from refinement | 0 | 0 |
| total X4 questions, median / worst | 22/24 | 34/39 |
| point radius (m), median / worst | 0.00335/0.329 | 0.00209/0.372 |
| point position error (m), median / worst | 0.000437/0.0649 | 0.00031/0.148 |
| cases spending the full budget | 126 of 126 (24 questions) | 126 of 126 (S2) |
| cases stopping with nowhere useful left to probe | 0 | 0 |

## Did the first two stages provide anything the candidate cannot recover?

All 126 cases started the adaptive search: **126 of 126** had at least one confirmed
point after the 4 starting probes plus, where needed, the moved-ask continuation (102 cases needed it).
The 4 starts alone confirmed a point in 24 cases.
Questions spent before the adaptive search could begin: median / worst 10/24, against 12/17 for the accepted method's two
deleted stages.

## Cases where the candidate is worse

| case | gap (m) | group | new c/w/U | old c/w/U | new needed missing | old needed missing | new inv/mer/dup | asks | end |
|---|---:|---|---|---|---:|---:|---|---:|---|
| 12157 | 100 | hard | 368/0/4 | 372/0/0 | 0 | 0 | 0/0/0 | 24 | budget |
| 12157 | 1000 | hard | 392/0/4 | 396/0/0 | 0 | 0 | 0/0/0 | 24 | budget |
| 12157 | 8000 | hard | 404/0/4 | 408/0/0 | 0 | 0 | 0/0/0 | 24 | budget |
| 12160 | 100 | hard | 87/207/0 | 294/0/0 | 1 | 0 | 0/0/0 | 22 | budget |
| 12160 | 1000 | hard | 117/221/0 | 338/0/0 | 1 | 0 | 0/0/0 | 22 | budget |
| 12160 | 8000 | hard | 232/252/0 | 484/0/0 | 1 | 0 | 0/0/0 | 22 | budget |
| 12163 | 100 | hard | 328/8/0 | 332/0/4 | 1 | 0 | 0/0/0 | 22 | budget |
| 12163 | 1000 | hard | 328/8/0 | 336/0/0 | 1 | 0 | 0/0/0 | 22 | budget |
| 12163 | 8000 | hard | 328/8/0 | 336/0/0 | 1 | 0 | 0/0/0 | 22 | budget |
| 12197 | 8000 | hard | 1434/0/6 | 1436/0/4 | 0 | 0 | 0/0/0 | 22 | budget |
| 12199 | 100 | hard | 1344/0/2 | 1346/0/0 | 0 | 0 | 0/0/0 | 22 | budget |
| 12368 | 8000 | hard | 1416/0/10 | 1421/0/5 | 0 | 0 | 0/0/0 | 22 | budget |
| 12376 | 8000 | hard | 2119/0/14 | 2124/0/9 | 0 | 0 | 0/0/0 | 22 | budget |

## Why the candidate fails, case by cause

| cause | cases | effect |
|---|---:|---|
| ran out of the 24-question budget before discovering a needed aim point: the starts confirmed nothing, the moved-ask continuation spent 19/19 questions getting the first point confirmed, and only 3/3 adaptive probes were left | 6 | 704 definite WRONG choices, 6 needed points missed |
| ran out of the budget before the adaptive search made a single probe: all 24 questions went to the 4 starts and the moved-ask continuation | 3 | no wrong answer, 12 extra UNKNOWN |
| located points too loosely: the same points, but fewer observations each, so refinement left them wider and `nearest` could not separate them everywhere | 4 | no wrong answer, 14 extra UNKNOWN |
| the adaptive search could not choose another useful position | 0 | none |

**FAIL.** 704 final wrong aim-point choices against 0 for the accepted three-stage result, and 6 aim points a later aimed muzzle on the firing ship really selects were never found. Invented, merged and duplicate points and refinement identity changes all stayed 0, and 112 of 126 cases matched the accepted result exactly at 22/24 questions instead of 34/39. The failures are a safety regression, not extra UNKNOWN, so the experiment does not pass.

The two deleted stages provide nothing the candidate cannot reach by placement: where it had the
questions it confirmed the same points by the same rules and gave the same answers. What they
provide is questions already spent by the time the adaptive stage begins. The accepted method
arrives there with a point confirmed for 12-17 questions and then gets its own 24 on top; the
candidate spends 6-24 of its single 24 confirming the first point at all - 102 of 126 cases need
the moved-ask continuation, because 4 probes alone rarely cross well enough to confirm a point -
and what is left is too little on the hard multi-point geometries. That is evidence against 24 as a
total, not against a near-target-only search.

## Per case

| case | group | gap (m) | new asks | new starts pts | new pre-adaptive asks | new primary | new end | new pts | new c/w/U | new needed missing | old asks | old pts | old c/w/U | old needed missing |
|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---:|---|---:|
| 12155 | hard | 100 | 22 | 0 | 19 | 3 | budget | 3 | 252/0/0 | 0 | 35 | 4 | 252/0/0 | 0 |
| 12155 | hard | 1000 | 22 | 0 | 19 | 3 | budget | 3 | 252/0/0 | 0 | 35 | 4 | 252/0/0 | 0 |
| 12155 | hard | 8000 | 22 | 0 | 19 | 3 | budget | 3 | 252/0/0 | 0 | 35 | 4 | 252/0/0 | 0 |
| 12157 | hard | 100 | 24 | 0 | 24 | 0 | budget | 4 | 368/0/4 | 0 | 35 | 4 | 372/0/0 | 0 |
| 12157 | hard | 1000 | 24 | 0 | 24 | 0 | budget | 4 | 392/0/4 | 0 | 35 | 4 | 396/0/0 | 0 |
| 12157 | hard | 8000 | 24 | 0 | 24 | 0 | budget | 4 | 404/0/4 | 0 | 35 | 4 | 408/0/0 | 0 |
| 12160 | hard | 100 | 22 | 0 | 19 | 3 | budget | 3 | 87/207/0 | 1 | 39 | 4 | 294/0/0 | 0 |
| 12160 | hard | 1000 | 22 | 0 | 19 | 3 | budget | 3 | 117/221/0 | 1 | 38 | 4 | 338/0/0 | 0 |
| 12160 | hard | 8000 | 22 | 0 | 19 | 3 | budget | 3 | 232/252/0 | 1 | 38 | 4 | 484/0/0 | 0 |
| 12163 | hard | 100 | 22 | 0 | 19 | 3 | budget | 3 | 328/8/0 | 1 | 35 | 4 | 332/0/4 | 0 |
| 12163 | hard | 1000 | 22 | 0 | 19 | 3 | budget | 3 | 328/8/0 | 1 | 35 | 4 | 336/0/0 | 0 |
| 12163 | hard | 8000 | 22 | 0 | 19 | 3 | budget | 3 | 328/8/0 | 1 | 35 | 4 | 336/0/0 | 0 |
| 12169 | hard | 100 | 22 | 0 | 15 | 7 | budget | 3 | 313/0/0 | 0 | 38 | 3 | 313/0/0 | 0 |
| 12169 | hard | 1000 | 22 | 0 | 15 | 7 | budget | 3 | 337/0/0 | 0 | 38 | 3 | 337/0/0 | 0 |
| 12169 | hard | 8000 | 22 | 0 | 15 | 7 | budget | 3 | 361/0/0 | 0 | 38 | 3 | 361/0/0 | 0 |
| 12177 | hard | 100 | 22 | 0 | 15 | 7 | budget | 3 | 1956/0/0 | 0 | 38 | 3 | 1956/0/0 | 0 |
| 12177 | hard | 1000 | 22 | 0 | 15 | 7 | budget | 3 | 2062/0/0 | 0 | 38 | 3 | 2062/0/0 | 0 |
| 12177 | hard | 8000 | 22 | 0 | 15 | 7 | budget | 3 | 2076/0/0 | 0 | 38 | 3 | 2076/0/0 | 0 |
| 12196 | hard | 100 | 22 | 0 | 15 | 3 | budget | 4 | 1344/0/0 | 0 | 35 | 4 | 1344/0/0 | 0 |
| 12196 | hard | 1000 | 22 | 0 | 15 | 3 | budget | 4 | 1344/0/0 | 0 | 35 | 4 | 1344/0/0 | 0 |
| 12196 | hard | 8000 | 22 | 0 | 15 | 3 | budget | 4 | 1344/0/0 | 0 | 35 | 4 | 1344/0/0 | 0 |
| 12197 | hard | 100 | 22 | 0 | 15 | 3 | budget | 4 | 1436/0/2 | 0 | 35 | 4 | 1436/0/2 | 0 |
| 12197 | hard | 1000 | 22 | 0 | 15 | 3 | budget | 4 | 1438/0/2 | 0 | 35 | 4 | 1438/0/2 | 0 |
| 12197 | hard | 8000 | 22 | 0 | 15 | 3 | budget | 4 | 1434/0/6 | 0 | 35 | 4 | 1436/0/4 | 0 |
| 12199 | hard | 100 | 22 | 0 | 15 | 3 | budget | 4 | 1344/0/2 | 0 | 38 | 4 | 1346/0/0 | 0 |
| 12199 | hard | 1000 | 22 | 0 | 15 | 3 | budget | 4 | 1344/0/0 | 0 | 37 | 4 | 1344/0/0 | 0 |
| 12199 | hard | 8000 | 22 | 0 | 15 | 3 | budget | 4 | 1344/0/0 | 0 | 38 | 4 | 1344/0/0 | 0 |
| 12234 | hard | 100 | 22 | 0 | 10 | 8 | budget | 3 | 1008/0/0 | 0 | 34 | 3 | 1008/0/0 | 0 |
| 12234 | hard | 1000 | 22 | 0 | 10 | 8 | budget | 3 | 1008/0/0 | 0 | 38 | 3 | 1008/0/0 | 0 |
| 12234 | hard | 8000 | 22 | 0 | 10 | 8 | budget | 3 | 1005/0/3 | 0 | 34 | 3 | 957/0/51 | 0 |
| 12360 | hard | 100 | 22 | 0 | 10 | 8 | budget | 3 | 1384/0/0 | 0 | 38 | 3 | 1384/0/0 | 0 |
| 12360 | hard | 1000 | 22 | 0 | 10 | 8 | budget | 3 | 1394/0/0 | 0 | 38 | 3 | 1394/0/0 | 0 |
| 12360 | hard | 8000 | 22 | 0 | 10 | 8 | budget | 3 | 1470/0/0 | 0 | 38 | 3 | 1470/0/0 | 0 |
| 12362 | hard | 100 | 22 | 0 | 10 | 8 | budget | 3 | 1327/0/0 | 0 | 35 | 3 | 1327/0/0 | 0 |
| 12362 | hard | 1000 | 22 | 0 | 10 | 8 | budget | 3 | 1327/0/0 | 0 | 35 | 3 | 1327/0/0 | 0 |
| 12362 | hard | 8000 | 22 | 0 | 10 | 8 | budget | 3 | 1480/0/0 | 0 | 35 | 3 | 1480/0/0 | 0 |
| 12365 | hard | 100 | 22 | 0 | 10 | 8 | budget | 3 | 2139/0/0 | 0 | 35 | 3 | 2139/0/0 | 0 |
| 12365 | hard | 1000 | 22 | 0 | 10 | 8 | budget | 3 | 2161/0/0 | 0 | 35 | 3 | 2161/0/0 | 0 |
| 12365 | hard | 8000 | 22 | 0 | 10 | 8 | budget | 3 | 2190/0/0 | 0 | 35 | 3 | 2190/0/0 | 0 |
| 12366 | hard | 100 | 22 | 0 | 10 | 8 | budget | 3 | 1252/0/0 | 0 | 35 | 3 | 1252/0/0 | 0 |
| 12366 | hard | 1000 | 22 | 0 | 10 | 8 | budget | 3 | 1255/0/0 | 0 | 35 | 3 | 1255/0/0 | 0 |
| 12366 | hard | 8000 | 22 | 0 | 10 | 8 | budget | 3 | 1298/0/0 | 0 | 35 | 2 | 1298/0/0 | 0 |
| 12368 | hard | 100 | 22 | 0 | 10 | 8 | budget | 3 | 1326/0/0 | 0 | 38 | 3 | 1326/0/0 | 0 |
| 12368 | hard | 1000 | 22 | 0 | 10 | 8 | budget | 3 | 1345/0/0 | 0 | 38 | 3 | 1345/0/0 | 0 |
| 12368 | hard | 8000 | 22 | 0 | 10 | 8 | budget | 3 | 1416/0/10 | 0 | 38 | 3 | 1421/0/5 | 0 |
| 12369 | hard | 100 | 22 | 0 | 10 | 8 | budget | 3 | 2133/0/0 | 0 | 38 | 3 | 2133/0/0 | 0 |
| 12369 | hard | 1000 | 22 | 0 | 10 | 8 | budget | 3 | 2179/0/0 | 0 | 38 | 3 | 2179/0/0 | 0 |
| 12369 | hard | 8000 | 22 | 0 | 10 | 8 | budget | 3 | 2261/0/0 | 0 | 38 | 3 | 2261/0/0 | 0 |
| 12376 | hard | 100 | 22 | 0 | 10 | 8 | budget | 3 | 1829/0/9 | 0 | 34 | 3 | 1829/0/9 | 0 |
| 12376 | hard | 1000 | 22 | 0 | 10 | 8 | budget | 3 | 1958/0/9 | 0 | 34 | 3 | 1958/0/9 | 0 |
| 12376 | hard | 8000 | 22 | 0 | 10 | 8 | budget | 3 | 2119/0/14 | 0 | 34 | 3 | 2124/0/9 | 0 |
| 12388 | hard | 100 | 22 | 0 | 10 | 8 | budget | 3 | 1226/0/0 | 0 | 35 | 3 | 1226/0/0 | 0 |
| 12388 | hard | 1000 | 22 | 0 | 10 | 8 | budget | 3 | 1300/0/0 | 0 | 35 | 3 | 1300/0/0 | 0 |
| 12388 | hard | 8000 | 22 | 0 | 10 | 8 | budget | 3 | 1392/0/0 | 0 | 35 | 3 | 1392/0/0 | 0 |
| 12390 | hard | 100 | 22 | 0 | 10 | 8 | budget | 3 | 1364/0/0 | 0 | 35 | 3 | 1364/0/0 | 0 |
| 12390 | hard | 1000 | 22 | 0 | 10 | 8 | budget | 3 | 1391/0/0 | 0 | 35 | 3 | 1391/0/0 | 0 |
| 12390 | hard | 8000 | 22 | 0 | 10 | 8 | budget | 3 | 1536/0/0 | 0 | 35 | 3 | 1536/0/0 | 0 |
| 3568 | ordinary | 100 | 22 | 1 | 6 | 16 | budget | 1 | 624/0/0 | 0 | 32 | 1 | 624/0/0 | 0 |
| 3568 | ordinary | 1000 | 22 | 1 | 6 | 16 | budget | 1 | 624/0/0 | 0 | 32 | 1 | 624/0/0 | 0 |
| 3568 | ordinary | 8000 | 22 | 1 | 6 | 16 | budget | 1 | 600/0/0 | 0 | 32 | 1 | 600/0/0 | 0 |
| 4072 | ordinary | 100 | 22 | 1 | 6 | 16 | budget | 1 | 228/0/0 | 0 | 32 | 1 | 228/0/0 | 0 |
| 4072 | ordinary | 1000 | 22 | 1 | 6 | 16 | budget | 1 | 228/0/0 | 0 | 32 | 1 | 228/0/0 | 0 |
| 4072 | ordinary | 8000 | 22 | 1 | 6 | 16 | budget | 1 | 228/0/0 | 0 | 32 | 1 | 228/0/0 | 0 |
| 4168 | ordinary | 100 | 22 | 0 | 19 | 3 | budget | 3 | 1439/0/0 | 0 | 32 | 4 | 1439/0/0 | 0 |
| 4168 | ordinary | 1000 | 22 | 0 | 19 | 3 | budget | 3 | 1442/0/0 | 0 | 33 | 4 | 1442/0/0 | 0 |
| 4168 | ordinary | 8000 | 22 | 0 | 19 | 3 | budget | 3 | 1447/0/0 | 0 | 32 | 4 | 1447/0/0 | 0 |
| 4432 | ordinary | 100 | 22 | 1 | 6 | 16 | budget | 1 | 266/0/0 | 0 | 32 | 1 | 266/0/0 | 0 |
| 4432 | ordinary | 1000 | 22 | 1 | 6 | 16 | budget | 1 | 266/0/0 | 0 | 32 | 1 | 266/0/0 | 0 |
| 4432 | ordinary | 8000 | 22 | 1 | 6 | 16 | budget | 1 | 266/0/0 | 0 | 32 | 1 | 266/0/0 | 0 |
| 5320 | ordinary | 100 | 22 | 1 | 6 | 16 | budget | 1 | 280/0/0 | 0 | 32 | 1 | 280/0/0 | 0 |
| 5320 | ordinary | 1000 | 22 | 1 | 6 | 16 | budget | 1 | 290/0/0 | 0 | 32 | 1 | 290/0/0 | 0 |
| 5320 | ordinary | 8000 | 22 | 1 | 6 | 16 | budget | 1 | 290/0/0 | 0 | 32 | 1 | 290/0/0 | 0 |
| 5368 | ordinary | 100 | 22 | 0 | 15 | 7 | budget | 3 | 705/0/0 | 0 | 32 | 3 | 705/0/0 | 0 |
| 5368 | ordinary | 1000 | 22 | 0 | 15 | 7 | budget | 3 | 705/0/0 | 0 | 32 | 3 | 705/0/0 | 0 |
| 5368 | ordinary | 8000 | 22 | 0 | 15 | 7 | budget | 3 | 705/0/0 | 0 | 32 | 3 | 705/0/0 | 0 |
| 5392 | ordinary | 100 | 22 | 0 | 15 | 3 | budget | 4 | 940/0/0 | 0 | 32 | 4 | 940/0/0 | 0 |
| 5392 | ordinary | 1000 | 22 | 0 | 15 | 3 | budget | 4 | 940/0/0 | 0 | 32 | 4 | 940/0/0 | 0 |
| 5392 | ordinary | 8000 | 22 | 0 | 15 | 3 | budget | 4 | 940/0/0 | 0 | 32 | 4 | 940/0/0 | 0 |
| 5704 | ordinary | 100 | 22 | 0 | 10 | 12 | budget | 2 | 1400/0/0 | 0 | 34 | 2 | 1400/0/0 | 0 |
| 5704 | ordinary | 1000 | 22 | 0 | 10 | 12 | budget | 2 | 1512/0/0 | 0 | 32 | 2 | 1512/0/0 | 0 |
| 5704 | ordinary | 8000 | 22 | 0 | 10 | 12 | budget | 2 | 1728/0/0 | 0 | 32 | 2 | 1728/0/0 | 0 |
| 5728 | ordinary | 100 | 22 | 0 | 10 | 12 | budget | 2 | 1736/0/0 | 0 | 32 | 2 | 1736/0/0 | 0 |
| 5728 | ordinary | 1000 | 22 | 0 | 10 | 12 | budget | 2 | 1736/0/0 | 0 | 32 | 2 | 1736/0/0 | 0 |
| 5728 | ordinary | 8000 | 22 | 0 | 10 | 12 | budget | 2 | 1728/0/0 | 0 | 32 | 2 | 1728/0/0 | 0 |
| 5776 | ordinary | 100 | 22 | 0 | 10 | 8 | budget | 3 | 2460/0/0 | 0 | 35 | 3 | 2460/0/0 | 0 |
| 5776 | ordinary | 1000 | 22 | 0 | 10 | 8 | budget | 3 | 2508/0/0 | 0 | 35 | 3 | 2508/0/0 | 0 |
| 5776 | ordinary | 8000 | 22 | 0 | 10 | 8 | budget | 3 | 2592/0/0 | 0 | 35 | 3 | 2592/0/0 | 0 |
| 5800 | ordinary | 100 | 22 | 1 | 6 | 16 | budget | 1 | 872/0/0 | 0 | 32 | 1 | 872/0/0 | 0 |
| 5800 | ordinary | 1000 | 22 | 1 | 6 | 16 | budget | 1 | 868/0/0 | 0 | 32 | 1 | 868/0/0 | 0 |
| 5800 | ordinary | 8000 | 22 | 1 | 6 | 16 | budget | 1 | 864/0/0 | 0 | 32 | 1 | 864/0/0 | 0 |
| 5824 | ordinary | 100 | 22 | 0 | 10 | 12 | budget | 2 | 1652/0/0 | 0 | 35 | 2 | 1652/0/0 | 0 |
| 5824 | ordinary | 1000 | 22 | 0 | 10 | 12 | budget | 2 | 1680/0/0 | 0 | 32 | 2 | 1680/0/0 | 0 |
| 5824 | ordinary | 8000 | 22 | 0 | 10 | 12 | budget | 2 | 1728/0/0 | 0 | 32 | 2 | 1728/0/0 | 0 |
| 5992 | ordinary | 100 | 22 | 0 | 10 | 12 | budget | 2 | 8/0/0 | 0 | 35 | 2 | 8/0/0 | 0 |
| 5992 | ordinary | 1000 | 22 | 0 | 10 | 12 | budget | 2 | 8/0/0 | 0 | 32 | 2 | 8/0/0 | 0 |
| 5992 | ordinary | 8000 | 22 | 0 | 10 | 12 | budget | 2 | 8/0/0 | 0 | 32 | 2 | 8/0/0 | 0 |
| 6232 | ordinary | 100 | 22 | 0 | 10 | 12 | budget | 2 | 151/0/0 | 0 | 32 | 2 | 151/0/0 | 0 |
| 6232 | ordinary | 1000 | 22 | 0 | 10 | 12 | budget | 2 | 156/0/0 | 0 | 32 | 2 | 156/0/0 | 0 |
| 6232 | ordinary | 8000 | 22 | 0 | 10 | 12 | budget | 2 | 156/0/0 | 0 | 32 | 2 | 156/0/0 | 0 |
| 6256 | ordinary | 100 | 22 | 0 | 10 | 12 | budget | 2 | 434/0/0 | 0 | 32 | 2 | 434/0/0 | 0 |
| 6256 | ordinary | 1000 | 22 | 0 | 10 | 12 | budget | 2 | 437/0/0 | 0 | 32 | 2 | 437/0/0 | 0 |
| 6256 | ordinary | 8000 | 22 | 0 | 10 | 12 | budget | 2 | 440/0/0 | 0 | 32 | 2 | 440/0/0 | 0 |
| 6280 | ordinary | 100 | 22 | 0 | 10 | 12 | budget | 2 | 437/0/0 | 0 | 34 | 2 | 437/0/0 | 0 |
| 6280 | ordinary | 1000 | 22 | 0 | 10 | 12 | budget | 2 | 440/0/0 | 0 | 32 | 2 | 440/0/0 | 0 |
| 6280 | ordinary | 8000 | 22 | 0 | 10 | 12 | budget | 2 | 440/0/0 | 0 | 32 | 2 | 440/0/0 | 0 |
| 6304 | ordinary | 100 | 22 | 0 | 10 | 12 | budget | 2 | 437/0/0 | 0 | 32 | 2 | 437/0/0 | 0 |
| 6304 | ordinary | 1000 | 22 | 0 | 10 | 12 | budget | 2 | 434/0/0 | 0 | 32 | 2 | 434/0/0 | 0 |
| 6304 | ordinary | 8000 | 22 | 0 | 10 | 12 | budget | 2 | 437/0/0 | 0 | 32 | 2 | 437/0/0 | 0 |
| 6328 | ordinary | 100 | 22 | 0 | 10 | 12 | budget | 2 | 440/0/0 | 0 | 34 | 2 | 440/0/0 | 0 |
| 6328 | ordinary | 1000 | 22 | 0 | 10 | 12 | budget | 2 | 440/0/0 | 0 | 32 | 2 | 440/0/0 | 0 |
| 6328 | ordinary | 8000 | 22 | 0 | 10 | 12 | budget | 2 | 440/0/0 | 0 | 32 | 2 | 440/0/0 | 0 |
| 6400 | ordinary | 100 | 22 | 0 | 10 | 8 | budget | 3 | 657/0/0 | 0 | 32 | 3 | 657/0/0 | 0 |
| 6400 | ordinary | 1000 | 22 | 0 | 10 | 8 | budget | 3 | 654/0/0 | 0 | 32 | 3 | 654/0/0 | 0 |
| 6400 | ordinary | 8000 | 22 | 0 | 10 | 8 | budget | 3 | 657/0/0 | 0 | 32 | 3 | 657/0/0 | 0 |
| 6424 | ordinary | 100 | 22 | 0 | 10 | 8 | budget | 3 | 657/0/0 | 0 | 35 | 3 | 657/0/0 | 0 |
| 6424 | ordinary | 1000 | 22 | 0 | 10 | 8 | budget | 3 | 657/0/0 | 0 | 32 | 3 | 657/0/0 | 0 |
| 6424 | ordinary | 8000 | 22 | 0 | 10 | 8 | budget | 3 | 657/0/0 | 0 | 32 | 3 | 657/0/0 | 0 |
| 6520 | ordinary | 100 | 22 | 1 | 6 | 16 | budget | 1 | 85/0/0 | 0 | 32 | 1 | 85/0/0 | 0 |
| 6520 | ordinary | 1000 | 22 | 1 | 6 | 16 | budget | 1 | 85/0/0 | 0 | 32 | 1 | 85/0/0 | 0 |
| 6520 | ordinary | 8000 | 22 | 1 | 6 | 16 | budget | 1 | 76/0/0 | 0 | 32 | 1 | 76/0/0 | 0 |
| 7024 | ordinary | 100 | 22 | 1 | 6 | 16 | budget | 1 | 433/0/0 | 0 | 32 | 1 | 433/0/0 | 0 |
| 7024 | ordinary | 1000 | 22 | 1 | 6 | 16 | budget | 1 | 436/0/0 | 0 | 32 | 1 | 436/0/0 | 0 |
| 7024 | ordinary | 8000 | 22 | 1 | 6 | 16 | budget | 1 | 475/0/0 | 0 | 32 | 1 | 475/0/0 | 0 |
| 8008 | ordinary | 100 | 22 | 1 | 6 | 16 | budget | 1 | 92/0/0 | 0 | 32 | 1 | 92/0/0 | 0 |
| 8008 | ordinary | 1000 | 22 | 1 | 6 | 16 | budget | 1 | 92/0/0 | 0 | 32 | 1 | 92/0/0 | 0 |
| 8008 | ordinary | 8000 | 22 | 1 | 6 | 16 | budget | 1 | 92/0/0 | 0 | 32 | 1 | 92/0/0 | 0 |