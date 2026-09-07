# Xenon M Laser 02 component one-key barrel resolution (X4 9.00)

**SOURCE-RESOLVED UNDER AN ALREADY ACCEPTED PROOF BOUNDARY — NO NEW RUNTIME
MOVEMENT SEMANTIC REQUIRED**

This reference answers one question about the shipped X4 9.00 component
`turret_xen_m_laser_02_mk1`: does its active muzzle path independently satisfy
the existing `depth4_one_key_barrel_translation` proof boundary?

**It does.** Every active-path transform the component authors is either a
zero, an authored rotation restriction already covered by the accepted case, or
a one-key `turret_active` candidate-channel-0 record that independently matches
the signature in
[turret-rank1-one-key-channel0-settled.md](turret-rank1-one-key-channel0-settled.md).
No new channel, axis, frame, order, timing, or transform meaning is needed.

The concrete files below are proof sources, not an inventory or a membership
list.

## Two macros, one component

Both `turret_xen_m_beam_02_mk1_macro` and `turret_xen_m_laser_02_mk1_macro`
declare `<component ref="turret_xen_m_laser_02_mk1" />`. The macros differ only
in gameplay properties (bullet class, rotation speed/acceleration,
localization); they share one component asset and therefore one muzzle
geometry. This is a `shipped-source` fact read from the two macro files, not
inferred from name spelling.

## Active path

```text
Connection01 (part_socket)
  → Connection03 (part_rotator)
    → Connection04 (part_gun)
      → Connection05 (part_barrel)
        → con_laser_01 / con_laser_02
```

Source-part path depth 4, two firing endpoints. The component's only other
`part` connection, `Connection02` (`anim_lights`), hangs off `part_socket` and
is not on either endpoint's ancestry, so it carries no muzzle transform.

Authored restrictions on the path, and no others:

| connection | restriction | limits |
|---|---|---|
| `Connection03` | `rotation_y` | none authored |
| `Connection04` | `rotation_x` | min `-10`, max `90` |

That is exactly the yaw/pitch layout the accepted case requires.

## `turret_active` selector and stored active records

`Connection01` authors the five-selector idiom, with a **single-frame** active
state:

| selector | frames |
|---|---|
| `turret_inactive` | 1–1 |
| `turret_activating` | 1–45 |
| `turret_active` | 50–50 |
| `turret_deactivating` | 55–100 |
| `gun_firing` | 50–55 |

Muzzle-path `turret_active` key-count families in
`assets/props/WeaponSystems/standard/TURRET_XEN_M_LASER_02_MK1_DATA.ANI`
(SHA-256 `a37f24ccec1166cf2dd716ffa1a18ab7dcc004002a070373234e01c25c98e678`):

| descriptor index | part | key-count family |
|---|---|---|
| 2 | `part_socket` | `[0, 0, 0, 0, 0]` |
| 12 | `part_rotator` | `[2, 0, 0, 0, 0]` |
| 17 | `part_gun` | `[0, 0, 0, 0, 0]` |
| 22 | `part_barrel` | `[1, 0, 0, 0, 0]` |

**No muzzle-path descriptor of this component stores any key in candidate
channels 1–4, in any of the five selectors.** There is therefore no companion
channel whose meaning would have to be discriminated before the settled pose
can be composed — the situation that forced a separate resolution for the
`[1, 2, 2, 0, 0]` beam_02 family in
[turret-rank1-beam-02-settled-transform.md](turret-rank1-beam-02-settled-transform.md)
does not arise here.

`(part_rotator, turret_active)` stores the doubled form, both keys
`(0x00000000, 0x403d92e4, 0x00000000)` = `(0, 2.962090492248535, 0)`.

`(part_barrel, turret_active)` stores exactly one channel-0 key:

| field | stored bits | float32 |
|---|---|---|
| ValueX | `0x00000000` | 0.0 |
| ValueY | `0x00000000` | 0.0 |
| ValueZ | `0x404e3d30` | 3.222484588623047 |
| InterpolationX/Y/Z | `0x00000001` ×3 | STEP form |
| `Time` | `0x34000000` | 1.1920928955078125e-07 |

The descriptor's offset-148 field is `0x3d088889` (1/30), the same authored
idiom as the accepted proof source.

## Adjacent-state boundary agreement

The barrel Z bits `0x404e3d30` are bit-identical at every state boundary that
touches the active frame:

| descriptor | stored channel-0 keys | boundary bits |
|---|---|---|
| `turret_activating` | 3 | last key `0x404e3d30` |
| `turret_active` | 1 | `0x404e3d30` |
| `turret_deactivating` | 3 | first key `0x404e3d30` |
| `gun_firing` | 3 | first and last keys `0x404e3d30` |

The rotator shows the same agreement at `0x403d92e4`. The neighbouring states
therefore enter and leave the active state at exactly the stored active values,
which is the boundary condition the accepted rule requires.

`gun_firing` (frames 50–55) dips the barrel channel-0 Z to `0x3f8cf1f8`
(`1.1011343002319336`) and returns within about 1/6 s, so a runtime
`barrelposition` sample taken at a `FIRED` instant is not automatically the
settled pose here either — the same recoil caveat as the accepted proof source,
with a smaller excursion.

## What would have blocked reuse, and is absent

- no keys in candidate channels 1–4 anywhere on the path, so no additive
  rotation or scale companion to interpret;
- no keyed `part_socket` or `part_gun` active record, so no additional settled
  transform between the yaw and pitch joints;
