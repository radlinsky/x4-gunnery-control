---
name: spawn-gunnery-scenario
description: Build, install, and operate deterministic X4 Gunnery Control live-test fixtures through Test Lab. Use whenever a test needs named spawned ships, exact placement, exact turret-group selection, or an operator checklist with human-error controls.
---

# Spawn a controlled gunnery scenario

Turn a live-test requirement into one safe operator action. The owner drives X4;
the agent owns every automatable prerequisite, fixture detail, installation
check, and evidence check.

## Operator identity: custom player-facing labels

In game the owner sees only names. Macros, variables, group ids, component ids,
and list positions do not exist for them. A fixture must therefore create its
own CUSTOM PLAYER-FACING LABELS: every spawned ship, target, and surface element
the owner must select gets a unique in-game readable label, and every operator
instruction references only those labels.

- Ships: spec `label` becomes `<label> <index>` through `set_object_name`
  (`testlab/.../md/x4_gunnery_control_testlab_scenario.xml:543`). Labels state
  the test role, not `enemy` or `target`.
- Surface rows show the component's native name. Make the requested row unique
  with a sparse loadout or the proven `[TEST TARGET]` prefix
  (`testlab/.../ui/testlab.lua:1015`; `ui/gunnery_control.lua:2570`).
- `[TEST TARGET]` is only a prefix; it does **not** change component type. The
  handoff and acceptance evidence must include the marked row's native name,
  kind, and macro. Never describe a marked turret as an engine.
- Duplicate rows are not operator-selectable until one is uniquely marked.
  Never ask the owner to infer a row from internal ids, list order, hull
  position, engageability, or logs.

Verify every macro against installed/current X4 sources through
`research-x4-modding`; do not trust memory for an untested macro.

## Non-negotiable outcome

Normal workflow: sit at the named ship's gunnery console, open **Gunnery Control
→ Test Lab**, confirm the displayed scenario id, click **Create test scenario**
once.

For a `setup.remote = true` fixture:

1. Sit at any safe launcher's gunnery console and click **Create test scenario**
   exactly once.
2. Wait for the acknowledgement, then teleport to the exact named spawned ship:
   - `READY: remote fixture verified` — fully qualified;
   - `PENDING: ... geometry is NOT qualified` — census passed, a discriminator
     must still run in system.
3. Open that ship's gunnery console and open **Test Lab exactly once**:
   - READY auto-selects the exact group and returns to Gunnery Control;
   - PENDING runs its in-system qualification on that single open, possibly
     moving the same preserved object through a bounded logged position search
     with a nonzero delay before each measurement. It selects the group and
     returns ONLY on `QUALIFIED`, and for a Direct-control test also marks the
     qualified target and surface — the owner still performs every
     Direct-control, target, and surface click. On `FAILED` or timeout it stops
     closed: leave X4 open, preserve the evidence, report the displayed text,
     press nothing, and do not retry coordinates by hand.
4. Continue the checklist. Never press Create after teleport.

Create is destructive replacement. In a live 2026-08-23 failure, a second Create
while aboard the spawned shooter despawned the occupied ship, orphaned the
player/camera context, and crashed X4. Test Lab must disable and reject Create
while teleport is pending and whenever the current gunnery ship matches the
remote shooter; operator wording is not a safety guard.

Despawn is equally destructive. It must be disabled aboard the remote shooter,
and its click handler must re-check occupancy so a handler captured on the safe
launcher cannot later destroy the occupied ship. MD cleanup must independently
reject cleanup or replacement while `player.ship` belongs to the fixture.

Create must: refuse a visible ship-name or macro mismatch, missing raw group, or
wrong operational-turret count; leave the prior fixture and checkbox state
untouched after a failed preflight; clear the previous fixture; create and name
every requested ship; verify the acknowledged count; keep staged state unchanged
until a matching acknowledgement, then revalidate ship/loadout, clear all groups,
and tick only the specified one; return to Gunnery Control only on success.

