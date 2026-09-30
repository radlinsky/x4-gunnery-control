# Rank-2 turret `turret_active` candidate-channel-1 `part_arm` records (X4 9.00)

Follow-up to
[turret-rank2-channel0-records.md](turret-rank2-channel0-records.md), which
recorded the muzzle-path `turret_active` descriptor set of the seven rank-2
components and the stored bytes of every populated candidate-channel-0 record.
This reference records the **stored bytes** of the candidate-channel-1 records
of the single `part_arm` `turret_active` descriptor in those same seven
components. The rotator-base candidate-channel-1 records are **not** recorded
here and are deliberately left open.

## Data source and scope

- ANI files: the same seven files under
  `.x4-research-cache/issue72-a2-ani-resources/` that the channel-0 pass
  cross-checked against the schema-25 census
  (`.x4-research-cache/issue72-a3-topology-priorities-census.json`, untracked)
  — `base/assets/props/WeaponSystems/{energy,standard,heavy}/` for the six
  base-game components and
  `ego_dlc_terran/assets/props/weaponsystems/standard/` for
  `turret_ter_m_laser_01_mk1`.
- Parsing: `scripts/census_ani_parser.py`. Its strict framing held for all
  seven files (16-byte header, version 1, 160-byte descriptors with zero
  reserved fields, 128-byte key records, no duplicate descriptors, and the
  descriptor channel counts consuming the file byte-exactly with nothing left
  over).
- Method cross-check: this pass re-read the published channel-0 anchors —
  the `(anim_base, turret_active)` records 4 and 5 and their file byte
  offsets — and they match
  `turret-rank2-channel0-records.md` in all seven files.
- This research ran at repository starting SHA
  `7248530ba54b917d05fe85eb4ada2f42eff69bc8`.
- Scope: **only** the candidate-channel-1 records of the
  `(part_arm, turret_active)` descriptor, one such descriptor per file.
  Candidate channel 1 is the second of the five candidate channels; the
  X4Converter third-party technique names that count field `NumRotKeys` and
  that record vector `rotKeys`. That naming is a `third-party-technique`
  lead only and is not an X4 semantic.
- No runtime observations. No ANI channel or stored-number meanings are
  asserted; see Evidence classification.

## Recorded descriptor and record locations

Uniform across all seven components: descriptor index 10 in the ANI
descriptor table, descriptor `(part_arm, turret_active)`, key-count family
`[0,2,0,0,0]` — zero records in candidate channels 0 and 2–4 and two records
in candidate channel 1. Record indices are 0-based global key-record indices;
byte offsets are file byte offsets of the 128-byte record start.

| Component | ANI file (cache-relative) | File size (bytes) | Record indices | Byte offsets |
|---|---|---|---|---|
| `turret_par_m_beam_01_mk1` | `base/assets/props/WeaponSystems/energy/TURRET_PAR_M_BEAM_01_MK1_DATA.ANI` | 13456 | 28, 29 | 8720, 8848 |
| `turret_par_m_laser_01_mk1` | `base/assets/props/WeaponSystems/standard/TURRET_PAR_M_LASER_01_MK1_DATA.ANI` | 14128 | 28, 29 | 9520, 9648 |
| `turret_par_m_plasma_01_mk1` | `base/assets/props/WeaponSystems/heavy/TURRET_PAR_M_PLASMA_01_MK1_DATA.ANI` | 15152 | 28, 29 | 9520, 9648 |
| `turret_tel_m_beam_01_mk1` | `base/assets/props/WeaponSystems/energy/TURRET_TEL_M_BEAM_01_MK1_DATA.ANI` | 17552 | 32, 33 | 11152, 11280 |
| `turret_tel_m_laser_01_mk1` | `base/assets/props/WeaponSystems/standard/TURRET_TEL_M_LASER_01_MK1_DATA.ANI` | 18352 | 32, 33 | 11312, 11440 |
| `turret_tel_m_plasma_01_mk1` | `base/assets/props/WeaponSystems/heavy/TURRET_TEL_M_PLASMA_01_MK1_DATA.ANI` | 17840 | 32, 33 | 10672, 10800 |
| `turret_ter_m_laser_01_mk1` | `ego_dlc_terran/assets/props/weaponsystems/standard/TURRET_TER_M_LASER_01_MK1_DATA.ANI` | 14256 | 22, 23 | 9392, 9520 |

