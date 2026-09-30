# Official missile-turret firing-endpoint geometry

Build pin: X4 9.00 build 611726, `X4.exe` SHA-256
`19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`.

Scope: the 32 official `missileturret` macros (16 guided, 16 dumbfire) in the
X4 9.00 base plus seven official extension source sets. Compare against
[barrelposition-offline-transform-semantics.md](barrelposition-offline-transform-semantics.md),
which covers the 92 conventional combat candidates only.

### Missile firing endpoints are `rocket`-tagged leaf connections

- X4: 9.00 build 611726
- Status: shipped-source
- Source: official `missileturret` component XML under the extracted source sets
- Live test: no
- Finding: every one of the 32 components exposes its firing endpoints as
  connections whose only tag token is `rocket`. Each such connection owns no
  part and carries an authored `<offset>` (position, usually with a
  quaternion). Per component there are 4 endpoints (24 macros), 2 (6 macros),
  or 1 (2 macros), and within a component all endpoints declare the same
  `parent` part. Endpoint structure therefore differs from the conventional
  `laser` corpus in the tag token and in endpoint count only; the whole joint
  path above the leaf is shared by a component's endpoints, so they differ
  only in the authored leaf offset.

### Missile joint layout is a subset of the conventional layout

- X4: 9.00 build 611726
- Status: shipped-source
- Source: same corpus, resolved with this repository's accepted endpoint-path
  and ANI census modules
- Live test: no
- Finding: all 32 selected endpoint paths reduce to two structural classes,
  counting connections from the root to the endpoint inclusive:
  - class M4 — 4 connections (24 macros: 12 guided, 12 dumbfire);
  - class M3 — 3 connections (8 macros: 4 guided, 4 dumbfire — the Split and
    Terran medium pairs).

  Both classes use exactly one root-side unbounded `rotation_y` and one
  leaf-side bounded `rotation_x`, in that order, and no translation or
  `rotation_z` restriction. Authored `rotation_x` limits observed are
  −10/+90, −5/+90, −5/+80 and −2/+89 degrees. Conventional selected paths in
  the same build run to 5 or 6 connections, so the missile paths are strictly
  shorter and use a strict subset of the structure the conventional model
  already expresses. Guided and dumbfire members are split evenly across both
  classes, so the guided/dumbfire distinction is not geometric.

### ANI data does reach the missile endpoint path

- X4: 9.00 build 611726
- Status: shipped-source
- Source: official geometry `*.ANI` resources for the same 32 components
- Live test: no
- Finding: each component has a geometry ANI whose descriptors cover the parts
  on the selected path, including `turret_active`. Only the root path
  connection declares an `<animations>` selector list; the intermediate rotator
  and gun connections carry no `animation` tag, and they inherit the root's
  effective selector list under the accepted inheritance rule, so their
  `turret_active` descriptors bind. Settled `turret_active` key counts on the
  path are non-zero for most components (commonly one or two position keys on
  the rotator or gun part, with two rotation keys in three components), so ANI
  locals are a required input, not an optional one. No component on this
  corpus uses `turretloop_active`; the accepted `turret`-family state and
  descriptor-duration rule applies to all 32.

### The final endpoint transform is the same native function

- X4: 9.00 build 611726
- Status: inference
- Source: pinned executable; RTTI-named vtables
- Live test: no
- Finding: the accepted selected-connection transform at `0x14081c960` is a
  virtual method that appears at the same vtable slot (offset `0x1EC8` from
  the vtable start) of exactly five RTTI-named classes: `U::Weapon`,
  `U::Turret`, `U::MissileTurret`, `U::MissileLauncher` and `U::BombLauncher`.
  The stored pointer is identical in all five, so `MissileTurret` does not
  override it. The function receives the connection to resolve as its third
  argument, contains no class or tag test, and reaches the accepted scene
  composition at `0x140e22b70` and the owner translation scale through the
  owner vtable slot `+0x1448` exactly as the conventional record describes.
  Diffing the `U::Turret` and `U::MissileTurret` vtables shows 19 differing
  slots out of 1048; the transform slot and its immediate composition
  neighbours are not among them. The interned `rocket` connection-tag id is
  read in only one place in the image, inside `Controllable::CreateDynamicInterior`,
  so no missile-specific tag branch exists on the transform path.

