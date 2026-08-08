# Asking the owner to reload or restart X4

The owner drives the game; you cannot. Every time you ask them to pick a change
up in game, say **which** reset, with authority. Read
[docs/RELOADING.md](docs/RELOADING.md) and apply its table to the files you
actually changed. Never offer "reload or restart" as a choice for them to make.

Say it in this shape: what changed, whether the installer needs to run, and
exactly one of **Reload UI** / **Reload MD** / **Reload AI** / **full restart via
the launcher**. When a change spans categories the strictest wins: any new or
deleted file, or any `t/`, `ui.xml` or `content.xml` edit, means a restart even
if `ui/*.lua` also changed.

Run `scripts/install-dev.sh "<game path>"` yourself before asking for a reload.
A reload reads loose files from disk, so an uninstalled change looks exactly
like a broken reload. A full restart through `scripts/launch-x4-dev.bat`
installs on its own; do not run the installer first in that case.

If the change could break the gunnery menu, ask for the restart: Test Lab is
reachable only through that menu, so a broken menu leaves no button to click.

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
