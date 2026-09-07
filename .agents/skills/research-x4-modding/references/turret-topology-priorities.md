# Combat topology group priorities (X4 9.00)

Recorded from the accepted schema-25 combat-topology census run of 2026-09-01 over the verified
X4 9.00 official source sets (base and the seven official extension sets), Issue #72 A3.
The 92 COMBAT_CANDIDATE turret macros are grouped structurally by firing-endpoint topology and
ordered by macro coverage (descending `macro_count`, then structural signature). This inventory
freezes the actual X4 9.00 group inventory so later work can target the highest-coverage groups.

## Run identity and verification

Starting SHA of the repository under test: `9397d1b3de719a5c1baf1eba174facce1380f7bd`.
Census command (run from the repository root; all roots are the verified X4 9.00
extracted/source roots under the ignored `.x4-research-cache/`):

```bash
CACHE=.x4-research-cache
python3 scripts/census_turret_assets.py \
  --source-set base="$CACHE/issue72-a2-sources/base" \
  --source-set ego_dlc_split="$CACHE/issue72-a2-sources/ego_dlc_split" \
  --source-set ego_dlc_terran="$CACHE/issue72-a2-sources/ego_dlc_terran" \
  --source-set ego_dlc_pirate="$CACHE/issue72-a2-sources/ego_dlc_pirate" \
  --source-set ego_dlc_boron="$CACHE/issue72-a2-sources/ego_dlc_boron" \
  --source-set ego_dlc_timelines="$CACHE/issue72-a2-sources/ego_dlc_timelines" \
  --source-set ego_dlc_mini_01="$CACHE/issue72-a2-sources/ego_dlc_mini_01" \
  --source-set ego_dlc_mini_02="$CACHE/issue72-a2-sources/ego_dlc_mini_02" \
  --resource-set base="$CACHE/issue72-a2-ani-resources/base" \
  --resource-set ego_dlc_split="$CACHE/issue72-a2-ani-resources/ego_dlc_split" \
  --resource-set ego_dlc_terran="$CACHE/issue72-a2-ani-resources/ego_dlc_terran" \
  --resource-set ego_dlc_pirate="$CACHE/issue72-a2-ani-resources/ego_dlc_pirate" \
  --resource-set ego_dlc_boron="$CACHE/issue72-a2-ani-resources/ego_dlc_boron" \
  --resource-set ego_dlc_timelines="$CACHE/issue72-a2-ani-resources/ego_dlc_timelines" \
  --resource-set ego_dlc_mini_01="$CACHE/issue72-a2-ani-resources/ego_dlc_mini_01" \
  --resource-set ego_dlc_mini_02="$CACHE/issue72-a2-ani-resources/ego_dlc_mini_02" \
  --require-accepted-turret-active-changing-case-baseline \
  --output "$CACHE/issue72-a3-topology-priorities-census.json"
```

Verified from the generated report:

- `schema_version` == 25
- COMBAT_CANDIDATE macro count == 92
- topology group count == 38; per-group `macro_count` sums to 92; `unique_component_count` sums to 91
- the run passed `--require-accepted-turret-active-changing-case-baseline` (444-descriptor
  `turret_active` cohort with exactly two changing cases in each of candidate channels 0 and 1)

The generated report stays untracked at `.x4-research-cache/issue72-a3-topology-priorities-census.json`.

## Boundaries

- **Evidence classification: shipped-source.** Every group below is a structural fact about
  shipped X4 9.00 component, endpoint, and ANI key-record storage; nothing is asserted about
  runtime behavior.
- **Semantic claim: none.** Grouping uses only structural numbers: endpoint count, source-part
  path depth, and stored key-record counts per candidate channel. No ANI byte value, timing,
  axis, pivot, frame, order, or transform meaning is claimed or implied.
- **The current ordering is macro coverage only.** Groups are ranked by how many COMBAT_CANDIDATE
  macros share each structural signature. Coverage is not an importance ranking.
