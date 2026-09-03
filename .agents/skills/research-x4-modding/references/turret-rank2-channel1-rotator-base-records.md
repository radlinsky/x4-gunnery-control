# Rank-2 turret `turret_active` candidate-channel-1 rotator-base records (X4 9.00)

Follow-up to
[turret-rank2-channel1-part-arm-records.md](turret-rank2-channel1-part-arm-records.md),
which recorded the stored bytes of the candidate-channel-1 records of the single
`part_arm` `turret_active` descriptor in the same seven components and deliberately
left the rotator-base records open. This reference records the **stored bytes** of
the candidate-channel-1 records of the muzzle-path rotator-base `turret_active`
descriptor in those same seven rank-2 components, closing that gap.

## Data source and scope

- ANI files: the same seven files under
  `.x4-research-cache/issue72-a2-ani-resources/` that the channel-0 and `part_arm`
  passes cross-checked (`.x4-research-cache/issue72-a3-topology-priorities-census.json`,
  untracked) — `base/assets/props/WeaponSystems/{energy,standard,heavy}/` for the six
  base-game components and
  `ego_dlc_terran/assets/props/weaponsystems/standard/` for
  `turret_ter_m_laser_01_mk1`.
- Raw dump of this pass:
  `.x4-research-cache/issue72-a4-channel1-rotator-base-raw.json` (untracked).
- Parsing: `scripts/census_ani_parser.py`. Its strict framing held for all
  seven files (16-byte header, version 1, 160-byte descriptors with zero
  reserved fields, 128-byte key records, no duplicate descriptors, and the
  descriptor channel counts consuming the file byte-exactly with nothing left
  over).
- Method cross-check: this pass re-read the published anchors in all seven files
  — the channel-0 `(anim_base, turret_active)` records 4 and 5 with their file
  byte offsets, and the `part_arm` candidate-channel-1 record indices, byte
  offsets, and first-three values — and they match
  `turret-rank2-channel0-records.md` and
  `turret-rank2-channel1-part-arm-records.md`.
- This research ran at repository starting SHA
  `bab913230db65a7bc07ab1396d6f09942c80d329`.
- Scope: **only** the candidate-channel-1 records of the muzzle-path
  rotator-base `turret_active` descriptor, exactly one such descriptor per file,
  using the exact per-component part identity recorded in
  `turret-rank2-channel0-records.md` (`detail_xl_rotator_base` for the three
  `turret_par_m_*` components and `turret_tel_m_beam_01_mk1` /
  `turret_tel_m_laser_01_mk1`, `detail_xl_rotator_base_002` for
  `turret_tel_m_plasma_01_mk1`, and `rotator_base` for
  `turret_ter_m_laser_01_mk1`). Candidate channel 1 is the second of the five
  candidate channels; the X4Converter third-party technique names that count
  field `NumRotKeys` and that record vector `rotKeys`. That naming is a
  `third-party-technique` lead only and is not an X4 semantic.
- No runtime observations. No ANI channel or stored-number meanings are
  asserted; see Evidence classification.

## Recorded descriptor and record locations

Record indices are 0-based global key-record indices; byte offsets are file byte
offsets of the 128-byte record start; descriptor index is the position in the
file's descriptor table. The descriptor sub-name is `turret_active` in every
case.

