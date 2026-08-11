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

Amended 2026-08-11 — this narrows the lesson, and the narrowing matters: the
failure is specific to POLLING, not to attribution. A shipped-source spike found
that MD does expose per-turret attribution, as event payloads rather than
property reads. `event_object_attacked_object` carries the firing weapon in
`param3.{2}`, and `event_weapon_fired` paired with `bullet.launcher` gives
per-shot bore direction (records in `md-ai.md`). There is no per-turret
current-target property anywhere in the 9.00 surface and there was never going to
be one — selection runs in an engine-side "shoot controller" that scripts write
to and never read back. So the corrected instrumentation rule is to LISTEN, not
to sample. Isolation by construction is still required on top of that: a hit
event names the turret that fired, but not the MODE that chose the target, so
mode-level questions still need a scenario where only one mode can be acting.

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