- **Ordinary gameplay-value prioritization remains unresolved.** Nothing in this inventory
  evaluates factions, weapons, ships, or any gameplay value, and none of the group statistics
  support one.
- **Candidate channel indexes have no assigned X4 meaning.** `nonzero_candidate_channel_indexes`
  lists only the candidate channels that contain at least one stored ANI key record in the group;
  the channels' X4 meaning is unproved (see the candidate-channel definition in
  [TURRET_ASSET_KINEMATICS.md](../../../../docs/TURRET_ASSET_KINEMATICS.md)).

## Paranid L Beam position

`turret_par_l_beam_01_mk1` (component; equipment macro `turret_par_l_beam_01_mk1_macro`) sits in
**rank 1**, the 21-macro group of two-endpoint, depth-4 conventional turrets whose selected
descriptors store no ANI key records in any candidate channel (all-zero key-count families).

## Group inventory (report order)

Per endpoint, `selected_descriptor_channel_count_tuples` are listed in stored (sorted) order;
`T ×n` means tuple `T` occurs exactly `n` times, so each list reconstructs the stored tuples
exactly. Membership lists the group's component assets in stored (sorted) order; component and
macro identities are independent (one component may back several macros).

### Rank 1 — 21 macro(s)

- `macro_count`: 21
- `unique_component_count`: 20
- `endpoint_count`: 2
- `nonzero_candidate_channel_indexes`: (none)
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[0, 0, 0, 0, 0] ×5`
  - endpoint 2: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[0, 0, 0, 0, 0] ×5`
- component membership (20): `turret_arg_m_beam_02_mk1`, `turret_arg_m_laser_02_mk1`, `turret_arg_m_plasma_02_mk1`, `turret_par_l_beam_01_mk1`, `turret_par_l_laser_01_mk1`, `turret_par_l_plasma_01_mk1`, `turret_par_m_beam_02_mk1`, `turret_par_m_laser_02_mk1`, `turret_par_m_plasma_02_mk1`, `turret_pir_l_battleship_01_laser_01_mk1`, `turret_spl_l_beam_01_mk1`, `turret_spl_l_laser_01_mk1`, `turret_spl_l_plasma_01_mk1`, `turret_tel_l_laser_01_mk1`, `turret_tel_m_beam_02_mk1`, `turret_tel_m_laser_02_mk1`, `turret_tel_m_plasma_02_mk1`, `turret_ter_l_beam_01_mk1`, `turret_ter_l_laser_01_mk1`, `turret_xen_m_laser_02_mk1`

### Rank 2 — 7 macro(s)

- `macro_count`: 7
- `unique_component_count`: 7
- `endpoint_count`: 2
- `nonzero_candidate_channel_indexes`: 0
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
  - endpoint 2: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
- component membership (7): `turret_par_m_beam_01_mk1`, `turret_par_m_laser_01_mk1`, `turret_par_m_plasma_01_mk1`, `turret_tel_m_beam_01_mk1`, `turret_tel_m_laser_01_mk1`, `turret_tel_m_plasma_01_mk1`, `turret_ter_m_laser_01_mk1`

### Rank 3 — 5 macro(s)

- `macro_count`: 5
- `unique_component_count`: 5
- `endpoint_count`: 2
- `nonzero_candidate_channel_indexes`: 0
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[1, 0, 0, 0, 0], [2, 0, 0, 0, 0] ×2, [5, 0, 0, 0, 0] ×2`
  - endpoint 2: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[1, 0, 0, 0, 0], [2, 0, 0, 0, 0] ×2, [5, 0, 0, 0, 0] ×2`
- component membership (5): `turret_spl_m_beam_02_mk1`, `turret_spl_m_laser_02_mk1`, `turret_spl_m_plasma_02_mk1`, `turret_ter_m_beam_02_mk1`, `turret_ter_m_laser_02_mk1`

