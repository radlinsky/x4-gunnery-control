---
name: spawn-gunnery-scenario
description: Prepare, install, and hand off deterministic X4 Gunnery Control live-test fixtures through Test Lab. Use when a test needs controlled spawned objects, exact placement/loadout identity, or a safe repeatable operator procedure.
---

# Prepare a controlled gunnery scenario

Use Test Lab to turn a live-test requirement into the smallest deterministic
fixture and owner procedure. The owner operates X4; the agent owns setup,
validation, installation, and log review.

Prefer changing only
`testlab/x4_gunnery_control_testlab/ui/scenario_spec.lua`. Extend reusable Test
Lab behavior only when the experiment cannot be expressed there; do not add
helpers, APIs, logging, or tests for one scenario's convenience.

Read only when relevant:

- [references/equipment.md](references/equipment.md) before a custom or unusual
  ship/turret loadout.
- [references/remote-fixtures.md](references/remote-fixtures.md) when
  `setup.remote = true` or the player must teleport into a spawned shooter.

## 1. Define the proof

Control only the identities, counts, placement, behavior, safety state, and
PASS/FAIL evidence the experiment needs. Give each meaningful control or treatment
one named role and use deterministic placement.

Before authoring a custom turret loadout, prove that each exact turret macro can
mount on the exact ship and that enough compatible mounts exist. Use the repository
compatibility query when available; until then use `research-x4-modding` against
current shipped source. Stop before fixture edits or X4 launch if compatibility is
incompatible or unresolved.

Never infer turret-to-ship compatibility from size, race, display name, similar
variants, valid-looking group ids, or an official loadout using another turret
macro. Do not create a local compatibility inventory.

For hostile fixtures, READY must depend on the relevant live safety/attackability
census. Do not infer geometry or targeting state from an uncorrelated no-fire
interval.

## 2. Author the smallest fixture

Treat `scenario_spec.lua` field comments as the fixture-schema authority. Use
exact setup identity, fixed placement, and only the roles, behavior, and readiness
fields required by the proof. Give the scenario a new id when its meaning changes.
The Create path must fail closed on setup identity or census mismatch and must not
require manual identity, cleanup, placement, or selection that the fixture can do
exactly.

## 3. Validate and load

Run relevant focused validation, `./scripts/validate.sh`, and `git diff --check`.
Follow [../../../docs/RELOADING.md](../../../docs/RELOADING.md) for the required
reset.

## 4. Give one exact live-test procedure

The user launches and operates X4. Never ask them to inspect the raw log.

State:

1. exact tested SHA and required setup/reset;
2. required save, ship, seat, console, and other setup state;
3. exact **Gunnery Control → Test Lab** path and scenario id;
4. exactly one **Create test scenario** action and the ship, group, and role names
   the fixture prepares;
5. whether gameplay uses **Attack my current enemy** or default
   **Attack any enemy** (selector: **Attack all enemies**);
6. exact owner actions and expected visible result;
7. exactly when to stop and upload the debug log, and what ChatGPT will inspect;
8. explicit PASS and FAIL conditions.

## 5. Review the evidence

Offline validation proves only OFFLINE behavior; actual X4 runtime behavior needs
LIVE evidence. A workflow using both is MIXED.

Inspect the uploaded log yourself. Correlate automated prerequisites with the same
scenario/request identity, including spawn acknowledgement, readiness, and exact
group/loadout state. Treat stale or mismatched acknowledgements as no proof.

For firing or targeting tests, prefer correlated shot/projectile/hit evidence. A
geometry-qualified state proves geometry only, not actual turret targeting.

If the evidence cannot isolate the cause of a failure, improve the evidence before
changing behavior unless other evidence already proves the bug.
