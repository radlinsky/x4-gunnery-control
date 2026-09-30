# Paranid L Beam candidate-channel-0 semantics (X4 9.00)

**PARANID L BEAM CHANNEL-0 TRANSLATION USE: LIVE-TESTED**

Candidate channel 0 is the first of the five ordered ANI key-record groups in
this project's structural vocabulary. X4Converter calls that group
position/location. A controlled X4 9.00 live discriminator now independently
supports treating the two exact Paranid L Beam muzzle-path `turret_active`
channel-0 triples as translations in the existing source-derived muzzle
composition.

This result is intentionally bounded. It proves the translation use needed for
the exact Paranid L Beam path below; it does not by itself promote every ANI
channel-0 record in every component to a globally resolved semantic.

## Scope and raw shipped facts

- Original semantic-research starting SHA:
  `237be7a5a66b9bc4ebe99237c379e68e5297cbcb`.
- Live discriminator repository SHA:
  `f03e3ede96aeac9b702ca58194060ab41a1f55f0`.
- Live scenario: `issue-83-a3-channel0-discriminator-r2`.
- X4 live build: 9.00 (`611726`), 2026-09-01.
- Exact resource:
  `assets/props/WeaponSystems/energy/TURRET_PAR_L_BEAM_01_MK1_DATA.ANI`.
- Exact `turret_active` descriptors checked:
  - index 12, `(part_rotator, turret_active)`: `[2, 0, 0, 0, 0]`
  - index 22, `(anim_barrel, turret_active)`: `[2, 0, 0, 0, 0]`
- The ANI header/table and 128-byte record framing close exactly at the file
  end: 25 descriptors, key-data offset 4016, 24 records, file size 7088 bytes.
- Under the existing candidate-channel framing, descriptor 12's two channel-0
  records have leading triples `(0, 6.145042419433594, 0)` and descriptor 22's
  have `(0, -0.23982000350952148, 27.710205078125)`. Each descriptor repeats
  its triple in both records.
- The component XML names the two parts, hierarchy, selector, restrictions,
  and connection offsets, but does not name any ANI binary channel.

These identities, counts, bytes, and framing are `shipped-source`.

## Source-derived production composition

The accepted Issue #72 provenance trace at
`38da3144120bf31f55c1fec77f22959613b0f3b6` retraced every constant in the
existing Paranid L Beam prospective-muzzle construction to current X4 9.00
source. Its active-position composition is:

`O + Ry(runtime yaw) * (P + Rx(-runtime pitch) * D)`

where the current production constants are:

- `O = (0.000001877547, 2.018104 + 6.145042419433594, -0.00001043081)`
- `P = (-0.000001730653, 2.926126, -16.11956)`
- `D = (-0.36177411330546533, 0.4829345992763463, 55.87084740617998)`

The `+6.145042419433594` term in `O` is descriptor 12 candidate-channel-0.
Descriptor 22 candidate-channel-0 participates in the source-derived `D`
construction through the fixed authored connection transform. Before the live
discriminator, treating those stored triples as translations remained an
`inference` despite the exact numeric provenance.

## X4Converter semantic lead

Pinned X4Converter commit
`0be4b494089ba7719d4c5d351e63160ef3843ef5` claims that the first count and
record block represent position:

- `X4ConverterTools/include/X4ConverterTools/ani/AnimDesc.h` names the first
  count/vector `NumPosKeys` and `posKeys`.
- `X4ConverterTools/src/ani/AnimDesc.cpp` reads that block first, labels those
  records `Position Keyframes`, and maps them to intermediate key type
  `location`.

Classification: `third-party-technique`. This supplied the semantic hypothesis;
it is not the live proof.

## Independent X4 live discriminator

##### Fail-closed qualification

The r2 fixture first required the exact selected Beam
`turret_par_l_beam_01_mk1_macro` in `group_rear_down_mid` to pass both target
geometries before observation was armed. X4 reported:

- target A: arc pass, external LOS pass, range `5084.625 <= 14000`;
- target B: arc pass, external LOS pass, range `6200.625 <= 14000`;
- bearing separation: `50.9085` degrees;
- post-warp location failures: 0.

The fixture census was also clean: 3 spawned ships, one shooter, exactly one
Beam plus one held-fire plasma, and zero loadout/location/preflight failures.

##### Actual firing evidence

The exact selected Beam fired at and hit both intended target roots. This is
stronger than a solution-only geometry result:

