# Turret behavior by firing situation

What your turrets do in each firing situation, under Direct-control and under Auto-engage. This document describes only what is built and known today. It is updated as more becomes known.

## Terms used here

These words mean one specific thing throughout this document.

- **Your target** — the target you selected in Direct-control.
- **Another target** — any other enemy target within radar range.
- **Aim at** — a turret can physically rotate and tilt to point at something.
- **Switch to** — a turret gives up on your target and shoots a different target instead.
- **Other targets in range** — the enemy targets a turret is allowed to switch to. Direct-control sends this set to your ticked turrets along with your target.
- **Ticked group** — a turret group with its checkbox ticked in the main Gunnery Console. Ticking sets the group to the **Attack all enemies** mode. See the modes table below.
- **Own mode** — whatever mode you left an unticked group in.
- **Armed / not armed** — a turret's on/off switch. A turret that is not armed does not fire, whatever else is true.
- **Your pilot** — whoever is flying your ship while you sit at the Gunnery Console. Your pilot may be **attacking** a target, or may be flying or idle.
- **Prefer My Target** — the "Other Turrets" toggle in Direct-control. It sends your target to every turret group on the ship, not only the ticked ones.

Confidence is marked on every behavior:

- **LIVE** — watched happen in game.
- **X4 CODE** — stated in Egosoft's own game scripts.
- **INFERRED** — worked out from the two above, not directly watched.
- **UNTESTED** — the mod has code for this, but it has not been confirmed in game.
- **UNKNOWN** — not known yet.

---

## Table 1: Firing situations

The situations that matter for this mod. Each is checked against **your target**.

| Situation | What it means |
|---|---|
| **ON SOLUTION** | The turret can aim at the target, the target is in range, and nothing blocks the shot. A clean shot. |
| **OUT OF RANGE** | The target is farther away than the turret's weapons can reach. |
| **OUT OF ARC** | The target is in a direction the turret cannot rotate or tilt far enough to aim at. For example, a turret on the top of the ship and a target directly below the ship. |
| **MASKED** | The turret is aimed right at the target, but part of your own ship is between the turret and the target, blocking the shot. |
| **NO SOLUTION** | The turret can aim and the target is in range, but the target is moving in a way that leaves no shot that would connect. |
| **WEAPON NOT READY** | Aiming is fine, but the turret itself cannot fire right now: reloading, overheated, out of ammunition, or destroyed. |
| **FIRE INHIBITED** | A shot is possible, but firing is held back on purpose: the group is on Hold fire, or the target is one you are not allowed to attack (friendly, surrendered, or captured). |

*Standard fire-control vocabulary also names NO CONTACT (the target is not detected at all) and NO FIRE-CONTROL TRACK (detected, but too little tracking data to shoot). X4 does not simulate these as separate situations, and the console will not let you select a target it cannot detect, so they are left out here.*

---

## Table 2: Turret group modes

The modes a turret group can be in. The in-game label is what X4 shows in the turret mode menu.

| In-game label | What the group does | Prefer My Target ON | Confidence |
|---|---|---|---|
| **Attack all enemies** | Shoots any enemy in range. This is what every ticked group is set to. | Shoots your target; behaves as Table 3 | LIVE |
| **Defend** | Fires only when defending against a threat, not on all enemies. | Is sent your target and will treat it as an enemy to shoot | UNTESTED |
| **Missile defence** | Shoots incoming missiles, not ships. | Is sent your target; whether it will shoot a ship is | UNTESTED |
| **Mine** | Turret task not built for shooting ships. | Is sent your target; effect | UNKNOWN |
| **Tow** | Turret task not built for shooting ships. | Is sent your target; effect | UNKNOWN |
| **Hold fire** | Does not fire. | Is sent your target; whether it fires anyway is | UNKNOWN |
| **(auto-assist)** | X4's automatic mode: the game picks the turret's target itself. No player-facing label in the turret menu; it is the game's default handling. | **Ignores the command.** It follows your *locked target*, not your selected target (see Table 6). | X4 CODE |

---

## Table 3: Direct-control

Direct-control aims your ticked turrets at the target you selected, and also sends them the other targets in range to switch to if they cannot hit your target.

