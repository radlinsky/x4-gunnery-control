# Asking the owner to reload or restart X4

The owner drives the game; you cannot. A PostToolUse hook
(`scripts/reload-advice.sh`) states the reset for each file you edit — follow it.
Three things it cannot know, because it sees one file at a time:

- **The strictest category wins across the whole change.** A new or deleted file,
  or any `t/`, `ui.xml` or `content.xml` edit, means a restart even when
  `ui/*.lua` also changed and the hook said Reload UI.
- **If the change could break the gunnery menu, ask for a restart.** Test Lab is
  reachable only through that menu, so a broken menu leaves no button to click.
- **Say it once, at the end, with authority**, naming what changed and exactly
  one reset. Never offer reload-or-restart as a choice.

[docs/RELOADING.md](docs/RELOADING.md) is the table; `tests/test_reload_advice.sh`
is the test. Change all three together.

# X4 research

Route X4 modding API, feasibility, unpacked Lua/MD/AI/XSD, and evidence-KB work
through `$research-x4-modding`. Preserve its evidence classifications and do
not upgrade observations without reproduction. Never commit unpacked game,
catalog/data, or third-party extension files.

Treat each use as feedback on the skill. When research exposes a repeated
lookup, missing source route, stale claim, unsafe/manual step, or reusable
command, improve the skill's concise workflow, focused references, scripts,
or regression tests within the task's write authority. Iterate on these
improvements, validate every skill change, and keep uncertain findings
classified as inference or experimental.
