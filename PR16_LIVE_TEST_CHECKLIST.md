# PR #16 agent-directed live X4 acceptance runbook

This is a stateful runbook for an LLM agent directing the owner through PR #16
live testing against a disposable X4 save. The owner drives X4; the agent reads
and writes this file, monitors `debug.log`, explains one test in plain English,
gives bounded step-by-step actions, waits for the owner's report, reconciles the
report with the log, and records the result before continuing.

The agent must work in order and stop at the first unsafe failure. It must not
infer a pass from silence unless the test explicitly says silence is expected.

## Agent run state

The directing agent updates this block before it gives an owner action and again
after it records a result. This is the resume point for a later agent or compacted
conversation. Do not erase prior test notes.

- Run status: **NOT STARTED**
- Run ID/date:
- Current section/test: **Preflight**
- Current row/step: **Not started**
- Last completed test: **None**
- Exact tested commit/build:
- Results requiring rerun: **None**
- Last owner report:
- Absolute `debug.log` path:
- Live-monitor command/session:
- Current evidence-window start:
- Evidence byte offset start:
- Evidence byte offset end:
- Latest log line reviewed:
- Active blocker: **None**
- Next owner action: **Wait for agent instructions**

## Run records

This section is append-only. On the first run, replace the placeholder with the
template below. After a fix, new build, or new X4 process, append another record;
never overwrite the earlier run.

_No run records yet._

```text
### Run <ID> — <IN PROGRESS|STOPPED|COMPLETE>
- Started/ended:
- Commit and runtime build:
- X4 process/build-marker line:
- Required reset performed:
- debug.log path:
- Starting/ending byte offsets:
- Supersedes run:
- Tests/rows requiring rerun:
- Stop reason:
```

## LLM agent operating contract

### Division of responsibility

The agent:

- Reads this entire operating contract before acting, then reads the complete
  section for the current test before directing it.
- Uses repository tools to inspect the working tree, runtime build marker,
  scripts, implementation, and `debug.log` itself.
- Updates **Agent run state**, the current test's result fields, timestamps,
  evidence paths, exact observations, and relevant log excerpt with
  `apply_patch` after every completed test or matrix row.
- Decides PASS, FAIL, BLOCKED, or NOT RUN from the written criteria. The owner
  reports what happened; the agent owns classification and must explain it.
- Keeps ordinary output concise. It quotes only the log lines needed to support
  the decision and never enables continuous success logging in the mod.

The owner:

- Drives X4, observes the screen, takes requested screenshots/video, and reports
  exactly what happened.
- Does not have to interpret protocol internals or decide the result.
- Stops pressing controls immediately when the agent or hard-stop rule says to
  stop.

The agent cannot click, type, save, load, move, target, or inspect anything
inside X4. It must never phrase an unperformed owner action as though it already
happened.

All build-marker, line-count, exact-log-message, repetition, and raw-error checks
in the source test steps are **agent actions**. The agent must not ask the owner
to inspect, count, search, copy, or transcribe routine log output. The owner only
reports visible game state and completion of requested game actions.

### Starting or resuming a run

1. Read **Agent run state** and the result field for the named current test.
2. If Run status contains `STOPPED`, Active blocker is not `None`, or the last
   result is FAIL/BLOCKED pending a decision, issue **no X4 action**. Preserve and
   review evidence first. Resume only after the owner authorizes the fix/setup
   change and the agent appends a run record with the new commit/build, required
   reset, and exact rerun scope.
3. Inspect `git status --short` and `git log -1 --oneline`. Do not touch unrelated
   user files. A modified checklist is expected during a run; a modified tracked
   X4-loaded file means the installed build may not match and blocks new results
   until reconciled. Record the exact tested commit during Preflight.
4. If the run state and filled results disagree, stop and ask the owner which run
   is authoritative. Do not silently overwrite evidence.
5. Ask only for missing facts that cannot be read from the repository or log,
   such as the save, ship, bindings, visible group states, or screenshot path.
   Make no assumptions about the game state.
6. Resume at the first incomplete row of the current test. Do not repeat a
   completed destructive action merely to regain context.

### Monitor `debug.log` directly

The launcher-created **X4 Gunnery Log** window is for the owner. The directing
agent must start its own repository-side monitor; it must not ask the owner to
read or transcribe routine log output.

1. Obtain and verify the absolute WSL path to the current `debug.log`. Prefer the
   launcher-reported path recorded during Preflight. If it is not known, ask the
   owner; do not guess between X4 account directories.
2. If X4 is already running, query the whole file for the latest build marker
   before starting the live tail; the tailer deliberately skips bytes that
   existed when it started because they may belong to a previous process:

   ```bash
   rg -n -F '[X4GC] UI initialized; build=' "/absolute/path/to/debug.log" | tail -n 1
   ```

   Compare the complete line with the expected build. Record its line number and
   current byte offset. If the marker is absent or stale, do not issue a game
   action.
3. Before issuing game actions, start this as a long-running tool process and
   retain its session identifier:

   ```bash
   ./scripts/tail-gunnery-log.sh "/absolute/path/to/debug.log"
   ```

4. Poll that process immediately before giving a test batch, after every owner
   report, and once more before recording the result. Read all new output. If
   the tool session was lost, restart it and recover from the recorded byte
   offsets before continuing.
5. Immediately before each owner-action batch, wait for writes to settle and
   record the byte count as `Evidence byte offset start`:

   ```bash
   wc -c < "/absolute/path/to/debug.log"
   ```

   After the owner reports, poll the monitor, record the new byte count as the
   end offset, and inspect exactly the new byte range. If `END` is smaller than
   `START`, the log was truncated: stop and re-verify the process/build marker.

   ```bash
   tail -c "+$((START + 1))" "/absolute/path/to/debug.log" \
     | head -c "$((END - START))"
   ```

   Wall-clock times are supporting context; byte offsets are authoritative for
   `zero`, `exactly one`, and repeated-line claims. If either offset is missing,
   mark the log-dependent assertions BLOCKED.
6. The filtered monitor is not a complete error detector. After every owner
   report, scan that exact byte range for both mod lines and broad errors:

   ```bash
   tail -c "+$((START + 1))" "/absolute/path/to/debug.log" \
     | head -c "$((END - START))" \
     | rg -n -i 'x4_gunnery|X4Gunnery|\[X4GC|lua.*error|ffi.*error|schema.*error|cue.*error|error.*cue|exception'
   ```

   Scan the whole raw file once during final evidence packaging for broader
   context, but never charge a pre-window error or line count to the current row.
