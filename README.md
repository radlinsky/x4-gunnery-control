# X4 Gunnery Control

<img width="790" height="664" alt="preview" src="https://github.com/user-attachments/assets/60dbe5e0-b583-4359-8b56-b9f201fdc52d" />

https://github.com/user-attachments/assets/19c517e6-2c34-4a32-8c1b-6d10ea47cd5b

X4 Foundations 9.00 extension that makes the Access Gunnery Control chair worth sitting in. Instead of the vanilla secondary-control menu, you get a turret console, direct fire orders, and four camera views of your turrets at work.

## What you can do

Sitting down opens the console. Every turret group gets a checkbox, or you can use Select all. You can also change each group's Mode and Armed state from the same screen.

The console and Direct-control view include a rotatable, zoomable ship hologram. Click a turret to select its group in the console or switch turret cameras during Direct-control. Markers show selection, firing and hits; missile turrets do not report hits.

With SirNukes Mod Support APIs installed, you can also open Gunnery Control while on foot aboard your own ship: Map → right-click that ship → Gunnery Control.

Once you select at least one group, two controls become available.

**Auto-engage** issues no fire orders. Your turrets still choose their own targets. The camera cycles only through turrets in the selected groups.

**Direct-control** lets you tell the selected groups what to shoot. Select Engagement Target lists ships and stations in radar range, along with class/type, distance, and an N / total IN RANGE count. Candidates with every evaluated turret IN RANGE are listed first. Select a ship or station to engage its hull, or switch to one of its surface elements.

While engaged, the surface element browser keeps the current aim point pinned and lets you switch between the parent hull and operational turret, shield, and engine surface elements. You can filter by Turret / Shield / Engine and by equipment. Surface elements are ordered largest-first (XL → L → M → S → XS), then by type and distance, and are paged 10 at a time. Each surface element shows distance and its own IN RANGE count. The pinned aim point also shows shield and hull status. You can refresh manually or enable an optional 10-second automatic refresh.

IN RANGE estimates whether each operational turret in your selected groups can reach the target. It compares the distance from the turret to the edge of the target (its bounding box) with the weapon's current range, and allows a little extra for non-beam weapons against ships that can move, or their engines. It does not check whether the turret can turn to face the target, lead a moving target, or shoot past obstacles, or whether X4 will actually let it fire. The distance shown in the list is from your ship to the target, not from each turret to the target's edge, so it will not always agree with IN RANGE. Counts update on their own; the refresh buttons only refresh the list.

For example, 3 / 4 IN RANGE means three of your four selected operational turrets are in range.

- Auto-next Target when destroyed is on by default. When the surface element you are attacking is destroyed, it moves to another one on the same ship or station (largest first, then by type and distance), then falls back to the hull. If none of those are in range, or the whole ship or station is gone, it opens the target browser and picks the closest enemy or hostile target. It only picks a target that at least one of your selected turrets can reach (IN RANGE). If the top choice is already IN RANGE, it switches right away instead of waiting for every range check to finish. After three tries with nothing in range, the browser stays open so you can choose. If there are no enemies at all, it leaves the choice to you straight away. Turn Auto-next off to always choose replacements yourself. See [the complete rules](docs/FIRE_CONTROL_BEHAVIOR.md#auto-next-replacement-rules).
- Next Target / Previous Target step through the same candidate list without reopening the browser.
- Choose the Direct-control turret mode, on the main console or the Direct-control panel: **Attack all enemies** keeps your target as the preferred target with the other enemies in range as fallback, or **Attack my current enemy** sticks strictly to your selected target (turrets that cannot engage it may sit idle).

Your previous turret settings are restored when you stand up, unless you click **Update turret behavior** on the main console first. That makes the current Mode/Armed settings stick after you leave the chair.

Saving and loading keeps your seat. Save while engaged and loading that save puts you back at the same turret, watching the same target, with the same groups selected.

## Four viewing modes

- Turret POV manual / Target POV manual: camera on the turret, or on what it is shooting at, with the normal UI still visible. Hold `Shift` + middle mouse button to look around freely.
- Turret POV cinematic / Target POV cinematic: the same two viewpoints through the game's cutscene camera. It hides the UI and aims the camera for you. Press `Esc` to return to the manual panel.
- Next Turret / Previous Turret cycle through every operational turret in the selected groups. This only moves the camera.

## Limitations

- This is not manual aiming. Direct-control tells the turrets what to hit, not how to aim.
- Many S/M ships have no turret camera, so Gunnery Control shows a ship camera instead. Direct-control, target selection, and Auto-engage still work normally.
- Turret POV cinematic can clip the camera into your own hull. Target POV cinematic usually looks better.
- The confirmation popup shown when you stand up works around an X4 bug that can leave `Esc` unresponsive after a camera session. Opening and closing another menu, such as the map, also restores `Esc`.
- IN RANGE is only an estimate. X4 may hold fire despite a positive count, or fire beyond the estimate because it also checks the distance from the muzzle to the aim point.
- If two groups share a name, the UI can show the wrong members for them. Commands still go to the right group.

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
- Nexus: [UI Extensions and HUD](https://www.nexusmods.com/x4foundations/mods/552) and [Print Extension List](https://www.nexusmods.com/x4foundations/mods/2191).
- Steam: [UI Extensions and HUD](https://steamcommunity.com/sharedfiles/filedetails/?id=3477279743) and [Print Extension List](https://steamcommunity.com/sharedfiles/filedetails/?id=3770927339).
- Optional: SirNukes Mod Support APIs ([Nexus](https://www.nexusmods.com/x4foundations/mods/503) / [Steam](https://steamcommunity.com/sharedfiles/filedetails/?id=2042901274)), to open Gunnery Control from the Map while on foot aboard your ship.

This extension replaces no vanilla game files, UI Extensions files, or combat AI scripts.

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
