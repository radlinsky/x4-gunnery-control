# Turret fire-range gate

Scope: X4 9.00 build 611726, the pinned `X4.exe` (SHA-256
`19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`, image base
`0x140000000`); see [native-analysis.md](native-analysis.md). Unless stated,
RVAs are real code addresses and every behavioral label ("fallback", "range
extension", "aim gate") is an analyst label, not a recovered native name. RTTI
class names (`U::Turret`, `U::Station`, shoot controllers) are real.

Use this before designing or changing any IN RANGE predicate. It separates the
engine's pre-fire range decision from the shipped AI's `bboxdistanceto`
heuristics.

### The engine range test lives in the common pre-fire gate

- X4: 9.00 build 611726
- Status: inference
- Source: native trace; pre-fire gate `0x00816D20` (the same function recorded
  in [weapon-path-obstruction-groups.md](weapon-path-obstruction-groups.md)),
  range section `0x00817808`–`0x00817981`
- Live test: no — static trace only
- Finding: every non-player shoot controller runs one range test before the
  obstruction section. Player-controlled weapons skip it: controller slot
  `+0x80` is true only for `U::PlayerShootController`, and a true result jumps
  straight to the permit path at `0x0081782A`. Pseudocode:

```text
R  = weapon.vslot_1EF0(useDefaultAmmo=false)        # same call as MD maxfirerange
Re = R
if |R| >= 1e-4 and not ammo.isbeam and target and not target.vslot_15D0():
    Re = R + min(R * params.maxshotrangefactor, params.maxextrashotrange)
if R > 0:
    if approx_len(aimPoint - muzzle) >= Re:                     # primary
        if GetDistanceSqTo(target, weapon, mode=2) >= Re*Re:     # fallback
            notify controller; return NO FIRE
# continue to the aim/obstruction sections
```

The two distance tests are OR-ed: either one passing keeps the shot alive.
The range section runs before the guided-ammunition obstruction bypass at
`0x008179A1`, so guided missiles are range-gated too. An out-of-range result
does not set the LINE OF FIRE BLOCKED flag.

### Primary distance: selected muzzle to the controller's aim point

- X4: 9.00 build 611726
- Status: inference
- Source: native trace; `0x00816FC0` builds the selected-connection transform
  (`0x0081CB80`) in the weapon's zone through `0x003DB8A0`; the controller's
  aim method (slot `+0xA8`, called at `0x008174C4`) writes the aim position;
  `0x00817602`–`0x00817675` forms the difference and its length
- Live test: no
- Finding: the primary length is from the weapon's selected firing
  connection (the same endpoint family as `barrelposition`) to the aim point
  that the shoot controller just computed, including lead. It uses
  `rcpss(rsqrtss(x))`, an approximate square root (roughly 1e-3 relative error).
  The target itself is the controller's assigned target at controller `+0x10`
  (slot `+0x88` is `0x007E5D30` for Basic, LargeTarget, Multiple and Player
  controllers). `U::LargeTargetShootController` does not substitute a module or
  surface element here.

### Fallback distance: turret origin to the target's own oriented bounding box

- X4: 9.00 build 611726
- Status: inference
- Source: native trace; call `0x008178FC` → `GetDistanceSqTo`
  (`0x003E1930`, identified by its own error strings) with `this=target`,
  `other=weapon`, mode 2 → `0x003E0C40` → `0x003E04C0` → target vtable slot
  `+0x14E0` (`0x00747100` for Object/Ship/Station/Module/Turret/Weapon)
- Live test: no
- Finding: the fallback is the exact squared distance from the **weapon
  component's origin** to the **target's own box**, measured in the target's
  local frame. Slot `+0x14E0` transforms the point into target space and clamps
  per axis against the half-extents/centre from slot `+0x14B0`, so the box is
  oriented with the target. Rotating the target changes the result through that
  orientation. Rotating the turret does not, because only the turret
  component's origin is used. Both callers pass the two `0x00747100` flag bytes
  as 1, which selects the slot-`+0x14B0` box and skips the child-component
  recursion (`0x00747390`). Nothing is cached: the transforms are evaluated at
  the current time on every call.

Which box slot `+0x14B0` returns, by class (vtable reads):

| Target class | Slot `+0x14B0` | Box |
|---|---|---|
| `U::Ship` (also Object/Defensible/Container/Asteroid) | `0x006DF940` | macro box `macro + 0x140`; it delegates to a child object's box only when macro-data flag `+0x8F2` is set and a child list exists |
| `U::Station` | `0x007EB460` | instance box at `this + 0xC90`, not the macro box |
| `U::Module`, `U::Turret`, `U::Weapon` (surface elements) | `0x0034EE10` → `+0x14A8` | the component's own macro box `macro + 0x140` |

A whole ship or station is therefore measured against its own root box, not a
module or surface element. A selected surface element or module is measured
against its own box, not its parent's.

### The range value and the extension parameters

- X4: 9.00 build 611726
- Status: inference
- Source: native trace; weapon slot `+0x1EF0` = `0x007C7350`
  (`U::Weapon`/`U::Turret`) and `0x00609270`
  (`U::MissileTurret`/`U::MissileLauncher`); MD `maxfirerange` handler
  `0x00D01971` (component-property jump table `0x00D0BDF0`, index = keyword −
  3, `maxfirerange` = keyword `0x370`); parameter loader `0x0060D940`,
  called at `0x0064072F` with the global `parameters` object `[0x06CF1538] +
  0x180`; shipped value in `libraries/parameters.xml` `<weapon ...>`
- Live test: no
- Finding: the MD `maxfirerange` getter and the gate make the same virtual call
  with the same `false` argument, so they return the same `R`.
  - Conventional turret `R` is the current bullet's range (ammo defaults
    `+0x78`, from weapon `+0x2E0`) times three equipment-modification
    multipliers (`0x0081CF20`, `0x0081D130`, `0x0081CFA0`). Each multiplier
    applies only when its bullet field is non-zero.
  - Missile turret `R` is the **loaded** missile's ammo-defaults `+0x78`, with
    no multipliers. Changing the loaded missile changes `R`. With an empty
    `+0x2E0`, `R` is 0 and the gate skips the range test.
  - Ammo defaults `+0x50` is `isbeam`: the MD `isbeam` handler `0x00D01A97`
    reads it through `0x000F15F0`. Beam weapons never get the extension.
  - `parameters + 0x1A0` is `maxshotrangefactor` and `+0x1A4` is
    `maxextrashotrange`. The loader stores the attributes at sub-struct `+0x20`
    and `+0x24`. Shipped 9.00 values are `1.1` and `500.0`, so a non-beam
    extension is `Re = R + min(1.1·R, 500 m)`; for any `R` above about 455 m,
    `Re = R + 500 m`. No other reader of `+0x1A4` exists in the image. A later
    post-load transform of `+0x1A0` was not ruled out.
  - Target-side condition: `vslot_15D0` is `0x0034FCE0` =
    `|vslot_1A88()| < 1e-4`. Slot `+0x1A88` is constant 0 for `U::Module`,
    `U::Turret` and `U::Destructible` (`0x00099FF0`), so **surface elements
    and modules never get the extension**. Ship, Station and Object read
    `this + 0x3AC` (`0x00352C00`). What that float means is unresolved, so
    whether a given ship or station gets the extension is unresolved.