7. Treat a truncation/reset notice as a new X4 process. Re-verify the exact
   current-build marker before accepting more results.
8. Do not mark a log-dependent condition PASS when the monitor was unavailable.
   Recover the exact range from recorded offsets or mark the test BLOCKED.
9. If the same diagnostic repeats at update/scan cadence, tell the owner to stop
   immediately and follow the failure protocol. Do not continue polling a flood
   while the game generates more of it.

### Direct one test at a time

For each mandatory test, each M4/M8/M9 matrix row, each requested conditional
row, and each Test Lab ship sweep:

1. Update **Agent run state** to the exact test/row and set its evidence-window
   start time.
2. In plain English, tell the owner:
   - what behavior this test is proving;
   - why it matters to the PR;
   - the required starting screen, ship, targets, checked groups, and baseline;
   - what success will look like; and
   - the specific hard-stop symptom for this test.
3. Give a short numbered action batch. Preserve the source step numbers in this
   file, but translate implementation terms into visible controls and outcomes.
   For a long test, issue only the steps needed to reach the next observation
   checkpoint. A batch has at most three owner actions and at most one
   irreversible action (Quick Save/Load, Reload UI, Cease/Get Up, destroying a
   target, or opening an unsupported full menu). End immediately after the next
   visible/log checkpoint. Never dump several matrix rows into one owner turn.
4. End the instruction turn with an explicit wait. Ask the owner to reply using:

   ```text
   Completed through step/row:
   What I saw:
   Group modes/armed values that changed:
   Camera/target/POV result:
   Popup or error text:
   Screenshot/video filename:
   Anything unexpected:
   ```

5. Do not give the next game action until the owner reports back. While handling
   that report, poll the live monitor and scan the raw error context yourself.
6. If the report is incomplete for a required visible condition, ask one focused
   follow-up and wait. Do not turn “seemed fine” into PASS.
7. When a long test reaches an intermediate checkpoint, record the observation
   in its Notes but leave its Result incomplete. Then give the next bounded batch.
8. When all criteria for the row/test are known, classify it, write the result
   and evidence into this file, update **Agent run state**, and only then proceed.

### Recording rules

- For prose tests, replace the entire selected result line with one unambiguous
  value such as `Result: **PASS**`; do not merely tick a box.
- For matrix tables, replace the row's bracket controls with the full bold word
  `**PASS**`, `**FAIL**`, `**BLOCKED**`, or `**NOT RUN**`, plus concise evidence
  and timestamp in that row. Never check a `P/F/B` box. Set the matrix-level
  result with the full word only after all required rows complete.
- Record the owner's visible observation separately from the agent-observed log
  evidence. Never attribute a log observation to the owner.
- Include start/end wall-clock times, the first differing source step, exact
  target/camera/group identity where required, and evidence filenames.
- Keep only relevant excerpts in this Markdown; raw logs can contain local paths
  or account identifiers and belong in the evidence package, not pasted in full.
- A clean log cannot replace a required visual observation. A reassuring visual
  result cannot override a required error or missing protocol line in the log.
- Do not rewrite a prior result after a new build is installed. Start a new run
  record, append `Run <ID>: <RESULT> — <evidence>` to the affected Notes, and
  clearly mark the older observation superseded without deleting it.
- Treat edits made while running this checklist as a live journal. Do not commit
  or publish filled owner results and local evidence paths unless the owner asks.

### Continue, pause, or stop

- **PASS:** write the result, summarize why it passed in one or two sentences,
  then introduce only the next test.
- **BLOCKED:** write exactly what fixture/action was unavailable. A mandatory
  BLOCKED result sets `Run status: **STOPPED — BLOCKED**` and requires an owner
  decision before more X4 input. For a conditional/destructive row whose safe
  fixture is simply unavailable, record BLOCKED without setting Active blocker,
  then continue to the next conditional row. If a safe setup adjustment could
  unblock it, explain one adjustment and wait for approval. Do not improvise
  spawning, save editing, destructive damage, or configuration.
- **FAIL or any hard stop:** tell the owner to stop all X4 input, record FAIL and
  the first differing step, poll/copy the logs, and preserve screenshots. Stop
  the test sequence. Set `Run status: **STOPPED — FAIL**`, set
  `Next owner action: **No X4 input**`, and record the Active blocker. Diagnose
  from the evidence and repository; do not ask the owner to retry the same
  action first.
- If a fix is within the active task's authority, implement it, add deterministic
  coverage, validate, and follow the repository's reload-advice hook. Otherwise,
  present the evidence and ask before editing.
- After any code/content/Test Lab change, do not resume at the next test until
  the agent has recorded the new commit/build, applied the one reset required by
  `docs/RELOADING.md`, and explicitly marked earlier affected live results as
  needing rerun. Never offer reload versus restart as a choice.
- Do not push or update the PR until the complete mandatory set passes and the
  owner authorizes publication.
- After the mandatory set passes, direct every conditional/destructive case for
  which the owner has a safe fixture. Record unavailable cases as BLOCKED rather
  than silently skipping them. Never ask the owner to perform O1–O7; the agent
  verifies those from the automated suite and records them as offline-only.

## Result vocabulary

- **PASS** — every listed visible and log condition matched.
- **FAIL** — a listed condition differed. Stop that test at the first differing
  step and preserve evidence.
- **BLOCKED** — the required ship, target, damage state, control, or game action
  could not be produced safely. State exactly what was unavailable.
- **NOT RUN** — not attempted yet.

Do not use **PASS** for a partially completed test. Optional/destructive tests
may be **BLOCKED** without failing the mandatory PR acceptance set.

## Hard-stop and evidence rule

Stop the current test immediately if any of these occur:

- Direct-control settings are not restored by Cease Engagement or Get Up.
- The player is left with a stuck external/cinematic camera, missing HUD, dead
  input, or an `Esc` key that no longer opens the expected screen.
- The gunnery menu disappears or breaks so Test Lab cannot be reached.
- A persisted phase produces no `restore accepted; phase=<required phase>` within
  ten seconds after load or Reload UI. Engaged rows require `phase=engaged`;
  M7B and M9D require `phase=target_select`.
- A Lua, FFI, MD property lookup, schema, or cue error appears.
- The same `[X4GC]` diagnostic repeats at scan/update cadence.

When one occurs:

