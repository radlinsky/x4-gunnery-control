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
- Finding: the SWI turret-equipment structural census is 169 macros (165 `turret`, 4 `missileturret`). This is the structural corpus; the production scope is the 164 combat + equipable subset recorded below. The 169 reduce to four source-level joint signatures, root-side to leaf-side: 159 `rotation_y` unbounded then `rotation_x` bounded; 8 bounded `rotation_y` then bounded `rotation_x`; 1 `rotation_x` bounded then `rotation_y` bounded (`turret_m_wall_sith_macro`); and 1 `rotation_z` unbounded then `rotation_x` bounded (`turret_arrestor_dish_macro`). All 169 selected endpoint paths use rotation restrictions only.

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
- Finding: these are diagnostic counts within the mount-resolvable subset, not production-scope counts. The production-scope recount is the 164-macro table further below; this table is retained only to show how mount resolvability cuts across the unusual cases.

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
  case sit in the 92 rather than the 77. Ware and weapon-behavior evidence has
  since confirmed all of them combat and equipable, so they are required
  despite being mount-unresolvable: the arrestor-dish clock-plus-cone
  interpretation and the bounded-yaw records stay in scope.

### Ware-backed equipability: 167 equipable of the 169

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
  replace, and remove operations alone. Applying the accepted equipability
  rule — an `equipment`-tagged ware, present in the effective set, whose direct
  `<component ref>` exactly equals the turret macro name — to all 169 exact
  macro identities gives **167 equipable** and 2 with no equipment ware. Every
  equipable macro resolves exactly one equipment ware. This record establishes
  equipability only: **no SWI turret ware carries a `purposes` token at all**,
  so the official-corpus convention "no `purposes` means combat" has no
  discriminating power on this third-party content and must not be used to
  infer combat here. Combat status is decided separately, from authored weapon
  behavior, in the record below. The 167 equipable are the accepted 169-macro
  structural census minus exactly these two identities:

  - `turret_l_singlexi8_turbolaser_red_macro` — the SWI ware file contains a
    ware whose `<component ref>` is this macro, but the whole `<ware>` element
    is inside an XML comment, so no ware exists in the effective set.
  - `turret_yuv_l_beam_macro` — no ware in any of the nine sources references
    this macro at all.

  Nothing was classified from macro names, mating tags, display names, or
  appearance. The four macros reusing official X4 components keep official
  wares that SWI does not remove, and are equipable.

  Reproduction, for a fresh session: enumerate every `macro` with
  `class="turret"` or `class="missileturret"` in the ignored SWI WeaponSystems
  XML (this yields the accepted 169, 165 + 4); build the effective ware set by
  applying the eight official `libraries/wares.xml` sources then the SWI diff,
  treating whole-`<ware>` add/replace/remove only; keep a macro when exactly one
  surviving `equipment`-tagged ware names it in `<component ref>`. That gives the
  169 minus the two identities above. Then apply the weapon-behavior rule from
  the next record to those 167 to reach the final 164. The same enumeration
  reproduces every count in the tables below, which is how the 169 census, the 159/8/1/1 signatures, the 13 undeclared-parent
  identities, the four `rocket` endpoints, and the 77/92 split were re-verified
  against the accepted record before the ware filter was applied.

### Combat versus utility is decided by authored weapon behavior

- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: third-party-technique
- Source: SWI `assets/fx/weaponFx/`, `assets/props/WeaponSystems/` and
  `libraries/influenceconfigurations.xml` recovered from the same verified
  `starwarsmod_m1_091hf` archive into ignored `.x4-research-cache/` (693 XML
  files, all extracted bytes matching their catalog MD5); official X4 9.00
  `assets/fx/weaponFx/macros/` as controls
