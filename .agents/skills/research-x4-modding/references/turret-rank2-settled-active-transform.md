# Rank-2 turret settled `turret_active` transform (X4 9.00)

**SOURCE-DERIVED RULE — LIVE-TESTED ON THE PARANID M LASER REPRESENTATIVE**

The seven rank-2 turret components have enough mutually corroborating offline
source evidence to define one rule for their settled `turret_active` pose. A
controlled X4 9.00 discriminator independently corroborated additive local-X
channel-1 composition on the exact Paranid M laser representative. A later
nine-pose live re-evaluation validated that representative's corrected
absolute endpoint-2 positions without fitting a runtime constant.

This reference closes the source-semantics and representative absolute-position
questions needed for the settled pose. It does not establish arbitrary ANI
channels, transition interpolation, or a global runtime telemetry sign
convention.

## Scope and sources

The cohort is:

- `turret_par_m_beam_01_mk1`
- `turret_par_m_laser_01_mk1`
- `turret_par_m_plasma_01_mk1`
- `turret_tel_m_beam_01_mk1`
- `turret_tel_m_laser_01_mk1`
- `turret_tel_m_plasma_01_mk1`
- `turret_ter_m_laser_01_mk1`

Research starting SHA: `a9e5585953b46db16a1cd94731d6f0bc0ed1f97b`.

Offline sources checked:

1. The seven X4 9.00 component XML and ANI resources already enumerated in
   [turret-rank2-channel0-records.md](turret-rank2-channel0-records.md),
   [turret-rank2-channel1-part-arm-records.md](turret-rank2-channel1-part-arm-records.md),
   and
   [turret-rank2-channel1-rotator-base-records.md](turret-rank2-channel1-rotator-base-records.md).
2. The schema-25 census at
   `.x4-research-cache/issue72-a3-topology-priorities-census.json` and direct
   XML/ANI re-parsing with `scripts/census_ani_parser.py` plus an independent
   descriptor/record dump. The cache and dump are untracked research inputs.
3. Pinned X4Converter commit
   `0be4b494089ba7719d4c5d351e63160ef3843ef5`, especially
   `AnimDesc.h`, `AnimDesc.cpp`, `model/Component.cpp`,
   `model/Connection.cpp`, `model/Part.cpp`, and
   `X4ConverterBlenderAddon/importer.py`.
4. The current official Egosoft download page, accessed 2026-09-02, which lists
   Blender Mod Tools 0.7.0 for X4 9.00 and above. The package is
   registration/login restricted and was not available in this environment.
   The public asset guide and the extracted current XSD set do not specify the
   binary ANI channel layout or its composition rule. An Egosoft-forum
   community guide supplied only a workflow lead, not an official semantic.

The original source pass did not run X4. The later live discriminator and
nine-pose absolute-position re-evaluation are recorded below and used the exact
source chain in this file without fitting runtime constants. The accepted
ANI-to-authored conversion is implemented at
`ed25ee0bcf527afa5d8034254ef4625e1c3da7ee`.

## Exact authored topology

Every component has two firing endpoints on one path:

```text
anim_base → part_arm → rotator-base → part_rotator → part_gun → endpoint
```

The rotator-base part identity is `detail_xl_rotator_base` except for
`turret_tel_m_plasma_01_mk1` (`detail_xl_rotator_base_002`) and
`turret_ter_m_laser_01_mk1` (`rotator_base`). All four state selectors are on
`ConnectionForanim_base`:

| selector | frames |
|---|---:|
| `turret_inactive` | 1–2 |
| `turret_activating` | 2–30 |
| `turret_active` | 30–31 |
| `turret_deactivating` | 50–80 |

`part_rotator` carries an unrestricted `rotation_y` restriction. `part_gun`
carries `rotation_x` with limits −10° through 89°. These are authored axis and
limit facts; this source pass does not assign signs to runtime yaw/pitch
telemetry.

### Shared upstream authored transforms

Positions are connection-local `(x,y,z)`. Quaternions are XML
`(qx,qy,qz,qw)`. Omitted rotations are identity.

