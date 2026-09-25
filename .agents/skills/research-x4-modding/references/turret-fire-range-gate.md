# Turret fire-range gate

Scope: X4 9.00 build 611726, the pinned `X4.exe` (SHA-256
`19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`, image base
`0x140000000`); see [native-analysis.md](native-analysis.md). RVAs are real
code addresses. Behavioral labels such as "fallback", "shot-range allowance",
"lead" and "aim gate" are analyst labels, not recovered native names. RTTI class
names (`U::Turret`, `U::Station`, the shoot controllers) are real.

Use this before designing or changing any IN RANGE predicate. It separates
X4's native turret range decision from the shipped AI's `bboxdistanceto`
movement heuristics. Issue #54 mistook those heuristics for the firing rule.

## Plain-English conclusion

X4 lets an AI turret fire when **either** of two distances is inside the range
limit `Re`:

1. the distance from the firing muzzle to the point the turret is aiming at
   (lead included); or
2. the distance from the turret's own origin to the target's own oriented
   bounding box.

`Re` is `$turret.maxfirerange`, plus an AI shot-range allowance of
`min(1.1·R, 500 m)` for non-beam ammunition against a target that can move
(a ship with engines, or that ship's engines).

For Gunnery Control:

- `$target.bboxdistanceto.{$turret}` **is** distance 2, apart from an
  approximate square root.
- `$turret.bboxdistanceto.{$target}`, the issue #54 form, is **not** X4's
  measure for whole ships or stations. It subtracts the target's half-diagonal
  from the distance to the target's centre, which is optimistic, by kilometres
  on long stations.
- A cheap aim-point-free predicate built on distance 2 is a **conservative
  approximation**:
  - It never calls a shot IN RANGE that X4 would refuse, apart from
    square-root rounding.
  - It can call a shot OUT OF RANGE that X4 would still fire, because X4 also
    accepts distance 1.
  - That band is a few metres to tens of metres for stationary geometry.
  - It grows with closing speed times projectile flight time for non-beam and
    unguided-missile turrets.

The recommended #197 formula is at the end of this file.

## Records

### The engine range test lives in the common pre-fire gate

- X4: 9.00 build 611726
- Status: inference
- Source: native trace; pre-fire gate `0x00816D20` (the function recorded in
  [weapon-path-obstruction-groups.md](weapon-path-obstruction-groups.md)),
  range section `0x00817808`–`0x00817981`
- Live test: no — static trace only
- Finding: every non-player shoot controller runs this range test after its
  aim-alignment stage and before the obstruction section. The range section
  precedes the guided-ammunition obstruction bypass at `0x008179A1`, so guided
  missiles are range-gated too. `U::PlayerShootController` skips it: its slot
  `+0x80` is true and `0x0081782A` jumps to the permit path.

```text
tgt = controller.slot_90()            # 0x00817614: Basic/LargeTarget → ctrl+0x10;
                                      # Multiple (0x007E5C10) → its chosen ctrl+0xC0
R   = weapon.slot_1EF0(false)         # identical call to MD $turret.maxfirerange
Re  = R
if |R| >= 1e-4 and not ammo(weapon+0x2E0).isbeam and tgt and |tgt.slot_1A88()| >= 1e-4:
    Re = R + min(R * params.maxshotrangefactor, params.maxextrashotrange)
if R > 0:
    if approx_len(aimPoint - muzzle) >= Re:                   # distance 1
        if GetDistanceSqTo(tgt, weapon, mode=2) >= Re*Re:      # distance 2
            controller.slot_C0(...); return NO FIRE
# continue to obstruction section
```

`R == 0`, meaning no loaded ammunition, skips the whole test. An
out-of-range result does not set the LINE OF FIRE BLOCKED flag.

### Shipped AI shot-range parameters

- X4: 9.00
- Status: shipped-source
- Source: `libraries/parameters.xml` in base; the `parameters.xml` diffs in
  `ego_dlc_boron`, `ego_dlc_split`, `ego_dlc_terran` and `ego_dlc_timelines`
- Live test: no
- Finding: base ships `<aicombat><weapon maxaimrangefactor="2.0"
  fastcharge="1.0" maxshotrangefactor="1.1" maxextrashotrange="500.0"/>`.
  None of the official DLC diffs touches this node. A third-party mod could
  patch it.

### The shot-range allowance: exact runtime rule and constants

- X4: 9.00 build 611726
- Status: inference
- Source: native trace, as listed below
  - arithmetic at `0x0081787B`–`0x008178B8`, with `xmm8 = 1.0` from
    `0x0081767D` and callee-saved across the aim stage;
  - the `parameters` global `[0x06CF1538]`, allocated and assigned at
    `0x009E8B62`–`0x009E8B93` and freed at `0x009EB45C`; its constructor is
    `0x00A8B680`;
  - the weapon sub-struct at `parameters + 0x180`: constructor `0x00635C20`,
    loader `0x0060D940` called at `0x0064072F` (the loader's callers load the
    `"parameters"` library);
  - the shipped values in the previous record.
- Live test: no
- Finding: the effective limit is
  **`Re = R + min(1.1·R, 500 m)`**. It is not `1.1·R`:
  - The gate computes `f = 1 + min(R·1.1, 500)/R` and compares against `f·R`.
    For any `R` above about 454.5 m, `Re = R + 500 m`.
  - The constructor defaults are the same values as the shipped XML:
    sub-struct `+0x20` is `0x3F8CCCCD` (1.1), `+0x24` is `0x43FA0000` (500.0)
    and `+0x10` is 2.0 (`maxaimrangefactor`).
  - The loader stores `maxshotrangefactor` at `+0x20` and `maxextrashotrange`
    at `+0x24` directly, using the current value as the default. Those are
    `parameters + 0x1A0` and `+0x1A4`, the fields the gate reads.
  - Nothing rewrites the values after load. A full-image scan of stores at
    `+0x1A0`/`+0x1A4` inside every function that references the global found
    none through a register holding the global. `0x00D95180` loads the global
    into `rbx` but stores through `r15`. The only `minss` reader of `+0x1A4` in
    the image is the gate.
  - Conditions, all required:
    - `R` is non-zero;
    - the loaded ammunition is not a beam: ammo-defaults `+0x50` is `isbeam`,
      the same byte the MD `isbeam` handler `0x00D01A97` reads through
      `0x000F15F0`;
    - a target exists;
    - the target's slot `+0x1A88` value is at least 1e-4 in magnitude (next
      record).

