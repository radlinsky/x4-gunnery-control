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

**Auto-engage**: issues no fire orders — your turrets still choose their own targets. Before
entering the camera it writes your checked groups' staged console settings to the
ship (so ticking a group, which sets its Mode to **Attack all enemies**, does take
effect for the duration). The camera cycles only through the turrets of the
checked groups, not every turret on the ship. Everything is reverted when you get
up.

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
- **Other Turrets: Prefer My Target**: every turret on the ship prefers your
  target. A turret that is out of range or cannot swing round to the target will
  roll to another hostile, but one whose own hull is in the way will track the
  target and hold fire rather than rolling.

  This affects every turret on the ship regardless of its Mode — no exceptions.
  A **Missile Defence** turret will start shooting the ship you picked instead
  of watching for incoming missiles; a **Defend** turret will engage a target
  that is not attacking you; **Mine** and **Tow** turrets are included too.
  **Release Other Turrets** is the off switch and reaches everything this
  button reached.
- **Release Other Turrets**: gives the rest of the ship back to its own
  settings. The groups you checked keep shooting your target, because you are
  still directing them. Getting up releases everything.

A few things worth knowing up front:

- **Ticking a group's checkbox sets that group's Mode to Attack all enemies.**
- **Everything you change in the console is temporary** and is undone when you
  press **Get Up**, unless you press **Update turret behavior** first, which
  makes those changes permanent.

**Saving and loading keeps your seat.** Save while engaged and the load puts you
back at the same turret, watching the same target, with the same groups checked.

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
- **On small ships the camera watches the whole ship, not the turret.** X4
  resolves a turret camera on S/M ships to the ship itself. Everything still
  works — Direct-control, target selection, auto-engage — the view is just less
  specific than it is on a capital ship.
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

**Steam Workshop**:
[subscribe](https://steamcommunity.com/sharedfiles/filedetails/?id=3778864325).
The Workshop build depends on the
[Workshop repackage of UI Extensions and HUD](https://steamcommunity.com/sharedfiles/filedetails/?id=3477279743),
so Steam pulls that in for you.

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
./scripts/package.sh
```
