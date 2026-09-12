---
name: spawn-gunnery-scenario
description: Prepare, install, and hand off deterministic X4 Gunnery Control live-test fixtures through Test Lab. Use when a test needs controlled spawned objects, exact placement/loadout identity, or a safe repeatable operator procedure.
---

# Prepare a controlled gunnery scenario

Use Test Lab to turn a live-test requirement into the smallest deterministic
fixture and owner procedure. The owner operates X4; the agent owns fixture setup,
validation, installation, and log review.

Prefer changing only
`testlab/x4_gunnery_control_testlab/ui/scenario_spec.lua`. Extend reusable Test
Lab behavior only when the experiment cannot be expressed there; do not add
helpers, APIs, logging, or tests for one scenario's convenience.

Work from the exact branch/SHA under test. Keep the repository
`scenario_spec.lua` disabled; the development installer enables only its
installed copy.

Read specialized guidance only when needed:

- [references/equipment.md](references/equipment.md) for sparse or unusual
  ship/turret loadouts.
- [references/remote-fixtures.md](references/remote-fixtures.md) for spawned
  player ships, teleport handoff, placement, remote evidence, and Create/Despawn
  safety.
- [../../../docs/TURRET_ASSET_KINEMATICS.md](../../../docs/TURRET_ASSET_KINEMATICS.md)
  for turret asset/mount/runtime terminology.
- [../../../docs/RELOADING.md](../../../docs/RELOADING.md) for reload/restart
  decisions.

Use `research-x4-modding` for X4 API, MD, AI, schema, macro, or shipped-behavior
claims rather than guessing.

## 1. Define the proof first

Specify only the identities, counts, placement, behavior, safety state, and
PASS/FAIL evidence the experiment needs. Give each meaningful control or treatment
one named role. Use deterministic placement; do not depend on the owner manually
positioning objects.

Verify unfamiliar X4 identities and loadout assumptions from current shipped
source. Do not infer ids, slot counts, equipment identity, or other internal facts
from display names.

Before authoring a custom turret loadout, prove that each exact turret macro can
mount on the exact ship and that enough compatible mounts exist. Use the repository
compatibility query when available; until then use `research-x4-modding` against
current shipped source. Incompatible or unresolved compatibility stops before
fixture edits or X4 launch.

Never infer turret-to-ship compatibility from size, race, display name, similar
variants, valid-looking group ids, or an official loadout using another turret
macro. Do not create a local compatibility inventory.

For hostile fixtures, READY must depend on the relevant live
safety/attackability census, not merely a red label or successful spawn. Do not
infer CANNOT BEAR, LINE OF FIRE BLOCKED, targeting, or similar engine state from
an uncorrelated no-fire interval.

## 2. Author the smallest fixture

Treat `scenario_spec.lua` field comments as the fixture-schema authority. Do not
duplicate that schema here.

Use exact setup identity, fixed placement, and only the roles, behavior, and
readiness fields required by the proof. Give the scenario a new id when its
meaning changes. The Create path must fail closed on setup identity or census
mismatch and must not require the owner to identify, clear, position, or select
objects manually when the fixture can do so exactly.

For sparse or unusual equipment, follow `references/equipment.md`. For remote
fixtures, follow `references/remote-fixtures.md` instead of duplicating its
operator or safety rules here.

## 3. Validate and load the exact state

Run relevant focused validation, `./scripts/validate.sh`, and `git diff --check`.
Do not weaken valid tests. Scenario data needs no dedicated unit test; add the
smallest regression test only when reusable Test Lab behavior changes.

Follow `docs/RELOADING.md` for the exact state not yet loaded in X4. For repeat
runs, base reset/reload decisions on changes since the exact head already loaded,
not the full PR diff. When a restart is required, launch
`scripts/launch-x4-test-lab-dev.bat` from the exact worktree under test.

## 4. Give one exact live-test procedure

The user launches and operates X4. Never ask them to inspect the raw log.

State:

1. exact tested SHA and required setup/reset;
2. required save, ship, seat, console, and other setup state;
3. exact **Gunnery Control → Test Lab** path and scenario id;
4. exact Create/setup action and fixture-prepared ship, group, and role names;
5. whether gameplay uses **Attack my current enemy** or default
   **Attack any enemy** (selector: **Attack all enemies**);
6. exact owner actions and expected visible result;
7. exactly when to stop and upload the debug log, and what ChatGPT will inspect;
8. explicit PASS and FAIL conditions.

For remote fixtures, include the operator flow required by
`references/remote-fixtures.md`. Name any controls the owner must not touch when
they could invalidate or destroy the fixture.

## 5. Review the evidence

Offline validation proves only OFFLINE behavior; actual X4 runtime behavior needs
LIVE evidence. A workflow using both is MIXED.

Inspect the uploaded log yourself. Correlate every automated prerequisite with
the same scenario/request identity, including spawn acknowledgement, readiness,
and exact group/loadout state. Treat stale or mismatched acknowledgements as no
proof.

For firing or targeting tests, prefer correlated shot/projectile/hit evidence.
A geometry-qualified state proves geometry only, not actual turret targeting.

If the evidence cannot distinguish code failure from setup, stale fixture state,
readiness, logging gaps, weapon readiness, stale projectiles, or unrelated X4
behavior, improve the evidence before changing behavior unless other evidence
already proves the bug.

## 6. Preserve the tested state

Commit and push the PR-specific fixture with the work it tested so checking out
the commit restores the scenario. Keep the repository `scenario_spec.lua`
disabled. Use **Despawn test scenario** only for explicit post-test cleanup.
