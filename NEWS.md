# News

## 0.31 - 2026-08-20

- Target selection now shows each ship/station candidate's class/type and an N / total ENGAGEABLE count for the selected turrets. Fully ENGAGEABLE candidates are listed first, ahead of the normal relationship/distance ordering.
- Surface element targeting has been rebuilt for large ships and stations. Filter operational surface elements by Turret / Shield / Engine, with alternatives ordered largest-first (XL → L → M → S → XS), then paged 20 at a time. Every listed surface element has its own ENGAGEABLE count; the current aim point stays pinned with distance, shield and hull status. Manual refresh and an optional 10-second automatic refresh keep the browser current.
- ENGAGEABLE now reflects the selected turrets' actual geometry. The ratio checks known turret traverse arc, weapon range, and a clear muzzle-to-target line of fire past your own ship. Unknown-arc turrets remain in the denominator and are reported as UNKNOWN. It is still a targeting aid, not a guarantee that X4 will authorize or fire a shot.
- Direct-control now has a turret mode selector, on the main console and the Direct-control panel. **Attack all enemies** keeps your selected target as the preferred target with the other enemies in range as fallback. **Attack my current enemy** sticks strictly to your selected target with no fallback, so turrets that cannot engage it may sit idle. Change it any time; Auto-engage is unaffected.
- Turret behavior edits are temporary by default. Your previous turret settings are restored when you stand up, unless you click **Update turret behavior** first. That commit button now lives only on the main console (it was removed from the compact engaged panels), and it makes the current Mode/Armed settings stick after you leave the chair.
- ENGAGEABLE now handles large ships and stations better. Weapon range is measured to the target's bounding box instead of its center, so weapons that can actually reach a big hull no longer read as out of range. And for whole ships or stations with applicable targetable modules, when their own center point blocks the line of fire, the check falls back to those modules; individually selected surface elements keep their own direct line-of-fire test. It is still a targeting aid, not a firing guarantee.
- When a surface element you are attacking is destroyed, Auto-next now prefers other ENGAGEABLE surface elements on the same ship or station first (paged 20 at a time), then that target's hull, then other objects in range.
- Loading a save no longer loses your gunnery session. Checked turret groups, control mode, the active target and POV are restored when you load.
- Target POV now works immediately after loading instead of requiring you to switch to another surface element and back first.
- "Other Turrets: Prefer My Target" and "Release Other Turrets" have been removed. The Release behavior could not cleanly revert `defend`, `missiledefence`, or `mining` modes after a ship-wide override. Ticking turret groups and using Direct-control is the supported way to direct turrets at a chosen target.
- Previous / Next controls now appear in the conventional order, with Previous on the left and Next on the right.

## 0.30 - 2026-08-07

- New: "All Turrets: Prefer My Target." During Direct-control every applicable turret prefers your chosen target when it can, and may shoot something else in range otherwise. This is separate from "Release Other Turrets," which was the action that handed unchecked/rest-of-ship turrets back while checked groups remained directed at the chosen target. Mining and towing turrets are left alone in both directions.
- Direct-control works on S/M ships again. When a turret camera is not available, Gunnery Control uses a ship camera instead. This is often the case for S/M ships. Target selection and control still work normally.
- Duplicate-named turret groups are now controllable. Previously, two groups sharing a name caused both to be greyed out. Groups remain controllable, but member rows and camera representative selection can still resolve under a sibling group; commands still reach the correct group.
- The Mode column now updates correctly after you cease an engagement.

## 0.20 - 2026-08-06

- Two modes in one compact panel: Auto-engage and Direct-control. Auto-engage is camera-only. It opens the turret POV without mutating settings or issuing fire orders. Direct-control lets you pick a target element (hull, turret, shield, or engine) and arms every checked group against it.
- Group-level checkboxes replace per-turret buttons. Select whole linked groups at once; ungrouped turrets remain individually selectable. A select-all checkbox is available in the console header.
- Auto-next Target when destroyed is on by default. When the engaged target or surface element is destroyed, the camera and soft target move to the next candidate automatically. Turn it off for manual retargeting.
- Next Target / Previous Target buttons step through the candidate list without reopening the browser.
- Element panel (Direct-control only) lists the engaged ship's hull and every operational surface element; click any element to re-point all overridden groups at it.
- Four POV options: Turret or Target anchor, each in manual or cinematic mode. Next/Previous Turret cycles the camera through every operational turret in your checked groups. Cinematic views hide all UI. `Esc` is the only exit and returns to manual panel.
- Console layout improved. Wider name column, solid semi-transparent backgrounds for legibility over the live view, and inset table so checkboxes are not flush with the screen edge.
- Help popup on seat exit. A brief message confirms whether your turrets were restored or the session disengaged.
- Several Esc and HUD bugs fixed. Exiting via cinematic POV, getting up after a session, or undocking no longer leaves the game menu unresponsive or the HUD hidden.

## 0.1.0 - 2026-08-03

- Initial practical gunnery-chair console for X4 9.00.
