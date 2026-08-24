# Testing and experiments

## Promote evidence carefully

Record a live result with X4 version, UI Extensions version, active mods, ship
and bridge, target kind, save context, date, and relevant log lines. Promote it
to `live-tested` only after reproduction. A user report remains experimental.

## Minimum live matrix

| Area | Test |
|---|---|
| Chair resolution | Sit in each bridge family; record `gunnercontrol` and enclosing ship. |
| Frame/Esc | Enter Watch; verify Esc returns to the console rather than a vanilla menu. In collapsed Engage, verify Esc expands its browser. |
| HUD/ticker | Verify normal HUD suppression separately from transient Messages/notifications. |
| Camera | Verify the selected physical turret remains the external target view while moving. |
| Bracket clicks | In Watch and collapsed Engage, test a new bracket, the already-current bracket, and a pending/non-targetable bracket; verify the soft target and menu phase after each automatic close. |
| Group labels | Compare directional labels and opaque fallbacks against one asymmetric L/XL ship macro. |
| Whole target | Engage a hostile ship/station hull and verify AI-owned aiming/firing/legal attack behavior. |
| Non-hostile target | Select neutral, friendly, and other player-owned objects; verify they are selectable but normal autoassist refuses illegal fire. |
| Surfaces | Test engine, turret, shield, and station-module surfaces independently. |

Do not represent HUD/ticker suppression, camera focus, or firing as verified
without a dated live result. Do not modify persistent notification settings as
part of these experiments.

## Method note 2026-08-04

Black-box probing produced two confidently wrong conclusions in the same
session: a silent `onHotkey` probe was read as proof of no input delivery (it
only proved no bindings existed), and `playerControls` was named as the
discriminator for `Esc` (it is not). Reading the shipped Helper property
documentation resolved the actual mechanism in one search. Source order matters:
read the shipped source before designing a probe, not after.

## Negative result 2026-08-11: a passive capture cannot attribute fire to a turret

X4 9.00, Test Lab observability logger
`testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_observe.xml`.
One ~10 minute free-play session on the player ship "Ray" (14 turrets, ids
`0x6c2bc`-`0x6c2cf`): 622 STATE samples and 7252 per-turret SOLUTION samples to
`debug.log`. n=1 ship, n=1 session.

The capture did not answer the behavioural question it was built for, and the
design cannot answer it, for two structural reasons rather than sampling ones:

- The "was it hit, by whom" signal it polled, `lastattacker`, is SHIP-scoped —
  no turret id ever appeared (see the attacker-attribution record in
  `ui-lua-menu-camera.md`).
- The aim-direction signal it polled, `$turret.rotation`, is STATIC — the
  mounted base orientation, one constant value per turret for the whole session
  (see the `$turret.rotation` record in `md-ai.md`).

With no per-turret hit signal and no per-turret pointing signal, nothing in a
mixed free-play capture separates the contribution of one turret, or one turret
MODE, from the rest. A third confound compounded it: the sweep enumerated only
`turrets.operational.list`, which excludes missile turrets, leaving an
unmeasured emitter that could account for hits.

Design rule that follows: any experiment intended to establish per-turret-mode
behaviour must be CONTROLLED — isolate by construction so only one class of
turret can possibly be firing (zero turrets in the competing mode, pilot idle so
the main guns are silent, missile turrets accounted for) rather than capturing a
mixed engagement and trying to disambiguate afterwards. Do not rebuild passive
observability expecting attribution to fall out of it.

Amended 2026-08-23 — this narrows the lesson, and the narrowing matters: the
failure is specific to POLLING, not to attribution. A shipped-source spike found
that MD exposes per-turret firing through event payloads rather than property
reads. `event_weapon_fired` names the weapon and, paired with
`bullet.launcher`, gives per-shot bore direction (records in `md-ai.md`). A
verified ordinary-projectile `event_object_attacked_object` payload may name the
turret, but `hitbymissile` instead named the launcher ship in the 2026-08-23
capture; never assume per-turret hit attribution across kill methods. There is
no per-turret current-target property anywhere in the 9.00 surface — selection
runs in an engine-side "shoot controller" that scripts write to and never read
back. So the corrected instrumentation rule is to LISTEN, validate each event's
runtime payload, and isolate by construction. A firing event names the turret
but not the MODE that chose the target, so mode-level questions still need a
scenario where only one mode can be acting.

## Live run 2026-08-04

X4 9.00 Steam, Windows 11 with WSL2, extension `x4_gunnery_control` build marker
`2026-08-04-lifecycle-1`, evidence from the game's own `debug.log`.

