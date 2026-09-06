# Rank-1 one-key `turret_active` channel-0 settled value (X4 9.00)

**SOURCE-RESOLVED FOR THE EXACT PLASMA 02 MK1 GROUP — NOT LIVE-TESTED**

One muzzle-path `turret_active` candidate-channel-0 descriptor in this group
stores exactly one key rather than the repeated pair recorded for the rank-2
cohort. This reference records why that single key is the constant settled
local translation for the whole `turret_active` state, and where the result
stops.

## Scope

Exactly three macros and their components:

- `turret_arg_m_plasma_02_mk1_macro` / `turret_arg_m_plasma_02_mk1`
- `turret_par_m_plasma_02_mk1_macro` / `turret_par_m_plasma_02_mk1`
- `turret_tel_m_plasma_02_mk1_macro` / `turret_tel_m_plasma_02_mk1`

These are rank-1 depth-4 profiles P4 (`par`, `tel`) and P7 (`arg`) in
[turret-rank1-animation-profile.md](turret-rank1-animation-profile.md). The
shared muzzle path is:

```text
part_socket → part_rotator → part_gun → part_barrel → con_standard_01/02
```

`part_rotator` carries the `rotation_y` restriction. This reference covers the
`part_barrel` channel-0 record only; it does not resolve the group's remaining
transform layers, endpoints, or channels 1–4.

## The one-key record

The `(part_barrel, turret_active)` descriptor has key-count family
`[1, 0, 0, 0, 0]`: descriptor index 22 for `par`/`tel` and 27 for `arg`. Its
single 128-byte channel-0 record is at file byte offset `8048` in all three
`assets/props/WeaponSystems/heavy/TURRET_{ARG,PAR,TEL}_M_PLASMA_02_MK1_DATA.ANI`
resources and is bit-identical across them
(SHA-256 `8981958ea3c56ed69471846a6b831c99065a85dcaa733599038e4a94b8d943d4`):

| field | stored bits | float32 |
|---|---|---|
| ValueX | `0x00000000` | 0.0 |
| ValueY | `0xb4bffc2b` | −3.575999869553925e-07 |
| ValueZ | `0x40574ede` | 3.3641886711120605 |
| InterpolationX/Y/Z | `0x00000001` ×3 | — |
| `Time` | `0x34000000` | 1.1920928955078125e-07 |

The stored Z value is material at metre scale, unlike the ~1e-7 rank-2 Teladi
rotator-base vector. The descriptor's offset-148 field is `0x3d088889`
(float32 `0.03333333507180214` = 1/30).

## Why one key is the settled value

##### 1. `turret_active` is authored as a single frame

All three components author the same selector set on the animated connection:

| selector | frames |
|---|---|
| `turret_inactive` | 0–0 |
| `turret_activating` | 0–45 |
| `turret_active` | 50–50 |
| `turret_deactivating` | 55–100 |
| `gun_firing` | 50–55 |

`turret_active` is a zero-length, one-frame state. A single stored key is the
complete description of a one-frame span: there is no second time sample to
interpolate toward and no sub-span over which a different default could apply.
Key count tracks the authored span, consistent with the rank-2 cohort's 30–31
span and two stored keys.

##### 2. The active key equals the activating and deactivating boundary values

The same bits `0x40574ede` appear as:

- the last key of `turret_activating` (`Time` 1.5 s = frame 45);
- the first key of `turret_deactivating` (`Time` 0.0);
- the first and last keys of `gun_firing`.

The neighbouring states enter and leave `turret_active` at exactly this value.
Any reading other than a constant hold would introduce a discontinuity at every
state boundary the shipped data explicitly matches.

The same continuity holds for the group's `part_rotator` channel-0 Y value
`0x403d92e4` (`2.962090492248535`), whose `[2, 0, 0, 0, 0]` active descriptor
stores that constant twice. The one-key and two-key forms are therefore the
same authored idiom, one written redundantly.