### Rank 4 — 4 macro(s)

- `macro_count`: 4
- `unique_component_count`: 4
- `endpoint_count`: 2
- `nonzero_candidate_channel_indexes`: 0, 1, 2
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[2, 2, 2, 0, 0] ×4`
  - endpoint 2: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[2, 2, 2, 0, 0] ×4`
- component membership (4): `turret_arg_m_beam_01_mk1`, `turret_arg_m_laser_01_mk1`, `turret_arg_m_plasma_01_mk1`, `turret_xen_m_laser_01_mk1`

### Rank 5 — 4 macro(s)

- `macro_count`: 4
- `unique_component_count`: 4
- `endpoint_count`: 5
- `nonzero_candidate_channel_indexes`: (none)
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[0, 0, 0, 0, 0] ×5`
  - endpoint 2: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[0, 0, 0, 0, 0] ×5`
  - endpoint 3: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[0, 0, 0, 0, 0] ×5`
  - endpoint 4: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[0, 0, 0, 0, 0] ×5`
  - endpoint 5: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[0, 0, 0, 0, 0] ×5`
- component membership (4): `turret_arg_m_gatling_02_mk1`, `turret_par_m_gatling_02_mk1`, `turret_pir_m_battleship_01_gatling_02_mk1`, `turret_tel_m_gatling_02_mk1`

### Rank 6 — 3 macro(s)

- `macro_count`: 3
- `unique_component_count`: 3
- `endpoint_count`: 1
- `nonzero_candidate_channel_indexes`: (none)
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[0, 0, 0, 0, 0] ×5`
- component membership (3): `turret_arg_m_shotgun_02_mk1`, `turret_par_m_shotgun_02_mk1`, `turret_tel_m_shotgun_02_mk1`

### Rank 7 — 3 macro(s)

- `macro_count`: 3
- `unique_component_count`: 3
- `endpoint_count`: 1
- `nonzero_candidate_channel_indexes`: 1
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[0, 2, 0, 0, 0] ×4`
- component membership (3): `turret_bor_m_arc_01_mk1`, `turret_bor_m_laser_01_mk1`, `turret_bor_m_railgun_01_mk1`

### Rank 8 — 3 macro(s)

- `macro_count`: 3
- `unique_component_count`: 3
- `endpoint_count`: 1
- `nonzero_candidate_channel_indexes`: 2
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[0, 0, 2, 0, 0] ×4`
- component membership (3): `turret_ter_m_laser_03_mk1`, `turret_xen_l_plasma_01_mk1`, `turret_xen_m_gatling_01_mk1`

### Rank 9 — 3 macro(s)

- `macro_count`: 3
- `unique_component_count`: 3
- `endpoint_count`: 1
- `nonzero_candidate_channel_indexes`: 0
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
- component membership (3): `turret_gen_m_disabler_01_mk1`, `turret_par_m_shotgun_01_mk1`, `turret_tel_m_shotgun_01_mk1`

### Rank 10 — 3 macro(s)

- `macro_count`: 3
- `unique_component_count`: 3
- `endpoint_count`: 2
- `nonzero_candidate_channel_indexes`: 1
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[0, 2, 0, 0, 0] ×4`
  - endpoint 2: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[0, 2, 0, 0, 0] ×4`
- component membership (3): `turret_spl_m_beam_01_mk1`, `turret_spl_m_laser_01_mk1`, `turret_spl_m_plasma_01_mk1`

### Rank 11 — 3 macro(s)

- `macro_count`: 3
- `unique_component_count`: 3
- `endpoint_count`: 5
- `nonzero_candidate_channel_indexes`: 0
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
  - endpoint 2: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
  - endpoint 3: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
  - endpoint 4: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
  - endpoint 5: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
- component membership (3): `turret_par_m_gatling_01_mk1`, `turret_tel_m_gatling_01_mk1`, `turret_ter_m_gatling_01_mk1`