### MD `bboxdistanceto` is a different geometry from the engine gate

- X4: 9.00 build 611726
- Status: inference
- Source: native trace; shared `distanceto`/`bboxdistanceto` handler
  `0x00CF2409` (keywords `0x131` and `0x53` share the jump-table entry);
  `bbox = (keyword == 0x53)` at `0x00CF244A`; `0x004B6FF0` → `GetDistanceTo`
  `0x003E1160` (mode = `bbox + 1`); radius read `0x000B3520` = box `+0x20`;
  object test `0x0012F7A0` (class id `0x49`)
- Live test: no
- Finding:
  `A.bboxdistanceto.{B} = max(0, dist(A's own oriented box, B's origin) −
  (B is class object ? B.box.radius : 0))`. The square root is approximate.
  The box radius is the half-extent vector length, which is half the box
  diagonal. The measurement is not box-to-box. The subtracted sphere is why
  Egosoft's script comment says accuracy depends on which object is bigger.
  - `$turret.bboxdistanceto.{$ship_or_station}` measures from the turret's box
    to the target's **origin**, then subtracts the target's half-diagonal. It
    is optimistic compared with the engine gate. The error grows with how far
    the target's box departs from a sphere: up to half-diagonal minus the
    smallest half-extent on the facing side, which is kilometres for long
    stations.
  - `$turret.bboxdistanceto.{$surface_element}` subtracts nothing, because a
    surface element is not class object. It measures from the turret's box to
    the element's origin, while the engine measures from the turret's origin to
    the element's box. The two differ by at most the turret and element box
    sizes.
  - `$target.bboxdistanceto.{$turret}` uses the same function, the same mode 2,
    the same flag bytes and the same `+0x14B0` box as the engine fallback, and a
    turret is never class object. It therefore reproduces the gate's fallback
    distance, turret origin to target box, for ship, station, module and
    surface-element targets, apart from sqrt approximation. The engine
    compares squared distances.