- The compact Engage frame held its phase for 323 seconds untouched (game time
  242641.00 to 242964.03) and was lost only when the Map was opened deliberately.
  This contradicts the earlier assumption that the compact frame loses ownership
  shortly after creation; do not plan around that assumption without re-testing.
- The engagement rollback path (`restored directed group`) fired exactly once on a
  failed transition. That acceptance criterion already passes.
- The player's own ship is selectable as an engage target. This is a defect; it should
  be excluded from target enumeration.
- The native "External Target View activated" notice reappears because the session is
  recreated on every Map close, which re-activates the turret camera. Suspect redundant
  camera activation before suspecting the notice itself.

## Negative masking fixture 2026-08-11: port-side target did not mask port-side turrets

X4 9.00, player-owned Boron Ray, Test Lab scenario
`issue-1-on-solution-masked-clear-r1`, one session on 2026-08-11. The exact
selected group was raw `group_front_up_left`, members `0x204df21` and
`0x204df32`. Target A spawned 3 km forward, 1.2 km port and at hull level;
target B used the same range/bearing at 1.2 km elevation; C was the elevated
15 km range control.

This did NOT stage LINE OF FIRE BLOCKED. Against A, the MD predicate reported `los_ex=1` and
`inrange=1` for both selected turrets. `0x204df21` hit A three times during the
initial 11-second hold. `0x204df32` did not fire in that interval, but later hit
the unchanged A when selected C was OUT OF RANGE. The late hit proves A was a
valid shot for that turret too; the initial asymmetry was consistent with slew
time, not masking. The owner independently reported that A was visibly not
masked.

Controls worked: both selected turrets eventually hit elevated B; both reported
`inrange=0` against C at about 15 km and fell back to A. Do not use this run as
evidence for or against whether `check_line_of_sight excludeself="true"`
detects own-hull masking.

Design corrections: put a candidate across the hull from the selected mounts,
and capture a second automatic snapshot only after the same target has remained
selected for at least 20 seconds. A short no-hit window is not a valid masking
signal on a traversing turret.

**Follow-up negative: cross-hull placement also did not mask.**

The immediate follow-up in the same X4 9.00 session used scenario
`issue-1-on-solution-cross-hull-r2`: A was moved from 1.2 km port to 1.2 km
starboard, still 3 km forward and at hull level. This also did NOT stage
LINE OF FIRE BLOCKED. Immediate and settled (20-second) snapshots both reported `los_ex=1`
and `inrange=1` for exact selected members `0x204df21` and `0x204df32`, and
both turrets struck A roughly 15--19 seconds after designation. The owner also
reported that A was visibly not masked.

Do not infer own-hull masking from a ship-local point that merely lies across
the hull in one projection. The next general obstruction test should use a
separate, named capital ship centred between the firing ship and target. That
can establish the externally blocked-line-of-fire case, but it still cannot
answer whether `check_line_of_sight excludeself="true"` detects the firing
ship's own hull.

## Live masking fixture 2026-08-11: independent obstruction and range controls

X4 9.00, player-owned Boron Ray, Test Lab scenario
`issue-1-on-solution-blocker-r3`, one session on 2026-08-11. Exact selected
group `group_front_up_left` contained members `0x204df21` and `0x204df32`.
The fixture placed a player-owned Argon XL carrier 2 km forward as an
intervening obstruction; hostile A was centred behind it at 4 km, clear-sky B
was 4 km forward and 1.2 km up, and C was 15 km forward and 1.2 km up.

Immediate and settled snapshots agreed for both selected turrets:

- A: `los_ex=0`, `inrange=1` -- LINE OF FIRE BLOCKED only.
- B: `los_ex=1`, `inrange=1` -- clear and within weapon range. Both selected
  turrets produced attributed hits on B.
- C: `los_ex=1`, `inrange=0` -- OUT OF RANGE only. Although C appeared nearly
  aligned with the carrier to the owner, the per-turret checks establish that
  neither selected member was masked.

This is live evidence that `check_line_of_sight excludeself="true"` can
distinguish an intervening ship obstruction for each exact selected turret,
independently of the shipped range predicate. It remains no evidence about
masking by the firing ship's own hull.

## Live missile-turret fixture 2026-08-23: guidance-aware direct-line policy resolved

X4 9.00, one process, controlled Test Lab revisions
`issue-65-remote-odysseus-e-r1` through `r6`. Every accepted fixture used one
player-owned Odysseus E roughly 500 km from Argon Prime's centre with an exact
census of 16 operational missile turrets: nine guided, seven dumbfire, and 160
missiles. All 16 groups were selected and directed at one named repaired,
hold-fire Xenon target.

