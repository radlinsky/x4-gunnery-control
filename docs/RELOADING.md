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
| A new X4-loaded file, or an X4-loaded file deleted | **restart** |
| Changes spanning more than one reload category | **restart** |
| Test Lab's own `testlab/ui/*.lua` | install with `X4GC_INSTALL_TESTLAB=1`, then **Reload UI** |
| Test Lab's own `testlab/md/*.xml` | install with `X4GC_INSTALL_TESTLAB=1`, then **Reload MD** |
| Any other `testlab/` file (`ui.xml`, `content.xml`, `t/*.xml`, a new file) | **restart**, with `launch-x4-test-lab-dev.bat` |
| Nothing changed, but the game is confused | **restart** |

Restart means: exit X4, then run `scripts/launch-x4-dev.bat` (or
`launch-x4-test-lab-dev.bat` when Test Lab is needed). The launcher installs
before it launches, so it is the one path where the install is not a separate
step.

The reload buttons are in the **Test Lab** extension, reachable from the gunnery
console. Test Lab is developer-only and is installed only when
`X4GC_INSTALL_TESTLAB` is set, which `launch-x4-test-lab-dev.bat` does.

## How to reach the buttons, exactly

The owner cannot act on "click Reload UI" alone — there is no such button on
screen until they are in the right place. Give all four of these every time:

1. **Where to be: seated at a gunnery console.** The buttons live in Test Lab,
   Test Lab is opened from a button on the console panel, and the console only
   exists while seated. Standing on the deck there is nothing to click.
2. **Which Test Lab button.** There are three, all opening the same menu, and
   naming "the Test Lab button" is not enough:

   | Screen | Where |
   |---|---|
   | Console (turret group list) | bottom action row, beside Refresh and Get Up |
   | Target browser (Direct-control picker) | action row, between Refresh and Back |
   | Engaged panel (upper-right, while engaged) | its own row at the bottom, under Prefer/Release |

   Pick by the phase the change has to be tested in, because opening Test Lab
   parks the session **as it is at that moment** and the reload restores from
   that. A fix that only shows while engaged must be reloaded from the engaged
   panel; reloading from the console restores a console session and the change
   never gets exercised.

   Then: **Reload UI** / **Reload MD** / **Reload AI** inside Test Lab.
3. **What it costs.** Opening Test Lab parks the session and a UI reload wipes
   all Lua state, so the session is rebuilt from the parked payload rather than
   continuing. Anything not in that payload is gone.
4. **What confirms it worked:** the log line
   `[X4GC] UI initialized; build=<runtimeBuild>` carrying the build id you just
   installed. Tell the owner the id to look for. If the id is the old one, the
   installer did not run and the reload re-ran the previous code.

State the phase to be in when the change only shows in one — engaged, on the
console, in target selection — rather than leaving them to guess.

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

**A UI reload wipes in-memory Lua state.** Every global and file-local is gone.
Before opening Test Lab, Gunnery Control parks the current session in an MD cue
variable; a successful persistence handshake rebuilds that parked phase after
the reload. Without a valid parked payload, the safe fallback is a fresh console
at chair ingress. The MD cue is the only storage measured to survive a UI reload,
which is why session persistence is built on one.

**`refreshmd` keeps existing cue variables and does not re-run cues that already
completed.** A marker in a conditionless root cue therefore cannot tell you
whether a refresh happened. Edit a cue that fires on demand and watch for its
new text.

**If the change broke the gunnery menu, you have no button to click.** Test Lab
is reachable only through that menu. Recovery is UI Extensions' `/rui` chat
command, or a restart.

## The hook

`.claude/settings.json` and `.codex/hooks.json` register the same PostToolUse
implementation at `.agents/hooks/reload-advice.sh`. Claude supplies one edited
file path; Codex supplies an `apply_patch` command that may name several files.
The hook understands both payloads and, for a multi-file Codex edit, selects the
strictest result before injecting one instruction. Codex requires the owner to
review and trust a new or changed project hook with `/hooks` before it runs.

Files X4 never loads produce nothing, so ordinary repository work stays quiet.

The script is also a plain CLI —
`.agents/hooks/reload-advice.sh ui/gunnery_control.lua` prints the same line.
The mapping, both client payloads, and multi-file precedence are covered by
`tests/test_reload_advice.sh`, which runs under `scripts/validate.sh`; keep the
hook and test in step with this table.