| Component | ANI file (cache-relative) | File size (bytes) | Descriptor index | Descriptor part | Key-count family | Record indices | Byte offsets |
|---|---|---|---|---|---|---|---|
| `turret_par_m_beam_01_mk1` | `base/assets/props/WeaponSystems/energy/TURRET_PAR_M_BEAM_01_MK1_DATA.ANI` | 13456 | 18 | `detail_xl_rotator_base` | `[0,2,0,0,0]` | 51, 52 | 11664, 11792 |
| `turret_par_m_laser_01_mk1` | `base/assets/props/WeaponSystems/standard/TURRET_PAR_M_LASER_01_MK1_DATA.ANI` | 14128 | 18 | `detail_xl_rotator_base` | `[0,2,0,0,0]` | 51, 52 | 12464, 12592 |
| `turret_par_m_plasma_01_mk1` | `base/assets/props/WeaponSystems/heavy/TURRET_PAR_M_PLASMA_01_MK1_DATA.ANI` | 15152 | 18 | `detail_xl_rotator_base` | `[0,2,0,0,0]` | 51, 52 | 12464, 12592 |
| `turret_tel_m_beam_01_mk1` | `base/assets/props/WeaponSystems/energy/TURRET_TEL_M_BEAM_01_MK1_DATA.ANI` | 17552 | 14 | `detail_xl_rotator_base` | `[2,2,0,0,0]` | 46, 47 | 12944, 13072 |
| `turret_tel_m_laser_01_mk1` | `base/assets/props/WeaponSystems/standard/TURRET_TEL_M_LASER_01_MK1_DATA.ANI` | 18352 | 14 | `detail_xl_rotator_base` | `[2,2,0,0,0]` | 46, 47 | 13104, 13232 |
| `turret_tel_m_plasma_01_mk1` | `base/assets/props/WeaponSystems/heavy/TURRET_TEL_M_PLASMA_01_MK1_DATA.ANI` | 17840 | 14 | `detail_xl_rotator_base_002` | `[2,2,0,0,0]` | 46, 47 | 12464, 12592 |
| `turret_ter_m_laser_01_mk1` | `ego_dlc_terran/assets/props/weaponsystems/standard/TURRET_TER_M_LASER_01_MK1_DATA.ANI` | 14256 | 18 | `rotator_base` | `[0,2,0,0,0]` | 40, 41 | 11696, 11824 |

In storage order the first record of each pair carries slots 3–5 =
`0x00000005,0x00000005,0x00000005` and slot 024 = `0x00000000` (0.0); the
second carries `0x00000001` ×3 and slot 024 = `0x3d088880`
(float32 0.03333330154418945 = 1/30) — the same two-record skeleton the
channel-0 and `part_arm` records showed.

## Stored bytes

Slot ids name byte offsets inside the 128-byte record: slots 0–2 =
`slot_000`–`slot_008` (the "first three values"), slots 3–5 =
`slot_012`–`slot_020` (the per-axis enum fields), `slot_024` = the member the
X4Converter third-party technique names `Time`. Float32 decodes accompany the
raw bits for convenience; the raw bits are the shipped data.

### First three values — all seven components, both records

Bit-identical across **all seven components and both stored records**:

| slot | stored bits | float32 |
|---|---|---|
| slot_000 | `0x3f1c61aa` | 0.6108652353286743 |
| slot_004 | `0x80000000` | −0.0 |
| slot_008 | `0x00000000` | 0.0 |

So the first-three values are bit-identical between the two records of every
component's pair, and also bit-identical across components.

### First stored record (all seven components)

Slots 3–5 (identical in all seven): `slot_012` = `0x00000005` (5),
`slot_016` = `0x00000005` (5), `slot_020` = `0x00000005` (5). Slot 024
(identical in all seven): `0x00000000` (float32 0.0).

Remaining slots with non-zero raw 32-bit bit patterns of the first stored record, by component family
(the `par` trio's records and the `ter` record are mutually bit-identical for
this record; the `tel` ×3 records are mutually bit-identical):

