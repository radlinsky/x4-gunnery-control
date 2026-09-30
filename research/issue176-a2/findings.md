# A2 geometry findings — 2026-09-16

Status: **inference**, experimental offline evidence for Issue #176 A2.
The numerical model is the frozen P3c direction-query surrogate, not bit-exact
X4. No game launch, production change, or ENGAGEABLE accuracy conclusion.
#173 must establish the pitch/arc scorer before any such conclusion.

## Corpus

6,444 base samples × eight rules × three rough-distance multipliers = 154,656
trials. Ordinary 1,800; boundary 4,560; original #172 74 (14 ordinary/60
adversarial); synthetic ten. These are designed samples, not frequency estimates.
The source census has 270 macro records; its 18 multi-point macro records share
15 components and 38 macro-weighted pairs (33 unique component pairs).
All 15 components are represented. Component classes were checked against the
current local official-source XML using `sources.component`:

| Component | Class | Aim points |
|---|---|---:|
| engine_xen_xl_mothership_01_allround_mk1 | engine (surface element) | 4 |
| ship_arg_l_destroyer_02 | ship_l | 3 |
| ship_arg_xl_carrier_02 | ship_xl | 4 |
| ship_bor_l_miner_liquid_01 | ship_l | 2 |
| ship_bor_l_miner_solid_01 | ship_l | 2 |
| ship_gen_s_fightingdrone_01 | ship_s | 3 |
| ship_par_l_expeditionary_01 | ship_l | 2 |
| ship_pir_s_heavyfighter_01 | ship_s | 2 |
| ship_tel_l_destroyer_01 | ship_l | 2 |
| ship_tel_l_destroyer_02 | ship_l | 2 |
| ship_tel_l_miner_liquid_02 | ship_l | 2 |
| ship_tel_l_miner_solid_02 | ship_l | 2 |
| ship_tel_l_trans_container_03 | ship_l | 2 |
| ship_ter_xl_carrier_01 | ship_xl | 3 |
| ship_ter_xl_resupplier_01 | ship_xl | 3 |

The ten synthetic cases comprise single points at .01, 1, 100 and 10 million
metres; paired points at 100 m depth with .001 or 1,000 m separation; a two-point
false-pair intersection; a three-point false common intersection; a .2 m
selector-boundary pair; and an origin coincident with its aim point. See the
README for exact construction, precision, acceptance, and query contracts.

## Comparison results

Nominal rough scale; entries are **three-query passes**, including synthetic
false consensuses. The fourth column pair gives attempts/recoveries; none of
these recoveries exceeded the anchor truth error envelope.

| Rule: slope, min–max m, angle | Ordinary /1,800 | Boundary /4,560 | #172 /74 | Synthetic /10 | Fourth attempts/recoveries |
|---|---:|---:|---:|---:|---:|
| tiny: .001, .01–4, 90° | 613 | 1,057 | 12 | 6 | 4,755/15 |
| small: .01, .25–32, 90° | 1,437 | 2,799 | 23 | 6 | 2,178/243 |
| medium: .03, 1–128, 90° | 1,788 | 3,017 | 0 | 6 | 1,632/850 |
| wide: .1, 4–512, 90° | 1,720 | 2,520 | 0 | 6 | 2,197/1,004 |
| equilateral: .03, 1–128, 60° | 1,792 | 3,225 | 0 | 6 | 1,420/555 |
| open: .03, 1–128, 120° | 1,785 | 2,820 | 0 | 5 | 1,833/1,086 |
| low floor: .03, .01–128, 90° | 1,791 | 3,013 | 0 | 6 | 1,633/808 |
| low cap: .03, 1–32, 90° | 1,430 | 2,461 | 0 | 6 | 2,546/657 |

Across **all** rules/rough scales: 43,200 ordinary trials gave 36,550 passes;
109,440 boundary trials gave 62,274; 1,776 #172 replays gave 181; 240 synthetic
trials gave 135. Official false consensus: **0**. Synthetic false consensus:
**25**, comprising 23 contracted-triangle witnesses and two close-point cases.
All 154,656 trials used 519,460 modeled observations (463,968 mandatory plus
55,492 corrective). There were 15,272 recoveries and zero wrong recoveries.
These totals mix deliberately different rules; they are not an accuracy metric.

### Detailed medium-rule audit, nominal scale

| Family | Total | Pass | Forward failure | Conditioning failure | Miss failure | Invalid | False consensus | Fourth attempts/recoveries | Queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Ordinary | 1,800 | 1,788 | 11 | 0 | 1 | 0 | 0 | 12/9 | 5,412 |
| Boundary | 4,560 | 3,017 | 1,392 | 0 | 151 | 0 | 0 | 1,543/811 | 15,223 |
| #172 | 74 | 0 | 74 | 0 | 0 | 0 | 0 | 74/29 | 296 |
| Synthetic | 10 | 6 | 0 | 1 | 2 | 1 | 1 | 3/1 | 33 |