Do not ask the owner to position ships, identify unnamed ships, clear old
fixtures, tick a group the spec can identify, or infer whether spawning
succeeded. **Reload UI**, **Re-run current spec**, and **Despawn test scenario**
are not routine operator steps. If the branch under test lacks the one-click
setup API, backport it rather than writing a longer manual checklist.

## Agent workflow

### 1. Isolate the PR under test

Work from that PR's exact branch/worktree with only its merged bases. Create
fixtures only for the current PR. Keep the live fixture uncommitted: the
repository fixture must finish with `enabled = false`.

### 2. Eliminate uncontrolled variables

Before editing, define the exact player ship macro and visible name; the exact
raw turret group id, visible label, and operational-member count; one uniquely
named group per role; deterministic `distance`, `x`, `y`; expected rows, state
changes, and log evidence; and what keeps fixtures alive and stationary.

Prefer `behaviour = "wait"`, `spread = 0`, and out-of-range targets when the test
only concerns menus. Add a role only when it distinguishes a specific predicate.
Never depend on the owner flying targets into position.

For an isolated conventional-turret shooter, the loadout must omit pilot-operated
main guns and every turret outside the selected group. Before READY, census
`weapons.operational`, `turrets.operational`, and `missileturrets.operational`
separately, verify the exact required turret-macro multiset, and hold both
ordinary and missile turrets in HOLD FIRE until post-teleport group activation. A
member count alone cannot distinguish two copies of the wrong macro.

### Deterministic turret equipment

Mount turrets with group-targeted `<turrets macro="..." group="..." exact="N"/>`
entries under `<groups>`. Never isolate a turret with singular
`<turret path="..."/>`: on the Behemoth E both singular routes produced an empty
ship while group-targeted entries equipped it (evidence: research `md-ai.md`,
singular-turret record). Singular paths remain valid for engines, large shields,
and main guns.

A group-targeted entry equips the whole group. Resolve its exact slot count and
connection/equipment tags from current X4 sources; with multiple slots, isolate
behavior through per-turret FIRED/HIT attribution rather than an unsupported
per-slot loadout. READY must verify the exact operational count and macro
multiset, not that some turret exists.

The proven Test Lab transport creates equipped ships. For stations, a
`create_station` result, module count, or visible shell is NOT evidence of an
equipped surface-targeting fixture: withhold READY until the correlated live
census confirms the expected modules and the minimum operational turrets, missile
turrets, shields, and engines.