### Rank 12 — 2 macro(s)

- `macro_count`: 2
- `unique_component_count`: 2
- `endpoint_count`: 1
- `nonzero_candidate_channel_indexes`: (none)
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[0, 0, 0, 0, 0] ×5`
- component membership (2): `turret_kha_m_beam_01_mk1`, `turret_ter_l_gatling_01_mk1`

### Rank 13 — 2 macro(s)

- `macro_count`: 2
- `unique_component_count`: 2
- `endpoint_count`: 1
- `nonzero_candidate_channel_indexes`: 0, 1, 2
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[1, 1, 1, 0, 0], [2, 2, 2, 0, 0] ×2, [5, 2, 2, 0, 0] ×2`
- component membership (2): `turret_spl_m_flak_02_mk1`, `turret_spl_m_shotgun_02_mk1`

### Rank 14 — 2 macro(s)

- `macro_count`: 2
- `unique_component_count`: 2
- `endpoint_count`: 1
- `nonzero_candidate_channel_indexes`: 0, 1
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[2, 2, 0, 0, 0] ×4`
- component membership (2): `turret_gen_m_gatling_01_mk1`, `turret_gen_m_shieldpierce_01_mk1`

### Rank 15 — 2 macro(s)

- `macro_count`: 2
- `unique_component_count`: 2
- `endpoint_count`: 2
- `nonzero_candidate_channel_indexes`: 0
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[1, 0, 0, 0, 0] ×5`
  - endpoint 2: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[1, 0, 0, 0, 0] ×5`
- component membership (2): `turret_arg_l_beam_01_mk1`, `turret_tel_l_beam_01_mk1`

### Rank 16 — 2 macro(s)

- `macro_count`: 2
- `unique_component_count`: 2
- `endpoint_count`: 2
- `nonzero_candidate_channel_indexes`: 0, 1, 2
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[1, 1, 1, 0, 0] ×2, [2, 2, 2, 0, 0] ×3`
  - endpoint 2: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[1, 1, 1, 0, 0] ×2, [2, 2, 2, 0, 0] ×3`
- component membership (2): `turret_arg_l_plasma_01_mk1`, `turret_tel_l_plasma_01_mk1`

### Rank 17 — 2 macro(s)

- `macro_count`: 2
- `unique_component_count`: 2
- `endpoint_count`: 5
- `nonzero_candidate_channel_indexes`: 0, 1, 2
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[1, 1, 1, 0, 0], [2, 2, 2, 0, 0] ×2, [3, 2, 2, 0, 0] ×2`
  - endpoint 2: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[1, 1, 1, 0, 0], [2, 2, 2, 0, 0] ×2, [3, 2, 2, 0, 0] ×2`
  - endpoint 3: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[1, 1, 1, 0, 0], [2, 2, 2, 0, 0] ×2, [3, 2, 2, 0, 0] ×2`
  - endpoint 4: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[1, 1, 1, 0, 0], [2, 2, 2, 0, 0] ×2, [3, 2, 2, 0, 0] ×2`
  - endpoint 5: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[1, 1, 1, 0, 0], [2, 2, 2, 0, 0] ×2, [3, 2, 2, 0, 0] ×2`
- component membership (2): `turret_spl_m_gatling_02_mk1`, `turret_ter_m_gatling_02_mk1`

### Rank 18 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 1
- `nonzero_candidate_channel_indexes`: (none)
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 2; `selected_descriptor_channel_count_tuples` = (none)
- component membership (1): `turret_xen_xl_battleship_01_mk1`

### Rank 19 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 1
- `nonzero_candidate_channel_indexes`: 2
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[0, 0, 2, 0, 0] ×4`
- component membership (1): `turret_bor_l_flak_01_mk1`

### Rank 20 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 1
- `nonzero_candidate_channel_indexes`: 2
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[0, 0, 2, 0, 0], [0, 0, 3, 0, 0] ×3`
- component membership (1): `turret_bor_m_railgun_02_mk1`