### Target speed decides the allowance: object `+0x3AC` is cached max speed

- X4: 9.00 build 611726
- Status: inference
- Source: `0x0034FCE0` (`vslot_15D0` = `|vslot_1A88()| < 1e-4`); slot
  `+0x1A88` implementations `0x00352C00` (Object/Ship/Station/Defensible/
  Container/Asteroid: `movss xmm0,[this+0x3AC]`), `0x00099FF0` (constant 0:
  Module, Turret, MissileTurret, Weapon, ShieldGenerator, Radar, Scanner,
  Destructible and every station module subclass), `0x0054E970` (Engine:
  forwards to its nearest class-`object` ancestor); `U::Object` constructor
  `0x006CA770` → `0x006CA950` (zeroes `+0x3AC`/`+0x3B0`/`+0x3B4`/`+0x3B8` at
  `0x006CAAD9`–`0x006CAAE0`); movement-capability recompute `0x006DC610`
  (writes `+0x3AC` at `0x006DCB38`, `+0x3B0` at `0x006DCAF1`); MD `maxspeed`
  handler `0x00CF38AC` (keyword `0x37C`) → `0x006DD090` → `0x006DC610`, which
  returns struct `+0x24`; property doc `scriptproperties.xml:781`
- Live test: no
- Finding: `this + 0x3AC` holds a cached copy of struct field `+0x24` from the
  engine/thruster aggregation. That is the same field MD `$ship.maxspeed`
  returns ("Maximum speed with present engine set up and conditions").
  - It is **not** current velocity, size, class or controller type. It changes
    only when the aggregation reruns, for example on engine or equipment
    changes. When the routine's operational filter is active (`0x006DC8B1`),
    non-operational engines are ignored. A ship without an engine
    contribution reaches the same write block through the no-engine path
    (`0x006DCBB0` → `0x006DCB2B`).
  - The recompute exits immediately when slot `+0x1C90` is true. That slot is
    constant true for `U::Station` (`0x0009C980`), so a station's `+0x3AC`
    stays at the constructor's 0.
  - The other `+0x3AC` writers in the image are other structs. For example,
    `0x002703B0`/`0x002706C0`/`0x00270DC0` belong to a type with a string at
    `+0x3B8`; U::Object has a float there.

