# Rank-1 P8 settled `turret_active` transform (X4 9.00)

**SOURCE-RESOLVED UNDER ALREADY ACCEPTED PROOF BOUNDARIES — NO NEW RUNTIME
SEMANTIC AND NO LIVE TEST REQUIRED**

This reference resolves the settled prospective-muzzle transform of the single
shipped X4 9.00 component `turret_ter_l_beam_01_mk1`, referenced by
`turret_ter_l_beam_01_mk1_macro`. It is rank-1 profile P8 in
[turret-rank1-animation-profile.md](turret-rank1-animation-profile.md).

Every runtime-dependent step below is already covered by an accepted proof
boundary. The concrete files cited are proof sources, not a membership list;
which macros production supports is a separate census/generator question.

## Shipped-source structure

Two laser-tagged endpoints on one depth-4 path:

```text
Connection01 / part_socket
  → Connection02 / part_rotator
    → Connection04 / anim_gun
      → Connection05 / anim_barrel
        → con_laser_01 / con_laser_02
```

Authored local positions, in path order; every path offset is position-only,
with no authored quaternion:

| connection | part | authored local position |
|---|---|---|
| `Connection01` | `part_socket` | `(0, 0, 0)` (empty offset) |
| `Connection02` | `part_rotator` | `(0, 8.5, 0)` |
| `Connection04` | `anim_gun` | `(0, 2.064657, -6.057116)` |
| `Connection05` | `anim_barrel` | `(0, 0.6179247, 45.60182)` |

| endpoint | authored local position |
|---|---|
| `con_laser_01` | `(2.003361, 4.62532e-3, 17.78848)` |
| `con_laser_02` | `(-2.000694, 0.135191, 17.78848)` |

Authored restrictions on the path, and no others: `Connection02` gives
`part_rotator` unrestricted `rotation_y` (yaw); `Connection04` gives `anim_gun`
`rotation_x` with min `-5` and max `80` (pitch).

The component's other part connections — `Connection03` (`detail_m_rotator`,
parent `part_rotator`), `Connection06` (`anim_lights`, parent `part_socket`),
and `Connection07` (`detail_m_socket`) — are off both endpoints' ancestry, so
they carry no muzzle transform. `Connection06` is the only other connection
whose descriptors store keys in candidate channels 1–2, and it is off-path.

`Connection01` authors the five-selector idiom:

| selector | frames |
|---|---|
| `turret_inactive` | 150–150 |
| `turret_activating` | 2–60 |
| `turret_active` | 60–61 |
| `turret_deactivating` | 90–150 |
| `gun_firing` | 70–80 |

## Muzzle-path `turret_active` records

From `.../TURRET_TER_L_BEAM_01_MK1_DATA.ANI` (SHA-256
`efb76bbf9f42170b2fea50de23628e025819f425d2d2cb2cf1c42ef116dd157a`;
30 descriptors, key-data offset 4816, 45 records, 10576 bytes, framing closes
exactly at file end):

| idx | part | key-count family | channel-0 active records |
|---|---|---|---|
| 2 | `part_socket` | `[0,0,0,0,0]` | — |
| 7 | `part_rotator` | `[2,0,0,0,0]` | both `(0x00000000, 0x00000000, 0x00000000)` |
| 17 | `anim_gun` | `[0,0,0,0,0]` | — |
| 22 | `anim_barrel` | `[2,0,0,0,0]` | both `(0x00000000, 0x00000000, 0x367ffe54)` = `(0, 0, 3.8145999496919103e-06)` |

**No muzzle-path descriptor of this component stores any key in candidate
channels 1–4, under any selector.** There is therefore no companion channel to
discriminate — the situation that forced separate live resolutions for the
`[1,2,2,0,0]` beam_02 family and the `[2,2,2,0,0]` P6 gun does not arise here.

Both records of each descriptor are bit-identical, and both values are
bit-identical at every state boundary touching the active state:

| descriptor | last `turret_activating` | `turret_active` | first `turret_deactivating` | `gun_firing` first/last |
|---|---|---|---|---|
| `part_rotator` ch0 | `0x00000000,0x00000000,0x00000000` | same | same | same |
| `anim_barrel` ch0 | `0x00000000,0x00000000,0x367ffe54` | same | same | same |

Stored per-axis interpolation is `0x00000002` on the first record and
`0x00000001` (STEP) on the second, the same authored idiom as the live-tested
Paranid L Beam. Because the two stored values are bit-identical, no
interpolation reading can select a different settled value.