### Rank 21 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 1
- `nonzero_candidate_channel_indexes`: 0
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
- component membership (1): `turret_kha_l_beam_01_mk1`

### Rank 22 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 1
- `nonzero_candidate_channel_indexes`: 1
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[0, 2, 0, 0, 0] ×4`
- component membership (1): `turret_spl_m_flak_01_mk1`

### Rank 23 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 1
- `nonzero_candidate_channel_indexes`: 0, 1
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[2, 2, 0, 0, 0] ×4`
- component membership (1): `turret_spl_m_shotgun_01_mk1`

### Rank 24 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 1
- `nonzero_candidate_channel_indexes`: 0, 1, 2
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[2, 2, 2, 0, 0] ×4`
- component membership (1): `turret_arg_m_shotgun_01_mk1`

### Rank 25 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 2
- `nonzero_candidate_channel_indexes`: 2
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[0, 0, 2, 0, 0] ×4`
  - endpoint 2: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[0, 0, 2, 0, 0] ×4`
- component membership (1): `turret_bor_l_laser_01_mk1`

### Rank 26 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 2
- `nonzero_candidate_channel_indexes`: 2
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[0, 0, 2, 0, 0], [0, 0, 3, 0, 0] ×3`
  - endpoint 2: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[0, 0, 2, 0, 0], [0, 0, 3, 0, 0] ×3`
- component membership (1): `turret_bor_m_arc_02_mk1`

### Rank 27 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 2
- `nonzero_candidate_channel_indexes`: 0
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[1, 0, 0, 0, 0], [2, 0, 0, 0, 0] ×4`
  - endpoint 2: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[1, 0, 0, 0, 0], [2, 0, 0, 0, 0] ×4`
- component membership (1): `turret_gen_m_yacht_01_mk1`

### Rank 28 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 2
- `nonzero_candidate_channel_indexes`: 0
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
  - endpoint 2: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
- component membership (1): `turret_ter_m_laser_04_mk1`

### Rank 29 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 2
- `nonzero_candidate_channel_indexes`: 2
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[0, 0, 2, 0, 0], [0, 0, 3, 0, 0] ×3`
  - endpoint 2: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[0, 0, 2, 0, 0], [0, 0, 3, 0, 0] ×3`
- component membership (1): `turret_bor_m_laser_02_mk1`

### Rank 30 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 2
- `nonzero_candidate_channel_indexes`: 0, 1, 2
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[1, 1, 1, 0, 0], [2, 2, 2, 0, 0] ×4`
  - endpoint 2: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[1, 1, 1, 0, 0], [2, 2, 2, 0, 0] ×4`
- component membership (1): `turret_xen_l_laser_01_mk1`

### Rank 31 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 2
- `nonzero_candidate_channel_indexes`: 0, 1, 2
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[1, 1, 1, 0, 0], [2, 2, 2, 0, 0] ×2, [3, 3, 3, 0, 0], [4, 4, 4, 0, 0]`
  - endpoint 2: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[1, 1, 1, 0, 0], [2, 2, 2, 0, 0] ×2, [3, 3, 3, 0, 0], [4, 4, 4, 0, 0]`
- component membership (1): `turret_arg_l_laser_01_mk1`

### Rank 32 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 2
- `nonzero_candidate_channel_indexes`: 0
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 6; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
  - endpoint 2: `source_part_path_depth` = 6; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
- component membership (1): `turret_ter_m_beam_01_mk1`

### Rank 33 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 3
- `nonzero_candidate_channel_indexes`: 2
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[0, 0, 2, 0, 0] ×4`
  - endpoint 2: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[0, 0, 2, 0, 0] ×4`
  - endpoint 3: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[0, 0, 2, 0, 0] ×4`
- component membership (1): `turret_bor_l_disruptor_01_mk1`