In storage order the first record of each pair carries slots 3–5 =
`0x00000005,0x00000005,0x00000005` and slot 024 = `0x00000000` (0.0); the
second carries `0x00000001` ×3 and slot 024 = `0x3d088880`
(float32 0.03333330154418945 = 1/30) — the same two-record skeleton the
channel-0 records showed.

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
| slot_000 | `0xbf1c61aa` | −0.6108652353286743 |
| slot_004 | `0x80000000` | −0.0 |
| slot_008 | `0x00000000` | 0.0 |

So the first-three values are bit-identical between the two records of every
component's pair, and also bit-identical across components.

### First stored record (all seven components)

Slots 3–5 (identical in all seven): `slot_012` = `0x00000005` (5),
`slot_016` = `0x00000005` (5), `slot_020` = `0x00000005` (5). Slot 024
(identical in all seven): `0x00000000` (float32 0.0).

Remaining slots with non-zero raw 32-bit bit patterns of the first stored record, by component family
(`par` = the three `turret_par_m_*` components, mutually bit-identical;
`tel` = the three `turret_tel_m_*` components, mutually bit-identical;
`ter` = `turret_ter_m_laser_01_mk1` alone):

| slot | par ×3 bits | par ×3 float32 | tel ×3 bits | tel ×3 float32 | ter bits | ter float32 |
|---|---|---|---|---|---|---|
| slot_028 | `0x3c360b80` | 0.011111140251159668 | `0x3c360b80` | 0.011111140251159668 | `0x3c360b80` | 0.011111140251159668 |
| slot_032 | `0xbf1c61aa` | −0.6108652353286743 | `0xbf1c61ac` | −0.6108653545379639 | `0xbf1c61aa` | −0.6108652353286743 |
| slot_036 | `0xbe82d82c` | −0.25555551052093506 | `0xbe9f49f4` | −0.31111109256744385 | `0xbe9f49f4` | −0.31111109256744385 |
| slot_040 | `0xbf1c61aa` | −0.6108652353286743 | `0xbf1c61ac` | −0.6108653545379639 | `0xbf1c61aa` | −0.6108652353286743 |
| slot_044 | `0x3c360b80` | 0.011111140251159668 | `0x3c360b80` | 0.011111140251159668 | `0x3c360b80` | 0.011111140251159668 |
| slot_048 | `0x80000000` | −0.0 | `0x80000000` | −0.0 | `0x80000000` | −0.0 |
| slot_052 | `0xbe82d82c` | −0.25555551052093506 | `0xbe9f49f4` | −0.31111109256744385 | `0xbe9f49f4` | −0.31111109256744385 |
| slot_056 | `0x80000000` | −0.0 | `0x80000000` | −0.0 | `0x80000000` | −0.0 |
| slot_060 | `0x3c360b80` | 0.011111140251159668 | `0x3c360b80` | 0.011111140251159668 | `0x3c360b80` | 0.011111140251159668 |
| slot_068 | `0xbe82d82c` | −0.25555551052093506 | `0xbe9f49f4` | −0.31111109256744385 | `0xbe9f49f4` | −0.31111109256744385 |

Every other slot of the first stored record is `0x00000000`, including
slot_064 and slots slot_072 through slot_124.

### Second stored record (all seven components)

Slots 3–5 (identical in all seven): `slot_012` = `0x00000001` (1),
`slot_016` = `0x00000001` (1), `slot_020` = `0x00000001` (1). Slot 024
(identical in all seven): `0x3d088880` (float32 0.03333330154418945 = 1/30).

Remaining slots with non-zero raw 32-bit bit patterns of the second stored record, by component family
(the `par` ×3 records and the `ter` record are mutually bit-identical for
this record; the `tel` ×3 records are mutually bit-identical):

