# Selected-target CLEAR LINE OF FIRE benchmark findings (#202)

Status: **OFFLINE**. Production MD unchanged since `cf459d0`, X4 9.00 build
611726 evidence base. Simulated query counts and Python run time are not X4
frame cost. There is no new LIVE evidence.

The model drift check against `md/x4_gunnery_control.xml` passes. All 9
deliberately wrong candidates fail. Benchmark integrity is **PASS**.

**Correction to `6daee59`.** MD loop counters are 1-based. Production's own
six-point loop indexes 1-based lists with `counter="$surfacei"`, so the
`$index gt 2` break keeps **two** station modules, not three. The cue comment
and `selected-target-line-of-fire.md` (two lines, 6 calls) were right. The
earlier "station cap drift" finding and the 9 / 126 station cost were wrong.
The new `three_modules` mutant now fails the benchmark if that error returns.

## What the earlier benchmarks established and missed

**#186 L6 (`607f2a9`, deleted since).** It passed 64/64 on synthetic box and
sphere scenes. It established the decision rules for the same-ray hierarchy:
target, then `.object`, then zone, plus X4's second ray. It also covered:

- the blocker categories;
- the wreck and absent-body states;
- guided missiles at 0 calls;
- at most 3 calls per pair.

It missed the following:

- **Own turret mesh.** The 2026-09-24 `XShapeFilter` correction came later. MD
  `excludeself=false` sees the firing turret's own meshes, so its BLOCKED rows
  could be self-hits.
- **Different method.** It scored a method production never shipped. Production
  declares the ship, element or nearest module, then the zone or firing ship,
  then the turret.
- **One point only.** It scored #184's recovered point. It never compared the
  centre, the `useaimtarget` probe and the six box points.
- **Origins.** Its origins were #185 predicted aimed muzzles, not the
  `barrelposition` element 0 that production reads. It had no parked, turning
  or multi-barrel origins.
- **No runtime pass behavior**, and no #60 or #202 witness.
- **Self-derived truth.** Its truth came from intersecting its own invented
  shapes.

**#184 and #185 reused here:**

- **Aim points.** 184 of 203 pristine 9.00 ships author no aim point, so
  `useaimtarget` falls back to the box centre. The Osaka,
  `ship_ter_l_destroyer_01`, is one of them.
- **Turret-element aim points.** Recomputed here from #184 `targets()`: 68 of 88
  authored turret-element aim points lie **outside** the element's
  collision-eligible box. Shield, engine and whole-ship points are all inside.
- **Endpoint layouts.** Official turret components, including mining and
  other non-combat components, have these numbers of `laser` endpoints:
  1 (30 components), 2 (66), 3 (1), 4 (2), 5 (11) and 8 (1). Missile turrets
  have 1, 2 or 4 `rocket` endpoints (2, 6 and 24 components).
- **#185 predicted muzzles are not used.** Production queries the current
  `barrelposition`.

## Coverage

The benchmark has 94 scenes. Six are unscored:

- a coincident-hit tie;
- a blocker in another zone's physics world;
- the membership of a wrecked module;
- a craft docked on the target ship, and one docked on a target module;
- a module destroyed after the pass fixed its module list.

| Group | Scenes | Covers |
|---|---:|---|
| Blockers and order | 22 | firing hull; own turret mesh; sibling turret, shield and engine; friendly and hostile ships; target hull, shield and engine; neighbouring element; unrelated station module, turret and shield; asteroid; wreck; destroyed without wreck; target before blocker; genuine miss; hit beyond the endpoint; tie |
| Membership | 28 | ship hull vs its elements and a docked craft; station nearest, second, third (outside the two-module cap), other, non-nearest, construction, wrecked, destroyed-mid-pass and single modules; docked craft; firing ship; own mesh; external blocker; no modules; both module-link hypotheses; station element vs its parent module, sibling and another module |
| Points | 18 | aim clear; first CLEAR at each of the six points; all seven blocked, self or miss; mixed; stop at first CLEAR; aim point outside box; hollow centre; only the centre clear; no authored aim; two aim points |
| Origin | 9 | parked; turning; settled; retargeting away; two resting yaws; 2-, 5- and 4-endpoint weapons whose non-first barrel is clear |
| Weapon | 10 | beam; projectile; flak; unguided own hull; cluster carrier; guided through the hull and past an external blocker; unloaded; missing guidance; unknown class |
| Uncertainty | 3 | zones differ; lost frame; cross-zone blocker |
| Negative controls | 4 | #69 NEAR all-blocked; parent not the selected element; own hull kept; guided is not a physical path |

Evidence for the stated arrangements: 3 LIVE, 8 native inference,
2 shipped-source and 81 hypothetical. The classification rules themselves are
native inference plus the #202 design. Only the LIVE subset can support an X4
accuracy claim, and it has 0 wrong answers.

The historical witnesses cover 4 hypotheses × 14 turrets for #202 and
3 hypotheses for #60. `runtime.lua` adds 17 checks on the real code: 13 CODE, 2 SPEC and 2 NOTE.