The one-key form is also unambiguous in `turret_inactive`: both `part_barrel`
and `part_rotator` store a single channel-0 key there carrying exactly the
rest values that `turret_activating` starts from.

##### 3. The stored interpolation value is STEP

Pinned X4Converter commit `0be4b494089ba7719d4c5d351e63160ef3843ef5` decodes
the three per-axis interpolation members with the enumeration
`{UNKNOWN, STEP, LINEAR, QUADRATIC, CUBIC, BEZIER, BEZIER_LINEARTIME, TCB}`
(`X4ConverterTools/src/ani/Keyframe.cpp`), so stored value `1` is `STEP`, and
its Blender importer maps `STEP` to constant interpolation
(`X4ConverterBlenderAddon/importer.py`). The single active key stores `1` on
all three axes. Across these files the terminal key of every descriptor is
`STEP` while intermediate keys are `BEZIER` (`5`).

##### 4. Channel 0 is already an accepted additive local translation

Candidate channel 0 as an additive local translation is established by
[paranid-l-beam-channel0-semantics.md](paranid-l-beam-channel0-semantics.md)
(live-tested for that exact path) and applied within a separately
source-resolved hierarchy by
[turret-rank2-teladi-channel0-resolution.md](turret-rank2-teladi-channel0-resolution.md).
This reference does not re-derive that field meaning.

## Decision

For these three components, the single `(part_barrel, turret_active)`
channel-0 key is source-resolved as the constant settled additive local
translation applied throughout `turret_active`. No timing lookup, ramp-in, or
rest-pose default is required.

## Boundary

- `gun_firing` (frames 50–55) overlaps the single active frame 50 and moves the
  same `part_barrel` channel-0 Z from `3.3641886711120605` through
  `0.2962638735771179` and back within about 1/6 s. A runtime barrel-position
  sample taken at a `FIRED` instant is therefore not automatically the settled
  `turret_active` position; recoil can displace it by up to about 3.07 m along
  the barrel axis.
- Not established: this group's remaining authored transforms, endpoint
  composition, or candidate channels 1–4; any runtime validation of the
  resulting muzzle position; and any generalisation of the one-key rule to
  arbitrary ANI channels, other selectors, or other components. Unproved cases
  must still fail closed.
- This group is **not** live-tested. Do not classify it alongside the
  live-tested Paranid representatives.

## Evidence records

### Authored selectors, path, and stored one-key record

- X4: 9.00
- Status: shipped-source
- Source: `assets/props/WeaponSystems/heavy/turret_{arg,par,tel}_m_plasma_02_mk1.xml`
  and `assets/props/WeaponSystems/heavy/TURRET_{ARG,PAR,TEL}_M_PLASMA_02_MK1_DATA.ANI`
- Live test: no — offline source verification only
- Finding: the muzzle path, the 0–0 / 0–45 / 50–50 / 55–100 / 50–55 selector
  frames, the `[1, 0, 0, 0, 0]` active `part_barrel` family, the record bytes
  and offset above, their bit-identity across the three resources, and the
  activating/deactivating/`gun_firing` boundary value matches.

### STEP interpolation decoding

- X4: technique applied to X4 assets; not engine proof
- Status: third-party-technique
- Source: X4Converter commit `0be4b494089ba7719d4c5d351e63160ef3843ef5`,
  `X4ConverterTools/src/ani/Keyframe.cpp` and
  `X4ConverterBlenderAddon/importer.py`
- Live test: no
- Finding: per-axis interpolation value `1` is named `STEP` and is imported as
  constant interpolation; the single active key stores `1` on all three axes.

### One-key settled value resolution

- X4: 9.00
- Status: inference
- Source: the shipped-source facts above plus the accepted channel-0
  translation meaning
- Live test: no — untested as of 2026-09-06
- Finding: for this exact three-component group the single active channel-0
  key is the constant settled additive local translation for the whole
  `turret_active` state. Bounded to this group and this state.
