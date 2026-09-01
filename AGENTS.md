# Asking the owner to reload or restart X4

The owner drives the game; you cannot. The shared Claude/Codex PostToolUse hook
(`.agents/hooks/reload-advice.sh`) states the reset for each edit — follow it.
Three things still require whole-task judgment:

- **The strictest category wins across the whole not-yet-loaded delta.** For a
  first test, compare the branch under test with the version currently loaded
  by X4. For a repeat test in the same X4 process, compare the new installation
  with the exact head already loaded and tested. A new/deleted X4-loaded file,
  or a changed `t/`, `ui.xml` or `content.xml` in that delta, means a restart;
  an unchanged restart-only file that X4 already loaded does not require a
  second restart. If the loaded baseline is uncertain, restart. Changes that
  span multiple independent reload categories also mean one restart.
- **If the change could break the gunnery menu, ask for a restart.** Test Lab is
  reachable only through that menu, so a broken menu leaves no button to click.
- **Say it once, at the end, with authority**, naming what changed and exactly
  one reset. Never offer reload-or-restart as a choice.

[docs/RELOADING.md](docs/RELOADING.md) is the table;
`tests/test_reload_advice.sh` is the cross-client contract. Change all three
together.

# Test value

Tests protect stable behavior, not temporary experiment setup. See
[`tests/README.md`](tests/README.md) for the permanent-suite boundary.

- Add or keep a test only when it names a realistic regression in production
  code, reusable Test Lab behavior, or repository tooling.
- Prefer the smallest behavioral contract that would fail if that regression
  returned. Do not snapshot implementation details or duplicate the code under
  test when a real behavior can be exercised instead.
- `testlab/x4_gunnery_control_testlab/ui/scenario_spec.lua` is mutable live-test
  input. Changing a live fixture must not require changing unit tests. Test the
  Test Lab validator and transport with small synthetic specs instead.
- Do not make exact live scenario ids, labels, coordinates, rotations, target
  macros, or historical operator setups permanent CI contracts unless that
  exact identity is itself required product behavior.
- After a live experiment is settled, preserve its durable result in the owning
  issue and, when reusable, the X4 research knowledge base. Retire
  fixture-specific CI tests unless they still protect a continuing product or
  reusable Test Lab contract.
- When an existing test is expensive or brittle, first identify the regression
  it prevents. If no current behavior depends on it, delete it rather than
  updating it.

# X4 research

Route X4 modding API, feasibility, unpacked Lua/MD/AI/XSD, and evidence-KB work
through `$research-x4-modding`. Preserve its evidence classifications and do
not upgrade observations without reproduction. Never commit unpacked game,
catalog/data, or third-party extension files. Use
[docs/TURRET_ASSET_KINEMATICS.md](docs/TURRET_ASSET_KINEMATICS.md) as the
canonical turret asset, mounting, runtime-instance, and muzzle identity
vocabulary; do not infer one identity from another's spelling.

Treat each use as feedback on the skill. When research exposes a repeated
lookup, missing source route, stale claim, unsafe/manual step, or reusable
command, improve the skill's concise workflow, focused references, scripts,
or regression tests within the task's write authority. Iterate on these
improvements, validate every skill change, and keep uncertain findings
classified as inference or experimental.
