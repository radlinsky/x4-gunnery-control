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
