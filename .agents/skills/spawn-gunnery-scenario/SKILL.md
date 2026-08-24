---
name: spawn-gunnery-scenario
description: Build, install, and operate deterministic X4 Gunnery Control live-test fixtures through Test Lab. Use whenever a test needs named spawned ships, exact placement, exact turret-group selection, or an operator checklist with human-error controls.
---

# Spawn a controlled gunnery scenario

Turn a live-test requirement into one safe operator action. The owner drives X4;
the agent owns every automatable prerequisite, fixture detail, installation
check, and evidence check.

## Non-negotiable outcome

The normal owner workflow is:

1. Sit at the named ship's gunnery console.
2. Open **Gunnery Control → Test Lab**.
3. Confirm the displayed scenario id.
4. Click **Create test scenario** once.

For a `setup.remote = true` fixture, use this distinct workflow:

1. Sit at any safe launcher's gunnery console and click **Create test scenario**
   exactly once.
2. Wait for the acknowledgement, then teleport to the exact named spawned player
   ship. Two acknowledgements are possible:
   - `READY: remote fixture verified` — the fixture is fully qualified.
   - `PENDING: ... geometry is NOT qualified` — the census passed but a geometry
     discriminator must still run in system (a fixture whose classification
     split only resolves once the player shares the fixture's system).
3. Open that ship's gunnery console and open **Test Lab exactly once**:
   - a READY fixture auto-arms the exact group and immediately returns to
     Gunnery Control;
   - a PENDING fixture runs its in-system qualification on that single open. It
     may automatically move the same preserved object through a bounded logged
     position search, with a nonzero delay before measuring each position. It
     auto-arms and returns to Gunnery Control ONLY on `QUALIFIED`. On `FAILED`
     (or a timeout) it stops closed: leave X4 open, preserve the evidence, and
     report the displayed text. Do not press Create, Reload UI, or Despawn, and
     do not retry coordinates manually.
4. Continue the gameplay checklist. Never press Create after teleport.

Create is destructive replacement. In a live 2026-08-23 failure, a second
Create while aboard the spawned shooter despawned the occupied ship, orphaned
the player/camera context, and crashed X4. A remote-capable Test Lab must disable
and reject Create while teleport is pending and whenever the current gunnery
ship exactly matches the remote shooter; operator wording is not a sufficient
safety guard.

Despawn is equally destructive. It must be disabled aboard the remote shooter,
and its click handler must re-check occupancy so a handler captured while the
owner was still on the safe launcher cannot later destroy the occupied ship.
Mission Director cleanup must independently reject cleanup or replacement while
`player.ship` belongs to the spawned fixture.

That button must:

- refuse a visible ship-name or macro mismatch, missing raw group, or wrong
  operational-turret count;
- leave the prior fixture and checkbox state untouched after a failed preflight;
- clear the previous Test Lab fixture;
- create and name every requested ship;
- verify the acknowledged ship count;
- keep checkbox/staged state unchanged until a matching acknowledgement, then
  revalidate the ship/loadout, clear all groups, and tick only the specified one;
- return to Gunnery Control only after successful acknowledgement.

Do not ask the owner to position ships, identify unnamed ships, manually clear
old fixtures, manually tick a group that the spec can identify, or infer whether
spawning succeeded. Do not use **Reload UI**, **Re-run current spec**, or
**Despawn test scenario** as a routine operator step.

If the branch under test lacks the one-click setup API, stop and add/backport
the Test Lab prerequisite. Do not compensate with a longer manual checklist.

## Agent workflow

### 1. Isolate the PR under test

- Work from that PR's exact branch/worktree, including only its merged bases.
- Create fixtures only for the current PR. Later PRs may change while defects
  are repaired.
- Keep the live fixture uncommitted. The repository fixture must finish with
  `enabled = false`.

### 2. Eliminate uncontrolled variables

Before editing, define:

- exact player ship macro and visible ship name;
- exact raw turret group id, visible label, and operational-member count;
- one uniquely named group per test role;
- deterministic `distance`, `x`, and `y` for every group;
- expected row values, state changes, and log evidence;
- conditions that keep fixtures alive and stationary.

Prefer `behaviour = "wait"`, `spread = 0`, and targets outside weapon range when
the test only concerns menus. Use multiple roles only when each distinguishes a
specific predicate. Never depend on the owner flying targets into position.

For an isolated conventional-turret shooter, the deterministic loadout must
omit pilot-operated main guns and every turret outside the selected group.
Before READY, census `weapons.operational`, `turrets.operational`, and
`missileturrets.operational` separately, verify the exact required turret-macro
multiset, and put both ordinary and missile turrets in HOLD FIRE until the
post-teleport group activation. A member count alone cannot distinguish two
copies of the wrong macro.

When one turret group needs different macros in individual slots, resolve the
hull's exact connection names from current extracted assets and use singular
`<turret macro="..." path="../connection_name"/>` entries in a Test-Lab-only
static named `libraries/loadouts.xml` definition, then create the ship with
`<loadout ref="..."/>`. Do not use an MD `<create_loadout>` result for this
case: two X4 9.00 Behemoth E attempts returned a completely empty ship even
after the singular paths were source-verified. Verify more than macro
existence: compare the hull connection tags with the equipment component's
connection tags. An alias may reference a component with different slot
compatibility than its canonical macro. Keep the live operational macro census
as the fail-closed proof that both connection assignments took. Never derive a
connection name from visible order, a previous hull, or an assumed zero-padded
sequence; record the exact shipped component source beside the fixture evidence
before the first live run.

Verify every macro against the installed/current X4 sources through
`research-x4-modding`; do not trust memory for an untested macro.

The proven Test Lab transport creates equipped ships. For stations, a
`create_station` result, construction-plan module count, or visible shell is
NOT evidence of an equipped surface-targeting fixture: withhold READY until the
correlated live census confirms the expected modules and the minimum
operational turrets, missile turrets, shields, and engines.

Remote station creation and equipment are live-tested in X4 9.00. Scenario
`issue-67-arc-barrel-two-phase-r6` created a remote operational `xen_defence`
station, selected one real operational defence module, and applied an exact
loadout to that module. Its same-action-list census already showed 5 modules,
2 standard M lasers, and 4 M shields; the 1 ms remote census and post-teleport
in-system census were identical. Do not switch to local creation or add a delay
to solve an empty census. See research `md-ai.md` "A remote operational station
can receive exact turret and shield equipment synchronously" for the bounded
evidence and rejected control.

The object target is critical: X4 documents `apply_loadout object=` as either a
ship or a **station module**. Never pass the station root. After
`create_station`, choose the intended object from
`$Station.modules.operational.list`, verify its exact macro, and apply to that
module:

- For an EXACT safe set, build a `create_loadout` with group-targeted
  `<turrets .../>` and `<shields .../>`, then
  `apply_loadout object="$Module"`. Verify the equipment macro's component tags
  and integrated/path semantics against the module's connection tags before the
  run. The r6 control used non-integrated
  `turret_xen_m_laser_02_mk1_macro` in `group01` and succeeded immediately.
  The preceding r5 request used integrated
  `turret_xen_m_gatling_01_mk1_macro` as a group entry and silently installed
  zero turrets while its shields succeeded; shipped loadouts use that gatling
  through singular path-targeted entries. Macro existence alone is insufficient.
- For a full faction loadout on already-operational modules, follow the earlier
  proven Test Lab shape: iterate the module list, `generate_loadout` with the
  station macro plus the exact module macro and faction equipment pool, then
  `apply_loadout object="$Module"`. Vanilla also supports sequence/index
  generation and application while finalising a construction sequence.
  `md.$EquipmentTable` is a vanilla global populated in `md/setup.xml`, including
  Xenon; do not mistake the absence of a repository assignment for an absent
  game-global table.

Keep the immediate, delayed, and final operational census when timing itself is
under test, but READY must always depend on the final exact census rather than
on creation success, module count, or an assumed timing rule.

Remote stations must be created with the resolved remote `sector` and an exact
sector-space `position`; `player.zone` still belongs to the safe launcher at
Create time. When the test depends on mesh-selected aim geometry, decide where
the discriminating measurement can actually run:

- If the classification split resolves at Create time, prefer a small bounded
  automatic position search. Keep only a candidate that satisfies the required
  per-weapon split, and withhold READY if none does.
- If the split can only resolve once the player is in the fixture's system (a
  hittable-aim-target measurement that does not resolve out of system), do NOT
  run an out-of-system search or destroy candidates: preserve exactly one
  deterministic candidate at its authored position, verify its census, and
  report a distinct geometry-PENDING state rather than READY. Re-measure that
  same preserved object against the same exact weapons on the single
  post-teleport Test Lab open, and qualify only on the required split; no split
  fails closed.

