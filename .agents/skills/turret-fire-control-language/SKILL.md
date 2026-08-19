---
name: turret-fire-control-language
description: Use precise military/fire-control terminology when discussing turret targeting, engagement states, weapon UI labels, code comments, logs, or gameplay logic. Apply when distinguishing sensor contact, weapon range, turret traverse/elevation limits, firing/intercept solutions, blocked lines of fire, or weapon readiness. Do not use "no firing solution" merely to mean that an otherwise valid shot is physically obstructed.
---

# Turret fire-control terminology

Use the terminology in this skill whenever describing turret targeting or engagement logic. Keep the concepts below separate. Do not collapse them into a generic "can/cannot target" state.

## Core model

Treat turret engagement as a sequence of independent tests:

1. **Track** — Is there adequate target information for fire control?
2. **Range** — Can the weapon reach the required intercept?
3. **Firing arc** — Can the turret physically train/elevate to the required aim direction?
4. **Fire-control solution** — Can fire control compute a valid aim/intercept solution?
5. **Line of fire** — Is the projectile path sufficiently clear?
6. **Weapon readiness / authorization** — Is the weapon able and permitted to fire now?

A failure at one stage must not be described using terminology belonging to another stage.

## Canonical states

### ENGAGEABLE
Use when all conditions required for an otherwise permitted shot are satisfied:

- adequate fire-control track;
- target/intercept is within weapon range;
- required aim direction is within turret traverse/elevation limits;
- a valid fire-control/intercept solution exists; and
- line of fire is clear.

Meaning: **the turret has a valid shot.**

Preferred wording:
- `ENGAGEABLE`
- `Fire-control solution valid`
- `Valid engagement solution`

Do not use `TARGET ACQUIRED` as a synonym. Target acquisition/track does not imply that a shot is possible.

---

### LINE OF FIRE BLOCKED
Use when the turret otherwise has a valid engagement geometry/solution but the projectile path is obstructed by the firing platform, terrain, another object, or other intervening geometry.

Meaning: **the turret could point and solve the shot, but something blocks the line of fire.**

Preferred wording:
- `LINE OF FIRE BLOCKED`
- `Line of fire masked`
- `Shot masked`

Examples:
- another section of the ship is between the muzzle and intercept point;
- a station module blocks the shot;
- terrain or another vessel crosses the line of fire.

Do **not** call this `NO FIRING SOLUTION`. An obstruction does not by itself invalidate the computed fire-control solution.

---

### CANNOT BEAR
Use when the required aim direction lies outside the turret's mechanical traverse or elevation limits.

Meaning: **the gun physically cannot point where it needs to point.**

Preferred wording:
- `CANNOT BEAR`
- `Outside firing arc`
- `Train/elevation limit reached` when specifically describing the mechanical limit

Important: evaluate the **required aim/intercept direction**, not merely the target's instantaneous position. A target may currently appear inside the nominal turret arc while the required lead point lies outside it. In that case, classify the shot as `CANNOT BEAR`.

Do not call this `LINE OF FIRE BLOCKED`; a blocked line of fire means the required direction is reachable but the shot path is obstructed.

---

### NO FIRING SOLUTION
Use when adequate target information exists and the turret is not rejected merely by an obstruction, but fire control cannot compute a valid ballistic/intercept solution.

Meaning: **there is no valid aim direction/timing that satisfies the engagement model.**

Preferred wording:
- `NO FIRING SOLUTION`
- `No fire-control solution`
- `No intercept solution` when specifically discussing moving-target interception

Possible causes include:
- target kinematics make interception impossible under the weapon model;
- projectile velocity/ballistics cannot produce a valid intercept;
- required solution fails numerical or fire-control constraints.

Do not use `NO FIRING SOLUTION` merely because the line of fire is blocked, the turret cannot bear, the weapon is reloading, or fire is administratively inhibited.

---

### OUT OF RANGE
Use when the target or computed intercept exceeds the weapon's usable range.

Meaning: **the weapon cannot reach the required intercept.**

Preferred wording:
- `OUT OF RANGE`

Do not describe ordinary range failure as `NO FIRING SOLUTION` if the system can identify range as the actual reason engagement is impossible.

---

### NO WEAPONS-QUALITY TRACK
Use when the target may be detected but the available tracking information is insufficient to generate a fire-control solution.

Meaning: **contact exists, but targeting data are not adequate for fire control.**

Preferred wording:
- `NO WEAPONS-QUALITY TRACK`
- `INSUFFICIENT TRACK`

Distinguish this from `TARGET NOT DETECTED`, where the target is not detected at all.

If the game/system does not model detection and fire-control tracking separately, this state may be omitted.

---

### TARGET NOT DETECTED
Use when the target is not currently detected by the relevant sensor/targeting system.

Preferred wording:
- `TARGET NOT DETECTED`
- `OUT OF SENSOR RANGE` when range is specifically known to be the reason

Avoid saying `OUT OF RADAR RANGE` unless the system specifically uses radar. Prefer `sensor range` for a generic game/system sensor model.

---

### WEAPON NOT READY
Use when engagement geometry is otherwise valid but the weapon cannot currently fire for a weapon-state reason.

