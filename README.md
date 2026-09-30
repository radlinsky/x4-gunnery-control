# X4 Gunnery Control

<img width="790" height="664" alt="preview" src="https://github.com/user-attachments/assets/60dbe5e0-b583-4359-8b56-b9f201fdc52d" />

https://github.com/user-attachments/assets/19c517e6-2c34-4a32-8c1b-6d10ea47cd5b

X4 Foundations 9.00 extension that makes the Access Gunnery Control chair worth sitting in. Instead of the vanilla secondary-control menu, you get a turret console, direct fire orders, and four camera views of your turrets at work.

## What you can do

Sitting down opens the console. Every turret group gets a checkbox, or you can use Select all. You can also change each group's Mode and Armed state from the same screen.

Once you select at least one group, two controls become available.

**Auto-engage** issues no fire orders. Your turrets still choose their own targets. The camera cycles only through turrets in the selected groups.

**Direct-control** lets you tell the selected groups what to shoot. Select Engagement Target lists ships and stations in radar range, along with class/type, distance, and an N / total IN RANGE count. Candidates with every evaluated turret IN RANGE are listed first. Select a ship or station to engage its hull, or switch to one of its surface elements.

While engaged, the surface element browser keeps the current aim point pinned and lets you switch between the parent hull and operational turret, shield, and engine surface elements. You can filter by Turret / Shield / Engine. Surface elements are ordered largest-first (XL → L → M → S → XS), then by type and distance, and are paged 10 at a time. Each surface element shows distance and its own IN RANGE count. The pinned aim point also shows shield and hull status. You can refresh manually or enable an optional 10-second automatic refresh.

IN RANGE estimates weapon reach for the operational turrets in your selected groups. It uses turret-origin distance to the target’s bounding box and current weapon range, with an allowance for non-beam ammunition against moving-capable ships or their engines. It does not test bearing, line of fire, intercept, readiness, or authorization. Displayed distance is measured from your ship’s origin to the target’s origin, separately from the range estimate. Counts update automatically; list refresh controls are separate.

For example, 3 / 4 IN RANGE means three of four selected operational turrets pass the range estimate.

- Auto-next Target when destroyed is on by default. On surface loss, it tries other surfaces on the same ship/station by size, type, then distance, followed by the original hull. If those fail, or a whole ship/station is lost, it visibly opens the target browser and chooses the closest attackable enemy or hostile object. Every replacement needs at least one selected operational turret IN RANGE from a fresh, complete scan. The browser allows at most three scan attempts before returning to manual selection; no eligible candidates means manual selection immediately. Turn Auto-next off to choose replacements yourself. See [the complete rules](docs/FIRE_CONTROL_BEHAVIOR.md#auto-next-replacement-rules).
- Next Target / Previous Target step through the same candidate list without reopening the browser.
- Choose the Direct-control turret mode, on the main console or the Direct-control panel: **Attack all enemies** keeps your target as the preferred target with the other enemies in range as fallback, or **Attack my current enemy** sticks strictly to your selected target (turrets that cannot engage it may sit idle).
- Your previous turret settings are restored when you stand up, unless you click **Update turret behavior** on the main console first. That makes the current Mode/Armed settings stick after you leave the chair.

Saving and loading keeps your seat. Save while engaged and loading that save puts you back at the same turret, watching the same target, with the same groups selected.

## Four viewing modes

- Turret POV manual / Target POV manual: camera on the turret, or on what it is shooting at, with the normal UI still visible. Hold `Shift` + middle mouse button to look around freely.
- Turret POV cinematic / Target POV cinematic: the same two viewpoints through the game's cutscene camera. It hides the UI and aims the camera for you. Press `Esc` to return to the manual panel.
- Next Turret / Previous Turret cycle through every operational turret in the selected groups. This only moves the camera.

## Limitations

- This is not manual aiming. Direct-control tells the turrets what to hit, not how to aim.
- Some S/M ships use a ship camera instead of a turret camera. When a turret camera is not available, Gunnery Control uses a ship camera instead. This is often the case for S/M ships. Direct-control, target selection, and Auto-engage still work normally.
- Turret POV cinematic can clip the camera into your own hull. Target POV cinematic usually looks better.
- The confirmation popup shown when you stand up works around an X4 bug that can leave `Esc` unresponsive after a camera session. Opening and closing another menu, such as the map, also restores `Esc`.
- IN RANGE is an estimate, not a firing guarantee. X4 may hold fire despite a positive count, or fire beyond the estimate because it also checks muzzle-to-aim-point distance.
- Duplicate-named groups can mislabel members in the UI. Commands still reach the correct group.

## Reporting problems

If Gunnery Control is not working correctly, please send me a debug log with the report.

In Steam, right-click X4 Foundations in your Library, choose Properties, and add this under General > Launch Options:

```text
-debug all -logfile debug.log
```

For GOG or another launcher, add the same arguments to X4's launch command.

Start X4, reproduce the problem, then quit the game. On Windows, the log is usually here:

```text
C:\Users\<your-name>\Documents\Egosoft\X4\<number>\debug.log
```

Attach `debug.log` to a [GitHub issue](https://github.com/radlinsky/x4-gunnery-control/issues) and briefly describe what you were doing when the problem occurred. If GitHub will not accept the `.log` file, zip it first.

X4 replaces `debug.log` every time it launches, so save or send the log before starting the game again.

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

Thanks to Chem O'Dun for suggestions and feedback on the mod.

## Development

The full developer guide is [DEVELOPMENT.md](DEVELOPMENT.md). Test procedure and coverage live in [TESTING.md](TESTING.md). Contributions are MIT licensed; see [CONTRIBUTING.md](CONTRIBUTING.md).

The short local check is:

```bash
./scripts/validate.sh
./scripts/package.sh
```