For a position search around a large station, reject candidates whose station-
root bounding box overlaps or nearly touches the shooter; a geometrically useful
module is not a safe fixture when the hull volumes intersect. When module layout
orientation matters, set and log a deterministic station rotation for every
trial rather than inheriting an implicit creation orientation. Keep position,
rotation, separation, range, bearing, and external line of fire as independent
fields.

Never ask the owner to retry guessed coordinates in either case.

Do not use the equipped defence station as a clean per-turret arc fixture: it
launches defence drones and clusters many surfaces at nearly the same bearing.
Use it for pagination/performance and broad surface-browser tests. For exact
fire attribution, prefer one stationary capital ship with carried defence
units removed before hostility, all weapons held fire, and an isolated surface
candidate.

`hostile = true` is a requirement, not proof. A temporary object relation boost
did not make a Terran-owned Osaka attackable by the player in the live 9.00
test. Prefer a naturally hostile owner such as Xenon and withhold READY unless
`player.ship.mayattack.{$Target}` is true for every requested hostile fixture.

### 3. Author the complete spec

Edit only
`testlab/x4_gunnery_control_testlab/ui/scenario_spec.lua` for the live fixture.
Use a new id and include `setup`:

```lua
X4GunneryTestLabScenarioSpec = {
    id      = "pr-number-purpose-r1",
    enabled = true,
    setup   = {
        shipMacro       = "ship_bor_l_destroyer_01_a_macro",
        shipLabel       = "Ray",
        turretGroup     = "group_front_up_left",
        turretLabel     = "Front Upper Left",
        expectedTurrets = 2,
    },
    groups  = {
        {
            label     = "A CLEAR CONTROL",
            macro     = "ship_xen_m_fighter_01_a_macro",
            faction   = "xenon",
            count     = 1,
            distance  = 5000,
            x         = 0,
            y         = 1200,
            spread    = 0,
            behaviour         = "wait",
            hostile           = true,
            holdFire          = true,
            stripDefenceUnits = true,
            repairGuard       = true,
        },
    },
}

return X4GunneryTestLabScenarioSpec
```