| slot | par ×3 + ter bits | par ×3 + ter float32 | tel ×3 bits | tel ×3 float32 |
|---|---|---|---|---|
| slot_028 | `0x3c360b80` | 0.011111140251159668 | `0x3c360b80` | 0.011111140251159668 |
| slot_032 | `0x3f1c61aa` | 0.6108652353286743 | `0x3f1c61ac` | 0.6108653545379639 |
| slot_036 | `0xbe9f49f4` | −0.31111109256744385 | `0xbe9f49f4` | −0.31111109256744385 |
| slot_040 | `0x3f1c61aa` | 0.6108652353286743 | `0x3f1c61ac` | 0.6108653545379639 |
| slot_044 | `0x3c360b80` | 0.011111140251159668 | `0x3c360b80` | 0.011111140251159668 |
| slot_048 | `0xa4393033` | −4.015630670827683e-17 | `0x80000000` | −0.0 |
| slot_052 | `0xbe9f49f4` | −0.31111109256744385 | `0xbe9f49f4` | −0.31111109256744385 |
| slot_056 | `0xa4393033` | −4.015630670827683e-17 | `0x80000000` | −0.0 |
| slot_060 | `0x3c360b80` | 0.011111140251159668 | `0x3c360b80` | 0.011111140251159668 |
| slot_064 | `0x2512d5e8` | 1.2735955631180138e-16 | `0x00000000` | 0.0 |
| slot_068 | `0xbe9f49f4` | −0.31111109256744385 | `0xbe9f49f4` | −0.31111109256744385 |
| slot_072 | `0x2512d5e8` | 1.2735955631180138e-16 | `0x00000000` | 0.0 |

Every other slot of the first stored record is `0x00000000`; in particular
`slot_064` and `slot_072` are `0x00000000` in the `tel` ×3 records, and slots
`slot_076` through `slot_124` are `0x00000000` in all seven components.

### Second stored record (all seven components)

Slots 3–5 (identical in all seven): `slot_012` = `0x00000001` (1),
`slot_016` = `0x00000001` (1), `slot_020` = `0x00000001` (1). Slot 024
(identical in all seven): `0x3d088880` (float32 0.03333330154418945 = 1/30).

Remaining slots with non-zero raw 32-bit bit patterns of the second stored record, by component family
(the `par` trio's records and the `ter` record are mutually bit-identical for
this record; the `tel` ×3 records are mutually bit-identical):

| slot | par ×3 + ter bits | par ×3 + ter float32 | tel ×3 bits | tel ×3 float32 |
|---|---|---|---|---|
| slot_028 | `0x3e7a4fa0` | 0.2444443702697754 | `0x3e7a4fa0` | 0.2444443702697754 |
| slot_032 | `0x3f1c61aa` | 0.6108652353286743 | `0x3f1c61ac` | 0.6108653545379639 |
| slot_036 | `0x3cb60b40` | 0.022222161293029785 | `0x3cb60b40` | 0.022222161293029785 |
| slot_040 | `0x3f1c61aa` | 0.6108652353286743 | `0x3f1c61ac` | 0.6108653545379639 |
| slot_044 | `0x3e7a4fa0` | 0.2444443702697754 | `0x3e7a4fa0` | 0.2444443702697754 |
| slot_048 | `0xa4393033` | −4.015630670827683e-17 | `0x80000000` | −0.0 |
| slot_052 | `0x3cb60b40` | 0.022222161293029785 | `0x3cb60b40` | 0.022222161293029785 |
| slot_056 | `0xa4393033` | −4.015630670827683e-17 | `0x80000000` | −0.0 |
| slot_060 | `0x3e7a4fa0` | 0.2444443702697754 | `0x3e7a4fa0` | 0.2444443702697754 |
| slot_064 | `0x2512d5e8` | 1.2735955631180138e-16 | `0x00000000` | 0.0 |
| slot_068 | `0x3cb60b40` | 0.022222161293029785 | `0x3cb60b40` | 0.022222161293029785 |
| slot_072 | `0x2512d5e8` | 1.2735955631180138e-16 | `0x00000000` | 0.0 |

Every other slot of the second stored record is `0x00000000`; in particular
`slot_064` and `slot_072` are `0x00000000` in the `tel` ×3 records, and slots
`slot_076` through `slot_124` are `0x00000000` in all seven components.

## Bit-identity statements

1. **Within each pair**: the first three values (`slot_000`, `slot_004`,
   `slot_008`) are bit-identical between the two stored records, in every one
   of the seven components.
