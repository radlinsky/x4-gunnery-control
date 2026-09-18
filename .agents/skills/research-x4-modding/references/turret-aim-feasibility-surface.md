# Runtime turret aim-feasibility surface

What X4 exposes, and what it keeps internal, for the question "can this
turret mechanically aim at this point?". Build pin for every native record:
X4 9.00 build 611726, `X4.exe` SHA-256
`19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`, rechecked
2026-09-18. See [native-analysis.md](native-analysis.md) for the method. All
addresses are RVAs. Labels such as "aim entry" are analyst labels; the only
native names used are export names, RTTI type names and shipped strings.

## No per-turret feasibility query exists in the script-visible surface

- X4: 9.00 build 611726
- Status: inference
- Source: `libraries/scriptproperties.xml` (`weapon` datatype, lines
  1441-1459; `componentslot` 1471-1491); `libraries/common.xsd`
  (`aim_turret`, `fire_turret`, `reset_turret`, `create_orientation`,
  `check_line_of_sight`); every `ffi.cdef` in `ui-9.00`; PE export directory of
  `X4.exe` (2378 named exports read with `pefile`; the older 2493 figure in
  [ui-lua-menu-camera.md](ui-lua-menu-camera.md) was not reproduced)
- Live test: no — static search, 2026-09-18
- Finding: no MD property, MD action, event, declared FFI function or
  undeclared export returns an arbitrary turret's joint limits, current or
  requested joint angles, or an in-limits result for a supplied point.
  - The `weapon` datatype has no aim, angle, limit or joint property.
    `isreadytofire` means "weapon active, turret deployed" only.
  - `useaimtarget` appears only on `check_line_of_sight` and
    `create_orientation`, and both return a boolean or an orientation, never
    the selected aim point or its distance.
  - The only script sources of `componentslot` values are NPC, chair, room
    and dock slots. None reaches a turret's internal joint connection, so the
    animated `componentslot.rotation` form cannot be applied to turret joints.
  - Keyword sweep of undeclared exports (turret, weapon, aim, point, target,
    rotation, angle, range, and similar): `GetWeaponDetails`,
    `GetWeaponDetails2`, `GetWeaponLaunchedMacro`, `SetWeaponLaunchedMacro`,
    `IsPointingWithinAimingRange`, `GetSofttarget`, `GetTurretGroupMode`,
    `SetTurretGroupMode`, plus VR/Tobii/radar/transporter/sync-point names.
    None is a per-turret aim query. The two aim-related ones are recorded
    below.

## `IsPointingWithinAimingRange` is a no-argument player HUD gimbal check

- X4: 9.00 build 611726
- Status: inference
- Source: export `0x00AFFCB0` → `0x009FC180` (split `.pdata` ranges to
  `0x009FC391`)
- Live test: no — static trace only; not declared or called
- Finding: signature `bool IsPointingWithinAimingRange(void)`. The incoming
  `rcx` is only spilled to home space, then overwritten.
  - The subject is the player's controlled object: `0x009F7950`, from the
    player global. `0x004DFFD0` takes its active weapon group (index
    `+0x668` into the 24-byte group vector at `+0x638`) and returns the first
    member of class `weapon`.
  - `0x00719750` produces a direction from player input state. It is not
    decoded further. Yaw is `atan2(x, z)`, pitch is `atan2(y, hypot(x, z))`,
    with a fixed return for the degenerate `x = z = 0` case.
  - Returns true iff yaw lies in `[Defaults+0x9F0, Defaults+0x9F4]` and
    pitch in `[Defaults+0x9F8, Defaults+0x9FC]` of that weapon's
    `Weapon::Defaults` (next record).
  - It takes no turret or target argument and tests the player's pointing
    direction. It cannot answer a per-turret, per-target question.

## `GetWeaponDetails2` is the player-slot HUD weapon query

- X4: 9.00 build 611726
- Status: inference
- Source: export `0x00B08290`; shipped strings "GetWeaponDetails2",
  "%s(): invalid call. Specified weaponnum must be > 0", "primary",
  "secondary"; vanilla declares the successor
  `WeaponDetails4 GetWeaponDetails3(size_t weaponnum, bool issecondary)`
  (`ui/core/lua/crosshair handling.lua`)
- Live test: no — static trace only
- Finding: signature form `Struct GetWeaponDetails2(size_t weaponnum, bool
  issecondary)`, returned through a hidden result pointer. It indexes the
  player ship's primary or secondary weapon slots for HUD state. It carries
  no aim or limit data.

## The engine keeps one yaw and one pitch limit pair per weapon macro

- X4: 9.00 build 611726
- Status: inference
- Source: `Weapon::Defaults` constructor `0x0081E2D0` (RTTI
  `.?AVDefaults@Weapon@U@@`, vtable `0x02B680A8`); limit loop
  `0x0081F0E0–0x0081F17D`; defaults accessor `0x0085D890`; full-image scan
  of every `.pdata` range for loads, stores and `lea` of `+0x9F0..+0x9FC`
- Live test: no — static trace only
- Finding: at macro load the constructor zeroes four floats, then walks the
  component's connections and each connection's 12-byte restriction records
  `{type, min, max}`.
  - Type 5 (`rotation_y`, yaw) is copied to `+0x9F0/+0x9F4`.
  - Type 4 (`rotation_x`, pitch) is copied to `+0x9F8/+0x9FC`.
  - These are the same type numbers the joint solver dispatches on.
  - The last record of each type wins. Z restrictions and pivot geometry are
    not kept, so this pair is a lossy per-macro summary, not an IK model.
  - It exists for any loaded weapon macro, including DLC and mod macros.
  - The only float reader in the image is `IsPointingWithinAimingRange`.
  - `GetMacroData` (`0x00283680`) calls the accessor twice, but reads
    bullet data at `+0x790`. `GetComponentData` (`0x00278AC0`) never calls
    it.
