<!--
Body of the GitHub release, used verbatim by .github/workflows/release.yml.
Plain English, no version numbers (so it does not drift), no engine internals.
NEWS.md is the player-facing history; CHANGELOG.md is the technical record.
-->

- A rotatable, zoomable ship hologram now shows your turret positions in the console and Direct-control view. Click a turret to select its group in the console or switch turret cameras during Direct-control. Markers distinguish unselected, selected, firing and hitting turrets; missile turrets show firing but do not report hits. Rotation and zoom are remembered per ship during the current UI session.
- Target and surface browsers now show **IN RANGE** counts instead of ENGAGEABLE. These estimate weapon reach for your selected operational turrets and update automatically. They do not promise that a turret can bear, has a clear line of fire, or will fire. Surface browser pages now show 10 alternatives at a time.
- Auto-next uses fresh range checks before choosing a replacement. It tries other surface elements on the same ship or station first, then its hull, then the nearest eligible enemy or hostile object. It preserves your camera POV and returns to manual selection after three unsuccessful object scans.
- You can open Gunnery Control while on foot aboard your own ship through Map → right-click that ship → **Gunnery Control**, when SirNukes Mod Support APIs is installed.
- Selecting an eligible hostile target in the world now updates your Direct-control target. Opening external menus, including the Map, parks Gunnery Control and restores it when you return.
- Improved chair entry, camera and menu recovery, and temporary turret-setting restoration while browsing targets.