2. **Across components, whole first stored record**: two distinct
   128-byte values. The `par` trio (`turret_par_m_beam_01_mk1`,
   `turret_par_m_laser_01_mk1`, `turret_par_m_plasma_01_mk1`) **and**
   `turret_ter_m_laser_01_mk1` are mutually bit-identical; the `tel` trio
   (`turret_tel_m_beam_01_mk1`, `turret_tel_m_laser_01_mk1`,
   `turret_tel_m_plasma_01_mk1`) share the other value. Unlike the `part_arm`
   first record, where `ter` formed its own third value, no third value exists
   here.
3. **Across components, whole second stored record**: two distinct
   128-byte values. The `par` trio **and** `turret_ter_m_laser_01_mk1` share
   one; the `tel` trio share the other.
4. **Complete 2-record pairs**: a component's full pair (both 128-byte
   records) is bit-identical to another component's pair exactly within
   `{par ×3, ter}` and exactly within the `tel` trio; no pair is
   bit-identical across those two groups.
5. **Within each pair, which slots differ**: in every component the two
   records differ exactly in slots 012, 016, 020, 024, 028, 036, 044, 052,
   060, and 068. Slots 032 and 040 keep one value across the whole pair in
   each component.

## Observations about the stored data (no semantics)

1. `0x80000000` occurs in `slot_048` and `slot_056` of both `tel` ×3
   records: a non-zero raw bit pattern that decodes as float32 −0.0, which is
   numerically zero. The corresponding slots of the `par` ×3 + `ter` records
   hold `0xa4393033` (float32 −4.015630670827683e-17); `slot_064` and
   `slot_072` of those records hold `0x2512d5e8` (float32
   1.2735955631180138e-16) while the `tel` records hold `0x00000000` there.
2. The first-three `slot_000` bits here, `0x3f1c61aa`
   (0.6108652353286743), are the sign-bit flip of the `part_arm` first-three
   `slot_000` bits, `0xbf1c61aa` (−0.6108652353286743); the `slot_004`
   (`0x80000000`) and `slot_008` (`0x00000000`) bits match the `part_arm`
   triple. No meaning is assigned to the sign difference.
3. The two records differ in exactly the same ten slots the `part_arm`
   candidate-channel-1 pairs differed in (012, 016, 020, 024, 028, 036, 044,
   052, 060, 068), and the `par` vs `tel` split of this descriptor again lives
   in the `slot_032`/`slot_040` bit pairs (`0x3f1c61aa` vs `0x3f1c61ac`),
   `slot_048`/`slot_056`, `slot_064`/`slot_072`.
4. No candidate-channel-1 semantic is asserted, and none of the stored
   patterns is interpreted as rotation, angle, position, or any other X4
   runtime quantity.

## Evidence classification

- **Shipped source**: the file sizes, descriptor indices, descriptor part
  identities, key-count families, global record indices, file byte offsets,
  all stored bit patterns, the zero-slot statements, and every bit-identity
  statement above.
- **Third-party technique**: the five-candidate-channel ordering and the
  naming of the second channel's count/vector as `NumRotKeys`/`rotKeys`, the
  128-byte record field map (float32 at byte 0, 4, 8; enum32 at 12, 16, 20;
  float32 member named `Time` at byte 24), and every float32 decoding of a
  raw bit pattern (X4Converter, pinned in
  [paranid-l-beam-channel0-semantics.md](paranid-l-beam-channel0-semantics.md)
  and `source-registry.md`). The naming supplies a lead only; it does not
  make candidate channel 1 an X4 rotation.
- **Not established**: what candidate channel 1 means at runtime, whether the
  engine consumes these descriptors, interpolates between the two records, or
  applies slot 024 or slots 3–5 in any way, what units or axis assignments the
  stored numbers would have under any such reading, any composition order with
  the channel-0, `part_arm`, or other descriptors' records, and any meaning of
  the `slot_000` sign difference against the `part_arm` triple. Nothing in
  this record upgrades to a semantic claim.
