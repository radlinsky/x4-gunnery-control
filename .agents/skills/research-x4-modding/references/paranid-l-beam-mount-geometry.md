# Paranid L Beam mount geometry — `group_rear_down_mid` (Issue #72/#83 A3)

X4 9.00 shipped-source. The Beam turret under A3 test
(`turret_par_l_beam_01_mk1_macro`) mounts on the Paranid L destroyer
(`ship_par_l_destroyer_01_a_macro`) at connection `con_turret_laser_l_04`,
group `group_rear_down_mid`.

Source: `assets/units/size_l/ship_par_l_destroyer_01.xml`, connection
`con_turret_laser_l_04` (cache: `issue72-a1-hull-current-9.00`):

```xml
<connection name="con_turret_laser_l_04" group="group_rear_down_mid " tags="turret large standard missile  combat ">
  <offset>
    <position x="0" y="-6.897476" z="-85.76994"/>
    <quaternion qx="-0" qy="-0" qz="-1" qw="4.371139E-08"/>
  </offset>
</connection>
```

Interpretation (ship-local axes: +z forward, +y up, +x right):

- **Ventral, rear, centerline.** `z=-85.8` is well astern; `y=-6.9` is below
  center; `x=0` is on the keel line.
- The quaternion `(0, 0, -1, ~0)` is a 180° rotation about the forward (z)
  axis — a belly mount whose local "up" points down. Its clear field of fire is
  the **lower-and-astern hemisphere** (below the hull, toward the stern).

## Consequence for the A3 live discriminator

Range is not the constraint: the Beam bullet
(`bullet_par_turret_l_railgun_01_mk1_macro`) is `speed=10000 lifetime=1.4`
(~14 km) and `system="turret_longrange"`.

The Issue #72 A3 r1 fixture (`issue-72-a3-channel0-discriminator-r1`) placed
both targets **forward** (`distance=7000`, +z) and one **above** (`y=1500`).
That is the opposite hemisphere from a belly-rear turret, so the whole hull sat
between the muzzle and both targets → `muzzle_los_self=0` at both bearings and
no FIRED evidence. The r1 result is a fixture-geometry artifact, **not**
evidence about channel-0 semantics (see
[paranid-l-beam-channel0-semantics.md](paranid-l-beam-channel0-semantics.md)).

A valid replacement must place targets **below and astern** (−y, −z) in the
turret's actual field of fire, in range (< ~14 km), with materially distinct
bearings, and must fail closed before firing unless the exact selected Beam has
settled self-LOS clear.