**Assumed in this table:** every ticked group is on **Attack all enemies** and is **armed** (Direct-control arms your ticked groups for you when you engage). A **not-armed** group never fires; see [Global rules](#global-rules). "Own mode" columns describe an unticked group left in some other mode.

| Situation (vs your target) | Ticked group — pilot attacking OR idle, same result | Unticked, Prefer My Target ON | Unticked, Prefer OFF, pilot attacking | Unticked, Prefer OFF, pilot idle |
|---|---|---|---|---|
| **ON SOLUTION** | Shoots your target. **LIVE** | Shoots your target, if its mode acts on it (Table 2) | Ignores your target. Shoots enemies per its own mode | Ignores your target. Does whatever its own mode does |
| **OUT OF RANGE** | Switches to another target it can reach. **LIVE** | Switches to another target, mode permitting. **INFERRED** | Own mode | Own mode |
| **OUT OF ARC** | Switches to another target it can aim at. **LIVE** | Switches to another target, mode permitting. **INFERRED** | Own mode | Own mode |
| **MASKED** | Stays aimed at your target and does **not** fire. Does **not** switch to another target. **LIVE** | Same: stays aimed, does not fire. **INFERRED** | Own mode | Own mode |
| **NO SOLUTION** | Fires at your target and misses; keeps trying. Does not switch, because X4 does not detect this situation. **INFERRED** | Same. **INFERRED** | Own mode | Own mode |
| **WEAPON NOT READY** | Holds until the turret is ready. A destroyed turret is skipped, and re-included if it survives. **X4 CODE** | Same | Own mode | Own mode |
| **FIRE INHIBITED** | Ticked groups are on Attack all enemies, so they never hold fire on their own. If your target can no longer be attacked, see [Global rules](#global-rules). **UNTESTED** | Depends on the group's own mode (Table 2) | Own mode | Own mode |

**Why MASKED behaves differently from OUT OF ARC.** X4 decides whether to switch to another target by asking only whether the turret can *aim* at your target, not whether it can *hit* it. A masked turret is aimed straight at your target, so the game counts it as fine and never switches. An OUT OF ARC turret cannot aim at your target at all, so the game switches it to another target. Nothing the mod sends changes this, because the decision to switch is the game engine's, not the mod's.

**About "every turret."** Prefer My Target sends your target to every turret group on the ship at once. Sending it does not force a group to shoot. Whether a group shoots your target depends on the mode it is in, which is what Table 2 lists.

---

## Table 4: Auto-engage

Auto-engage lets you watch your ticked turret groups. Because they are ticked, they are on **Attack all enemies**. Auto-engage does not tell any turret which target to shoot; each turret picks its own target. There is no selected target and no Prefer My Target here.

| Group | Behavior | Confidence |
|---|---|---|
| **Ticked** | On Attack all enemies. The game picks each turret's target and handles every firing situation on its own. Fires only if armed. | X4 CODE |
| **Unticked** | Left in its own mode, unchanged. | X4 CODE |

Because the mod tells no turret what to shoot in Auto-engage, each situation plays out the way X4 handles it normally. A ticked turret that cannot aim at the target *it* chose will switch to another on its own.

---

## Global rules

These apply on top of everything above.

- **Not armed means no fire.** A turret group that is not armed does not fire, whatever its mode or your selection. Direct-control arms your ticked groups when you engage. In Auto-engage, a group keeps whatever armed state you gave it.
- **When your target can no longer be attacked** (it is destroyed, surrenders, or changes owner), one of two things happens under Direct-control. If **Auto-next target** is on (the default) and there is another target in range, Direct-control moves to that target automatically. Otherwise, the target-selection screen reopens and you pick again. The surrender and change-of-owner case is **UNTESTED**.
- **Selecting part of a ship.** You can select one component (a specific turret or engine) instead of a whole ship. Direct-control aims at that component, and the situations in Table 1 apply to it the same way.
- **Standing up.** When you stand up from the console, every turret group goes back to the mode and armed state it had before you sat down. The one exception is if you pressed **Update turret behavior**, which makes your current settings the ones it returns to instead.

---

## Technical detail

For readers who want the mechanism. Two separate mod actions are involved.

**1. Ticked groups (the fallback list).** When you engage in Direct-control, the mod sends each ticked group two instructions: first your target alone, then your target plus every other enemy in range, both marked "shoot this one first." This is the `DirectFallback` action. Because your target is marked preferred and the others are also supplied, a turret that cannot aim at or reach your target has a ready set to switch to. This action is limited to groups on Attack all enemies, which is exactly what ticked groups are.

**2. Prefer My Target (unticked groups).** This sends the same "your target first" instruction to the whole ship without limiting it to one mode, which is the only way to reach groups on auto-assist or Hold fire. Releasing it sends the enemy list back with no preferred target, returning the ship to its prior state. This is the `PreferAllTurrets` action.

What the game itself checks, per situation, for a ticked turret:

| Situation | What the game checks | Result | Confidence |
|---|---|---|---|
| **ON SOLUTION** | Can aim, in range, shot clear | Shoots your target | LIVE |
| **OUT OF RANGE** | Distance vs the turret's reach | Switches to another target in range | LIVE |
| **OUT OF ARC** | Can the turret aim that far | Switches to another target it can aim at | LIVE |
| **MASKED** | Is the shot path clear of your own ship | Stays aimed, holds fire, does not switch | LIVE |
| **NO SOLUTION** | (the game runs no such check) | Fires and misses | INFERRED |
| **WEAPON NOT READY** | Turret ready to fire | Waits until ready | X4 CODE |

---

## Table 6: Game and code names

Plain-language meaning for the names used above and in the mod's code.

| Name | In-game label | Plain meaning |
|---|---|---|
| `weaponmode.attackenemies` | Attack all enemies | Shoots any enemy from a list of targets the mod provides. |
| `weaponmode.autoassist` | (none; game default) | The game aims the turret itself and ignores any target list the mod sends. |
| `weaponmode.holdfire` | Hold fire | The turret does not fire. |
| `weaponmode.missiledefence` | Missile defence | Shoots incoming missiles, not ships. |
| `weaponmode.defend` | Defend | Fires only when defending, not on all enemies. |
| `set_turret_targets` | (none; internal) | The command that tells a ship's turrets what to shoot. Carries a list of targets, an optional "shoot this one first" target, and an optional limit to one mode. |
| preferred target | (none; internal) | The "shoot this one first" mark. The game honors it only if the turret can aim at that target; if it cannot, the turret uses the rest of the list. |
| Selected target (soft target) | your current selection | The target you pick out in the main Gunnery Console menu. The mod can set this, and Direct-control aims your turrets at it. |
| Locked target (hard target) | your locked target | The primary target your ship's own systems track, set by locking a target in the normal HUD. The mod **cannot** set this. Auto-assist turrets follow this target, which is why they ignore the mod's selection. |

*Some turret modes (Mine, Tow) appear in the game's turret menu but are not covered above because they are not built for shooting ships. Auto-assist has no menu label; it is the game's default when no other mode is chosen.*
