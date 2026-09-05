# Rank-2 turret `turret_active` candidate-channel-0 records (X4 9.00)

Follow-up to [turret-topology-priorities.md](turret-topology-priorities.md).
That inventory ranked the 38 COMBAT_CANDIDATE endpoint-topology groups; rank 2
is the **7-macro, depth-5** cohort (each component stores selected descriptors
with `[2,0,0,0,0]` families). This reference records the complete
muzzle-path `turret_active` descriptor set for those 7 components and the
**stored bytes** of every populated candidate-channel-0 record on those paths.

## Data source and scope

- Report: `.x4-research-cache/issue72-a3-topology-priorities-census.json`
  (untracked, schema 25), the existing census recorded in
  `turret-topology-priorities.md`, cross-checked descriptor-by-descriptor
  against the seven ANI files under
  `.x4-research-cache/issue72-a2-ani-resources/`
  (`base/assets/props/WeaponSystems/{energy,standard,heavy}/` and
  `ego_dlc_terran/assets/props/weaponsystems/standard/`), parsed with
  `scripts/census_ani_parser.py`.
- This research ran at repository starting SHA
  `f03e3ede96aeac9b702ca58194060ab41a1f55f0`.
- Scope: **only** the 7 rank-2 components (one component per macro):
  `turret_par_m_beam_01_mk1`, `turret_par_m_laser_01_mk1`,
  `turret_par_m_plasma_01_mk1`, `turret_tel_m_beam_01_mk1`,
  `turret_tel_m_laser_01_mk1`, `turret_tel_m_plasma_01_mk1`,
  `turret_ter_m_laser_01_mk1`. Each has 2 firing endpoints on the same 5-edge
  source path:
  `anim_base → part_arm → {rotator base part} → part_rotator → part_gun`,
  where `{rotator base part}` is `detail_xl_rotator_base` (par ×3,
  `tel_m_beam`, `tel_m_laser`), `detail_xl_rotator_base_002`
  (`tel_m_plasma`), or `rotator_base` (`ter_m_laser`).
- No runtime observations. No ANI channel or stored-number meanings are
  asserted; see Evidence classification.

## Recorded descriptor set (uniform across all 7 components)

Each component's XML authors exactly four same-name animation selectors
(`turret_inactive`, `turret_activating`, `turret_active`,
`turret_deactivating`), all on the `ConnectionForanim_base` connection
(the path edge below `anim_base`). Under the rank-1 reference's coverage
rule (descriptor's source connection on a muzzle path, plus a same-name
selector on the same connection or a strict ancestor), each component has
exactly **five** muzzle-path `turret_active` descriptors:

| Part (path edge) | Selector relation | Key-count family `[c0,c1,c2,c3,c4]` |
|---|---|---|
| `anim_base` | same connection | `[2,0,0,0,0]` |
| `part_arm` | strict ancestor, distance 1 | `[0,2,0,0,0]` |
| `{rotator base part}` | strict ancestor, distance 2 | `[2,2,0,0,0]` (3 `tel` components), `[0,2,0,0,0]` (3 `par` + `ter`) |
| `part_rotator` | strict ancestor, distance 3 | `[0,0,0,0,0]` |
| `part_gun` | strict ancestor, distance 4 | `[0,0,0,0,0]` |

These five `turret_active` descriptors are the **only** muzzle-path
`turret_active` descriptors with same-name selector coverage in the whole
rank-2 cohort, and census-vs-ANI descriptor counts matched for every
component. Every other `turret_active` descriptor in these ANI files
(`anim_barrel`, `part_barrel`, `dummy_*`, `detail_*_strut_low`, …) sits on
parts **off** the muzzle path and is not recorded as a path contribution.

## Populated candidate-channel-0 records (stored bytes)

Channel order follows the X4Converter third-party technique:
`[position, rotation, scale, pre_scale, post_scale]`; record layout
128 bytes: slots 0–2 = first-three values (float32), slots 3–5 = per-axis
enums, slot 6 (`slot_024`) = the member X4Converter names `Time` (float32),
slots 7 onward = control/flags (all zero in every record below).

