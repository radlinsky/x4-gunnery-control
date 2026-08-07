# X4 Gunnery Control Developer Guide

This guide takes a contributor from a fresh clone to a tested development ZIP.
It covers the main extension and the separate, developer-only Test Lab. The
normal player package intentionally does not contain this guide, Test Lab, test
fixtures, or development scripts.

## 1. Know the scope before changing code

X4 Gunnery Control is a fire-control console, not a replacement for X4's turret
simulation. **Auto-engage** is camera-only and must not change any turret
setting. **Direct-control** temporarily overrides every checked mutable group
and must restore all of them on exit.

Both modes land in a compact upper-right live panel with four POV buttons
(Turret/Target × manual/cinematic) and Next/Prev turret cycling.
Direct-control additionally keeps Select Engagement Target, Cease Engagement,
and a Next Target / Previous Target row (cycles through the same candidate list
in the same order as the target browser; greyed when one candidate or fewer).
A separate upper-left element panel, shown only in direct mode, is titled with
the engaged target's name and lists Hull and every operational surface element;
the active one is greyed. Clicking another element re-engages it.

The cinematic POV uses `<play_cutscene cinematicmode="true">` from MD; the game
UI (including this panel) is hidden while the cutscene runs, so the player must
use `Esc` to exit — Next/Prev are unreachable during a cinematic. Turrets keep
firing while the cinematic is active (live-tested). A running cutscene cannot be
re-aimed without stopping and restarting it; the player sees a brief camera cut
on retarget.

The camera-view frames request no vanilla HUD or ticker
(`keepHUDVisible=false`, `showTickerPermanently=false`). The ticker-only
implementation can still display transient mission updates and notifications, so
these properties are not proof that every bottom-left Messages item is suppressed.

Directional group identifiers in vanilla ship macro XML (for example,
`group_front_up_left`) can be humanized, but the runtime group/slot structures
do not expose a dedicated transform or positional-name field. Always retain a
numbered fallback for opaque identifiers such as `group01`; never invent a
direction from turret ordering alone.

Do not equate a Lua session table with ownership of an X4 menu. X4's Helper can
auto-hide a frame, call `menu.cleanup`, and clear `menu.shown` without invoking
`menu.onCloseElement`. Lifecycle and visual phase must therefore be separate:

| Lifecycle | Meaning | Allowed result |
|---|---|---|
| inactive | No owned session | Chair ingress may create a console |
| owned | Helper frame and session agree | Current visual phase may run |
| suspending_map / suspended_map | Map is the verified replacement menu | Preserve guarded state only |
| reopening | One epoch-fenced Map return is pending | Reacquire frame/camera or fail safe |
| orphaned / ending | Frame ownership was lost or the player left | Restore override, cockpit view, and clear |

### Phase and control-mode model

The session has two independent pieces of state:

| Field | Values | Meaning |
|---|---|---|
| `session.phase` | `console`, `target_select`, `engaged` | Which UI page is visible |
| `session.controlMode` | `nil`, `"auto"`, `"direct"` | Engagement mode while `phase == "engaged"` |

The old `watch` and `direct` phases are gone. `phase = "engaged"` with
`controlMode = "auto"` is what Watch was; `controlMode = "direct"` is what the
old Direct phase was.

Camera state is two axes:

| Field | Values |
|---|---|
| `session.povAnchor` | `"turret"` or `"target"` |
| `session.povMode` | `"manual"` or `"cinematic"` |

`applyPov()` is the single entry point that reads both axes and either calls
`SetPlayerCameraTargetView` (manual, after stopping any running cutscene) or
`sendCutsceneAimStart` (cinematic).

Map is the first explicitly supported resumable interruption because UI
Extensions exposes a Map cleanup callback. Do not claim generic resume for every
global menu: until a menu has a verified close hook, losing the gunnery frame
must restore any Direct-control override and end safely. `playerGetUp` and
`playerUndock` are always terminal. Every delayed camera or redisplay callback
must capture the session object and epoch; abort stale work after suspension,
cleanup, or a later re-seat. A suspended callback must not restore an earlier
soft target over a target the player selected in Map.

**Direct-control never re-issues the turret order by itself.** The order is a
soft target set once at engage time; when that target is destroyed the camera
follows on to the next candidate but the turrets fall back to autoassist. Next
Target / Previous Target is how the player re-orders them. Auto-engage is
unaffected — its turrets pick their own targets and the camera re-checks on the
5 s cadence.

**ID normalisation.** Raw FFI values such as the return of `targetRoot()`
stringify with a `ULL` suffix; `id()`-converted values do not. A bare
`tostring()` comparison therefore judges the same component as two different
objects. Always compare through `State.normID()`. For the same reason,
`GetComponentData` silently returns `nil` for every key when passed a raw FFI
id; route every call through the `componentData()` wrapper, which applies
`id()` first.

### Safety requirements

- **Direct-control may override every checked mutable group at once.** The
  previous "never override more than one group at a time" invariant is
  intentionally relaxed; the new obligation is that restore is exhaustive.
- Snapshot the exact mode and armed state of each group before changing either
  value (`session.directSnapshots` is a list, one entry per overridden group).
- `restoreDirect` loops over every snapshot. A per-entry failure (group
  destroyed or unresolvable) is logged and skipped; the loop never aborts.
  One destroyed group must not strand the remaining groups on armed `autoassist`.
- Only groups passing `State.canMutate` (non-ambiguous, at least one operational
  member) are snapshotted. An ambiguous group is never written.