### Endpoint selection uses the same role-parameterised collection builder

- X4: 9.00 build 611726
- Status: inference
- Source: pinned executable; RTTI-named `Defaults` constructors and the shared
  endpoint-collection builder
- Live test: no
- Finding: every weapon class builds its firing-endpoint collection through one
  shared, non-virtual function at `0x14081f7f0(defaults, macro, roleTagId)`. It
  stores the role tag id at `Defaults+0x798`, then enumerates the macro's
  connection store through the macro vtable slot `+0xa8`
  (`0x140973ba0` → `0x14088cc80`) with a tag predicate built by `0x140884010`
  and the clear flag set, so the destination vector at
  `Defaults+0x7a0..+0x7a8` is reset to empty and refilled. The enumerator walks
  the contiguous connection array `[store+0x170]..[store+0x178]` in native
  storage order and appends each passing connection without reordering, which
  is the accepted unsigned connection-name-hash order.

  That function has exactly four callers, one per weapon role:
  `U::Weapon::Defaults` (`0x14081e2d0`, at `0x14081f0a4`) passes the interned
  `laser` tag id from `0x14395ccd8`; `U::MissileTurret::Defaults`
  (`0x14060b400`, at `0x14060b44c`) and `U::MissileLauncher::Defaults`
  (`0x14060a570`, at `0x14060a5a2`) pass the interned `rocket` tag id from
  `0x14395ce00`; a fourth caller at `0x140849fa2` serves the remaining
  launcher class. `U::MissileTurret::Defaults` chains
  `U::Turret::Defaults` (`0x14080cf60`) → `U::Weapon::Defaults`, so the
  `laser`-filtered vector is built first and then cleared and rebuilt with the
  `rocket` role. The selection rule for missile turrets is therefore the
  accepted conventional rule with `rocket` substituted for `laser`, evaluated
  by the same code.

### `barrelposition` always takes element zero; firing cycles separately

- X4: 9.00 build 611726
- Status: inference
- Source: pinned executable; call-site census of the two endpoint accessors
- Live test: no
- Finding: the script property reaches `0x1407c6e80`, which clears `edx` and
  calls `0x1405bebc0(weapon, 0)` — element zero of the same
  `Defaults+0x7a0` vector — then invokes vtable slot `+0x1EC8`
  (`0x14081c960`, the identical pointer in `U::Turret` and `U::MissileTurret`)
  on that connection. `0x1407c6e80` has exactly one caller, the property
  evaluator case at `0x140d045cf`, so nothing else consumes the index-zero
  endpoint.

  A separate accessor `0x1405bec50` indexes the same vector with the per-shot
  counter at `weapon+0x2f0`, which `0x1407c6ed0` advances modulo the endpoint
  count. The firing function that consumes it (`0x1408132d0`) is vtable slot
  674 and is the same pointer in `U::Turret` and `U::MissileTurret`. Per-shot
  barrel cycling therefore exists identically for conventional and missile
  turrets and never changes what `barrelposition` reports.

### Missile components declare no `laser` connections

- X4: 9.00 build 611726
- Status: shipped-source
- Source: the 32 official `missileturret` component XML files
- Live test: no
- Finding: no missile-turret component declares any `laser`-tagged connection,
  so the rebuild described above yields a `rocket`-only collection on this
  corpus whether or not the builder clears first. Sibling `rocket` endpoints
  are not interchangeable for geometry: on the Argon M guided component the
  two outermost endpoints are about 6.2 m apart and carry opposite-sign
  quaternions, so endpoint identity materially changes the muzzle pose even
  though every sibling shares one parent part and therefore one bearing/arc
  chain.

### Coverage

- X4: 9.00 build 611726
- Status: inference
- Source: the records above plus the accepted 32-macro corpus audit
- Live test: no
- Finding: all 32 official missile turrets are deterministic offline. Guided
  and dumbfire macros are both class `missileturret`, construct the same
  `U::MissileTurret::Defaults`, and therefore share one selection path; no
  class-specific branch alters the result. The representative firing endpoint
  is the `rocket`-tagged connection with the smallest unsigned native
  connection-name hash, and the accepted evaluator resolves it for all 32 with
  no hash collision.
