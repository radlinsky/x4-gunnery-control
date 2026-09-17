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
- Finding: the SWI turret-equipment structural census is 169 macros (165 `turret`, 4 `missileturret`). This is the structural corpus, not the production scope; see the mating-connection record below for the supported subset. The 169 reduce to four source-level joint signatures, root-side to leaf-side: 159 `rotation_y` unbounded then `rotation_x` bounded; 8 bounded `rotation_y` then bounded `rotation_x`; 1 `rotation_x` bounded then `rotation_y` bounded (`turret_m_wall_sith_macro`); and 1 `rotation_z` unbounded then `rotation_x` bounded (`turret_arrestor_dish_macro`). All 169 selected endpoint paths use rotation restrictions only.

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

The 13 undeclared-parent cases are the six `turret_m_llaser_*`,
`turret_yuv_l_beam_macro`, `turret_gravity_well_macro`,
`turret_m_tractor_heavy_macro`, plus the four SWI missile-turret macros
`turret_m_borontube_macro`, `turret_m_conctube_macro`,
`turret_m_conctubelight_macro`, and `turret_m_torptube_macro`.

### Official turret controls for the SWI comparison
- X4: 9.00 build 611726
- Status: shipped-source
- Source: `.x4-research-cache/official-source-sets/` covering base X4 9.00 and installed DLC source sets
- Live test: no — source comparison only
- Finding: the broader official scan contains 147 turret/missileturret macros: 114 ordinary turrets, 32 missile turrets with `rocket` firing endpoints and ordinary `rotation_y` then `rotation_x` geometry, and one three-joint mining turret with one `rotation_y` followed by two `rotation_x` joints. No official control in that scan has a bounded `rotation_y`, a targeting `rotation_z`, reversed X/Y joint order, or a selected-path parent naming an undeclared part. Every one of those 147 macros also resolves exactly one `component`-tagged mating connection, so the accepted compatibility rule never fails closed on official data.

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

### Only 77 of the 169 resolve a mating connection

- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: third-party-technique
- Source: same SWI WeaponSystems XML corpus; the accepted rule in `turret-ship-compatibility.md`; the official control recorded above
- Live test: no
- Finding: the accepted compatibility rule resolves a turret's mating connection as its unique connection tagged `component`. Only 77 of the 169 SWI macros have one, against 147 of 147 in the official control above; the other 92 have none. Those 92 are not missing a turret connection — each has exactly one `turret`-tagged connection carrying ordinary size/variant/hittability tags — they omit the structural `component` token that the rule requires. Under the repository's fail-closed policy the mating connection is therefore unresolved for those 92 and they cannot enter production scope on current evidence, whatever the ware answer turns out to be.

  The 77 mount-resolvable macros are 73 SWI-component macros plus 4 that reuse
  official X4 components: `turret_xen_l_laser_01_mk1_macro`,
  `turret_xen_m_beam_02_mk1_macro`, `turret_xen_m_laser_02_mk1_macro`, and
  `turret_yuv_m_bioplasma_macro`. The last four declare the normal `turret_*`
  selector family and carry no SWI-specific ANI or loader uncertainty.

### Unusual-case recount over the 77 mount-resolvable macros

- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: third-party-technique
- Source: same corpus, recomputed per macro rather than inherited from the 169 census
- Live test: no
- Finding: recounted against the mount-resolvable subset instead of the 169 structural census:

| Case | 169 census | Of the 77 | Identities within the 77 |
|---|---|---|---|
| unbounded `rotation_y` → bounded `rotation_x` | 159 | 75 | — |
| bounded `rotation_y` → bounded `rotation_x` | 8 | 1 | `turret_m_ion_nk7_ball_macro` |
| reversed `rotation_x` → `rotation_y` | 1 | 1 | `turret_m_wall_sith_macro` |
| unbounded `rotation_z` → bounded `rotation_x` | 1 | 0 | `turret_arrestor_dish_macro` falls out |
| `missileturret` macros | 4 | 4 | `turret_m_borontube_macro`, `turret_m_conctube_macro`, `turret_m_conctubelight_macro`, `turret_m_torptube_macro` |
| component classed `weapon` | 1 | 1 | `weapon_kx5_s_turret_macro` |
| undeclared-parent root connection | 13 | 7 | the four missile turrets above plus `turret_gravity_well_macro`, `turret_m_tractor_heavy_macro`, `turret_yuv_l_beam_macro` |
| metre-scale missing-selector ANI uncertainty | 88 | 36 | the six `turret_m_llaser_*` macros all fall out with the 92 |

  Seven of the eight bounded-`rotation_y` macros fall out, as does the sole
  `rotation_z` case, so the arrestor-dish clock-plus-cone interpretation is no
  longer needed for supported geometry. Every other unusual case survives: the
  reversed X/Y wall turret, all four missile turrets, the `weapon`-class
  component mismatch, and seven undeclared-parent macros remain in scope and
  still require explicit handling.