### Rank 34 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 4
- `nonzero_candidate_channel_indexes`: (none)
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[0, 0, 0, 0, 0] ×5`
  - endpoint 2: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[0, 0, 0, 0, 0] ×5`
  - endpoint 3: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[0, 0, 0, 0, 0] ×5`
  - endpoint 4: `source_part_path_depth` = 4; `selected_descriptor_channel_count_tuples` = `[0, 0, 0, 0, 0] ×5`
- component membership (1): `turret_arg_m_flak_02_mk1`

### Rank 35 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 4
- `nonzero_candidate_channel_indexes`: 0, 1, 2
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 6; `selected_descriptor_channel_count_tuples` = `[2, 2, 2, 0, 0] ×5`
  - endpoint 2: `source_part_path_depth` = 6; `selected_descriptor_channel_count_tuples` = `[2, 2, 2, 0, 0] ×5`
  - endpoint 3: `source_part_path_depth` = 6; `selected_descriptor_channel_count_tuples` = `[2, 2, 2, 0, 0] ×5`
  - endpoint 4: `source_part_path_depth` = 6; `selected_descriptor_channel_count_tuples` = `[2, 2, 2, 0, 0] ×5`
- component membership (1): `turret_arg_m_flak_01_mk1`

### Rank 36 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 5
- `nonzero_candidate_channel_indexes`: 1
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[0, 2, 0, 0, 0] ×4`
  - endpoint 2: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[0, 2, 0, 0, 0] ×4`
  - endpoint 3: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[0, 2, 0, 0, 0] ×4`
  - endpoint 4: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[0, 2, 0, 0, 0] ×4`
  - endpoint 5: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[0, 2, 0, 0, 0] ×4`
- component membership (1): `turret_spl_m_gatling_01_mk1`

### Rank 37 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 5
- `nonzero_candidate_channel_indexes`: 0, 1, 2
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[2, 2, 2, 0, 0] ×4`
  - endpoint 2: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[2, 2, 2, 0, 0] ×4`
  - endpoint 3: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[2, 2, 2, 0, 0] ×4`
  - endpoint 4: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[2, 2, 2, 0, 0] ×4`
  - endpoint 5: `source_part_path_depth` = 5; `selected_descriptor_channel_count_tuples` = `[2, 2, 2, 0, 0] ×4`
- component membership (1): `turret_arg_m_gatling_01_mk1`

### Rank 38 — 1 macro(s)

- `macro_count`: 1
- `unique_component_count`: 1
- `endpoint_count`: 8
- `nonzero_candidate_channel_indexes`: 0
- `endpoint_structure`:
  - endpoint 1: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
  - endpoint 2: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
  - endpoint 3: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
  - endpoint 4: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
  - endpoint 5: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
  - endpoint 6: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
  - endpoint 7: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
  - endpoint 8: `source_part_path_depth` = 3; `selected_descriptor_channel_count_tuples` = `[2, 0, 0, 0, 0] ×4`
- component membership (1): `turret_xen_m_gatling_02_mk1`

## Evidence record

- X4: 9.00
- Status: shipped-source
- Source: the eight verified X4 9.00 official sets under `.x4-research-cache/issue72-a2-sources/` (XML) and `.x4-research-cache/issue72-a2-ani-resources/` (ANI), censored by the current schema-25 census at starting SHA `9397d1b3de719a5c1baf1eba174facce1380f7bd`; report at `.x4-research-cache/issue72-a3-topology-priorities-census.json` (untracked)
- Live test: no — offline source verification only, as of 2026-09-01
- Finding: X4 9.00 ships 92 COMBAT_CANDIDATE conventional turret macros covering 91 unique turret component assets, distributed over the 38 structural endpoint-topology groups listed above in report order. This is an inventory of shipped source structure and ANI key-record storage counts; it assigns no meaning to any candidate channel, no runtime behavior, and no gameplay value.
