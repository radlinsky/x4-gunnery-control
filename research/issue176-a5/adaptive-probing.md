# A5 adaptive multi-ray aim-point finder — 2026-09-18

Scope: [Issue #176](https://github.com/radlinsky/x4-gunnery-control/issues/176)
A5, CANNOT BEAR for turrets with known geometry. Offline, status **inference**.
This replaces the `same_ray_refine` proposal in `ray-failure-groups.md`, which
is not implemented. Uses the accepted A4x design, scenarios, query model
(`study.Q`: native nearest aimtarget, binary32, quantised yaw/pitch) and truth
scorer unchanged. No X4 launch, no production change. Range, line of fire,
firing solution, readiness and authorization are out of scope.

```sh
python3 research/issue176-a5/adaptive.py --selftest          # ~1 min
python3 research/issue176-a5/adaptive.py --focus             # 361 focus cases, ~6 min on 4 niced workers
python3 research/issue176-a5/adaptive.py --sample 1000       # seeded broad screen, ~20 min
python3 research/issue176-a5/adaptive_report.py [adaptive-focus|adaptive-sample1000]
```

Rows (with a per-query trace for every adaptive run) are ignored under
`.x4-research-cache/issue176-a5/`. The full corpus was not run: measured cost
is ~4 s per case per worker (the yaw-rest gate dominates), so 37,830 cases
would take ~10 h. The focus set holds every case named in the brief; the
broad screen is 1,000 seeded random cases (899 realistic, 96 synthetic
truth-known rows per factor).

## Answers

1. **Does adaptive probing outperform the fixed ray methods?** Yes, on the
   rows that matter. On the 361 focus cases (factor 1) it decides 316
   (137 ENGAGEABLE, 179 NOT ENGAGEABLE) with **0 false ENGAGEABLE and 0 false
   NOT ENGAGEABLE**. three_ray4 decides 282, same_ray 2 (both wrong), and the
   current chain decides 360 but 14 of them wrongly (5 false ENGAGEABLE,
   9 false NOT). On the broad screen it matches same_ray's coverage on easy
   rows (875 vs 882 of 899) without same_ray's unsafe end-agreement rule.
2. **The 79 aim-point-switch cases:** 70 decided (38 ENGAGEABLE, 32 NOT),
   none wrong, 9 UNKNOWN. three_ray4 decides 0.
3. **The current false ENGAGEABLE fallback cases:** all 5 are gone. Of the
   15 chain residual rows, 13 are now decided correctly (9 ENGAGEABLE, 4 NOT)
   and 2 are UNKNOWN. Both known flip-back rows (13132:22 open bracket,
   2979:99 closed bracket) come out correctly NOT ENGAGEABLE.
4. **Queries:** median 6–7, p90 9–10, p99 11–13, max 13 on the focus set,
   19–21 on the broad screen. The anchor query is included in every count.
5. **Does angular stopping save queries versus locating the point?** Yes,
   but not in the way I expected. Median 6–7 against 10–11 for `locate`, and
   the same answers. The saving comes from not spending the extra sideways
   probes when a located point already clears its limit. The certificate
   **never** decided a wide coarse bracket before the point was located (0 on
   realistic rows). The linearised bound (below) only applies to regions
   under 1% of range, and a rough along-ray bracket is ~8–100% wide.
6. **Remaining failure modes:** listed below.
7. **Simpler version for A6:** `tri2`, sideways rays only (described below).

## The method

A query from position U returns a direction toward whichever aim point the
native selector picks from U. The anchor query from the turret origin O
defines the anchor ray; the original selection P lies on it, and that is the
point whose CANNOT BEAR answer matters. State is the depth interval
`[lo, hi]` of P along the anchor ray, with the angular cone of the quantised
direction around it.

1. **Sideways probe.** Start on the anchor ray at depth `lo/2`, where P
   provably stays nearest, and step sideways by the offset that changes the
   viewing angle of the current depth estimate by α (2° at first). The
   estimate is the rough distance until an upper bound exists, then the depth
   that halves the viewing angle *from the turret's yaw pivot* between `lo`
   and `hi`. So a 50 m target and a 5 km target get spacings three orders of
   magnitude apart.
2. **If the returned ray crosses the anchor ray inside `[lo, hi]`,** the
   crossing depth τ has error `~EPS·τ/sin α`. Two along-ray probes then check
   it coarsely (forward short of τ, non-forward past τ). Those bounds are
   kept.
3. **If it misses,** another aim point was selected. That observation is
   recorded, not discarded. The next sideways probe halves α and turns 60°.
   A smaller step keeps P nearest more often. That is how the 79 switch rows
   are recovered: 120 of the 361 focus rows saw at least one such miss and
   more than one selected aim point.
4. **Located:** two sideways rays from different directions agree with each
   other and with the anchor-ray bounds. The region becomes their
   intersection, typically millimetres wide.
5. **If located but not certified,** widen α ×4 (up to 30°, at most twice),
   which shrinks the crossing error in proportion to 1/α. If a wider ray loses
   P, the located region stands.
6. **Stop** when the certificate decides, when nothing narrower can be
   observed (`floor`), or when the budget runs out (24 queries,
   research-loose). Otherwise the answer is UNKNOWN.

**Certificate (the stop rule).** For the region, compute the required
leaf-joint pitch per resting yaw at the centre, and its gradient by central
differences. Spread = |∇pitch| × region diameter, including the angular cone.
Decide YES when a resting solution's margin inside the arc is more than
2 × spread; decide NO when every rest is out of arc by more than 2 × spread.
Also require that the yaw-gate class is the same at both ends and the centre,
and that the target is far from the yaw pole. Only offered when the region is
under 1% of its distance from the yaw pivot and the yaw rest is unique.

This is a **first-order** certificate, not a global proof: at mm/100 m
scale, curvature is ~10⁻⁵ of the linear term. Offline truth agrees with it.
No certified region missed the true depth (0 of ~3,800 decided rows), and a
24-point truth scan inside every certified region found no label change. The
scan is a screen, not proof.

## Variants (same rows)

| variant | what differs | factor 1 focus: YES / NO / UNKNOWN, false | queries med/p90/max |
|---|---|---|---|
| **adaptive** | as above | 137 / 179 / 45, 0 | 6/10/13 |
| locate | stops only once the point is located and widened | 137 / 179 / 45, 0 | 10/12/13 |
| tri2 | no along-ray confirmation; two agreeing sideways rays set the region | 137 / 178 / 46, 0 | 5/8/20 |
| strict | depth only from along-ray bounds (~8% floor) | 0 / 0 / 361, 0 | 5/6/9 |
| along | no sideways probes | 0 / 0 / 361, 0 | 7/10/14 |

`strict` and `along` show the diagnosis that drove the design. The along-ray
primitive cannot localise below ~8% (a probe within `2·EPS/FORWARD` of P reads
non-forward). Near a large target that is several degrees of pitch, so these
rows never certify. Sideways triangulation reaches ~10⁻⁴ relative in one
query. The along-ray probes are only a coarse consistency check.

Distance-estimate sensitivity (focus, realistic): factor 0.5 → 136/178/47,
factor 1 → 137/179/45, factor 2 → 137/178/46, all with 0 false. The broad
screen is also flat across factors (874–875 decided of 899). The spacing
adapts because the first crossing replaces the estimate. Factors are
sensitivity constructs, not gameplay frequencies.

Broad screen (1,000 seeded cases, factor 1). Realistic: adaptive
508/367/24 with 0 false; same_ray 513/369/17 with 0 false in this sample;
three_ray4 324/234/341; chain 521/377/0 with 1 false ENGAGEABLE. Synthetic
stress: adaptive 45/19/32, tri2 59/23/14, both with 0 false. same_ray has
1 false NOT.

## Remaining failure modes

- **Non-`ordinary_xy` turrets get no certificate** (bounded_traverse,
  rotation_z, reversed_xy): 41 of the 45 focus UNKNOWNs. Every one of them
  was located. Adding a per-class margin (the scorer's clamps already expose
  the joint requests) is the obvious next step and needs no new queries.
- **Genuinely near-limit rows:** a margin below 2 × spread even after
  widening, for example 13393:276 with a margin of 0.004° and a spread of
  0.40°. UNKNOWN is correct at this resolution.
- **Uncertifiable geometry:** the target is within the barrel's lever of the
  yaw pivot, or there are several yaw rests. These rows are UNKNOWN.
- **False consensus remains possible in principle.** Two sideways rays that
  selected *other* points could still cross the anchor ray at the same depth.
  The coarse along-ray check narrows this to within ~8% of the crossing. The
  constructed `false_pair` / `false_triple` synthetics produced no false
  answer. Truth-side containment was 100% on every decided row.
- **Assumptions:** the along-ray *lower* bound (forward ⇒ P ahead) is the same
  unproven assumption same_ray makes. The runtime offset-origin query primitive
  is still unproven live (`runtime-aim-query-survey.md` §1a).
- **Cost:** 6–13 queries per decision against three_ray4's 3–4.

## Recommendation for A6

Carry forward **`tri2` with the angular certificate**: anchor query, sideways
probes sized by viewing angle from the turret (halve α and turn on a miss,
widen ×4 once located if the margin needs it), and stop on margin > 2 ×
linearised spread. It matched `adaptive` on realistic rows with fewer queries
(median 4–5) and decided more synthetic stress rows, with 0 false answers
either way. Keep the adaptive along-ray check as an optional guard if the
false-consensus risk needs closing. Add non-`ordinary_xy` margins first,
because that is where most of the remaining UNKNOWNs are.
