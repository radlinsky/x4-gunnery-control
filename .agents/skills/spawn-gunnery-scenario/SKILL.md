---
name: spawn-gunnery-scenario
description: Prepare, install, and hand off deterministic X4 Gunnery Control live-test fixtures through Test Lab. Use when a test needs controlled spawned objects, exact placement/loadout identity, or a safe repeatable operator procedure.
---

# Prepare a controlled gunnery scenario

Use Test Lab to turn a live-test requirement into a deterministic fixture and a
small owner checklist. The owner operates X4; the agent owns fixture setup,
validation, installation, and log review.

## Default path

Start with the existing Test Lab capability. Prefer changing only
`testlab/x4_gunnery_control_testlab/ui/scenario_spec.lua`.

Extend reusable Test Lab behavior only when the experiment cannot be expressed
with the existing scenario spec. Do not add helpers, fixture APIs, logging, or
tests merely to make one scenario more convenient.

Work from the exact branch/SHA under test. Keep PR-specific live fixtures
uncommitted where practical. Keep the repository `scenario_spec.lua` disabled;
the Test Lab development installer enables only the installed copy.

Read specialized guidance only when the requested fixture needs it:

- [references/remote-fixtures.md](references/remote-fixtures.md) — spawned player
  ships, teleport handoff, and remote Create/Despawn safety.
- [references/equipment.md](references/equipment.md) — deterministic sparse or
  unusual ship/turret loadouts and exact asset identity.

For turret asset/mount/runtime terminology, use
[../../../docs/TURRET_ASSET_KINEMATICS.md](../../../docs/TURRET_ASSET_KINEMATICS.md).
For X4 API, MD, AI, schema, macro, or shipped-behavior claims, use
`research-x4-modding` rather than guessing.

## 1. Define the proof before editing

Write down only what the experiment needs to control or prove:

- exact player ship and turret-group identity needed by the test;
- one uniquely named fixture role per meaningful control or treatment;
- exact object identity/count and deterministic placement for each role;
- the minimal behavior/safety state needed to keep the fixture stable;
- the visible result and log evidence that will count as PASS or FAIL.

Use deterministic positions: normally `spread = 0` and `behaviour = "wait"` for
controlled targets. Add roles only when each distinguishes a specific predicate.
Never depend on the owner flying or nudging a target into place.

Verify unfamiliar X4 macros and loadout assumptions from current X4 sources.
Do not infer internal ids, slot counts, labels, or equipment identity from a
display name.

For hostile fixtures, use existing Test Lab safety controls where applicable.
READY must depend on the relevant live safety/attackability census, not merely on
a red label or successful spawn.

Qualify only predicates relevant to the experiment. Do not infer CANNOT BEAR,
LINE OF FIRE BLOCKED, targeting, or other engine state from an uncorrelated
no-fire interval.

## 2. Author the smallest fixture

Edit `scenario_spec.lua` first. Its field comments are the source of truth for
the supported fixture schema; do not duplicate that schema here.

For each fixture:

- give it a new scenario id when its meaning changes;
- keep the repository copy `enabled = false`;
- use exact setup identity for the required ship and turret group;
- use role names that tell the owner what each spawned object is for;
- use fixed placement and only the behavior needed by the test;
- specify exact readiness census fields only when the test depends on them.

The Create path must fail closed on a setup identity/census mismatch and must not
leave the owner guessing whether the fixture succeeded. Do not ask the owner to
identify unnamed objects, manually clear old fixtures, position ships, or
manually select a group that the spec can select exactly.

For a remote fixture, read `references/remote-fixtures.md`. Create and Despawn
are destructive replacement/cleanup actions: Test Lab must reject them while an
occupied spawned player fixture could be destroyed. This is a code-level safety
requirement, not just operator wording.

## 3. Validate and load the exact state

Run the relevant repository validation for the files changed, including
`./scripts/validate.sh` and `git diff --check` before accepting repository
changes. Do not weaken valid tests to accommodate a fixture.

Follow [../../../docs/RELOADING.md](../../../docs/RELOADING.md) for installation,
reload, and restart decisions. Apply it to the exact state not yet loaded in X4.
For repeat runs, compute the reset from the files changed since the exact head
already loaded in the current X4 process, not from the full PR diff.
When a restart is required, have the owner use
`scripts/launch-x4-test-lab-dev.bat` from the exact worktree under test; that
launcher installs Test Lab and enables the installed scenario copy.

## 4. Give the owner one exact live-test procedure

Before any live run, read the current version of this skill and give a complete
procedure. The user launches and operates X4; do not ask them to inspect the raw
log.

Always state:

1. the exact tested SHA and required setup/reset;
2. the required save, ship, seat, console, and other setup state;
3. the exact **Gunnery Control → Test Lab** path and displayed scenario id;
4. exactly one **Create test scenario** action for setup;
5. the exact turret group and spawned object names/roles the fixture should
   prepare automatically;
6. whether the gameplay order is **Attack my current enemy** or the default
   **Attack any enemy**;
7. the owner's exact clicks/actions in order and expected visible result;
8. exactly when to stop and upload the debug log;
9. what ChatGPT will inspect in that log;
10. explicit PASS and FAIL conditions.

For a remote fixture, add the exact teleport and single post-teleport Test Lab
open from `references/remote-fixtures.md`; state clearly that Create must not be
pressed again after teleport.

Name controls the owner must not touch when they could invalidate or destroy the
fixture. Do not write vague instructions such as “choose a group,” “pick a
target,” “spawn the ships,” or “repeat as needed.”

## 5. Review evidence yourself

Offline validation proves only OFFLINE behavior. Actual X4 runtime behavior
requires LIVE evidence; a workflow that combines both is MIXED.

For every automated prerequisite, identify the correlated log record or field
that proves it. At minimum, correlate scenario/request identity, acknowledged
spawned count, setup/readiness result, and the exact group/loadout state the
experiment depends on. A stale or mismatched acknowledgement is not proof.

After the owner uploads the log, inspect it yourself. Do not ask the owner to
interpret raw log lines. Treat manual visual observations as owner observations
unless they have matching machine evidence.

For firing/targeting experiments, prefer correlated shot/projectile/hit evidence
when available. A geometry-qualified state proves a geometry solution only; it
does not by itself prove actual turret targeting.

If the evidence cannot distinguish code failure from setup, stale fixture state,
readiness, logging gaps, or unrelated X4 behavior, improve the evidence before
changing behavior unless other evidence already proves the bug.

## 6. Clean up

After the live run:

- keep the repository `scenario_spec.lua` disabled;
- run relevant validation again before committing reusable changes;
- commit only reusable Test Lab behavior or documentation intended to remain;
- do not commit a PR-specific live fixture unless it is intentionally reusable
  infrastructure;
- use **Despawn test scenario** only as explicit post-test cleanup, not as a
  routine prerequisite for creating the next fixture.