1. **Owner:** do not press more keys to try to cure it.
2. **Owner:** take a screenshot or short video if the failure is visible and
   report the current ship, chair, checked groups, camera turret, target, and POV.
3. **Agent:** record the first numbered step that differed.
4. **Agent:** copy the complete `debug.log` before another launch truncates it.
5. **Agent:** save and inspect the exact filtered/raw evidence range separately.
6. **Agent:** set the stopped run state and write the owner's reported state into
   this checklist before diagnosing or editing.

A persistence-protocol failure blocks the PR. Do not substitute another
transport or retry until the evidence has been reviewed.

### Evidence window for every test

Use one byte-offset window per owner-action batch so counts from earlier actions
do not leak into later results. A long test/row can have several ordered ranges
in its Notes. Wall-clock time is supporting context only:

1. **Agent:** before issuing step 1, write the local start time and settled
   `wc -c` start offset in that test's Notes.
2. **Owner:** take the requested baseline screenshot and perform only the bounded
   action batch supplied by the agent.
3. **Agent:** after the owner reports, write the local end time and `wc -c` end
   offset before issuing another action. Extract exactly that range to a
   test-specific temporary file:

   ```bash
   tail -c "+$((START + 1))" "/path/to/debug.log" \
     | head -c "$((END - START))" > "/tmp/pr16-<run>-<test>-raw.log"
   ```

4. **Agent:** filter that exact range and build its raw-error index. The filtered
   view intentionally omits unrelated engine noise and cannot prove the absence
   of every Lua/FFI/MD/schema/cue failure:

   ```bash
   ./scripts/filter-gunnery-log.sh "/tmp/pr16-<run>-<test>-raw.log" \
     > "/tmp/pr16-<run>-<test>-filtered.log"
   rg -n -i 'x4_gunnery|X4Gunnery|\[X4GC|lua.*error|ffi.*error|schema.*error|cue.*error|error.*cue|exception' \
     "/tmp/pr16-<run>-<test>-raw.log" \
     > "/tmp/pr16-<run>-<test>-errors.log"
   ```

5. Unless a row says otherwise, `exactly one`, `zero`, and line-count claims
   apply only inside that row's recorded byte range. `[X4GC TEST]` sweep records
   do not count as normal `[X4GC]` lifecycle lines. Missing/invalid offsets make
   log-dependent assertions BLOCKED, not PASS.

### How to prove the checked-group set

The engaged panel shows only the current camera turret, so one screenshot cannot
prove the complete checked-group set. For each persistence row, before Quick
Save or before opening Test Lab, use **Next Turret** repeatedly until it wraps to
the starting turret and record the ordered `turret: group` headers. After
restore, first verify the exact saved camera, then repeat one full cycle and
compare the complete ordered roster. The fixture requires camera-capable members
in every checked group, so a missing or extra checked group changes this roster.

When the test later returns to the console, also compare every checkbox with the
saved console screenshot. For Direct, exact baseline restoration remains a
separate required check. Record both forms where available; never infer the full
set from a single current turret.

## Preflight

### Environment record

- Tester:
- Date/time:
- X4 version:
- kuertee UI Extensions and HUD version/source:
- Exact Gunnery Control commit tested:
- Runtime marker expected: `2026-08-08-pr-review`
- UI language:
- Enabled DLC:
- Other enabled mods:
- Disposable save name:
- Test ship name and macro:
- Bridge/chair:
- Turret groups and turret types:
- Launcher-reported `debug.log` path:
- Screenshot/video folder:

### One required installation reset

1. Copy aside an existing `debug.log` if it matters; X4 truncates it on launch.
2. Exit X4.
3. In Windows Explorer, browse to this checkout through WSL and double-click:

   ```text
   \\wsl.localhost\<distro>\home\<user>\path\to\x4-gunnery-control\scripts\launch-x4-test-lab-dev.bat
   ```

   For a custom X4 location, run the same UNC path from Command Prompt and pass
   the game folder:

   ```bat
   "\\wsl.localhost\<distro>\home\<user>\path\to\x4-gunnery-control\scripts\launch-x4-test-lab-dev.bat" "C:\path\to\X4 Foundations"
   ```

   Do not copy the launcher to a normal Windows path: that path can start X4 but
   cannot reinstall this WSL checkout or start its filtered tail.
4. Do not use a reload button as a substitute for this initial reset. This PR
   adds `ui/gunnery_persistence.lua` and changes `ui.xml`, which require a full
   extension reload.
5. In X4's Extensions screen, confirm these are enabled:
   - X4 Gunnery Control
   - kuertee UI Extensions and HUD
   - X4 Gunnery Control — Test Lab
6. Enable X4 help texts for the Get Up/`Esc` notification tests.
7. Load only the disposable test save.
8. Confirm the launcher prints `Reinstalling loose development files...`, the
   resolved `debug.log` path, and opens a second **X4 Gunnery Log** window. That
   second window is the filtered live tail. Record the printed log path above.
9. **Agent:** find exactly this current-build marker in `debug.log` and record its
   line number/byte offset:

   ```text
   [X4GC] UI initialized; build=2026-08-08-pr-review
   ```

10. **Agent:** if the marker is missing or shows another build, mark preflight
    **FAIL** and stop. The installed files are not the files under test.
11. Open a gunnery console and confirm the **Test Lab** button exists.
12. Record the current Quick Save and Quick Load bindings. Use those bindings
    below so opening an unsupported full menu does not silently end a session.

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

First differing step:

Evidence files:

Notes:

### Primary fixture

Prepare one ship with:

1. At least two operational, camera-capable turrets.
2. At least two stable, mutable **grouped** rows, each visibly containing two or
   more member turrets. Do not use a synthetic single-turret row for mandatory
   Direct save/load: its component ID is intentionally discarded when X4
   remaps IDs during a game load.
3. At least one operational, camera-capable member in every grouped row you will
   check, so the full camera-roster cycle can prove the selected-group set.
4. Deliberately different original group states, such as one armed and one
   disarmed or two visibly different modes.
5. At least two safe hostile target candidates in radar range.
6. One target with visible engine, turret, or shield surface elements.
7. A safe way to destroy a disposable hostile target for target-loss tests.

Before every Direct-control test, record each checked group's displayed name,
mode, armed state, and operational/total count. A screenshot is preferred.

Grouped rows selected (name and visible members):

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

Fixture/save name:

Baseline screenshot:

Notes:

## Mandatory acceptance tests

### M0 — startup, console, and idle log volume