The #172 recovery split is 11/14 original ordinary cases and 18/60 original
adversarial cases; all 74 fail the initial medium triple.

Statuses above are exclusive. Pairwise disagreement flags occur in 12 ordinary,
1,543 boundary, 74 known and two synthetic cases; all also violate miss/forward
checks. There are another 18 boundary conditioning flags behind a primary
forward status. There are no non-finite failures; the invalid synthetic has an
undefined direction because O equals the selected point.

Hidden selection partitions, ordered O/A/B (letters denote identity equality):

| Family | AAA | AAB | ABA | ABB | ABC |
|---|---:|---:|---:|---:|---:|
| Ordinary | 1,788 | 5 | 5 | 2 | 0 |
| Boundary | 3,017 | 624 | 547 | 342 | 30 |
| #172 | 0 | 0 | 49 | 25 | 0 |
| Synthetic | 7 | 0 | 2 | 0 | 1 |

AAA includes the invalid and ill-conditioned synthetic observations; a hidden
identity match does not imply usable geometry. Machine summaries label each
identity by its first probe index: AAB appears as `002`, ABA as `010`.

Ships versus surface elements: ordinary ships pass 1,672/1,680, recover 7/8;
the engine passes 116/120, recovers 2/4. Boundary ships pass 2,572/3,840, recover
675/1,268; the engine passes 445/720, recovers 136/275. The engine is only one
surface-element structure, not broad evidence for all possible surface targets.

Accepted ordinary anchor error: median **.03458 m**, maximum **232.1093 m**;
boundary: median **.06148 m**, maximum **234.9306 m**. The largest absolute errors
are long-range samples; one-percent conditioning is not centimetre accuracy.
Across every rule, zero accepted same-selection reconstructions exceeded their
E; the maximum error/E ratio was **.753553**. Maximum measured direction sine
error **2.70266e-6** was below **epsilon = 3.17424e-6**. This corroborates the
chosen finite-precision allowance on these data, not a universal error theorem.

### Distance, scale and clamps

Medium nominal passes at rough distances 10/100/1,000/10,000/100,000 m:
ordinary **356/359/355/358/360**, each out of 360;
boundary **675/544/490/554/754**, each out of 912. Fourth recoveries by distance
are ordinary **1/1/5/2/0**, boundary **80/232/257/242/0**.
At rough multipliers .5/1/2, ordinary passes **1,792/1,788/1,772**;
boundary **3,220/3,017/2,906**; #172 **16/0/0**. A centre-distance estimate can
substantially underestimate selected-point range near a large target.

The supported starting family is **.015–.03 times rough distance**, with a
**1 m floor, 128 m cap**, and **60° or 90°** probe angle. The .015 endpoint is
measured by the medium rule's .5 estimate multiplier, not an extra tuned rule.
These are experimental bounds for this precision/range envelope, not universally
optimal constants. The measured 1 m floor avoids conditioning failures seen
with .15–.3 m probes near large targets. A 32 m cap loses all 360 ordinary
100 km samples; 128 m retains them. The 10-million-metre synthetic still fails,
as it should under a hard cap. The wide rule increases ordinary failures from
12 to 80 and boundary failures from 1,543 to 2,040 through more switching.
Slope/floor/cap all differ in that comparison, so it does **not** isolate a
universal maximum-spacing switching threshold. The low-cap/floor controls
isolate those bounds within the medium rule.

Triangle shape matters to boundary coverage: 60° has more initial passes;
90° recovers more after one inward probe. 120° has fewer initial passes and the
additional close-point false-consensus mechanism below. None provides a proof
of hidden-point identity. No rule uses target names or macro identity.

## Failure mechanisms inspected

The ignored `examples.json`, `inspected.json`, and `report.txt` preserve origins,
selected identities, every pair's distances/miss/envelope, and exact-direction
controls. IDs below are A2 sample IDs; rule and estimate multiplier disambiguate
trials. Exact-direction controls retain the observed hidden selections and remove
angular quantization; they do not replace the binary32 selector.

- **Selector switching / backward closest approach:** medium nominal sample 1,
  Xenon engine, selects [3,0,0]. O/A distances are approximately .028 and −.916 m,
  while A/B reconstructs about 210 m away. O/A misses by .403 m against a
  4.91e-6 m allowance. Boundary sample 1800 and original #172 sample 6360
  (historical ID 885521) show the same mechanism; the latter has an O/A distance
  of −7.265 m on A's ray. All retain forward failure with exact directions.
  These are model limitations under different hidden selections, not non-finite
  arithmetic or the old scorer. Near-centre samples need not be plausible
  combat encounters; no box-based invalidation or gameplay prevalence is assumed.
