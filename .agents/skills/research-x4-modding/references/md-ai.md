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

### Per-turret firing solution is computable from MD
- X4: 9.00
- Status: shipped-source
- Source: `schemas-9.00/libraries/common.xsd:21691` (the `check_line_of_sight` action element); `aiscripts/mining.collect.ship.capital.xml:229-231`; `aiscripts/move.attack.object.capital.xml:657,681`
- Live test: no — untested as of 2026-08-09
- Finding: `check_line_of_sight` is an MD/AI action that performs ray casts. Its `object` attribute accepts a turret component, so line of sight can be tested per individual turret against a target. Attributes include `object`, `objectoffset`, `target`, `targetoffset`, `useaimtarget`, `excludeself`, and `name`. Setting `useaimtarget="true"` uses the object's aim targets as the raycast destination, consistent with weapon aiming. Shipped combat and mining AI defines "this turret can engage this target" as line of sight AND `turret.distanceto.{target} + (target.size/2) < turret.maxfirerange`. Vanilla does NOT perform any separate gimbal or traverse-arc test; LOS from the turret component plus range is the engine's own working definition of a firing solution. The vanilla loop answers only "does ANY turret have a solution" (it breaks on first hit), so an N-of-total count is strictly more expensive than anything shipped code does.
- Scope of that claim, added 2026-08-10 so it is not over-read: this establishes what VANILLA computes, from shipped source. It has never been run by this project and says nothing about detecting the MASKED condition — a turret trained on a target with the ship's OWN hull in the line of fire. Whether `check_line_of_sight` can answer that is UNRESOLVED and untested: the ray from a turret to its target begins inside the firing ship's own hull, so `excludeself` plausibly decides the result in both directions (true and it cannot see own-hull masking at all; false and it may report every shot blocked), but the exact `excludeself` semantics have not been verified against the engine. Not pursued, because MASKED was confirmed live on 2026-08-09 to be unrecoverable regardless — the engine's preferred-target fallback never rolls off a MASKED target, so knowing the condition would not let a mod act on it. Do not cite this entry as evidence either that the technique works for MASKED or that it cannot.
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
- Still UNRESOLVED after that capture: everything above about MASKED. The capture
  did not stage a MASKED condition, and it never established what
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

## Per-turret attribution from MD events