| family | `anim_base` position | `part_arm` position / quaternion | rotator-base position / quaternion | rotator-base part offset |
|---|---|---|---|---|
| Paranid ×3 | `(0,-1.991911,2.638335)` | `(0,-0.008089185,0)` / identity | `(0,0.003018975,-3.745065)` / `(0.3007058,0,0,-0.953717)` | `(0,5.96e-8,-1.192e-7)` |
| Teladi ×3 | `(0,-1.999982,-0.0001986027)` | `(0,-1.80006e-5,2.669387)` / `(5.96e-8,0,0,-1)` | `(0,0.003018746,-3.745065)` / `(-5.96e-8,0,0,-1)` | `(0,1.192e-7,0)` |
| Terran | `(0,-1.991911,-0.2152019)` | `(0,-0.008089185,2.853536)` / identity | `(0,0.003018975,-3.745065)` / `(0.3007058,0,0,-0.953717)` | `(0,5.96e-8,-1.192e-7)` |

The Paranid/Terran rotator-base quaternion is the signed principal X rotation
−35° (quaternion sign-normalized); the Teladi values are identity to exported
float residue.

### Per-component downstream transforms and endpoints

| component | `part_rotator` position / quaternion / part offset | `part_gun` position / quaternion / part offset | endpoint 1; endpoint 2 positions |
|---|---|---|---|
| `par_m_beam` | `(5.48e-8,2.384e-7,-4.172e-7)` / `(-0.3007058,0,0,-0.953717)` / none | `(-2.32e-8,1.028346,-0.4325762)` / identity / none | `(0.2306155,-0.1077832,2.274507)`; `(-0.2306155,-0.1077832,2.274507)` |
| `par_m_laser` | `(0,1.039598,0.6400551)` / `(-0.3007058,0,0,-0.953717)` / `(0,-5.96e-8,-1.192e-7)` | `(0,-0.190359,-0.5231426)` / identity / `(0,0,2.384e-7)` | `(0.2562549,0.2704595,5.609009)`; `(-0.3138258,0.2704595,5.609009)` |
| `par_m_plasma` | `(0,0.8191521,0.5735763)` / `(-0.3007058,0,0,-0.953717)` / none | `(-8.42e-8,0.05871224,-0.8014987)` / `(1.808e-7,-2.3e-9,0,-1)` / `(0,-2.54e-8,0)` | `(-0.413957,-0.05976738,2.289655)`; `(0.4139574,-0.05976691,2.289655)` |
| `tel_m_beam` | `(5.066e-7,1.113813,-0.4385716)` / identity / none | `(-9.537e-7,0.3985944,-0.0718013)` / identity / `(0,2.98e-8,2.384e-7)` | `(0.7378538,0.05214825,2.724045)`; `(-0.7411804,0.05214825,2.724045)` |
| `tel_m_laser` | `(-4.619e-7,0.504442,-0.03085339)` / identity / `(0,1.192e-7,1.192e-7)` | `(-0.2250015,0.9301549,-0.001182318)` / identity / `(0,0,-1.192e-7)` | `(0.8107684,0.01269937,5.323081)`; `(-0.360766,0.01269937,5.323081)` |
| `tel_m_plasma` | `(-4.619e-7,0.5087894,-0.03085339)` / identity / `(0,2.384e-7,2.384e-7)` | `(0,0.6530152,-0.4986504)` / identity / `(0,-1.788e-7,1.192e-7)` | `(-0.5150182,0.314377,2.313589)`; `(0.5162557,0.314377,2.313589)` |
| `ter_m_laser` | `(0,1.039598,0.6400551)` / `(-0.3007058,0,0,-0.953717)` / `(0,-5.96e-8,-1.192e-7)` | `(-0.2250015,-0.1942234,-1.192e-7)` / identity / `(-1.49e-8,5.96e-8,3.576e-7)` | `(0.7535628,0.1360996,6.793119)`; `(-0.3611313,0.1360996,6.793119)` |

The near-identity quaternions and sub-micrometre part offsets are retained as
source facts rather than rounded away. The pinned converter's `Part` parser
does not preserve the nested XML part `<offset>`, so it does not independently
corroborate that sub-layer; the offsets are nevertheless explicit shipped
metadata and their total scale is immaterial to a metre-scale discriminator.
Endpoint quaternions on the Paranid plasma and Teladi beam are also near
identity; they affect endpoint orientation, not the listed endpoint origin.

## Candidate-channel facts needed for the settled pose

Let

```text
α = float32(35 × π / 180) = 0.6108652353286743
```