Which targets get the allowance, for non-beam turrets:

| Target | Slot `+0x1A88` | Allowance |
|---|---|---|
| whole ship | cached `maxspeed` | yes, whenever the cached max speed is non-zero (every ship with working engines) |
| ship turret or shield element | constant 0 | never |
| ship engine element | owning ship's cached `maxspeed` | same as its ship |
| whole station | 0, never recomputed | never |
| station module, or a turret or shield element on a station | constant 0 | never |

### Distance 2: turret origin to the target's own oriented box

- X4: 9.00 build 611726
- Status: inference
- Source: gate call `0x008178FC` → `GetDistanceSqTo` (`0x003E1930`, named by
  its own error strings) with `this=target`, `other=weapon`, mode 2 →
  `0x003E0C40` → `0x003E04C0` → target slot `+0x14E0`. `0x00747100` is the
  implementation for every class Gunnery Control targets; `U::Component`'s
  base `0x003E26F0` is not reached by them.
- Live test: no
- Finding: the fallback is the exact squared distance from the weapon
  component's **origin** to the target's **own** box.
  - The point is transformed into target space. Slot `+0x14E0` then clamps it
    per axis against the half-extents and centre from slot `+0x14B0`, so the
    box is oriented with the target.
  - Target rotation matters. Turret rotation does not, because only the turret
    component's origin is used.
  - Both flag bytes are 1. That selects the slot-`+0x14B0` box and skips the
    child recursion at `0x00747390`.
  - Nothing is cached. Transforms are read at the current game time.

Box source per target class (vtable reads):