Every spawned ship is named `<label> <index>`. Labels must state the test role,
not merely `enemy` or `target`.

For safe hostile capital targets, `holdFire=true` must add the ship to the
persistent safety guard, set every operational turret/missile turret to HOLD
FIRE, and repeatedly cease fire. `stripDefenceUnits=true` must remove carried
defence units before hostility is applied. READY must report zero unsafe
weapons, zero remaining defence units, and the expected attackable-hostile
count.

For repeated hit-attribution tests, `repairGuard=true` must keep the fixture
attackable by repairing the victim ship and exact struck component after each
player-ship hit. Do not substitute minimum-hull or invulnerability flags;
vanilla target selection can exclude indestructible or invulnerable surfaces.
READY must report the exact repair-guarded fixture count before the owner fires.

Position uses ship-local axes: positive `distance` is forward, negative is
astern, positive `x` is right, and positive `y` is up. Random spread cannot
stage repeatable bearing, elevation, range, or masking controls.

For a remote absolute-anchor fixture, do not give any group `distance = 0`.
The current Lua-to-MD receiver treats scalar zero as a missing optional value
and substitutes its 5 km default. Use a shared nonzero base offset (for
example, shooter `1`, blocker `2101`, target `4201`) so all intended relative
separations remain exact. Confirm masking visually before permitting fire and
compare the observer's target distance with the designed geometry.