The exact active records are:

| path part | all seven channel-1 first-three values | records |
|---|---|---|
| `part_arm` | `(-α,-0.0,0.0)` | two identical value triples at 0 and 1/30 |
| rotator-base | `(+α,-0.0,0.0)` | two identical value triples at 0 and 1/30 |

Channel 0 is `(0,0,0)` at `anim_base`. Only the three Teladi rotator-base
parts additionally store
`(4.6193599700927734e-7, 8.195638656616211e-8,
-2.7567148208618164e-7)`; each pair again repeats the triple.

The numerical agreement with the authored hierarchy is specific:

- `α` differs from mathematical 35° in radians only by float32 rounding;
- `(0.3007058,0,0,-0.953717)` and
  `(-0.3007058,0,0,-0.953717)`, after the irrelevant whole-quaternion sign is
  normalized, encode signed principal X rotations −35° and +35°;
- only the first candidate-channel-1 coordinate is non-zero, matching that
  authored X relationship and the downstream `rotation_x` restriction;
- the arm and rotator-base values have equal magnitudes and opposite signs.

These numeric and structural relationships are `shipped-source` facts plus
ordinary quaternion arithmetic. Calling `α` radians and the three coordinates
Euler X/Y/Z is additionally corroborated by the third-party technique below.

## Third-party transform interpretation

At the pinned commit, X4Converter:

- represents each authored connection as a transformed node and its named part
  as a child node; connections whose XML `parent` names that part are then
  attached below the part node, preserving subtree propagation;
- names candidate channel 1 `rotKeys`, emits it as `rotation_euler`, and targets
  the Blender object with the exact part name rather than the connection node;
- imports each axis into the same Blender Euler axis and adds the ANI value to
  that part object's starting `rotation_euler`; therefore the separate authored
  connection rotation remains in the parent→child composition rather than
  being replaced by the ANI value;
- likewise adds candidate-channel-0 values to the part object's starting
  `location`;
- reads authored XML positions and quaternions directly, but applies
  `start - value` for ANI location X and ANI Euler X while applying
  `start + value` for ANI Y/Z.

Accordingly, accepted ANI position and rotation triples enter authored/native
geometry as:

```text
(x, y, z)_ANI-stored → (-x, y, z)_authored/native
```

The converter behavior is `third-party-technique`, not X4 proof. It gives an
exact, testable conversion and composition hypothesis; the corrected
Paranid M laser absolute-position result below independently corroborates its
material local-X rotation consequence.

## Generic settled-transform rule

For each path part, preserve the component's authored connection transform
and part transform as separate layers. Under the source-derived rule:

1. Apply the authored connection transform from the parent part to the named
   connection.
2. Convert each accepted settled ANI triple from stored coordinates to the
   authored/native convention as `(-x, y, z)`. At the child part, add the
   converted channel-0 triple to local position and the converted channel-1
   triple, in radians, to local Euler X/Y/Z rotation. Preserve any authored
   part offset at this layer. Only X is non-zero in the accepted rotation
   records, so Euler order is irrelevant for this cohort.
3. Attach the next connection below that animated part, so the ANI contribution
   moves the whole downstream subtree.
4. Apply live `rotation_y` at `part_rotator` and live `rotation_x` at
   `part_gun`, retaining those variables in native restriction convention.
5. Compose each endpoint's own authored transform separately. There is one
   shared chain and two endpoint leaves; neither endpoint may stand in for the
   other.

Writing `C_i` for the authored connection transform and `P_i*` for the child
part transform after step 2, define `L_i* = C_i · P_i*`. With `Y(ψ)` for the
`part_rotator` restriction, `X(θ)` for the `part_gun` restriction, and `E_k`
for endpoint `k`, the cohort rule is:

```text
M_k(ψ,θ) = L_anim_base* · L_part_arm* · L_rotator_base*
           · L_part_rotator* · Y(ψ)
           · L_part_gun* · X(θ) · E_k,       k ∈ {1,2}
```

This notation deliberately leaves a global runtime telemetry-sign convention
outside the fixed active-pose result. The live discriminator below instantiates
the representative from projectile bore direction rather than assuming that a
logged target-bearing sign is the joint sign.

### Representative: `turret_par_m_laser_01_mk1`

In exact path order, the fixed source inputs are:

```text
anim_base:
  connection position (0,-1.991911,2.638335)
  ANI position       (0,0,0)

part_arm:
  connection position  (0,-0.008089185,0)
  authored rotation    identity
  stored ANI Euler     (-α,0,0)
  applied native Euler (+α,0,0)

rotator-base:
  connection position  (0,0.003018975,-3.745065)
  authored rotation    X(-35°)
  part offset           (0,5.96e-8,-1.192e-7)
  stored ANI Euler      (+α,0,0)
  applied native Euler  (-α,0,0)
  active local rotation X(-35°)+X(-35°) = X(-70°)

part_rotator:
  connection position (0,1.039598,0.6400551)
  authored rotation   X(+35°)
  part offset          (0,-5.96e-8,-1.192e-7)
  restriction          rotation_y

part_gun:
  connection position (0,-0.190359,-0.5231426)
  authored rotation   identity
  part offset          (0,0,2.384e-7)
  restriction          rotation_x, -10°..89°

endpoint 1: (0.2562549,0.2704595,5.609009)
endpoint 2: (-0.3138258,0.2704595,5.609009)
```

Thus its fixed active orientation before live yaw/pitch is
`X(+35°) · X(-70°) · X(+35°) = identity`. The arm moves the downstream base
pivot and the compensated arm/base/rotator relationship restores the live
joint frame; this is mechanically coherent rather than disconnected mesh
rotations.

## Cross-component corroboration and grouping

The strongest independent source-pattern check is the authored-family split:

```text
Paranid/Terran:
  +35° applied ANI arm + (-35° authored base -35° applied ANI base)
  + 35° authored rotator = 0° net fixed X rotation

Teladi:
  +35° applied ANI arm + 0° authored base -35° applied ANI base
  + 0° authored rotator = 0° net fixed X rotation
```

Exact exported residues remain in the literal matrices, but the authored
35-degree construction is common. A replacement interpretation would instead
leave Paranid/Terran at +35° while Teladi remains at 0°, despite their identical
active ANI triples and shared topology. The converted additive interpretation therefore explains both
authored families with one rule and is the mechanically coherent
source-derived rule.

One generic algorithm covers all seven. They do **not** require separate
semantic groups. Real data differences that remain parameters of that rule are:

- component-specific connection, part, and endpoint offsets;
- Paranid/Terran compensated authored ±35° quaternions versus Teladi
  near-identity quaternions;
- the tiny Teladi rotator-base channel-0 vector;
- rotator-base part spelling;
- near-zero export residues and component-specific endpoint quaternions;
- trailing ANI control data, which splits by family but cannot affect the
  settled first-three value because both active records repeat it.

## Why settled interpolation is not required

The active selector spans frames 30–31. For every required channel-0 and
channel-1 descriptor, the two stored active records are at 0 and 1/30 and have
bit-identical first-three values. Therefore every interpolation between those
endpoints returns the same transform input. The result does not select “the
last record” as a special runtime value; it uses the constant value shared by
both stored endpoints. Transition records and their control fields are outside
the settled-pose requirement.

This does not globally establish X4's interpolation enum, control-point, or
selector-propagation semantics.

## X4 9.00 live discriminator

A controlled live run on 2026-09-04 used X4 9.00 build 611726 and the exact
Paranid representative `turret_par_m_laser_01_mk1_macro` on
`ship_par_m_trans_container_01_a_macro`. The repository base was
`22d479b6b7e1d0d3ad2470cee1e1b1ff37e449b3`; the scenario was intentionally
uncommitted Test Lab input named
`issue-83-b2-par-m-laser-channel1-discriminator-r1`.

The corrected Test Lab operational census was exactly one weapon, one ordinary
turret, and zero missile turrets. Create reached `remote_ready`; onboard Test
Lab resolved exactly one intended equipment macro and enabled observation.
Early records while the turret remained in default `attackenemies` mode are
excluded because the discriminator contract required explicit
`autoassist` / Attack my current enemy attribution. Only later `autoassist`
records whose `aimed=` object matched the selected target are used, with
correlated `HIT ... istgt=1` records for both named targets.

After training settled, repeated exact-turret `FIRED` records converged to:

| target | projectile yaw | projectile pitch | runtime `barrelposition` |
|---|---:|---:|---|
| left | about `-0.635243` | `0.643347` | `(-2.50881, 4.76001, 2.37470)` |
| right | about `+0.635244` | `0.643347` | `(2.00360, 4.76001, 2.74713)` |

Use the projectile bore directions from those same firing instants to
instantiate the variable yaw/pitch portion of each candidate. This avoids
assuming that target-relative telemetry signs are the native joint signs.
Compare right-minus-left muzzle displacement rather than absolute muzzle
position: fixed hull-mount translation cancels, and displacement magnitude is
also invariant to any fixed hull-mount rotation.

The runtime displacement is approximately:

```text
(4.5124118, 0, 0.3724348) m
|Δ| = 4.5277553 m
```

For authored endpoint 2, the additive source rule predicts:

```text
(4.5124173, 0, 0.3724296) m
|Δ| = 4.5277603 m
```

The vector residual is about `7.6e-6 m`; the magnitude residual is about
`5.0e-6 m`.

The replacement control treats the same active channel-1 values as replacing
the authored rotations, leaving the Paranid fixed frame at +35° as described
above. For each observed projectile bore direction, solve that control's two
live joint rotations to reproduce the bore direction before evaluating the
muzzle. It predicts approximately:

```text
(3.9155441, -0.3358029, 0.4795738) m
|Δ| = 3.9590706 m
```

That is about `0.6931763 m` vector error and `0.5686847 m` magnitude error.
The conclusion is not dependent on choosing endpoint 2 after the fact: using
endpoint 1 or the endpoint midpoint still leaves the additive displacement
magnitude within about `0.0051 m` or `0.0152 m` respectively, while the
replacement controls miss by about `0.5831 m` or `0.6118 m`.

The live discriminator therefore selects additive local-X channel-1
composition and rejects the replacement interpretation for this exact Paranid
rank-2 representative. Because both the old raw-X composition and the corrected
ANI-X conversion leave the net pre-joint orientation at identity, this
right-minus-left displacement test did not materially discriminate their fixed
upstream translation.

Re-evaluating the same B2 session out of sample with the corrected absolute
source chain gives endpoint-2 position errors of approximately `6.11e-6 m`
and `5.95e-6 m` for the left and right samples respectively.

## X4 9.00 nine-pose absolute-position validation

A separate captured B4 run on X4 9.00 build 611726 exercised the exact
`turret_par_m_laser_01_mk1_macro` representative at nine materially distinct
poses. Each pose had a settled runtime `barrelposition`, a later exact-turret
firing record that returned to that position within the accepted sampling
contract, and correlated target-hit evidence. The corrected source chain was
instantiated from the corresponding projectile bore direction; no runtime
constant was fitted.

Before correcting the ANI-X convention, runtime minus source prediction was a
nearly pose-invariant approximately `(0, +4.296162, +0.003464) m`. Shipped
source explains that residual directly:

```text
[Rx(+35°) - Rx(-35°)] * (0, 0.003018975, -3.745065)
  ≈ (0, +4.296162073, +0.003463226) m
```

With stored ANI triples converted as `(-x, y, z)`, the nine corrected
endpoint-2 errors are:

| pose | error (m) |
|---|---:|
| center | `0.0000070` |
| yaw right | `0.0000069` |
| yaw left | `0.0000108` |
| pitch low | `0.0000064` |
| pitch high | `0.0000147` |
| right low | `0.0000033` |
| right high | `0.0000157` |
| left low | `0.0000073` |
| left high | `0.0000125` |

The observed range is approximately `3.3e-6..1.57e-5 m`, far below the
`0.5 m` validation cap. This completes the absolute-position validation for
the exact rank-2 representative.

## Decision and proof boundary

**SOURCE-SEMANTICS RESOLVED; REPRESENTATIVE NINE-POSE ABSOLUTE-POSITION
VALIDATION PASSED.**

The shipped hierarchy/numeric construction and pinned converter converge on
one exact source rule for all seven components: accepted ANI position and
rotation triples are normalized to `(-x, y, z)` before additive local
composition with authored geometry. X4 9.00 selected additive channel-1
composition over replacement in B2, and the corrected rule then reproduced all
nine captured B4 absolute endpoint-2 positions to approximately
`3.3e-6..1.57e-5 m` without a fitted runtime constant.