- no authored quaternion on any path connection offset;
- no second `turret_active` selector occurrence and no multi-frame active span;
- no restriction other than the accepted unbounded `rotation_y` and
  `rotation_x` −10/+90 pair.

## Decision

The `turret_xen_m_laser_02_mk1` active muzzle path is **fully source-resolved
by the existing `depth4_one_key_barrel_translation` case**: the settled pose is
the rotator channel-0 translation `(0, 2.962090492248535, 0)` plus the barrel
one-key channel-0 translation `(0, 0, 3.222484588623047)`, composed under the
authored `rotation_y` / `rotation_x` joints. No new semantic case and no new
evidence-bounded signature variant is required.

## Live-test position

**No live test is required for this component.** Every runtime movement it
exercises falls inside an already accepted proof boundary:

- candidate channel 0 as an additive local translation is `live-tested` for a
  turret muzzle path in
  [paranid-l-beam-channel0-semantics.md](paranid-l-beam-channel0-semantics.md);
- the one-key active record as the constant settled value is the accepted rule
  in [turret-rank1-one-key-channel0-settled.md](turret-rank1-one-key-channel0-settled.md),
  matched here independently from this component's own shipped source;
- the composed depth-4 one-key settled model has live confirmation from the
  beam_02 run in
  [turret-rank1-beam-02-settled-transform.md](turret-rank1-beam-02-settled-transform.md),
  which additionally had to reject a companion-channel reading this component
  does not even store.

A live test would only become necessary if a later change proposed a transform
outside that boundary.

## Proof boundary

- This resolves the settled `turret_active` muzzle geometry of this one
  component. It makes no claim about `turret_activating`,
  `turret_deactivating`, `gun_firing` interpolation, recoil timing, or
  transition poses.
- It assigns no meaning to candidate channels 1–4, which this component's
  muzzle path does not populate.
- It is offline source verification; this component has not itself been
  live-tested.
- Matching the accepted signature resolves geometry only. Whether a supported
  macro record is produced for either macro is a separate
  census/generator question, and one component backing two macros is a known
  distinct concern there.

## Evidence records

### Two macros share one turret component

- X4: 9.00
- Status: shipped-source
- Source: `assets/props/WeaponSystems/standard/macros/turret_xen_m_beam_02_mk1_macro.xml` and `assets/props/WeaponSystems/standard/macros/turret_xen_m_laser_02_mk1_macro.xml`
- Live test: no — offline source verification only, as of 2026-09-06
- Finding: both macros declare `<component ref="turret_xen_m_laser_02_mk1" />`
  and differ only in bullet class, rotation speed/acceleration, hull and
  localization properties. They share one component asset and therefore one
  authored muzzle geometry.

### Active-path structure and authored restrictions

- X4: 9.00
- Status: shipped-source
- Source: `assets/props/WeaponSystems/standard/turret_xen_m_laser_02_mk1.xml`
- Live test: no — offline source verification only, as of 2026-09-06
- Finding: the two firing endpoints `con_laser_01` and `con_laser_02` hang off
  `part_barrel` on the depth-4 path
  `Connection01`/`part_socket` → `Connection03`/`part_rotator` →
  `Connection04`/`part_gun` → `Connection05`/`part_barrel`. `Connection03`
  authors an unlimited `rotation_y`; `Connection04` authors `rotation_x` with
  min `-10` and max `90`; no other path connection authors a restriction or a
  quaternion. `Connection01` authors `turret_active` as the single frame
  50–50 within the five-selector idiom.

### Muzzle-path `turret_active` stored records

- X4: 9.00
- Status: shipped-source
- Source: `assets/props/WeaponSystems/standard/TURRET_XEN_M_LASER_02_MK1_DATA.ANI`, SHA-256 `a37f24ccec1166cf2dd716ffa1a18ab7dcc004002a070373234e01c25c98e678`
- Live test: no — offline source verification only, as of 2026-09-06
- Finding: muzzle-path active key-count families are `part_socket`
  `[0,0,0,0,0]`, `part_rotator` `[2,0,0,0,0]`, `part_gun` `[0,0,0,0,0]`,
  `part_barrel` `[1,0,0,0,0]`; no muzzle-path descriptor stores a key in
  candidate channels 1–4 under any selector. The rotator's doubled active
  channel-0 keys are both `(0x00000000,0x403d92e4,0x00000000)`. The barrel's
  single active channel-0 key is `(0x00000000,0x00000000,0x404e3d30)` with
  per-axis interpolation `0x00000001` and `Time` `0x34000000`, and its Z bits
  are bit-identical to the last `turret_activating` key, the first
  `turret_deactivating` key, and the first and last `gun_firing` keys.
  `gun_firing` moves that Z to `0x3f8cf1f8` and back within the state.

### Independent match to the accepted one-key barrel case

- X4: 9.00
- Status: inference
- Source: the shipped-source facts above compared against the resolved signature in [turret-rank1-one-key-channel0-settled.md](turret-rank1-one-key-channel0-settled.md)
- Live test: no — untested as of 2026-09-06
- Finding: the component independently satisfies every condition of the
  accepted `depth4_one_key_barrel_translation` case — depth-4 two-endpoint
  path, keyed rotator and barrel edges only, doubled rotator channel-0
  `(0, 2.962090492248535, 0)`, one-key STEP barrel channel-0
  `(0, 0, 3.222484588623047)`, one-frame authored `turret_active`, exact
  adjacent-state boundary agreement, and the unbounded `rotation_y` /
  `rotation_x` −10/+90 layout. No new semantic case, signature variant, or live
  discrimination is required.
