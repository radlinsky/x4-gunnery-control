<!--
Body of the GitHub release, used verbatim by .github/workflows/release.yml.
Plain English, no version numbers (so it does not drift), no engine internals.
The technical record is CHANGELOG.md; this is what a player reads.
-->

I never liked the vanilla gunnery control chair — you sit down and get the same
boring menu. This mod replaces it with a real turret console.

## New in this release

- **New features**
- **All Turrets: Prefer My Target** Normally, only the turret group(s)
  you selected to control will try and fire at your target. If your target
  goes out of range from any of your selected turrets, those turrets will sit idle.
  This button tells **every** turret that can hit your chosen target to do so (including
  the turrets outside your selected group). Turrets that cannot find a firing
  solution for your target instead find the next best enemy target in-range.
- **Release Other Turrets** Turns off the ship-wide "Prefer my target" mode.

- **Bug fixes**
- Direct-control now works on M ships lacking a turret camera.
- If the camera cannot attach for a target-view request, target selection stays
  open so you can continue playing instead of being kicked out.
- Turret groups with duplicate names are now still controllable.
- The group **Mode** column now refreshes correctly after **Cease Engagement**.

## What you can do

**Pick your turret groups.** Every physical turret group gets a row with a
checkbox. Check the ones you want, or use **Select all**. Names read like
*Front Upper Left*, with the turret type when the game exposes it. You can set
each group's **Mode** and **Armed** state right there, same as on the ship's
behaviour tab.

Then two buttons light up:

**Auto-engage** — changes nothing. Your turrets keep doing what they were
already doing. This is just for sitting back and watching them work.

**Direct-control** — you tell the checked groups what to shoot.
**Select Engagement Target** lists ships and stations in radar range; click one
and its hull is engaged immediately. You can also point every checked group at a
specific surface element instead — a turret, a shield generator, an engine.

- **Auto-next Target when destroyed** is on by default: when the target dies,
  everything moves to the next one automatically. Turn it off and the mod stops
  and asks you to pick the next target yourself, which feels a lot more like
  actually manning the gun.
- **Next Target** / **Previous Target** step through the same list without
  reopening the browser.

## Four ways to watch

- **Turret POV manual** / **Target POV manual** — camera on the turret, or on
  what it is shooting at, with the normal UI still up. Hold `Shift` + middle
  mouse button to look around.
- **Turret POV cinematic** / **Target POV cinematic** — the same two viewpoints
  through the game's cutscene camera, which hides all UI and aims for you.
  `Esc` returns you to the manual panel.
- **Next Turret** / **Previous Turret** cycle the camera through every
  operational turret in the checked groups. This only moves the camera; it never
  changes what is being shot at.

## Leaving the seat

**Cease Engagement**, **Get Up**, closing the console, undocking, or changing
ships puts every group back exactly as you found it, and a short popup confirms
it.

## Things to know

- **This is not manual aiming.** X4 still decides barrel traverse, lead, when to
  fire, and whether a target is legal to attack. You say *what*, not *how*. The
  engine gives no way to man a turret yourself.
- **Turret POV cinematic often clips into your own hull** and looks rough.
  Target POV cinematic is the prettier of the two.
- **The camera's aim point is a good guess.** X4 offers no way to ask a turret
  what it is shooting at, so the mod picks the most likely target the same way
  the game would. Usually right, occasionally not.
- On some S/M ships, a turret-target camera request can resolve to a wider
  ship-level view instead of a tight turret component view.
- If two turret groups share the same name, member rows can appear under the
  wrong name and Direct-control can open the camera on a sibling group's
  representative turret. Commands still apply to the correct group.
- Cinematic views hide the entire UI, including this mod's panel.

## Requirements

- X4 Foundations 9.00 or newer.
- [kuertee UI Extensions and HUD](https://www.nexusmods.com/x4foundations/mods/552)
  9.00 or newer. This is a hard requirement — X4 will not load Gunnery Control
  without it. Steam Workshop subscribers need it from Nexus too; it is not on
  the Workshop.

## Install

Extract the zip so you end up with:

```text
X4 Foundations/extensions/x4_gunnery_control/
```

Then enable both extensions in the Extensions menu and load a save.