Unlike the Paranid L Beam and the plasma-02 proof source, `gun_firing` here
stores the settled value in **both** of its records on both path descriptors:
this component authors no channel-0 recoil excursion, so a runtime
`barrelposition` sample taken at a `FIRED` instant is not displaced along the
barrel axis by the firing state.

## Settled endpoint model

Reuse the accepted ANI-to-authored/native conversion `(x, y, z)_ANI-stored →
(-x, y, z)_authored/native` and the accepted channel-0 interpretation as an
additive local translation on the animated child part. Both P8 triples store
exactly `0.0` in X, so the conversion is numerically a no-op here and no
axis-sign or handedness choice affects the result.

Exact settled local translations:

```text
part_rotator: (0, 0, 0)
anim_barrel:  (0, 0, 3.8145999496919103e-06)
```

With `C_s`, `C_r`, `C_g`, `C_b` the authored connection transforms above, `T_r`
and `T_b` the settled local translations, `Y(ψ)` and `X(θ)` the native yaw and
pitch joint rotations, and `E_k` endpoint `k`'s authored transform:

```text
M_k(ψ,θ) = C_s · C_r · T_r · Y(ψ) · C_g · X(θ) · C_b · T_b · E_k,   k ∈ {1,2}
```

`T_r` is an exact zero vector, so under the accepted additive channel-0
composition it contributes nothing arithmetically — this is addition of zero,
not an assumed no-op. `T_b` is retained exactly but is a micrometre-scale
displacement, not a material metre-scale one.

At zero yaw and pitch the settled socket-local endpoints are therefore:

| endpoint | settled socket-local position |
|---|---|
| `con_laser_01` | `(2.003361, 11.18720702, 57.333187815)` |
| `con_laser_02` | `(-2.000694, 11.3177727, 57.333187815)` |

In plain English: the muzzle geometry of this turret is carried entirely by its
authored connection offsets and endpoint leaves. Its two settled animation
translations are an exact zero at the rotator and a micrometre at the barrel.

## Evidence mapping for every runtime-dependent step

| required semantic | evidence category | accepted source |
|---|---|---|
| authored path, offsets, restrictions, endpoints, selector frames | shipped-source | this component's XML |
| stored active/adjacent-state records, counts, bits, interpolation, framing | shipped-source | this component's ANI |
| candidate channel 0 is an additive local translation on the animated child part | live-tested | [paranid-l-beam-channel0-semantics.md](paranid-l-beam-channel0-semantics.md), for the structurally identical `{rotator, barrel}` depth-4 keyed-edge set |
| ANI-to-authored `(-x, y, z)` conversion | third-party-technique (numerically inert here: both X are exactly `0.0`) | X4Converter `0be4b494089ba7719d4c5d351e63160ef3843ef5`, as recorded in [turret-rank2-settled-active-transform.md](turret-rank2-settled-active-transform.md) |
| settled-state selection from a 60–61 two-frame active span with two bit-identical keys and exact adjacent-state boundary agreement | live-tested for the identical selector layout and record idiom | [paranid-l-beam-channel0-semantics.md](paranid-l-beam-channel0-semantics.md); the same 60–61 constant-over-active-state argument is accepted in [turret-rank1-p6-settled-transform.md](turret-rank1-p6-settled-transform.md) |
| transform composition order (socket, rotator + yaw, gun + pitch, barrel, endpoint leaf) | live-tested | [paranid-l-beam-channel0-semantics.md](paranid-l-beam-channel0-semantics.md) and [turret-rank1-p6-settled-transform.md](turret-rank1-p6-settled-transform.md) |
| an exact-zero settled channel-0 translation contributes nothing | inference from the accepted additive channel-0 composition; already accepted in the `depth4_zero_translation` case | [paranid-l-beam-channel0-semantics.md](paranid-l-beam-channel0-semantics.md) |
| no channel 1–4 meaning is needed | shipped-source | this component's ANI stores no on-path key in channels 1–4 under any selector |
| both firing endpoints are the authored leaves of `anim_barrel` | shipped-source; endpoint leaves are outside every accepted signature and applied as authored | this component's XML |

STEP interpolation naming remains `third-party-technique` and is not load-bearing
here, because both stored keys are bit-identical.

## Production position

`turret_ter_l_beam_01_mk1_macro` is **not** currently supported. Every accepted
`semantic_case` in `scripts/census_source_semantics.py` fails closed on this
component, verified against the resolver with a P8-shaped fixture:

- `depth4_dual_translation` matches the keyed-edge set `{1, 3}` and the
  `[2,0,0,0,0]` counts but hard-codes the exact Paranid L Beam channel-0 bits;
