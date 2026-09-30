# Offline selected-muzzle transform semantics

Build pin for every record below unless stated otherwise: X4 9.00 build 611726, `X4.exe` SHA-256 `19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`.

This reference preserves the generic offline transform rules needed to reproduce the selected `weapon.barrelposition` connection for mounted, deployed, non-firing conventional combat turrets. Endpoint identity is separate: use the accepted build-pinned endpoint-selection rule. X4Native remains validation equipment, not a production dependency or a source of transform rules.

## Composition convention and mounted-turret rule

- X4: 9.00 build 611726
- Status: shipped-source
- Source: pinned executable transform path; official turret component XML and ANI resources
- Live test: no — derived from executable/data flow; LIVE records are holdouts only
- Finding: transforms are row-vector matrices stored as translation followed by `+X`, `+Y`, `+Z` basis rows. For the selected connection scene path, child-local transforms compose before parent transforms. With the mounted-turret owner scale fixed to unity, the generic segment order is:

```text
partLocal/ANI ∘ J_C ∘ C_authored ∘ parentWorld
```

`C_authored` is the owning connection's authored XML offset. `J_C` is the runtime restriction-state matrix and is identity for an unrestricted connection. The selected `barrelposition` result is the selected connection's composed component-space transform.

Key executable points for this build: selected-connection transform `0x14081c960`; scene connection composition `0x140e22b70`; part-world composition `0x14074c2d0`; animation-local evaluation `0x1411608b0`; restriction matrix builder `0x1404b5f20`.

## Authored and ANI locals

- X4: 9.00 build 611726
- Status: shipped-source
- Source: XML connection/part loaders, ANI loader/binder/evaluator, pinned executable
- Live test: no
- Finding:
  - connection local transform is the direct XML `<connection><offset>` transform;
  - stored part local is the direct XML `<part><offset>` transform, or identity when absent;
  - an animated part's default local has zero translation and the authored part-local rotation;
  - a present ANI position track replaces the animation-default translation;
  - a present ANI rotation track replaces the animation-default rotation;
  - ANI position XYZ flows through unchanged on this path; there is no generic ANI-X negation;
  - groups 2–4 are not read by the local evaluator used on this selected-connection path.

Using right-handed row-vector matrices:

```text
Rx(a) = [[1,0,0],[0,c,s],[0,-s,c]]
Ry(a) = [[c,0,-s],[0,1,0],[s,0,c]]
Rz(a) = [[c,s,0],[-s,c,0],[0,0,1]]

XML rotation(pitch, yaw, roll) = Rz(-roll) · Rx(-pitch) · Ry(yaw)
ANI rotation(x, y, z)          = Rx(-x) · Rz(-z) · Ry(y)
```

XML Euler angles are converted from degrees to radians. ANI rotation values are already consumed as radians. ANI translation/rotation is not generically additive to the stored part local; the animated branch substitutes the animation local and then composes it with the owning connection.

## Runtime restriction matrix

- X4: 9.00 build 611726
- Status: shipped-source
- Source: restriction XML loader, per-instance IK state, `0x140e20370`, `0x1404b5f20`
- Live test: no
- Finding: restriction records map to current per-instance scalar values in XML order. Translation scalars are used directly; rotation scalars are radians. XML rotation limits are converted to radians upstream. For restriction values `(v_tx,v_ty,v_tz,v_rx,v_ry,v_rz)`:

```text
J_C.t = (v_tx, v_ty, v_tz)
J_C.R = Rz(-v_rz) · Rx(-v_rx) · Ry(+v_ry)
```

The joint rotates about the owning connection origin, in the connection-local frame, before the authored connection rotation. For the 92-candidate conventional-combat corpus, every selected endpoint path requires only one leaf-side `rotation_x` and one root-side `rotation_y`; no selected path requires translation or `rotation_z` restrictions.

## Animation selector, state, and local time

- X4: 9.00 build 611726
- Status: shipped-source
- Source: component animation-selector loading/inheritance, ANI descriptor binding, `SequenceControlUnit` state evaluation, `libraries/animation_sequences.xml`
- Live test: no
- Finding:
  - a connection's effective selector list is its own list followed by its parent's effective list;
  - matching is case-insensitive and an inner/child duplicate wins;
  - `truncateanimations` stops inheritance;
  - ANI binding uses the exact `(part, selector)` pair;
  - a selector with no matching descriptor yields the animation default;
  - a missing selector yields the animation default after queued work drains;
  - a non-animated part uses its stored XML part local;
  - normal deployed non-firing turret geometry uses `turret_active` at descriptor duration, then holds that descriptor;
  - `gun_firing` is entered only by the fire trigger and automatically returns to active;
  - `turretloop_active` re-enters itself and therefore loops rather than holds.

The 92-candidate audit found 90 candidates using the `turret_active` family, one using `turretloop_active`, and one selected path that is fully static. All selected animated path parts are covered by the recovered selector/state mechanism.

### Bounded `turretloop_active` phase rule

The Xenon loop path is not bitwise phase-constant. Float32 key/handle differences are about `6e-8`. The accepted offline evaluator therefore treats a loop as usable only when every supported axis uses enum 1/2/5 and every curve-shaping control point stays within `1e-6` of the phase-0 value. This bounds the whole supported linear/cubic curve, not only key timestamps. A loop outside that bound fails closed.

This is a bounded phase-stability guarantee, not exact equality and not a claim about arbitrary loop families.

## Owner translation scale and ANI group 2

- X4: 9.00 build 611726
- Status: inference
- Source: owner vtable `+0x1448`, movement-controller implementations, selected-connection data flow, official turret component/macro corpus
- Live test: no
- Finding: the same owning turret component supplies the translation scale at every selected-path level. Shipped-source data shows turret component/macro data does not create scale-bearing owner controllers and the default/static controller path returns unity. Within the mounted/deployed/non-firing boundary, the offline evaluator therefore uses `S=(1,1,1,1)`.

ANI group 2 does not reach this selected `barrelposition` path. The local evaluator reads position and rotation groups only; group 2 feeds other baked/scene-matrix paths or an `AnimationController` owner scale, and turret asset data does not install such a controller on the mounted turret owner. The non-unit ARG/TEL L Beam/Laser group-2 values therefore do not alter the selected muzzle transform under this boundary.

## Coverage and proof boundary

- X4: 9.00 build 611726
- Status: inference
- Source: official 92-candidate conventional-combat corpus and the build-pinned executable/data rules above
- Live test: validation exists separately; it was not used to derive these rules
- Finding: the accepted shipped-source rules and corpus audit cover every transform input found on all 92 selected endpoint paths for mounted, deployed, non-firing conventional combat turrets in this build: authored/default/ANI local, restriction state, active descriptor/time, and owner scale.

Do not generalize this reference to another X4 executable without re-verifying the build/hash. It does not claim the static `barrelposition` fallback, arbitrary transient scale controllers, firing/recoil poses, missile-turret behavior, or unrelated scene/render matrix paths share the same boundary. Unsupported source structure should fail closed.

LIVE evidence remains validation material. The accepted native measurement route is documented separately in `barrelposition-live-connection-orientation.md`; endpoint selection is documented separately by the accepted endpoint-selection research.