| slot | par ×3 + ter bits | par ×3 + ter float32 | tel ×3 bits | tel ×3 float32 |
|---|---|---|---|---|
| slot_028 | `0x3e7a4fa0` | 0.2444443702697754 | `0x3e7a4fa0` | 0.2444443702697754 |
| slot_032 | `0xbf1c61aa` | −0.6108652353286743 | `0xbf1c61ac` | −0.6108653545379639 |
| slot_036 | `0x3cb60b40` | 0.022222161293029785 | `0x3cb60b40` | 0.022222161293029785 |
| slot_040 | `0xbf1c61aa` | −0.6108652353286743 | `0xbf1c61ac` | −0.6108653545379639 |
| slot_044 | `0x3e7a4fa0` | 0.2444443702697754 | `0x3e7a4fa0` | 0.2444443702697754 |
| slot_048 | `0x80000000` | −0.0 | `0x80000000` | −0.0 |
| slot_052 | `0x3cb60b40` | 0.022222161293029785 | `0x3cb60b40` | 0.022222161293029785 |
| slot_056 | `0x80000000` | −0.0 | `0x80000000` | −0.0 |
| slot_060 | `0x3e7a4fa0` | 0.2444443702697754 | `0x3e7a4fa0` | 0.2444443702697754 |
| slot_068 | `0x3cb60b40` | 0.022222161293029785 | `0x3cb60b40` | 0.022222161293029785 |

Every other slot of the second stored record is `0x00000000`, including
slot_064 and slots slot_072 through slot_124.

## Bit-identity statements

1. **Within each pair**: the first three values (`slot_000`, `slot_004`,
   `slot_008`) are bit-identical between the two stored records, in every one
   of the seven components.
2. **Across components, whole first stored record**: three distinct
   128-byte values. The `par` trio (`turret_par_m_beam_01_mk1`,
   `turret_par_m_laser_01_mk1`, `turret_par_m_plasma_01_mk1`) is mutually
   bit-identical; the `tel` trio (`turret_tel_m_beam_01_mk1`,
   `turret_tel_m_laser_01_mk1`, `turret_tel_m_plasma_01_mk1`) is mutually
   bit-identical; `turret_ter_m_laser_01_mk1` forms its own third value,
   combining the `par` bits of slot_032/slot_040 with the `tel` bits of
   slot_036/slot_052/slot_068.
3. **Across components, whole second stored record**: two distinct
   128-byte values. The `par` trio **and** `turret_ter_m_laser_01_mk1` are
   mutually bit-identical; the `tel` trio share the other value.
4. **Complete 2-record pairs**: a component's full pair (both 128-byte
   records) is bit-identical to another component's pair exactly within the
   `par` trio and exactly within the `tel` trio.
   `turret_ter_m_laser_01_mk1`'s pair is not bit-identical to any other
   component's pair: its second record equals the `par` second record, but
   its first record differs from the `par` first record in slot_036,
   slot_052, and slot_068 (`0xbe9f49f4` vs `0xbe82d82c`).
5. **Within each pair, which slots differ**: in every component the two
   records differ exactly in slots 012, 016, 020, 024, 028, 036, 044, 052,
   060, and 068. Slots 032 and 040 keep one value across the whole pair in
   each component.

## Observations about the stored data (no semantics)

1. Unlike the rank-2 channel-0 records — all of which have zero in every
   slot from slot 7 onward — every candidate-channel-1 `part_arm` record here
   carries ten slots with non-zero raw 32-bit bit patterns in the byte
   28–68 region. `slot_048` and `slot_056` (`0x80000000`) decode as
   float32 −0.0 and are numerically zero; the other eight decode to
   numerically non-zero float values.
2. The two records differ exactly in slots 012, 016, 020, 024, 028,
   036, 044, 052, 060, and 068; every other slot is bit-identical
   across the pair. Any reading that selects between the two records
   (for example by slot 024) selects between the trailing slot values
   as well. No meaning for that selection is asserted.
3. The first-three values of all seven components are the identical triple
   (`0xbf1c61aa`, `0x80000000`, `0x00000000`); all cross-component variation
   in this descriptor's channel-1 records lives in slots 032, 036, 040, 052,
   and 068.
4. No candidate-channel-1 semantic is asserted, and none of the stored
   patterns is interpreted as rotation, angle, position, or any other X4
   runtime quantity.

## Evidence classification

- **Shipped source**: the file sizes, descriptor index, key-count family,
  global record indices, file byte offsets, all stored bit patterns, the
  zero-slot statements, and every bit-identity statement above.
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
  stored numbers would have under any such reading, and any composition order
  with the channel-0 records or other descriptors. Nothing in this record
  upgrades to a semantic claim.