### Ware-backed equipability and combat purpose remain unresolved

- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: third-party-technique
- Source: inventory of the locally retained SWI research data
- Live test: no
- Finding: the accepted model decides equipability and combat-versus-utility from equipment wares — an equipment ware whose direct `<component ref>` exactly equals the turret macro name, with empty `<use>` purpose tokens meaning combat and exactly `mine` or `salvage` meaning non-combat utility. The retained SWI extraction covers `props/WeaponSystems/` XML and 41 ANI resources only; it contains no SWI `libraries/wares.xml`, no ship macros, and no macro index, and the SWI catalogs are no longer present on this machine. Neither axis can be derived from the retained data, so no SWI macro is yet classified combat or equipable. 77 is an upper bound on the final corpus, not the corpus.

  To close this, extract SWI `libraries/wares.xml` from the SWI catalogs into
  the ignored cache and apply the accepted ware rule to the 77. Two members
  are the obvious purpose-test candidates on their authored mating tags
  (`turret_gravity_well_macro` tagged `gravitywell`, `turret_m_tractor_heavy_macro`
  tagged `tractorh`); neither is classified here, because the accepted rule
  decides purpose from the ware, not from tags or names.

### SWI ANI extraction and path-relevant translations
- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: third-party-technique
- Source: owner-provided SWI catalogs; 41 needed ANI resources extracted under ignored `.x4-research-cache/issue176-swi-ani/` with manifest; all 41 extracted bytes matched their catalog MD5 values
- Live test: no
- Finding: of the 165 macros using SWI-authored components, 129 reference geometry sources with an SWI ANI resource. The 41 relevant SWI ANI files contain path-relevant `turret_active` descriptors for 106 of them; 88 have non-zero path translations. Restricted to the 77 mount-resolvable macros the same measurement gives 60, 50 and 36. The non-zero family translates `part_rotator` by approximately +2.96209 m on Y and `part_barrel` by approximately +3.521184 m on Z, a combined rest-muzzle displacement of about 4.6014 m if those descriptors bind. The examined path-relevant rotation channels are zero, so this evidence can change pivots/fixed translations but not joint axis, order, or authored limits.

### Missing-selector ANI binding remains unresolved
- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: inference
- Source: SWI ANI/XML comparison above, official X4 turret selector census, and the accepted offline selector-binding model
- Live test: no — no compatible SWI/X4 9.00 runtime is currently available
- Finding: 165 SWI-component macros do not declare the normal `turret_*` state selector family, while the affected ANI resources still contain `turret_active` records. Official X4 9.00 turret sources do not provide a matching control where path-relevant ANI records exist but no effective selector declares that animation name. Therefore the evidence does not establish whether X4 binds those records anyway. The two interpretations differ by metre-scale geometry for 88 of the 165 SWI-component macros, and for 36 of the 77 mount-resolvable macros, so neither interpretation should be promoted to runtime truth without new evidence.

### Undeclared-parent loader behavior remains unresolved
- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: inference
- Source: SWI source geometry for the 13 affected macros plus official source scan showing no equivalent undeclared-parent control
- Live test: no — no compatible SWI/X4 9.00 runtime is currently available
- Finding: this affects 13 of the 169 and 7 of the 77 mount-resolvable macros. Source inspection cannot distinguish whether X4 attaches a connection whose `parent` names an undeclared part at the component root or drops that connection/subtree. ANI evidence confirms the source art contains a `part_socket` identity in the affected family but does not resolve loader behavior. Treat root-attachment as an explicit inference, not a proven runtime fact.

### Current evidence boundary for offline truth geometry
- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: inference
- Source: combined source and static-trace evidence recorded above
- Live test: no
- Finding: an ordered path of fixed transforms and axis-tagged rotation joints with per-joint limits is sufficient to encode all 169 SWI source-level joint layouts and the observed ANI translations. Within the 77 mount-resolvable macros, runtime truth remains conditional for 36 affected by missing-selector ANI binding and 7 affected by undeclared-parent loader behavior, until compatible live evidence or stronger native evidence resolves those two facts. The corresponding 88 and 13 figures describe the 169 structural census and must not be quoted as production scope.