Purpose: prove the installed build starts, the menu remains reachable, and the
new protocol does not flood ordinary logs.

1. After preflight, remain outside the gunnery chair for 60 seconds.
2. **Agent:** record the start/end offsets of this outside-chair interval. Ignore
   the one startup marker and count any repeated `[X4GC]` lines in that range.
3. Sit at the gunnery console.
4. Wait for Gunnery Control to open and settle for ten seconds.
5. Record a second start/end time and do nothing for another 60 seconds.
6. Confirm the console lists turret groups and that Test Lab is reachable.
7. **Agent:** confirm there are no repeating request/grant, commit, scan, camera,
   lifecycle, or watchdog messages during either idle period.

Pass:

- The current build marker appeared once.
- The console opened normally.
- Expected one-shot lifecycle messages may appear.
- Stable idle time produces no repeating normal-success diagnostics.

Fail:

- Any log line repeats at update/watchdog cadence.
- Ordinary persistence traffic is logged continuously.
- The console or Test Lab button is unavailable.

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

Filtered line count before/after idle:

Outside-chair window:

Console-idle window:

First repeating line, if any:

Notes:

### M1 — Direct-control Reload UI transport

Purpose: exercise the full Lua request nonce → MD grant → accept → dynamically
named target/session replies → paired restore envelope path. This remains a
live-only inference until this test succeeds.

1. Set two checked mutable groups to different, recorded baseline states.
2. Enter **Direct-control**.
3. Select a live hostile whole ship or station hull.
4. Wait for the compact engaged panel.
5. Stay on **Turret POV manual** and note the current camera turret.
6. In the engaged upper-right panel, use the bottom **Test Lab** button below
   Prefer/Release. Do not enter Test Lab from the console or target browser.
7. In Test Lab, click **Reload UI** once.
8. **Agent:** confirm a new current-build startup marker appears in the evidence
   range.
9. Wait ten seconds without changing the view.
10. Confirm the engaged Direct panel returns with the same camera turret, hull
    target, and Turret/manual POV.
11. Confirm the view does not snap to another anchor during the ten-second wait.
12. Click **Cease Engagement**.
13. Confirm every checked group returns exactly to its recorded baseline.
14. Before Cease, compare one full restored camera-roster cycle with the saved
    cycle. At the console, also compare every restored checkbox with the saved
    checked-group screenshot.

Pass log:

```text
[X4GC] UI initialized; build=2026-08-08-pr-review
[X4GC] restore accepted; phase=engaged
```

Other one-shot lifecycle lines are allowed. There must be no repeating restore
loop and no Lua/FFI/MD error.

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

Groups/baselines:

Camera/target before and after:

Saved/restored checked-group screenshots:

Filtered log excerpt:

Notes:

### M2 — Direct ordinary Quick Save/Quick Load and teardown

Purpose: prove ordinary game save/load does not rely on opening Test Lab and
that Direct snapshots remain capable of restoring player settings.

#### M2A — teardown with Cease Engagement

1. Start a fresh console session.
2. Record two checked groups' baseline mode and armed state.
3. Enter Direct-control and select a hostile hull.
4. Wait for the compact engaged panel and note the camera turret and POV.
5. Quick Save directly from the engaged panel.
6. Wait for X4's save-complete indication.
7. Change to another camera turret or POV so the subsequent load is unambiguous.
8. Quick Load the save.
9. Do not touch controls for ten seconds.
10. Confirm Direct-control, saved camera turret, saved target, and saved POV
    returned—not the post-save change from step 7.
11. Compare one full restored camera-roster cycle with the saved cycle.
12. Confirm the soft target visibly points to the saved target.
13. Click **Cease Engagement**.
14. Confirm both groups exactly match their pre-test baseline and every console
    checkbox matches the saved selection.
15. Preserve screenshots of the baseline, saved state, deliberate post-save
    change, and restored state. Record the single `restore accepted` line.

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

Save/time:

Saved state versus post-save change:

Baseline screenshot:

Saved screenshot:

Post-save change screenshot:

Restored screenshot:

Restore-acceptance line:

Restored group states:

Notes/log excerpt:

#### M2B — teardown with Get Up

1. Repeat M2A steps 1–10 with a new save.
2. Before Get Up, compare one full restored camera-roster cycle with the saved
   cycle.
3. Click Gunnery Control's **Get Up** button.
4. Confirm the player returns to the normal chair/standing view.
5. Confirm the popup says `Turret groups restored to their previous settings.`
6. Confirm every Direct-controlled group matches its baseline.
7. Press `Esc` once and confirm X4's game menu opens immediately.
8. Preserve the same four state screenshots as M2A and record the single
   `restore accepted` line.

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

Save/time:

Popup text observed:

Baseline/saved/changed/restored screenshots:

Restore-acceptance line:

Restored group states:

Notes/log excerpt:

### M3 — Auto ordinary Quick Save/Quick Load without turret writes

Purpose: prove Auto restore retains its camera session but never mutates turret
mode or armed settings.

1. Start a fresh console session.
2. Check at least two mutable groups and record every checked group's mode and
   armed state.
3. Enter **Auto-engage** and wait for it to acquire a target.
4. Note the camera turret, target, and current POV.
5. Quick Save from the engaged panel and wait for completion.
6. Change camera turret or POV after the save.
7. Quick Load.
8. Do nothing for ten seconds.
9. Confirm Auto-engage, saved camera turret, saved target, and saved POV return.
10. Compare one full restored camera-roster cycle with the saved cycle.
11. Press `Esc` to return to the console.
12. Compare every checkbox with the saved selection and confirm all group
    settings remain unchanged.
13. Click **Get Up**.
14. Confirm the popup says `Gunnery Control disengaged.` and `Esc` works.
15. Preserve screenshots of the baseline, saved state, deliberate post-save
    change, and restored state. Record the single `restore accepted` line.

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

Save/time:

Camera/target/POV before and after:

Group states before/during/after:

Baseline/saved/changed/restored screenshots:

Restore-acceptance line:

Notes/log excerpt:

### M4 — all POVs and camera-turret selection survive ordinary save/load

Purpose: prove every saved final POV survives the delayed camera gate. Opening
Test Lab is forbidden in this matrix because it would make an extra commit and
mask missing button persistence.

Run the procedure below once for every row in the matrix.

1. Start a fresh engagement in the row's mode.
2. Select a non-first camera turret with **Next Turret** or **Previous Turret**
   when at least two are available.
