# Issue #69 current evidence boundary

This focused record supersedes older Issue #69 root-cause wording in `md-ai.md`
where that wording conflicts with the findings below. Keep the older entries as
investigation history until they are consolidated, but do not treat
"single-vs-multiple aim points" or target-hull masking as established causes.

## ENGAGEABLE can remain false while the same turret hits the exact designated component

- X4: 9.00
- Status: live-tested
- Source: controlled Test Lab investigation using fixture
  `issue-69-engine-straddle-r1`; correlated `FIRED`, `FIREDRAY`, LOSPROBE, and
  `HIT` records in the current Issue #69 workstream.
- Live test: yes — controlled Issue #69 sessions on 2026-08-27.
- Finding: the tested Paranid L plasma turret can fire at and hit the exact
  designated Argon L all-round engine while ENGAGEABLE remains `0 / 1` and the
  tested MD `check_line_of_sight` queries return false. Correlated hit evidence
  includes `hitcomp == aimed` and `istgt=1`, so the observed success is not
  merely a near miss or an unrelated parent-hull hit. This establishes a real
  disagreement between the tested MD LOS predicate and a successful projectile
  path. It does not establish why the two differ.

## The committed `look_at_bbox` arc change is not the Issue #69 solution

- X4: 9.00
- Status: live-tested
- Source: fixture `issue-69-engine-straddle-r1`; branch production predicate in
  `md/x4_gunnery_control.xml`; prior Issue #69 live records in `md-ai.md`.
- Live test: yes — 2026-08-27.
- Finding: the target's `look_at_bbox` pitch can be inside the authored turret
  elevation band while production ENGAGEABLE remains false and the turret later
  fires/hits the exact component. Therefore the committed bounding-box arc
  orientation does not resolve the residual Issue #69 under-report. Whether
  `look_at_bbox` is useful as a separate approximation is a distinct design
  question; it must not be described as the demonstrated #69 fix.

## Multiple authored aim targets are not established as this residual's cause

- X4: 9.00
- Status: shipped-source boundary plus source-audit correction
- Source: `common.xsd` documentation for `useaimtarget`; current Issue #69 source
  audit of the tested engine component. The handoff that established this
  correction did not include the unpacked component path, so record that path
  when the source audit is next reproduced.
- Live test: no — this is a source-interpretation boundary, not a runtime claim.
- Finding: the tested engine component was found to contain exactly one authored
  `aimtarget`. The prior claim that this specific residual is proven to result
  from X4 choosing among multiple authored engine aim targets is therefore not
  supported. XSD wording about an object's "aim targets" also does not expose
  the native turret controller's selected firing point or provide an enumerable
  script-visible firing-solution set. Treat runtime point selection as unknown
  unless separately established.

## `excludeself=true` false does not identify the blocker

- X4: 9.00
- Status: live-tested plus shipped-source boundary
- Source: Issue #69 LOSPROBE runs; `common.xsd` `check_line_of_sight` interface.
- Live test: yes — 2026-08-27.
- Finding: LOS remained false with `excludeself=true`, which eliminates firing-
  ship self-collision as the sole explanation. It does not prove that the
  target's parent hull is the blocker. Exposed source does not document
  first-hit acceptance, parent-vs-child collision identity, LOS collision
  masks/meshes, projectile participation, or arbitrary `targetoffset`
  acceptance semantics. Do not infer the blocker identity from this boolean
  alone.

## Current durable boundary

The exact cause of the MD-LOS/projectile disagreement remains unresolved.
Hypotheses and the active target-anchored-endpoint / post-projectile
experiments belong in GitHub Issue #69 and the live-test log until a decisive
run establishes them. Do not promote an MD API limitation, projectile
self-intersection, parent/child collision semantics, or target-offset behavior
into this KB before that evidence exists.
