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

### Turret gimbal/traverse arc is not exposed to mods
- X4: 9.00
- Status: inference
- Source: `props-9.00/libraries/scriptproperties.xml` weapon/turret datatypes (~lines 1441–1461); ship component XML under `ships-comp-base-9.00`; turret macro XML under `cutscenes-9.00/assets/props/WeaponSystems/`; `schemas-9.00/libraries/common.xsd`
- Live test: no — untested as of 2026-08-09
- Finding: no arc, cone, or gimbal-limit property was found on the weapon or turret datatype. Turret macros expose `rotationspeed` and `rotationacceleration` only, not angular limits. This is a negative result bounded by the sources searched above. It does not matter in practice: finding 1 (check_line_of_sight) supersedes the need for arc data — the engine's own combat AI never tests an arc and uses LOS + range as its complete solution check.

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
  `common.xsd:2419` for `weaponmodelookup` versus `extendedweaponmodelookup`
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
  `holdfire` are not members of `weaponmodelookup` (`common.xsd:2419`) and are
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
  but the two candidate detectors were never tested — see the scope notes on the
  `check_line_of_sight` record above and on `GetLastAttackInfo` in
  ui-lua-menu-camera.md. Neither was pursued because no fix follows from the
  answer.
- Limitations: `weaponmode.autoassist` is excluded from all of this — it
  discards script-supplied target lists by construction (Egosoft's own comment,
  `aiscripts/fight.attack.object.capital.xml:1756`), so no fallback list reaches
  it. The fallback selection rule among eligible targets remains unverified; do
  not claim it is nearest-first.

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
