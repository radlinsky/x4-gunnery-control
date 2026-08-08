# Debug logging evidence

## X4 launch arguments and log output

### X4 debug log invocation is silent-failing and strict
- X4: 9.00
- Status: live-tested
- Corroboration: documented-public Egosoft community wiki and a Nexus guide
  both show the form `-debug all -logfile debuglog.txt`
- Source: game debug.log; live run on 2026-08-04, extension `x4_gunnery_control`
  build marker `2026-08-04-lifecycle-1`, X4 9.00 Steam, Windows 11 with WSL2
- Live test: yes — all four argument forms tested on the same machine and build on 2026-08-04
- Finding: the most important fact is that every failure is silent. X4 never reports a
  bad `-logfile` argument, so a wrong form is indistinguishable from "the mod is not
  logging". Verified matrix:

  | Arguments | Result |
  |---|---|
  | `-debug all` with no `-logfile` | no log written anywhere |
  | `-logfile "x4-gunnery-control-debug.log"` (quoted bare name) | no log written anywhere |
  | `-logfile "C:\...\x4-gunnery-control-debug.log"` (quoted absolute path) | X4 writes to a file literally named `INVALID.FILENAME` in its userdata folder |
  | `-logfile debug.log` (unquoted bare name) | works |

  `-logfile` is required; `-debug all` alone produces nothing. The value must be
  unquoted and a bare filename. Why a quoted bare name fails while a quoted absolute path
  produces `INVALID.FILENAME` was not isolated and is recorded as inference only: the
  parser may reject quoted values entirely but falls back to a sentinel name when the
  value parses as a path. Only the unquoted form was needed to resolve the issue.

  The log is written to `Documents\Egosoft\X4\<numeric-id>\`, a sibling of the `save`
  folder, where `<numeric-id>` is the Steam account ID. That folder also contains a
  non-numeric `extensions` sibling, so any script auto-detecting the userdata directory
  must filter to all-digit names rather than picking the most recently modified
  subdirectory. X4 truncates the log at every launch; copy it aside before relaunching.

### Diagnosing a missing log
- X4: 9.00
- Status: live-tested
- Source: game debug.log; live run on 2026-08-04 on Windows 11 with WSL2
- Live test: yes — both techniques used to resolve the missing-log issue on 2026-08-04
- Finding: two non-obvious techniques resolved the missing-log issue.

  Confirm what the process actually received rather than what you think you passed:
  `Get-CimInstance Win32_Process -Filter "Name='X4.exe'"` returns the full command line
  as Windows sees it.

  Check log *content*, not file size or mtime. Windows does not flush a file's metadata
  while a process holds the handle open, so a growing log can look stale from outside.
  Compare the first `Logfile started, time ...` line and grep for a known build marker
  to confirm the log belongs to the current run.

### The log is readable from WSL while X4 is still running
- X4: 9.00
- Status: live-tested
- Source: live session on 2026-08-08, extension `x4_gunnery_control`, X4 9.00 Steam,
  Windows 11 with WSL2; log at
  `/mnt/c/Users/PC/Documents/Egosoft/X4/51053644/debug.log`
- Live test: yes — lines emitted by in-game actions were read from WSL during the same
  session on 2026-08-08, before X4 exited
- Finding: X4 does not withhold log output until it exits. Lines written during play were
  read from WSL while the game was still running, matched to the action that produced them
  by their in-game timestamp.

  Reading bytes past a tracked offset returned that new content. Nothing derived from the
  file's metadata was consulted to find it. This is the same metadata staleness recorded
  above, so `tail -f`, which polls `stat`, is not the tool for this; `scripts/tail-gunnery-log.sh`
  in this repository tracks a byte offset instead.

  Not established by this test: whether X4 flushes on a timer, per line, or per buffer.
  Only that content written during play is readable during play.