## Results

Definite failures against the #202 rules:

- **FAIL — missing missile guidance becomes unguided,** in every strategy.
  Production checks only for absent ammunition. A loaded macro whose
  `.isguided` is false or null takes the physical path. X4's own gate reads a
  guidance byte that defaults to unguided, so this matches native behavior.
  #202 nevertheless requires UNKNOWN. Shipped-source work must show whether MD
  can tell a missing guidance value from false. The official
  `missile_story_dumbfire_light_mk2_macro` has no usable guidance value.
- **FAIL (SPEC, task 3 pending) — the display ignores GUIDED.** It shows
  `1 / 3` where the agreed value is `2 / 3`.
- **FAIL (SPEC, task 3 pending) — the display uses a non-ASCII dash.**

Correct YES and NO answers are counted separately. `seven` and `lazy` give
identical statuses in every scene.

| Strategy | Correct CLEAR | Correct BLOCKED | Correct UNKNOWN | GUIDED | Excess UNKNOWN | Wrong CLEAR | Wrong BLOCKED |
|---|---:|---:|---:|---:|---:|---:|---:|
| current | 17 | 43 | 19 | 3 | 5 | 1 (guidance) | 0 |
| seven | 28 | 35 | 15 | 3 | 6 | 1 (guidance) | 0 |

The expected values differ per strategy because each strategy tests different
lines. The runtime checks all pass:

- the pass runs while an IN RANGE request is outstanding;
- it checks one turret per request and sends no IN RANGE traffic;
- duplicated replies, replies after a timeout and replies after the session
  ends are ignored;
- no request is sent while the game is paused or while an engaged session is
  outside direct control;
- a membership change drops the pass in flight;
- the last complete result stays visible while the pass refreshes;
- an old selection's result is discarded on the next update;
- a vanished component completes the pass as UNKNOWN.

One observation (NOTE): `Clear.text` itself does not check whether a result is
still current. Until the next `Clear.run` update, a caller that passes the old
target id still receives the old result. Both displays pass the current
selection id, so this is at most a one-update window. That is plausibly
invisible, but it has not been checked LIVE.

Second observation (NOTE, newly found): a timeout discards the whole pass and
the next pass restarts at the first turret. One turret whose MD request never
answers therefore keeps both displays on "scanning" indefinitely, although the
other turrets answer. The #202 LIVE run recorded no timeouts, so this is
OFFLINE only.

## How the seven-point scan differs from the current centre ray

**Where it recovers.** `seven` returns CLEAR where `current` returns BLOCKED or
UNKNOWN in these cases:

- the aim point is clear;
- the first CLEAR is at any of the six points;
- the centre is hollow;
- the aim point lies outside the element's box;
- there is no authored aim point;
- the nearest of two aim points is occluded;
- a stop at the first CLEAR occurs after UNKNOWN points.

**New regression boundary.** In `only-centre-clear`, `current` returns CLEAR and
`seven` returns BLOCKED. When an element authors an aim point, the scan never
tests the box centre. Adding the centre as an eighth point would cost at most
3 calls. It would make the scan never worse than the current method from the
same origin.

**The aim probe cannot be classified.** Its endpoint is unknown, so a failed
probe adds nothing to BLOCKED. In `mixed-unknown-only` the aim line really hits
a blocker, but the result is UNKNOWN. That is correct under the
no-invented-endpoint rule, and it is a coverage loss.

**Lazy classification costs less.** Classify only after all seven fail, and
stop at the first BLOCKED. The statuses are the same. A clear at point *k*
costs *k* calls rather than 1 + 3(*k* − 1). All seven blocked costs 9 calls
rather than 19.

**Limits of both methods.** A parked or turning origin, and a first barrel
blocked while another barrel is clear, give BLOCKED or UNKNOWN for both. The
tested-path answer is correct in each case, yet the target is reachable.
Whether the next pass fixes this depends on the turret having turned by then.

## Historical reproductions

**#202, selected Osaka element `0x17c090`.** The Ray's 14 turrets are
12 `turret_bor_m_railgun_02_mk1_macro` (one `laser` endpoint) and
2 `turret_bor_l_disruptor_01_mk1_macro` (three endpoints, 0.67 m authored
spread). The owner's local 2026-09-25 `debug.log` records these identities. It
comes from a different X4 session with the same fixture id and the same
persistent Ray component ids, and is not retained. The hitting weapon
`0x3e59e` is a railgun.

The current model reproduces the observation under every hypothesis: **0/14 in
42 calls**, every centre line giving Q(T) false, Q(Z) true and Q(W) false.

| Hypothesis | seven | eager calls | lazy calls | Evidence |
|---|---|---:|---:|---|
| Centre occluded, aim point clear | 14/14 | 14 | 14 | hypothetical for 11 turrets |
| Aim clear for the 3 Test Lab turrets, y75 clear for the others | 14/14 | 124 | 58 | 3 LIVE (see caveat), 11 hypothetical |
| All seven occluded for the other 11 | 3/14 | 212 | 102 | 3 LIVE (see caveat); the rest is an unexplained limitation |
| Alternate barrel | 0/14 | 266 | 126 | refuted for the 12 single-endpoint railguns, including the hitting weapon; possible for the 2 disruptors only |

