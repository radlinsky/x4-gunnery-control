# Rank-1 turret `turret_active` animation-data profiles (X4 9.00)

Follow-up to the Issue #72 A3 topology inventory
([turret-topology-priorities.md](turret-topology-priorities.md)). That inventory
grouped the 92 COMBAT_CANDIDATE macros by **selector-selected** descriptors
only; rank 1 (21 macros / 20 components) was defined by every selected
descriptor storing no ANI key records in any candidate channel (all-zero
key-count families). This reference asks the next structural question: when the
**full** set of muzzle-path `turret_active` descriptors with same-name selector
coverage is counted, do the rank-1 components share one animation-data pattern
or does the group split?

**Result: rank 1 splits.** The 20 components form **9 distinct descriptor
profiles** under the full six-field record (the split is unchanged when the
descriptor index is dropped, and persists — 4 patterns — even under the
coarsest key-family-only projection). `turret_par_l_beam_01_mk1` (the internal
macro the project calls **Paranid L Beam**, equipment macro
`turret_par_l_beam_01_mk1_macro`) sits in a 3-component profile with
`turret_par_l_laser_01_mk1` and `turret_par_l_plasma_01_mk1`; the other 17
rank-1 components do not share that profile.

## Data source and scope

- Report: `.x4-research-cache/issue72-a3-topology-priorities-census.json`
  (untracked, schema 25), the existing census recorded in
  `turret-topology-priorities.md` over the verified X4 9.00 official source
  sets (base plus the seven official extension sets). The report existed, so
  no census rerun was performed.
- This research ran at repository starting SHA
  `d3149a081e38cd5d3928d89f8e2c596503417f6f`; the census report itself was
  generated at repository starting SHA `9397d1b3de719a5c1baf1eba174facce1380f7bd`.
- Scope: **only** the 20 rank-1 components. Ranks 2–38 are not analyzed here.
  No ANI channel or stored-number meanings are researched here.

## Recorded descriptor set (per component)

For each rank-1 component, the recorded set is every literal `turret_active`
ANI descriptor (exact, case-sensitive subname) that satisfies both:

1. **Muzzle endpoint path membership** — the descriptor's source connection lies
   on the root-to-endpoint connection path of at least one of the component's
   firing endpoints, and
2. **Same-name selector coverage** — an exact same-name authored animation
   selector occurs on the descriptor's own source connection (relation
   `same_connection`) or on a strict ancestor connection (relation
   `strict_ancestor_distance_N`, where N is the ancestor edge distance).

Per descriptor, the recorded fields are:

| Field | Meaning in this record |
|---|---|
| descriptor index | position of the descriptor in the component's ANI descriptor table |
| part | the descriptor's authored part identity |
| source connection | the component connection that owns the descriptor |
| same-connection vs ancestor | `same_connection`, or `strict_ancestor_distance_N` (nearest same-name ancestor distance) |
| key-count family | `[c0, c1, c2, c3, c4]`, the stored ANI key-record counts in candidate channels 0–4 |
| muzzle endpoint membership count | how many of the component's firing endpoints have the descriptor's source connection on their path |

A component's **descriptor profile** is its multiset of these six-field
records, ordered by descriptor index. Two components share a profile only if
every recorded field of every one of their four descriptors matches exactly.

Completeness check across the 20 rank-1 components:

- Each component stores 5–7 literal `turret_active` descriptors in its ANI
  file; exactly **4 per component (80 total)** meet both conditions above, and
  every recorded descriptor has muzzle endpoint membership count 2 (both
  firing endpoints).
- The remaining 1–3 descriptors per component are all **off** every muzzle
  endpoint path (parts such as `anim_lights`, `fx_barrel_decal`,
  `fx_gun_decals`, `part_cover_L`/`part_cover_R`, `part_connector`,
  `detail_xl_damper`, `detail_m_rotator`), so they are not profile members by
  condition 1.
- **No** on-path `turret_active` descriptor of any rank-1 component lacks
  same-name selector coverage; condition 2 excluded nothing. The recorded set
  is therefore complete for the stated filter.

## Rank-1 macro/component totals

- **21 macros over 20 unique components.** `turret_xen_m_laser_02_mk1` backs
  two of the macros (`turret_xen_m_beam_02_mk1_macro` and
  `turret_xen_m_laser_02_mk1_macro`, per the census macro→component
  classifications); every other rank-1 component backs exactly one macro.
- Every rank-1 component has 2 firing endpoints, source-part path depth 4, and
  all-zero key-count families for its selector-selected descriptors — the
  structural signature of topology rank 1.

## The 9 profiles

All 20 profiles begin with one identical same-connection descriptor — index 2,
part `part_socket`, source connection `Connection01`, relation
`same_connection`, family `[0, 0, 0, 0, 0]`, membership 2. Under the census
selector-selection rule (exact same-name selector on the same source
connection), that descriptor is the component's selector-selected
`turret_active` descriptor; it is the only one of the four in rank 1 that is
selector-selected, and it stores no ANI key records. The three
strict-ancestor descriptors differ between profiles; their parts and stored
key-counts are the content of the split. Profiles are listed largest first,
ties broken alphabetically; every row also has muzzle endpoint membership 2.