R1 selected Xenon K turret surface `0x18c351` at roughly 2.1 km. All 16 direct
muzzle rays were own-hull-masked with `excludeself="false"`; 15 became clear
with `excludeself="true"`. Eight guided turrets emitted 16 attributed launches,
and impacts reached the designated surface and adjacent components. The seven
dumbfire turrets were all in CANNOT BEAR, so R1 settled the guided case only:
guided missile turrets must retain bearing/range but not require a direct ray.

R2 moved the clear-left Xenon K hull into dumbfire elevation limits. The UI
reported 14/16 ENGAGEABLE. Three dumbfire components launched 92 missiles:
M turrets `0x1836d2` and `0x1836d3` launched 24 each, and L turret `0x1836d4`
launched 44. Every one of the 92 delayed observations still found the exact
missile after 500 ms, intended target `0x1836d8`, at 421--819 m from the
Odysseus. For those firing turrets the direct muzzle ray was blocked when the
own ship was included and clear with `excludeself="true"`. This is live evidence
that the production predicate must ignore the firing ship's own hull for this
Odysseus/dumbfire loadout.

The first blocked control did not qualify: R2's Xenon K was so large that
targetable hull/components remained exposed around the Colossus; dumbfire
turrets launched and hit it. R3 replaced the K with a Xenon P, but a zero group
distance was treated as a missing optional value and placed the shooter at the
5 km default, beyond the target and blocker. R4 fixed placement with shared
nonzero absolute offsets (shooter 1 m, blocker 2101 m, target 4201 m), but the
Colossus mesh had real openings: the P was inside its outer silhouette while
four of seven dumbfire muzzle rays remained clear. R5 failed closed because the
guessed Asgard macro did not exist. Catalog extraction established the exact
macro `ship_atf_xl_battleship_01_a_macro` for R6.

R6 placed that broadside player-owned Asgard midway before the Xenon P. The
owner confirmed no part of the P was visible through or around the blocker.
The P was 4494 m from the Odysseus, and all seven dumbfire records were within
weapon range but returned `los_ex=0` and `muzzle_los_ex=0`. All nine guided
turrets also had blocked direct rays. The shipped UI predicate nevertheless
reported exactly 8/16 ENGAGEABLE: eight guided turrets could bear and remained
eligible; one guided turret was in CANNOT BEAR; all seven dumbfire turrets were
rejected by the retained external direct-line check. No blocked-lane firing was
needed because the exact per-turret rays and production ENGAGEABLE result
answered the predicate question directly.

Accepted scope: affirmative `ammo.macro.isguided` bypasses the direct ray while
retaining bearing/range. Unguided or missing-guidance missile ammunition keeps
the direct ray with `excludeself="true"`, which ignores the firing ship but
still rejects a solid intervening ship. This is live-tested for one vanilla
Odysseus E loadout, not a universal engine guarantee for every hull or modded
missile.

Instrumentation correction: FIRED events named each missile turret, but every
`method=hitbymissile` HIT event reported the Odysseus launcher ship with
`isturret=0`. Per-turret missile impact attribution through
`event_object_attacked_object.param3.{2}` is refuted for this kill method; keep
launch and impact attribution separate.

Operational corrections: remote Create is destructive replacement. A second
Create after teleport despawned the occupied shooter and crashed the game; the
UI now rejects that action. Also, an outer silhouette is not a valid obstruction
control when the physical mesh has holes. Require complete visual occlusion and
all exact muzzle rays blocked before permitting fire.

## Issue #67 Colossus r9 diagnostic 2026-08-24: useful evidence, false qualification

Experimental record; do not promote the arc or shoot-controller conclusions
without the clean follow-up. X4 9.00 (611726), UI Extensions 9.00, X4 Gunnery
Control 0.31, Test Lab 0.10, scenario
`issue-67-arc-barrel-two-phase-r9`, tested HEAD `b751b4f`. The player began on
a safe launcher in Two Grand, created the fixture remotely in Hatikvah's Choice
I, teleported to `ISSUE ARC-BARREL COLOSSUS E 1`, and used its physical gunnery
console. Evidence is the correlated game `debug.log` from the disposable save.

What this session proved or reproduced:

- Remote station equipment is not a locality or next-tick problem for the
  tested path. `apply_loadout object="$Module"` immediately produced exactly
  five modules, two `turret_xen_m_laser_02_mk1_macro`, four
  `shield_xen_m_standard_02_mk1_macro`, no missile turrets, and no engines.
  The 1 ms and in-system censuses matched. Together with r6 this is reproduced
  live evidence; the durable bounded result is in `md-ai.md`.
