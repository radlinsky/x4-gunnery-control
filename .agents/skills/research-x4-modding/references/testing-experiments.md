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