The first-probe LIVE fact recovers at least **3/14**, with one caveat. The
issue records those Test Lab muzzle-to-aim-target checks as clear, but not
their `excludeself` setting. If they used `true`, the firing hull was ignored,
and the proposed `excludeself=false` probe could still be blocked. The remaining
11 turrets
need the compact per-turret logging planned in #202 task 2. The element's type
(turret, shield or engine) was not recorded. `0x17c097` at 12/14 is not
modelled.

**#60, Xenon Defence Platform.** The legacy root `useaimtarget` probe
reproduces 0/14 under all three hypotheses. The current module-declared method
gives:

| Hypothesis | current | root_zone | root_ship |
|---|---|---|---|
| Centre gap | CLEAR | CLEAR | CLEAR |
| Module-to-root link returns null | CLEAR | UNKNOWN | UNKNOWN |
| Cross-zone | UNKNOWN (zone) | UNKNOWN | UNKNOWN |

None of these is the proven historical cause. A single LIVE diagnostic
distinguishes them: root-declared versus module-declared rays on one explicit
module-centre endpoint, with `weapon.zone` and `target.zone` logged.

**Station hull decision.**

- **current (module-declared)** does not depend on the link. It returns UNKNOWN
  for a hit on another module, for modules beyond the nearest two to the
  firing ship, and for external blockers. Modules are ranked from the firing
  ship's position, not the turret's, so the tested pair can miss the module
  nearest a given turret.
- **root_ship** recovers other and non-nearest modules when the link works. It
  never returns a false answer.
- **root_zone** additionally reports external blockers. However, it returns a
  **false BLOCKED** if a module's parent walk skips the station and reaches the
  zone directly (`station:link-zone`).

Declaring the root therefore needs the LIVE link check first. If it is adopted
before then, keep the firing-ship blocker.

**Negative controls.** All hold. The live #69 NEAR case with a Terraformer
between the turret and the target is BLOCKED in both strategies. The mutants
fail as intended:

- `declare_parent` (parent or sibling mistaken for the selected element);
- `excludeself` (own hull dropped);
- `guided_clear` (guided launch treated as a straight path);
- `three_modules` (the earlier cap mistake);
- `unloaded_unguided`, `no_classify`, `no_self_query`, `first_blocked_stops`
  and `zone_skip`.

## Query cost (simulated `check_line_of_sight` calls)

| Case | current, per turret / 14 turrets | seven eager | seven lazy |
|---|---|---|---|
| First line clear | 1 / 14 | 1 / 14 | 1 / 14 |
| All seven blocked | 3 / 42 | 19 / 266 | 9 / 126 |
| All seven own-mesh | 3 / 42 | 19 / 266 | 19 / 266 |
| All seven miss | 2 / 28 | 13 / 182 | 13 / 182 |
| Station, no module line clear | 4 / 56 | same as current | same |
| Station, worst case (both lines own ship or own mesh) | 6 / 84 | same as current | same |
| Median over ray-issuing scenes | 3 | 13 | 7 |

- **LIVE context from the #202 record, not measured here.** A 42-call pass had
  a median of 184 ms and IN RANGE sweeps took 371–380 ms. The pass takes one
  frame per turret, so its elapsed time is not ray cost. A worst-case pass of
  266 calls, at up to 19 calls in one MD event, needs LIVE frame measurement.

## Remaining gaps (LIVE or shipped-source only)

1. Whether a station module hit reaches the root: the `null` or `zone`
   hypotheses, and the #60 cause.
2. The type of `0x17c090`, and which of the aim or six points clear for the 11
   turrets without LIVE evidence.
3. How often the first hit is the firing turret's own mesh (UNKNOWN self).
4. Whether a muzzle inside its own hull produces a hit, and in what order the
   engine reports near-coincident hits.
5. Blockers in another zone's physics world.
6. Whether a wrecked module, or a craft docked on the target, counts as a
   target member. Both are hull descendants. A hit on a docked craft reads
   CLEAR, and #202 does not say whether it should.
7. Whether MD can tell missing missile guidance from unguided.
8. The effect of turret motion between its check and the display, and of
   multiple resting yaws.
9. Frame cost of the worst-case seven-point pass.
10. What MD does with a module that dies after the pass fixed its module list.
11. The `excludeself` setting of the earlier Test Lab aim-target checks.

**Already LIVE-backed:**

- #202: 0/14, 42 calls, 11 hits and 3 clear aim probes (issue record; the log
  is not on GitHub);
- #60: the 0/14 contradiction (issue record; the raw log was not retained);
- #69 FAR: a parked origin self-blocked, then a fired hit;
- #69 NEAR: the negative control;
- #69 MID: the six-point fallback corrected an engine false negative;
- #66 R1: guided missiles launched through their own hull mask.

Everything else here is OFFLINE decision logic over stated arrangements.