- The Colossus static loadout produced exactly two
  `turret_arg_m_beam_02_mk1_macro` and two
  `turret_arg_m_plasma_02_mk1_macro`, no other weapons or missile turrets. All
  four fired, and all four produced attributed hits on clear control A. This
  reproduces the r3 operational census and resolves the `_02_mk1` positive
  compatibility question.
- None of those four conventional turrets had a zero/degenerate
  `weapon.barrelposition`. The spawn/qualification values matched the earlier
  Behemoth measurements, then changed as the turrets trained. The exact #67
  zero-barrel premise is therefore a bounded negative for these macros; the
  one-session dynamic-value observation remains experimental.

The in-system qualifier nevertheless false-qualified attempt 1/8 at station
distance 5750 m, vertical offset -900 m, and roll 180 degrees. It logged
`root_splits=0` but accepted `module_clear_candidates=2`. Those two candidates
were plasma turrets against module `0x1789da`: each station-root origin and aim
pitch was below the -10 degree lower limit, while that DIFFERENT module's origin
and aim were both inside the arc. This was root-outside/module-inside, not the
required same-component origin-outside/aim-inside split. The timed test still
designated the station root, so the acceptance condition did not match the
object under test.

The A/B/C observations must remain separated:

- A was the valid clear control. At settled mark 2 all four were in range,
  inside the arc, externally clear, self-inclusive clear, ready, and firing.
  The hull refreshed from 0/4 to 4/4 ENGAGEABLE after roughly two seconds, but
  the five alternative surface rows remained at the 0/4 values computed in the
  page snapshot. No surface element was directly designated, so this is a
  suspected stale-snapshot UI defect, not evidence that the surface elements
  themselves were or were not engageable.
- B's station root was in range but below -10 degrees for all four turrets and
  its root rays were blocked. Across the 20 exact station-module probes, every
  self-inclusive muzzle ray was blocked. For every shooter turret, at least one
  module ray became clear with the firing ship excluded, isolating own-Colossus
  hull masking in the mod's geometry check. The two qualifying plasma/module
  pairs were also in arc and in range, making them clean candidates for a direct
  component test. B was not a clean engine-behavior result because the actual
  designation remained the below-arc station root. In the later
  `attackenemies` interval, 130 FIRED and 62 HIT events occurred while B was the
  selected/aimed object; every hit was on fallback A and none had `istgt=1`.
  That is consistent with CANNOT BEAR fallback and does not answer how X4 would
  handle the in-arc module's own-hull-masked path.
- C was in range and externally clear for all four, but below the lower arc
  limit; its self-inclusive rays were also blocked. It did not fire and remains
  a valid CANNOT BEAR control, not a line-of-fire discriminator.

Questions still open at the r9 checkpoint (question 2 is answered by the r11
follow-up below):

1. Can a deterministic station surface be placed so the SAME exact component's
   origin pitch is outside the generated arc while its hittable aim-point pitch
   is inside, with range and external line of fire independently clear? If no
   bounded search finds one, record a bounded negative rather than weakening
   the qualifier.
2. When an exact conventional turret and exact directly designated component
   are in arc and range, and `muzzle_los_ex=1` while `muzzle_los_self=0`, does
   X4 fire and hit that component or hold fire? The r9 module candidates make
   this the next clean test.
3. Does directing `set_turret_targets` at a station root cause any engine-side
   root-to-module selection, or is module engagement seen in vanilla solely the
   result of explicit AI-script retargeting? Test this separately from the
   direct-component masking case.
4. Why did A's surface-page snapshot remain 0/4 after the pinned hull refreshed
   to 4/4? Re-open/recompute and directly select one exact surface before
   classifying this as a UI bug.

Fixture rule: a qualifying component must be the component the timed action
actually designates. Keep the arc split and own-hull masking as independent
branches; a target with both CANNOT BEAR and a blocked line of fire cannot
decide which condition controls firing.

## Issue #67 r10/r11 follow-up 2026-08-24: conventional own-hull masking resolved

X4 9.00 (611726), UI Extensions 9.00, X4 Gunnery Control 0.31, Test Lab
0.10, branch `feature/issue-67-arc-barrel-fixture`. Evidence is the correlated
game `debug.log` from the disposable save. The accepted manual-designation run
used scenario `issue-67-direct-surface-mask-r11` and runtime build marker
`2026-08-24-testlab-manual-designation-1`.

