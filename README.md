# X4 Gunnery Control

<img width="790" height="664" alt="preview" src="https://github.com/user-attachments/assets/60dbe5e0-b583-4359-8b56-b9f201fdc52d" />

https://github.com/user-attachments/assets/19c517e6-2c34-4a32-8c1b-6d10ea47cd5b

X4 Foundations 9.00 extension that makes the Access Gunnery Control chair worth sitting in. Instead of the vanilla secondary-control menu, you get a turret console, direct fire orders, and four camera views of your turrets at work.

## What you can do

Sitting down opens the console. Every turret group gets a checkbox, or you can use Select all. You can also change each group's Mode and Armed state from the same screen.

Once you select at least one group, two controls become available.

**Auto-engage** issues no fire orders. Your turrets still choose their own targets. Before entering the camera, Gunnery Control applies the selected groups' current console settings for the session. The camera cycles only through turrets in the selected groups.

**Direct-control** lets you tell the selected groups what to shoot. Select Engagement Target lists ships and stations in radar range, along with class/type, distance, and an N / total ENGAGEABLE count. Fully ENGAGEABLE candidates are listed first. Select a ship or station to engage its hull, or switch to one of its surface elements.

While engaged, the surface element browser keeps the current aim point pinned and lets you switch between the parent hull and operational turret, shield, and engine surface elements. You can filter by Turret / Shield / Engine. Surface elements are ordered largest-first (XL → L → M → S → XS), then by type and distance, and are paged 20 at a time. Each surface element shows distance and its own ENGAGEABLE count. The pinned aim point also shows shield and hull status. You can refresh manually or enable an optional 10-second automatic refresh.

The ENGAGEABLE count is a geometry check, not a guarantee that a turret will fire. A turret counts as ENGAGEABLE when its known traverse arc covers the aim direction, the target is within weapon range, and the line of fire from the muzzle is clear past your own ship. Turrets with unknown arc data stay in the denominator and are reported as UNKNOWN. Readiness, fire authorization, intercept, and actual firing are separate.

For example, 3 / 4 ENGAGEABLE means 3 of the 4 selected/evaluated turrets currently pass that geometry check.

- Auto-next Target when destroyed is on by default. When the current target dies, the turrets and camera automatically select the next target (or surface element). Turn it off if you prefer to choose the next one yourself.
- Next Target / Previous Target step through the same candidate list without reopening the browser.
- Ticking a group's checkbox sets that group's Mode to Attack all enemies.
- Your previous turret settings are restored when you stand up, unless you click **Update turret behavior** first. That makes the current Mode/Armed settings stick after you leave the chair.

Saving and loading keeps your seat. Save while engaged and loading that save puts you back at the same turret, watching the same target, with the same groups selected.

## Four viewing modes

- Turret POV manual / Target POV manual: camera on the turret, or on what it is shooting at, with the normal UI still visible. Hold `Shift` + middle mouse button to look around freely.
- Turret POV cinematic / Target POV cinematic: the same two viewpoints through the game's cutscene camera. It hides the UI and aims the camera for you. Press `Esc` to return to the manual panel.
- Next Turret / Previous Turret cycle through every operational turret in the selected groups. This only moves the camera.

## Limitations

- This is not manual aiming. Direct-control tells the turrets what to hit, not how to aim.
- Some S/M ships use a ship camera instead of a turret camera. When a turret camera is not available, Gunnery Control uses a ship camera instead. This is often the case for S/M ships. Direct-control, target selection, and Auto-engage still work normally.
- Turret POV cinematic can clip the camera into your own hull. Target POV cinematic usually looks better.
- The confirmation popup that appears when you stand up also works around an X4 bug that can leave `Esc` unresponsive after a camera session. If help texts are disabled in the game options, that workaround is also disabled. Opening and closing another menu, such as the map, restores `Esc`.
- ENGAGEABLE is a targeting aid, not a firing guarantee. A turret can pass the geometry check and still hold fire because it is not ready, lacks authorization, or cannot solve the intercept. UNKNOWN turrets may still fire when their arc data are unavailable to the mod.
- Duplicate-named groups can mislabel members in the UI. Commands still reach the correct group.

## Requirements

- X4 Foundations 9.00 or newer.
- Nexus: [UI Extensions and HUD](https://www.nexusmods.com/x4foundations/mods/552) and [Print Extension List](https://www.nexusmods.com/x4foundations/mods/2191). Leave Protected UI Mode active as UI Extensions recommends.
- Steam: [UI Extensions and HUD](https://steamcommunity.com/sharedfiles/filedetails/?id=3477279743) and [Print Extension List](https://steamcommunity.com/sharedfiles/filedetails/?id=3770927339).

The extension replaces no vanilla game files, UI Extensions files, or combat AI scripts.

## Installation

Nexus / Vortex: install both required extensions first, then install the ZIP without changing its top-level `x4_gunnery_control` folder.

Steam Workshop: [subscribe](https://steamcommunity.com/sharedfiles/filedetails/?id=3778864325). Steam will also pull the two required Workshop dependencies.

Manual: extract the archive so you end up with:

```text
X4 Foundations/extensions/x4_gunnery_control/
```

Launch X4, enable Gunnery Control and both required extensions in the Extensions menu, and load a save.

## Shout-outs

Thanks to [Kuertee](https://github.com/kuertee) for pointers on how to make the cinematic mode work.

## Development

The full developer guide is [DEVELOPMENT.md](DEVELOPMENT.md). Test procedure and coverage live in [TESTING.md](TESTING.md). Contributions are MIT licensed; see [CONTRIBUTING.md](CONTRIBUTING.md).

The short local check is:

```bash
./scripts/validate.sh
./scripts/package.sh
```