- **Forward but skew / conflicting pair estimates:** ordinary fighting-drone
  sample 649 selects [0,0,2]. O/A estimates about 999 m; the mixed O/B pair
  about 1,146 m, with 1.547 m miss versus .00745 m allowance. Exact directions
  still fail miss. Boundary sample 4009 at estimate factor .5 similarly has
  1.93–2.07 m mixed-pair misses. The third ray detects a false two-ray solution.
- **Pure two-ray false intersection:** synthetic 6440 gives O/A an essentially
  zero-miss intersection near 100 m, while O/B intersects near the real 50 m
  point. A/B misses by 1.341 m (allowance .000396 m). Both miss and disagreement
  reject it, including under exact directions. Checking O/A alone would fail.
- **Poor conditioning despite one selected identity:** tiny sample 0 has 1 cm
  probes and ray sines about 4.58e-5; its distance envelope is tens of metres at
  roughly 212 m true range. Low-floor sample 240 at factor .5 has .15 m probes
  around a roughly 300 m point and pair envelopes near 3.94 m. Exact directions
  do not overcome the declared observation uncertainty. The 10-million-metre
  synthetic 6437 has sine about 1.14e-5 with a 128 m cap: quantized reconstruction
  is 11.185 million m with a multi-million-metre envelope. It fails safely.
- **Undefined direction:** synthetic 6443 puts O on the aim point; the anchor
  query is invalid. No fourth query is attempted. This is a deliberate invalid
  input control, not a discovered non-finite official failure.
- **Exact deceptive three-point consensus:** synthetic 6441 selects [0,1,2]
  yet all three pairs agree near 100 m; O's real point is 50 m away. Medium
  nominal error is **49.9995 m** versus E **.01554 m**. Exact directions still
  pass. Let O=0, X=(0,0,100), and A/B be the lateral probes. Authored points
  `P_i=(O_i+X)/2` lie on each probe's ray to X. Each probe selects its own
  nearest point for the tested triangle angles; all three rays nevertheless
  converge on X, which is not an authored point. This is an information limit,
  not fixable by tightening a finite-precision tolerance. Of 24 layouts/scales,
  23 pass this witness; tiny/.5 rejects for conditioning only.
- **Finite-precision deceptive close points:** open-angle synthetic 6438 has
  two points only .001 m apart at 100 m. At estimate factors 1 and 2, [0,0,1]
  passes with errors **.013118/.008931 m**, exceeding E **.012695/.006370 m**.
  Exact directions fail miss: quantization moves a small real skew inside the
  acceptance allowance. This is a distinct, tolerance-dependent false consensus;
  do not fold it into the exact contracted-triangle counterexample.

## Fourth probe and conclusion

**Keep the inward fourth probe as an experimental candidate:** nominal medium
recovers **9 ordinary + 811 boundary + 29 known = 849 official cases** in
1,629 official attempts, with zero wrong recoveries here. Including synthetic,
850/1,632 recoveries bring passes from 4,811 to 5,661 at 20,964 total queries
instead of 19,332. The one already accepted synthetic false point remains.
This is a substantial recovery on the deliberately difficult boundary set,
not evidence of a gameplay benefit rate. It earns further evaluation, not
production adoption.

Recovered medium cases comprise 736 ordinary/boundary forward failures and 84
ordinary/boundary miss failures plus 29 historical forward failures; no medium conditioning-only
case recovers. At the cap the outward probe cannot increase the baseline, and
one new ray cannot repair an unresolved retained O/A or O/B pair. Do **not**
retain the outward branch for the supported medium candidate on this evidence;
its implementation remains in the research comparison to expose that result.
Remaining failures include 641 boundary forward failures, 43 boundary misses,
46 boundary conditioning failures, two boundary forward failures originating
from miss, three ordinary failures and 45 historical failures. One closer
probe cannot always replace both switched rays, or obtain sufficient baseline.

**Three-ray consensus remains technically useful as a bounded predictive
candidate, not as a reliable hidden-point identifier.** Retain forward/finite,
all-pair miss, all-pair reconstruction agreement and angular/error-envelope
checks. Start further comparison with the .015–.03 scaled, 1–128 m clamped,
60°/90° family. The evidence supports these experimental choices within the
sampled precision/range regime; it does not establish universal optimal bounds
or compatibility with every future DLC/mod geometry. The exact synthetic
counterexample explicitly demonstrates why current official zero false counts
cannot establish that guarantee.

Unresolved: engine-native direction precision and coordinate-frame errors,
a suitable runtime rough-distance source, moving targets/query coherence,
the acceptable geometric error budget, and the downstream consequences of
both large long-range error and false common points. **#173 must validate the
pitch/arc scorer before any ENGAGEABLE accuracy assessment.** No such assessment
or product acceptance decision is made here. No live-game reset is needed for
these offline research files.

Validation: complete simulation plus numerical/representative audit,
`./scripts/validate.sh`, and `git diff --check`. The frozen helpers were unchanged;
no shared-helper test changes were needed. Reproduction commands and ignored
output locations are in the README.