3. Select the exact POV named in the row.
4. Wait until the view is visibly settled.
5. Record the mode, camera turret, target, anchor, and Manual/Cinematic state.
6. Quick Save directly. Do not open Test Lab.
7. Wait for save completion.
8. Change both the POV and camera turret after saving.
9. Quick Load.
10. Observe immediately, after two seconds, and after ten seconds.
11. Confirm the saved mode, target, camera turret, and exact POV returned.
12. Confirm no delayed callback pulls Target POV back to Turret POV.
13. For Cinematic rows, confirm UI/HUD is hidden and the correct anchor/look-at
    direction is used. Press `Esc` once and confirm the engaged Turret/manual
    panel returns—not the console or game menu.
14. End each Direct row with **Cease Engagement** and confirm every recorded
    baseline mode/armed value returns. End each Auto row with **Get Up**, confirm
    no group value changed, confirm `Gunnery Control disengaged.`, and verify
    `Esc` opens the game menu.
15. Before teardown, follow **How to prove the checked-group set** by comparing a
    complete restored camera-roster cycle with the saved cycle. Preserve the
    restored console screenshot too whenever the teardown reaches the console.

| ID | Mode | Saved POV | Result | Save/time | Immediate | 2 s | 10 s | Notes/evidence |
|---|---|---|---|---|---|---|---|---|
| M4A | Direct | Turret POV manual | [ ] P [ ] F [ ] B | | | | | |
| M4B | Direct | Target POV manual | [ ] P [ ] F [ ] B | | | | | |
| M4C | Direct | Turret POV cinematic | [ ] P [ ] F [ ] B | | | | | |
| M4D | Direct | Target POV cinematic | [ ] P [ ] F [ ] B | | | | | |
| M4E | Auto | Turret POV manual | [ ] P [ ] F [ ] B | | | | | |
| M4F | Auto | Target POV manual | [ ] P [ ] F [ ] B | | | | | |
| M4G | Auto | Turret POV cinematic | [ ] P [ ] F [ ] B | | | | | |
| M4H | Auto | Target POV cinematic | [ ] P [ ] F [ ] B | | | | | |

Matrix result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

First failing row/step:

Notes:

### M5 — exact surface-element target survives load

Purpose: distinguish restoring a root object from restoring the exact selected
engine, turret, shield, or station-module surface.

1. Enter Direct-control against a hostile object with surface elements.
2. In the upper-left element panel, select one engine, turret, or shield.
3. Confirm that exact element's button is greyed as the active selection.
4. Select **Target POV manual** and confirm the view is anchored to the
   selected element, not merely its ship/station hull.
5. Record the root target and exact surface name/type.
6. Quick Save directly and wait for completion.
7. After saving, select **Hull** so the load result is unambiguous.
8. Quick Load and wait ten seconds.
9. Inspect the upper-left element panel.
10. Confirm the same root object and exact saved surface are active and the same
    element button is greyed.
11. Confirm Target POV uses the element.
12. Cease and verify group baselines.
13. If a stationary hostile station module is readily available, repeat with a
    station-module surface and record it separately.

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

Save/time:

Root target:

Exact surface before/after:

Station module repeat:

Notes/log excerpt:

### M6 — Auto explicit no-target persistence

Purpose: prove an explicit no-target commit clears the old MD component instead
of reviving a stale target.

1. Use an otherwise empty/safe sector with one qualifying disposable target.
2. Record all checked group settings.
3. Enter Auto-engage and wait for that target to be acquired.
4. Destroy the target, or otherwise make its component non-operational, so no
   candidate remains. Moving an operational soft target out of range is not
   sufficient because the current soft target is deliberately retained.
   Do not use a friendly/player-owned target for live fire.
5. Wait at least six seconds for the Auto scan cadence.
6. **Agent:** confirm the evidence range contains exactly one:

   ```text
   [X4GC] auto target lost; scanning without a target
   ```

7. Confirm Auto stays engaged, switches to Turret/manual, and disables Target
   POV actions.
8. From the engaged panel, open Test Lab and click **Reload UI**.
9. Wait ten seconds after the restore.
10. Confirm Auto remains engaged without a target and the old target does not
    reappear.
11. Wait another ten seconds and confirm the loss line does not repeat every
    scan.
12. Confirm no turret mode or armed setting changed.

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

Target/removal method:

Target-loss line count:

Group settings before/after:

Notes/log excerpt:

### M7 — Direct target-loss branches and persisted Auto-next option

#### M7A — Auto-next Target enabled

1. Prepare hostile targets A and B in eligibility range.
2. Enter Direct-control against A with **Auto-next Target when destroyed**
   checked.
3. Quick Save, change the checkbox off after save, then Quick Load.
4. Confirm Auto-next restored as checked.
5. Destroy A, or otherwise make its component non-operational, while B remains
   eligible. Moving an operational A out of range does not trigger this branch.
6. Wait for the update cycle.
7. Confirm Direct stays engaged and B becomes the root, soft, and aim target.
   In Turret POV the camera must remain anchored to the selected turret while
   looking toward B; in Target POV it must use B as the saved target anchor.
8. **Agent:** confirm exactly one major transition line begins:

   ```text
   [X4GC] engaged target lost; auto-next engaged
   ```

9. Cease and confirm exact baseline restoration.

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

Targets A/B:

Save/time:

Observed transition:

Notes/log excerpt:

#### M7B — Auto-next Target disabled and target-selection restore

1. Start a fresh Direct engagement against A.
2. Uncheck **Auto-next Target when destroyed**.
3. Quick Save, check it again after save, then Quick Load.
4. Confirm Auto-next restored as unchecked.
5. Destroy A, or otherwise make its component non-operational. Moving an
   operational A out of range does not trigger this branch.
6. Confirm the UI returns to the target browser and resets to Turret/manual.
7. **Agent:** confirm exactly one major transition line begins:

   ```text
   [X4GC] engaged target lost; back to target selection
   ```

8. While still in the target browser, use its **Test Lab** button in the action
   row between Refresh and Back.
9. Click **Reload UI**.
10. Confirm the restore is accepted with `phase=target_select`.
11. Confirm the saved Direct snapshots are restored and the UI deliberately
    returns to the console. The observable proof that persistence cleared is
    step 13: the old session must not restore a second time.
12. Confirm no checked group remains stranded on armed `autoassist`.
13. Sit/reopen once more and confirm no old engagement restores again.

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

Target/removal method:

Restore/teardown observations:

Group states:

Notes/log excerpt:

