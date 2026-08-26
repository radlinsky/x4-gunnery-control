# Mission Director, AI, and XSD evidence

## XSD lookup

### Follow the MD schema include chain from the extracted tree
- X4: 9.00
- Status: shipped-source
- Source: `md/md.xsd`
- Live test: no — untested as of 2026-08-03
- Finding: begin at `md/md.xsd` and retain relative includes/imports such as
  `../libraries/md.xsd` and its dependencies. Copy only that recursive tree to
  an explicit ignored cache; never unpack catalogs into the repository.

### Pair `?` with a value or type check before object-event registration
- X4: 9.00
- Status: shipped-source
- Source: `md/story_paranid.xml:7644`; `libraries/common.xsd`
  (`event_object_destroyed`)
- Live test: no — the operator interpretation is untested as of 2026-08-08
- Finding: shipped MD uses `$MainPlayerShip? and $MainPlayerShip != null`
  before dereferencing the variable. Treat `?` as a declaration/existence
  guard, not proof that the value is non-null; that semantic interpretation is
  an inference from the shipped idiom. Before activating an object event such
  as `event_object_destroyed`, require a non-null or
  `typeof ... == datatype.component` value as well. When teardown removes the
  variable, make any queued-event action guard definition-safe too.

### Rename a cue when moving it across the hierarchy of a save-persistent script
- X4: 9.00
- Status: live-tested
- Source: X4 9.00 Steam `debug.log`, 2026-08-08 R2 fresh process loading a
  disposable save from the prior `X4GunneryControl` cue hierarchy
- Live test: yes — reproduced once on 2026-08-08 with commit c79b0f6 and runtime
  marker `2026-08-08-target-watch-fix`
- Finding: moving `TargetDestroyed` from a direct child to a nested watcher while
  retaining its name produced `Duplicate cue name TargetDestroyed` on save load,
  even though the new XML contained only one cue with that name. Saved MD state
  colliding with the moved definition is an inference; the direct observation is
  the duplicate-name error. Give a moved cue a new unique name and verify it by
  loading the same save in a fresh process.

## Turret firing solutions from MD

### Behemoth E Front Upper Mid uses `con_turret_m_03` and `_04`
- X4: 9.00
- Status: shipped-source
- Source: `assets/units/size_l/ship_arg_l_destroyer_02.xml:490-500`;
  `libraries/loadouts.xml:405-446` (`scenario_combat_arg_destroyer`)
- Live test: no — the corrected singular assignments are not yet reproduced
- Finding: Behemoth E macro `ship_arg_l_destroyer_02_a_macro` references hull
  component `ship_arg_l_destroyer_02`. Its two `group_front_up_mid` medium
  turret connections are exactly `con_turret_m_03` and `con_turret_m_04`.
  Names such as `con_turret_005` and `con_turret_006` do not occur on this hull.
  The same hull exposes engines `con_engine_01..03`, large shields
  `con_shield_l_01..03`, and two medium shields in `group_front_up_mid`; those
  engine, shield, software, and thruster selections match the shipped
  `scenario_combat_arg_destroyer` loadout. The `_02` Argon M beam and plasma
  components expose `turret medium standard hittable component combat` tags,
  matching the hull's `combat hittable medium missile standard turret` slots
  on the relevant compatibility dimensions.

### Colossus E exposes eight STANDARD/HITTABLE medium turret groups of two slots each
- X4: 9.00
- Status: shipped-source
- Source: `assets/units/size_xl/ship_arg_xl_carrier_02.xml:707-808` (component
  referenced by `assets/units/size_xl/macros/ship_arg_xl_carrier_02_a_macro.xml`);
  group-name corroboration `libraries/loadouts.xml` (`scenario_combat_arg_carrier_02`)
- Live test: no — source enumeration only, as of 2026-08-23
- Finding: the Colossus E component has exactly 76 connections, of which 17 are
  turret connections: 16 medium plus 1 large, and there are no `small` tagged
  connections. All 16 medium connections carry the exact tag set
  `combat hittable medium missile standard turret`; the large one
  (`con_turret_l_01`) carries `combat large missile standard turret` (no
  `hittable`). The 16 medium connections form exactly eight groups of two.
  Raw group IDs carry padding whitespace; the vanilla Colossus loadout
  references all eight names in trimmed form, so the trimmed name is the
  usable group ID:

  | raw group ID (exact) | connections | position (x / y / z, m) |
  |---|---|---|
  | `"        group_front_right_down  "` | `con_turret_m_09`, `con_turret_m_01` | +270.40 / −24.62 / +720.62, +808.64 |
  | `"       group_front_left_up "` | `con_turret_m_06`, `con_turret_m_14` | −295.70 / +118.89 / +720.62, +808.64 |
  | `"       group_front_right_up  "` | `con_turret_m_08`, `con_turret_m_16` | +295.70 / +118.89 / +720.62, +808.64 |
  | `"       group_front_left_down  "` | `con_turret_m_07`, `con_turret_m_15` | −270.40 / −24.62 / +720.62, +808.64 |
  | `"      group_rear_left_up "` | `con_turret_m_02`, `con_turret_m_10` | −372.95…−372.98 / +116.31…+116.38 / −616.02, −535.32 |
  | `"       group_rear_right_up "` | `con_turret_m_03`, `con_turret_m_11` | +372.95…+372.99 / +116.31…+116.37 / −616.02, −535.32 |
  | `"      group_rear_left_down  "` | `con_turret_m_04`, `con_turret_m_12` | −343.86…−343.88 / −48.63…−48.71 / −616.06, −535.22 |
  | `"       group_rear_right_down  "` | `con_turret_m_05`, `con_turret_m_13` | +343.85…+343.89 / −48.64…−48.71 / −616.06, −535.22 |

  Geometry, with +Z the bow and +Y up: front groups at z≈+721/+809 m, rear
  groups at z≈−535/−616 m (each group's two slots are ~88 m apart front, ~81 m
  apart rear, longitudinally); `*_up` groups at y≈+116…+119 m (upper deck),
  `*_down` at y≈−25…−49 m; left is negative x, right positive x. The L turret
  sits at (0, +159.33, −245.59). Front mount quaternions are near-identity
  with a mirrored ~10° tilt about the longitudinal axis, e.g.
  `con_turret_m_06` `qx=-8.47e-08 qy=3.147e-07 qz=-0.08715479 qw=-0.9961948`,
  `con_turret_m_08` `qx=-1.38e-07 qy=2.952e-07 qz=0.08715667 qw=-0.9961947`.
  The bow assignment (+Z = front) is an inference, not a coordinate
  document: the Behemoth E's bow main guns `con_weapon_01/02` sit at z=+327.6
  (`assets/units/size_l/ship_arg_l_destroyer_02.xml:526-530`), and Egosoft's
  own `group_front_*` / `group_rear_*` names here agree with that reading.
- Fixture-design inference, not an engine claim: for #67 the pair
  `group_front_left_up` (beam) + `group_front_right_up` (plasma) is the
  simplest choice — both on the upper deck, in the bow hemisphere, mirrored
  across the centerline, so one forward target placement can exercise both
  groups without repositioning the ship.

### Colossus E live-mounts the `_02_mk1` beam and plasma; `_01_mk1` rejection remains inferred
- X4: 9.00
- Status: live-tested
- Bound: the `_02_mk1` positive is live-tested on Colossus E. The `_01_mk1`
  negative is still inferred from shipped tag geometry and was not live-tried.
- Source: `assets/props/WeaponSystems/energy/turret_arg_m_beam_02_mk1.xml:328`
  (socket `con_beam_turret_01`), `assets/props/WeaponSystems/heavy/turret_arg_m_plasma_02_mk1.xml:331`
  (socket `con_plasma_turret`); macros `turret_arg_m_beam_02_mk1_macro` and
  `turret_arg_m_plasma_02_mk1_macro` (each a `class="turret"` macro referencing
  exactly that component); negative: `assets/props/WeaponSystems/energy/turret_arg_m_beam_01_mk1.xml:11`
  and `assets/props/WeaponSystems/heavy/turret_arg_m_plasma_01_mk1.xml:11`; family
  census over all Argon M/L turret components in `01.cat`; vanilla loadouts
  `scenario_combat_arg_carrier_02` and `scenario_combat_arg_destroyer` in
  `libraries/loadouts.xml`; controlled Test Lab runs
  `issue-67-arc-barrel-two-phase-r3` at `f230345` and r9 at `b751b4f`, game
  `debug.log`, 2026-08-24
- Live test: yes — two fresh X4 processes produced the exact operational
  Colossus census of two `turret_arg_m_beam_02_mk1_macro` and two
  `turret_arg_m_plasma_02_mk1_macro` in the intended four slot paths, with no
  other weapons or missile turrets. In r9 all four emitted FIRED events and
  produced attributed hits on the clear A control.
- Finding: the positive compatibility is no longer inference: the exact
  `_02_mk1` pair mounts and fires on Colossus E. The tag facts that predicted it
  are shipped-source: the slot tag set
  `combat hittable medium missile standard turret` matches
  `turret_arg_m_beam_02_mk1` (socket tags
  `turret medium standard component hittable combat`) and
  `turret_arg_m_plasma_02_mk1` (socket tags
  `turret medium standard hittable component combat`) on every
  tag-comparison axis: kind `turret`, size `medium`, generation `standard`,
  durability `hittable`, and a weapon-family axis on which the slot
  advertises BOTH `combat` and `missile` and the equipment carries `combat`.
  The extra `component` tag appears only on equipment sides. The compatibility
  rule inferred from those tags remains **inference** (matching is engine-side
  C++ and no shipped script states it): the family axis is two-valued on the
  slot and single-valued on the
  equipment — Argon M missile turrets (`turret_arg_m_guided_02_mk1`,
  `turret_arg_m_dumbfire_02_mk1`) are tagged `turret medium missile component
  hittable standard` (no `combat`) and the vanilla Colossus loadout mounts
  them in these very front groups, while the energy/heavy M turrets (beam,
  plasma, laser, flak, gatling, shotgun `_02_mk1`) carry `combat` without
  `missile`, and the vanilla Behemoth loadout mounts the M laser in the
  identical slot tag set. Subset matching in either direction is therefore
  false for these slots; missing `missile` (or `combat`) on the equipment side
  does not exclude it. L-slot evidence matches the same model: the
  `combat large missile standard turret` slots accept `turret_arg_l_beam_01_mk1`
  (`turret large standard component combat`, no `hittable`, none required by
  the slot) and `turret_arg_l_guided_01_mk1` / `turret_arg_l_dumbfire_01_mk1`
  (`turret large missile component standard`). The `_01_mk1` rejection — and
  the "only the `_02_mk1` fits" conclusion built on it — is inference, not
  engine fact: the `_01_mk1` beam and plasma sockets are tagged
  `advanced combat component medium turret unhittable`, wrong on both the
  generation axis (`advanced` vs `standard`) and the durability axis
  (`unhittable` vs `hittable`), and the Colossus hull has no `advanced`
  connection tags at all; under the inferred rule only the `_02_mk1`
  standard/hittable variants can fit these slots on this hull.

### Issue #67 zero-barrel premise did not reproduce for the tested `_02` M turrets
- X4: 9.00
- Status: live-tested
- Source: Behemoth E issue-67 spawn-time preflight, full-restart run on SHA
  `d7e3870`; Colossus E run `issue-67-arc-barrel-two-phase-r9` at `b751b4f`,
  game `debug.log`, 2026-08-24
- Live test: yes — the same exact beam/plasma macros reported nonzero barrel
  positions on Behemoth E and on an operational Colossus E in separate X4
  processes; the Colossus turrets also fired and hit the clear A control
- Finding: at spawn-time preflight the tested `_02` Argon M turrets reported
  clearly nonzero `weapon.barrelposition` — beam ≈ `(-2.39787, 2.59794,
  2.69955)`, plasma ≈ `(-2.44541, 2.47571, 3.40943)` — on both hulls. The r9
  values then changed substantially as the Colossus turrets trained on A, B,
  and C; for example, the settled A values were approximately
  `(-2.68, 5.64, 6.06)` for the beams and `(-4.24, 5.76, 5.84)` for the
  plasmas. Thus the exact zero/degenerate premise in #67 is a reproduced
  negative for these macros, and `barrelposition` must not be assumed static.
  No speculative production line-of-fire change follows from a zero-barrel
  condition that was not observed.
- Bound: the nonzero result is macro-specific. The changing Colossus values
  were observed in one r9 session and are experimental as a claim about their
  exact relationship to turret animation; reproduce that behavior before
  generalizing it to other turrets or hulls.