Examples:
- reloading;
- overheated;
- damaged or disabled;
- no ammunition;
- charging/cycling.

Preferred wording:
- `WEAPON NOT READY` as a category;
- use the specific state (`RELOADING`, `OVERHEATED`, `NO AMMO`, `DISABLED`) when known.

Do not call these conditions `NO FIRING SOLUTION`.

---

### FIRE NOT AUTHORIZED
Use when a shot is technically possible but firing is deliberately prohibited by logic, safety constraints, rules of engagement, friendly-fire protection, user settings, or another authorization layer.

Preferred wording:
- `FIRE NOT AUTHORIZED`

Do not call this `LINE OF FIRE BLOCKED` unless physical obstruction is actually the reason.

## Recommended decision precedence

When the UI needs to show exactly one reason a turret cannot fire, prefer the most specific actionable failure state using this order unless the project already defines another priority:

```text
TARGET NOT DETECTED
    ↓
NO WEAPONS-QUALITY TRACK
    ↓
OUT OF RANGE
    ↓
NO FIRING SOLUTION
    ↓
CANNOT BEAR
    ↓
LINE OF FIRE BLOCKED
    ↓
WEAPON NOT READY
    ↓
FIRE NOT AUTHORIZED
    ↓
ENGAGEABLE
```

This order is a presentation convention, not a claim that every fire-control system evaluates checks in that exact sequence. If multiple failures exist simultaneously, preserve the individual booleans internally even if the UI displays only one status.

## Preferred internal model

When designing code or data structures, prefer independent properties rather than a single overloaded targeting state. For example:

```text
has_contact
has_fire_control_track
in_weapon_range
has_intercept_solution
aim_point_in_arc
line_of_fire_clear
weapon_ready
fire_authorized
```

Then derive the displayed status from those properties.

Do not define `has_firing_solution` to include line-of-fire clearance, traverse limits, reload state, or authorization unless the existing codebase explicitly uses that broader definition and changing it would break compatibility. If an existing variable uses the term incorrectly, preserve behavior when necessary but recommend a clearer name.

## Terminology distinctions

Keep these distinctions explicit:

- **Contact / detected**: sensors know the target exists.
- **Track**: sufficient target state is available for targeting/fire control.
- **In arc**: turret can physically reach the required bearing/elevation.
- **Engageable**: a valid fire-control/intercept solution exists and the shot is otherwise geometrically valid.
- **Line of fire blocked**: line of fire is physically obstructed (masked).
- **Cannot bear**: turret cannot mechanically reach the required aim direction.
- **No firing solution**: fire control cannot obtain a valid ballistic/intercept solution.
- **Weapon ready**: the gun itself is capable of firing now.
- **Fire authorized**: higher-level logic permits the shot.

## Wording rules

When writing UI text, comments, variable names, documentation, or explanations:

1. Prefer `line of fire blocked` for a blocked line of fire (the physical condition may still be called *masking*).
2. Prefer `cannot bear` for traverse/elevation limitations.
3. Reserve `no firing solution` for inability to calculate/obtain a valid firing or intercept solution.
4. Use `engageable` when describing a turret that has a valid solution and can engage.
5. Do not use `target acquired`, `target locked`, `line of sight`, `firing solution`, and `in firing arc` interchangeably.
6. Distinguish **line of sight** from **line of fire** when relevant. A sensor may see/track a target even when the weapon's projectile path is masked.
7. Prefer terse uppercase labels for HUD/status displays and natural sentence case in prose.
8. When naming program variables, encode the actual predicate rather than military flavor alone; e.g. `lineOfFireClear` is preferable to an ambiguous `canEngage` when the property represents only obstruction testing.

## Example classifications

### Example 1
Target is detected and tracked; intercept is in range; turret can point at the required lead point; projectile path is clear; solution exists.

**State: `ENGAGEABLE`**

### Example 2
Target is detected and tracked; intercept is in range; turret can reach the required lead point; a valid solution exists; own-ship geometry blocks the muzzle-to-intercept path.

**State: `LINE OF FIRE BLOCKED`**

### Example 3
Target is detected and tracked, but the required lead point is beyond the turret's allowed traverse.

**State: `CANNOT BEAR`**

### Example 4
Target is detected and tracked; required direction is mechanically reachable; line of fire is not the limiting factor; no valid projectile intercept can be computed.

**State: `NO FIRING SOLUTION`**

### Example 5
Target's current bearing is inside the nominal firing arc, but leading the moving target requires aiming beyond the traverse stop.

**State: `CANNOT BEAR`**

### Example 6
Target is engageable and the line of fire is clear, but the gun is cycling after its previous shot.

**State: `WEAPON NOT READY`** (`RELOADING`/`CYCLING` if that detail is exposed)

## When asked to invent labels

When the user asks for menu labels, HUD states, code identifiers, tooltips, or documentation involving these concepts:

- first identify which predicate is actually being represented;
- choose terminology from this skill based on that predicate;
- keep labels short;
- explain a terminology distinction only when it affects the design decision;
- do not introduce extra military jargon merely for flavor.