### M8 — Map lifecycle around persisted phases

Run each row independently. Use Quick Save/Quick Load only where the row says;
do not open the full save menu.

Common procedure:

1. Establish the row's starting phase and record it.
2. Press `M` once.
3. Confirm Map appears.
4. Close Map with one `Esc`.
5. Observe after two seconds and ten seconds.
6. For rows marked Save/Load, repeat steps 1–3, Quick Save while Map is open,
   close Map, change POV if possible, and Quick Load.
7. If Map is visible after load, close it once.
8. Confirm the expected gunnery phase/state resumes and teardown remains safe.
9. At the row's teardown, compare a complete restored camera-roster cycle with
   the saved cycle and preserve the restored console screenshot for engaged rows.

| ID | Starting phase | Save/Load | Expected result | Result | Notes/evidence |
|---|---|---:|---|---|---|
| M8A | Console | No | Same console returns | [ ] P [ ] F [ ] B | |
| M8B | Auto engaged | Yes | Same Auto groups/target/camera/POV | [ ] P [ ] F [ ] B | |
| M8C | Direct engaged | Yes | Same Direct state; Cease restores baseline | [ ] P [ ] F [ ] B | |
| M8D | Direct target browser | No | Same target browser resumes with snapshots retained; Back restores them | [ ] P [ ] F [ ] B | |

For M8D, first enter Direct-control against a target, then click **Select
Engagement Target** to reopen the browser before pressing `M`. Do not use the
initial Direct picker; it has no live snapshots and cannot prove Back restores
an existing override.

A single `Map reopen did not display; retrying` may occur only if the first
handoff genuinely fails and then recovers. Repeating retries or a blank frame
are failures.

Matrix result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

First failing row/step:

Notes:

### M9 — Test Lab lifecycle around persisted phases

Use the Test Lab button belonging to the phase under test:

- Console: bottom action row beside Refresh/Get Up.
- Direct target browser: action row between Refresh and Back.
- Engaged Auto panel: its bottom row.
- Engaged Direct panel: bottom row below Prefer/Release.

For each row:

1. Establish and record the starting phase.
2. Open Test Lab from that phase's button.
3. With no sweep active, click Test Lab's standard top-right close button. (The
   **Abort** button exists only after a sweep starts; do not start one here.)
   Verify the originating gunnery phase returns: Console returns to Console;
   Auto/Direct engaged returns to that same engaged state; Direct target browser
   returns to that browser with its snapshots still owned.
4. Re-establish the phase.
5. Open Test Lab again from the same button.
6. Click **Reload UI**.
7. **Agent:** confirm the current startup marker and required restore line;
   **owner:** confirm the expected visible restored state.
8. Confirm there is no blank frame, orphaned input, or stale second restore.
9. At teardown, compare a complete restored camera-roster cycle with the saved
   cycle and preserve the restored console screenshot for engaged rows.

| ID | Starting phase | Expected Reload UI result | Result | Notes/evidence |
|---|---|---|---|---|
| M9A | Console | Console rebuilds; no engagement | [ ] P [ ] F [ ] B | |
| M9B | Auto engaged | Same Auto state restores | [ ] P [ ] F [ ] B | |
| M9C | Direct engaged | Same Direct state restores; Cease works | [ ] P [ ] F [ ] B | |
| M9D | Direct target browser reopened from an engagement | Snapshots release safely; return to console | [ ] P [ ] F [ ] B | |

For M9D, first enter Direct-control against a target, then click **Select
Engagement Target** to reopen the browser. Do not use the initial empty Direct
picker; it has no live Direct snapshots and cannot prove their release.

Matrix result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

First failing row/step:

Notes:

### M10 — Prefer/Release persisted state and live behavior

Purpose: verify normal saves retain settled Prefer/Release state and ordinary
operator use visibly applies and clears the preference. The exact 0.01-second
callback race is not human-reproducible and is listed under offline-only O7.

#### M10A — settled Prefer and Release across save/load

1. Use a ship with one checked Direct group plus at least one unchecked combat
   turret that is not already in `autoassist`. Put hostile A (the selected
   Direct target) and hostile B in that unchecked turret's firing arc.
2. Before clicking Prefer, confirm on video that the unchecked turret is firing
   at B, not A. If you cannot produce a distinguishable A/B firing direction,
   mark this test **BLOCKED** rather than inferring behavior from inactivity.
3. Enter Direct-control against hostile A.
4. Click **All Turrets: Prefer My Target**.
5. Wait one second for the deferred MD apply.
6. Confirm **Release Other Turrets** becomes available and the unchecked turret
   visibly changes its aim/fire from B to A. Record the video timestamp.
7. Quick Save, click Release after saving, then Quick Load.
8. Confirm the saved UI state still shows Release available and the unchecked
   turret visibly prefers A again.
9. Click **Release Other Turrets** and wait one second.
10. Confirm the unchecked turret stops being forced toward A and resumes B (or
    another independently selected target). If its own AI also selects A, reset
    the A/B fixture and repeat this observation once; if still indistinguishable,
    mark **BLOCKED**, not PASS.
11. Quick Save, click Prefer after saving, then Quick Load.
12. Confirm the released UI state returns and the unchecked turret is not
    forced back to A during a five-second observation.
13. Cease and verify checked-group baselines.

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

Unchecked turret observed:

Targets A/B and their positions:

Video timestamps for baseline / Prefer / restored Prefer / Release / restored Release:

Save/time for Prefer and Release:

Notes/evidence:

#### M10B — rapid operator Apply then Release

1. Re-enter Direct-control with at least one unchecked eligible combat turret.
2. Start a short video recording; normal success logging is intentionally
   silent.
3. Click **All Turrets: Prefer My Target**, then click **Release Other Turrets**
   as soon as the repainted panel makes it available.
4. Use the same distinguishable A/B setup as M10A and watch only the unchecked
   turret after the release.
5. Confirm it is not forced from B to the engaged target A.
6. Confirm the panel returns to Prefer available / Release unavailable.
7. Wait five seconds and confirm the preference does not visibly reassert.
8. Cease and confirm checked-group baselines.

This is an ordinary live safety check, not proof of the sub-frame callback race.

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

Video filename:

Unchecked turret behavior:

Notes/log excerpt:

### M11 — normal cross-ship/chair cleanup

This tests supported cleanup. Preserving a foreign parked payload while moving
ships is not safely forceable through normal UI and is listed under offline-only
coverage below.

