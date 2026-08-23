# Turret behavior by firing situation

What your turrets do in each firing situation, under Direct-control and under Auto-engage. This document describes only what is built and known today. It is updated as more becomes known.

## Terms used here

These words mean one specific thing throughout this document.

- **Your target** — the target you selected in Direct-control.
- **Another target** — any other enemy target within radar range.
- **Aim at** — a turret can physically rotate and tilt to point at something.
- **Switch to** — a turret gives up on your target and shoots a different target instead.
- **Other targets in range** — the enemy targets a turret is allowed to switch to. Under the **Attack all enemies** Direct-control turret mode, Direct-control sends this set to your ticked turrets along with your target; under **Attack my current enemy** it is not sent.
- **Ticked group** — a turret group with its checkbox ticked in the main Gunnery Console. When you engage Direct-control, ticked groups are set to the **Direct-control turret mode** you selected. See the modes table below.
- **Direct-control turret mode** — the mode Direct-control applies to your ticked groups, chosen from a selector on the main console and on the Direct-control panel. Either **Attack all enemies** (preferred target with a fallback list) or **Attack my current enemy** (strict selected target, no fallback). Changing it while engaged re-applies it immediately.
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
| **ENGAGEABLE** | Generic fire-control condition: adequate track, the turret can aim at the target, the target is in range, nothing blocks the shot, and a valid firing/intercept solution exists. |
| **OUT OF RANGE** | The target is farther away than the turret's weapons can reach. |
| **CANNOT BEAR** | The target is in a direction the turret cannot rotate or tilt far enough to aim at. For example, a turret on the top of the ship and a target directly below the ship. |
| **LINE OF FIRE BLOCKED** | The turret can bear on the target, but an obstruction masks a required projectile path. The obstruction may be the firing ship, terrain, or another object; guided missile turrets do not use a direct muzzle-to-target path for the console's geometry check. |
| **NO FIRING SOLUTION** | The turret can aim and the target is in range, but the target is moving in a way that leaves no shot that would connect. |
| **WEAPON NOT READY** | Aiming is fine, but the turret itself cannot fire right now: reloading, overheated, out of ammunition, or destroyed. |
| **FIRE NOT AUTHORIZED** | A shot is possible, but firing is held back on purpose: the group is on Hold fire, or the target is one you are not allowed to attack (friendly, surrendered, or captured). |

*Standard fire-control vocabulary also names TARGET NOT DETECTED (the target is not detected at all) and NO WEAPONS-QUALITY TRACK (detected, but too little tracking data to shoot). X4 does not simulate these as separate situations, and the console will not let you select a target it cannot detect, so they are left out here.*

**What the console's ENGAGEABLE ratio measures.** The `N / total ENGAGEABLE` value shown in Gunnery Control is a mod-computed geometric check, not a readout of an X4 firing state. It counts each checked turret only when its bearing and range gates pass and its weapon-specific direct-line policy passes:

- the turret has known arc data and its traverse arc contains the aim direction;
- the target is within weapon range, measured as bounding-box distance (`bboxdistanceto`) against the weapon's max fire range rather than center-to-center distance, so reachable hull or modules on a large ship or station count as in range even when the center is far; and
- the applicable direct-line policy passes:
  - a conventional turret requires a clear muzzle-to-target line of fire that includes its own ship, so its own hull or an external object can mask the shot;
  - an unguided missile turret requires a clear direct line that excludes its own ship, so its own hull does not mask a viable launch but terrain or another object still does; ammunition with missing or unrecognized guidance data takes this conservative unguided path; and
  - a missile turret with affirmatively guided loaded ammunition does not require a direct muzzle-to-target line, because the missile can steer after launch. Bearing and range remain mandatory.

When a required direct ray against a whole ship or station root is blocked — a large root's aim point may be its bounding-box centre, which sits inside the target hull — and the root is a targetable modular object with more than one operational module (a station, or a capital ship with an embedded targetable defence module), the check falls back to that root's operational and construction modules and counts the turret if any one is reachable under the same weapon-specific policy. An individually selected surface element keeps its own direct-line policy and does not use this fallback.