| Target | Slot `+0x14B0` | Box |
|---|---|---|
| `U::Ship` | `0x006DF940` | macro box `macro+0x140`. It delegates to a child object's box only when macro-data flag `+0x8F2` is set and a child passes the global class filter. |
| `U::Station` | `0x007EB460` | the live instance box at `this+0xC90` (see below) |
| `U::Turret`, `U::MissileTurret`, `U::ShieldGenerator`, `U::Engine` (Gunnery Control's turret, shield and engine surface elements) | `0x0034EE10` → `+0x14A8` `0x0034EE00` | the element's own macro box, `macro+0x140` |
| station modules (Production, Storage, Habitation, Defence, Connection, Pier, Processing) | `0x0034EE10` | own macro box. `U::BuildModule` uses the instance box `0x00354470`; `U::DockingBay` uses `0x0053C5C0`, which falls back to the parent box when its own radius is about 0. |

Station instance box: the constructor `0x007F7310` zeroes `+0xC90`/`+0xCA0`/
`+0xCB0`. The rebuild `0x00801CE0`, reached from `U::Station` slot `+0x1E90`
(`0x008013F0`, called from 14 sites), seeds from the station's own macro box.
It then unions every filtered child in `this+0xA8`, each child box transformed
into the station frame (`0x014E17D0`/`0x014E1BD0`). The result is an
axis-aligned box in the station frame that follows module construction and
removal whenever slot `+0x1E90` runs. Which events trigger each of the 14 call
sites was not enumerated. It does not matter for equivalence: MD and the gate
read the same field at the same moment.

A whole ship or station is measured against its own root box, not a module or
surface element. A selected surface element or module is measured against its
own box, not its parent's. Gunnery Control's surface elements are the
`turret`, `shield` and `engine` upgrade-slot components that
`ui/gunnery_control.lua` `readSurfaceTargets` enumerates, never modules
themselves.

### MD `bboxdistanceto` geometry, and the exact MD form of distance 2

- X4: 9.00 build 611726
- Status: inference
- Source: native trace, as listed below
  - shared `distanceto`/`bboxdistanceto` handler `0x00CF2409`. Keywords
    `0x131` and `0x53` share the entry in the component-property jump table
    `0x00D0BDF0`, where index = keyword − 3.
  - `bbox = (keyword == 0x53)` at `0x00CF244A`.
  - `0x004B6FF0` → `GetDistanceTo` `0x003E1160` (mode = `bbox + 1`) →
    `0x003E0750` → `0x003E0240` → slot `+0x14E0` with both flag bytes 1.
  - the radius term is `0x000B3520`, box `+0x20`, applied only when
    `0x0012F7A0` finds the other operand is class `object` (`0x49`).
  - class membership uses slot `+0x11E8`, a per-class 2-bit table: Turret
    `0x02B8A380`, ShieldGenerator `0x02B460A8`, Engine `0x02AE7350`, Module
    `0x02B45F10`, Ship `0x02B87B68`, Station `0x02B7CF40`.
- Live test: no
- Finding:
  `A.bboxdistanceto.{B} = max(0, approx_len(A's own oriented box → B's origin)
  − (B is class object ? B.box.radius : 0))`, where radius is half the box
  diagonal. It is not box-to-box.

  | Expression | What it measures |
  |---|---|
  | `$turret.bboxdistanceto.{$ship_or_station}` | turret box to target **centre**, minus the target's half-diagonal. Optimistic by up to half-diagonal minus the facing half-extent (kilometres on long stations). |
  | `$turret.bboxdistanceto.{$surface_element}` | turret box to element origin; no subtraction (element is not class object). |
  | `$target.bboxdistanceto.{$turret}` | target box to turret origin; no subtraction for any of the four target types (Turret, ShieldGenerator and Engine are not class object) |

  The last form matches distance 2 for all four target types:
  - the same slot `+0x14E0` implementation;
  - the same mode 2 and flag bytes, so no child recursion;
  - the same slot-`+0x14B0` box;
  - the same common-space search `0x003D8CD0` with a null space;
  - the same `0x003DB8A0` turret-origin transform at the current game time.

  The only differences:
  - MD takes `rcpss(rsqrtss(d²))`, roughly ±7e-4 relative error (±6 m at
    8.6 km), where the gate compares `d²` with `Re²` exactly;
  - MD evaluates at script time, the gate at firing time.

### Distance 1: how the aim point is produced

- X4: 9.00 build 611726
- Status: inference
- Source: native trace, as listed below
  - controller slot `+0xA8`: Basic `0x007E72B0`, LargeTarget `0x007E7DE0`,
    Multiple `0x007E9CD0`, Player `0x007E8650`;
  - shared solver `0x007E7460`;
  - aim-point selectors `0x00520FC0`/`0x005210E0` (see
    [macro-box-aimtargets.md](macro-box-aimtargets.md));
  - LargeTarget offset setter `0x007E8330`;
  - weapon slots `+0x1F48` (turret: `0x0009C980` true for Turret and
    MissileTurret) and `+0x1F18` (lead enable: `0x007C7450` = not beam,
    `0x0060A8C0` = missile not guided);
  - target prediction `0x003E2120`; flight time `0x014DD920`.
- Live test: no
- Finding:
  - **Basic.** Periodically re-samples the target's motion into `ctrl+0x60`
    (`0x003DEE20`), then calls the shared solver.
  - **LargeTarget with a turret or missile weapon.** Slot `+0x1F48`/`+0x1F50`
    is true, so it runs the Basic path and then adds the target-local offset
    `ctrl+0xA0`. That offset is set only when the target macro has no
    authored aim-target collection (`+0x760` null). It maps the turret's
    normalized position inside its own ship's box onto the target box, scaled
    by `(0.25, 0.25, 0.75)` of the target's half-extents. It is zeroed if the
    point fails `0x0051BEB0`, a point-inside test against the target's own
    body. The result stays inside the target box. Its exact conditions, and
    why a station root never keeps it, are in
    [selected-target-line-of-fire.md](selected-target-line-of-fire.md).
  - **LargeTarget with a non-turret weapon.** Aims along the firing ship's
    forward axis at `0.99·R` and requires that segment to hit the target box.
    It never applies to turrets.
  - **Multiple.** Chooses a target from its list. A candidate passes when the
    distance from the weapon to that candidate's own aim point is below `R`
    for beams or `1.1·R` otherwise; `0x007EAC60` also prefilters at 1.5 times
    that. The chosen target becomes `ctrl+0xC0`, and slot `+0x90` makes the
    gate range-test that same target with both distances.
  - **Shared solver.** Starts from the selected target-local point:
    - the nearest authored aim point relative to the weapon component's
      origin (not its firing endpoint; see
      [macro-box-aimtargets.md](macro-box-aimtargets.md)); or
    - the box centre when there is none (184 of 203 vanilla ship components
      have none), plus the LargeTarget offset.
  - **Lead.** Only when slot `+0x1F18` is true: non-beam conventional turrets
    and unguided missile turrets. It iterates up to 6 times: flight time from
    distance, projectile speed and acceleration; the point predicted at
    now + flight time from the sampled target motion (linear and angular);
    the authored point re-selected in the predicted frame. Finally it
    subtracts shooter velocity × flight time, unless bullet flag `+0x320` is
    set. With no lead (beams, guided missiles) the aim point is the current
    target point.

### Can distance 1 pass while distance 2 fails?

- X4: 9.00 build 611726
- Status: inference
- Source: the two records above; aim-point containment from
  [macro-box-aimtargets.md](macro-box-aimtargets.md)
- Live test: no
- Finding: yes, and only in the direction that makes a box-only predicate
  conservative.
  - Because P is inside or on the box,
    `|aim − muzzle| ≥ box distance − |muzzle − turret origin| − overhang(P) −
    |Δv_P|·t_f`, where:
    - `overhang(P)` is how far the selected point lies outside the box;
    - `Δv_P` is the point's velocity minus the shooter's, applied only when
      lead is enabled;
    - `t_f` is the projectile flight time.
  - So X4 can fire while `$target.bboxdistanceto.{$turret}` ≥ `Re` only inside
    a band of width at most
    `|muzzle − origin| + overhang + (lead ? closing speed · t_f : 0)`.
  - Stationary geometry, or beam and guided-missile turrets: at most the
    turret's muzzle offset from its origin plus any authored-point overhang.
    That is metres to tens of metres. Vanilla ship aim points are all inside
    their boxes. Some turret surface elements author their aim point above
    the collision socket, so overhang is possible there. The box-centre
    fallback and the LargeTarget offset are always inside the box.
  - Closing targets with lead (non-beam or unguided turrets): the band grows
    by about `Re × closing speed / projectile speed`. For example, 300 m/s
    closing against 1,500 m/s projectiles is about 20 % of `Re`. Receding
    targets move the aim point away, and distance 2 decides.
  - Nothing in the gate lets a target pass distance 2 while X4 refuses it.
    The two tests are OR-ed, so a box-only predicate cannot be optimistic
    beyond square-root rounding and evaluation-time skew.

### MD `maxfirerange` is the gate's `R`

- X4: 9.00 build 611726
- Status: inference
- Source: MD handler `0x00D01971` (keyword `0x370`, jump index `0x36D`) calls
  weapon slot `+0x1EF0` with `false`, exactly as the gate does at `0x00817838`;
  slot implementations `0x007C7350` (Weapon, Turret, BombLauncher) and
  `0x00609270` (MissileTurret, MissileLauncher)
- Live test: no
- Finding: `$turret.maxfirerange` is the same `R` for:
  - projectile turrets: loaded bullet's ammo-defaults `+0x78`, times the
    equipment-modification multipliers `0x0081CF20`/`0x0081D130`/
    `0x0081CFA0`;
  - beam turrets: the same function;
  - missile turrets: the currently loaded missile's `+0x78`, no multipliers,
    so it changes with the loaded missile;
  - modded weapons: same code, reading their macro data.

  A mod can use it directly and must not reconstruct ammunition range. With
  nothing loaded, both return 0. The gate then skips the range test, while an
  MD predicate would say OUT OF RANGE for a turret that cannot fire anyway.

### Shipped AI range checks are positioning heuristics, not the fire gate

- X4: 9.00
- Status: shipped-source
- Source: census of `maxfirerange`, `bboxdistanceto`, `maxcombatrange` and
  weapon-range tokens over base plus all seven official DLC `md/`,
  `aiscripts/`, `ui/` Lua and `libraries/` XSD/XML extracted 2026-09-24
- Live test: no
- Finding: see the md-ai.md record "Per-turret line of sight and the shipped AI
  range heuristics". The capital-combat `bboxdistanceto le maxfirerange` loop
  decides ship positioning and module retargeting. The mining form is an
  approach test. No shipped script fires a turret through either. The UI
  exposes only player-weapon predicates: `IsTargetInPlayerWeaponRange`, and
  `GetDefensibleWeaponFireRange`, which is the maximum of slot `+0x1EF0`.

### Related native range gates that are not the fire gate

- X4: 9.00 build 611726
- Status: inference
- Source: firing update `0x008132D0` at `0x00813F5C`–`0x008140DD`
- Live test: no
- Finding: the firing update skips aiming entirely when the origin-to-origin
  squared distance (mode 1) is at least `(slot_1EE8 · maxaimrangefactor)²`,
  with the factor at 2.0. Slot `+0x1EE8` is a sibling range getter that reads
  bullet `+0x344`. This decides whether the turret tracks at all, not whether
  it fires.

### Practical IN RANGE formula for issue #197

- X4: 9.00 build 611726
- Status: inference
- Source: the records above
- Live test: no — not required to choose the formula. See "Remaining live
  question" below.
- Finding: the classification is **conservative approximation**:
  - It is not exact, because distance 1 can accept shots distance 2 rejects.
  - Its error is one-directional: it never reports IN RANGE when X4 would
    refuse, apart from square-root rounding and evaluation timing.
  - The error is bounded by the formula in "Can distance 1 pass while
    distance 2 fails?".

```text
R      = $turret.maxfirerange
extra  = (not $turret.isbeam) and moving_target ? min(1.1 * R, 500m) : 0
IN RANGE  iff  R > 0 and $target.bboxdistanceto.{$turret} lt (R + extra)

moving_target:
  whole ship              → $target.maxspeed gt 0
  engine on a ship        → that ship's maxspeed gt 0
  turret/shield element   → false
  station, anything on it → false
```

`$ship.maxspeed` is the same struct field the gate caches. MD recomputes it,
so it can only differ from the cached copy between recomputes. The gate's
threshold is 1e-4 m/s.

Remaining live question, optional: none of the formula's inputs needs a live
test to choose it. The static trace cannot measure the size of the lead band
for real ships and turret pairs. If #197 wants a measured bound, fire one
non-beam turret at a fighter closing at a known speed and log the first shot
against `$target.bboxdistanceto.{$turret}` and `R + extra`.