1. On ship A, enter Direct-control and record baseline settings.
2. Use Get Up or the normal stand-up interaction.
3. Confirm ship A's settings restore and the camera/input state clears.
4. Move normally to ship B and sit in a gunnery chair.
5. Confirm a fresh console appears with ship B's groups.
6. Confirm no ship-A target, camera turret, checked group, or Direct mode appears.
7. Return to ship A and verify its group settings remain at baseline.

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

Ships/chairs:

Ship-A baselines after return:

Notes/log excerpt:

### M12 — final teardown count and quiet soak

1. Across the tests above, complete at least five Direct **Cease Engagement**
   operations and at least three **Get Up** operations.
2. Record whether each restored exact mode/armed values.
3. **Agent:** filter the accumulated evidence for
   `post-restore readback mismatch`.
4. Require zero matches for a pass.
5. **Owner:** start one stable **Auto** engagement, wait until its panel and
   target have visibly settled, then report that checkpoint.
6. **Agent:** record the stable-minute start time and byte offset, then instruct
   the owner to take no action for 60 seconds.
7. **Agent:** record the end time/offset and count only new filtered `[X4GC]`
   lines in that exact byte range.
8. Require zero normal-success lines during the stable minute.
9. A natural camera mismatch may log once per session; the same line repeating
   every 0.25 seconds is a failure.

| # | Source test | Exit (`Cease`/`Get Up`) | Group + baseline mode/armed | Actual mode/armed | Exact? | Evidence |
|---|---|---|---|---|---|---|
| 1 | | | | | [ ] Y [ ] N | |
| 2 | | | | | [ ] Y [ ] N | |
| 3 | | | | | [ ] Y [ ] N | |
| 4 | | | | | [ ] Y [ ] N | |
| 5 | | | | | [ ] Y [ ] N | |
| 6 | | | | | [ ] Y [ ] N | |
| 7 | | | | | [ ] Y [ ] N | |
| 8 | | | | | [ ] Y [ ] N | |

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

Mismatch count:

Stable-minute byte range and filtered line count:

Notes/evidence:

## Conditional and destructive live tests

These are valuable but may be **BLOCKED** by available ships, targets, or the
inability to control destruction timing. Never alter an important save to force
them.

### D1 — saved camera turret destroyed, another usable turret remains

1. Use Direct-control with at least two checked camera-capable turrets A and B.
2. Select A as the current camera and record baselines.
3. Open Test Lab from the engaged panel; this parks A in the payload.
4. While Test Lab remains open, allow controlled hostile damage to make A
   non-operational while B remains operational.
5. If the world is paused or A cannot be destroyed without leaving Test Lab,
   mark **BLOCKED**; do not improvise save editing.
6. Click **Reload UI**.
7. Confirm restore falls back to B and remains engaged with the saved mode,
   target, and POV.
8. Cease and confirm exact baseline restoration.

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

Damage method and turret status:

Fallback turret:

Notes/log excerpt:

### D2 — no usable restored camera, Direct then Auto

Run once in Direct and once in Auto if a controlled setup is available.

1. Establish the engagement and record settings.
2. Open engaged Test Lab to park it.
3. While Test Lab remains open, make every camera-capable member in the checked
   groups unavailable/non-operational.
4. Click **Reload UI**.
5. **Agent:** confirm this one-shot line:

   ```text
   [X4GC] restore has no camera member; returning to console
   ```

6. Direct pass: settings restore exactly once, MD state clears, and the console
   returns with no invisible engagement.
7. Auto pass: the console returns and no turret setting is written.
8. Reopen once and confirm the failed session does not restore again.

| Mode | Result | Group writes/restoration | Second restore? | Notes/evidence |
|---|---|---|---|---|
| Direct | [ ] P [ ] F [ ] B | | | |
| Auto | [ ] P [ ] F [ ] B | | | |

### D3 — target destroyed after payload is parked but before restore

1. Engage a disposable target.
2. Open Test Lab from the engaged panel to park the target.
3. While Test Lab remains open, have another actor destroy the target.
4. If the timing cannot be controlled, mark **BLOCKED**.
5. Click **Reload UI**.
6. Confirm no dangling or wrong component becomes the target.
7. Confirm the mode uses its safe target-loss/no-target behavior.
8. **Agent:** confirm no FFI or MD error appears; **owner:** confirm teardown
   remains visibly safe.

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

Target/destruction method:

Observed restored state:

Notes/log excerpt:

### D4 — unsupported full menus safely tear down

1. Enter Direct-control and record baselines.
2. Open Player Information or another full-menu hotkey that is not Map.
3. Confirm the session safely ends rather than assuming it can resume.
4. Confirm Direct settings restore and camera/input are normal.
5. Repeat once from Auto and confirm no turret settings change.

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

Menus tested:

Direct/Auto results:

Notes/log excerpt:

### D5 — mining/towing turrets are excluded from Prefer/Release

1. Use a mixed ship with combat turrets plus a mining or towing turret.
2. Put the mining/towing turret into an observable normal activity if your
   fixture permits; otherwise record its stable mode/armed state.
3. Check combat groups only and enter Direct-control.
4. Select a hostile target.
5. Click Prefer, wait one second, then click Release.
6. Observe the mining/towing turret through both actions.
7. Confirm it never retargets, changes mode, disarms, or goes idle because of
   either click.

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

Ship/loadout/activity:

Observed behavior:

Notes/video:

### D6 — duplicate humanized turret-group labels

1. Use a Split Raptor if available; otherwise use a Phoenix E.
2. Open the console and locate rows whose full displayed base collides, such as
   `Center Upper: <equipment shortname>` repeated for identical equipment.
3. Confirm suffixes distinguish only those full-label collisions:
   `Center Upper: <equipment>`, `Center Upper: <equipment> · 2`, and where
   applicable `... · 3`. Different equipment shortnames need no numeric suffix.
4. Record non-zero operational/total counts.
5. Select only the first colliding row and Direct-control a safe hostile.
6. Observe which physical turrets enter armed `autoassist`.
7. Cease and confirm restoration.
8. Repeat for each colliding row.
9. Confirm commanding one row never changes another row's physical turrets.

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

Hull and displayed labels/counts:

Per-row physical behavior:

Notes/screenshots:

### D7 — broader bridge, target, and compatibility coverage

Restore the clean baseline before changing compatibility configurations. Run at
least M2A, M3, M4B, M4D, M5, and M12 under each configuration attempted.