- Consequence: the engine has generic per-macro limits but gives scripts no
  way to read them. A wrapper would have to be native code.

## Lua data-getter keys are hashed, not stored as strings

- X4: 9.00 build 611726
- Status: inference
- Source: `GetMacroData` `0x00283680` hash loop `0x0028385A–0x00283885` and
  binary-search dispatch; registration at `0x002716A2` (`GetMacroData`) and
  `0x0027159B` (`GetComponentData` → `0x00278AC0`)
- Live test: no — hash reproduced offline against known vanilla keys
- Finding: the key is hashed with a 64-bit FNV-1 variant: start value
  `0x811C9DC5`, and for each sign-extended byte `h = h·0x1000193 mod 2^64`,
  then `h ^= byte`. The dispatcher then binary-searches 64-bit constants.
  Vanilla keys such as `name`, `ware`, `isminingweapon`, `makerrace`, `mk`,
  `size` and `icon` reproduce. Hidden keys therefore cannot be found by
  string search. Candidate names must be hashed and matched against the
  dispatcher constants (64 in `GetMacroData`, 240 in `GetComponentData`).

## The joint solver clamps silently and reports no reachability

- X4: 9.00 build 611726
- Status: inference
- Source: solver `0x00E2132D` limit block `0x00E21D49–0x00E21E0B`; settled
  test `0x00E22029–0x00E22054`; notification `0x00E22105`; callers
  `0x00E22497` (turret aim path) and `0x007485AC` (other IK user); aim entry
  `0x0081C580`
- Live test: no — static trace only
- Finding:
  - A request outside the authored `[min, max]` is replaced by the nearer
    limit, measured by wrapped angular distance.
  - No out-of-limit flag is stored.
  - After the mover call the solver ANDs a per-joint settled test,
    `|target - angle| < eps` and `|velocity| < eps`. When every joint has
    settled it sends a virtual notification.
  - A joint parked on a clamp also counts as settled, so "settled" does not
    mean "on target".
  - Both solver callers discard its return value. The aim entry
    `0x0081C580` returns nothing.
  - There is no dry-run mode: every call path steps the mover.
- Boundary: the start-shooting controller (`0x00817D20` → `0x008198E0`) was
  not decoded far enough to name its aim-error gate. That gate is internal
  either way.

## Aim and shoot state events are internal only

- X4: 9.00 build 611726
- Status: inference
- Source: aim entry `0x0081C580` builds `U::StartedAimingEvent` (vtable
  `0x02BA61E0`) for the turret and `U::WeaponStartedAimingEvent` (vtable
  `0x02BA60C8`) for the nearest defensible ancestor; the stop path builds
  `WeaponStoppedAimingEvent` (`0x02BA6090`); the engine event-name table also
  lists `weaponshoottargetset`, `weaponstartedshooting` and their pairs.
  Negative search: `md.xsd`, `common.xsd`, all shipped MD/AI XML and UI Lua.
- Live test: no
- Finding: the events fire once, on the first aim after not aiming. They
  carry the target position, velocity and a flag, not a feasibility result.
  No MD event, AI event or Lua event name exposes them. Only native code
  could subscribe.

## `aim_turret`, `fire_turret` and `reset_turret` return nothing

- X4: 9.00
- Status: shipped-source
- Source: `libraries/common.xsd` (`aim_turret`: `turret`, `target`;
  `fire_turret`: `turret`; `reset_turret`: `turret`); native `AimTurretAction`
  `0x00BD0B20` → aim entry `0x0081C580` (inference)
- Live test: no
- Finding: none of the three has a result attribute or child. `aim_turret`
  reaches the same aim entry as normal turret control, so it moves the
  joints. These actions command a turret. They are not queries.

## `GetDistanceBetween` is origin-to-origin with an approximate square root

- X4: 9.00 build 611726
- Status: inference
- Source: export `0x0018CE20` → `0x003E1160` → `0x003E0750` → `0x003E0240`,
  mode argument 1
- Live test: no — static trace only
- Finding: the export resolves both ids to components. It transforms the
  second component's origin into the common context at the current time and
  returns the Euclidean distance to the first component's origin.
  - It does not use bounding boxes or aim targets.
  - The square root is `rsqrtss` followed by `rcpss`, so results carry a
    relative error on the order of `1e-3` at worst.
  - Modes above 1 take a different virtual position path, which the export
    never uses.

## `create_orientation` accepts an arbitrary origin position

- X4: 9.00
- Status: shipped-source
- Source: `libraries/common.xsd` `create_orientation` (`position` child:
  "Position the orientation originates at"); vanilla offset origins at
  `md/factionlogic_staticdefense.xml:1131`, `md/cinematiccamera.xml:1340`
  and `:1723`
- Live test: no — not yet run with `useaimtarget="true"` and an offset origin
- Finding: the origin may be any position given by `value` or `x/y/z` with
  `object`/`space`. The native `useaimtarget` route selects the aim point
  nearest the query origin ([macro-box-aimtargets.md](macro-box-aimtargets.md)).
  So a query from a chosen probe origin should return the direction from that
  origin to the aim point nearest it. That combination is inference until one
  live check confirms it.
