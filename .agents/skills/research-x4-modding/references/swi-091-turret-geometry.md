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
- Finding: the SWI turret-equipment structural census is 169 macros (165 `turret`, 4 `missileturret`). This is the structural corpus; the production scope is the 167 combat + equipable subset recorded below. The 169 reduce to four source-level joint signatures, root-side to leaf-side: 159 `rotation_y` unbounded then `rotation_x` bounded; 8 bounded `rotation_y` then bounded `rotation_x`; 1 `rotation_x` bounded then `rotation_y` bounded (`turret_m_wall_sith_macro`); and 1 `rotation_z` unbounded then `rotation_x` bounded (`turret_arrestor_dish_macro`). All 169 selected endpoint paths use rotation restrictions only.

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

### Mating-connection resolvability: 77 of the 169

- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: third-party-technique
- Source: same SWI WeaponSystems XML corpus; the accepted rule in `turret-ship-compatibility.md`; the official control recorded above
- Live test: no
- Finding: the accepted compatibility rule resolves a turret's mating connection as its unique connection tagged `component`. Only 77 of the 169 SWI macros have one, against 147 of 147 in the official control above; the other 92 have none. Those 92 are not missing a turret connection — each has exactly one `turret`-tagged connection carrying ordinary size/variant/hittability tags — they omit the structural `component` token that the rule requires. Under the repository's fail-closed policy the mating connection is therefore unresolved for those 92, so the accepted compatibility rule cannot currently resolve a mount for them. That is a statement about mount resolvability only. It is not evidence that those macros are non-combat or non-equipable, and membership in either the 77 or the 92 does not by itself decide #176 production scope.

  The 77 mount-resolvable macros are 73 SWI-component macros plus 4 that reuse
  official X4 components: `turret_xen_l_laser_01_mk1_macro`,
  `turret_xen_m_beam_02_mk1_macro`, `turret_xen_m_laser_02_mk1_macro`, and
  `turret_yuv_m_bioplasma_macro`. The last four declare the normal `turret_*`
  selector family and carry no SWI-specific ANI or loader uncertainty.

### Diagnostic unusual-case recount within the mount-resolvable subset

- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: third-party-technique
- Source: same corpus, recomputed per macro rather than inherited from the 169 census
- Live test: no
- Finding: these are diagnostic counts within the mount-resolvable subset, not production-scope counts. The production-scope recount is the 167-macro table further below; this table is retained only to show how mount resolvability cuts across the unusual cases.

| Case | 169 census | Within the 77 | Identities |
|---|---|---|---|
| unbounded `rotation_y` → bounded `rotation_x` | 159 | 75 | — |
| bounded `rotation_y` → bounded `rotation_x` | 8 | 1 | `turret_m_ion_nk7_ball_macro` |
| reversed `rotation_x` → `rotation_y` | 1 | 1 | `turret_m_wall_sith_macro` |
| unbounded `rotation_z` → bounded `rotation_x` | 1 | 0 | `turret_arrestor_dish_macro` (in the 92) |
| `missileturret` macros | 4 | 4 | `turret_m_borontube_macro`, `turret_m_conctube_macro`, `turret_m_conctubelight_macro`, `turret_m_torptube_macro` |
| component classed `weapon` | 1 | 1 | `weapon_kx5_s_turret_macro` |
| undeclared-parent root connection | 13 | 7 | the four missile turrets above plus `turret_gravity_well_macro`, `turret_m_tractor_heavy_macro`, `turret_yuv_l_beam_macro` |
| metre-scale missing-selector ANI uncertainty | 88 | 36 | the six `turret_m_llaser_*` macros are in the 92 |

  Seven of the eight bounded-`rotation_y` macros and the sole `rotation_z`
  case sit in the 92 rather than the 77. Ware evidence has since confirmed all
  of them combat and equipable, so they are required despite being
  mount-unresolvable: the arrestor-dish clock-plus-cone interpretation and the
  bounded-yaw records stay in scope.