### Shipped AI range checks are positioning heuristics, not the fire gate

- X4: 9.00
- Status: shipped-source
- Source: census of `maxfirerange`, `bboxdistanceto`, `maxcombatrange` and
  weapon-range tokens over base plus all seven official DLC `md/`,
  `aiscripts/`, `ui/` Lua and `libraries/` XSD/XML extracted 2026-09-24
- Live test: no
- Finding: `maxfirerange` appears only in
  `aiscripts/move.attack.object.capital.xml:647,656,679,680` and
  `aiscripts/mining.collect.ship.capital.xml:230`. The capital-combat
  `bboxdistanceto le maxfirerange` loop sits inside the "STATE 2: in range, stay
  here" movement branch and decides whether the ship holds position or
  repositions or retargets a module. No shipped script fires a turret through
  it. The remaining weapon-range uses are ship-level
  `this.ship/station.bboxdistanceto.{target}` against `maxcombatrange` in
  approach, station-defence and laser-tower scripts. The UI exposes only
  player-weapon HUD predicates (`IsTargetInPlayerWeaponRange`,
  `GetDefensibleWeaponFireRange` = max of slot `+0x1EF0` across weapons at
  `0x0021C699`/`0x0021C788`).

### Related native range gates that are not the fire gate

- X4: 9.00 build 611726
- Status: inference
- Source: native trace; firing update `0x008132D0` at `0x00813F5C`–`0x008140DD`;
  `U::MultipleShootController` aim `0x007E9CD0` and candidate check `0x007EAC60`
- Live test: no
- Finding:
  - Aim range: the firing update skips aiming when the origin-to-origin
    squared distance (`GetDistanceSqTo`, mode 1) is at least
    `(vslot_1EE8 · maxaimrangefactor)²`. The shipped factor is `2.0`. Slot
    `+0x1EE8` is a sibling range getter that uses bullet `+0x344` instead of
    ammo `+0x78`. This gate decides whether the turret tracks at all, not
    whether it fires.
  - Multi-target selection: `U::MultipleShootController`, the controller for a
    list of targets, accepts a candidate only when the distance from the weapon
    to that candidate's computed aim point is below `R × 1.1` for non-beam
    weapons or `R` for beams. It first prefilters at 1.5 times that value. This
    affects which listed target it switches to, not the per-shot gate.

### Practical IN RANGE predicate

- X4: 9.00 build 611726
- Status: inference
- Source: the records above
- Live test: no — see the discriminating test below
- Finding: for a stationary target, the engine fallback already decides the
  result: an aim point inside the target box is never nearer than the box
  itself, apart from the muzzle-to-origin offset. The aim point can only
  *extend* range for a lead point, or an authored point outside the box, that
  is nearer than the box. So a cheap predicate without aim-point discovery is
  `$target.bboxdistanceto.{$turret} lt Re` with `R = $turret.maxfirerange` and
  `Re` from the extension rule. For surface elements, modules and beam turrets,
  `Re = R` exactly. For non-beam turrets against a ship or station, `Re` is `R`
  or `R + min(1.1R, 500 m)` depending on the unresolved `+0x3AC` field. The
  current `$weapon.bboxdistanceto.{$target} le maxfirerange` form is close for
  surface elements, but it is not the engine rule for whole ships or stations.

Smallest discriminating live test: one beam turret, so there is no extension
and `Re = R`, on a stationary player ship. Use a long station or large ship
target seen broadside. Choose a range where `$turret.bboxdistanceto.{$target}`
is at most `R` but `$target.bboxdistanceto.{$turret}` is more than `R`, with a
matched control a few hundred metres closer where both are within range. Log
both distances, `maxfirerange` and actual fire. Then repeat with one non-beam
turret against the same ship target and against one of its surface elements,
at `R < d < R + 500 m`. That settles whether ships get the extension, while
the surface element must stay out of range.