Every populated path `turret_active` candidate-channel-0 record set is a
**2-record pair**; in storage order the first record carries slot 3–5 =
`0x00000005,0x00000005,0x00000005` and slot 024 = `0x00000000` (0.0), the
second carries `0x00000001` ×3 and slot 024 = `0x3d088880`
(float32 0.03333330154418945 = 1/30).

### `anim_base` (all 7 components)

Global record indices 4 and 5 (file byte offsets below). First three stored
values, both records:

| slot | stored bits | float32 |
|---|---|---|
| slot_000 | `0x00000000` | 0.0 |
| slot_004 | `0x00000000` | 0.0 |
| slot_008 | `0x00000000` | 0.0 |

- Record 4 (slot 024 = 0.0), record 5 (slot 024 = 1/30); all slots 7–31 zero.
- The 128-byte record pairs are **bit-identical across all seven ANI files**.
- File byte offsets (record 4 / record 5): `par_m_beam` 5648/5776,
  `par_m_laser` 6448/6576, `par_m_plasma` 6448/6576, `tel_m_beam` 7568/7696,
  `tel_m_laser` 7728/7856, `tel_m_plasma` 7088/7216, `ter_m_laser` 7088/7216.

### `{rotator base part}` (the 3 `tel` components only)

Global record indices 44 and 45. First three stored values, **both records**
and in all three files, bit-identical:

| slot | stored bits | float32 |
|---|---|---|
| slot_000 | `0x34f80000` | 4.6193599700927734e-07 |
| slot_004 | `0x33b00000` | 8.195638656616211e-08 |
| slot_008 | `0xb4940000` | −2.7567148208618164e-07 |

- Record 44 (slot 024 = 0.0), record 45 (slot 024 = 1/30); all slots 7–31 zero.
- File byte offsets (record 44 / record 45): `tel_m_beam` 12688/12816,
  `tel_m_laser` 12848/12976, `tel_m_plasma` 12208/12336.
- No other rank-2 path descriptor stores a candidate-channel-0 record.

## Observations about the stored data (no semantics)

1. In every descriptor recorded above, the two stored records are
   **bit-identical in the first three values**; they differ only in slots
   3–5 (`5,5,5` → `1,1,1`) and slot 024 (`0.0` → `1/30`). Any convex
   combination of the two record vectors returns the same vector, so the
   stored first-three values are constant across each descriptor's stored
   time span regardless of which record is read.
2. Consequently a literal read of the stored first-three values is well
   defined per descriptor without a time lookup; this is the same structural
   situation as the rank-1 Paranid L Beam anchor whose stored channel-0
   values were likewise constant across its two records
   (`paranid-l-beam-channel0-semantics.md`).
3. Under a channel-0-as-translation reading (that reading is **unproven**;
   see `paranid-l-beam-channel0-semantics.md`), the `turret_active` path
   contribution for all seven rank-2 components is exactly `(0,0,0)` from
   `anim_base`, plus the ~1e-7-scale vector at the `tel` rotator-base part.
   The non-zero active-pose data in these components lives in candidate
   channel 1 on `part_arm` and the rotator-base part (`[0,2,0,0,0]` /
   `[2,2,0,0,0]` families); no channel-1 semantic is asserted.

## Evidence classification

- **Shipped source**: all byte offsets, record indices, stored bit patterns,
  key-count tuples, selector connections, and the bit-identity statements.
- **Third-party technique**: the channel order
  `[position, rotation, scale, pre_scale, post_scale]`, the 128-byte record
  field map, the float32 decoding of the slots, and the member name `Time`
  for slot 024 (X4Converter, pinned in `source-registry.md`).
- **Not established**: what any candidate channel means at runtime, whether
  the engine consumes these descriptors, interpolates between the two
  records, or applies slot 024 in any way; and what slots 3–5 select.
  Nothing here upgrades to a semantic claim.