- Live test: no — SWI 0.9.1 HF is not available in the current X4 9.00 runtime
- Finding: every SWI turret macro declares a `<bullet class>` (or, for the
  missile turrets, a `<missile class>`), so combat status is decided by
  following that reference to the projectile macro's own authored properties.
  Across the whole official X4 9.00 bullet corpus the utility weapons are
  marked in exactly three ways, and only these three: `<weapon
  system="weapon_mining">` on the 11 mining bullets whose wares carry
  `purposes="mine"`; `<weapon system="weapon_repair">` on the repair laser;
  and `<bullet tug="1">` with an empty `<damage repair="0"/>` on the salvage
  scrapbeam whose ware carries `purposes="salvage"`. Two attributes that look
  like utility markers are not: official combat ion weapons carry
  `influencelist`, and official mining bullets carry substantial positive
  damage values, so neither an influence list nor the size of a damage value
  discriminates.

  The rule applied, in order, is therefore: a declared utility weapon system
  (`weapon_mining`, `weapon_repair`) or `tug="1"` means **NONCOMBAT_UTILITY**;
  otherwise a positive non-repair `damage`, `areadamage`, or `explosiondamage`
  amount means **COMBAT**; anything else is **UNRESOLVED**. Over the 167
  equipable macros this gives **164 COMBAT, 2 NONCOMBAT_UTILITY, 1
  UNRESOLVED**.

  The two utility turrets are `turret_m_sw_mining_01_macro` and
  `turret_m_sw_mining_02_macro`. Neither is identifiable from geometry or
  mating tags; both declare the official bullet
  `bullet_tel_turret_l_mining_01_mk1_macro`, which SWI does not override and
  which declares `<weapon system="weapon_mining">` — the same system as the
  official mining turrets whose wares carry `purposes="mine"`.

  The one unresolved turret is `turret_gravity_well_macro`. Its bullet is the
  only SWI turret projectile whose `<damage>` and `<areadamage>` are both
  `hull="1" repair="1"`, the repair flag that in official source marks the
  repair laser. That source shape does not establish ordinary damaging
  behavior. It nonetheless
  declares a combat weapon system (`turret_longrange`) and an
  `influencelist="gravity_well"` that `libraries/influenceconfigurations.xml`
  authors as a hostile 30-second `disabletravel` on the target — the same
  mechanic family as SWI's ion torpedo effects and official X4's
  `ion_disrupt_*`. It is demonstrably not mining, salvage, tug, or a
  friendly-repair weapon, but the source does not settle whether a
  repair-flagged hostile-effect turret is in #176 combat scope. Fail closed:
  UNRESOLVED, excluded from the supported corpus until decided.

  `turret_m_tractor_heavy_macro`, the other mating-tag suspect, is **COMBAT**:
  it inflicts non-repair damage, declares `turret_midrange`, sets no `tug`
  attribute, and its `tractor_heavy_effect` influence list is a hostile
  movement-suppression debuff. Three other in-scope turrets carry
  `tractor_*_effect` influence lists on ordinarily damaging bullets. No
  classification anywhere used a macro name, display name, mating tag,
  appearance, faction, or the absence of a ware `purposes` token.

### Unusual-case recount over the final 164-macro corpus

- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: third-party-technique
- Source: same corpus, recomputed per macro over the combat + equipable set
- Live test: no
- Finding: these are the production-scope counts for #176. Mount resolvability
  is reported as a separate property inside the corpus, not as a scope filter.

| Case | 169 census | Final 164 | In scope? |
|---|---|---|---|
| unbounded `rotation_y` → bounded `rotation_x` | 159 | 154 | yes; all five excluded macros are from this signature |
| bounded `rotation_y` → bounded `rotation_x` | 8 | 8 | yes — all eight |
| reversed `rotation_x` → `rotation_y` (`turret_m_wall_sith_macro`) | 1 | 1 | yes |
| unbounded `rotation_z` → bounded `rotation_x` (`turret_arrestor_dish_macro`) | 1 | 1 | yes |
| `missileturret` with `rocket` endpoints | 4 | 4 | yes — all four |
| component classed `weapon` (`weapon_kx5_s_turret_macro`) | 1 | 1 | yes |
| undeclared-parent root connection | 13 | 11 | yes; `turret_yuv_l_beam_macro` and `turret_gravity_well_macro` drop out |
| non-zero missing-selector ANI translations (unbound; resolved) | 88 | 84 | yes |
| geometry source with an SWI ANI resource | 129 | 124 | — |
| path-relevant `turret_active` descriptors | 106 | 102 | — |

  No unusual geometry case is retired: every bounded-yaw macro, the
  reversed-order wall turret, the rotation-Z arrestor dish, all four missile
  turrets, and the component-classed-as-weapon case are combat and equipable
  and must be supported. All five excluded macros — 2 with no equipment ware,
  2 mining, 1 unresolved — are ordinary `rotation_y` → `rotation_x` turrets.

  Mount resolvability inside the final corpus: **74 of the 164** resolve a
  unique `component`-tagged mating connection and **90 do not**. The two
  properties stay independent, exactly as the mating-connection record states.
  Within those 74 the unusual cases are 72 ordinary signatures,
  `turret_m_ion_nk7_ball_macro` (bounded yaw), `turret_m_wall_sith_macro`, all
  four missile turrets, `weapon_kx5_s_turret_macro`, 5 undeclared-parent
  macros, and 34 with non-zero ANI translations.

### SWI ANI extraction and path-relevant translations
- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: third-party-technique
- Source: owner-provided SWI catalogs; 41 needed ANI resources extracted under ignored `.x4-research-cache/issue176-swi-ani/` with manifest; all 41 extracted bytes matched their catalog MD5 values
- Live test: no
- Finding: of the 165 macros using SWI-authored components, 129 reference geometry sources with an SWI ANI resource. The 41 relevant SWI ANI files contain path-relevant `turret_active` descriptors for 106 of them; 88 have non-zero path translations. Restricted to the 77 mount-resolvable macros the same measurement gives 60, 50 and 36. The non-zero family translates `part_rotator` by approximately +2.96209 m on Y and `part_barrel` by approximately +3.521184 m on Z, a combined rest-muzzle displacement of about 4.6014 m if those descriptors bind. The examined path-relevant rotation channels are zero, so this evidence can change pivots/fixed translations but not joint axis, order, or authored limits. Those descriptors do **not** bind: see the resolved missing-selector record below. These translations are art data X4 never reaches on these components.