### Final #176 scope: 167 combat + equipable of the 169

- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: third-party-technique
- Source: SWI `libraries/wares.xml` recovered from the owner's original
  `starwarsmod_m1_091hf` archive (`content.xml` `version="091"`,
  `description="Star Wars 0.9.1 HF"`, `date="2025-12-24"`); catalog entry
  `ext_02.cat` `libraries/wares.xml`, extracted bytes MD5
  `c7f87df657c0e1f4058e710defcb0c7b` matching the catalog index. Archive
  identity against the accepted research was confirmed by re-reading all 41
  previously extracted ANI resources at their recorded `ext_01.dat` offsets:
  41/41 byte-identical. Joined against the eight official X4 9.00
  `libraries/wares.xml` sources under `.x4-research-cache/official-source-sets/`.
  Raw SWI data stays under ignored `.x4-research-cache/` paths.
- Live test: no — SWI 0.9.1 HF is not available in the current X4 9.00 runtime
- Finding: the SWI ware file is a `<diff>` (119 `add`, 662 `replace`, 1008
  `remove`) applied over the official ware set; no selector in any of the nine
  sources edits a ware's `<component>` or `<use>` subtree, so ware identity,
  component reference, and purpose tokens are decided by whole-`<ware>` add,
  replace, and remove operations alone. Applying the accepted rule — an
  `equipment`-tagged ware, present in the effective set, whose direct
  `<component ref>` exactly equals the turret macro name, with no `purposes`
  token meaning combat and `mine`/`salvage` meaning utility — to all 169 exact
  macro identities gives **167 combat + equipable**, 0 utility/non-combat, 0
  ambiguous or unresolved, and 2 with no equipment ware. Every in-scope macro
  resolves exactly one equipment ware; none carries a `purposes` token. The
  final corpus is therefore the accepted 169-macro structural census minus
  exactly these two identities:

  - `turret_l_singlexi8_turbolaser_red_macro` — the SWI ware file contains a
    ware whose `<component ref>` is this macro, but the whole `<ware>` element
    is inside an XML comment, so no ware exists in the effective set.
  - `turret_yuv_l_beam_macro` — no ware in any of the nine sources references
    this macro at all.

  Nothing was classified from macro names, mating tags, display names, or
  appearance. The two purpose-test candidates flagged earlier on their mating
  tags, `turret_gravity_well_macro` (`gravitywell`) and
  `turret_m_tractor_heavy_macro` (`tractorh`), each resolve a single
  `equipment`-tagged ware with a bare `<use threshold="0" />` and are therefore
  **in scope** under the ware rule; the tags carried no weight either way. The
  four macros reusing official X4 components keep official wares that SWI does
  not remove, and are in scope.

  Reproduction, for a fresh session: enumerate every `macro` with
  `class="turret"` or `class="missileturret"` in the ignored SWI WeaponSystems
  XML (this yields the accepted 169, 165 + 4); build the effective ware set by
  applying the eight official `libraries/wares.xml` sources then the SWI diff,
  treating whole-`<ware>` add/replace/remove only; keep a macro when exactly one
  surviving `equipment`-tagged ware names it in `<component ref>` and no `<use>`
  entry carries `purposes`. The result is the 169 minus the two identities
  above. The same enumeration reproduces every count in the tables below, which
  is how the 169 census, the 159/8/1/1 signatures, the 13 undeclared-parent
  identities, the four `rocket` endpoints, and the 77/92 split were re-verified
  against the accepted record before the ware filter was applied.

### Unusual-case recount over the final 167-macro corpus

- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: third-party-technique
- Source: same corpus, recomputed per macro over the ware-filtered set
- Live test: no
- Finding: these are the production-scope counts for #176. Mount resolvability
  is reported as a separate property inside the corpus, not as a scope filter.