The source-backed rationale and live-test boundaries are recorded in the knowledge base under [missile guidance](../.agents/skills/research-x4-modding/references/md-ai.md#missile-guidance-is-a-shipped-fire-control-discriminator-but-missile-turret-launch-los-is-engine-side), [guided missile turrets](../.agents/skills/research-x4-modding/references/md-ai.md#guided-missiles-launch-through-an-own-hull-masked-direct-ray-and-reach-the-designated-surface), and [unguided missile turrets](../.agents/skills/research-x4-modding/references/md-ai.md#unguided-missile-turrets-ignore-own-hull-but-retain-an-external-direct-line-check).

The denominator is the count of all selected/evaluated turret members represented by the request, including members whose arc data are unknown. A turret with unknown or modded-macro arc coverage stays in the denominator but cannot enter the ENGAGEABLE numerator; its arc-unknown status is reported separately as UNKNOWN. The displayed ratio does **not** prove adequate fire-control track, a valid ballistic/intercept solution, weapon readiness, fire authorization, or actual firing — the bounding-box range gate and the per-module line-of-fire fallback are geometry evidence only. The generic fire-control concept `ENGAGEABLE` additionally assumes adequate track and a valid firing/intercept solution; weapon readiness and fire authorization remain separate states.

---

## Table 2: Turret group modes

The modes a turret group can be in. The in-game label is exactly what X4 shows in the turret mode menu, and they are listed here in the order that menu lists them.

Five of these are **restrict** or **prioritise** modes. "Attack only X" means the turret will not engage anything outside class X. "Attack X first" is not a restriction at all — it is Attack all enemies with a sort order, so anything can still be shot.

| In-game label | What the group does |
|---|---|
| **Defend** | Fires only when defending against a threat, not on all enemies. |
| **Attack all enemies** | Shoots any enemy in range. One of the two Direct-control turret modes: it aims ticked groups at your target with the other enemies in range as a fallback list. |
| **Attack only capital ships** | Will not engage anything smaller than a capital ship. |
| **Attack capital ships first** | Shoots any enemy, capital ships preferred. Not a restriction. |
| **Attack only fighters** | Will not engage anything larger than a fighter. |
| **Attack fighters first** | Shoots any enemy, fighters preferred. Not a restriction. |
| **Shoot only missiles** | Shoots incoming missiles, not ships. |
| **Shoot missiles first** | Shoots any enemy, missiles preferred. Not a restriction. |
| **Attack my current enemy** | The other Direct-control turret mode: ticked groups follow the target you selected strictly, with no fallback list, so a turret that cannot engage it may sit idle. Outside Direct-control this is X4's automatic mode, where the game picks the turret's target itself. |
| **Mining** | Turret task built for asteroids. |
| **Towing** | Turret task not built for shooting. Towing is the single mode X4's own combat AI skips when it hands out targets, and the single mode it excludes when it orders a cease-fire. |
| **Hold fire** *(not in the menu)* | Does not fire. X4 uses Hold fire as its own way to make a ship stop shooting — a fleeing ship is put on Hold fire without its target list being cleared. |

**Hold fire is not a mode you can pick.** It is absent from X4's turret mode menu entirely. A group is only in Hold fire because a script, a fleet order, or this mod put it there.

---

## Table 3: Direct-control

Direct-control aims your ticked turrets at the target you selected. When you engage, you pick a **Direct-control turret mode** from the selector on the main console or the Direct-control panel:

- **Attack all enemies** — your selected target is the preferred target, and Direct-control also sends every other enemy in range as a fallback. A turret that cannot hit your target can switch to one of those.
- **Attack my current enemy** — your selected target is strict. No fallback list is sent, so a turret that cannot engage your target may sit idle rather than switch to something else.

Changing the mode while engaged re-applies it to your ticked groups at once. Legacy saves from before the selector default to **Attack all enemies**.

**Assumed in this table:** every ticked group is **armed** (Direct-control arms your ticked groups for you when you engage). A **not-armed** group never fires; see [Global rules](#global-rules). Where the two Direct-control turret modes differ, the ticked column names both; otherwise the behavior is the same for both. "Own mode" columns describe an unticked group left in some other mode.

| Situation (vs your target) | Ticked group — pilot attacking OR idle, same result | Unticked, pilot attacking | Unticked, pilot idle |
|---|---|---|---|
| **ENGAGEABLE** | Shoots your target. **LIVE** | Ignores your target. Shoots enemies per its own mode | Ignores your target. Does whatever its own mode does |
| **OUT OF RANGE** | **Attack all enemies:** switches to another target it can reach. **Attack my current enemy:** no fallback, so it may sit idle. **LIVE** | Own mode | Own mode |
| **CANNOT BEAR** | **Attack all enemies:** switches to another target it can aim at. **Attack my current enemy:** no fallback, so it may sit idle. **LIVE** | Own mode | Own mode |
| **LINE OF FIRE BLOCKED** | Stays aimed at your target and does **not** fire. Does **not** switch to another target. **LIVE** | Own mode | Own mode |
| **NO FIRING SOLUTION** | Fires at your target and misses; keeps trying. Does not switch, because X4 does not detect this situation. **INFERRED** | Own mode | Own mode |
| **WEAPON NOT READY** | Holds until the turret is ready. A destroyed turret is skipped, and re-included if it survives. **X4 CODE** | Own mode | Own mode |
| **FIRE NOT AUTHORIZED** | Neither Direct-control turret mode holds fire on its own. If your target can no longer be attacked, see [Global rules](#global-rules). **UNTESTED** | Own mode | Own mode |

**Why LINE OF FIRE BLOCKED behaves differently from CANNOT BEAR.** This applies to the **Attack all enemies** mode, where a fallback list is sent. X4 decides whether to switch to a fallback target by asking only whether the turret can *aim* at your target, not whether it can *hit* it. A turret with a blocked line of fire is aimed straight at your target, so the game counts it as fine and never switches. A turret that cannot bear cannot aim at your target at all, so the game switches it to a fallback target. Nothing the mod sends changes this, because the decision to switch is the game engine's, not the mod's. Under **Attack my current enemy** no fallback is sent, so nothing switches in either case.

---

## Table 4: Auto-engage

Auto-engage lets you watch your ticked turret groups. It puts them on **Attack all enemies**, independent of the Direct-control turret mode selector, and does not tell any turret which target to shoot; each turret picks its own target.

| Group | Behavior | Confidence |
|---|---|---|
| **Ticked** | On Attack all enemies. The game picks each turret's target and handles every firing situation on its own. Fires only if armed. | X4 CODE |
| **Unticked** | Left in its own mode, unchanged. | X4 CODE |

Because the mod tells no turret what to shoot in Auto-engage, each situation plays out the way X4 handles it normally. A ticked turret that cannot aim at the target *it* chose will switch to another on its own.

---

## Global rules

These apply on top of everything above.

- **Not armed means no fire.** A turret group that is not armed does not fire, whatever its mode or your selection. Direct-control arms your ticked groups when you engage. In Auto-engage, a group keeps whatever armed state you gave it.
- **When your target can no longer be attacked** (it is destroyed, surrenders, or changes owner), what happens next depends on **Auto-next target**. If it is off, the target-selection screen reopens and you pick again. If it is on (the default), Direct-control moves on automatically. When the lost target was a surface element, it tries candidates in this order: the other ENGAGEABLE surface elements on the same ship or station, ranked and paged 20 at a time; then that root's hull; then, if none of those work, the other objects in range, ranked. When a target changes owner or otherwise stops being one you are allowed to attack, X4's own combat AI notices on its own: it stops firing at it, drops it from its target lists, and picks a new target. That part is the game's doing, not the mod's. **X4 CODE**
- **Selecting part of a ship.** You can select one component (a specific turret or engine) instead of a whole ship. Direct-control aims at that component, and the situations in Table 1 apply to it the same way.
- **Standing up.** When you stand up from the console, every turret group goes back to the mode and armed state it had before you sat down. The one exception is if you pressed **Update turret behavior** — the commit button on the main console, not the engaged panels — which makes your current settings the ones it returns to instead.

---

## Technical detail

For readers who want the mechanism.

**How the Direct-control turret mode is applied.** When you engage in Direct-control, the mod applies the selected turret mode to each ticked group:

- **Attack all enemies** (`attackenemies`) sends each ticked group two instructions: first your target alone, then your target plus every other enemy in range, both marked "shoot this one first." This is the `DirectFallback` action, and it only applies to groups on `attackenemies`. Because your target is marked preferred and the others are also supplied, a turret that cannot aim at or reach your target has a ready set to switch to.
- **Attack my current enemy** (`autoassist`) sets each ticked group to `autoassist` pointed at your selected soft target/surface element, and installs no fallback list. A turret that cannot engage your target has nothing to switch to and may sit idle.

What the game itself checks, per situation, for a ticked turret on **Attack all enemies** (with the fallback list). Under **Attack my current enemy** the switch results do not apply, because no fallback list is sent:

| Condition | What the game checks | Result | Confidence |
|---|---|---|---|
| **AIM / RANGE / LINE CLEAR** | Can aim, in range, shot clear | Shoots your target | LIVE |
| **OUT OF RANGE** | Distance vs the turret's reach | Switches to a fallback target in range | LIVE |
| **CANNOT BEAR** | Can the turret aim that far | Switches to a fallback target it can aim at | LIVE |
| **LINE OF FIRE BLOCKED** | Is the weapon's required projectile path obstructed | Stays aimed, holds fire, does not switch | LIVE |
| **NO FIRING SOLUTION** | (the game runs no such check) | Fires and misses | INFERRED |
| **WEAPON NOT READY** | Turret ready to fire | Waits until ready | X4 CODE |

---

## Table 6: Game and code names

Plain-language meaning for the names used above and in the mod's code.

| Name | In-game label | Plain meaning |
|---|---|---|
| `weaponmode.attackenemies` | Attack all enemies | Shoots any enemy from a list of targets the mod provides. |
| `weaponmode.autoassist` | Attack my current enemy | Follows a single current target rather than a mod-supplied list. Under the Direct-control **Attack my current enemy** mode the mod points it at your selected soft target and sends no fallback list; outside Direct-control the game aims it itself. |
| `weaponmode.holdfire` | (none; not in the turret menu) | The turret does not fire. Only a script can put a group in this mode. |
| `weaponmode.missiledefence` | Shoot only missiles | Shoots incoming missiles, not ships. |
| `weaponmode.defend` | Defend | Fires only when defending, not on all enemies. |
| `set_turret_targets` | (none; internal) | The command that tells a ship's turrets what to shoot. Carries a list of targets, an optional "shoot this one first" target, and an optional limit to one mode. |
| preferred target | (none; internal) | The "shoot this one first" mark. The game honors it only if the turret can aim at that target; if it cannot, the turret uses the rest of the list. |
| Selected target (soft target) | your current selection | The target you pick out in the main Gunnery Console menu. The mod can set this, and Direct-control aims your turrets at it. |
| Locked target (hard target) | your locked target | The primary target your ship's own systems track, set by locking a target in the normal HUD. The mod **cannot** set this. Under Direct-control, the mod drives turrets through the soft target instead — including the **Attack my current enemy** mode, which follows your selected soft target. |

*Table 2 lists every mode the game's turret menu offers, plus Hold fire, which the menu does not offer and only a script can set.*
