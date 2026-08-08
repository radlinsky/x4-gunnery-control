# When to reload and when to restart X4

The authoritative answer to "do I need to restart the game?". Everything else in
the repository points here; do not restate the table elsewhere.

Every reload reads the **loose files on disk**, so `scripts/install-dev.sh` must
run first. Without it a reload re-runs the copy the game already has and nothing
appears to change — which looks exactly like a broken reload.

## Decision table

| What changed | What to do |
|---|---|
| `ui/*.lua` | install, then **Reload UI** |
| `md/*.xml` | install, then **Reload MD**, then trigger the cue again |
| `libraries/*.xml`, AI scripts | install, then **Reload AI** (untested here — treat a failure as "restart") |
| `t/*.xml` (text) | **restart** |
| `ui.xml`, `content.xml` | **restart** |
| A new file, or a file deleted | **restart** |
| Test Lab's own `testlab/` files | **restart**, with `launch-x4-test-lab-dev.bat` |
| Nothing changed, but the game is confused | **restart** |

Restart means: exit X4, then run `scripts/launch-x4-dev.bat` (or
`launch-x4-test-lab-dev.bat` when Test Lab is needed). The launcher installs
before it launches, so it is the one path where the install is not a separate
step.

The reload buttons are in the **Test Lab** extension, reachable from the gunnery
console. Test Lab is developer-only and is installed only when
`X4GC_INSTALL_TESTLAB` is set, which `launch-x4-test-lab-dev.bat` does.

## Why the split

Live-tested on 2026-08-08 against X4 9.00; recorded in the research KB under
"Reloading UI Lua without restarting X4" and "refreshmd re-reads MD from disk".

- **Reload UI** calls `ScheduleReloadUI()`, which re-reads `ui/` from disk.
- **Reload MD** calls `ExecuteDebugCommand("refreshmd", 0)`, which re-reads
  `md/`. The second argument must be `0`; `nil` segfaults the game.
- They are **independent**. A UI reload does not re-read MD, and an MD refresh
  does not re-read UI Lua. Both were verified with the other held fixed.
- `t/`, `ui.xml` and `content.xml` are read when the extension is loaded and no
  reload command re-reads them. Assume a restart.

## Two consequences worth knowing

**A UI reload wipes Lua state.** Every global and file-local is gone, so a live
gunnery session is lost and the console rebuilds from chair ingress. An MD cue
variable is the only storage measured to survive it — which is why session
persistence is built on one.

**`refreshmd` keeps existing cue variables and does not re-run cues that already
completed.** A marker in a conditionless root cue therefore cannot tell you
whether a refresh happened. Edit a cue that fires on demand and watch for its
new text.

**If the change broke the gunnery menu, you have no button to click.** Test Lab
is reachable only through that menu. Recovery is UI Extensions' `/rui` chat
command, or a restart.
