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

Where a behavior carries a confidence rating, it uses these labels, strongest first:

- **X4 CODE** — stated in Egosoft's own game scripts.
- **LIVE** — watched happen in game.
- **INFERRED** — worked out from the two above, not directly watched.
- **UNTESTED** — the mod has code for this, but it has not been confirmed in game.
- **UNKNOWN** — not known yet.

---

## Table 1: Firing situations

The situations that matter for this mod. Each is checked against **your target**.

| Situation | What it means |
|---|---|
| **ENGAGEABLE** | The turret can aim at the target, the target is in range, and nothing blocks the shot. A clean shot. |
| **OUT OF RANGE** | The target is farther away than the turret's weapons can reach. |
| **CANNOT BEAR** | The target is in a direction the turret cannot rotate or tilt far enough to aim at. For example, a turret on the top of the ship and a target directly below the ship. |
| **LINE OF FIRE BLOCKED** | The turret is aimed right at the target, but part of your own ship is between the turret and the target, blocking the shot. |
| **NO FIRING SOLUTION** | The turret can aim and the target is in range, but the target is moving in a way that leaves no shot that would connect. |
| **WEAPON NOT READY** | Aiming is fine, but the turret itself cannot fire right now: reloading, overheated, out of ammunition, or destroyed. |
| **FIRE NOT AUTHORIZED** | A shot is possible, but firing is held back on purpose: the group is on Hold fire, or the target is one you are not allowed to attack (friendly, surrendered, or captured). |

*Standard fire-control vocabulary also names TARGET NOT DETECTED (the target is not detected at all) and NO WEAPONS-QUALITY TRACK (detected, but too little tracking data to shoot). X4 does not simulate these as separate situations, and the console will not let you select a target it cannot detect, so they are left out here.*

**What the console's ENGAGEABLE ratio measures.** The `N / total ENGAGEABLE` value shown in Gunnery Control is a mod-computed geometric check, not a readout of an X4 firing state. It counts each checked turret only when all three conditions are true for the selected target:

- the turret has known arc data and its traverse arc contains the aim direction;
- the target is within weapon range; and
- a ray from the muzzle to the target passes without intersecting the firing ship.

The denominator is the count of all selected/evaluated turret members represented by the request, including members whose arc data are unknown. A turret with unknown or modded-macro arc coverage stays in the denominator but cannot enter the ENGAGEABLE numerator; its arc-unknown status is reported separately as UNKNOWN. The displayed ratio does **not** prove adequate fire-control track, a valid ballistic/intercept solution, weapon readiness, fire authorization, or actual firing. The generic fire-control concept `ENGAGEABLE` additionally assumes adequate track and a valid firing/intercept solution; weapon readiness and fire authorization remain separate states.

---

## Table 2: Turret group modes

The modes a turret group can be in. The in-game label is exactly what X4 shows in the turret mode menu, and they are listed here in the order that menu lists them.

Five of these are **restrict** or **prioritise** modes. "Attack only X" means the turret will not engage anything outside class X. "Attack X first" is not a restriction at all — it is Attack all enemies with a sort order, so anything can still be shot.

| In-game label | What the group does |
|---|---|
| **Defend** | Fires only when defending against a threat, not on all enemies. |
| **Attack all enemies** | Shoots any enemy in range. This is what every ticked group is set to. |
| **Attack only capital ships** | Will not engage anything smaller than a capital ship. |
| **Attack capital ships first** | Shoots any enemy, capital ships preferred. Not a restriction. |
| **Attack only fighters** | Will not engage anything larger than a fighter. |
| **Attack fighters first** | Shoots any enemy, fighters preferred. Not a restriction. |
| **Shoot only missiles** | Shoots incoming missiles, not ships. |
| **Shoot missiles first** | Shoots any enemy, missiles preferred. Not a restriction. |
| **Attack my current enemy** | X4's automatic mode. The game picks the turret's target itself. |
| **Mining** | Turret task built for asteroids. |
| **Towing** | Turret task not built for shooting. Towing is the single mode X4's own combat AI skips when it hands out targets, and the single mode it excludes when it orders a cease-fire. |
| **Hold fire** *(not in the menu)* | Does not fire. X4 uses Hold fire as its own way to make a ship stop shooting — a fleeing ship is put on Hold fire without its target list being cleared. |

**Hold fire is not a mode you can pick.** It is absent from X4's turret mode menu entirely. A group is only in Hold fire because a script, a fleet order, or this mod put it there.

---

## Table 3: Direct-control

Direct-control aims your ticked turrets at the target you selected, and also sends them the other targets in range to switch to if they cannot hit your target.