| Configuration | Version/source | Rows run | Result | Notes/evidence |
|---|---|---|---|---|
| Additional vanilla/DLC bridge | | | [ ] P [ ] F [ ] B | |
| Turret Behaviour Resurrected | | | [ ] P [ ] F [ ] B | |
| Subsystem Targeting Orders | | | [ ] P [ ] F [ ] B | |
| Station-module surface target | | | [ ] P [ ] F [ ] B | |

## Test Lab current-ship sweep

Run this once on the primary fixture and again for each extra ship used above.

1. Sit in the ship's gunnery chair and open Gunnery Control.
2. Click **Test Lab** from the console action row.
3. Click **Start Current Ship Sweep**.
4. **Agent:** direct exactly one listed turret per owner turn and record its
   displayed index/name before issuing the action.
5. **Owner:** for that turret only, click **Inspecting turret camera** and observe
   the unobscured camera for the full five seconds.
6. After returning to the chair, report what was visible. When the agent asks
   for the verdict action, choose exactly one: Visual Pass, Visual Fail, Retry,
   or Skip.
7. **Agent:** poll/reconcile the technical log result and owner's observation,
   write that turret's index/name/verdict/evidence in Notes, then wait before
   directing the next turret.
8. Do not mark Visual Pass merely because technical checks passed.
9. After all physical turrets have a verdict, allow Test Lab to complete every
   mutable group snapshot/apply/restore check.
10. Record the final on-screen summary.
11. At the end of the X4 run, parse `[X4GC TEST]` records into CSV.

Pass gate:

- Every inspected turret ends with a deliberate **Visual Pass**; `Visual Fail`
  and `Skip` counts are zero. A Retry is allowed only if its eventual verdict is
  Visual Pass and its technical result is clean.
- The final summary reports `Technical N/N`, where N is every queued physical
  turret, and `Group verification: pass/fail G/0`, where G is every mutable
  group tested.
- The parsed CSV agrees with the on-screen counts and contains no technical,
  target-preservation, visual, or group failure.

Result: [ ] PASS [ ] FAIL [ ] BLOCKED [ ] NOT RUN

Ship:

Visual failures/skips:

Technical/group failures:

Summary screenshot/CSV:

Notes:

## Offline-only coverage — no owner action required

Do not claim live coverage for these without a purpose-built instrumented build.
They have deterministic automated coverage because normal X4 controls cannot
create the required malformed or reordered transport safely.

### O1 — stale unaccepted grant race

Sequence: request A → clear → request B → delayed grant A → valid grant B.
Engine event scheduling offers no manual delay injection. Adapter tests prove A
cannot claim B and B still completes.

Owner result: **OFFLINE ONLY**

### O2 — malformed or foreign persisted payload

Cases include `t=session`, invalid enums, incomplete snapshots, and a foreign
ship payload arriving while a live Direct session owns snapshots. Producing
these requires MD/save injection. Runtime tests prove the exact live session,
epoch, callbacks, camera, MD events, and turret writes remain untouched.

Owner result: **OFFLINE ONLY**

### O3 — re-point return false and thrown calls

Normal X4 exposes success but no safe control that forces `SetSofttarget` to
return false or throw on demand. Automated tests cover success, refusal, first
throw with exactly one retry, second throw, and retry refusal. If a natural
failure occurs, preserve these one-shot signatures:

```text
[X4GC] re-point target refused; abandoning
[X4GC] re-point retry refused; abandoning
[X4GC] re-point target raised twice; abandoning
```

Owner result: **OFFLINE ONLY unless observed naturally**

### O4 — removed/reordered turret through ordinary save/load

Loading a save restores that save's world and loadout, so an operator cannot
normally remove the saved turret while the game is closed. D1/D2 approximate
this with a parked MD payload; deterministic tests cover truly missing members.

Owner result: **OFFLINE ONLY for exact removed-member case**

### O5 — forced menu-open versus delayed-reopen event ordering

The engine scheduler decides which ordering occurs. Record the ordering observed
in M1/M2/M9, but do not claim both orderings unless both happened naturally.

Owner result: **OBSERVATIONAL ONLY**

### O6 — foreign payload retained while changing ships

Normal chair exit correctly emits `session_end`, so normal play cannot carry an
old parked payload into another ship. M11 covers supported cleanup; injected
foreign-payload rejection remains automated-only.

Owner result: **OFFLINE ONLY**

### O7 — Apply/Release inside the 0.01-second deferred callback window

The vulnerable order is Apply → Release before the next delayed UI callback is
drained. The Apply handler repaints the panel before a human can click Release,
so “within one second” does not reproduce this sub-frame race. The runtime test
invokes both real UI handlers before draining callbacks and proves the stale
apply neither emits nor re-persists `preferAllTurrets=true`. M10B covers only
ordinary rapid operator behavior.

Owner result: **OFFLINE ONLY**

## Final evidence package

Before another launch, the directing agent performs the filesystem/log commands
below. The owner only supplies screenshots, videos, and visible observations.
If the agent cannot access the recorded log path, it stops and asks for access
rather than delegating routine log interpretation back to the owner.

1. Copy the complete `debug.log` to a stable filename.
2. From the repository root, create the filtered log:

   ```bash
   ./scripts/filter-gunnery-log.sh "/path/to/debug.log" > pr16-live.log
   ```

3. Parse Test Lab records:

   ```bash
   ./scripts/parse-testlab-log.sh "/path/to/debug.log" > pr16-testlab.csv
   ```

4. Preserve screenshots/videos referenced in this checklist.
5. Summarize all mandatory results:

| Test | Result | First failing step or short note |
|---|---|---|
| Preflight | | |
| M0 | | |
| M1 | | |
| M2A | | |
| M2B | | |
| M3 | | |
| M4 | | |
| M5 | | |
| M6 | | |
| M7A | | |
| M7B | | |
| M8 | | |
| M9 | | |
| M10A | | |
| M10B | | |
| M11 | | |
| M12 | | |
| Test Lab sweep | | |

6. List every conditional/destructive result as PASS, FAIL, BLOCKED, or NOT RUN.
7. Attach the stable raw `debug.log`, `pr16-live.log`, and `pr16-errors.log` for
   every acceptance run, including a passing run. Preserve an additional copy
   of the full raw log immediately when any error occurs.
8. Report the first failure before later cascading observations.

Overall mandatory result: [ ] PASS [ ] FAIL [ ] INCOMPLETE

Conditional/destructive summary:

Logs attached:

Screenshots/videos attached:

Final notes:
