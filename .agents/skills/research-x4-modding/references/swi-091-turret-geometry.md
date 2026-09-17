# SWI 0.9.1 HF turret geometry and ANI evidence

Scope: X4 9.00 build 611726 and owner-provided Star Wars Interworlds 0.9.1 HF
content dated 2025-12-24. Third-party source files and extracted resources stay
under ignored `.x4-research-cache/` paths; this reference records only paraphrased
evidence and derived conclusions.

### SWI turret joint-layout census
- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: third-party-technique
- Source: owner-provided SWI catalogs; ignored extracted WeaponSystems XML under `.x4-research-cache/issue179/swi_xml/`
- Live test: no — SWI 0.9.1 HF is not available in the current X4 9.00 runtime environment
- Finding: the 169 in-scope SWI turret-equipment macros reduce to four source-level joint signatures, root-side to leaf-side: 159 `rotation_y` unbounded then `rotation_x` bounded; 8 bounded `rotation_y` then bounded `rotation_x`; 1 `rotation_x` bounded then `rotation_y` bounded (`turret_m_wall_sith_macro`); and 1 `rotation_z` unbounded then `rotation_x` bounded (`turret_arrestor_dish_macro`). All 169 selected endpoint paths use rotation restrictions only.

The eight bounded-`rotation_y` cases are `turret_s_gauntlet_macro`,
`turret_s_lambda_macro`, `turret_m_ion_nk7_ball_macro`, the four
`turret_l_imp_exe_quad_ball_{red,orange,blue,green}_macro` variants, and
`turret_m_imp_exe_tri_ball_ic_macro`.

### SWI ingestion anomalies are orthogonal to joint layout
- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: third-party-technique
- Source: same SWI WeaponSystems XML corpus
- Live test: no
- Finding: 13 macros have a selected-path root connection whose `parent` names an undeclared part; 1 turret macro (`weapon_kx5_s_turret_macro`) references a component classed `weapon`; and all 4 SWI `missileturret` macros use `rocket`-tagged firing endpoints instead of `laser`. These are source-ingestion differences, not additional joint signatures.

The 13 undeclared-parent cases are the nine `turret_m_llaser_*`,
`turret_yuv_l_beam_macro`, `turret_gravity_well_macro`,
`turret_m_tractor_heavy_macro`, plus the four SWI missile-turret macros
`turret_m_borontube_macro`, `turret_m_conctube_macro`,
`turret_m_conctubelight_macro`, and `turret_m_torptube_macro`.

### Official turret controls for the SWI comparison
- X4: 9.00 build 611726
- Status: shipped-source
- Source: `.x4-research-cache/official-source-sets/` covering base X4 9.00 and installed DLC source sets
- Live test: no — source comparison only
- Finding: the broader official scan contains 147 turret/missileturret macros: 114 ordinary turrets, 32 missile turrets with `rocket` firing endpoints and ordinary `rotation_y` then `rotation_x` geometry, and one three-joint mining turret with one `rotation_y` followed by two `rotation_x` joints. No official control in that scan has a bounded `rotation_y`, a targeting `rotation_z`, reversed X/Y joint order, or a selected-path parent naming an undeclared part.

### Rotation restriction roles, limits, and clamp propagation
- X4: 9.00 build 611726
- Status: inference
- Source: build-pinned static trace of `X4.exe` SHA-256 `19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`; route `0x0081C580` → `0x007569A0` → `0x00E221A0` → solver ranges `0x00E21110`–`0x00E22199` → mover `0x00E1F840`
- Live test: no — static trace only
- Finding: restriction records encode rotation type separately from hierarchy position. The traced type table maps `rotation_x`, `rotation_y`, and `rotation_z` to distinct solved rotation types; solver dispatch is selected by that type, not by joint order. Authored limits use wrapped-interval containment; an out-of-range requested angle clamps to the nearer wrapped limit, the clamped upstream transform is composed before downstream joints solve, and the mover zeros velocity when parked at a limit. This supports treating a bounded mechanical stop as a settled pose rather than automatically as UNKNOWN.

### Reversed X/Y wall turret interpretation
- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: inference
- Source: SWI `turret_m_wall_sith_macro` source geometry plus the build-pinned restriction-type dispatch trace above
- Live test: no
- Finding: `turret_m_wall_sith_macro` is an elevation-over-traverse arrangement: root-side `rotation_x` has authored limits -50/+50 degrees and leaf-side `rotation_y` has -20/+20 degrees. Both joint pivots are at the component origin in the extracted source. The type-dispatch trace implies the root X restriction is solved with X-axis angular semantics and the leaf Y restriction with Y-axis angular semantics; hierarchy order does not rename their roles.

