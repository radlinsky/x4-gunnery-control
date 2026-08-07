# X4 Gunnery Control

<img width="790" height="664" alt="preview" src="https://github.com/user-attachments/assets/60dbe5e0-b583-4359-8b56-b9f201fdc52d" />

https://github.com/user-attachments/assets/19c517e6-2c34-4a32-8c1b-6d10ea47cd5b

X4 Foundations 9.00 extension that makes the **Access Gunnery
Control** chair worth sitting in. Instead of the vanilla secondary-control menu,
you get a full turret console, direct fire orders, and four camera views of your
turrets at work.

## What you can do

**Pick your turret groups.** Sitting down opens the console. Every
turret group gets a checkbox; check the ones you want to work with,
or use **Select all**. You can change each
group's **Mode** and **Armed** state right there, exactly like on the
ship's behaviour tab.

Once you select at least one group, two buttons light up:

**Auto-engage**: does not alter turret behavior at all. Your turrets keep choosing targets by
whatever settings the ship already had. This mode exists purely so you can sit
and watch them work.

**Direct-control**: you tell the checked groups exactly what to shoot.
The **Select Engagement Target** menu lists the ships and stations in radar range; click
one and its hull is engaged immediately, but you can instead
mark a specific surface element (e.g. turret, shield, engine).

- **Auto-next Target when destroyed** is checked by default: when the target
  dies, the turret(s) and camera automatically select the next target.
  Uncheck it, and the turret(s) will sit idly by until you pick
  the next target yourself, which is closer to actually manning the gun.
- **Next Target** / **Previous Target** step through the same candidate list
  without reopening the browser.

## Four viewing modes

- **Turret POV manual** / **Target POV manual** — camera on the turret, or on
  what it is shooting at, with the normal UI still up. Hold `Shift` + middle
  mouse button to look around freely.
- **Turret POV cinematic** / **Target POV cinematic** — the same two viewpoints
  through the game's cutscene camera. It hides all UI and aims the camera for
  you. Press `Esc` to come back to the manual panel.
- **Next Turret** / **Previous Turret** cycle the camera through every
  operational turret in the checked groups. This only moves the camera.

## Limitations

- **This is not manual aiming.** Direct-control tells the turrets
  *what* to hit, not *how*. The engine exposes no way to man a turret yourself.
- **Turret POV cinematic often clips the camera into your own hull.** It looks
  rough. Target POV cinematic is the better-looking of the two.
- The confirmation popup that appears when you stand up also works around an X4
  bug that leaves `Esc` dead after a camera session. If you have turned help
  texts off in the game options, that popup never shows — and the workaround
  goes with it. Press `Esc` once after standing up; it stays unresponsive until
  any other menu opens and closes (e.g. M for map).

## Requirements

- X4 Foundations 9.00 or newer.
- [kuertee UI Extensions and HUD](https://www.nexusmods.com/x4foundations/mods/552).
  Leave Protected UI Mode active as its instructions recommend.

The extension replaces no vanilla game files, no UI Extensions files, and no
combat AI scripts.

## Installation

**Nexus / Vortex**: install UI Extensions and HUD first, then install the ZIP
without changing its top-level `x4_gunnery_control` folder.

**Steam Workshop**: subscribe, then install UI Extensions and HUD from Nexus
Mods as well. It is not on the Workshop, and the game will not load this mod
without it.

**Manual** — extract the archive so you end up with:

```text
X4 Foundations/extensions/x4_gunnery_control/
```

Launch X4, enable both extensions in the Extensions menu, and load a save.

## Shout-outs

Thanks to [Kuertee](https://github.com/kuertee) for pointers on how to make the cinematic mode work!

## Development

The full developer guide is [DEVELOPMENT.md](DEVELOPMENT.md): setup, loose-file
installs, debugging, the edit loop, the Test Lab, packaging and releases. Test
procedure and coverage live in [TESTING.md](TESTING.md). Contributions are MIT
licensed; see [CONTRIBUTING.md](CONTRIBUTING.md).

The short local check is:

```bash
./scripts/validate.sh
./scripts/package.sh 0.20
```
