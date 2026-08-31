# Turret macros with no equipment ware (X4 9.00)

Issue #72 A3 follow-up. The A3 census leaves turret macros UNRESOLVED with
`no_exact_equipment_ware`. This reference records per-macro shipped-source
eligibility evidence, one macro per entry. Evidence rule per entry: only
shipped-source references to that exact macro and its own authored use
context determine the result; related records (siblings, shared components,
the ware channel) are corroboration, not proof; macro and display-name
spelling is never used as evidence.

## `turret_xen_l_laser_01_mk1_scenario_macro` — COMBAT_CANDIDATE

Identity: macro `turret_xen_l_laser_01_mk1_scenario_macro`; component
`turret_xen_l_laser_01_mk1`; source set `base`; A3 census reason as emitted by the current classifier
(at commit `a9f215f`): `no_exact_equipment_ware`.

Result: **COMBAT_CANDIDATE** — the macro's own authored records identify it
as a conventional weapon turret declaring a damaging long-range weapon, and
nothing in its authored context expresses a non-combat purpose.

### The macro is an authored conventional weapon-turret prop
- X4: 9.00
- Status: shipped-source
- Source: `base/assets/props/WeaponSystems/standard/macros/turret_xen_l_laser_01_mk1_scenario_macro.xml`
- Live test: no — untested as of 2026-08-31
- Finding: The file defines one `<macro>` of that name with
  `class="turret"`, referencing component `turret_xen_l_laser_01_mk1` and
  declaring a dedicated bullet class, rotation speed and acceleration
  limits, and a hull value. It sits in the `WeaponSystems/standard/` macro
  set, the authored location of the faction combat turret macros; the mining
  utility turrets are authored in the separate `WeaponSystems/mining/` set.

### The macro's declared bullet is a damaging long-range weapon
- X4: 9.00
- Status: shipped-source
- Source: `base/assets/fx/weaponFx/macros/bullet_xen_turret_l_laser_01_mk1_scenario_macro.xml`
- Live test: no — untested as of 2026-08-31
- Finding: The bullet macro the turret declares references the standard Xenon
  laser bullet component and carries a full weapon profile: damage value
  3229 with shield disruption, reload time 3, two barrels, projectile speed
  1958, and the authored declaration
  `<weapon system="turret_longrange" />`. The corpus's utility channel is
  authored differently: the Argon mining turret bullet declares
  `<weapon system="weapon_mining" />` with base damage 50 plus a mining
  damage multiplier of 30 and attach-on-impact behavior. Nothing in this
  macro's authored context expresses a `mine` or `salvage` purpose.

### The macro has no other shipped references and no equipment ware
- X4: 9.00
- Status: shipped-source
- Source: all 8 shipped X4 9.00 catalogs extracted to `.x4-research-cache/issue72-a2-sources/`
- Live test: no — untested as of 2026-08-31
- Finding: The macro name occurs exactly once across all 8 shipped source
  sets, in its own definition file; no other source references it. Under
  `libraries/` the name occurs zero times. The equipment channel for this
  weapon system is ware `turret_xen_l_laser_01_mk1` in
  `base/libraries/wares.xml`, whose `<component ref>` points at the standard
  macro `turret_xen_l_laser_01_mk1_macro`, not at the scenario macro; the
  ware grants `xenon` and `player` entries with no `purposes`. The scenario
  macro therefore has no authored ware access channel — the A3
  `no_exact_equipment_ware` condition.

### Corroboration (not proof)
- X4: 9.00
- Status: shipped-source
- Source: `base/assets/props/WeaponSystems/standard/macros/turret_xen_l_laser_01_mk1_macro.xml`; `base/libraries/wares.xml`
- Live test: no — untested as of 2026-08-31
- Finding: The standard macro on the same component is a COMBAT_CANDIDATE in
  the current A3 census (as of commit `a9f215f`, after the multi-`<use>`
  no-`purposes` rule) through its ware's no-`purposes` dual-`<use>` entries.
  Shared component identity corroborates the result only; it is not its
  basis.

### Limitations
- COMBAT_CANDIDATE is a kind-level eligibility statement from the macro's and
  its declared bullet's own authored records: a conventional (non-missile)
  turret whose declared weapon is a damaging long-range weapon. It does not
  establish where or whether the macro is deployed: nothing in the shipped
  source references it and no ware maps to it.
- Engine-side behavior is not verifiable offline; no live-test claim is made.
- The A3 classifier still reports UNRESOLVED/`no_exact_equipment_ware` for
  this macro because the purpose channel it reads is the equipment ware; this
  entry records that the macro's own authored records supply kind-level
  evidence the ware channel cannot reach.
- The cached A3 baseline artifact
  `.x4-research-cache/issue72-a3-correction-census.json` predates the
  multi-`<use>` rule (it records the standard macro UNRESOLVED) and spells
  the no-ware reason `NO_EXACT_EFFECTIVE_WARE_MAPPING`; the current
  classifier at `a9f215f` emits `no_exact_equipment_ware`.

### Candidate rule (inference; not applied to any other macro)
- X4: 9.00
- Status: inference
- Source: derived from the four shipped-source records above (the macro file, its declared bullet file, the all-8-set reference enumeration, and the ware channel record); no separate source
- Live test: no — untested as of 2026-08-31
- Finding: For no-ware turret macros, the macro's own file plus the file of
  the bullet it declares may supply kind-level evidence of what the macro is,
  even when no equipment ware maps to it. Recorded as a candidate general
  rule only; every macro entry in this reference is determined from that
  macro's own authored records, and this rule is not used to classify any
  macro.

## `turret_xen_l_plasma_01_mk1_story_macro` — COMBAT_CANDIDATE