### A remote operational station can receive exact turret and shield equipment synchronously
- X4: 9.00
- Status: live-tested
- Source: `libraries/common.xsd:24586-24614` (`apply_loadout`; `object` is
  documented as either a ship or a station module); controlled Test Lab runs
  `issue-67-arc-barrel-two-phase-r5`, r6, and r9, game `debug.log`, 2026-08-24;
  fixture implementation
  `testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_scenario.xml`
- Live test: yes — r6 and r9 reproduced the successful exact census in two
  fresh X4 9.00 processes from the same disposable save;
  the player began in Two Grand while Test Lab created the station in
  Hatikvah's Choice I, then the player teleported to the remote fixture
- Finding: local station creation is NOT required for the tested path.
  `create_station sector=... state="componentstate.operational"
  constructionplan="'xen_defence'"` created the five-module shell remotely.
  Test Lab selected one operational
  `xenon_small_station_01_base_macro` module and applied an exact loadout to
  that MODULE, not the station root. In both r6 and r9 the immediate
  same-action-list census was exactly 5 modules, 2
  `turret_xen_m_laser_02_mk1_macro` standard lasers,
  4 `shield_xen_m_standard_02_mk1_macro` shields, 0 missile turrets, and 0
  engines. A cue delayed by 1 ms reported the same census while still remote;
  the post-teleport in-system census also matched and returned `equipped=1`.
  Thus neither local creation nor a later MD tick was needed for this exact
  station-module loadout. The geometry test still failed independently because
  all four shooter turrets reported the same arc classification for station
  root and aim point (`splits=0`).

  The r5 rejected control matters: the four shields appeared immediately, but
  a group-targeted `turret_xen_m_gatling_01_mk1_macro` request produced no
  turrets at any phase. Shipped source marks that gatling `integrated="1"` and
  uses it through singular path-targeted `<turret>` entries; the successful
  standard laser is non-integrated and is used through group-targeted
  `<turrets>` entries. It is therefore a source-backed compatibility candidate,
  not evidence that remote turret creation failed. Scope remains one
  `xen_defence` module and these exact macros; arbitrary module/loadout
  combinations remain untested.

### Vanilla populates `md.$EquipmentTable` and applies generated station loadouts per module
- X4: 9.00
- Status: shipped-source
- Source: `md/setup.xml:85-99` initializes `md.$EquipmentTable` and includes
  `faction.xenon`; `md/finalisestations.xml:114-135` reads that pool, generates
  per-sequence-entry loadouts, and applies each by sequence/index;
  `libraries/constructionplans.xml` plan `id="xen_defence"`; historical Test Lab
  revision `5444018` generated with `macro="$Station.macro"
  module="$Module.macro"` and applied with `object="$Module"`
- Live test: partial — the historical local 2026-08-13 run reported five
  modules, 120 turrets, and 60 shields; r6 independently proves the exact
  module-object application route remotely, but the full generated faction
  loadout was not repeated remotely
- Finding: the prior statement that `md.$EquipmentTable` was populated nowhere
  was false; it confused this repository's assignments with the vanilla MD
  global established during game setup. The `xen_defence` plan contains one
  dock module and four `xenon_small_station_01_base_macro` defence modules.
  Equipment slots live in each module component, and `apply_loadout object=`
  must target a station module. For a full faction loadout, either use the
  vanilla construction-sequence generation/application route or iterate the
  operational modules, generate for each station/module macro pair, and apply
  the result to that module. For a bounded deterministic fixture, construct an
  exact compatible loadout and apply it to the selected module directly; no
  `md.$EquipmentTable` lookup is needed for that exact route.

### Official extensions register loadout entries with a full root, and MD can consume an extension-defined ID
- X4: 9.00
- Status: shipped-source
- Source: installed official `ego_dlc_boron`, `ego_dlc_split`,
  `ego_dlc_terran`, `ego_dlc_pirate`, `ego_dlc_timelines`, `ego_dlc_mini_01`,
  and `ego_dlc_mini_02` `ext_03.cat!libraries/loadouts.xml`; in particular,
  `ego_dlc_mini_01/ext_03.cat!libraries/loadouts.xml` and
  `!md/story_hyperion.xml:1021,1034`
- Live test: no — source inspection only, as of 2026-08-23
- Finding: each of the seven installed official extensions that contains
  `libraries/loadouts.xml` declares a complete `<loadouts>` root with direct
  `<loadout id="...">` children; none uses a `<diff>` root in that file. The
  Hyperion Pack defines `story_hyperion_reward_special` in its own library and
  uses `<loadout ref="story_hyperion_reward_special"/>` inside its own MD
  `create_ship` actions. This proves the extension-defined-ID route, including
  the full-root registration shape, in current shipped content. The MD schema
  also describes `get_loadout` as lookup by ID and accepts an optional macro
  (`libraries/common.xsd:24489-24523`).
- Load-order bound: an extension must be enabled and meet its base-version
  dependency. `content.xml` comments in the installed official extensions say
  dependencies are loaded first; use an explicit dependency when one extension
  consumes content supplied by another. The official same-extension library/MD
  pair has no self-dependency, so the inspected source does not establish any
  additional intra-extension ordering declaration.

### Issue #67 custom static named loadout resolves and applies its per-group turret census on the Test Lab route
- X4: 9.00
- Status: live-tested
- Source: full-restart Issue #67 run on SHA d7e3870 (superseding an earlier
  2026-08-23 run); installed
  `extensions/x4_gunnery_control_testlab/libraries/loadouts.xml` matching the
  repository file; Test Lab MD
  `x4_gunnery_control_testlab_scenario.xml:376-432`
- Live test: yes — a full-X4-restart run reached the `static_ref` branch and
  created a Behemoth E (macro `ship_arg_l_destroyer_02_a_macro`) using
  `<loadout ref="x4gc_testlab_issue67_behemoth_arc_barrel"/>`; the resulting
  ship reported the exact expected census — weapons=4, turrets=4, beam=2,
  plasma=2, loadout_failures=0. An EARLIER 2026-08-23 run had reported 0
  weapons and 0 turrets with no identified log error; that zero result is
  unexplained and is SUPERSEDED by this later full-restart run.
- Finding: a static `<loadout ref>` to a full-root, extension-defined loadout
  DOES resolve and apply its per-group turret census on this Test Lab route.
  The earlier zero-turret run is treated as an unexplained EARLIER run, not a
  route failure. Established for the Behemoth E macro; no other hull has been
  live-mounted on this route.
- Bound: proves the route resolves and applies for this loadout/macro pair;
  does not establish the cause of the earlier zero run, nor generalize the
  per-group census result to any other hull (e.g. Colossus compatibility
  remains inference).

### Issue #67 static-ref structure matches the shipped registration shape and the route is now shown to work
- X4: 9.00
- Status: inference
- Bound: source comparison plus the live-tested result above; no source
  inspected exposes the engine's loadout-registration diagnostic or the
  per-entry apply decision, so the cause of the earlier zero run stays unknown
- Source: Test Lab `libraries/loadouts.xml:5-31`; vanilla
  `libraries/loadouts.xml:405-451`; official extension census in the preceding
  record
- Live test: no — this is an inference from the current source and the
  live-tested run above, not a new reproduction
- Finding: the Test Lab file uses the same full `<loadouts>` root and direct
  ID form as official extensions, and its ID is referenced inside the
  corresponding `create_ship`, as in shipped scenarios. Its macro,
  engine/shield paths, and `groups` form also have shipped counterparts. The
  live-tested run above shows the route resolves and applies the per-group
  census, so the earlier zero result is not attributable to a structural
  registration or application defect on the current evidence; its cause is not
  source-proven and no root cause is claimed. The pre-spawn MD `get_loadout`
  probe (custom ID plus a shipped control ID, logging whether each result is
  present) remains staged to separate ID lookup/registration from a later
  create/apply outcome should the earlier zero ever recur. Do not infer a
  corrective XML change from the current evidence.

### Singular-turret loadouts are unreliable on the Behemoth E (both transient and static-ref routes)
- X4: 9.00
- Status: live-tested
- Source: Test Lab `debug.log` at game times 248864.65 and 249183.19 on
  2026-08-23 (transient route); Issue #67 r14 arc-survey Create at game time
  248874.28 on 2026-08-25 (static-ref route), `debug.log`
  `[X4GC TEST] action=failed ... loadout_failures=1 ... plasma=0 shooter_turrets=0`;
  `x4_gunnery_control_testlab_scenario.xml`,
  `libraries/loadouts.xml`
- Live test: yes — three creation attempts across two X4 processes; the
  2026-08-23 pair used source-verified `con_turret_m_03`/`con_turret_m_04`, and
  the 2026-08-25 run used a static named `<loadout ref>` with one singular
  `<turret macro="turret_arg_m_plasma_02_mk1_macro" path="../con_turret_m_04"/>`
- Finding: a singular per-slot `<turret ... path="..."/>` entry produces an
  EMPTY Behemoth E on BOTH loadout routes. The transient route — an MD
  `<create_loadout>` result through
  `<create_ship><loadout loadout="$Issue67BehemothLoadout"/></create_ship>` —
  produced zero operational engines, shields, weapons, and turrets (correcting
  the paths did not help). The static named-loadout `ref` route — proven to
  equip this hull cleanly when its turrets are mounted as GROUP-TARGETED
  `<turrets group="..." exact="N"/>` entries (see the arc-barrel static-ref
  result above, turrets=4) — ALSO failed (`loadout_failures=1`, empty shooter)
  the moment a single turret was moved to a singular `<turret path>` entry under
  `<macros>`; replacing it with
  `<turrets macro="turret_arg_m_plasma_02_mk1_macro" group="group_front_up_mid" exact="2"/>`
  under `<groups>` is the fix. So the defect is specific to singular `<turret>`
  entries, not the loadout route: shipped `scenario_combat_arg_destroyer`
  (`libraries/loadouts.xml:405-451`) mounts every turret via `<turrets group=>`
  and mounts only engines, large shields, and main `<weapon>` guns via singular
  `<... path>` under `<macros>`. Consequence: a group with two medium slots
  (`group_front_up_mid` = `con_turret_m_03` + `con_turret_m_04`) can only be
  armed with two identical turrets; isolate the one under test by per-turret hit
  attribution, not by mounting a single slot. Bound: established for the
  Behemoth E macro `ship_arg_l_destroyer_02_a_macro`; not generalized to other
  hulls.

### Per-turret firing solution is computable from MD
- X4: 9.00
- Status: shipped-source
- Source: `schemas-9.00/libraries/common.xsd:21691` (the `check_line_of_sight` action element); combat range gates `aiscripts/move.attack.object.capital.xml:656,657` (main target) and `:680,681` (station module); the sole mining-approach range gate `aiscripts/mining.collect.ship.capital.xml:229,230`; distance/size property docs `props-9.00/libraries/scriptproperties.xml:66,76,80`
- Live test: no — untested as of 2026-08-09
- Finding: `check_line_of_sight` is an MD/AI action that performs ray casts. Its `object` attribute accepts a turret component, so line of sight can be tested per individual turret against a target. Attributes include `object`, `objectoffset`, `target`, `targetoffset`, `useaimtarget`, `excludeself`, and `name`. Setting `useaimtarget="true"` uses the object's aim targets as the raycast destination, consistent with weapon aiming.
- **Range geometry — CORRECTED 2026-08-18 against the extracted X4 9.00 tree.** The original text claimed both combat and mining AI define "this turret can engage this target" as line of sight AND `turret.distanceto.{target} + (target.size/2) < turret.maxfirerange`. That attributed the MINING form to combat. Shipped source shows two different range tests:
  - **Combat weapon-fire reachability** — capital-ship combat script, `aiscripts/move.attack.object.capital.xml:656`: `$locweapon.bboxdistanceto.{$target} le $locweapon.maxfirerange`, with `check_line_of_sight` at `:657`; the station-module branch repeats the same test against a module component (`:680`, LOS at `:681`). The distance is bounding-box-to-bounding-box, compared directly against `maxfirerange`, with NO size term. The loop iterates `weapons.operational.list` (`:644`), and turrets are stripped from it unless `$frontweapon == 3` (`:648`).
  - **Asteroid-mining approach** — `aiscripts/mining.collect.ship.capital.xml:230`: `($turrets.{$i}.distanceto.{$target} + ($target.size/2)) lt $turrets.{$i}.maxfirerange`, after `check_line_of_sight` at `:229`, over the ship's mining-mode turrets found at `:224`. This is the ONLY `distanceto + size/2` range gate in the shipped AI tree: a full census (`grep -rn maxfirerange` over `aiscripts/` and `md/`) finds the property on exactly five lines in exactly these two files — `move.attack.object.capital.xml:647,656,679,680` and `mining.collect.ship.capital.xml:230`. The gate answers "can any mining turret mine this asteroid from the current approach position"; if none passes, the ship keeps moving (`:236`).
  - Property semantics, `props-9.00/libraries/scriptproperties.xml`: `distanceto.{$component}` is "Distance to other component" (`:76`) — the point distance; `bboxdistanceto.{$component}` is "Distance from this component's bounding box to other component's bounding box" (`:80`); `size` is "Size (based on bounding box)" (`:66`). Shipped scripts treat `size/2` as an object's radius: `move.gate.xml:622` labels `$exitgate.size / 2.0` "gate radius", and `move.attack.object.capital.xml:586` subtracts `$target.size/2m` from `distanceto` to form a surface distance. **Inference** (anchored in those shipped usages, not stated in the property docs): the combat form measures the NEAR-surface gap between the two bounding boxes, while the mining form adds the target's radius to the center distance — i.e. the distance to the target's FAR edge, passing only if the asteroid's whole bounding extent fits inside `maxfirerange`. The two forms can differ by up to a full target size; the mining form is the stricter.
  - Egosoft's own caveat on the combat form (`move.attack.object.capital.xml:409`): "NB: accuracy of bboxdistanceto depends on which object is bigger"; their movement code therefore forms distances as `bboxdistanceto.[$sector,$position] - target.size/2m` (`:410`).