### P1 — Paranid L Beam profile (3 components)

`**turret_par_l_beam_01_mk1**` (Paranid L Beam), `turret_par_l_laser_01_mk1`,
`turret_par_l_plasma_01_mk1`

| idx | part | source connection | relation | key-count family |
|---|---|---|---|---|
| 2 | `part_socket` | `Connection01` | `same_connection` | `[0, 0, 0, 0, 0]` |
| 12 | `part_rotator` | `Connection03` | `strict_ancestor_distance_1` | `[2, 0, 0, 0, 0]` |
| 17 | `anim_gun` | `Connection04` | `strict_ancestor_distance_2` | `[0, 0, 0, 0, 0]` |
| 22 | `anim_barrel` | `Connection05` | `strict_ancestor_distance_3` | `[2, 0, 0, 0, 0]` |

This is the pattern that motivated the check: besides the all-zero
selector-selected descriptor, two on-path `turret_active` descriptors store
keys — the rotator and the barrel parts, each `[2, 0, 0, 0, 0]`.

### P2 — (3 components)

`turret_arg_m_beam_02_mk1`, `turret_par_m_beam_02_mk1`, `turret_tel_m_beam_02_mk1`

| idx | part | source connection | relation | key-count family |
|---|---|---|---|---|
| 2 | `part_socket` | `Connection01` | `same_connection` | `[0, 0, 0, 0, 0]` |
| 12 | `detail_xl_rotator` | `Connection03` | `strict_ancestor_distance_1` | `[2, 0, 0, 0, 0]` |
| 17 | `detail_xl_gun` | `Connection04` | `strict_ancestor_distance_2` | `[0, 0, 0, 0, 0]` |
| 22 | `detail_xl_barrel` | `Connection05` | `strict_ancestor_distance_3` | `[1, 2, 2, 0, 0]` |

### P3 — (3 components)

`turret_arg_m_laser_02_mk1`, `turret_par_m_laser_02_mk1`, `turret_tel_m_laser_02_mk1`

| idx | part | source connection | relation | key-count family |
|---|---|---|---|---|
| 2 | `part_socket` | `Connection01` | `same_connection` | `[0, 0, 0, 0, 0]` |
| 7 | `part_rotator` | `Connection02` | `strict_ancestor_distance_1` | `[2, 0, 0, 0, 0]` |
| 12 | `part_gun` | `Connection03` | `strict_ancestor_distance_2` | `[0, 0, 0, 0, 0]` |
| 17 | `part_barrel` | `Connection04` | `strict_ancestor_distance_3` | `[1, 0, 0, 0, 0]` |

### P4 — (3 components)

`turret_par_m_plasma_02_mk1`, `turret_tel_m_plasma_02_mk1`, `turret_xen_m_laser_02_mk1`

| idx | part | source connection | relation | key-count family |
|---|---|---|---|---|
| 2 | `part_socket` | `Connection01` | `same_connection` | `[0, 0, 0, 0, 0]` |
| 12 | `part_rotator` | `Connection03` | `strict_ancestor_distance_1` | `[2, 0, 0, 0, 0]` |
| 17 | `part_gun` | `Connection04` | `strict_ancestor_distance_2` | `[0, 0, 0, 0, 0]` |
| 22 | `part_barrel` | `Connection05` | `strict_ancestor_distance_3` | `[1, 0, 0, 0, 0]` |

### P5 — (3 components)

`turret_spl_l_beam_01_mk1`, `turret_spl_l_laser_01_mk1`, `turret_spl_l_plasma_01_mk1`

| idx | part | source connection | relation | key-count family |
|---|---|---|---|---|
| 2 | `part_socket` | `Connection01` | `same_connection` | `[0, 0, 0, 0, 0]` |
| 7 | `part_rotator` | `Connection02` | `strict_ancestor_distance_1` | `[0, 0, 0, 0, 0]` |
| 12 | `part_gun` | `Connection03` | `strict_ancestor_distance_2` | `[2, 0, 0, 0, 0]` |
| 17 | `part_barrel` | `Connection04` | `strict_ancestor_distance_3` | `[2, 0, 0, 0, 0]` |

### P6 — (2 components)

`turret_pir_l_battleship_01_laser_01_mk1`, `turret_tel_l_laser_01_mk1`

| idx | part | source connection | relation | key-count family |
|---|---|---|---|---|
| 2 | `part_socket` | `Connection01` | `same_connection` | `[0, 0, 0, 0, 0]` |
| 12 | `part_rotator` | `Connection03` | `strict_ancestor_distance_1` | `[0, 0, 0, 0, 0]` |
| 27 | `part_gun` | `Connection06` | `strict_ancestor_distance_2` | `[2, 2, 2, 0, 0]` |
| 32 | `part_barrel` | `Connection07` | `strict_ancestor_distance_3` | `[2, 0, 0, 0, 0]` |

### P7 — (1 component)

`turret_arg_m_plasma_02_mk1`