For a solid-obstruction control, a blocker's outer silhouette is insufficient:
capital-ship meshes can contain hangar or structural openings that admit exact
muzzle rays. Require the owner to confirm that no part of the target is visible
through or around the blocker, then require `muzzle_los_ex=0` for every weapon
the control claims to block before permitting fire. The catalog-verified Asgard
macro is `ship_atf_xl_battleship_01_a_macro`; resolve unfamiliar ship macros
from selected catalog assets before authoring the spec rather than inferring a
faction prefix from the display name.

`behaviour`:

- `wait`: hold position; default for controlled targets.
- `attack`: approach and fire; use only when incoming fire is the variable.
- `none`: no explicit order; normally for a player-owned platform/blocker.

### 4. Validate without weakening the guard

The repository test intentionally rejects an enabled committed fixture:

1. Temporarily set `enabled = false` with `apply_patch`.
2. Run `./scripts/validate.sh` and `git diff --check`.
3. Restore `enabled = true` with `apply_patch`.
4. Confirm `git diff` contains only the intended uncommitted fixture change.

Never bypass or edit the disabled-fixture test.

### 5. Install the exact worktree

Discover the X4 root through `research-x4-modding`, then run from the PR's
worktree:

```bash
X4GC_INSTALL_TESTLAB=1 ./scripts/install-dev.sh "<X4 root>"
```

Verify installation succeeded for both `x4_gunnery_control` and
`x4_gunnery_control_testlab`. When asking for a reset, link the launcher from
the same exact worktree—not another checkout.

Follow repository reload policy. A change to Test Lab MD, translations,
`ui.xml`, `content.xml`, a new/deleted X4-loaded file, or multiple reload
categories requires a full restart. A scenario-spec-only edit remains governed
by the repository hook/advice; do not carry a private exception from older
experiments.

For a repeat run, compute the reset from the files changed since the exact head
already installed and loaded in the current X4 process—not from the PR's full
base diff. If a prior restart already loaded an unchanged translation or
structural file, a follow-up that changes only production/Test Lab `ui/*.lua`
needs install + **Reload UI**, not another restart. Record the loaded head before
iterating. If that baseline is unknown, X4 exited, another worktree was
installed, or the gunnery menu may be broken, require the full restart.

### 6. Give a complete operator handoff

The final instruction before the live run must contain all of these, in order:

1. Exact reset and exact worktree launcher.
2. Required save, ship, seat, and console state.
3. Exact menu path.
4. Exact displayed scenario id.
5. Exactly one setup action: **Create test scenario**. For a remote fixture,
   explicitly add the teleport and the single post-teleport Test Lab opening.
   State whether that opening auto-arms directly (a READY fixture) or first runs
   an in-system qualification that auto-arms only on `QUALIFIED` and stops closed
   on `FAILED` (a geometry-PENDING fixture), and that Create must not be pressed
   again either way.
6. What success does automatically, including the selected turret group.
7. Exact spawned names and expected distances/roles.
8. Every test action in click order.
9. Exact expected visible result for each action.
10. What evidence the agent will inspect afterward.
11. One failure instruction: stop, leave X4 open, and report the displayed
    `FAILED:` text; do not improvise with reload/despawn buttons.

Explicitly say which controls the owner must **not** touch. Never write “choose
a group,” “pick a target,” “spawn the ships,” or “repeat as needed.” Name the
single correct group, target, button, and expected result.

### 7. Verify evidence before accepting

