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

### Unresolved: which `rocket` endpoint the engine selects

- X4: 9.00 build 611726
- Status: inference
- Source: pinned executable; this repository's accepted endpoint-selection rule
- Live test: no
- Finding: the accepted "element zero of the role-tagged connection vector,
  ordered by the native connection-name hash" selection rule was recovered
  against the `laser` role. Nothing found here proves the same rule applies to
  the `rocket` role, and the native code that supplies the connection argument
  was not traced to a shared, role-parameterised selector. For the 2
  single-endpoint components (`turret_bor_m_dumbfire_01_mk1`,
  `turret_bor_m_guided_01_mk1`) the selection is unambiguous regardless. For
  the other 30 the selected leaf offset is one of 2 or 4 authored candidates,
  all of which are derivable offline; only the choice among them is open.