Remote station creation and equipment are live-tested in X4 9.00. Scenarios
`issue-67-arc-barrel-two-phase-r6` and r9 each created a remote operational
`xen_defence` station, selected one real operational defence module, and applied
an exact loadout to it; their same-action-list censuses already showed 5 modules,
2 standard M lasers, and 4 M shields, and the 1 ms remote and post-teleport
censuses were identical. Do not switch to local creation or add a delay to solve
an empty census (research `md-ai.md`, "A remote operational station can receive
exact turret and shield equipment synchronously").

X4 documents `apply_loadout object=` as either a ship or a **station module**.
Never pass the station root. After `create_station`, take the intended object
from `$Station.modules.operational.list`, verify its exact macro, and apply to
that module:

- Exact safe set: build a `create_loadout` with group-targeted `<turrets .../>`
  and `<shields .../>`, then `apply_loadout object="$Module"`. Verify the
  equipment macro's component tags and integrated/path semantics against the
  module's connection tags first. r6's non-integrated
  `turret_xen_m_laser_02_mk1_macro` in `group01` succeeded; r5's integrated
  `turret_xen_m_gatling_01_mk1_macro` as a group entry silently installed zero
  turrets while its shields succeeded. Macro existence alone is insufficient.
- Full faction loadout on operational modules: iterate the module list,
  `generate_loadout` with the station macro plus the exact module macro and
  faction equipment pool, then `apply_loadout object="$Module"`.
  `md.$EquipmentTable` is a vanilla global populated in `md/setup.xml`, including
  Xenon.

Keep immediate, delayed, and final censuses when timing is under test, but READY
must depend on the final exact census, never on creation success, module count,
or an assumed timing rule.

### Surface-geometry fixture contract

Create a remote fixture in the resolved remote sector; `player.zone` still
belongs to the safe launcher. Tight angular geometry must not rely on absolute
coordinates: after teleport, resolve the exact selected weapon position P*, place
or reposition preserved targets at `P* + stored offset`, preserve their authored
rotation, and fail closed on every reposition/post-warp mismatch.

1. Verify the exact shooter weapon macro/count and target loadouts.
2. Resolve live P* and apply deterministic P*-relative transforms.
3. Qualify each role against the same exact component the owner will click;
   never combine a root predicate with a different module/surface.
4. Check range, firing arc, attackability, and line-of-fire predicates
   independently so CANNOT BEAR and LINE OF FIRE BLOCKED cannot be confused.
5. Give every role its own exact component id, predicates, unique label/marker,
   and designation/observation correlation.
6. Test Lab may select the weapon group and mark aids, but must not call
   `SetSofttarget` or perform the Direct-control root/surface click.
7. Arm observation only after Gunnery accepts the owner's exact manual click.
8. Accept behavior only from correlated per-weapon FIRED and exact-component HIT
   records; an uncorrelated no-fire interval proves nothing.

A qualifier-time line-of-sight result immediately after a warp may be transient:
in the #67 r32 run both exact surfaces read `0/0` during qualification, then
`1/1` about three seconds later, and were hit. Keep such reads as telemetry
unless the experiment establishes a settled LOS gate.

#### Single marked-objective invariant

For a Direct-control fixture, define one `$ObjectiveComponent` and enforce this
entire chain mechanically:

1. Controls qualify independently and are never designation candidates.
2. `QUALIFIED` requires exactly one objective candidate plus its expected
   component kind/macro and every production-equivalent gate under test.
3. Emit exactly one token/component pair: `$ObjectiveComponent`. Never emit a
   control first or add an optional second target to an existing bridge.
4. The suggested component, marked row, `operator_designated` component, observer
   target, FIRED `aimed`, and HIT `hitcomp` must correlate to that same component.
5. Zero, multiple, wrong-type, or missing candidates return `FAILED` before the
   menu returns to Gunnery.

Do not retrofit a new marked objective into a qualifier built for another test.
Add an independent named role/pose when the existing controls do not reproduce
that objective on the current run. A prior run's component id or geometry is
seed evidence, never proof that a fresh instance still contains the discriminator.

Use a bounded search only when its predicates resolve in the current attention
state. Otherwise preserve the deterministic candidate, report geometry-PENDING,
and measure once in system. A generated coordinate is not deterministic until its
exact predicates reproduce on a fresh instance.

| Failed pattern | Required correction |
|---|---|
| Different root/module supplies each predicate | Qualify and designate one exact component. |
| Control qualifies but objective is absent | Make the objective mandatory; fail on zero/multiple candidates. |
| More than one component crosses the marker bridge | Emit one pair for the objective only. |
| Marker text contradicts native row type | Treat native kind/macro as authoritative and fail qualification. |
| Absolute remote coordinates drift from the weapon | Store P*-relative offsets and reapply after teleport. |
| Moving modular target changes every ray | Stop moving it; use independently placed stationary ships. |
| Singular turret loadout empties the ship | Use group-targeted turret entries and exact census. |
| Duplicate visible surface labels | Use a sparse unique loadout or proven marker. |
| Automated surface write fails | Exercise normal manual root→surface selection. |
| Immediate post-warp LOS blocks all candidates | Treat as telemetry until a settled LOS contract is proved. |
| One role qualifies, control does not | Qualify and correlate every role independently. |

Prefer stationary capital targets with defence units removed and weapons held
fire. `hostile = true` is not proof of authorization: withhold READY unless
`player.ship.mayattack.{$Target}` is true for every requested hostile fixture.

### 3. Author the complete spec

Edit only `testlab/x4_gunnery_control_testlab/ui/scenario_spec.lua`. Use a new id
and include `setup`:

```lua
X4GunneryTestLabScenarioSpec = {
    id      = "pr-number-purpose-r1",
    enabled = false,
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

`holdFire=true` must add the ship to the persistent safety guard, set every
operational turret/missile turret to HOLD FIRE, and repeatedly cease fire.
`stripDefenceUnits=true` must remove carried defence units before hostility is
applied. READY must report zero unsafe weapons, zero remaining defence units, and
the expected attackable-hostile count.

`repairGuard=true` must keep the fixture attackable by repairing the victim ship
and exact struck component after each player-ship hit. Do not substitute
minimum-hull or invulnerability flags; vanilla target selection can exclude
indestructible or invulnerable surfaces. READY must report the exact
repair-guarded count before the owner fires.

Position uses ship-local axes: positive `distance` forward, negative astern,
positive `x` right, positive `y` up. Random spread cannot stage repeatable
bearing, elevation, range, or masking controls.

For a remote absolute-anchor fixture, give no group `distance = 0`: the Lua-to-MD
receiver treats scalar zero as missing and substitutes its 5 km default. Use a
shared nonzero base offset (shooter `1`, blocker `2101`, target `4201`).

For a solid-obstruction control, an outer silhouette is insufficient: capital
meshes can contain openings that admit exact muzzle rays. Require the owner to
confirm no part of the target is visible through or around the blocker, and
require `muzzle_los_ex=0` for every weapon the control claims to block, before
permitting fire. The catalog-verified Asgard macro is
`ship_atf_xl_battleship_01_a_macro`; resolve unfamiliar macros from catalog
assets rather than inferring a faction prefix from a display name.

`behaviour`: `wait` holds position (default for controlled targets); `attack`
approaches and fires (only when incoming fire is the variable); `none` gives no
order (normally a player-owned platform/blocker).

### 4. Validate without weakening the guard

The committed spec always stays `enabled = false`; never hand-edit that line.
A dev install is always for a live run, so `scripts/install-dev.sh` (run from
`scripts/launch-x4-test-lab-dev.bat`) copies the Test Lab into the game's
extensions dir and flips `enabled` to `true` on the installed copy only — the
offline suite keeps seeing `false`. Validate the repo file as-is:

1. Keep the spec at `enabled = false` (do not toggle it).
2. Run `./scripts/validate.sh` and `git diff --check`.
3. Confirm `git diff` contains only the intended fixture/spec change.

Never bypass or edit the disabled-fixture test, and never commit a spec with
`enabled = true`.

### 5. Install the exact worktree

Discover the X4 root through `research-x4-modding`, then run from the PR's
worktree:

```bash
X4GC_INSTALL_TESTLAB=1 ./scripts/install-dev.sh "<X4 root>"
```

Verify both `x4_gunnery_control` and `x4_gunnery_control_testlab` installed, and
link the launcher from that same worktree.

Follow repository reload policy: a change to Test Lab MD, translations, `ui.xml`,
`content.xml`, a new/deleted X4-loaded file, or multiple reload categories needs a
full restart. A scenario-spec-only edit stays governed by the repository
hook/advice.

For a repeat run, compute the reset from the files changed since the exact head
already installed and loaded in the current X4 process — not from the PR's full
base diff. If a prior restart already loaded an unchanged translation or
structural file, a follow-up changing only `ui/*.lua` needs install + **Reload
UI**. Record the loaded head before iterating; if that baseline is unknown, X4
exited, another worktree was installed, or the menu may be broken, require the
full restart.

### 6. Give a complete operator handoff

The final instruction must contain, in order:

1. Exact reset and exact worktree launcher.
2. Required save, ship, seat, and console state.
3. Exact menu path.
4. Exact displayed scenario id.
5. Exactly one setup action: **Create test scenario**. For a remote fixture add
   the teleport and the single post-teleport Test Lab opening, state whether that
   opening selects the group directly (READY) or first runs an in-system
   qualification that marks the manual targets only on `QUALIFIED` and stops
   closed on `FAILED`, and that Create must not be pressed again either way.
6. What success does automatically, including the selected group and any marked
   rows, explicitly distinguished from the owner clicks under test.
7. Exact spawned names and expected distances/roles.
8. Every test action in click order.
9. Exact expected visible result for each action.
10. What evidence the agent will inspect afterwards.
11. One failure instruction: stop, leave X4 open, report the displayed `FAILED:`
    text, and do not improvise with reload/despawn buttons.

Say which controls the owner must **not** touch. Never write "choose a group,"
"pick a target," "spawn the ships," or "repeat as needed."

### 7. Verify evidence before accepting

The one-click path logs `[X4GC TEST] event=scenario_create`:
`event=scenario_runtime action=loaded` (engine time, loaded spec);
`action=requested` (request token, spec, expected count, group, turret ids);
`action=ready` (same token, acknowledged count, selected group);
`action=rejected|failed|timeout` (do not continue).

A geometry-PENDING remote fixture instead logs `action=remote_geometry_pending`
at Create, and the single post-teleport open logs `event=geometry_qualify
action=requested` followed by exactly one of `action=qualified` (aids ready;
observation still off until the owner's exact click) or `action=failed|timeout`
(stop closed). Require exactly one transported objective and a separate
`operator_designated` record before timed observation. Verify that the qualified
native kind/macro and component id match the marked row, designation, observer,
FIRED `aimed`, and HIT `hitcomp`; a generic `qualified` record is insufficient.
When a qualifier compares root and module geometry, preserve its independent
root/module origin and aim, range, and external line-of-fire fields; `qualified`
is not a claim about which point the engine actually uses.

MD logs `[X4GC TEST SCENARIO]` creation details and the final spawned count.
Inspect logs yourself; do not ask the owner to interpret them, and keep owner
observations experimental until reproduced.

Before accepting, turn the checklist into an evidence matrix: every required
automated step maps to a distinct log event or correlated field, and repeated
actions are counted explicitly (two Create clicks = two tokens and two `ready`
records). Report any missing record instead of accepting a general "passed," and
label unloggable visual assertions as owner observations. For hostile safety
fixtures also require the correlated READY fields `safe_fixtures`,
`safe_weapons`, `unsafe_weapons`, `defence_units`, and `hostiles`; a red label is
not the primary check.

### 8. Clean up

Confirm the spec is still `enabled = false` before any commit (the dev-bat may
have flipped only the installed copy), run the full validation again, and do not
commit a PR-specific fixture unless it is intentional reusable, disabled test
infrastructure. Use **Despawn test scenario** only for explicit cleanup after
testing, never as a precondition for the next fixture.

## Geometry guardrails

- For a guaranteed `LINE OF FIRE BLOCKED` control, place a named stationary
  capital ship on the segment between turret ship and candidate; make it
  player-owned when it must be excluded from the hostile browser.
- Keep an `OUT OF RANGE` control clear of blockers, and confirm its per-turret
  line of fire separately when the test needs that distinction.
- Do not infer `CANNOT BEAR`, `LINE OF FIRE BLOCKED`, or `NO FIRING SOLUTION`
  from a no-fire interval. Follow `turret-fire-control-language` and instrument
  the actual predicate.

## Transport and evidence basis

Lua streams flat scalar events because nested tables are not a verified MD
payload: `scenario_begin` carries spec/request ids, each `scenario_group` one
definition, `scenario_commit` replaces then creates. MD returns a scalar
acknowledgement with an engine-monotonic request timestamp, serial, spec id, and
actual spawned count; stale or mismatched replies are ignored. Despawn is
disabled while a request is pending.

The spawner is XSD-validated against X4 9.00. `create_ship`, `safepos`, Wait and
Attack orders, dynamic macro lookup, relation boosts, and guarded destruction are
grounded in extracted shipped scripts recorded by `research-x4-modding`. Dynamic
`faction.{string}` remains an inference with a logged Xenon fallback.

## Validation

After Test Lab or skill changes run:

```bash
./scripts/validate.sh
python3 /home/pc/.codex/skills/.system/skill-creator/scripts/quick_validate.py \
  .agents/skills/spawn-gunnery-scenario
```

Also run `tests/test_research_x4_skill.sh` when this workflow changes research
routing or evidence claims.