### Missing-selector ANI binding is resolved: the descriptors never bind

- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: shipped-source
- Source: build-pinned `X4.exe` SHA-256
  `19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`,
  re-disassembled for this record at `0x14088a203` (animated-part bit 9),
  `0x140754fa0`–`0x140754ffa` (instance animation-entry creation),
  `0x140880d10` (per-part animation source object), `0x14074c2d0`
  (part local-transform branch); plus the accepted #166 A7 selector/state
  trace and a per-connection re-scan of the affected SWI component XML under
  ignored `.x4-research-cache/issue179/swi_xml/`
- Live test: no — static native trace plus source scan
- Finding: this supersedes the earlier "remains unresolved" record. The
  engine decides whether a part is animated from authored `<animation>`
  records alone, before any ANI file is consulted:

  - `0x14088a203` sets the animated bit only when the connection's own
    `<animations>` list is non-empty, or when its parent part is animated and
    the tag gate passes. A component with no `<animation>` record anywhere
    therefore has no animated part.
  - `0x140754fa0` creates a per-instance animation entry only for parts
    carrying that bit, so no `SequenceControlUnit`, no state, and no initial
    `Turret`/`MissileTurret` `turret_active`/`turret_inactive` selection
    happens for such a part.
  - `0x140880d10` returns a null animation source object when the connection
    has no selector list and no animated ancestor, so no ANI descriptor is
    ever bound. Descriptor binding is per selector name; a `turret_active`
    descriptor with no `turret_active` selector has nothing to bind to.
  - `0x14074c2d0` branches on that same bit and, when it is clear, copies the
    stored part matrix directly. The animated evaluator is not called.

  Re-scanning the affected SWI sources: the 84 in-scope macros resolve to 64
  distinct components, and **all 64 contain zero `<animation>` records on any
  connection**, on or off the selected path. No SWI file redefines or `<diff>`s
  those components. The ANI `turret_active` descriptors exist in the art but
  are unreachable.

  **Therefore the physical transform X4 uses for every affected path part is
  the stored XML part local**, not the ANI descriptor and not a runtime choice
  between them. The stored part translation is zero on all 325 affected-macro
  path parts, which is also what the animation-default branch would give, so
  the two non-ANI branches coincide and only the ANI branch would have
  differed — by up to 3.521184 m on a single axis, about 4.6014 m combined.

  Consequence for prediction: geometry is fixed at load/instance-init from
  static data. The target position enters only the downstream joint solver, so
  the engine can never try one geometry, fail, and reach for the other. An
  "either candidate geometry can bear on the target" rule has no runtime
  referent and must not be used. The stored-part-local geometry is
  authoritative; the ANI alternative is not a second runtime geometry and
  should be dropped rather than scored.

  The 84 macros are **no longer uncertain on this ground**. The separate
  undeclared-parent question below is unaffected: it applies to 11 macros, all
  of which are inside the 84, and it does not interact with the bit-9 decision,
  because those components declare no animation records either way.

### Undeclared-parent loader behavior remains unresolved
- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: inference
- Source: SWI source geometry for the 13 affected macros plus official source scan showing no equivalent undeclared-parent control
- Live test: no — no compatible SWI/X4 9.00 runtime is currently available
- Finding: this affects 13 of the 169, **11 of the final 164-macro combat + equipable corpus**, of which 5 are also mount-resolvable. Source inspection cannot distinguish whether X4 attaches a connection whose `parent` names an undeclared part at the component root or drops that connection/subtree. ANI evidence confirms the source art contains a `part_socket` identity in the affected family but does not resolve loader behavior. Treat root-attachment as an explicit inference, not a proven runtime fact.

### Current evidence boundary for offline truth geometry
- X4: 9.00 build 611726; SWI 0.9.1 HF
- Status: inference
- Source: combined source and static-trace evidence recorded above
- Live test: no
- Finding: an ordered path of fixed transforms and axis-tagged rotation joints with per-joint limits is sufficient to encode all 169 SWI source-level joint layouts and the observed ANI translations. Missing-selector ANI binding is now resolved by native evidence: the 84 affected in-scope macros take the stored XML part local and carry a single geometry. The one remaining offline-truth uncertainty for the final #176 corpus is undeclared-parent loader behavior, affecting 11 in-scope macros, all of which sit inside those 84. The runtime handedness caveat on the rotation-Z arrestor dish is a separate, narrower open item.
