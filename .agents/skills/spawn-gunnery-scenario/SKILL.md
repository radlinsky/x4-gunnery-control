---
name: spawn-gunnery-scenario
description: Prepare, install, and hand off deterministic X4 Gunnery Control live-test fixtures through Test Lab. Use when a test needs controlled spawned objects, exact placement/loadout identity, or a safe repeatable operator procedure.
---

# Prepare a controlled gunnery scenario

Use Test Lab to turn a live-test requirement into a deterministic fixture and a
small owner checklist. The owner operates X4; the agent owns fixture setup,
validation, installation, and log review.

## Default path

Start with the existing Test Lab capability. Prefer a change only to
`testlab/x4_gunnery_control_testlab/ui/scenario_spec.lua`.

Extend reusable Test Lab behavior only when the required experiment cannot be
expressed with the existing scenario spec. Do not add helpers, fixture APIs,
logging, or tests merely to make one historical scenario more convenient.

Work from the exact branch/SHA under test. Keep a live PR-specific fixture
uncommitted where practical, and always leave the repository fixture with
`enabled = false` before committing.

Read specialized guidance only when the requested fixture needs it:

- [references/remote-fixtures.md](references/remote-fixtures.md) — spawned player
  ships, teleport handoff, remote Create/Despawn safety, deferred qualification.
- [references/surface-geometry.md](references/surface-geometry.md) — surface
  selection, arc/line-of-fire experiments, weapon-relative placement, bounded
  searches.
- [references/equipment-and-stations.md](references/equipment-and-stations.md) —
  sparse or unusual X4 loadouts, surface identity, station equipment.

For turret asset/mount/runtime terminology, use
[../../../docs/TURRET_ASSET_KINEMATICS.md](../../../docs/TURRET_ASSET_KINEMATICS.md).
For X4 API, MD, AI, schema, macro, or shipped-behavior claims, use
`research-x4-modding` rather than guessing.

## 1. Define the proof before editing

Write down only what the experiment needs to control or prove:

- exact player ship macro and visible name;
- exact raw turret group id, visible label, operational member count, and exact
  required member-macro multiset when identity matters;
- one uniquely named fixture role per meaningful control or treatment;
- exact object macro/faction/count and deterministic placement for each role;
- the minimal behavior/safety state needed to keep the fixture stable;
- the exact visible result and log evidence that will count as PASS or FAIL.

Use deterministic positions: normally `spread = 0` and `behaviour = "wait"` for
controlled targets. Add roles only when each one distinguishes a specific
predicate. Never depend on the owner flying or nudging a target into place.

Verify unfamiliar X4 macros and loadout assumptions from current X4 sources.
Do not infer internal ids, slot counts, labels, or equipment identity from a
display name.

For isolated shooter fixtures, census ordinary operational game emitters,
ordinary turrets, and missile turrets separately. Verify the exact required
macro multiset when the experiment depends on equipment identity; a member count
alone is not enough.

For hostile fixtures, use existing Test Lab safety controls such as HOLD FIRE
and defence-unit removal where applicable. READY must depend on the relevant
live safety/attackability census, not merely on a red label or successful spawn.

Qualify only predicates relevant to the experiment. Do not infer CANNOT BEAR,
LINE OF FIRE BLOCKED, targeting, or other engine state from an uncorrelated
no-fire interval.

## 2. Author the smallest fixture

Edit `scenario_spec.lua` first. Its field comments are the source of truth for
the currently supported fixture schema; do not duplicate that schema here.

For each live fixture:

- give it a new scenario id when its meaning changes;
- set `enabled = true` only for the live copy being installed;
- use exact setup identity for the required ship and turret group;
- use role names that tell the owner what each spawned object is for;
- use fixed placement and only the behavior needed by the test;
- specify exact readiness census fields when the test depends on them.

The Create path must fail closed on a setup identity/census mismatch and must
not leave the owner guessing whether the fixture succeeded. Do not ask the
owner to identify unnamed objects, manually clear old fixtures, position ships,
or manually select a group that the spec can select exactly.