Identity: macro `turret_xen_l_plasma_01_mk1_story_macro`; component
`turret_xen_l_plasma_01_mk1`; source set `base`; A3 census reason as emitted
by the current classifier (at commit `a9f215f`): `no_exact_equipment_ware`.

Result: **COMBAT_CANDIDATE** — the macro's own authored records identify it
as a conventional weapon turret declaring a damaging plasma weapon, and its
authored use context is dedicated capital-ship turret mounts; nothing in its
authored context expresses a non-combat purpose.

### The macro is an authored conventional weapon-turret prop
- X4: 9.00
- Status: shipped-source
- Source: `base/assets/props/WeaponSystems/heavy/macros/turret_xen_l_plasma_01_mk1_story_macro.xml`
- Live test: no — untested as of 2026-08-31
- Finding: The file defines one `<macro>` of that name with
  `class="turret"`, referencing component `turret_xen_l_plasma_01_mk1`,
  declaring its own dedicated bullet class
  `bullet_xen_turret_l_plasma_01_mk1_story_macro`, and carrying combat
  damage-effect slots (low, medium, high). It additionally carries authored
  `alias` and `ref` attributes pointing at the standard macro
  `turret_xen_l_plasma_01_mk1_macro`; their runtime semantics are not
  verified offline and are recorded here as authored facts only. It sits in
  the `WeaponSystems/heavy/` macro set alongside the standard macro for the
  same component; the mining utility turrets are authored in the separate
  `WeaponSystems/mining/` set.

### The macro's declared bullet is a damaging plasma weapon
- X4: 9.00
- Status: shipped-source
- Source: `base/assets/fx/weaponFx/macros/bullet_xen_turret_l_plasma_01_mk1_story_macro.xml`
- Live test: no — untested as of 2026-08-31
- Finding: The bullet macro the turret declares references the standard
  Xenon plasma bullet component `bullet_xen_l_plasma_01_mk1` and carries a
  damaging weapon profile: damage value 2100, area damage 500, projectile
  speed 900, and the plasma impact and muzzle effects. It carries authored
  `alias` and `ref` attributes pointing at the standard turret bullet
  `bullet_xen_turret_l_plasma_01_mk1_macro` and declares no `<weapon>`
  element of its own. Nothing in its authored properties expresses a
  non-combat purpose; the corpus's utility channel is authored differently
  (the Argon mining turret bullet declares
  `<weapon system="weapon_mining" />` with base damage 50, a mining damage
  multiplier of 30, and attach-on-impact behavior).

### The macro is authored into dedicated capital-ship turret mounts
- X4: 9.00
- Status: shipped-source
- Source: `ego_dlc_timelines/assets/units/size_xl/macros/ship_xen_xl_mothership_01_a_macro.xml`
- Live test: no — untested as of 2026-08-31
- Finding: The Xenon XL mothership ship macro mounts the macro in its six
  dedicated large-turret connection slots `con_turret_large_01` through
  `con_turret_large_06` (connection `con_turret`) — an authored
  capital-ship weapon mount in the shipped DLC catalog.

### The macro has no equipment ware
- X4: 9.00
- Status: shipped-source
- Source: all 8 shipped X4 9.00 catalogs extracted to `.x4-research-cache/issue72-a2-sources/`
- Live test: no — untested as of 2026-08-31
- Finding: The macro name occurs exactly seven times across all 8 shipped
  source sets: once in its own definition file and six times in the
  mothership mounts above; under `libraries/` the name occurs zero times in
  every set. The equipment channel for this weapon system is ware
  `turret_xen_l_plasma_01_mk1` in `base/libraries/wares.xml`, whose
  `<component ref>` points at the standard macro
  `turret_xen_l_plasma_01_mk1_macro`, not at the story macro; the ware
  grants `xenon` and `player` entries with no `purposes`. The story macro
  therefore has no authored ware access channel — the A3
  `no_exact_equipment_ware` condition.

### Corroboration (not proof)
- X4: 9.00
- Status: shipped-source
- Source: `base/assets/props/WeaponSystems/heavy/macros/turret_xen_l_plasma_01_mk1_macro.xml`; `base/assets/fx/weaponFx/macros/bullet_xen_turret_l_plasma_01_mk1_macro.xml`; `base/libraries/wares.xml`
- Live test: no — untested as of 2026-08-31
- Finding: The standard macro on the same component is a COMBAT_CANDIDATE in
  the current A3 census (as of commit `a9f215f`, after the multi-`<use>`
  no-`purposes` rule) through its ware's no-`purposes` dual-`<use>` entries;
  its bullet declares `<weapon system="turret_midrange" />`. Shared
  component identity and the macro's `alias`/`ref` linkage to the standard
  macro corroborate the result only; they are not its basis.

### Limitations
- COMBAT_CANDIDATE is a kind-level eligibility statement from the macro's,
  its declared bullet's, and its ship-mount record's own shipped-source
  records: a conventional (non-missile) turret declaring a damaging plasma
  weapon, authored into capital-ship turret mounts. It does not establish
  engine-side behavior; no live-test claim is made.
- The `alias`/`ref` attributes on the story macro and its bullet are
  recorded as authored facts; their runtime semantics are not verified
  offline and play no part in the result.
- The story bullet declares no `<weapon>` element of its own; the
  weapon-system classification rests on the macro's `class="turret"`, the
  bullet's damaging plasma profile, and the authored mount context — not on
  a weapon-system declaration inside the story records.
- The A3 classifier still reports UNRESOLVED/`no_exact_equipment_ware` for
  this macro because the purpose channel it reads is the equipment ware;
  this entry records that the macro's own authored records supply kind-level
  evidence the ware channel cannot reach.
