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

Verify every macro against the installed/current X4 sources through
`research-x4-modding`; do not trust memory for an untested macro.

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
            behaviour = "wait",
            hostile   = true,
        },
    },
}

return X4GunneryTestLabScenarioSpec
```

Every spawned ship is named `<label> <index>`. Labels must state the test role,
not merely `enemy` or `target`.

Position uses ship-local axes: positive `distance` is forward, negative is
astern, positive `x` is right, and positive `y` is up. Random spread cannot
stage repeatable bearing, elevation, range, or masking controls.

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

### 6. Give a complete operator handoff

The final instruction before the live run must contain all of these, in order:

1. Exact reset and exact worktree launcher.
2. Required save, ship, seat, and console state.
3. Exact menu path.
4. Exact displayed scenario id.
5. Exactly one setup action: **Create test scenario**.
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

- `action=requested`: exact spec, expected ship count, raw group, turret ids;
- `action=ready`: acknowledged count and exact selected group;
- `action=rejected|failed|timeout`: do not continue the gameplay checklist.

MD logs `[X4GC TEST SCENARIO]` creation details and the final spawned count.
After the owner reports completion, inspect logs yourself. Do not ask the owner
to interpret raw logs. Keep owner observations experimental until reproduced.

### 8. Clean up

- Restore `enabled = false` before any commit.
- Run the full validation again.
- Do not commit a PR-specific fixture unless the fixture itself is intentional
  reusable test infrastructure and remains disabled.
- Use **Despawn test scenario** only for explicit cleanup after testing, not as
  a precondition for creating the next fixture.

## Geometry guardrails

- For a guaranteed `MASKED` control, place a named stationary capital ship on
  the segment between turret ship and candidate. Make it player-owned when it
  must be excluded from the hostile browser. This establishes an intervening
  obstruction, not own-hull masking.
- Keep an `OUT OF RANGE` control independently clear of blockers. Confirm its
  per-turret line of fire separately when the test needs that distinction.
- Do not infer `OUT OF ARC`, `MASKED`, or `NO SOLUTION` from a no-fire interval.
  Follow `turret-fire-control-language` and instrument the actual predicate.

## Transport and evidence basis

Lua streams flat scalar events because nested Lua tables are not a verified MD
payload. `scenario_begin` carries the spec/request ids, each `scenario_group`
carries one definition, and `scenario_commit` replaces then creates. MD returns
a scalar acknowledgement containing the globally retained monotonic UI-load
generation, request serial, spec id, and actual spawned count. Stale or
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