The ANI channel-0 X conversion is converter-backed but not materially
live-discriminated: resolved channel-0 X values in this cohort are zero or
microscopic. The material B4 correction is the nonzero channel-1 Euler X
conversion. Nonzero Euler Y/Z and Euler order remain unproved and must fail
closed.

Not established here:

- general channel-1 semantics outside this exact topology and settled state;
- nonzero channel-0 X behavior beyond the converter-backed conversion rule;
- nonzero Euler Y/Z or Euler order;
- transition interpolation/control semantics;
- a global runtime yaw/pitch telemetry-sign convention;
- runtime validation of every component-specific offset/endpoint set in the
  seven-member cohort.

## Evidence records

### Authored hierarchy and stored active values

- X4: 9.00
- Status: shipped-source
- Source: the seven component XML/ANI resource pairs listed by the three
  preceding rank-2 references; direct cache re-parse on 2026-09-02
- Live test: no
- Finding: exact path, selectors, restrictions, transforms, endpoints, active
  record identities, and cross-component differences recorded above.

### Channel-1 additive local-Euler interpretation

- X4: technique applied to X4 assets; not engine proof
- Status: third-party-technique
- Source: X4Converter commit
  `0be4b494089ba7719d4c5d351e63160ef3843ef5`, `AnimDesc.*` and
  `X4ConverterBlenderAddon/importer.py`
- Live test: no
- Finding: candidate channel 1 is mapped to Euler rotation and added to the
  starting local rotation. Authored XML transforms are read directly, while
  ANI position and Euler X use `start - value`; accepted ANI triples therefore
  enter authored/native geometry as `(-x, y, z)`.

### Cohort transform synthesis

- X4: 9.00
- Status: inference
- Source: shipped-source hierarchy/numeric agreement plus the pinned
  third-party transform technique
- Live test: representative runtime corroboration recorded separately below
- Finding: converted additive local channel-1 rotations produce one
  mechanically coherent fixed active orientation and one generic transform
  rule across all seven; replacement creates an unexplained authored-family
  split.

### Paranid M laser additive channel-1 composition

- X4: 9.00 build 611726
- Status: live-tested
- Source: owner-captured `debug.log`, 2026-09-04, scenario
  `issue-83-b2-par-m-laser-channel1-discriminator-r1`; exact source transforms
  and endpoints recorded above
- Live test: yes — repository base
  `22d479b6b7e1d0d3ad2470cee1e1b1ff37e449b3` plus uncommitted fixture-only
  scenario input
- Finding: corrected setup reached remote READY and exact single-turret
  activation; after excluding pre-`autoassist` records, both intended targets
  produced attributable exact-turret FIRED/HIT evidence. The settled
  right-minus-left runtime muzzle displacement was within about `7.6e-6 m` of
  the additive endpoint-2 prediction, while the replacement control was about
  `0.693 m` away. Additive local-X channel-1 composition is therefore
  independently corroborated for this exact rank-2 representative. Corrected
  absolute-source re-evaluation gives left/right endpoint-2 errors of about
  `6.11e-6 m` and `5.95e-6 m`.

### Paranid M laser corrected nine-pose absolute positions

- X4: 9.00 build 611726
- Status: live-tested
- Source: owner-captured B4 rank-2 nine-pose `debug.log`, 2026-09-05,
  scenario `issue-83-b4-rank2-nine-pose-r1`; shipped component and hull-mount
  transforms;
  accepted implementation SHA `ed25ee0bcf527afa5d8034254ef4625e1c3da7ee`
- Live test: yes — nine settled poses with exact-turret firing and correlated
  hit evidence, re-evaluated from projectile bore directions
- Finding: after converting stored ANI triples to authored/native
  `(-x, y, z)`, endpoint-2 absolute errors are approximately
  `3.3e-6..1.57e-5 m` with no fitted runtime constant. The former fixed
  residual is exactly explained, to logged precision, by the source-only
  rotation-difference calculation recorded above.

### Official tooling availability

- X4: 9.00
- Status: documented-public
- Source: `https://www.egosoft.com/download/x4/bonus_en.php?list=190`, accessed
  2026-09-02 while logged out
- Live test: no
- Finding: availability/version only — Egosoft lists Blender Mod Tools 0.7.0
  for X4 9.00 and above, but the package is login/game-registration restricted.
  No public official source checked in this pass specified the binary ANI
  composition semantics.
