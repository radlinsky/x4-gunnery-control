# Rank-1 P6 settled `turret_active` transform (X4 9.00)

**SOURCE-RESOLVED FOR ONE STRUCTURAL FAMILY — LIVE-TESTED ON THE TELADI
REPRESENTATIVE**

This reference resolves the settled prospective-muzzle transform shared by:

- `turret_pir_l_battleship_01_laser_01_mk1`
- `turret_tel_l_laser_01_mk1`

Their equipment macros explicitly reference those respective component assets.
The Teladi representative was live-tested. Pirate applicability rests on the
identical source inputs recorded below; it is not a claim that the Pirate macro
was separately exercised in X4.

## Shipped-source structure

Both components have two laser-tagged endpoints on the same depth-4 path:

```text
part_socket → part_rotator → part_gun → part_barrel
            → con_laser_01 / con_laser_02
```

All authored part offsets and rotations on this path are identity. Connection
positions, in path order, are:

| part | connection | authored local position |
|---|---|---|
| `part_socket` | `Connection01` | `(0, 0, 0)` |
| `part_rotator` | `Connection03` | `(-0.0244168, 17.52643, -0.1001702)` |
| `part_gun` | `Connection06` | `(2.980232e-8, -0.02269363, -5.565336)` |
| `part_barrel` | `Connection07` | `(-4.023314e-6, 0.1448975, 11.62085)` |

The endpoint-local positions are:

| endpoint | authored local position |
|---|---|
| `con_laser_01` | `(4.560871, -0.1317711, 23.71955)` |
| `con_laser_02` | `(-4.823473, -0.001207352, 23.71955)` |

`Connection03` gives `part_rotator` unrestricted authored `rotation_y`.
`Connection06` gives `part_gun` authored `rotation_x` from −5° through +90°.
These are the yaw and pitch joints respectively.

The exact `turret_active` selector on `Connection01` spans frames 60–61.
The active path descriptor families are socket `[0,0,0,0,0]`, rotator
`[0,0,0,0,0]`, gun `[2,2,2,0,0]`, and barrel `[2,0,0,0,0]`.

## Settled records and state boundaries

The first three stored values required by the settled pose are:

| descriptor and candidate channel | both active records |
|---|---|
| `part_gun`, channel 0 | `(0, 0, 0)` |
| `part_gun`, channel 1 | `(0, -0, 0)` |
| `part_gun`, channel 2 | `(1, 1, 1)` |
| `part_barrel`, channel 0 | `(0, -1.9072999748459551e-6, 0)` |

For every row, the first-three values are bit-identical across the two active
records. They also equal the last stored `turret_activating` value and the first
stored `turret_deactivating` value for the same descriptor/channel. The settled
input is therefore constant over the authored active state; no interpolation or
transition-control interpretation is needed to choose a different value.

The Pirate and Teladi active record blocks are bit-identical. The complete gun
active block has SHA-256
`8c8da483e4bd86007be3a82f63f38a90baf69ff023cb014e91094bc7459c83ab`;
the complete barrel active block has SHA-256
`cf9605efc1f5edd1c72c1c073907e0dd729870d839c6d6395bfb845e6aaa3969`.
Their whole ANI resources are not claimed identical. Direct XML comparison
also finds the same path connection transforms, endpoint transforms, selector,
and yaw/pitch restrictions in both components.

## Settled endpoint model

Reuse the accepted ANI-to-authored/native conversion:

```text
(x, y, z)_ANI-stored → (-x, y, z)_authored/native
```

The accepted channel-0 interpretation places its converted value as an
additive local translation on the animated child part. P6 therefore has exact
settled translations:

```text
part_gun:    (0, 0, 0)
part_barrel: (0, -1.9072999748459551e-6, 0)
```

The conversion leaves these particular triples numerically unchanged because
their X values are zero. The barrel value is retained exactly but is not a
material metre-scale displacement. The gun channel-1 `(0,-0,0)` and channel-2
`(1,1,1)` companions add no material settled rotation, scale, or other
transform for this family, as established by the live discriminator below.

Let `C_s`, `C_r`, `C_g`, and `C_b` be the authored connection transforms above;
let `T_g` and `T_b` be the settled local translations; let `Y(ψ)` and `X(θ)` be
the native yaw and pitch joint rotations; and let `E_k` be endpoint `k`'s
authored transform. The settled endpoint model is:

```text
M_k(ψ,θ) = C_s · C_r · Y(ψ)
           · C_g · T_g · X(θ) · C_b · T_b · E_k,    k ∈ {1,2}
```

`T_g` is identity, so it has no numerical effect. Operationally, the hierarchy
is socket, rotator and live yaw, gun settled translation and live pitch,
barrel settled translation, then the distinct endpoint leaf. The live proof
instantiated the variable joint pose from independently logged bore/mount
angles rather than asserting a global sign convention for target-bearing
telemetry.

No material settled translation, rotation, scale, or other transform is
missing from this model. The exact micrometre-scale barrel translation remains
part of the source model.

## X4 9.00 live discriminator

