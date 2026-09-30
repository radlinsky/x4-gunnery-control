# Turret behavior by firing situation

Current Direct-control and Auto-engage behavior, with the mod’s range and distance estimates separated from X4’s firing decisions. Auto-next rules are implemented and accepted OFFLINE for issue #197 P3; end-to-end LIVE acceptance remains pending in P5.

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
| **ENGAGEABLE** | Generic fire-control condition: the turret can aim at the target, the target is in range, nothing blocks the shot, a valid FIRING SOLUTION exists, and firing at that target is authorized. |
| **OUT OF RANGE** | The target is farther away than the turret's weapons can reach. |
| **CANNOT BEAR** | The target is in a direction the turret cannot rotate or tilt far enough to aim at. For example, a turret on the top of the ship and a target directly below the ship. |
| **LINE OF FIRE BLOCKED** | The turret can bear on the target, but an obstruction masks a required projectile path. The obstruction may be the firing ship, terrain, or another object; native tracing indicates guided loaded missiles bypass X4’s pre-fire obstruction check; that does not guarantee a hit. See [obstruction evidence](../.agents/skills/research-x4-modding/references/weapon-path-obstruction-groups.md) (**INFERRED**). |
| **NO FIRING SOLUTION** | The turret can aim and the target is in range, but the target is moving in a way that leaves no shot that would connect. |
| **WEAPON NOT READY** | A weapon cannot fire, for example because it is destroyed, reloading, or out of ammunition. Destroyed turrets are excluded from Direct-control and IN RANGE counts. |
| **FIRE NOT AUTHORIZED** | A shot is possible, but firing is held back on purpose: the group is on Hold fire, or the target is one you are not allowed to attack (friendly, surrendered, or captured). |

*Standard fire-control vocabulary also names TARGET NOT DETECTED (the target is not detected at all). The console will not let you select a target it cannot detect, so this is left out here. Gunnery Control does not use a separate target-information condition: any target position or movement information needed to make a shot is part of whether a valid FIRING SOLUTION exists.*

## What the console estimates

**IN RANGE** is the only production turret prediction. `N / total IN RANGE` counts unique operational turret members in ticked groups whose range estimate passes for that target. For example, `3 / 4 IN RANGE` means three of four members pass; it does not mean three can aim or fire. The console has no ENGAGEABLE, CLEAR LINE OF FIRE, CAN AIM, or separate selected-detail calculation.

For each turret, the mod uses:

```text
R = turret.maxfirerange
IN RANGE iff R > 0 and target.bboxdistanceto.{turret} < R + extra
```

`extra` is `min(1.1 × R, 500 m)` for non-beam ammunition against a ship with positive maximum speed or an engine on that ship; otherwise it is zero. This tests capability to move, not current motion. Stations and their elements, and turret/shield elements on ships, receive no allowance. Range comes from the weapon’s current ammunition and equipment state.

**Native range evidence — INFERRED, X4 9.00 build 611726.** Static native tracing indicates that X4’s pre-fire range gate accepts either muzzle-to-aim-point distance (including lead) or turret-origin-to-target-oriented-box distance below the adjusted range. The mod approximates only the box branch with `target.bboxdistanceto.{turret}`. It can report OUT OF RANGE when X4’s other branch would accept the shot. Approximate square-root rounding and different evaluation times also affect boundaries. This is range evidence only: bearing, intercept, obstructions, readiness, authorization, and actual firing remain X4’s decisions. See the [range-gate evidence and limits](../.agents/skills/research-x4-modding/references/turret-fire-range-gate.md).

**Distance** is the approximate origin-to-origin distance from your ship to the target or exact surface element, displayed in kilometres. It is distinct from the turret-to-target-box distance used for IN RANGE and is not a weapon-range test.

Browser sweeps automatically check one selected operational turret across the visible targets before advancing to the next turret, including the pinned selected target. Completed browsing sweeps repeat after a one-second delay and pause with the game. Displayed counts can be partial or from an earlier sweep; Auto-next requires fresh results (see Auto-next replacement rules). The object browser puts candidates with every evaluated turret IN RANGE first, then sorts by relation, distance, and name. Surface pages keep size/type/distance ordering, 10 rows at a time. List refresh controls are separate from the automatic range sweeps.