### `event_object_attacked_object` param3 carries the firing WEAPON — this is the per-turret attribution route
- X4: 9.00
- Status: shipped-source
- Source: `schemas-9.00/libraries/common.xsd:13055` (the event element; its
  `xs:documentation` at `:13058` reads "object = attacker, param = attacked
  object, param2 = kill method, param3 = [attacked component, weapon]").
  Shipped proof the second element really is the weapon: `md/notifications.xml:1515`
  passes `event.param3.{2}` straight into `change_relation_on_attack weapon=`,
  whose `weapon` attribute is declared at `common.xsd:21620` (element at `:21611`)
- Live test: no — read from shipped source, untested by this project as of 2026-08-11
- Finding: the event's `param3` is a two-element list, `[attacked component,
  weapon]`. `event.param3.{2}` is therefore the weapon component that landed the
  hit — on a turreted ship, the individual turret. Vanilla's own use is the
  corroboration: `notifications.xml` does not inspect or reinterpret the value, it
  forwards it as the `weapon` argument of a relation-change action that is typed
  to take a weapon. This is a HIT signal, delivered to a listener, rather than a
  property that can be polled.
- **This supersedes the `lastattacker` dead end.** `lastattacker` is ship-scoped
  by design and cannot attribute a hit to a turret (live capture 2026-08-11, see
  the attacker-attribution record in `ui-lua-menu-camera.md`). Per-turret
  attribution is available — just from an event payload, not from a property read.
  Anyone landing on the negative result should come here.
- Related but distinct, do not conflate: `md/x4ep1_mentor_subscription.xml:7138`
  tests `event.param3.isclass.bullet and event.param3.launcher`, but that is a
  condition on `event_player_ship_hit`, a different event whose `param3` is the
  BULLET itself rather than a two-element list. It is evidence for the
  `bullet.launcher` route below, not for this event's payload shape.

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
- Live test: no — read from shipped source, untested by this project as of 2026-08-11
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
- Consequence worth recording: `event_object_attacked_object` fires on a HIT and
  `event_weapon_fired` on every TRIGGER PULL. Listening to both and diffing per
  weapon yields a per-turret hit rate — rounds sent versus rounds connecting —
  which is a measurement neither signal gives alone. Untested; this is the design
  consequence of the two schema records above, not an observed result.
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
  but holding fire produces nothing, which is precisely the MASKED case.
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

### `weapon.barrelposition` is a static muzzle offset, not an aim direction
- X4: 9.00
- Status: shipped-source
- Source: `props-9.00/libraries/scriptproperties.xml:1452` ("The position of the
  weapon's barrel (may be 0,0,0 for weapons with no collision)", type `position`);
  vanilla's only meaningful use at `md/cinematiccamera.xml:3224`, which reads
  `$Anchor.barrelposition` and immediately takes `.z` to frame a camera shot
- Live test: no — read from shipped source, untested by this project as of 2026-08-11
- Finding: the property is real, but it is a POSITION, not a direction, and the
  one shipped consumer uses it as a static muzzle offset for camera framing on
  fixed nose guns. Nothing indicates it tracks turret swivel, and it is
  explicitly allowed to be `0,0,0`. Do not build aim-direction logic on it.

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
  preferred target plus a real list actually does, see the OUT OF ARC / OUT OF
  RANGE / MASKED record below.
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
  when the preferred target was MASKED and OUT OF ARC.
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

### preferredtarget falls back on OUT OF ARC and OUT OF RANGE, but not on MASKED
- X4: 9.00
- Status: live-tested
- Corroboration: staged twice against purpose-built hostile groups, with the
  directed mode logged per engage
- Source: in-game trials 2026-08-09 (OUT OF RANGE, MASKED) and 2026-08-10
  (OUT OF ARC), player-piloted capital ship, `set_turret_targets` issued
  narrow-then-wide with `preferredtarget` plus a hostile `target` list and
  `weaponmode="weaponmode.attackenemies"`
- Live test: yes — 2026-08-09 and 2026-08-10, X4 9.00
- Finding: a turret that cannot engage the preferred target rolls to another
  hostile from the supplied list in two of the three fire-control conditions.
  - **OUT OF RANGE** (target 15 km out, far beyond turret reach): falls back.
  - **OUT OF ARC** (target 3 km astern and 1.2 km high, engaged by a group whose
    mount cannot bear on it): falls back. A group that *can* bear on the same
    target engages it normally, which is the control.
  - **MASKED** (turret trained on the target with own hull in the line of fire):
    does **not** fall back. The turret tracks the target and holds fire
    indefinitely. The engine's fallback asks whether the turret can aim, not
    whether it can hit.
- Consequence: MASKED cannot be corrected by re-issuing targets, because the
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
  records above). What is unavailable is polling, not attribution. MASKED itself
  was still never staged and remains unobserved; no fix follows from the answer
  regardless, so the closure of this line of work stands on the fix, not on the
  detectors.
- Limitations: `weaponmode.autoassist` is excluded from all of this — it
  discards script-supplied target lists by construction (Egosoft's own comment,
  `aiscripts/fight.attack.object.capital.xml:1756`), so no fallback list reaches
  it. The fallback selection rule among eligible targets remains unverified; do
  not claim it is nearest-first.

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
  turret — which is what this mod's `PreferAllTurrets` action does.
  (Note the containment direction: `$turretmodes` is built from live turret
  `.mode` reads, so on a ship with a holdfire turret the loop variable can hold a
  value the attribute will not accept.)
- The one thing shipped source cannot answer: whether the engine then honours a
  target list on a holdfire turret, or whether "do not shoot" overrides it. That
  needs a controlled live test, and the source is silent on it. Do not assume
  either way. (Autoassist is separately known to discard the list outright —
  record above.)

### `mayattack` includes relation and fire-authorisation gates
- X4: 9.00
- Status: shipped-source
- Source: `libraries/common.xsd`; `aiscripts/fight.attack.object.capital.xml`
- Live test: no — untested as of 2026-08-03
- Finding: absent an active fire-authorisation override, `mayattack` is true for
  kill relation, or killmilitary against a fight-purpose object. Autoassist
  paths retain this gate when considering `player.target`; selecting a neutral,
  friendly, or player-owned object does not make normal turret AI fire on it.

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
