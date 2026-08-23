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