| Case | 169 census | Final 167 | In scope? |
|---|---|---|---|
| unbounded `rotation_y` → bounded `rotation_x` | 159 | 157 | yes; the 2 excluded macros are both from this signature |
| bounded `rotation_y` → bounded `rotation_x` | 8 | 8 | yes — all eight |
| reversed `rotation_x` → `rotation_y` (`turret_m_wall_sith_macro`) | 1 | 1 | yes |
| unbounded `rotation_z` → bounded `rotation_x` (`turret_arrestor_dish_macro`) | 1 | 1 | yes |
| `missileturret` with `rocket` endpoints | 4 | 4 | yes — all four |
| component classed `weapon` (`weapon_kx5_s_turret_macro`) | 1 | 1 | yes |
| undeclared-parent root connection | 13 | 12 | yes; only `turret_yuv_l_beam_macro` drops out |
| non-zero missing-selector ANI translations | 88 | 87 | yes; only `turret_yuv_l_beam_macro` drops out |
| geometry source with an SWI ANI resource | 129 | 127 | both excluded macros had one |
| path-relevant `turret_active` descriptors | 106 | 105 | `turret_l_singlexi8_turbolaser_red_macro`'s ANI has none |

  No unusual geometry case is retired by ware evidence: every bounded-yaw
  macro, the reversed-order wall turret, the rotation-Z arrestor dish, all four
  missile turrets, and the component-classed-as-weapon case are combat and
  equipable and must be supported. Both exclusions are ordinary
  `rotation_y` → `rotation_x` turrets.

  Mount resolvability inside the final corpus: **75 of the 167** resolve a
  unique `component`-tagged mating connection and **92 do not**. Both excluded
  macros came from the 77, so the 92 is unchanged; the two properties are
  independent, exactly as the mating-connection record states. Within those 75,
  the unusual cases are 73 ordinary signatures, `turret_m_ion_nk7_ball_macro`
  (bounded yaw), `turret_m_wall_sith_macro`, all four missile turrets,
  `weapon_kx5_s_turret_macro`, 6 undeclared-parent macros, and 35 with non-zero
  ANI translations.

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
- Finding: 165 SWI-component macros do not declare the normal `turret_*` state selector family, while the affected ANI resources still contain `turret_active` records. Official X4 9.00 turret sources do not provide a matching control where path-relevant ANI records exist but no effective selector declares that animation name. Therefore the evidence does not establish whether X4 binds those records anyway. The two interpretations differ by metre-scale geometry for 88 of the 165 SWI-component macros — **87 of the final 167-macro combat + equipable corpus**, of which 35 are also mount-resolvable — so neither interpretation should be promoted to runtime truth without new evidence.

### Undeclared-parent loader behavior remains unresolved
- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: inference
- Source: SWI source geometry for the 13 affected macros plus official source scan showing no equivalent undeclared-parent control
- Live test: no — no compatible SWI/X4 9.00 runtime is currently available
- Finding: this affects 13 of the 169, **12 of the final 167-macro combat + equipable corpus**, of which 6 are also mount-resolvable. Source inspection cannot distinguish whether X4 attaches a connection whose `parent` names an undeclared part at the component root or drops that connection/subtree. ANI evidence confirms the source art contains a `part_socket` identity in the affected family but does not resolve loader behavior. Treat root-attachment as an explicit inference, not a proven runtime fact.

### Current evidence boundary for offline truth geometry
- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: inference
- Source: combined source and static-trace evidence recorded above
- Live test: no
- Finding: an ordered path of fixed transforms and axis-tagged rotation joints with per-joint limits is sufficient to encode all 169 SWI source-level joint layouts and the observed ANI translations. Runtime truth remains conditional for the 87 in-scope macros affected by missing-selector ANI binding and the 12 affected by undeclared-parent loader behavior, until compatible live evidence or stronger native evidence resolves those two facts. Both uncertainties survive the ware filter and remain unresolved for the final #176 corpus.