### Why r10 was abandoned

The r10 direct-station-module fixture re-used the r9 station candidate, but its
post-teleport movement destroyed the useful external-ray distinction: an
unchanged settled control and a deliberately delayed post-warp measurement both
left all candidate station-module rays externally blocked. That is an
experimental result for the tested generated station instance, not a universal
station-warp/collision rule. Waiting longer did not have an evidence-backed
purpose. The next fixture therefore removed station movement entirely and used
four independently pre-positioned, stationary Xenon K candidates whose
operational surfaces could be enumerated after teleport.

### r11 qualification and manual interaction

The r11 Create census passed exactly: one player-owned Colossus E shooter plus
four repaired, held-fire Xenon Ks; four conventional shooter turrets (two
`turret_arg_m_beam_02_mk1_macro`, two
`turret_arg_m_plasma_02_mk1_macro`); no missile turrets, unrelated weapons, or
remaining defence units; all four K targets legally attackable. The in-system
qualifier scanned 140 operational target surfaces and 280 exact plasma/surface
pairs. It found 17 externally clear candidates and selected surface `0x1796eb`
(`XEN L Graviton Turret Mk1`) on `MASK CANDIDATE K 2 1` (`0x1796ce`) because
both exact plasma turrets satisfied all intended gates against that SAME
component:

- `0x179672`: origin/aim pitch `-0.168770/-0.168039` rad, range 3683 m of
  5500 m, `muzzle_los_ex=1`, `muzzle_los_self=0`, `mayattack=1`;
- `0x179673`: origin/aim pitch `-0.172767/-0.172005` rad, range 3598.5 m of
  5500 m, `muzzle_los_ex=1`, `muzzle_los_self=0`, `mayattack=1`.

Two attempts to automate designation were invalid fixture designs. Calling the
engagement bridge while Test Lab owned the external menu failed, and deferring
the same exact surface write until Gunnery regained ownership still produced
two `SetSofttarget` refusals. Those failures do NOT establish an X4 surface
targeting limitation: they bypassed the normal player interaction. The final
fixture only marked the exact root and surface. The owner then clicked Direct
control, the marked K root, and the marked surface; Gunnery accepted the exact
surface immediately and logged a distinct `action=operator_designated` before
observation began.

### Clean firing result

At both initial and settled (20.874 s) snapshots, the two selected plasma
turrets were in `autoassist`, `isreadytofire=1`, in range, inside their generated
arcs, externally clear, and self-inclusive blocked against the manually selected
surface. From designation through the settled snapshot the observer recorded
zero FIRED and zero HIT events. The independently refreshed Gunnery surface row
reported 0/2 ENGAGEABLE on every pinned update during the same interval.

This is the clean answer to r9 question 2 for the tested conventional turrets:
X4 held fire when the exact in-arc/in-range selected surface had an external
clear ray but an own-Colossus-hull-masked projectile path. The production
self-inclusive conventional line-of-fire gate agreed with engine behavior; no
#67 production line-of-fire change is warranted for this branch.

### Arc evidence and what remains open

The same 280-pair scan found exactly one origin-versus-hittable-aim boundary
crossing: plasma `0x179673` against Xenon K shield surface `0x17970f` on
candidate `0x179707`, with origin pitch `-0.174791` rad just outside the -10
degree limit and hittable aim pitch `-0.174418` rad just inside. It was in range
but externally blocked (`muzzle_los_ex=0`), so it cannot decide whether the
production origin-based arc gate under-counts a shot X4 would take. It does
prove the two points can straddle the generated limit on one exact component.

Still open for #67:

1. Reproduce a same-component origin-outside/aim-inside split with range and
   external line of fire clear, then manually designate that exact surface and
   observe the exact turret's fire/hit behavior. Use fresh independently
   pre-positioned candidates and a bounded search; one generated r11 coordinate
   is not yet deterministic.
2. Separately determine whether station-root `set_turret_targets` ever becomes
   an engine-side module engagement, or whether vanilla module attacks depend
   on explicit AI-script retargeting.
3. Separately reproduce the r9 A-page case where a hull refreshed to 4/4 while
   its surface rows retained 0/4. Recompute/reopen and directly select one exact
   surface before classifying it as a stale-snapshot UI defect.

Do not revisit remote/local station timing: r6 and r9 already reproduced the
exact remote module loadout synchronously. Do not revisit zero/degenerate
barrels for the tested `_02` macros or weaken the conventional line-of-fire
gate: those branches are resolved within their stated bounds.