For a remote fixture, read `references/remote-fixtures.md`. Create and Despawn
are destructive replacement/cleanup actions: Test Lab must reject them while an
occupied spawned player fixture could be destroyed. This is a code-level safety
requirement, not just operator wording.

## 3. Validate the repository state

Before committing any fixture or skill/Test Lab change:

1. Restore `scenario_spec.lua` to `enabled = false`.
2. Run `./scripts/validate.sh`.
3. Run `git diff --check`.
4. For this skill, run:

```bash
python3 /home/pc/.codex/skills/.system/skill-creator/scripts/quick_validate.py \
  .agents/skills/spawn-gunnery-scenario
```

Run `tests/test_research_x4_skill.sh` as well if the change alters research
routing or research/evidence claims.

Do not weaken the repository's disabled-fixture guard to validate an enabled
live fixture.

## 4. Install the exact state to be tested

Discover the X4 root through `research-x4-modding`, then install from the exact
branch/worktree under test:

```bash
X4GC_INSTALL_TESTLAB=1 ./scripts/install-dev.sh "<X4 root>"
```

Verify both the main extension and Test Lab install succeeded. Use the launcher
from that same exact worktree when a full restart is required.

Follow the repository reload policy for the files actually changed. For repeat
runs, compute the reset from the files changed since the exact head already
installed and loaded in the current X4 process, not from the PR's entire base
diff. Record the loaded head before iterating.

If the loaded baseline is unknown, X4 exited, another worktree was installed, or
the gunnery/Test Lab UI may be stale or broken, require the safer full restart.
Do not carry private reload exceptions from old experiments into a new run.

## 5. Give the owner one exact live-test procedure

Before any live run, read the current version of this skill and give a complete
procedure. The user launches and operates X4; do not ask them to inspect the raw
log.

Always state:

1. the exact tested SHA and required install/reset;
2. the required save, ship, seat, console, and other setup state;
3. the exact **Gunnery Control → Test Lab** path and displayed scenario id;
4. exactly one **Create test scenario** action for setup;
5. the exact turret group and spawned object names/roles the fixture should
   prepare automatically;
6. whether the gameplay order is **Attack my current enemy** or the default
   **Attack any enemy**;
7. the owner's exact clicks/actions in order and the expected visible result;
8. exactly when to stop and upload the debug log;
9. what ChatGPT will inspect in that log;
10. explicit PASS and FAIL conditions.

For a remote fixture, add the exact teleport and single post-teleport Test Lab
open from `references/remote-fixtures.md`; state clearly that Create must not be
pressed again after teleport.

Name the controls the owner must not touch when they could invalidate or destroy
the fixture. Do not write vague instructions such as “choose a group,” “pick a
target,” “spawn the ships,” or “repeat as needed.”

## 6. Review evidence yourself

Offline validation proves only OFFLINE behavior. Actual X4 runtime behavior
requires LIVE evidence; a workflow that combines both is MIXED.

For every automated prerequisite, identify the distinct correlated log record or
field that proves it. At minimum, correlate scenario id/request identity,
acknowledged spawned count, setup/readiness result, and the exact group/loadout
state the experiment depends on. A stale or mismatched acknowledgement is not
proof.

After the owner uploads the log, inspect it yourself. Do not ask the owner to
interpret raw log lines. Treat manual visual observations as owner observations
unless they have matching machine evidence.

For firing/targeting experiments, prefer correlated shot/projectile/hit evidence
when available. `ON SOLUTION` proves a geometry solution only; it does not by
itself prove actual turret targeting.

If the evidence cannot distinguish code failure from setup, stale fixture state,
readiness, logging gaps, or unrelated X4 behavior, improve the evidence before
changing behavior unless other evidence already proves the bug.

## 7. Clean up the repository state

After the live run:

- restore `enabled = false` before any commit;
- run full validation and `git diff --check` again;
- commit only reusable Test Lab behavior or documentation intended to remain;
- do not commit a PR-specific live fixture unless it is intentionally reusable
  infrastructure and remains disabled;
- use **Despawn test scenario** only as explicit post-test cleanup, not as a
  routine prerequisite for creating the next fixture.
