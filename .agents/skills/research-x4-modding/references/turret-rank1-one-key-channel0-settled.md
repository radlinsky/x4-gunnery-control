# Rank-1 one-key `turret_active` channel-0 settled value (X4 9.00)

**SOURCE-RESOLVED STRUCTURAL RULE — NOT A GLOBAL ANI RULE OR LIVE-TESTED COHORT**

This reference records a reusable source-resolution rule for one narrow ANI
shape: a single candidate-channel-0 key on a one-frame `turret_active` state.
The rule is identified by source structure and state behavior, not by turret
macro name. Concrete X4 9.00 components below are the evidence cohort for the
rule, not a permanent membership list.

## Resolved signature

This rule resolves one descriptor only. It may be reused for another component
only after shipped source independently confirms all of the relevant conditions:

- the descriptor is on a muzzle-endpoint ancestry path;
- it is the `turret_active` candidate-channel-0 record for the animated part;
- the record contains exactly one channel-0 key and no keys in channels 1–4 for
  that descriptor;
- the authored `turret_active` selector is a single frame;
- the active key matches the value at the adjacent state boundaries; and
- the stored interpolation is the STEP form described below.

Matching this rule does **not** source-resolve an entire turret. Other authored
transforms, animated parts, endpoint composition, runtime restrictions, and ANI
channels must still be resolved independently. A new macro therefore does not
need a new KB entry merely because its name differs, but it also does not gain
support merely because it has one key.

## X4 9.00 evidence cohort

The audited rank-1 source currently contains this proved form on the
`part_barrel` `turret_active` descriptor for:

- `turret_arg_m_plasma_02_mk1`
- `turret_par_m_plasma_02_mk1`
- `turret_tel_m_plasma_02_mk1`

Their equipment macros are respectively
`turret_arg_m_plasma_02_mk1_macro`, `turret_par_m_plasma_02_mk1_macro`, and
`turret_tel_m_plasma_02_mk1_macro`. These concrete identities are recorded for
traceability; the reusable claim is the structural rule above.

These components are rank-1 depth-4 profiles P7 (`arg`) and P4 (`par`, `tel`)
in [turret-rank1-animation-profile.md](turret-rank1-animation-profile.md).
Their shared muzzle path is:

```text
part_socket → part_rotator → part_gun → part_barrel → con_standard_01/02
```

`part_rotator` carries the `rotation_y` restriction. This reference resolves the
one-key `part_barrel` channel-0 record only.

## The one-key record

For the evidence cohort, `(part_barrel, turret_active)` has key-count family
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

The stored Z value is material at metre scale. The descriptor's offset-148
field is `0x3d088889` (float32 `0.03333333507180214` = 1/30).

## Why one key is the settled value

##### Single-frame active state

All three evidence components author the same selector frames:

| selector | frames |
|---|---|
| `turret_inactive` | 0–0 |
| `turret_activating` | 0–45 |
| `turret_active` | 50–50 |
| `turret_deactivating` | 55–100 |
| `gun_firing` | 50–55 |

`turret_active` is a one-frame state. Its single stored key is therefore the
complete active-state sample; there is no second sample or active sub-span over
which a different value could be selected.

##### Matching state boundaries

The same barrel Z bits `0x40574ede` appear as the last `turret_activating` key,
the first `turret_deactivating` key, and the first and last `gun_firing` keys.
The neighbouring states therefore enter and leave the active state at exactly
the stored active value.

The same authored idiom appears on the cohort's `part_rotator`: its active
channel-0 Y value `0x403d92e4` (`2.962090492248535`) is stored twice in a
`[2, 0, 0, 0, 0]` descriptor. The inactive one-key forms likewise carry the
rest values from which `turret_activating` starts.

##### STEP interpolation corroboration

Pinned X4Converter commit `0be4b494089ba7719d4c5d351e63160ef3843ef5` decodes
per-axis interpolation values as
`{UNKNOWN, STEP, LINEAR, QUADRATIC, CUBIC, BEZIER, BEZIER_LINEARTIME, TCB}` in
`X4ConverterTools/src/ani/Keyframe.cpp`. Stored value `1` is therefore named
`STEP`, and `X4ConverterBlenderAddon/importer.py` maps `STEP` to constant
interpolation. The evidence cohort's single active key stores `1` on all three
axes. This is `third-party-technique`, not engine proof.

##### Channel-0 field meaning

Candidate channel 0 as an additive local translation is established by
[paranid-l-beam-channel0-semantics.md](paranid-l-beam-channel0-semantics.md)
(live-tested for that exact path) and reused inside a separately source-resolved
hierarchy by
[turret-rank2-teladi-channel0-resolution.md](turret-rank2-teladi-channel0-resolution.md).
This reference does not re-derive that field meaning.

## Decision

For a descriptor that independently matches the resolved signature above, the
single `turret_active` channel-0 key may be treated as the constant settled
additive local translation for that one-frame active state. No timing lookup,
ramp-in, or rest-pose default is required for that descriptor.

This is a reusable field/state rule, not a macro allow-list. Source resolution
of the rest of any turret remains a separate requirement.

## Boundary

- This rule does not generalize to arbitrary one-key ANI channels, multi-frame
  one-key states, other selectors, or records whose boundary/interpolation facts
  differ. Those cases remain unproved and must fail closed.
- For the current plasma-02 evidence cohort, `gun_firing` (frames 50–55) overlaps
  active frame 50 and moves the same `part_barrel` channel-0 Z from
  `3.3641886711120605` through `0.2962638735771179` and back within about 1/6 s.
  A runtime barrel-position sample taken at a `FIRED` instant is therefore not
  automatically the settled `turret_active` position; recoil can displace it by
  up to about 3.07 m along the barrel axis.
- This reference does not establish the evidence cohort's remaining authored
  transforms, endpoint composition, candidate channels 1–4, or final runtime
  muzzle position.
- The evidence cohort is **not** live-tested. Do not classify it alongside the
  live-tested Paranid representatives.

## Evidence records

### Authored state/signature and stored one-key record

- X4: 9.00
- Status: shipped-source
- Source: `assets/props/WeaponSystems/heavy/turret_{arg,par,tel}_m_plasma_02_mk1.xml` and `assets/props/WeaponSystems/heavy/TURRET_{ARG,PAR,TEL}_M_PLASMA_02_MK1_DATA.ANI`
- Live test: no — offline source verification only
- Finding: the current evidence cohort supplies the one-frame active selector,
  one-key barrel channel-0 record, record bytes, matching adjacent-state values,
  and recoil overlap described above. These components are evidence carriers
  for the structural rule rather than the identity of the rule itself.

### STEP interpolation decoding

- X4: technique applied to X4 assets; not engine proof
- Status: third-party-technique
- Source: X4Converter commit `0be4b494089ba7719d4c5d351e63160ef3843ef5`, `X4ConverterTools/src/ani/Keyframe.cpp` and `X4ConverterBlenderAddon/importer.py`
- Live test: no
- Finding: per-axis interpolation value `1` is named `STEP` and is imported as
  constant interpolation.

### One-key settled-value rule

- X4: 9.00
- Status: inference
- Source: the shipped-source signature above plus the accepted channel-0 translation meaning
- Live test: no — untested as of 2026-09-06
- Finding: a descriptor independently matching the resolved signature may use
  its single active channel-0 key as the constant settled additive local
  translation for that one-frame `turret_active` state. This resolves that
  descriptor only, not an arbitrary component or ANI record.