**Assumed in this table:** every ticked group is on **Attack all enemies** and is **armed** (Direct-control arms your ticked groups for you when you engage). A **not-armed** group never fires; see [Global rules](#global-rules). "Own mode" columns describe an unticked group left in some other mode.

| Situation (vs your target) | Ticked group — pilot attacking OR idle, same result | Unticked, pilot attacking | Unticked, pilot idle |
|---|---|---|---|
| **ENGAGEABLE** | Shoots your target. **LIVE** | Ignores your target. Shoots enemies per its own mode | Ignores your target. Does whatever its own mode does |
| **OUT OF RANGE** | Switches to another target it can reach. **LIVE** | Own mode | Own mode |
| **CANNOT BEAR** | Switches to another target it can aim at. **LIVE** | Own mode | Own mode |
| **LINE OF FIRE BLOCKED** | Stays aimed at your target and does **not** fire. Does **not** switch to another target. **LIVE** | Own mode | Own mode |
| **NO FIRING SOLUTION** | Fires at your target and misses; keeps trying. Does not switch, because X4 does not detect this situation. **INFERRED** | Own mode | Own mode |
| **WEAPON NOT READY** | Holds until the turret is ready. A destroyed turret is skipped, and re-included if it survives. **X4 CODE** | Own mode | Own mode |
| **FIRE NOT AUTHORIZED** | Ticked groups are on Attack all enemies, so they never hold fire on their own. If your target can no longer be attacked, see [Global rules](#global-rules). **UNTESTED** | Own mode | Own mode |

**Why LINE OF FIRE BLOCKED behaves differently from CANNOT BEAR.** X4 decides whether to switch to another target by asking only whether the turret can *aim* at your target, not whether it can *hit* it. A turret with a blocked line of fire is aimed straight at your target, so the game counts it as fine and never switches. A turret that cannot bear cannot aim at your target at all, so the game switches it to another target. Nothing the mod sends changes this, because the decision to switch is the game engine's, not the mod's.

---

## Table 4: Auto-engage

Auto-engage lets you watch your ticked turret groups. Because they are ticked, they are on **Attack all enemies**. Auto-engage does not tell any turret which target to shoot; each turret picks its own target.

| Group | Behavior | Confidence |
|---|---|---|
| **Ticked** | On Attack all enemies. The game picks each turret's target and handles every firing situation on its own. Fires only if armed. | X4 CODE |
| **Unticked** | Left in its own mode, unchanged. | X4 CODE |

Because the mod tells no turret what to shoot in Auto-engage, each situation plays out the way X4 handles it normally. A ticked turret that cannot aim at the target *it* chose will switch to another on its own.

---

## Global rules

These apply on top of everything above.

- **Not armed means no fire.** A turret group that is not armed does not fire, whatever its mode or your selection. Direct-control arms your ticked groups when you engage. In Auto-engage, a group keeps whatever armed state you gave it.
- **When your target can no longer be attacked** (it is destroyed, surrenders, or changes owner), one of two things happens under Direct-control. If **Auto-next target** is on (the default) and there is another target in range, Direct-control moves to that target automatically. Otherwise, the target-selection screen reopens and you pick again. When a target changes owner or otherwise stops being one you are allowed to attack, X4's own combat AI notices on its own: it stops firing at it, drops it from its target lists, and picks a new target. That part is the game's doing, not the mod's. **X4 CODE**
- **Selecting part of a ship.** You can select one component (a specific turret or engine) instead of a whole ship. Direct-control aims at that component, and the situations in Table 1 apply to it the same way.
- **Standing up.** When you stand up from the console, every turret group goes back to the mode and armed state it had before you sat down. The one exception is if you pressed **Update turret behavior**, which makes your current settings the ones it returns to instead.

---

## Technical detail

For readers who want the mechanism.

**Ticked groups (the fallback list).** When you engage in Direct-control, the mod sends each ticked group two instructions: first your target alone, then your target plus every other enemy in range, both marked "shoot this one first." This is the `DirectFallback` action. Because your target is marked preferred and the others are also supplied, a turret that cannot aim at or reach your target has a ready set to switch to. This action is limited to groups on Attack all enemies, which is exactly what ticked groups are.

What the game itself checks, per situation, for a ticked turret:

| Situation | What the game checks | Result | Confidence |
|---|---|---|---|
| **ENGAGEABLE** | Can aim, in range, shot clear | Shoots your target | LIVE |
| **OUT OF RANGE** | Distance vs the turret's reach | Switches to another target in range | LIVE |
| **CANNOT BEAR** | Can the turret aim that far | Switches to another target it can aim at | LIVE |
| **LINE OF FIRE BLOCKED** | Is the shot path clear of your own ship | Stays aimed, holds fire, does not switch | LIVE |
| **NO FIRING SOLUTION** | (the game runs no such check) | Fires and misses | INFERRED |
| **WEAPON NOT READY** | Turret ready to fire | Waits until ready | X4 CODE |

---

## Table 6: Game and code names

Plain-language meaning for the names used above and in the mod's code.

| Name | In-game label | Plain meaning |
|---|---|---|
| `weaponmode.attackenemies` | Attack all enemies | Shoots any enemy from a list of targets the mod provides. |
| `weaponmode.autoassist` | Attack my current enemy | The game aims the turret itself and ignores any target list the mod sends. |
| `weaponmode.holdfire` | (none; not in the turret menu) | The turret does not fire. Only a script can put a group in this mode. |
| `weaponmode.missiledefence` | Shoot only missiles | Shoots incoming missiles, not ships. |
| `weaponmode.defend` | Defend | Fires only when defending, not on all enemies. |
| `set_turret_targets` | (none; internal) | The command that tells a ship's turrets what to shoot. Carries a list of targets, an optional "shoot this one first" target, and an optional limit to one mode. |
| preferred target | (none; internal) | The "shoot this one first" mark. The game honors it only if the turret can aim at that target; if it cannot, the turret uses the rest of the list. |
| Selected target (soft target) | your current selection | The target you pick out in the main Gunnery Console menu. The mod can set this, and Direct-control aims your turrets at it. |
| Locked target (hard target) | your locked target | The primary target your ship's own systems track, set by locking a target in the normal HUD. The mod **cannot** set this. Turrets on Attack my current enemy follow this target, which is why they ignore the mod's selection. |

*Table 2 lists every mode the game's turret menu offers, plus Hold fire, which the menu does not offer and only a script can set.*