- `depth4_zero_translation` requires keyed edges `{2, 3}`;
- `depth4_p6_translation` requires the `[2,2,2,0,0]` gun and the exact P6
  authored offsets;
- `depth4_one_key_barrel_translation` requires a one-key barrel, a one-frame
  active selector, and `rotation_x` −10/+90;
- the rank-2 case requires depth 5.

Supporting P8 therefore requires a **new bounded `semantic_case`** keyed on this
component's own exact structure and stored bits. It requires no new runtime
semantic, so it may reuse the existing depth-4 channel-0 derivation math.

## Live-test position

**No live test is required.** Every runtime movement this component exercises
falls inside an accepted proof boundary, and the one boundary that had to be
discriminated live elsewhere — companion channels 1 and 2 — is not populated on
this muzzle path at all.

## Proof boundary

- This resolves the settled `turret_active` muzzle geometry of this one
  component. It makes no claim about `turret_activating`,
  `turret_deactivating`, `gun_firing` interpolation, or transition poses.
- It assigns no meaning to candidate channels 1–4, which this muzzle path does
  not populate.
- It is offline source verification; this component has not itself been
  live-tested, and the `rotation_x` −5/+80 pitch limits are an arc input, not
  part of the settled-transform derivation.
- It establishes no global ANI rule. Reuse requires an independent source match
  for the complete structure, authored transforms, settled values, state
  boundaries, and absent companion channels.

## Evidence records

### Authored hierarchy, restrictions, endpoints, and selector

- X4: 9.00
- Status: shipped-source
- Source: `extensions/ego_dlc_terran/assets/props/weaponsystems/energy/turret_ter_l_beam_01_mk1.xml`; `extensions/ego_dlc_terran/assets/props/weaponsystems/energy/macros/turret_ter_l_beam_01_mk1_macro.xml`
- Live test: no — offline source verification only, as of 2026-09-07
- Finding: the macro declares `<component ref="turret_ter_l_beam_01_mk1" />`.
  The component's two laser endpoints hang off `anim_barrel` on the depth-4
  path `Connection01`/`part_socket` → `Connection02`/`part_rotator` →
  `Connection04`/`anim_gun` → `Connection05`/`anim_barrel`, with the authored
  positions recorded above and no authored quaternion on any path offset.
  `Connection02` authors an unlimited `rotation_y`; `Connection04` authors
  `rotation_x` min `-5` max `80`; no other path connection authors a
  restriction. `Connection01` authors `turret_active` as frames 60–61 within
  the five-selector idiom. Freshly extracted from the installed X4 9.00
  `ego_dlc_terran` catalogs and byte-identical to the existing research cache.

### Muzzle-path `turret_active` stored records

- X4: 9.00
- Status: shipped-source
- Source: `extensions/ego_dlc_terran/assets/props/weaponsystems/energy/TURRET_TER_L_BEAM_01_MK1_DATA.ANI`, SHA-256 `efb76bbf9f42170b2fea50de23628e025819f425d2d2cb2cf1c42ef116dd157a`
- Live test: no — offline source verification only, as of 2026-09-07
- Finding: muzzle-path active key-count families are `part_socket`
  `[0,0,0,0,0]`, `part_rotator` `[2,0,0,0,0]`, `anim_gun` `[0,0,0,0,0]`,
  `anim_barrel` `[2,0,0,0,0]`; no muzzle-path descriptor stores a key in
  candidate channels 1–4 under any selector. The rotator's two active channel-0
  records are both `(0x00000000,0x00000000,0x00000000)`; the barrel's are both
  `(0x00000000,0x00000000,0x367ffe54)`. Both values are bit-identical to the
  last `turret_activating` key, the first `turret_deactivating` key, and both
  `gun_firing` keys for the same descriptor, so this component authors no
  channel-0 recoil excursion.

### P8 settled-transform synthesis

- X4: 9.00
- Status: inference
- Source: the shipped-source facts above compared against the accepted
  channel-0 translation, composition, and settled-state evidence cited in the
  evidence mapping
- Live test: no — not required; every step maps onto an accepted proof boundary
- Finding: compose the exact channel-0 local translations through the authored
  yaw then pitch joints and retain both authored endpoint leaves. The rotator
  translation is an exact zero and the barrel translation is micrometre-scale,
  so the authored connection offsets and endpoint leaves carry the settled
  muzzle geometry. Recognition needs a new bounded `semantic_case`, but no new
  runtime semantic.