- Vanilla does NOT perform any separate gimbal or traverse-arc test; LOS from the weapon component plus the applicable range test is the engine's own working definition of a firing solution. The vanilla loops answer only "does ANY weapon (combat) / ANY mining turret (mining) have a solution" — both break on the first hit — so an N-of-total count is strictly more expensive than anything shipped code does.
- Scope of that claim, added 2026-08-10 so it is not over-read: this establishes what VANILLA computes, from shipped source. It has never been run by this project and says nothing about detecting the LINE OF FIRE BLOCKED condition — a turret trained on a target with the ship's OWN hull in the line of fire. Whether `check_line_of_sight` can answer that is UNRESOLVED and untested: the ray from a turret to its target begins inside the firing ship's own hull, so `excludeself` plausibly decides the result in both directions (true and it cannot see own-hull masking at all; false and it may report every shot blocked), but the exact `excludeself` semantics have not been verified against the engine. Not pursued, because LINE OF FIRE BLOCKED was confirmed live on 2026-08-09 to be unrecoverable regardless — the engine's preferred-target fallback never rolls off a LINE OF FIRE BLOCKED target, so knowing the condition would not let a mod act on it. Do not cite this entry as evidence either that the technique works for LINE OF FIRE BLOCKED or that it cannot.
- RESOLVED 2026-08-11, the `excludeself` half only: `excludeself="false"` is useless
  from a turret mounted on the firing ship. In a Test Lab capture that called both
  variants back to back on the same turret/target pair every sample,
  `excludeself="false"` returned blocked on **7252 of 7252** per-turret
  measurements — zero exceptions, including turrets with an obviously clear
  open-space shot. `excludeself="true"` over the identical samples discriminated:
  5449 clear, 1803 blocked. The second branch predicted above ("false and it may
  report every shot blocked") is what happens; the ray evidently starts inside the
  firing ship's own collision hull and self-terminates. Only `excludeself="true"`
  carries information. Evidence class: first-party live capture, n=1 ship
  ("Ray", 14 turrets, ids `0x6c2bc`-`0x6c2cf`), n=1 session of ~10 minutes free
  play, X4 9.00, logger
  `testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_observe.xml`
  (call sites `:244-245`), captured to `debug.log`. Not shipped-source; not
  reproduced on a second ship or a second session.
- Still UNRESOLVED after that capture: everything above about LINE OF FIRE BLOCKED. The capture
  did not stage a LINE OF FIRE BLOCKED condition, and it never established what
  `excludeself="true"` blocked results actually correspond to. Do not read
  "1803 blocked" as "1803 masked".
- WHY it behaves that way, added 2026-08-11 from shipped source (not live-tested):
  the schema contradicts itself about this attribute. `common.xsd:21722` declares
  `<xs:attribute name="excludeself" ... default="false" use="optional">`, while
  the `xs:documentation` three lines below it (`:21725`) says "True by default."
  The 7252/7252 blocked result is consistent with the XSD `default="false"` being
  the operative behaviour and self-collision then dominating every ray. Practical
  rule: never rely on the default here. Pass `excludeself` explicitly on every
  `check_line_of_sight` call, because the two halves of the schema disagree about
  what omitting it means.
- Dead lead, recorded 2026-08-11 so it is not chased again (shipped-source):
  `useaimtarget` does NOT give the shooter's aim direction. Aim targets belong to
  the object BEING SHOT AT — they are hittable points on the victim's mesh.
  The attribute on `check_line_of_sight` (`common.xsd:21715`) is documented at
  `:21718` as "an object's aim targets ... will be used as the raycast target",
  and `create_orientation`'s copy of the attribute (`:24127`, documented `:24130`)
  says "the refobject's aim targets ... will be used as the reference point".
  The attribute name invites the opposite reading and this project acted on it;
  it selects a destination, never an origin or a bore direction.

### Missile guidance is a shipped fire-control discriminator, but missile-turret launch LOS is engine-side
- X4: 9.00
- Status: shipped-source
- Source: `props-9.00/libraries/scriptproperties.xml:1443,1455,1463,2150`
  (`weapon.ammo.macro`, `weapon.isguided`, the `missileturret` datatype, and
  `macro.isguided`) and
  `aiscripts/fight.attack.object.bigtarget.xml:398-425,993-1117` (fixed-launcher
  guidance branches). A full `check_line_of_sight` census over shipped
  `aiscripts/` finds the action in exactly five scripts: lockbox collection,
  mass-traffic police/watchdog, capital mining, and capital movement/attack;
  none is the missile firing path.
- Live test: no — this record is the shipped-source boundary; see the following
  live record for guided missile turrets.
- Finding: loaded ammunition exposes its missile macro and `isguided` flag.
  Vanilla uses that flag as a real fire-control discriminator for fixed missile
  launchers: an unguided launcher tightens ship aim tolerance to 4 degrees
  against capitals or 8 degrees otherwise, while guided missile handling takes
  separate branches. Turret weapons are explicitly skipped by that ship-aim
  calculation, so shipped scripts do not reveal the engine's missile-turret
  launch test. There is no shipped AI-script LOS gate that can be copied as a
  missile-turret rule.
- Design consequence (inference, now partly corroborated by the live record
  below): do not apply the conventional direct muzzle-to-target ray uniformly
  to missile turrets. Guidance is the available discriminator. Missing ammo or
  modded ammo without affirmative `isguided` data must not be promoted to the
  guided branch.

### Guided missiles launch through an own-hull-masked direct ray and reach the designated surface
- X4: 9.00
- Status: live-tested
- Source: controlled Test Lab run 2026-08-23, scenario
  `issue-65-remote-odysseus-e-r1`, game `debug.log`; detailed run record in
  `testing-experiments.md`.
- Live test: yes — one X4 9.00 session, one player-owned Odysseus E, one Xenon K
  turret surface selected under `autoassist`.
- Finding: the initial simultaneous diagnostic against selected surface
  `0x18c351` returned `los=0` for all 16 missile turrets; 15 returned
  `los_noself=1`. Eight guided turrets whose direct rays were self-masked then
  emitted 16 attributed missile launches. Missile impact events landed on the
  designated surface (four `hitcomp=0x18c351`, including three while the
  designation was still active) and on adjacent components through splash.
  This establishes that a guided missile turret can have a valid launch and
  engagement path even when `check_line_of_sight excludeself="false"` rejects
  the direct muzzle ray. For an ENGAGEABLE predicate, a guided missile turret
  should retain bearing and range gates but must not require that direct ray.
- Boundary: R1 did NOT answer the unguided case. All seven dumbfire turrets were
  outside their elevation limits against the chosen surface. That question was
  subsequently resolved by the R2/R6 record below.

### Unguided missile turrets ignore own hull but retain an external direct-line check
- X4: 9.00
- Status: live-tested
- Source: controlled Test Lab runs 2026-08-23, scenarios
  `issue-65-remote-odysseus-e-r2` and `r6`, game `debug.log`; detailed run and
  rejected-control history in `testing-experiments.md`.
- Live test: yes — one exact player-owned Odysseus E loadout, clear Xenon K
  hull control and fully Asgard-masked Xenon P control.
- Finding: in the clear lane, three dumbfire components whose muzzle rays were
  blocked only by the Odysseus's own hull launched 92 missiles; all 92 exact
  missiles still existed after 500 ms while retaining the intended K target.
  In the final blocked lane, the P was wholly hidden by a solid Asgard, all
  seven dumbfire turrets were within range, and every exact muzzle ray returned
  `muzzle_los_ex=0`. ENGAGEABLE fell to 8/16: eight guided turrets that could
  bear remained eligible despite their equally blocked direct rays, while all
  seven dumbfire turrets were rejected and one guided turret was in CANNOT
  BEAR.
- Design consequence: for a missile turret, affirmative loaded-ammunition
  `macro.isguided` bypasses direct LOS while bearing/range remain mandatory.
  Unguided or missing-guidance ammunition retains direct LOS with
  `excludeself="true"`: ignore the firing ship's own hull, not external
  obstructions. This is verified for the tested vanilla Odysseus/loadout; do
  not upgrade it to a universal result for arbitrary hulls or modded missiles.

### Modular targets, attackable defence modules, and the per-module LOS fallback
- X4: 9.00
- Status: shipped-source
- Source: `props-9.00/libraries/scriptproperties.xml` — `.defensible` on `component` (`:35`, "Defensible context"), `ismodular` on `destructible` (`:171`), `.modules.<state>.{count,list}` on `defensible` (`:555-559`), `defencemodules` on `defensible` (`:640`), `defencemodule` datatype (`:1097`), `canhaveattackablemodules` on `ship` (`:812`) and the ship-macro variant on `macro` (`:2097`); `aiscripts/move.attack.object.capital.xml:664-694` (per-module LOS retarget fallback); `aiscripts/lib.target.selection.xml:306-347` (module acquisition); Allectus "Subsystem Targeting Orders" (ws_2437198154) `readme.txt:35-59` for the plain-English subsystem taxonomy.
- Live test: yes — the #62 root-only guard was confirmed in a live Test Lab session (surface-element ENGAGEABLE stopped over-counting) on 2026-08-19. The `canhaveattackablemodules` extension is shipped-source-derived and NOT yet independently live-confirmed on a ship that carries a defence module.
- Finding:
  - `.defensible` is a base `component` property returning the component's containing defensible context. For a surface element (a turret/shield/engine component) it resolves to the PARENT ship or station, not the element itself. On a whole-object root, `$target == $target.defensible` holds (vanilla treats the two interchangeably, e.g. `move.attack.object.capital.xml:718` passes `$target.defensible` where `$target` is the attack target). This equality is the reliable root-vs-sub-element discriminator.
  - Two DISTINCT engine notions of "has separately-targetable parts": `ismodular` is true for STATIONS built from modules (production/storage/dock/**defence**/build). `canhaveattackablemodules` is a **ship-only** property (`ship` datatype) — "true iff the ship is defined to contain a defence module which indicates it may have targetable modules". A `defencemodule` is its own component class (`type="module"`); the disc/tube/claim defence-platform structures, the Khaak hive cluster, and asteroid turret bases are `defencemodule`-class. `.defencemodules` lists them.
  - Vanilla's per-module LOS retarget fallback (`move.attack.object.capital.xml:664`) is gated ONLY on `$target.defensible.ismodular and modules.operational.count gt 1`; when the root ray is blocked it iterates modules and RETARGETS the weapon to the first visible one (`$target = $locmodule`, `:684`). It does NOT reference `canhaveattackablemodules`. The `canhaveattackablemodules` gate lives in higher-level TARGET SELECTION (`lib.target.selection.xml:306-347`), which acquires a module as the target via `find_module`/`find_object_component` with `match module="ismodular or canhaveattackablemodules"` — a different mechanism than the move-script's retarget.
  - That fallback is explicit AI-script retargeting, not proof that the
    engine-side shoot controller automatically converts a station-root
    `set_turret_targets` designation into a module designation. An ENGAGEABLE
    implementation may mirror the geometry as a design choice, but must not
    describe that approximation as observed engine behavior. Test
    root-to-module behavior by logging the exact designated component and the
    firing/hit component separately.
  - CONSEQUENCE for an ENGAGEABLE-style per-module fallback (#62): mirroring the vanilla `ismodular` fallback but running it against a player-selected SURFACE ELEMENT over-counts, because that element's `.defensible` is the whole modular station, so any weapon that can see ANY station module gets counted as engageable against the one element. Fix: gate the fallback on `$target == $target.defensible` (whole root only). Extending the gate with `or @$target.canhaveattackablemodules` (always `@`-guarded — the property errors on a non-ship, so a station root must read it via `@`) admits the rare capital ships that embed a defence module, matching vanilla target selection; it is inert where a ship's defence modules are not exposed through `.modules.operational.list`.
  - Subsystem taxonomy (Allectus mod, community `third-party-technique`, corroborates the engine grouping): SHIP subsystems are engines, missile launchers, S/M turrets, L/XL turrets, shield generators, and main (fixed) batteries; STATION subsystems are dock/storage/production/defence/shipyard modules. The mod also notes capital attackers only accept subsystems within line of sight at order start — the same LOS constraint this project models in ENGAGEABLE.

## Per-turret attribution from MD events

### `event_object_attacked_object` documents a firing WEAPON, but the runtime value is kill-method-dependent
- X4: 9.00
- Status: shipped-source
- Source: `schemas-9.00/libraries/common.xsd:13055` (the event element; its
  `xs:documentation` at `:13058` reads "object = attacker, param = attacked
  object, param2 = kill method, param3 = [attacked component, weapon]").
  Shipped proof the second element really is the weapon: `md/notifications.xml:1515`
  passes `event.param3.{2}` straight into `change_relation_on_attack weapon=`,
  whose `weapon` attribute is declared at `common.xsd:21620` (element at `:21611`)
- Live test: yes — ordinary turret hits have produced a turret component in
  controlled captures; missile-hit behaviour is split into the correction below.
- Finding: the event's `param3` is a two-element list, `[attacked component,
  weapon]`. Vanilla's own use corroborates the documented role:
  `notifications.xml` does not inspect or reinterpret `event.param3.{2}`, but
  forwards it as the `weapon` argument of a relation-change action. This is a
  HIT signal, delivered to a listener, rather than a property that can be
  polled. The schema does NOT guarantee that the runtime component is always an
  individual turret; the missile correction below is a demonstrated exception.
- **This supersedes the `lastattacker` dead end.** `lastattacker` is ship-scoped
  by design and cannot attribute a hit to a turret (live capture 2026-08-11, see
  the attacker-attribution record in `ui-lua-menu-camera.md`). Per-turret
  attribution can be available from event payloads rather than a property read,
  but the exact event must be validated for the kill method. Anyone landing on
  the negative result should come here and the missile exception below.
- Related but distinct, do not conflate: `md/x4ep1_mentor_subscription.xml:7138`
  tests `event.param3.isclass.bullet and event.param3.launcher`, but that is a
  condition on `event_player_ship_hit`, a different event whose `param3` is the
  BULLET itself rather than a two-element list. It is evidence for the
  `bullet.launcher` route below, not for this event's payload shape.

### `hitbymissile` reports the launcher ship, not the individual missile turret
- X4: 9.00
- Status: live-tested
- Source: controlled Test Lab run 2026-08-23, scenario
  `issue-65-remote-odysseus-e-r1`, game `debug.log`.
- Live test: yes — 16 launches from eight guided missile turrets and their
  subsequent impacts in one X4 9.00 session.
- Finding: for every observed `event_object_attacked_object` record with
  `method=hitbymissile`, `event.param3.{2}` resolved to Odysseus launcher ship
  `0x18c2de`, with `isturret=0`, rather than any of the missile-turret components
  named by the corresponding FIRED events. Therefore missile impacts cannot be
  attributed per turret through this payload. Use `event_weapon_fired` for the
  exact missile turret that launched; correlate later impact only at ship or
  missile-object level unless another live-verified identifier is available.

### `event_weapon_fired` fires per trigger pull and accepts a single weapon or a group
- X4: 9.00
- Status: shipped-source
- Source: `schemas-9.00/libraries/common.xsd:16836` (element; documentation at
  `:16839` reads "Event for the specified weapon firing (object = the weapon,
  param = fired bullet/missile/bomb)"). It takes the `objecteventsource`
  attribute group (`common.xsd:7155`), which supplies `object` (single) or
  `group`. Vanilla call sites, all group form:
  `aiscripts/move.attack.object.capital.xml:905`, `md/cinematiccamera.xml:3212`,
  `md/scenario_combat.xml:113` and `:300`
- Live test: yes for missile turrets — the 2026-08-23 run emitted 16 FIRED
  events naming eight exact guided missile-turret components.
- Finding: a mod can listen for the moment any specific weapon fires, scoped to
  one weapon or to a group it assembles. Turrets ARE weapons for this purpose and
  they DO appear in `<ship>.weapons.operational.list` — the proof is negative and
  strong: `move.attack.object.capital.xml:882` builds a group from that list and
  then at `:884-888` iterates in reverse REMOVING every member where
  `$locweapon.isclass.turret`, which is only necessary if turrets were in it.
  `md/cinematiccamera.xml:3104` does the same exclusion the other way, via
  `find_object_component class="class.weapon"` with a `<match class="class.turret"
  negate="true"/>` child. Both vanilla users of this event deliberately strip
  turrets out; a mod that wants turrets simply does not strip them.
- Bounded consequence: for ordinary turret projectiles where the hit payload
  has been verified to name the turret, listening to both events can yield a
  per-turret hit rate. Do NOT apply that design to missiles: the launch event is
  per turret, but `hitbymissile` reports the launcher ship (correction above).
- Missile correlation boundary (shipped-source): the FIRED payload gives a
  direct exact pair, `event.object` = missile turret and `event.param` = fired
  missile. That missile exposes `.target`
  (`props-9.00/libraries/scriptproperties.xml:894-897`), and
  `event_object_incoming_missile` also exposes the same missile in `param2` plus
  its target component in `param` (`common.xsd:14431-14444`). This directly
  links turret -> missile -> intended target at launch. It still does NOT link
  to an arbitrary-target impact: `event_object_attacked_object` omits the
  missile object for `hitbymissile`. `event_player_ship_hit` does include the
  projectile in `param3` (`common.xsd:15427-15440`), but only when the victim is
  the player-controlled ship or ship context. No general-target equivalent has
  been verified.
- Note on list choice: `weapons.operational.list` (used here) and
  `turrets.operational.list` are different enumerations, and neither includes
  missile turrets (see the `missileturrets` record below). Pick deliberately.

### `bullet.launcher` is the surviving route to a turret's real bore direction
- X4: 9.00
- Status: shipped-source
- Source: `props-9.00/libraries/scriptproperties.xml:891` (`launcher`, "Weapon
  that fired this bullet", on the `bullet` datatype declared at `:890`);
  `bullet` derives from `component`, so it carries `component.rotation` (`:58`).
  Vanilla reads the property at `md/x4ep1_mentor_subscription.xml:7138`
- Live test: no — read from shipped source, untested by this project as of 2026-08-11
- Finding: every bullet knows the weapon that fired it. Paired with
  `event_weapon_fired` (whose `param` IS the fired bullet), a mod can take the
  bullet's own `.rotation` at the moment of fire and attribute it to a specific
  turret via `.launcher`. That is a real bore direction, sampled per shot.
- Why this matters: it is the replacement lead for the refuted
  `$turret.rotation` route (record below). MD cannot ask a turret where it is
  pointing, but it can observe where a turret actually shot. The two are not
  equivalent — this samples only at trigger pulls, so a turret that is tracking
  but holding fire produces nothing, which is precisely the LINE OF FIRE BLOCKED case.
- Untested by this project. Whether `bullet.rotation` is populated usefully at
  event time, and whether the bullet is still valid when the handler runs, are
  both open.

### No per-turret current-target read exists anywhere in the 9.00 surface
- X4: 9.00
- Status: inference
- Bound: a negative result; it is only as strong as the search, so the search is
  recorded precisely below
- Source: recorded precisely, because for a negative result the bound IS the claim.
  MD `props-9.00/libraries/scriptproperties.xml` read in full for the relevant
  datatypes — `weapon` `:1441-1459`, `turret` (`:1461`, a bare alias
  `<datatype name="turret" type="weapon"/>` adding zero properties of its own),
  `destructible` `:162-189`, `component` `:12-160`, `defensible` `:426-652`,
  `componentslot` `:1471-1491`; the complete Lua FFI `ffi.cdef` surface of
  `ui-9.00` (57 `.lua` files contain an `ffi.cdef`, carrying 2713
  declaration lines and 1916 distinct function names, recounted 2026-08-11); and
  all 2493 names in `.x4-research-cache/exports/x4-exe-exports-9.00.txt`
- Live test: no — source search only, as of 2026-08-11
- Finding: there is no read-back of `set_turret_targets`, and no property or
  function anywhere that returns what an individual turret is currently shooting
  at. The entire turret/weapon getter set in the Lua FFI is
  `GetTurretGroupMode2`, `IsTurretGroupArmed`, `GetWeaponMode`, `IsWeaponArmed`,
  `GetCurrentAmmoOfWeapon`, `GetNumTurrets`, `GetTurret(size_t)` — modes, armed
  state, ammo, and enumeration, never a target. (`GetTurretGroupMode2` is the
  only form present — there is no unsuffixed `GetTurretGroupMode` in 9.00 — and
  `GetNumTurretSlots` sits beside `GetNumTurrets` at
  `ui-9.00/ui/core/lua/crosshair handling.lua:106-107`.) In the executable export
  list, all 48 names matching `target` case-insensitively are camera, radar,
  mission, render, softtarget, or transporter symbols. The two that look
  promising are not: `IsTargetInPlayerWeaponRange` is a range predicate on the
  player's current target, and `IsAutotargetingActive` is a global input-assist
  flag. Neither is per-turret, and neither returns a target.
- Why it does not exist: per-turret target selection runs in a C++ component that
  Egosoft's own comments call the "shoot controller"
  (`aiscripts/fight.attack.object.medium.xml:1362`,
  `aiscripts/fight.attack.object.capital.xml:2116`, and
  `aiscripts/fight.attack.object.bigtarget.xml:155`). Scripts write targets INTO
  it and never read back out; the autoassist comment at
  `fight.attack.object.capital.xml:1756` says acquisition "is handled in code".
  The asymmetry is deliberate, not an oversight.
- Consequence: any per-turret question must be answered from EVENTS
  (`event_object_attacked_object`, `event_weapon_fired`) rather than from polling.
  That is the structural reason the passive polling capture of 2026-08-11 failed
  (see `testing-experiments.md`).

### `weapon.barrelposition` is a muzzle position, not an aim direction
- X4: 9.00
- Status: shipped-source
- Source: `props-9.00/libraries/scriptproperties.xml:1452` ("The position of the
  weapon's barrel (may be 0,0,0 for weapons with no collision)", type `position`);
  vanilla's only meaningful use at `md/cinematiccamera.xml:3224`, which reads
  `$Anchor.barrelposition` and immediately takes `.z` to frame a camera shot
- Live test: experimental — Issue #67 Colossus E r9 on 2026-08-24 logged
  materially different values for the same four turrets after they trained on
  different targets; this dynamic behavior has not yet been reproduced
- Finding: the property is real, but it is a POSITION, not a direction, and the
  one shipped consumer uses its `.z` value for camera framing on fixed nose
  guns. It is explicitly allowed to be `0,0,0`. The earlier inference that it
  was static was wrong: r9 observed the values change as turrets trained. That
  still does not make the property an aim direction or document its coordinate
  frame. Do not build aim-direction logic on it, and do not classify a turret
  as zero-barrel from an OOS or untrained sample without an in-system settled
  measurement.

### No aiscript reads a turret's rotation
- X4: 9.00
- Status: inference
- Bound: a negative result, only as strong as the grep recorded below
- Source: exhaustive grep for `.rotation` across all of
  `.x4-research-cache/extracted/scripts-9.00/aiscripts/`
- Live test: no — source search only, as of 2026-08-11
- Finding: every `.rotation` read in the shipped aiscripts resolves to a ship, a
  dock, a gate, or a waypoint — the census is `this.assignedcontrolled.rotation`
  (16), `this.ship.rotation` (6), and one each of `$thisship.rotation`,
  `$thisship.assigneddock.rotation`, `$exitgate.rotation`,
  `$checkpoints.{$Count}.rotation`, and a `relativeposition{...}.rotation`. Not
  one reads rotation off a turret or weapon. Vanilla never asks a turret where it
  is pointing, which independently corroborates the live finding that the answer
  would be useless (record below).

### Turret gimbal/traverse arc is not exposed to mods
- X4: 9.00
- Status: inference
- Source: `props-9.00/libraries/scriptproperties.xml` weapon/turret datatypes (~lines 1441–1461); ship component XML under `ships-comp-base-9.00`; turret macro XML under `cutscenes-9.00/assets/props/WeaponSystems/`; `schemas-9.00/libraries/common.xsd`
- Live test: no — untested as of 2026-08-09
- Finding: no arc, cone, or gimbal-limit property was found on the weapon or turret datatype. Turret macros expose `rotationspeed` and `rotationacceleration` only, not angular limits. This is a negative result bounded by the sources searched above. It does not matter in practice: finding 1 (check_line_of_sight) supersedes the need for arc data — the engine's own combat AI never tests an arc and uses LOS + range as its complete solution check.

### `$turret.rotation` is the mounted base orientation, not the live barrel
- X4: 9.00
- Status: live-tested
- Source: live Test Lab capture 2026-08-11, X4 9.00, player ship "Ray", 14
  turrets (ids `0x6c2bc`-`0x6c2cf`); logger
  `testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_observe.xml`
  (`:263-264` read `$Turret.rotation.yaw` / `.pitch`), captured to `debug.log`.
  Property documented at `props-9.00/libraries/scriptproperties.xml:58`
  ("Rotation relative to parent") on the `component` datatype (`:12`)
- Live test: yes — one ~10 minute free-play session, 2026-08-11. n=1 ship,
  n=1 session
- Finding: over the whole capture — through combat and hard maneuvering that
  visibly forced turrets to traverse — each of the 14 turrets reported EXACTLY
  ONE distinct yaw value, and it never changed. MD `.rotation` on a turret
  component therefore carries zero information about where the turret is
  currently pointing; it is the mount's orientation relative to the hull. Any
  plan to derive aim direction, bearing, or a firing cone from MD `.rotation`
  is dead.
- REFUTED by this: the inference recorded in this project's own observability
  plan that the `componentslot` `.rotation` versus `.staticrotation` split
  (`scriptproperties.xml:1481` and `:1486`, where `staticrotation` is annotated
  "ignoring offset changes due to animation") implied plain `.rotation` includes
  animation and would track the barrel. It does not, at least not on the
  `component` form actually queried here. Do not re-derive it.
- Limitations: only `component.rotation` (props:58) was probed. The
  `componentslot.rotation` form (props:1481), reached via a slot rather than the
  component, was NOT probed and could in principle behave differently; treat
  that as untested rather than as also refuted.
- Replacement lead, added 2026-08-11: use `bullet.launcher` plus the bullet's own
  rotation, sampled on `event_weapon_fired` — see the `bullet.launcher` record
  above. It gives a real bore direction per shot instead of a static mount
  orientation, at the cost of only producing data when the turret actually fires.
  Corroborating this entry from the other direction: no shipped aiscript reads
  rotation off a turret either (record above).

### `turrets.<state>.list` silently excludes missile turrets
- X4: 9.00
- Status: shipped-source
- Source: `props-9.00/libraries/scriptproperties.xml:539` (`turrets.<state>.list`)
  versus `:542-545` (`missileturrets.<state>.count/list/indexof/random`);
  `missileturret` is its own datatype deriving from `turret` at `:1463`
- Live test: surfaced as a measurement gap in the 2026-08-11 Test Lab capture
- Finding: `<ship>.turrets.<state>.list` and `<ship>.missileturrets.<state>.list`
  are separate property lists. A sweep or measurement loop written over
  `turrets.operational.list` therefore omits an entire class of weapon emitter
  with no error and no log line.
- Why it is recorded: the 2026-08-11 fire-control capture enumerated only
  `turrets.operational.list`, which left missile turrets as an unmeasured firing
  source that could account for observed hits the instrumented turrets did not
  explain. Any per-turret census, LOS sweep, or attribution attempt must
  enumerate both lists or state explicitly that missile turrets are out of scope.

### Searching only the Lua FFI produces false negatives on targeting capability
- X4: 9.00
- Status: documented-public
- Source: cross-reference with `check_line_of_sight` record above; `schemas-9.00/libraries/common.xsd`; `props-9.00/libraries/scriptproperties.xml`
- Live test: no — methodology lesson only, as of 2026-08-09
- Finding: a capability search restricted to the UI Lua FFI concluded that per-turret firing solutions were impossible in X4 9.00, because the relevant capability exists only as the MD action `check_line_of_sight`. Capability questions must be searched across BOTH the Lua FFI surface AND the MD action/property surface (`common.xsd` plus `scriptproperties.xml` plus shipped aiscripts) before any negative conclusion is recorded. See the `check_line_of_sight` record above.

## AI fire-control interpretation

### Autoassist does not create manual turret possession
- X4: 9.00
- Status: shipped-source
- Source: `aiscripts/fight.attack.object.capital.xml`
- Live test: no — untested as of 2026-08-03
- Finding: applying a turret group `autoassist` mode and armed state directs
  X4's existing AI; it does not provide player barrel steering. Treat
  `player.target` and `mayattack`/attack-legality checks as X4-owned gates, and
  verify firing against a hostile target in a disposable live test.

### Autoassist turrets track a target they cannot hit, and stay silent
- X4: 9.00
- Status: live-tested
- Source: in-game trial 2026-08-07; player-owned multi-turret ship, one hostile
  off a single flank, every turret group armed `autoassist` via Gunnery Control
  Direct-control
- Live test: yes — reproduced in the described X4 9.00 trial on 2026-08-07, and
  again on 2026-08-10 with the ship's own pilot under an active attack order,
  which rules out pilot state as the explanation
- Finding: a turret on the flank facing away from the target rotates to track
  it but never fires, observed over 30 seconds. Autoassist therefore hands the
  target to every armed turret regardless of firing solution, and a turret with
  no solution neither picks another target nor reverts to its own behaviour. It
  is the assignment that is exclusive, not merely the firing. This is the
  idle-turret cost of Direct-control.

### Conventional autoassist turrets hold fire on a manually selected own-hull-masked ship surface
- X4: 9.00 (611726)
- Status: live-tested
- Source: controlled Test Lab run 2026-08-24, scenario
  `issue-67-direct-surface-mask-r11`, production build marker
  `2026-08-24-testlab-manual-designation-1`, game `debug.log`; detailed run
  record in `testing-experiments.md`
- Live test: yes — one player-owned Colossus E, one stationary repaired/held-fire
  Xenon K, two exact `turret_arg_m_plasma_02_mk1_macro` members, and one exact
  manually selected `turret_xen_l_laser_01_mk1_macro` surface
- Finding: the owner used the normal Direct-control flow to select the marked
  Xenon K root and then the exact surface `0x1796eb`; Gunnery accepted that
  component and only then armed observation. At both the initial and 20.874 s
  settled snapshots, plasma turrets `0x179672` and `0x179673` were
  `isreadytofire=1`, in range, and inside their generated -10/+90 degree arcs.
  Each exact muzzle ray was clear with the firing ship excluded
  (`muzzle_los_ex=1`) and blocked with it included (`muzzle_los_self=0`). The
  observer recorded zero FIRED and zero HIT events throughout the interval.
  Gunnery's independently recomputed pinned-surface result remained 0/2
  ENGAGEABLE for the same selected component. For this controlled conventional
  weapon case, X4's autoassist shoot controller therefore held fire on the
  own-hull-masked surface, and the production self-inclusive line-of-fire gate
  agreed with the observed firing result.
- Consequence for #67: do not remove or self-exclude the conventional
  projectile line-of-fire gate based on the earlier zero-barrel hypothesis.
  The exact `_02` beam/plasma barrels were non-degenerate, and the existing
  predicate correctly rejected this clean masking case.
- Boundaries: one generated Colossus/K instance and two plasma turrets. This
  does not establish every hull's collision behavior, station-root-to-module
  retargeting, or the separate origin-versus-hittable-aim arc question. The
  two earlier automated surface-designation failures are fixture failures, not
  evidence that surface elements are invalid targets: the normal manual
  root-then-surface path succeeded immediately.

### RETRACTED 2026-08-10: "A preferred target without a target list frees turrets from their mode"
- X4: 9.00
- Status: inference
- Source: retraction authorised by Caleb 2026-08-09; the original record came
  from an in-game trial on 2026-08-07 that issued `set_turret_targets` with
  `preferredtarget` and no `target` list
- Live test: the original trial happened, but it did not test what it claimed
- Finding: **the entry that stood here was wrong and has been removed.** A
  `set_turret_targets` call with no `target` attribute evaluates its target list
  as null and throws "Evaluated value 'null' is not of type list", so nothing is
  applied at all. Every observation attributed to that call was therefore
  caused by something else. The failure surfaces only as a log line, which is
  how it survived: 18 occurrences appeared in a single later log. This voided
  every observation of the feature made before the mandatory-`target` fix, not
  just this record.
- What survives, from other calls that did apply: `weaponmode` on
  `set_turret_targets` selects which turrets RECEIVE the instruction and is not a
  constraint on what they subsequently shoot — which is why feeding a hostile
  ship list to `missiledefence` turrets made them fire on hulls. This project
  used that to justify excluding `missiledefence`, `defend`, `towing`, `mining`
  and `holdfire` from its ship-wide sweep; the owner reversed that product
  decision on 2026-08-10 and the sweep now omits `weaponmode` entirely. The
  engine finding above is unaffected — it is what makes the new behaviour work,
  and what makes it a real change rather than a cosmetic one. For what a
  preferred target plus a real list actually does, see the CANNOT BEAR / OUT OF
  RANGE / LINE OF FIRE BLOCKED record below.
- Lesson: an MD action that throws is a log line, not an error the game surfaces.
  Confirm the action applied before recording anything observed after it.

### Omitting `weaponmode` on `set_turret_targets` is the only way to reach every turret
- X4: 9.00
- Status: shipped-source
- Source: `schemas-9.00/libraries/common.xsd:36223` (the `weaponmode` attribute
  on `set_turret_targets`, typed `weaponmodelookup`, documented "Turrets in the
  specified mode will choose from these targets (defaults to any)");
  `common.xsd:2334-2421` for `weaponmodelookup` versus `extendedweaponmodelookup`
  at `:2420-2440` (line numbers corrected 2026-08-11; the earlier `:2419` was off)
- Live test: no — untested as of 2026-08-10
- Finding: `weaponmode` is optional, and its documented default is *any*. A call
  that omits it applies to every turret on the object regardless of mode. This
  matters beyond convenience: `weaponmode` is typed `weaponmodelookup`, which
  does NOT contain `autoassist` or `holdfire` — those two live only in
  `extendedweaponmodelookup`, used by `set_weapon_mode` but not here. So a script
  that loops over modes and passes each one can never address an autoassist or
  holdfire turret, no matter how the loop is written. Omitting the attribute is
  the only route to them.
- Consequence: "apply to all turrets" and "apply per mode" are not
  interchangeable strategies with different ergonomics; they cover different
  turret sets. Reaching autoassist and holdfire requires the omission.
- Limitations: reaching a turret is not the same as moving it. Autoassist turrets
  discard script-supplied lists outright (record below), so the call arrives and
  does nothing. Whether a target list overrides `holdfire`'s "do not shoot" is
  UNTESTED — do not assume either way.

### Autoassist discards script-supplied target lists; attackenemies honours them
- X4: 9.00
- Status: shipped-source
- Corroboration: live behaviour matches — directed `autoassist` turrets given a
  fallback list ignored it, `attackenemies` turrets rolled to it (2026-08-09/10)
- Source: `aiscripts/fight.attack.object.capital.xml:1756`, carrying Egosoft's
  own comment "NB: this target list will be ignored. target acquisition for
  autoassist turrets is handled in code."; same shape at `:267` and `:456`;
  the `attackenemies` counterpart at `:2172`
- Live test: yes — the consequence was observed on 2026-08-09 and 2026-08-10
- Finding: passing `target` to `set_turret_targets` with
  `weaponmode="weaponmode.autoassist"` is a no-op by construction. Autoassist
  target acquisition happens in engine code and no script-supplied list reaches
  it, so `preferredtarget`'s documented "if it can't attack, it will choose from
  the target list" has nothing to choose from. Any fallback behaviour requires
  `weaponmode.attackenemies`, which vanilla itself drives with a script-supplied
  list at `:2172`.
- Consequence for mods: `autoassist` cannot be used as a private marker mode AND
  carry a fallback list at the same time. Note also that `autoassist` and
  `holdfire` are not members of `weaponmodelookup` (`common.xsd:2334-2421`) and are
  invalid values for the attribute in the sweep direction.

### Autoassist fires at a directly selected ship or station surface element
- X4: 9.00
- Status: live-tested
- Source: controlled live runs 2026-08-17, extension `x4_gunnery_control`
  (Direct-control, checked turret groups armed `autoassist`) plus the Test Lab
  observer; game `debug.log`; Issue #48 Task 5 live checkpoint (2026-08-17)
- Live test: yes — 2026-08-17, X4 9.00, one controlled run per target kind
- Observer fields, so the evidence is checkable: `aimed=` is the designated
  component label for the shot, `hitcomp` is the attacked component from the
  same event payload (`event.param3.{1}`, sibling of the firing weapon at
  `param3.{2}` — see the attribution record above), and `istgt=1` means the
  struck component EQUALS the designated one.
- Finding: an armed `autoassist` group fires at the surface element the player
  has directly selected, on a ship AND on a station, and the engine keeps the
  fire at that element. In both runs the designation was the surface-element
  component itself, not the parent ship or station root:
  - **Ship surface:** selected Osaka surface component `0x17989d`; a census
    confirmed the checked turrets were in `autoassist`. Post-selection FIRED
    records carry `aimed=0x17989d`, and attributed HIT records land on
    `hitcomp=0x17989d` with `istgt=1`.
  - **Station surface:** selected component `0x6c588`, a station surface
    element on the XEN Xenon Defence Platform. Post-selection FIRED records are
    `mode=autoassist aimed=0x6c588`, and attributed turret HIT records land on
    `hitcomp=0x6c588` with `istgt=1`.
  The root-versus-component distinction is what makes this element-granularity
  evidence: with the element designated, hits registered on the element itself
  (`istgt=1`), not on the root object or on a neighbouring component.
- The assignment proof is post-boundary shot/hit evidence (FIRED `aimed=`, HIT
  `hitcomp=` plus `istgt=1`), not a line-of-sight or firing-solution
  measurement. That is why this stands as a live-tested targeting result even
  though no firing-solution field was consulted.
- Corroboration added 2026-08-23: on an Odysseus E, 16 guided missile launches
  carried `aimed=0x18c351` for the directly selected Xenon K turret surface, and
  missile-hit events registered that same component four times (three while the
  designation remained active). Adjacent-component events at the same impact
  times are splash and do not negate the direct surface hits. The missile HIT
  payload named the launcher ship rather than the individual turret, so this is
  surface-designation evidence, not per-turret impact attribution.
- **This supersedes the earlier inference that station surface elements are
  inherently unusable as fire targets.** That inference grew out of a
  2026-08-17 research-branch run on a station under `attackenemies` (n=1): the
  element was supplied as the script preferred target, the turrets fired at a
  different station component instead (0/239 shots within 0.05 rad of the
  element), and the run was read as a likely engine limitation on stations. The
  autoassist evidence refutes the generalized claim: a station surface element
  IS an effective per-turret fire target when it is the player's selected
  target. Superseded is the "inherently unusable" generalization, not the
  underlying n=1 `attackenemies` observation — that run used a different mode
  with a different acquisition path (record above), and nothing here
  re-establishes that `attackenemies` honours a script-supplied preferred
  element.
- Boundaries so the result is not over-read:
  - This does NOT claim every checked turret fires. Consistent with "Autoassist
    turrets track a target they cannot hit, and stay silent" (record above), a
    turret that cannot bear the selected element may remain idle; the live
    result is that the shots fired were aimed at, and landed on, the selected
    component.
  - The shipped-source finding that `autoassist` discards script-supplied
    fallback lists (record above) is PRESERVED and is consistent with this
    result: the element was engaged because it was the selected target the
    engine's own acquisition follows, not because any script-supplied list named
    it.
  - The same controlled run produced post-boundary `attackenemies` fire and
    hits on the selected preferred target (`mode=attackenemies`). Expected
    fallback behaviour was additionally confirmed by the owner in play; that
    confirmation is recorded as an owner observation for this run, not as a new
    live-tested engine result, and it does not extend the durable live-tested
    fallback findings (OUT OF RANGE / CANNOT BEAR fall back; LINE OF FIRE
    BLOCKED holds — record below).

### Vanilla's fight loop does NOT overwrite mod-supplied attackenemies targets
- X4: 9.00
- Status: live-tested
- Corroboration: contradicts the plausible reading of the shipped source, which
  is why it needed observing rather than inferring
- Source: in-game trial 2026-08-10, player-piloted capital ship. Pilot held
  `command.attackobject` continuously for ~145 s (read back per tick via
  `GetComponentData(pilot, "aicommandraw")`) while the mod issued
  `set_turret_targets` with `preferredtarget` plus a hostile `target` list at
  `weaponmode="weaponmode.attackenemies"`, across roughly a dozen target changes
- Live test: yes — 2026-08-10, X4 9.00
- Finding: `aiscripts/fight.attack.object.capital.xml` re-issues
  `set_turret_targets` for `attackenemies` at `:2172` inside a loop paced by
  `<wait min="11ms" max="17ms"/>` (`:2282`), which reads as though a fighting
  pilot's script would overwrite any mod-supplied list ~60 times a second. It
  does not. Under an active attack order the mod's preferred target was honoured
  and held, re-acquired on every target change, and its fallback list was used
  when the preferred target was LINE OF FIRE BLOCKED and CANNOT BEAR.
- Consequence for mods: a mod may direct turrets with
  `weaponmode.attackenemies` regardless of what the ship's own pilot is doing.
  There is no need to detect the pilot's command state and switch modes to avoid
  a clash. Doing so is actively harmful, because the alternative mode with an
  engine-side acquisition path is `autoassist`, which discards the fallback list
  (record above) and leaves a turret that cannot bear on the target tracking it
  in silence.
- Limitations: observed on one ship over one engagement. What arbitrates between
  the two writers was not determined — last-writer-wins at the ~4 Hz the mod
  re-issues at is the obvious guess, but it was not tested, and a visible
  consequence is that a turret slews briefly toward the vanilla-chosen target on
  each change before settling on the mod's. Behaviour was not checked for NPC
  ships, for a pilot under `command.attackenemies` specifically, or when two
  mods write turret targets at once.

### preferredtarget falls back on CANNOT BEAR and OUT OF RANGE, but not on LINE OF FIRE BLOCKED
- X4: 9.00
- Status: live-tested
- Corroboration: staged twice against purpose-built hostile groups, with the
  directed mode logged per engage
- Source: in-game trials 2026-08-09 (OUT OF RANGE, LINE OF FIRE BLOCKED) and 2026-08-10
  (CANNOT BEAR), player-piloted capital ship, `set_turret_targets` issued
  narrow-then-wide with `preferredtarget` plus a hostile `target` list and
  `weaponmode="weaponmode.attackenemies"`
- Live test: yes — 2026-08-09 and 2026-08-10, X4 9.00
- Finding: a turret that cannot engage the preferred target rolls to another
  hostile from the supplied list in two of the three fire-control conditions.
  - **OUT OF RANGE** (target 15 km out, far beyond turret reach): falls back.
  - **CANNOT BEAR** (target 3 km astern and 1.2 km high, engaged by a group whose
    mount cannot bear on it): falls back. A group that *can* bear on the same
    target engages it normally, which is the control.
  - **LINE OF FIRE BLOCKED** (turret trained on the target with own hull in the line of fire):
    does **not** fall back. The turret tracks the target and holds fire
    indefinitely. The engine's fallback asks whether the turret can aim, not
    whether it can hit.
- Consequence: LINE OF FIRE BLOCKED cannot be corrected by re-issuing targets, because the
  engine's own fallback is what would have to act and it does not. Whether a mod
  could OBSERVE the condition is a separate and open question: there is no
  per-turret current-target property (`scriptproperties.xml:1441-1461`, checked),
  and both originally proposed detectors turned out to be dead ends *as polled
  reads*: `lastattacker` resolves to the ship, not the turret
  (ui-lua-menu-camera.md), and `check_line_of_sight` with `excludeself="false"`
  reports blocked unconditionally from an on-ship turret (scope notes on the
  `check_line_of_sight` record above). CORRECTED 2026-08-11 — do not read that as
  "attribution is impossible": per-turret attribution exists via the EVENT
  `event_object_attacked_object`, whose `param3.{2}` is the firing weapon, and
  per-shot bore direction via `event_weapon_fired` plus `bullet.launcher` (both
  records above). What is unavailable is polling, not attribution. LINE OF FIRE BLOCKED itself
  was still never staged and remains unobserved; no fix follows from the answer
  regardless, so the closure of this line of work stands on the fix, not on the
  detectors.
- Limitations: `weaponmode.autoassist` is excluded from all of this — it
  discards script-supplied target lists by construction (Egosoft's own comment,
  `aiscripts/fight.attack.object.capital.xml:1756`), so no fallback list reaches
  it. The fallback selection rule among eligible targets remains unverified; do
  not claim it is nearest-first.

### The player-selectable turret mode list is eleven modes, and holdfire is not one of them
- X4: 9.00
- Status: shipped-source
- Source: the dropdown model is a single literal table,
  `ui-9.00/ui/addons/ego_detailmonitorhelper/helper.lua:12712-12724`
  (`Helper.turretModes`), consumed by `Helper.getTurretModes` at `:12726-12734`.
  Its three call sites are the only turret-mode pickers in the shipped UI:
  `ui/addons/ego_detailmonitor/menu_docked.lua:850` (all turrets), `:867`
  (single turret), `:885` (turret group), and the map-menu equivalents
  `menu_map.lua:16092`, `:16106`, `:16126`. Selection commits through
  `C.SetWeaponMode` / `C.SetTurretGroupMode2` (`menu_docked.lua:869`, `:887`).
  Labels resolved from `t2-9.00/t/0001-l044.xml` (English, page 1001)
- Live test: no — read from shipped source and text DB, untested by this project
  as of 2026-08-11
- Finding: in table order, with the label the player actually sees:
  `defend` "Defend" (8613), `attackenemies` "Attack all enemies" (8614),
  `attackcapital` "Attack only capital ships" (8634), `prefercapital`
  "Attack capital ships first" (8637), `attackfighters` "Attack only fighters"
  (8635), `preferfighters` "Attack fighters first" (8638), `missiledefence`
  "Shoot only missiles" (8636), `prefermissiles` "Shoot missiles first" (8639),
  `autoassist` "Attack my current enemy" (8617), `mining` "Mining" (8616),
  `towing` "(Turret mode)Towing" (8633).
- **`autoassist` IS player-selectable and IS labelled.** It is entry `[9]` with
  `forall = true`. Any statement that autoassist is an unlabelled internal
  default is wrong. Its in-game name, "Attack my current enemy", is also a plain
  description of the behaviour recorded elsewhere in this file: it follows the
  player's locked target and discards script-supplied lists.
- **`holdfire` is absent from the entire shipped turret-mode UI.** It is not in
  `Helper.turretModes`, and a grep for `holdfire` across
  `ui-9.00/ui/addons/ego_detailmonitor/`, `ui/addons/ego_detailmonitorhelper/`
  and `ui/core/` returns nothing. The only `holdfire` hits anywhere in `ui-9.00`
  are unrelated: three in `ego_interactmenu/menu_interactmenu.lua` (`:1030`,
  `:1103` script-parameter comments, and `:6239` the fleet order "Stop and hold
  fire"). So a player cannot put a turret into holdfire from the turret menu;
  only a script can, via `set_weapon_mode` (typed `extendedweaponmodelookup`).
  A turret found in holdfire got there from a script or a fleet order.
- Two filters decide which of the eleven a given player actually sees. `forall`
  is false only for `towing`, so towing is offered per-turret but suppressed from
  the "all turrets" dropdown unless the ship has only tug turrets
  (`menu_docked.lua:850` passes `not hasonlytugturrets`). Per entry, the UI calls
  the engine predicate `C.IsWeaponModeCompatible(turret, "", entry.id)`
  (`helper.lua:12730`, declared `:416`), which is where hardware gating such as
  "this is a mining laser" lives. That predicate is engine-side; its rule is not
  readable from script and is not established here.
- Bound on the claim: this enumerates the VANILLA UI. An installed extension can
  add its own picker. Labels are the English text DB only.

### `weaponmodelookup` has eleven members; the doc-relevant five are the capital/fighter/missile priority modes
- X4: 9.00
- Status: shipped-source
- Source: `schemas-9.00/libraries/common.xsd:2334-2418` enumerated in full;
  `extendedweaponmodelookup` at `:2420-2441`
- Live test: no — read from shipped source, untested by this project as of 2026-08-11
- Finding: `weaponmodelookup` contains exactly, with Egosoft's own
  `xs:documentation`: `weaponmode.any` "Any mode applies" (`:2338`),
  `attackenemies` "Attack all enemies" (`:2345`), `attackcapital` "Attack only
  capital ships (All ships of size class L or XL)" (`:2352`), `attackfighters`
  "Attack only non-capital ships (All ships of size class XS, S, or M)"
  (`:2359`), `defend` "Defend against attackers (default for non-mining
  weapons)" (`:2366`), `mining` "Mining asteroids (default for mining weapons)"
  (`:2373`), `missiledefence` "Attempt to shoot down missiles" (`:2380`),
  `prefercapital` "Attack all enemies, but prioritize capital ships" (`:2387`),
  `preferfighters` "Attack all enemies, but prioritize fighters" (`:2394`),
  `prefermissiles` "Attack all enemies, but prioritize missiles" (`:2401`),
  `towing` "Attempt to tow scrap" (`:2408`). `extendedweaponmodelookup` adds
  `autoassist` "Automatically target the current target (player only)" (`:2424`)
  and `holdfire` "Do not shoot" (`:2431`), and nothing else.
- The distinction that matters for fire control: the three `prefer*` modes are
  documented as "Attack all enemies, but prioritize X". They are attackenemies
  with a sort order, NOT a target restriction — so a mod's preferred target
  reaches them the same way it reaches attackenemies. The two `attackcapital` /
  `attackfighters` modes ARE restrictions by size class, so a target of the wrong size
  class is one the turret is documented not to engage.
- Vanilla treats them exactly that way. `fight.attack.object.capital.xml:1697`
  lists `attackenemies`, `attackcapital`, `attackfighters`, `prefercapital`,
  `preferfighters` and `prefermissiles` together as the modes whose presence
  makes a ship worth running the fight loop for. In the player-owned branch the
  three `prefer*` modes each get the full target set with the ship's preferred
  target passed straight through (`:2172` attackenemies, `:2192` prefercapital,
  `:2208` preferfighters, `:2224` prefermissiles), while `attackcapital` (`:2240`)
  and `attackfighters` (`:2249`) get only the size-filtered group.

### Vanilla hands missiledefence and mining turrets a SHIP as preferred target
- X4: 9.00
- Status: shipped-source
- Source: `aiscripts/fight.attack.object.capital.xml:2261-2267` (missiledefence)
  and `:2270-2272` (mining), in the player-owned branch; `$preferredtarget`
  originates at `:1979` as `@$primarytarget`. The NPC branch is stronger still:
  `fight.attack.object.medium.xml:1372-1374` and
  `fight.attack.object.capital.xml:2126-2128` loop `$turretmodes` and pass the
  same hostile `$targets.list` to EVERY mode except `towing`, and `$turretmodes`
  is built from unfiltered live `.mode` reads at `capital.xml:1683-1688`
- Live test: no — read from shipped source, untested by this project as of 2026-08-11
- Finding: the missiledefence call at `:2267` sets `$locpreferred` to
  `$preferredtarget` FIRST (`:2262`) and only replaces it with a random missile
  if the preferred target is not already in the incoming-missile list (`:2263-2265`).
  Since `$preferredtarget` descends from `$primarytarget`, the ship the pilot is
  attacking, vanilla routinely hands a missiledefence turret a hostile SHIP as
  its preferred target alongside a missiles-only fallback list. Directing a
  missiledefence turret at a ship is therefore Egosoft's own behaviour, not a
  mod-only abuse.
- On NPC ships the same is true of `mining`: a mining-mode turret on a
  non-player-owned ship receives the full hostile ship list with a hostile
  preferred target, because the sweep excludes only `towing`. Vanilla's mining
  restraint on PLAYER ships is a script-side gate, not a property of the mode —
  `:2270` guards the asteroid call on `this.ship == player.occupiedship`, and
  `:1903` carries the comment "turret handling for AI pilots is handled in the
  respective mining scripts".
- No hardware gate backs any of this up in script. `weapon.ismining` and
  `weapon.iscombat` exist (`props-9.00/libraries/scriptproperties.xml:1450-1451`)
  but a grep for `ismining`, `iscombat` and `isrepairing` across ALL of
  `scripts-9.00/` (`aiscripts/` and `md/`) returns zero hits — no shipped script
  reads them. Nothing in shipped script filters a target list by whether the
  receiving turret is mining or combat hardware.
- What is still NOT established: whether the ENGINE's shoot controller then acts
  on that ship target, for either mode. Vanilla's willingness to send it is not
  proof the turret fires. `IsWeaponModeCompatible` (`helper.lua:416`) shows
  hardware/mode compatibility gating does exist engine-side and is unreadable
  from script. Both rows still need a live test to settle "does it shoot".

### Vanilla drops a turret target the moment it stops being attackable, and holds fire by MODE alone
- X4: 9.00
- Status: shipped-source
- Source: `aiscripts/fight.attack.object.capital.xml:1057-1096`, a handler whose
  own comment (`:1057`) reads "stop firing if a target changes ownership to less
  than hostile"; the mirror at `fight.attack.object.medium.xml:443-446`.
  `ClearTarget` is defined at `aiscripts/lib.target.selection.singletarget.xml:5-49`.
  `stop_firing_at_target` is declared at `schemas-9.00/libraries/common.xsd:37511-37529`
- Live test: no — read from shipped source, untested by this project as of 2026-08-11
- Finding: change-of-owner and relation change are handled explicitly, and the
  handler is script-side, not engine-side. It triggers on
  `event_object_relation_range_changed` or `event_object_changed_owner` over the
  target groups (`:1060-1065`), gated by `check_value value="not
  this.assignedcontrolled.mayattack.{event.object}"` (`:1070`). So the trigger is
  the loss of `mayattack`, i.e. relation, not destruction.
  - If the target stopped being attackable, `ClearTarget` (`:1087`) removes it
    from every group and calls `stop_firing_at_target` on it
    (`lib.target.selection.singletarget.xml:12`, `:27`, `:42`), then
    `abort_called_scripts resume="Start"` (`:1095`) restarts target selection.
  - If the FIRING ship changed owner, everything is cleared wholesale
    (`:1075-1082`).
  - Autoassist is handled separately at `:1088-1091`: if `player.target` is no
    longer attackable, vanilla issues `cease_fire weaponmode="weaponmode.autoassist"`,
    because an autoassist turret's target is engine-chosen and clearing a list
    would not reach it.
- Consequence for a mod: the engine does not silently drop a preferred target
  that stops being hostile — a SCRIPT does, and that script is the ship's own
  fight AI. A mod that keeps re-issuing a preferred target after the target
  turns friendly is fighting the vanilla handler rather than being corrected by
  it. `mayattack` is the operative test
  (`props-9.00/libraries/scriptproperties.xml:119-120`, kill relation, or
  killmilitary against a fight-purpose object, "can be overridden by fire
  authorisation override").
- **Do not confuse `canbeattacked` with permission.** `canbeattacked`
  (`scriptproperties.xml:24`) is documented as "true iff the component exists in
  the game graph, is not a wreck, and is either operational, is of real class
  station, or is a child of a station" — pure existence and integrity. It
  contains no relation check whatsoever. Relation lives in `mayattack` (`:119-120`)
  and `ishostileto` (`:121-122`). Vanilla uses both, for different jobs.
- Corroborating how binding `holdfire` is: vanilla's own stand-down path is the MODE
  alone. `aiscripts/lib.set.weaponmode.xml:17-20` falls back to
  `weaponmode.holdfire` when called with no mode, logging "falling back on
  weaponmode.holdfire", and `move.flee.xml:191-196` and `order.wait.xml:206` use
  it to make a ship stop shooting. Neither of those scripts pairs it with
  `cease_fire` or clears turret targets — grep for `cease_fire`,
  `set_turret_targets` and `stop_shooting` in both files returns nothing. Egosoft
  evidently trusts the mode by itself to stop fire, with stale target lists
  possibly still in place. That is suggestive that holdfire outranks a target
  list, but it is NOT proof: no shipped script ever sends a target list to a
  holdfire turret, so shipped source never exercises the conflict. The row still
  needs a live test.

### No lead, intercept, or predicted-position handling exists in shipped scripts
- X4: 9.00
- Status: inference
- Bound: a negative result; the greps are the claim
- Source: `props-9.00/libraries/scriptproperties.xml` grepped for
  `predictedposition`, `intercept`, `leadposition`, `aimposition` — zero hits.
  `schemas-9.00/libraries/common.xsd` grepped for `predict` and `intercept` —
  the only hits are four unrelated enumerations (`:2505` `interceptor`, `:2550`
  `shiptype.interceptor`, `:3602` `interception`, `:3696`
  `assignment.interception`), all ship-role or assignment names.
  `scripts-9.00/aiscripts/fight.attack.object.capital.xml`,
  `fight.attack.object.medium.xml`, `fight.attack.object.bigtarget.xml` and
  `fight.attack.object.station.xml` grepped for `velocity` — zero hits in any of
  them
- Live test: no — source search only, as of 2026-08-11
- Finding: no shipped aiscript computes a firing lead, and no MD property or
  action exposes one. The combat scripts never read a target's velocity at all.
  Whatever ballistic lead the engine applies when a turret actually shoots is
  entirely inside the C++ shoot controller and is invisible to and unreachable
  from script. A script-side "is there a shot that would connect" test therefore
  does not exist in vanilla, which is consistent with the separately recorded
  finding that vanilla's complete firing-solution test is line of sight plus
  range.
- Bound restated so it is not over-read: this establishes that SCRIPTS do no lead
  computation. It says nothing about whether the engine does. Do not cite it as
  evidence that X4 turrets fire without lead.

### Vanilla sweeps every turret mode but towing, and feeds defend/missiledefence hostiles
- X4: 9.00
- Status: shipped-source
- Source: `aiscripts/fight.attack.object.medium.xml:1361-1376` (the NPC branch:
  `<do_for_each name="$locmode" in="$turretmodes">` guarded by
  `<do_if value="$locmode != weaponmode.towing">`, calling `set_turret_targets`
  at `:1374` with the same `$targets.list` and the same `preferredtarget` for
  every mode). Egosoft's comment at `:1362`: "non player-owned ships use only one
  weapon mode. throw all targets into one group and allow shoot controller to
  select targets per turret as appropriate." Identical construct and comment in
  the capital script at `:2116` and `:2128`. `$turretmodes` is built at
  `fight.attack.object.capital.xml:1683-1688` by reading `.mode` off each member
  of `this.ship.turrets.operational.list`
- Live test: no — read from shipped source, untested by this project as of 2026-08-11
- Finding: vanilla's own answer to "which modes may receive a target list" is
  *all of the ones present on the ship, except towing*. It does not curate the
  list per mode; it hands the same hostile set and the same preferred target to
  every mode and lets the engine-side shoot controller sort out per-turret
  assignment.
- Specific consequences, each separately sourced in the capital script's
  player-owned branch:
  - **defend** turrets are given a hostile ship list plus a preferred target by
    vanilla itself (`fight.attack.object.capital.xml:2258`, fed `$attackers.list`).
  - **missiledefence** turrets likewise (`:2267`, fed `$incomingmissiles.list`).
    So directing these modes at hostiles is not a mod-only abuse of the API.
  - **towing** is the single mode Egosoft explicitly excludes from the sweep.
  - **mining** is gated on `this.ship == player.occupiedship` (`:2270`), i.e.
    vanilla only drives mining turrets on the ship the player occupies.
- **holdfire and autoassist are structurally unreachable via `weaponmode=`.**
  `set_turret_targets`'s `weaponmode` attribute is typed `weaponmodelookup`
  (`common.xsd:36223`), the simple type declared at `:2334-2421`.
  `extendedweaponmodelookup` (`:2420-2440`) is a `<xs:union
  memberTypes="weaponmodelookup">` that adds exactly two further members and no
  others: `weaponmode.autoassist` (`:2424`) and `weaponmode.holdfire` (`:2431`,
  documented "Do not shoot"). Those two are therefore invalid as `weaponmode`
  values here, and no loop over modes can address them however it is written.
  OMITTING `weaponmode` entirely is the only path that reaches a holdfire
  turret.
  (Note the containment direction: `$turretmodes` is built from live turret
  `.mode` reads, so on a ship with a holdfire turret the loop variable can hold a
  value the attribute will not accept.)
- The one thing shipped source cannot answer: whether the engine then honours a
  target list on a holdfire turret, or whether "do not shoot" overrides it. That
  needs a controlled live test, and the source is silent on it. Do not assume
  either way. (Autoassist is separately known to discard the list outright —
  record above.) The closest circumstantial evidence, and it is only
  circumstantial, is that vanilla stands ships down using the mode alone without
  clearing targets — see the change-of-owner record above.
- Superseded in one respect by the mode-enumeration records above: "every turret
  mode" here means the eleven members of `weaponmodelookup`, which include
  `attackcapital`, `attackfighters`, `prefercapital`, `preferfighters` and
  `prefermissiles`. This entry predates that enumeration and should not be read
  as implying the mode set is just defend/attackenemies/mining/missiledefence/towing.

### `mayattack` includes relation and fire-authorisation gates
- X4: 9.00
- Status: shipped-source
- Source: `libraries/common.xsd`; `aiscripts/fight.attack.object.capital.xml`
- Live test: no — untested as of 2026-08-03
- Finding: absent an active fire-authorisation override, `mayattack` is true for
  kill relation, or killmilitary against a fight-purpose object. Autoassist
  paths retain this gate when considering `player.target`; selecting a neutral,
  friendly, or player-owned object does not make normal turret AI fire on it.

### `create_ship` macro and faction are independent parameters (mismatch has no shipped precedent)
- X4: 9.00
- Status: inference
- Source: `libraries/common.xsd` (`create_ship`); scoped scan of extracted
  vanilla 9.00 MD (306 `create_ship` instances: every literal macro/faction
  pair matched, the remainder used variables — no literal mismatch); Test Lab
  `md/x4_gunnery_control_testlab_scenario.xml` (the `surface_mask` target
  branch passes `macro.{$Def.$macro}` and `<owner exact="$Owner"/>`
  independently, with no `<pilot>` element); `ui/testlab.lua` (`validateSpec`
  requires only non-empty macro/faction strings)
- Live test: no — a mismatched spawn has not been reproduced
- Finding: the hull macro and the owner/faction are supplied independently,
  so e.g. an Argon hull under xenon ownership is structurally supported, with
  attackability expected through the owner's kill relation (see the `mayattack`
  record above). But no shipped 9.00 MD exhibits a literal macro/faction
  mismatch, so treat such a spawn as unproven until a live reproduction. The
  fail-closed detection path is the live hostiles census: MD increments the
  hostile count only when `mayattack` is true, and the readiness check refuses
  READY on a mismatch. Pair with the Osaka record in the spawn skill: a
  relation boost alone did not legalize a friendly-owned target.

### Preferred turret targets do not legalize an attack
- X4: 9.00
- Status: shipped-source
- Source: `libraries/common.xsd` (`set_turret_targets`)
- Live test: no — untested as of 2026-08-03
- Finding: if a preferred target cannot be attacked, turrets select from the
  supplied target list instead. The action is also ignored in low attention.
  Treat target assignment and permission to attack as separate questions.

### Direct turret actions are a separate experimental path
- X4: 9.00
- Status: inference
- Source: `libraries/common.xsd` (`aim_turret`, `fire_turret`, `shoot`); scoped
  search of extracted X4 9.00 MD/AI scripts
- Live test: no — untested as of 2026-08-03
- Finding: the schema exposes per-turret aim/fire actions and an untargeted
  visible-attention `shoot` action, but the scoped shipped-script search found
  no established continuous player-gunnery example. Do not claim these safely
  bypass relation, firing-arc, collision, attention, or authorisation limits
  until a disposable live experiment proves exact behavior and cleanup.

Do not infer a target is attackable merely because it can be selected. Separate
whole-object, engine, shield, turret, and station-module surface tests.

### UI-triggered events sent during UI init at startup arrive before MD is listening
- X4: 9.00
- Status: live-tested
- Source: live session on 2026-08-08, extension `x4_gunnery_control`, X4 9.00 Steam,
  Windows 11; game debug.log
- Live test: yes — observed on both inits of a fresh launch on 2026-08-08
- Finding: `AddUITriggeredEvent` calls made from a menu file's init at game startup produced
  no MD-side effect at all. Two sends were logged from Lua, and the receiving cues logged
  nothing for either.

  The ordering is visible in the log: both Lua sends were logged before the MD script logged
  its own activation. The same sends, issued from the same code after a UI reload later in
  the session, were received normally and logged by MD within a second.

  The events are dropped silently. Nothing in the log distinguishes "MD was not listening"
  from "MD ignored it"; only the ordering does.

  This extension also re-sends on `gameLoadingDone` (`ui/gunnery_control.lua`). In the runs
  measured here that later send was received and the init send was not.

  Not established by this test: the exact point at which MD begins accepting these events, or
  whether a retry or delay from Lua would be received earlier than the `gameLoadingDone` hook.

### A `checkinterval` cue that resets itself hard-freezes X4; periodic cues need `<delay>`
- X4: 9.00
- Status: live-tested
- Source: live session 2026-08-15, extension `x4_gunnery_control`, X4 9.00 Steam,
  Windows 11; game debug.log
- Live test: yes — froze the game on the first click that armed the cue, 2026-08-15
- Finding: a `<cue checkinterval="2s">` whose `<actions>` end with a self
  `<reset_cue>` does NOT wait the interval between cycles. It re-arms, re-evaluates
  its `<conditions>` true, and re-fires in the SAME frame, an unbounded loop that
  hard-freezes X4 with no error and no further log output (the log ended exactly on
  the last action before the loop). `checkinterval` only spaces out polls of a cue
  still WAITING for its first fire; it does not throttle a reset-driven re-arm.
- Fix: for a periodic self-repeating cue use `<delay exact="Ns"/>` (child order
  `conditions` → `delay` → `actions`) with the trailing `reset_cue`. `<delay>` gates
  each cycle: after the condition passes the cue waits N s, runs, resets, waits N s
  again. Verified non-freezing in the same session.
- The event-driven `reset_cue` re-arm idiom (a sibling cue reset from an
  `event_ui_triggered` handler) is unaffected — it is safe precisely because it is
  not condition-polled.

### Re-feeding the hostile list on release does NOT revert defend/missiledefence/mining
- X4: 9.00
- Status: live-tested
- Source: live session 2026-08-15, extension `x4_gunnery_control`, fixture with one
  `attackenemies` group and the rest `defend`; game debug.log
- Live test: yes — 2026-08-15, `defend` observed still firing after release
- Finding: to undo a ship-wide preferred-target override, issuing
  `set_turret_targets target=$hostiles weaponmode=$mode` with `clearpreferred`
  (default true) reverts the ATTACK-family modes (`attackcapital`, `attackfighters`,
  `prefercapital`, `preferfighters`, `prefermissiles`, `any`) correctly, because
  attacking the hostile list IS their resting behaviour. It does NOT revert the three
  modes vanilla feeds a CURATED list — `defend` (attackers), `missiledefence`
  (incoming missiles), `mining` (asteroids). `clearpreferred` drops the preferred
  MARK but not the target LIST, and the old target is still in `$hostiles`, so the
  turret keeps engaging it. Census showed 29 `mode=defend` turret hits after the
  release flag went `prefer=0`. `missiledefence`/`mining` were not on the fixture but
  share the structure (see the shipped-source records at "Vanilla hands
  missiledefence and mining turrets a SHIP as preferred target" and the note that a
  ship list made `missiledefence` fire on hulls).
- Implication: reverting those three requires stopping the mod's influence, not
  re-supplying a list — and no available API does so cleanly. `cease_fire
  weaponmode=$mode` (vanilla's own stop mechanism) was then tried live and only
  stops these turrets MOMENTARILY: they resume firing on the old target within
  seconds, so it does not revert the curated-list modes either. `SetTurretGroupMode2`
  reset (no-op write of a group's own mode) cleared the preferred mark but not the
  list, and an empty target list did not release active guns. Live-tested across the
  issue #36 sessions (2026-08-13..16, X4 9.00, mixed-mode fixture). With no API found
  to clear a turret's supplied target list, the ship-wide override was removed
  entirely (issue #38) rather than shipped with an unreachable release.

### Ship component connection-offset quaternions are stored inverted (child-to-parent)
- X4: 9.00
- Status: live-tested
- Source: r16 Test Lab `debug.log` `WEAPONPOSE` instrumentation, request
  55003123_q2 at game time 248895.15 on 2026-08-26;
  `assets/units/size_l/ship_par_l_destroyer_01.xml` con_turret_laser_l_01
  quaternion `(-0.1274921,0,0,-0.9918396)` vs measured weapon
  `rotation.pitch=-0.25568` rad; 70-surface pitch cross-check
- Live test: yes — one instrumented run; the conjugate of the raw XML
  connection quaternion predicted all 70 measured surface pitches with zero
  error (rmse 0.000 deg), while the as-given form erred up to 27 deg
- Finding: to get an equipment component's live orientation frame from a ship
  component XML connection offset, use the CONJUGATE of the stored quaternion
  (the stored value maps child frame to parent). Position offsets are direct.
  The earlier Colossus E r13 calibration could not detect this because that
  mount's quaternion was a pure boresight roll, invisible to pitch
  measurements. Bound: verified for one turret mount on one hull; the
  conjugation rule itself is consistent with all shipped loadouts observed.

### X4 fires when a component's origin is outside a turret's authored pitch stop but its hittable aim point is inside
- X4: 9.00
- Status: live-tested
- Source: r32 Test Lab `debug.log` on 2026-08-26, game time 248913-249157;
  qualify `request_id=84394242_q2` (`group_front_up_mid2`, shooter ship
  `1544423`, weapon `0x1790f5` `turret_par_l_plasma_01_mk1_macro`, authored
  band {-5,+80} => +80 deg = 1.39626 rad); closes the open question left at
  the own-hull masking record above
- Live test: yes — one instrumented run, one arc-split case plus one
  in-arc positive control, both manually designated through Direct control
- Finding: the fixture qualified two exact `turret_arg_l_beam_01_mk1_macro`
  surfaces on two Argon L destroyers. Arc-split case `SKY SURVEY A 000`
  (`0x179112`) surface `0x17911d`: `origin_pitch=1.41806` (outside +80 deg),
  `aim_pitch=1.37386` (inside), `arc_split=1 origin_outside=1 aim_inside=1
  inrange=1 mayattack=1`. Positive control `SKY SURVEY A 100` (`0x179135`)
  surface `0x179140`: `origin_pitch=1.22173 aim_pitch=1.21314 arc_split=0`.
  With the predicate evaluating the `useaimtarget` bearing, both surfaces
  rendered `1 / 1  ENGAGEABLE` (`0x179140` at 249125.95, `0x17911d` at
  249148.82; pinned refresh of `1544477` still `engageable=1` at 249155.83).
  The owner then destroyed both exact components: `0x179140` FIRED 249138.45
  / HIT 249140.77 `hitcomp=0x179140 istgt=1`, `0x17911d` FIRED 249155.79 /
  HIT 249156.10 `hitcomp=0x17911d istgt=1`, each row leaving the browser
  immediately after (`all=4` -> `all=3`). X4 therefore does engage across an
  authored pitch limit when the hittable aim point is inside it, so an
  origin-based arc check refuses shots the engine will take.
- Consequence: evaluate arc membership on the weapon-local `useaimtarget`
  look_at bearing, not on `$target.relativeposition.{$weapon}.rotation.pitch`.
- Note on granularity: ship-root and surface engageability legitimately
  disagree under this geometry. At 249156.48 root `1544466` read `0 / 1`
  while its own surface `1544477` read `1 / 1  ENGAGEABLE` — exactly the
  `origin_outside=1 / aim_inside=1` split. Do not read a root row as a
  verdict on its surfaces.
- Boundaries: one shooter macro, one authored band, one target hull, pitch
  axis only. Yaw stops and modded macros are untested. An unresolved
  anomaly on a NON-designated component from the same run is tracked
  separately: engine `0x179141` read `0 / 1` at 249125.03 (pinned,
  `hull_percent=18`) yet was hit at 249125.11 and 249129.11 with
  `aimed=0x179141 istgt=1` under `mode=autoassist`.