- Restore when Direct-control is ceased, the console is closed, the player
  chooses Get Up (which leaves the chair), the player changes ship, the game
  plan changes, or a save is loaded. Do not treat `Esc` as a release event.
- Auto-engage never snapshots and never restores; it mutates nothing.
- Do not mutate a group when physical-turret-to-group mapping is ambiguous.
- Test the selected target directly: a whole object and a surface element are
  distinct engagement cases. Preserve the target ID/connection across camera
  transitions where X4 exposes one.
- Never treat a whole-ship camera fallback as a turret-camera success.
- Keep Test Lab out of the normal Nexus archive.
- Do not copy or replace Egosoft files or dependency source files.

Do not conflate the bridge asset's `gunnertrigger` cockpit tag with the runtime
control group. `GetPlayerCurrentControlGroup()` reports `gunnercontrol` while
the player occupies the Access Gunnery Control chair. At that secondary post,
`GetPlayerOccupiedShipID()` can be zero. Resolve the ship through the player's
enclosing `container`, as X4 9.00's shipped `DockedMenu` does, and verify that
the container is a ship before using it.

**The leave-seat helptext popup is load-bearing — do not suppress it.**
An X4 engine bug (confirmed by three in-game trials) leaves Esc dead after
`SetPlayerCameraTargetView` is called from a turret seat. The only observed cure
is a subsequent menu that calls `CreateView`/`DisplayView` (i.e.
`View.createView()` in `ego_viewhelper/viewhelper.lua:38`, which only runs when
`View.frames` is empty). The `show_help` action in the `Notify` MD cue forces
that path on every seat exit. Making the popup conditional or "tidying it away"
without re-testing Esc after a camera session would silently re-introduce the
bug. Known ceiling: if the player has hints/help disabled in game options the
popup may not display and the Esc bug would return. See
`.agents/skills/research-x4-modding/references/ui-lua-menu-camera.md` ("Engine
bug: SetPlayerCameraTargetView leaves Esc dead after get-up") for the full
three-arm trial record, the list of every candidate cure that was ruled out, and
the diagnosis methodology.

Read [README.md](README.md) for the user-facing behavior and
[TESTING.md](TESTING.md) for the current in-game test matrix before making a
runtime change.

For X4 API, feasibility, unpacked-source, or evidence-KB work, invoke
`$research-x4-modding <question>`. The skill searches evidence before sources,
retains classifications, and only writes verified durable findings after an
explicit invocation or a request to update the KB.

## 2. Prepare the development computer

You need:

- a legal X4 Foundations installation, version 9.00 or newer;
- [kuertee UI Extensions and HUD](https://www.nexusmods.com/x4foundations/mods/552),
  version 9.00 or newer;
- Git;
- Bash;
- Lua 5.1 runtime and compiler;
- `xmllint` from libxml2;
- ShellCheck;
- `zip` and `unzip`.

Most validation, installation, and packaging scripts are Bash scripts. On
Linux, use the normal terminal. On Windows, the simplest reproducible build
setup is WSL 2 with Ubuntu; Git Bash or MSYS2 can also work if all of the
commands above are on `PATH`. The Windows game launcher is a native Batch file
and does not require Bash after the loose files have been installed.

### Ubuntu, Debian, or WSL Ubuntu

```bash
sudo apt-get update
sudo apt-get install -y git bash lua5.1 libxml2-utils shellcheck zip unzip
```

Confirm the required commands:

```bash
git --version
bash --version
lua5.1 -v
luac5.1 -v
xmllint --version
shellcheck --version
zip -v
unzip -v
```

`luac5.1 -v` can print its version to standard error; that is normal. If the
machine only provides commands named `lua` and `luac`, validation will use
those fallbacks. Confirm that they really are compatible with Lua 5.1 before
trusting the result.

### Native Windows alternative

Install Git for Windows and MSYS2, then install equivalent MSYS2 packages for
Lua 5.1, libxml2, ShellCheck, zip, and unzip. Run repository scripts from the
same MSYS2 shell. Do not mix Windows and WSL tool paths in one command. If native
tool setup becomes difficult, use WSL and access the game through `/mnt/c`.

## XML schemas and VS Code validation

X4 resolves the `#modding` schema path through its virtual filesystem; VS Code
does not. For the installed X4 9.00 build, use the X Catalog Tool to extract
these entries from `<X4_ROOT>/08.cat` into a local directory outside this
repository, preserving their catalog paths:

```text
<X4_SCHEMA_ROOT>/
├── libraries/common.xsd
├── libraries/md.xsd
├── md/md.xsd
├── ui/core/addon.xsd
└── ui/core/coreaddon.xsd
```

The Mission Director chain is exact and small:

```text
md/md.xsd
  └── ../libraries/md.xsd
        └── common.xsd
```

`ui/core/addon.xsd` is self-contained. `coreaddon.xsd` is useful when
reviewing vanilla `ego_*` UI addons; this project uses `addon.xsd`. Do not copy
schemas into this repository or try to derive raw `.dat` offsets by hand.

Install **XML Language Support by Red Hat** in VS Code. Add this
machine-specific configuration to VS Code User Settings, replacing the paths
with the extracted schema directory. Do not commit workstation-specific paths.

```json
{
  "xml.fileAssociations": [
    {
      "pattern": "**/x4-gunnery-control/md/*.xml",
      "systemId": "file:///absolute/path/to/X4_SCHEMA_ROOT/md/md.xsd"
    },
    {
      "pattern": "**/x4-gunnery-control/ui.xml",
      "systemId": "file:///absolute/path/to/X4_SCHEMA_ROOT/ui/core/addon.xsd"
    },
    {
      "pattern": "**/x4-gunnery-control/testlab/*/ui.xml",
      "systemId": "file:///absolute/path/to/X4_SCHEMA_ROOT/ui/core/addon.xsd"
    }
  ]
}
```

On Windows, use forward-slash file URIs, for example
`file:///C:/X4Schemas/md/md.xsd`. Reload VS Code after changing associations.
If `md/md.xsd` cannot resolve `../libraries/md.xsd`, re-extract the schemas
with their catalog directory layout intact. Do not associate `content.xml` or
`t/*.xml` with `ui/core/addon.xsd`; they are different X4 XML formats.

## How to find reliable X4 modding information

Treat the exact installed game build as the starting point, not an old forum
post or an unrelated mod. Record the value in `version.dat`, then inspect the
matching catalogs and UI Extensions version before deciding that an API,
callback, or schema is available.

1. Use XSD go-to-definition first for Mission Director and XML attributes. It
   establishes valid elements, attributes, types, and relative schema includes,
   but does not prove runtime behavior.
2. Extract the relevant shipped vanilla files with the X Catalog Tool. Search
   them with `rg` for the API, action, event, control group, or callback being
   considered, then read the surrounding lifecycle code rather than copying a
   single call in isolation.
3. For UI hooks, inspect the installed UI Extensions source and callback
   comments/examples. Confirm both the registration point and when the callback
   executes relative to the vanilla menu or HUD lifecycle.
4. Use Egosoft's UI modding getting-started guide and Lua function overview for
   the supported model, and the breaking-changes page for upgrade risk. These
   pages are useful orientation, but shipped 9.00 files remain the source of
   truth for exact signatures and behavior; the breaking-changes list is not
   exhaustive for UI scripts.
5. Add narrowly scoped `[X4GC]` or `[X4GC TEST]` diagnostics, reproduce in a
   disposable save, and inspect `debug.log`. Live evidence is required for
   asynchronous camera, target, input, and menu-lifecycle assumptions.
6. Triangulate every non-trivial conclusion from all three sources: a current
   declaration/schema, a current shipped use, and live in-game evidence. If one
   is missing, mark the result as an in-game gate or an open question.

For every material finding, record the X4/UI Extensions version, catalog path,
search term, nearby vanilla behavior, and test result in the relevant
`CHANGELOG.md` entry, test, or developer documentation. This preserves the
reasoning when a future game update changes the UI or scripting surface.

## 3. Clone the repository and make a branch

Use the repository URL shown on its GitHub page:

```bash
git clone <repository-url> x4-gunnery-control
cd x4-gunnery-control
git status --short --branch
git switch -c feature/short-description
```

If the repository is already cloned, update it without discarding local work:

```bash
git status --short --branch
git fetch origin
git switch main
git pull --ff-only
git switch -c feature/short-description
```

Never run a reset or checkout command to discard changes unless you have first
confirmed that the files are disposable.

## 4. Locate X4 and install its UI dependency

Common Steam game locations are:

```text
Windows: C:\Program Files (x86)\Steam\steamapps\common\X4 Foundations
Linux:   ~/.local/share/Steam/steamapps/common/X4 Foundations
Linux:   ~/.steam/steam/steamapps/common/X4 Foundations
WSL:     /mnt/c/Program Files (x86)/Steam/steamapps/common/X4 Foundations
Git Bash:/c/Program Files (x86)/Steam/steamapps/common/X4 Foundations
```

The correct directory contains `X4.exe` on Windows or `X4` on Linux and an
`extensions` directory. If Steam uses a second library, open X4's Installed
Files page in Steam and use **Browse** to find the real location.

Install UI Extensions and HUD into the game's `extensions` directory. Its
current 9.00 instructions recommend leaving Protected UI Mode active. If you
change that setting or enable/disable UI Extensions, fully terminate and restart
X4 at the operating-system level so its menus reload. Confirm that the
dependency is enabled in the Extensions menu before debugging this project.

For in-game development, use a disposable test save or a Creative Custom Game
Start. Never use an important campaign save for mutation, destruction, or
live-fire tests.

## 5. Learn the repository layout

| Path | Purpose |
|---|---|
| `content.xml` | Extension identity, game/dependency versions, and description |
| `ui.xml` | UI entry-point registration |
| `ui/gunnery_state.lua` | Pure state transitions; designed for Lua unit tests |
| `ui/gunnery_control.lua` | X4/UI Extensions integration, menus, FFI calls, camera, and lifecycle |
| `md/x4_gunnery_control.xml` | Small Mission Director recovery record |
| `t/0001.xml` | Player-visible English text |
| `testlab/x4_gunnery_control_testlab/` | Separate developer-only companion extension |
| `tests/` | Lua and shell tests plus deterministic log fixtures |
| `scripts/validate.sh` | Full static and unit validation entry point |
| `scripts/install-dev.sh` | Loose-file installation of the main extension |
| `scripts/launch-x4-dev.bat` | Windows launcher with development logging arguments |
| `scripts/filter-gunnery-log.sh` | Filters main lifecycle, Test Lab, and relevant error records |
| `scripts/package.sh` | Main Nexus ZIP builder |
| `scripts/package-testlab.sh` | Developer Test Lab ZIP builder |
| `scripts/parse-testlab-log.sh` | Converts Test Lab log records to CSV |
| `scripts/package-workshop.sh` | Stages the Steam Workshop folder for `WorkshopTool` |
| `scripts/release-workshop.sh` | Stages and pushes a Workshop update in one command |
| `release/` | Release assets: Workshop `preview.png`, GitHub release body |
| `.agents/skills/research-x4-modding/` | The `$research-x4-modding` skill and its evidence KB |
| `.claude/skills/research-x4-modding` | Symlink to the above; see the note below |
| `.github/workflows/` | Pull-request CI and tag-release automation |

`.claude/skills/research-x4-modding` is a **tracked relative symlink** to
`../../.agents/skills/research-x4-modding`. The skill has one home,
`.agents/`, which is the tool-neutral location that `AGENTS.md` and the
`SKILL_DIR` convention refer to; the symlink is only there so Claude Code finds
it under `.claude/skills/`. Edit the real files under `.agents/`. Git stores the
link itself (mode `120000`), so a fresh clone on Linux or WSL gets it for free;
Windows checkouts without symlink support materialise it as a text file
containing the path, in which case the skill is still readable at its real
location.

Keep engine-independent decisions in the pure state modules whenever possible.
That makes lifecycle and restoration behavior testable without launching X4.
Keep FFI calls and UI Extensions hooks in their runtime adapters.

## 6. Establish a clean baseline

From the repository root, run:

```bash
./scripts/validate.sh
```

A complete run performs all of the following:

1. Parses the main and Test Lab XML with `xmllint`.
2. Compiles every project and test Lua file without executing it.
3. Runs the pure Lua unit tests.
4. Runs ShellCheck on project shell scripts.
5. Runs the shell tests, including Test Lab log parsing.
6. Rejects tracked catalog, Vortex-management, and debug-log artifacts.
7. Checks the main extension and required UI dependency IDs.

The last line should be:

```text
validation passed
```

Warnings about a missing Lua compiler, Lua runtime, or ShellCheck mean part of
the suite was skipped. Install the missing tool rather than submitting a change
based on a partial pass.

To run one test during a tight edit loop:

```bash
lua5.1 tests/test_gunnery_state.lua
lua5.1 tests/test_testlab_state.lua
./tests/test_parse_testlab_log.sh
```

Run the full validation script again before committing.

## 7. Install loose development files

Declare a task-specific path for the game installation. Quote it because the
default Windows directory contains spaces:

```bash
# change root path here
X4_ROOT="/c/Program Files (x86)/Steam/steamapps/common/X4 Foundations"
./scripts/install-dev.sh "$X4_ROOT"
```

Examples:

```bash
# WSL
X4_ROOT="/mnt/c/Program Files (x86)/Steam/steamapps/common/X4 Foundations"

# Git Bash
X4_ROOT="/c/Program Files (x86)/Steam/steamapps/common/X4 Foundations"

# Linux; replace the name with the actual account directory
X4_ROOT="/home/alice/.local/share/Steam/steamapps/common/X4 Foundations"
```

The installer validates the game directory, creates
`extensions/x4_gunnery_control` fresh (wiping any previous copy), and copies
the current loose XML/Lua/text files. Wiping first ensures files deleted from
the repository do not linger in the installed copy. It does not install
Test Lab.

Re-run the installer after every source change that must be tested in X4. A
full X4 restart is the reliable way to reload UI Lua and extension XML; do not
assume that loading a save hot-reloads them.

On Windows, the launcher (`launch-x4-dev.bat`) runs `install-dev.sh`
automatically before starting X4, so you do not need to run it by hand first
when using that workflow. The launcher derives the distro name and the
repository's Linux path from its own UNC path
(`\\wsl.localhost\<distro>\...`), then calls `wsl.exe -d <distro>` to invoke
the installer. The `-d <distro>` flag is passed explicitly rather than relying
on the system default WSL distro, because the default may be a different
distribution (for example, `docker-desktop`) that does not have the repository.
If the install fails, the launcher prints an error and exits without starting
X4, so you never test stale mod code by accident. Use `install-dev.sh`
directly for manual or Linux-side installs.

## 8. Enable development logging

On Windows, the normal way to start a debug session is to double-click the
launcher in Windows Explorer. A WSL checkout is reachable from Windows Explorer
under `\\wsl.localhost\<distro>\`, so substitute your own distro name, account
name, and checkout location into:

```text
\\wsl.localhost\<distro>\home\<user>\path\to\x4-gunnery-control\scripts\launch-x4-dev.bat
```

No arguments are needed when X4 is at the default Steam or GOG location; the
launcher auto-detects it. Create a Windows Explorer shortcut to that path to
make the launch a single double-click. Before the script runs, `cmd.exe` prints:

```text
UNC paths are not supported.  Defaulting to Windows directory.
```

That notice comes from `cmd.exe` itself, cannot be suppressed from inside a
batch file, and is harmless. The launcher uses only absolute paths and behaves
identically with the working directory defaulted to `C:\Windows`. Do not report
it as a bug. The console window stays open after launching so the printed log
path remains readable; set `X4GC_NO_PAUSE=1` to skip the final pause.

Use Command Prompt or PowerShell instead when you need to pass a custom
installation folder:

```bat
scripts\launch-x4-dev.bat "C:\Program Files (x86)\Steam\steamapps\common\X4 Foundations"
```

The argument can be either the X4 installation folder or the full path to
`X4.exe`. Leave it out to auto-detect the default Steam/GOG location or to be
prompted for a folder:

```bat
scripts\launch-x4-dev.bat
```

For a custom Steam library, either pass the folder each time or set a temporary
Command Prompt variable first:

```bat
set "X4GC_GAME_ROOT=D:\SteamLibrary\steamapps\common\X4 Foundations"
scripts\launch-x4-dev.bat
```

The launcher exits `0` on success, `2` when `X4.exe` was not found, `3` when
Windows failed to start X4, and `4` when the install step failed.

The launcher validates `X4.exe`, sets the game directory as the working
directory, and adds these parameters (with the resolved log directory printed
first):

```text
-prefersinglefiles -debug all -logfile debug.log
```

`-prefersinglefiles` tells X4 to prefer the loose files being copied during
development. `-debug all` enables diagnostics and `-logfile` names the file
they are written to.

Three properties of `-logfile` are exact, and X4 fails silently rather than
reporting a bad argument:

- It is required. `-debug all` on its own produces no log whatsoever.
- Its value must be unquoted. `-logfile debug.log` works, while
  `-logfile "debug.log"` produces no log at all.
- Its value must be a bare filename. An absolute path makes X4 write to a file
  literally named `INVALID.FILENAME` in its userdata folder.

Linux and Steam users should add the same unquoted parameters to X4 launch
options; the log appears in X4's userdata folder, typically
`~/Documents/Egosoft/X4/<numeric-id>/` or the Steam-managed equivalent.

X4 truncates `debug.log` at every launch, so each run starts clean and the
previous run's log is lost. Copy it aside if you need to keep it.

The launcher resolves and prints that destination before starting the game, for
example:

```text
Gunnery diagnostics will be written to:
  C:\Users\<user>\Documents\Egosoft\X4\<numeric-id>\debug.log
```

From WSL, the log is normally available at
`/mnt/c/Users/<Windows-user>/Documents/Egosoft/X4/<numeric-id>/debug.log`.

Useful searches are:

```bash
./scripts/filter-gunnery-log.sh "/path/to/debug.log"
rg '\[X4GC\]' "/path/to/debug.log"
rg '\[X4GC TEST\]' "/path/to/debug.log"
rg -i 'error|exception|ffi|x4_gunnery' "/path/to/debug.log"
```

Use `[X4GC]` for main-extension diagnostics and `[X4GC TEST]` for structured
Test Lab records. Lifecycle diagnostics record the transition reason, ownership
state, visual phase, chair/ship context, camera focus, and pause state when the
engine exposes it. Do not commit a game debug log; validation rejects one.

## 9. Follow the normal edit-test loop

For each small change:

1. State the behavior and the safety invariant it affects.
2. Add or update a test in `tests/` for pure state behavior.
3. Change `ui/gunnery_state.lua` or the Test Lab state module first when the
   behavior does not require X4 APIs.
4. Make the smallest required runtime change in `ui/gunnery_control.lua` or the
   Test Lab runtime file.
5. Add player-visible strings to `t/0001.xml`; do not scatter display text
   through Lua.
6. Run the focused Lua test.
7. Run `./scripts/validate.sh`.
8. Re-run `install-dev.sh` (or just launch via `launch-x4-dev.bat`, which
   runs the install automatically) and restart X4 for an in-game check.
9. Inspect `debug.log`, even when the menu appears to work.
10. Run the relevant lifecycle and target-preservation cases from
    [TESTING.md](TESTING.md).

When adding or changing an X4 FFI call, verify its signature and lifetime
semantics against the exact installed X4 version. The
[official UI modding guide](https://wiki.egosoft.com/X%20Rebirth%20Wiki/Modding%20support/UI%20Modding%20support/Getting%20started%20guide/)
documents FFI declarations, `const char*` conversion, and `UniverseID`
conversion. The exact installed game's shipped UI files are the runtime source
of truth for current menu behavior; for secondary-control resolution, compare
with `ui/addons/ego_detailmonitor/menu_docked.lua` after extracting the game's
catalogs. Egosoft's
[breaking-changes page](https://wiki.egosoft.com/X4%20Foundations%20Wiki/Modding%20Support/Breaking%20Changes/)
warns that shipped UI scripts can change without being listed there. Use the
[X Catalog Tool](https://wiki.egosoft.com/X%20Rebirth%20Wiki/Modding%20support/X%20Catalog%20Tool/)
to inspect shipped catalogs; never copy a vanilla file into this extension as a
replacement.

## 10. Test in the game without Test Lab

Do a quick manual smoke test before the wider sweep:

1. Start from a disposable save with the main extension and UI Extensions and
   HUD enabled.
2. Enter a capital ship that has an `Access Gunnery Control` chair.
3. Sit in the chair and open the normal secondary-control interaction.
4. Confirm the Gunnery Control menu opens and lists turret groups with
   checkboxes. Confirm that **Auto-engage** and **Direct-control** are greyed
   until at least one mutable group is checked.
5. Check one group. Confirm both action buttons become active. Note the group's
   current mode and armed state for later comparison.
6. Press **Auto-engage**. Confirm the live panel opens with the current turret
   name, four POV buttons, and Next/Prev. Verify the group's mode and armed
   state are unchanged (Auto-engage must not mutate anything). Try all four POV
   buttons. If more than one operational turret is available, confirm Next and
   Prev cycle the camera and wrap around; confirm both buttons are greyed when
   only one turret qualifies.
7. Press `Esc` from the manual panel. Confirm the Gunnery Control console
   returns and the camera view ends.
8. Press **Auto-engage** again, then switch to a cinematic POV. Confirm the game
   UI is hidden. Press `Esc`; confirm the manual panel returns (not the console
   and not the X4 options menu).
9. Return to the console. Check two groups. Press **Direct-control**. Confirm
   the target browser opens and lists known ships/stations in the current sector
   within radar range; confirm the occupied ship is absent. Click a hostile
   ship; confirm the browser immediately collapses to the compact panel — no
   intermediate hull/element picker screen. Confirm **every checked mutable
   group** changed to armed `autoassist`, not just one. Confirm the upper-left
   element panel appears with the target's name as its header, listing Hull
   (greyed, as the default) plus any operational surface elements. Confirm the
   upper-right panel has a Next Target / Previous Target row; it should be
   greyed when only one candidate exists and active otherwise. Confirm X4, not
   this mod, aims and fires only when `mayattack`/its other safety checks allow
   it.
10. Kill the engaged target while in a cinematic POV. Confirm the camera
    restarts on the next target (brief cut expected).
11. Press `Esc` from a cinematic POV. Confirm the manual panel returns.
12. Choose **Cease Engagement** and confirm every previously checked group has
    its exact prior mode and armed state restored.
13. Re-enter Direct-control, then press `M`. Close Map with `Esc`; the panel
    should resume. Try Player Information and one other global-menu hotkey only
    as safe-teardown tests: no stale override, camera frame, pause, or movement
    lock may remain, but phase resume is not yet promised.
14. Choose **Get Up** from the live panel. Confirm the player leaves the chair
    and every overridden group is restored. Sit again and verify a fresh
    Gunnery Control console opens without a blank transparent frame.
15. Enter Direct-control, save the game, reload it. Confirm every group is
    restored on load (not just one).
16. Repeat Direct-control with an operational hostile turret, shield, and engine.
    Repeat against a station module surface; verify its surfaces appear in the
    picker. Whole-object and surface-element targets are distinct cases.
17. Review all `[X4GC]` log lines and any Lua/FFI errors.

Use a friendly/player-owned target only to confirm selection, non-firing,
preservation, and cleanup. Normal autoassist should refuse it. Do not add a
forced-fire implementation based only on the `aim_turret`/`fire_turret` XSD
names: their continuous behavior, attention constraints, safety effects, and
cleanup need a separate disposable-save experiment first.

## 11. Build and install Test Lab

Test Lab exercises every discoverable physical turret on the current ship and
verifies one temporary mutation/restoration cycle per unambiguous mutable group.
It intentionally does not use undocumented spawn, teleport, force-seat, or fire
APIs.

Build both archives:

```bash
./scripts/package.sh 0.20
./scripts/package-testlab.sh 0.20
```

Extract both top-level extension directories beside one another:

```text
X4 Foundations/extensions/x4_gunnery_control/
X4 Foundations/extensions/x4_gunnery_control_testlab/
```

The archive must preserve those top-level folders. Do not extract the contents
directly into the shared `extensions` directory.

Enable both project extensions and UI Extensions and HUD in X4. Use the current
[Safe Cheat Panel](https://www.nexusmods.com/x4foundations/mods/1971) to spawn or
obtain one ship and teleport to it, then manually sit in its gunnery chair.
Follow [TESTING.md](TESTING.md) exactly for the current-ship sweep, visual
verdicts, motion/lifecycle matrix, target matrix, and live-fire caution.

After a sweep, convert structured records to CSV:

```bash
./scripts/parse-testlab-log.sh "/path/to/debug.log" > testlab-results.csv
```

The generated CSV is local evidence, not source. Review it and attach it to an
issue when useful; do not commit it unless a maintainer explicitly requests a
small deterministic fixture.

## 12. Test targets and surface elements deliberately

A whole ship and one of its surface elements exercise different preservation
paths. Cover at least:

| Case | What to prove |
|---|---|
| No target | The sweep does not invent a target |
| Friendly whole ship | Target survives; no live fire |
| Other player-owned ship | Listed and selectable; normal autoassist does not fire |
| Hostile whole ship | Object ID survives Direct-control/cease/cleanup |
| Hostile engine | Exact engine component ID and any returned connection both survive |
| Hostile turret | Exact turret component ID and any returned connection both survive |
| Hostile shield | Exact shield component ID and any returned connection both survive |
| Hostile station module | Exact module-surface component ID and any returned connection both survive |
| Target destroyed during Direct-control | Failure and cleanup are logged without stale state |

Safe Cheat Panel can provide an NPC-faction ship or station, but not a free
floating engine, turret, or shield generator. Spawn the containing ship or
station and select the installed surface element in Gunnery Control's
Direct-control picker. Prefer an unarmed or minimally armed hostile L freighter for ship
tests. Targets may defend themselves; isolate the test area and use a disposable
save.

## 13. Inspect and package a release candidate

The package builders always validate first. Build with the intended version:

```bash
./scripts/package.sh 0.20
./scripts/package-testlab.sh 0.20
```

Inspect the archives before distributing them:

```bash
unzip -l dist/x4_gunnery_control-v0.20.zip
unzip -l dist/x4_gunnery_control_testlab-v0.20.zip
```

The normal archive must contain one `x4_gunnery_control/` directory with only
runtime XML/Lua/text files, README, and license. It must not contain Test Lab,
`.git`, tests, development docs, scripts, debug logs, loose CSV results, or
Vortex marker files.

For a version change, review all version-bearing locations together:

- `content.xml` and the Test Lab `content.xml`;
- `CHANGELOG.md`;
- the status and command examples in project documentation;
- hard-coded versions in `.github/workflows/ci.yml`;
- the semantic version passed to the package scripts and release tag.

Do not call a release stable until the camera release gate in
[TESTING.md](TESTING.md) has passed for the supported bridge matrix.

## 14. Review and commit the change

Before committing:

```bash
git status --short
git diff --check
git diff
./scripts/validate.sh
```

Stage only the intended files, inspect the staged patch, and commit:

```bash
git add path/to/changed-file path/to/test-file
git diff --cached --check
git diff --cached
git commit -m "Describe the behavior change"
```

Push the feature branch and open a pull request. The pull request should state:

- the user-visible behavior;
- the safety/restoration invariants affected;
- unit/static validation performed;
- X4, UI Extensions, and active-mod versions;
- ships, bridges, turret types, and target types tested;
- camera-gate outcome and relevant Test Lab summary;
- any known limitation or untested case.

CI repeats validation and builds both archives. A green CI job does not replace
the in-game camera, lifecycle, target-preservation, or live-fire checks.

## 15. Troubleshooting

| Symptom | Checks |
|---|---|
| `validate.sh` says a check was skipped | Install the named Lua or ShellCheck dependency and run it again. |
| `install-dev.sh` rejects the game path | Point it at the directory containing `X4.exe`/`X4` and `extensions`, not at the extension folder. |
| Changes do not appear in X4 | On Windows the launcher runs `install-dev.sh` automatically; on Linux run it manually. Use `launch-x4-dev.bat` on Windows or add `-prefersinglefiles` on Linux, verify the enabled extension, and fully restart X4. |
| `launch-x4-dev.bat` cannot find X4 | Pass the installation folder or full `X4.exe` path, or set `X4GC_GAME_ROOT` for a custom Steam library. |
| No development log can be found | Use the directory printed by `launch-x4-dev.bat`; `debug.log` lands in X4's userdata folder under `Documents\Egosoft\X4\<numeric-id>\`. Confirm `-logfile debug.log` is present and unquoted: X4 writes nothing at all when it is missing or quoted. A stale `INVALID.FILENAME` beside it means an absolute path was passed instead of a bare filename. Remember that each launch truncates the previous log. |
| Gunnery Control does not open | Confirm UI Extensions 9.00+, follow its current Protected UI Mode guidance, fully restart X4, and inspect `[X4GC]`/Lua errors. |
| Test Lab is missing | Install and enable the separate Test Lab ZIP beside the main extension and ensure both builds are from the same commit. |
| Camera frames the whole ship | Record the ship, bridge, turret, and log. This fails the camera gate even if no Lua error appears. |
| Direct-control leaves a group changed | Preserve the save/log, record lifecycle steps, restore the group manually in vanilla UI, and file a bug before more live-fire testing. |
| Surface target becomes whole-ship target | Record both expected and observed connection information; object-ID-only preservation is insufficient. |
| ZIP installs with an extra nested folder | Re-extract so the immediate directory under `extensions` is `x4_gunnery_control` or `x4_gunnery_control_testlab`. |
| XML loads locally but fails in X4 | Inspect `debug.log`, validate against the exact game version, and compare the registration/API usage with shipped UI files. |

When reporting a runtime problem, include the filtered development log, the exact reproduction
steps, ship and bridge, physical turret and group, target/surface element, game
version, UI Extensions version, active mod list, and whether the ship or target
was moving.

## 16. Releasing

### Version scheme

Versions are two-part `MAJOR.MINOR` with a mandatory two-digit minor: `0.20`,
`1.00`, `2.50`. The integer stored in `content.xml`'s `version` attribute is
the source of truth; X4 displays it divided by 100. EgoSoft's own example: to
display v2.50 you specify `version="250"`. `scripts/lib-release.sh` converts
between the two forms; `scripts/validate.sh` and the package scripts cross-check
them.

### Bump order

`validate.sh` fails when `content.xml` and the newest `CHANGELOG.md` heading
disagree — by design. The bump order that makes it go green:

1. Add `## [MAJOR.MINOR] - DATE` as the new top heading in `CHANGELOG.md` with
   the release notes beneath it.
2. Update `content.xml`'s `version` integer and `date` to match.

Do them together in one commit. Pushing either change alone leaves the repo
red.

### Tag and GitHub release

Tag `vMAJOR.MINOR` (for example `v0.20`) and push it:

```bash
git tag v0.20
git push origin v0.20
```

`.github/workflows/release.yml` fires on any `v*` tag. It runs `validate.sh`,
then calls `package.sh "${GITHUB_REF_NAME#v}"` — stripping the leading `v` —
and publishes the resulting archive as a GitHub release. That argument is
cross-checked against `content.xml` transitively inside `package.sh`, so a tag
that does not match `content.xml` fails the build before anything is published.

### Nexus Mods

Upload `dist/x4_gunnery_control-v0.20.zip` to Nexus. The archive's internal
top-level folder is already `x4_gunnery_control`, which is what Vortex and
manual extraction both require.

### Steam Workshop (manual, Windows-only)

Prerequisites before the first publish:

- Accept the Steam Workshop Legal Agreement for X4 Foundations in your Steam
  account.
- `WorkshopTool.exe` comes from **X Tools**, a free application in your Steam
  library (app 282160), not from the `XTools_1.11.zip` at the repository root —
  that 2019 archive contains only `XRCatTool`. Install X Tools from Steam and
  launch it; it opens a command prompt already in the folder containing
  `WorkshopTool.exe`. Launching it through Steam is required, because the tool
  needs the Steam session it initialises.
- You must stay logged into Steam while WorkshopTool runs.
- A preview image lives at `release/preview.png` (Steam accepts JPG or PNG,
  640×360 or larger). The script picks up `release/preview.jpg` or
  `release/preview.png`, whichever exists, and passes its path to `-preview`. It
  is deliberately not copied into the staged folder, because everything in there
  is packed into the shipped catalog.

Stage the Workshop folder and print the commands:

```bash
./scripts/package-workshop.sh 0.20
```

The script prints two commands. Paste the one that fits your situation:

```text
# First publish — creates a new Workshop item:
WorkshopTool publishx4 -path "<staged-path>" -preview "<repo>\release\preview.png" -buildcat

# Subsequent updates — updates an existing item:
WorkshopTool update -path "<staged-path>" -buildcat -changenote "Describe your changes here"
```

`update` requires `-changenote`; omitting it is an error. The version integer in
`content.xml` must increase on every `update` unless `-minor` is passed.

Once the item exists, the whole update is one command — it stages, then drives
WorkshopTool for you (extra arguments are forwarded, so `-minor` works):

```bash
./scripts/release-workshop.sh 0.21 "What changed"
```

WorkshopTool.exe runs fine from WSL through Windows interop; the script `cd`s
into the X Tools folder first, because the tool reads `steam_appid.txt` from its
own directory. Steam must be running and logged in. Override the tool location
with `X4GC_WORKSHOPTOOL`, or set `X4GC_DRY_RUN=1` to print the command without
publishing.

The script deliberately refuses to do the *first* publish: that one needs
`-preview` and a legal-agreement acceptance that is not worth automating once.

The item's title and description are **not** touched by `update` — WorkshopTool
ignores both unless `-namedesc up` is passed. So the long description is edited
on the Workshop website and survives every release; keep the paste-ready copy in
`release/workshop-description.bbcode` in step with `release/RELEASE_NOTES.md`.
The one-line `description` attribute in `content.xml` is what the in-game
Extensions menu shows, and it seeded the page at first publish.

### Why the staged content.xml differs from the repository's

WorkshopTool refuses to publish an extension that depends on anything which is
not itself a Workshop item, failing with `ERROR: There are dependencies on
non-Workshop extensions` — and it refuses even when the dependency is marked
`optional="true"`. Our hard dependency names kuertee's Nexus id
`kuerteeUIExtensionsAndHUD`, which would block the publish outright.

`package-workshop.sh` therefore rewrites that one line in the staged copy to
point at the [Workshop repackage of the same mod](https://steamcommunity.com/workshop/filedetails/?id=3477279743),
uploaded by Valador8869/UncommonDLL with kuertee's permission. Workshop-installed
extensions carry the id form `ws_<workshopid>`, not the bare number — visible in
any real install (`ws_2042901274` SirNukes Mod Support APIs, `ws_3715253556`
Options Helper). The `version` attribute is dropped, because the repackage sets
its own version integer and demanding the wrong one would block loading for every
subscriber. The script aborts if the rewrite does not take.

The consequence to remember: **Workshop and Nexus builds depend on different
extension ids.** A Workshop subscriber gets the Workshop UI Extensions; a Nexus
user gets kuertee's own. Installing both copies at once is a mod conflict, not a
supported configuration.

Staging exists because WorkshopTool mutates the folder given to `-path`: on a
successful first publish it rewrites the `id` attribute in that folder's
`content.xml` with the numeric Workshop id it assigned. Pointing WorkshopTool at
the repository directly would overwrite the tracked `content.xml`. See the
[Egosoft Steam Workshop guide](https://wiki.egosoft.com/X%20Rebirth%20Wiki/Modding%20support/Steam%20Workshop%20for%20X%20Rebirth%20and%20X4/)
for the full WorkshopTool reference.

#### After the first publish

This was done on 2026-08-06: the item is
[3778864325](https://steamcommunity.com/sharedfiles/filedetails/?id=3778864325)
and `release/workshop-id.txt` holds `ws_3778864325`.

The `ws_` prefix is required. WorkshopTool reports only the bare number on a
successful publish, but an extension whose own `id` is that bare number is not
recognised as a Workshop item at all — `WorkshopTool showpage` answers `ERROR:
Extension does not have a Steam Workshop entry`, and `update` would have no item
to update. With `ws_` in front, the same command finds the page. Use `showpage`
to check the id form after any change to it; it is the one read-only command the
tool has.

`package-workshop.sh` substitutes that id into the staged `content.xml` on
every future run so `WorkshopTool update` targets the correct item.

#### Known consequence of the Workshop id

A Workshop-installed copy of the extension carries the numeric Workshop id (e.g.
`3456789012`) instead of `x4_gunnery_control`. Any extension that declares
`<dependency id="x4_gunnery_control">` will not resolve against a
Workshop-installed copy. Today that only affects
`testlab/x4_gunnery_control_testlab/content.xml`, which is developer-only and
never shipped, so it costs nothing in practice. A future dependent mod would be
affected. This is inherent to X4's Workshop model and is why kuertee's mods are
Nexus-only.

## Reference links

- [Project testing guide](TESTING.md)
- [Contribution rules](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)
- [Egosoft UI modding getting-started guide](https://wiki.egosoft.com/X%20Rebirth%20Wiki/Modding%20support/UI%20Modding%20support/Getting%20started%20guide/)
- [Egosoft Lua function overview](https://wiki.egosoft.com/X%20Rebirth%20Wiki/Modding%20support/UI%20Modding%20support/Lua%20function%20overview/)
- [Egosoft UI/modding breaking changes](https://wiki.egosoft.com/X4%20Foundations%20Wiki/Modding%20Support/Breaking%20Changes/)
- [Egosoft X Catalog Tool](https://wiki.egosoft.com/X%20Rebirth%20Wiki/Modding%20support/X%20Catalog%20Tool/)
- [kuertee UI Extensions and HUD](https://www.nexusmods.com/x4foundations/mods/552)
- [Safe Cheat Panel](https://www.nexusmods.com/x4foundations/mods/1971)
