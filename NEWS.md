# News

## Unreleased

- **Loading a save no longer loses your gunnery session.** Turret groups, the active target, and POV are all restored when you load.
- **Target POV now works after loading.** It used to do nothing until you switched to another surface element and back.
- **"Other Turrets: Prefer My Target" and "Release Other Turrets" removed.** The Release behaviour was broken by an X4 API limitation — it could not cleanly revert `defend`, `missiledefence`, or `mining` modes after a ship-wide override. Ticking turret groups and using Direct-control is the supported way to direct turrets at a chosen target.

## 0.30 — 2026-08-07

- **New: "All Turrets: Prefer My Target."** During Direct-control every turret on the ship shoots your chosen target when it can, and something else in range otherwise. Checked groups stay on your target; unchecked groups return to their own modes. Mining and towing turrets are left alone in both directions.
- **Direct-control works on S/M ships again.** The camera now opens normally instead of kicking you back to the console. On some smaller ships the view may resolve to a wider ship-level perspective rather than a tight turret frame — you can still see and aim, just from farther away.
- **Duplicate-named turret groups are now controllable.** Previously, two groups sharing a name caused both to be greyed out. Groups remain controllable, but member rows and camera representative selection can still resolve under a sibling group; commands still reach the correct group.
- **The Mode column now updates correctly** after you cease an engagement.

## 0.20 — 2026-08-06

- **Two modes in one compact panel: Auto-engage and Direct-control.** Auto-engage is camera-only — it opens the turret POV without mutating settings or issuing fire orders. Direct-control lets you pick a target element (hull, turret, shield, or engine) and arms every checked group against it.
- **Group-level checkboxes replace per-turret buttons.** Select whole linked groups at once; ungrouped turrets remain individually selectable. A select-all checkbox is available in the console header.
- **Auto-next Target when destroyed** is on by default. When the engaged target dies, the camera and soft target move to the next candidate automatically. Turn it off for manual retargeting.
- **Next Target / Previous Target buttons** step through the candidate list without reopening the browser.
- **Element panel** (Direct-control only) lists the engaged ship's hull and every operational surface element; click any element to re-point all overridden groups at it.
- **Four POV options:** Turret or Target anchor, each in manual or cinematic mode. Next/Previous Turret cycles the camera through every operational turret in your checked groups. Cinematic views hide all UI — `Esc` is the only exit and returns to manual panel.
- **Console layout improved.** Wider name column, solid semi-transparent backgrounds for legibility over the live view, and inset table so checkboxes are not flush with the screen edge.
- **Help popup on seat exit.** A brief message confirms whether your turrets were restored or the session disengaged.
- **Several Esc and HUD bugs fixed.** Exiting via cinematic POV, getting up after a session, or undocking no longer leaves the game menu unresponsive or the HUD hidden.

## 0.1.0 — 2026-08-03

- Initial practical gunnery-chair console for X4 9.00.