### Rotation-Z arrestor-dish interpretation
- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: inference
- Source: SWI `turret_arrestor_dish_macro` source geometry plus the build-pinned restriction-type dispatch trace above
- Live test: no
- Finding: the source path has an unbounded root `rotation_z` joint and a leaf `rotation_x` joint limited to -25/+25 degrees. The static trace shows `rotation_z` is processed as a solved rotation restriction. Interpreting the traced Z-axis angular branch yields a clock-plus-cone mount whose reachable direction region is a roughly 25-degree half-angle cone about component +Z. The source-level joint signature is firm; runtime handedness and exact emitted muzzle position remain unvalidated.

### Missile-turret endpoint control
- X4: 9.00 build 611726
- Status: shipped-source
- Source: official turret/missileturret WeaponSystems corpus under `.x4-research-cache/official-source-sets/`
- Live test: no — source comparison only
- Finding: all 32 official `missileturret` macros in the broader scan use `rocket`-tagged firing endpoints and ordinary rotation-joint geometry. The `missile` token appears on turret-side mating connections rather than serving as the firing endpoint tag.

### SWI missile-turret solver reuse
- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: inference
- Source: official missile-turret control above, SWI missile-turret source paths, and build-pinned static trace of restriction-record iteration
- Live test: no
- Finding: the traced joint solver operates over restriction records rather than firing-endpoint tag family. The four SWI missile turrets therefore fit the same joint-solving model when their single `rocket` endpoint is used for offline path geometry. Whether script-visible `weapon.barrelposition` exposes missile-turret endpoints is not established by this evidence.

### SWI ANI extraction and path-relevant translations
- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: third-party-technique
- Source: owner-provided SWI catalogs; 41 needed ANI resources extracted under ignored `.x4-research-cache/issue176-swi-ani/` with manifest; all 41 extracted bytes matched their catalog MD5 values
- Live test: no
- Finding: 129/169 macros reference geometry sources with ANI resources. The 41 relevant SWI ANI files contain path-relevant `turret_active` descriptors for 106 macros; 88 macros have non-zero path translations. The non-zero family translates `part_rotator` by approximately +2.96209 m on Y and `part_barrel` by approximately +3.521184 m on Z, a combined rest-muzzle displacement of about 4.6014 m if those descriptors bind. The examined path-relevant rotation channels are zero, so this evidence can change pivots/fixed translations but not joint axis, order, or authored limits.

### Missing-selector ANI binding remains unresolved
- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: inference
- Source: SWI ANI/XML comparison above, official X4 turret selector census, and the accepted offline selector-binding model
- Live test: no — no compatible SWI/X4 9.00 runtime is currently available
- Finding: 165 SWI-component macros do not declare the normal `turret_*` state selector family, while the affected ANI resources still contain `turret_active` records. Official X4 9.00 turret sources do not provide a matching control where path-relevant ANI records exist but no effective selector declares that animation name. Therefore the evidence does not establish whether X4 binds those records anyway. The two interpretations differ by metre-scale geometry for 88/169 macros, so neither interpretation should be promoted to runtime truth without new evidence.

### Undeclared-parent loader behavior remains unresolved
- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: inference
- Source: SWI source geometry for the 13 affected macros plus official source scan showing no equivalent undeclared-parent control
- Live test: no — no compatible SWI/X4 9.00 runtime is currently available
- Finding: source inspection cannot distinguish whether X4 attaches a connection whose `parent` names an undeclared part at the component root or drops that connection/subtree. ANI evidence confirms the source art contains a `part_socket` identity in the affected family but does not resolve loader behavior. Treat root-attachment as an explicit inference, not a proven runtime fact.

### Current evidence boundary for offline truth geometry
- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: inference
- Source: combined source and static-trace evidence recorded above
- Live test: no
- Finding: an ordered path of fixed transforms and axis-tagged rotation joints with per-joint limits is sufficient to encode all 169 SWI source-level joint layouts and the observed ANI translations. Runtime truth remains conditional for the 88 macros affected by missing-selector ANI binding and the 13 macros affected by undeclared-parent loader behavior until compatible live evidence or stronger native evidence resolves those two facts.
