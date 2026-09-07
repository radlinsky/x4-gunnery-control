# Rank-1 M Beam 02 settled `turret_active` transform (X4 9.00)

**SOURCE-RESOLVED FOR ONE STRUCTURAL FAMILY — LIVE-TESTED ON THE ARGON
REPRESENTATIVE**

This reference resolves the settled `turret_active` barrel transform for the
rank-1 profile P2 family in
[turret-rank1-animation-profile.md](turret-rank1-animation-profile.md):

- `turret_arg_m_beam_02_mk1`
- `turret_par_m_beam_02_mk1`
- `turret_tel_m_beam_02_mk1`

Their `detail_xl_barrel` `turret_active` descriptor has key-count family
`[1, 2, 2, 0, 0]`. Because candidate channels 1 and 2 are populated, this
descriptor does **not** satisfy
[turret-rank1-one-key-channel0-settled.md](turret-rank1-one-key-channel0-settled.md),
whose signature requires no keys in channels 1–4. That rule is therefore not
reused here; this family needed its own resolution.

## Shipped-source structure

The three components' ANI resources are bit-identical whole-file:

```text
SHA-256 98a8b6e7751d9ef5c7ed452d81d20d9a566aeaa47787249c04de518719507ec7
```

The `arg`, `par`, and `tel` members therefore share one animation byte-for-byte;
family sharing is a shipped-source fact, not an inference.

Active `detail_xl_barrel` values:

| candidate channel | stored first-three values | across selectors |
|---|---|---|
| 0 (one key) | approximately `(-4.47e-7, 1.19e-7, 3.4313702583)` | exact agreement at the activating and deactivating boundaries |
| 1 (two keys) | `(-6.2831854820251465, -0.0, 0.0)` | flat |
| 2 (two keys) | `(0.9999998211860657, 1.0, 1.000000238418579)` | flat |

The channel-1 X value is float32 −2π. The channel-2 triple is identity to
float32 residue.

## Third-party interpretation

At pinned X4Converter commit
`0be4b494089ba7719d4c5d351e63160ef3843ef5`, candidate channel 1 maps to
additive Euler rotation and candidate channel 2 maps to multiplicative scale.
This is `third-party-technique` and is **not** promoted here to global X4 ANI
channel semantics; it supplies a testable hypothesis for this family only.

Under that hypothesis, an additive-radian channel-1 X of −2π is a full turn and
therefore effectively identity, and the channel-2 triple is effectively unit
scale. The prediction is that the settled barrel pose is the channel-0
translation alone. A degree reading of channel 1 would instead rotate the barrel
by −2π degrees and displace the muzzle materially.

## X4 9.00 live discriminator

A controlled live run on 2026-09-06 used X4 9.00 build 611726, repository SHA
`bc380802e52006aa0d5f58ca7d1a69ee483771aa`, and the disposable scenario
`issue-128-arg-m-beam-02-live-transform-r1`. The representative was
`turret_arg_m_beam_02_mk1_macro` on the controlled Colossus E.

Contract:

- exactly the two beam turrets fired, and both hit their intended targets;
  competing plasma turrets remained HOLD FIRE;
- each source model was instantiated from the bore direction of the same
  `FIRED` projectile, not from target-relative telemetry signs;
- the score is the runtime `barrelposition` residual against the endpoint-2
  prediction taken **perpendicular to the bore**, so `gun_firing` recoil along
  the barrel axis cannot determine the result.

Post-settled `FIRED` samples:

| side | samples | intended median | intended max | degree-control median | degree-control min |
|---|---:|---:|---:|---:|---:|
| left | 6 | ~`0.0083` m | ~`0.0130` m | ~`0.5399` m | ~`0.5289` m |
| right | 10 | ~`0.0035` m | ~`0.0180` m | ~`0.5357` m | ~`0.5284` m |

The intended maximum is more than an order of magnitude below the control
minimum on both sides. Additive-radian treatment therefore makes the stored −2π
effectively identity for this structural family, and a degree reading is
decisively rejected.

## Decision

For the P2 `detail_xl_barrel` descriptor, the settled `turret_active` transform
is the channel-0 additive local translation; the channel-1 and channel-2
companions contribute no material additional settled transform. The integrated
live result establishes this for the shared beam_02 animation behavior.

## Proof boundary

- No claim is made about arbitrary ANI candidate channel 1 or channel 2
  semantics outside this family and settled state.
- No claim is made about transition/interpolation or recoil semantics.
- Channel 2's exact runtime meaning is **not** independently discriminated: its
  candidate scale values are effectively identity, so the live run cannot
  distinguish "scale applied" from "scale ignored".
- The live proof covers the shared beam_02 animation behavior on the ARG
  representative. ARG/PAR/TEL family sharing is `shipped-source` (bit-identical
  ANI), not a live-tested claim for `par` and `tel` individually.

## Evidence records

### Shared beam_02 ANI resource and active barrel values

- X4: 9.00
- Status: shipped-source
- Source: `assets/props/WeaponSystems/heavy/turret_{arg,par,tel}_m_beam_02_mk1.xml` and the shared `..._DATA.ANI` resources, SHA-256 `98a8b6e7751d9ef5c7ed452d81d20d9a566aeaa47787249c04de518719507ec7`
- Live test: no — offline source verification only
- Finding: the three ANI resources are bit-identical whole-file; the active
  `detail_xl_barrel` key-count family is `[1, 2, 2, 0, 0]`; channel 1 is
  `(-6.2831854820251465,-0.0,0.0)` and channel 2 is
  `(0.9999998211860657,1.0,1.000000238418579)`, both flat across selectors;
  channel 0 is approximately `(-4.47e-7,1.19e-7,3.4313702583)` with exact
  activating/deactivating boundary agreement. Populated channels 1 and 2 mean
  the existing one-key channel-0 rule does not apply.

### Channel 1 and channel 2 field mapping

- X4: technique applied to X4 assets; not engine proof
- Status: third-party-technique
- Source: X4Converter commit `0be4b494089ba7719d4c5d351e63160ef3843ef5`
- Live test: no
- Finding: candidate channel 1 is mapped to additive Euler rotation and
  candidate channel 2 to multiplicative scale. Not promoted to global X4
  semantics.

### ARG M Beam 02 settled transform live discrimination

- X4: 9.00 build 611726
- Status: live-tested
- Source: owner-captured `debug.log`, 2026-09-06, repository SHA `bc380802e52006aa0d5f58ca7d1a69ee483771aa` plus disposable scenario `issue-128-arg-m-beam-02-live-transform-r1`; representative `turret_arg_m_beam_02_mk1_macro` on the controlled Colossus E
- Live test: yes — exactly two beam turrets fired and hit both intended targets while competing plasma turrets held fire; models instantiated from each FIRED projectile bore direction; scored on the endpoint-2 runtime `barrelposition` residual perpendicular to the bore so recoil could not determine the result
- Finding: post-settled LEFT (6 FIRED samples) intended median ~`0.0083` m and
  max ~`0.0130` m against a degree-control median ~`0.5399` m and min
  ~`0.5289` m; post-settled RIGHT (10 FIRED samples) intended median ~`0.0035` m
  and max ~`0.0180` m against a degree-control median ~`0.5357` m and min
  ~`0.5284` m. Additive-radian treatment makes the stored −2π effectively
  identity for this structural family and decisively rejects a degree reading;
  the channel-1/2 companions add no material settled transform.