The one-click path logs `[X4GC TEST] event=scenario_create`:

- `event=scenario_runtime action=loaded`: engine time and loaded spec;
- `action=requested`: exact request token, spec, expected count, group, turret ids;
- `action=ready`: the same request token, acknowledged count, selected group;
- `action=rejected|failed|timeout`: do not continue the gameplay checklist.

For a geometry-PENDING remote fixture, Create instead logs
`action=remote_geometry_pending`, and the single post-teleport Test Lab open
logs `event=geometry_qualify action=requested` followed by exactly one of
`action=qualified` (a measured fixture-specific geometry candidate passed, group
armed, observation on) or
`action=failed|timeout` (stop closed). Treat those as the qualification's
distinct evidence records; the fixture is not armed until `action=qualified`.
When a qualifier compares root and module geometry, inspect and preserve its
independent root-origin/root-aim, module-origin/module-aim, range, and external
line-of-fire fields. Do not collapse `qualified` into a claim about which target
point the engine actually uses; only the subsequent timed test can establish
that behavior.

MD logs `[X4GC TEST SCENARIO]` creation details and the final spawned count.
After the owner reports completion, inspect logs yourself. Do not ask the owner
to interpret raw logs. Keep owner observations experimental until reproduced.

Before accepting, turn the operator checklist into an evidence matrix. Every
required automated step must map to a distinct log event or correlated field.
Count repeated actions explicitly (for example, two Create clicks require two
different request tokens and two `ready` records). If any required record is
missing, report the incomplete step and continue the live test; never accept a
general “passed” report as proof of unlogged steps. If a manual visual assertion
cannot be logged, label it as the owner's observation rather than automation.
For hostile safety fixtures, also require the correlated READY fields for
`safe_fixtures`, `safe_weapons`, `unsafe_weapons`, `defence_units`, and
`hostiles`; a visible red/neutral label is not the primary check.

### 8. Clean up

- Restore `enabled = false` before any commit.
- Run the full validation again.
- Do not commit a PR-specific fixture unless the fixture itself is intentional
  reusable test infrastructure and remains disabled.
- Use **Despawn test scenario** only for explicit cleanup after testing, not as
  a precondition for creating the next fixture.

## Geometry guardrails

- For a guaranteed `LINE OF FIRE BLOCKED` control, place a named stationary capital ship on
  the segment between turret ship and candidate. Make it player-owned when it
  must be excluded from the hostile browser. This establishes an intervening
  obstruction, not own-hull masking.
- Keep an `OUT OF RANGE` control independently clear of blockers. Confirm its
  per-turret line of fire separately when the test needs that distinction.
- Do not infer `CANNOT BEAR`, `LINE OF FIRE BLOCKED`, or `NO FIRING SOLUTION` from a no-fire interval.
  Follow `turret-fire-control-language` and instrument the actual predicate.

## Transport and evidence basis

Lua streams flat scalar events because nested Lua tables are not a verified MD
payload. `scenario_begin` carries the spec/request ids, each `scenario_group`
carries one definition, and `scenario_commit` replaces then creates. MD returns
a scalar acknowledgement containing an engine-monotonic request timestamp,
request serial, spec id, and actual spawned count. Stale or
mismatched replies are ignored. Despawn is
disabled while a request is pending and defensively invalidates correlation.

The spawner is XSD-validated against X4 9.00. `create_ship`, `safepos`, Wait and
Attack orders, dynamic macro lookup, relation boosts, and guarded destruction
are grounded in the extracted shipped scripts recorded by
`research-x4-modding`. Dynamic `faction.{string}` remains an inference with a
logged Xenon fallback.

## Validation

After Test Lab or skill changes run:

```bash
./scripts/validate.sh
python3 /home/pc/.codex/skills/.system/skill-creator/scripts/quick_validate.py \
  .agents/skills/spawn-gunnery-scenario
```

Also run `tests/test_research_x4_skill.sh` when this workflow changes research
routing or evidence claims.