| idx | part | source connection | relation | key-count family |
|---|---|---|---|---|
| 2 | `part_socket` | `Connection01` | `same_connection` | `[0, 0, 0, 0, 0]` |
| 12 | `part_rotator` | `Connection03` | `strict_ancestor_distance_1` | `[2, 0, 0, 0, 0]` |
| 17 | `part_gun` | `Connection04` | `strict_ancestor_distance_2` | `[0, 0, 0, 0, 0]` |
| 27 | `part_barrel` | `Connection06` | `strict_ancestor_distance_3` | `[1, 0, 0, 0, 0]` |

### P8 — (1 component)

`turret_ter_l_beam_01_mk1`

| idx | part | source connection | relation | key-count family |
|---|---|---|---|---|
| 2 | `part_socket` | `Connection01` | `same_connection` | `[0, 0, 0, 0, 0]` |
| 7 | `part_rotator` | `Connection02` | `strict_ancestor_distance_1` | `[2, 0, 0, 0, 0]` |
| 17 | `anim_gun` | `Connection04` | `strict_ancestor_distance_2` | `[0, 0, 0, 0, 0]` |
| 22 | `anim_barrel` | `Connection05` | `strict_ancestor_distance_3` | `[2, 0, 0, 0, 0]` |

### P9 — (1 component)

`turret_ter_l_laser_01_mk1`

| idx | part | source connection | relation | key-count family |
|---|---|---|---|---|
| 2 | `part_socket` | `Connection01` | `same_connection` | `[0, 0, 0, 0, 0]` |
| 7 | `part_rotator` | `Connection02` | `strict_ancestor_distance_1` | `[2, 0, 0, 0, 0]` |
| 12 | `part_gun` | `Connection03` | `strict_ancestor_distance_2` | `[0, 0, 0, 0, 0]` |
| 17 | `anim_barrel` | `Connection04` | `strict_ancestor_distance_3` | `[2, 0, 0, 0, 0]` |

## Projection note

- Grouping by the full six-field record and by the same record with the
  descriptor index dropped give the **same 9-way partition**; descriptor
  indexes differ between components exactly where parts, connections, or
  key-count families differ.
- The coarsest projection — multiset of key-count families only, ignoring
  parts, connections, relations, and indexes — still yields **4** distinct
  patterns: `[0,0,0,0,0]×2 + [2,0,0,0,0]×2` (P1, P5, P8, P9 members; 8
  components), `[0,0,0,0,0]×2 + [2,0,0,0,0] + [1,0,0,0,0]` (P3, P4, P7
  members; 7 components), `[0,0,0,0,0]×2 + [2,0,0,0,0] + [1,2,2,0,0]` (P2; 3
  components), and `[0,0,0,0,0]×3 + [2,2,2,0,0] + [2,0,0,0,0]` (P6; 2
  components). The conclusion "rank 1 splits" does not depend on how finely
  the profile is defined.

## Boundaries

- **Evidence classification:** stored identities and counts (component, macro,
  and macro→component mapping, part, connection, descriptor index,
  key-count families, membership counts) are **shipped-source**; the
  same-name selector relationships (`same_connection`,
  `strict_ancestor_distance_N`) are **inference** from shipped source
  structure.
- **Semantic claim: none.** No meaning is assigned to any ANI candidate
  channel or stored number.
- This inventory does **not** prove runtime animation propagation from a
  same-name ancestor selector to a descriptor, does **not** prove any
  `turret_active` runtime behavior, and assigns no transform, order, frame,
  axis, pivot, or timing semantics. Structural same-name coverage is a source
  fact, not a runtime proof.
- Ranks 2–38 are out of scope; no ANI semantic research was performed here.

## Evidence record

### Stored identities, counts, and profile membership

- X4: 9.00
- Status: shipped-source
- Source: `.x4-research-cache/issue72-a3-topology-priorities-census.json`
  (schema-25 census over the verified X4 9.00 official source sets under
  `.x4-research-cache/`; report untracked)
- Live test: no — offline source verification only, as of 2026-09-01
- Finding: the 20 rank-1 components (21 macros) each carry exactly four
  muzzle-path `turret_active` descriptors with same-name selector coverage,
  all with muzzle endpoint membership 2; these records form 9 distinct
  component profiles rather than one shared pattern. The Paranid L Beam
  component shares its profile with the other two `par_l` components, and its
  two key-bearing on-path descriptors are the `part_rotator` and
  `anim_barrel` entries, both `[2, 0, 0, 0, 0]`. No runtime or
  channel-meaning claim is made or implied.

### Same-name selector relationships

- X4: 9.00
- Status: inference
- Source: `.x4-research-cache/issue72-a3-topology-priorities-census.json`
  (same schema-25 census; census rule: exact case-sensitive same-name match on
  the descriptor's own connection or an ancestor connection, ancestor distance
  counted along the authored connection hierarchy)
- Live test: no — offline source verification only, as of 2026-09-01
- Finding: for every rank-1 component, the one same-connection descriptor
  sits on `Connection01`, and the three strict-ancestor descriptors sit 1–3
  edges below it; no on-path `turret_active` descriptor of any rank-1 component
  lacks same-name selector coverage. Structural coverage is not runtime
  propagation.