The controlled Teladi-representative run used repository SHA
`c203701c7661c94bc6b193ae0e26332ee2587de0` and scenario
`issue-132-p6-tel-l-laser-transform-r1`. Correlated setup evidence established
the exact scenario, two spawned ships, one shooter, one ordinary turret, no
missile turrets, exact group `group_front_up_mid2`, and exact member macro
`turret_tel_l_laser_01_mk1_macro`. The observer then attributed firing and
target hits to that sole turret.

The intended model treated the gun companions as adding no material transform.
The discriminating control instead added the stored channel-2 unit triple to
unit authored scale, producing local scale `(2,2,2)` at `part_gun`. That control
adds an extra copy of the downstream gun-to-endpoint vector, approximately
35.63–35.67 m depending on endpoint.

After settling, runtime `barrelposition` repeated as approximately:

```text
(-4.84789, 42.7379, 19.0772)
```

The independently instantiated endpoint-2 source prediction was approximately
`(-4.84789379, 42.73788185, 19.07721840)`, an absolute residual of about
`2.61e-5 m`. The doubled-scale control residual was about `35.66834 m`.
Endpoint 1 was independently excluded by a residual of about `9.38525 m`.
The post-settled evidence contained 24 exact-turret `FIRED` samples with the
same barrel result and 12 attributed target `HIT` records.

The live result therefore establishes that the active gun channel-1/channel-2
companions add no material settled transform for this shared source family.

## Decision and proof boundary

The complete settled P6 endpoint transform is source-resolved. One structural
rule covers both components because every authored and active-record input used
by the model is identical; only the Teladi representative is individually
live-tested.

This result does **not** establish:

- global ANI candidate-channel 1 or channel 2 semantics;
- whether an identity-valued channel 2 is multiplicative unit scale or ignored
  outside this family—the live result cannot distinguish those two no-op cases;
- non-identity scale behavior, nonzero Euler components, or Euler order;
- transition interpolation/control semantics or `gun_firing` recoil semantics;
- a global runtime yaw/pitch telemetry-sign convention; or
- runtime validation of the Pirate equipment macro as a separate instance.

Reusing this result requires an independent source match for the complete
depth-4 structure, authored transforms/restrictions, settled values, state
boundaries, and companion-channel evidence. Similar key counts are not enough.

## Evidence records

### Shared authored hierarchy and settled records

- X4: 9.00
- Status: shipped-source
- Source: `assets/props/WeaponSystems/standard/turret_tel_l_laser_01_mk1.xml`; `assets/props/WeaponSystems/standard/TURRET_TEL_L_LASER_01_MK1_DATA.ANI`; `extensions/ego_dlc_pirate/assets/props/weaponsystems/standard/turret_pir_l_battleship_01_laser_01_mk1.xml`; `extensions/ego_dlc_pirate/assets/props/weaponsystems/standard/TURRET_PIR_L_BATTLESHIP_01_LASER_01_MK1_DATA.ANI`; the two corresponding equipment-macro XML resources
- Live test: no — offline source verification only
- Finding: the two components have identical required authored paths,
  transforms, endpoints, selectors, restrictions, active first-three values,
  adjacent-state boundary values, and bit-identical complete active gun/barrel
  record blocks. Their whole ANI files are not asserted identical.

### ANI field conversion and composition technique

- X4: technique applied to X4 assets; not engine proof
- Status: third-party-technique
- Source: X4Converter commit
  `0be4b494089ba7719d4c5d351e63160ef3843ef5`, as recorded in
  [turret-rank2-settled-active-transform.md](turret-rank2-settled-active-transform.md)
- Live test: no
- Finding: candidate channel 0 is mapped to additive local position, channel 1
  to additive local Euler rotation, and channel 2 to scale; accepted ANI
  position/rotation triples enter authored/native geometry as `(-x,y,z)`.
  These mappings are not promoted to global engine semantics here.

### P6 settled-transform synthesis

- X4: 9.00
- Status: inference
- Source: the shipped-source structure and constant state-boundary records
  above, plus the accepted channel-0 and ANI-to-authored composition evidence
- Live test: representative runtime corroboration recorded separately below
- Finding: compose exact local channel-0 translations through authored yaw then
  pitch and retain both authored endpoint leaves; the gun channel-1/channel-2
  identity values require no material settled transform under the candidate
  source model.

### Teladi representative settled absolute endpoint

- X4: 9.00
- Status: live-tested
- Source: owner-captured `debug.log`, reviewed 2026-09-07; repository SHA
  `c203701c7661c94bc6b193ae0e26332ee2587de0`; scenario
  `issue-132-p6-tel-l-laser-transform-r1`
- Live test: yes — exact scenario/group/loadout/observer attribution; 24
  post-settled exact-turret firing samples and 12 attributed target hits
- Finding: endpoint 2 reproduced settled runtime `barrelposition` to about
  `2.61e-5 m` absolute error; the `(2,2,2)` additive-scale control missed by
  about `35.66834 m`, and endpoint 1 missed by about `9.38525 m`. The P6 active
  gun channel-1/channel-2 companions therefore add no material settled
  transform for the shared source family.
