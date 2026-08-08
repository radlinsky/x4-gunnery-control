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
- Live test: yes — reproduced in the described X4 9.00 trial on 2026-08-07
- Finding: a turret on the flank facing away from the target rotates to track
  it but never fires, observed over 30 seconds. Autoassist therefore hands the
  target to every armed turret regardless of firing solution, and a turret with
  no solution neither picks another target nor reverts to its own behaviour. It
  is the assignment that is exclusive, not merely the firing. This is the
  idle-turret cost of Direct-control.

### A preferred target without a target list frees turrets from their mode
- X4: 9.00
- Status: live-tested
- Source: in-game trial 2026-08-07; `set_turret_targets` issued with
  `preferredtarget` and no `target` list, once per distinct turret mode on a
  player-owned ship
- Live test: yes — reproduced in the described X4 9.00 trial on 2026-08-07
- Finding: turrets that cannot attack the preferred target engage something
  else in range rather than holding fire, and that choice is **not** limited by
  the turret's own mode. Every turret on a ship set entirely to
  `missiledefence` opened fire on ships once the preference was applied, with
  no missiles present. Treat `weaponmode` on `set_turret_targets` as selecting
  which turrets receive the instruction, not as a constraint on what they
  subsequently shoot. The exact fallback selection rule is unverified; do not
  claim it is nearest-first.

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