- target A (`ISSUE83 CHANNEL0 TARGET A DOWN ASTERN 1`): repeated exact-Beam
  `FIRED` records and correlated `HIT` records;
- target B (`ISSUE83 CHANNEL0 TARGET B DOWN ASTERN OFFSET 1`): repeated
  exact-Beam `FIRED` records and correlated `HIT` records.

The non-selected plasma remained held fire in the observation census.

##### Full model versus channel-0-omitted control

Use settled firing samples after the turret had converged on each materially
distinct bearing. The runtime `barrelposition` and target bearing are both from
the exact firing Beam at the same firing instant.

| target | runtime yaw | runtime pitch | full-model muzzle | X4 runtime barrel | full-model error |
|---|---:|---:|---|---|---:|
| A | `3.14159` | `0.794607` | `(0.361778, 51.296385, -22.677009)` | `(-0.315022, 51.7481, -22.2003)` | `0.9431 m` |
| B | `-2.24964` | `0.958926` | `(-11.896648, 57.101156, -10.062470)` | `(-11.4341, 57.5926, -9.47812)` | `0.8927 m` |

The correctly omitted control removes both exact candidate-channel-0 source
vectors. Their magnitudes are:

- descriptor 12: `6.1450424 m`;
- descriptor 22: `27.7112428 m`.

Every authored/runtime transform between those source vectors and the muzzle is
rotational, so it preserves each vector's magnitude. Therefore the displacement
between the full model and a control omitting both vectors is conservatively at
least the reverse-triangle bound:

`27.7112428 - 6.1450424 = 21.5662004 m`.

Using the same two runtime samples, the omitted control must therefore be at
least:

- target A: `21.5662004 - 0.9430566 = 20.6231 m` from X4's runtime barrel;
- target B: `21.5662004 - 0.8927106 = 20.6735 m` from X4's runtime barrel.

So the full source-derived translation model is under 1 m from X4 at both
bearings, while the channel-0-omitted control is guaranteed to be more than
20.6 m away. The result does not depend on choosing a favorable fixed-axis
rotation for the omitted control.

Classification: `live-tested` for using these two exact Paranid L Beam
candidate-channel-0 triples as translations in this source-derived active muzzle
path.

## Conclusion and proof boundary

**The Issue #83 Paranid L Beam channel-0 discriminator passes.** For the exact
Paranid L Beam muzzle path, candidate channel 0 can now be treated as a
translation input in the accepted source-derived transform composition.

What this result does **not** prove:

- that every component's candidate channel 0 can be accepted without its own
  source/topology resolution;
- interpolation or timing semantics (both tested Paranid records repeat their
  vector in their two channel-0 records, so no interpolation distinction was
  required here);
- candidate channels 1–4;
- arbitrary axis, pivot, transform-order, or selector-propagation rules outside
  the already provenance-traced Paranid L Beam construction;
- B3's final runtime-position tolerance. This live test was a semantic
  discriminator, not the later nine-pose validation matrix.

Unknown semantics for other topology/profile requirements must still fail
closed.

## Evidence records

### Exact stored descriptor facts

- X4: 9.00
- Status: shipped-source
- Source: `assets/props/WeaponSystems/energy/TURRET_PAR_L_BEAM_01_MK1_DATA.ANI`; `assets/props/WeaponSystems/energy/turret_par_l_beam_01_mk1.xml`
- Live test: no — offline source verification only
- Finding: descriptors 12 and 22 are the exact named `turret_active` records with `[2, 0, 0, 0, 0]`, carrying the repeated triples recorded above.

### Candidate-channel-0 position interpretation

- X4: 9.00
- Status: third-party-technique
- Source: X4Converter commit `0be4b494089ba7719d4c5d351e63160ef3843ef5`
- Live test: no — third-party parser interpretation only
- Finding: X4Converter calls the first count/vector `NumPosKeys`/`posKeys` and exports it as `location`.

### Paranid L Beam translation use

- X4: 9.00 build 611726
- Status: live-tested
- Source: owner-captured X4 `debug.log` from `issue-83-a3-channel0-discriminator-r2`; the accepted Issue #72 source trace in `md/x4_gunnery_control.xml` and the exact Beam ANI/component resources
- Live test: yes — 2026-09-01 at repository SHA `f03e3ede96aeac9b702ca58194060ab41a1f55f0`
- Finding: both qualified target bearings produced exact-Beam FIRED/HIT evidence; settled full-model errors were `0.9431 m` and `0.8927 m`, while the same-sample channel-0-omitted control is conservatively bounded above `20.6 m` error.