The generic firing situations above describe game behavior, not console status labels. Historical geometry and obstruction research remains in the [research index](../.agents/skills/research-x4-modding/references/index.md); it is not a production firing predictor.

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
| **WEAPON NOT READY** | A destroyed turret is skipped because it cannot be Direct-controlled. **X4 CODE** | Own mode | Own mode |
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
- **When your target is destroyed or no longer operational,** Auto-next searches for a replacement as described below. With Auto-next off, the target browser reopens for manual selection. **An ownership change is different:** if the selected target remains operational but becomes unattackable, Gunnery Control refreshes the directed turrets’ fallback targets without automatically changing your selected target or camera. Surrender alone is not established as an Auto-next trigger. Separately, X4’s shipped combat AI can stop firing and revise its own target lists when attack permission is lost; `autoassist` has its own cease-fire handling. These are documented script paths, not a universal engine guarantee. **X4 CODE** — see [combat AI evidence](../.agents/skills/research-x4-modding/references/md-ai.md).
- **Selecting part of a ship.** You can select one component (a specific turret or engine) instead of a whole ship. Direct-control aims at that component, and the situations in Table 1 apply to it the same way.
- **Standing up.** When you stand up from the console, every turret group goes back to the mode and armed state it had before you sat down. The one exception is if you pressed **Update turret behavior** — the commit button on the main console, not the engaged panels — which makes your current settings the ones it returns to instead.

## Auto-next replacement rules

Auto-next is on by default. Every automatic replacement must be attackable and have **at least one** selected operational Direct-controlled turret IN RANGE before it can compete for selection. All selected turrets need not pass; a higher count does not win priority. Stale scans cannot supply a replacement. An incomplete scan can, but only for the top-ranked attackable candidate (the nearest object, or the first surface in size, type and distance order) once any selected turret reports it IN RANGE, because nothing else can outrank it.

1. **Lost surface element:** check other operational surfaces on the original ship/station in 20-row pages. Require fresh IN RANGE results for each page; a page completes before the next unless its top-ranked surface engages early. Among qualifying surfaces, choose the first by size (XL → L → M → S → XS), then type (turret → shield → engine), then distance. A farther large turret outranks a nearer small shield.
2. **Original hull:** if no surface qualifies, check that ship/station hull with a fresh, complete IN RANGE sweep.
3. **Target browser:** if the hull does not qualify, visibly open the browser and scan there. Ordinary ship/station loss starts here directly. Enemy and hostile attackable ships/stations compete equally; choose the closest qualifying object using distance measured after the sweep.

Only the target-browser stage has a **three-attempt limit**. Each fresh scan attempt counts, including failed or incomplete scans; selection requires complete results except for the top-ranked early engagement above. With no eligible enemy/hostile candidates, return immediately to manual selection without scanning. After three attempts without a replacement, leave the browser open for manual selection. Same-root surface pages and the original hull follow their established order without that limit.

Attack eligibility and selected operational turret membership are rechecked before engagement. A candidate that is lost after a complete scan is skipped; the other candidates keep that scan’s results. Auto-next keeps the camera POV the player had (Turret or Target, manual or cinematic). The browser shows Turret POV manual while it scans; a manual pick from the browser starts in Turret POV manual. Manual engagement, disabling Auto-next, returning to the console, or ending the session cancels the automatic process. These mod rules do not change X4’s per-turret fallback behavior in Table 3.

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
| **WEAPON NOT READY** | Is the turret destroyed | Destroyed turret is skipped | X4 CODE |

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
| Locked target (hard target) | your locked target | The primary target your ship's own systems hold as the locked target, set by locking a target in the normal HUD. The mod **cannot** set this. Under Direct-control, the mod drives turrets through the soft target instead — including the **Attack my current enemy** mode, which follows your selected soft target. |

*Table 2 lists every mode the game's turret menu offers, plus Hold fire, which the menu does not offer and only a script can set.*
