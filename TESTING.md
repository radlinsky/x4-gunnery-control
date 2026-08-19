# X4 Gunnery Control Test Lab

Test Lab is a separate **developer-only** extension. It is not included in the
normal Nexus ZIP and should not be installed by ordinary players.

## Open live checks

A queue, not a matrix. Each entry is something the offline tests cannot settle,
with the steps to settle it and the exact signature that means failure. Delete
an entry once it has a dated result; move anything durable into the research
knowledge base. The coverage matrix further down is what to test on every
build; this section is what is currently unanswered.

For PR #16, use `PR16_LIVE_TEST_CHECKLIST.md` as the canonical procedure and do
not repeat this queue separately: item 1 maps to M10/O7, item 2 to D5, item 3 to
M12, and item 4 to D6. Record results in the checklist, then use them to retire
or update these durable open questions.

Every check assumes a filtered log:

```bash
./scripts/filter-gunnery-log.sh /path/to/x4-gunnery-control-debug.log
```

### Deferred research lookup: padded turret group ids

Vanilla ship XML pads `group=` with spaces, inconsistently between connections
naming the same group. Whether `GetUpgradeGroups2` strips that before Lua sees
it remains an inference; the code tolerates both. The shipped padding probe was
removed to keep ordinary logs concise, so silence in a normal run is not
evidence that the engine trims. Settle this only in an explicitly instrumented
research run before changing the classification of the research KB record
"Group identifiers in ship component XML carry surrounding whitespace".

### 1. Is the 2026-08-07 mode-write race dead? (added 2026-08-07)

The per-write diagnostics were removed in `0b48b90`; the post-restore readback
now logs only on disagreement, so silence is the pass condition.

1. Over a normal play session, cease at least five engagements and get up from
   the chair at least three times, on more than one ship if convenient.
2. Filter the log for `post-restore readback mismatch`.

- **Pass:** no lines.
- **Fail:** `post-restore readback mismatch for N group(s): REASON`. The engine
  did not take one or more restore writes. Keep the log and the ship/groups;
  this is the original race resurfacing.

### 2. Duplicate turret group labels on the known hulls (added 2026-08-07)

Fifteen shipped hulls have two groups that humanize to one label. Addressing is
by key, so this should be cosmetic only. Worst case is the Split Raptor, where
three groups collapse to "Center Upper".

1. Sit in a Raptor (`ship_spl_xl_carrier_01`), or failing that a Phoenix E
   (`ship_tel_l_destroyer_02`), and open the console.
2. Look at the group list, then check one group at a time and Direct-control it.

- **Pass:** identical full labels appear as `Center Upper: <equipment>`,
  `Center Upper: <equipment> · 2`, and where applicable `... · 3`, each with its
  own non-zero turret count, and commanding one changes only that group.
  Different equipment names already distinguish rows and need no suffix.
- **Fail:** entries with a zero or `0 / 0` count, entries named `Turret 1` style
  fallbacks, or a mode change on one entry visibly moving another group's
  turrets. Any of those means attribution collapsed and the KB record
  "15 shipped ships have two turret groups that humanize to the same label" is
  wrong about the consequence.

## Build and install

Build both archives from the repository root:

```bash
./scripts/package.sh 0.1.0
./scripts/package-testlab.sh 0.1.0
```

Install the normal archive first, then extract the Test Lab archive beside it:

```text
X4 Foundations/extensions/x4_gunnery_control/
X4 Foundations/extensions/x4_gunnery_control_testlab/
```

Enable X4 Gunnery Control, kuertee UI Extensions and HUD, and Test Lab in the
Extensions menu. From a repository checkout on Windows, start the session by
double-clicking the launcher in Windows Explorer:

```text
\\wsl.localhost\<distro>\home\<user>\path\to\x4-gunnery-control\scripts\launch-x4-test-lab-dev.bat
```

The launcher reinstalls the main mod automatically before starting X4; no
separate install step is needed. No arguments are needed for a default Steam or
GOG installation. The `UNC paths are not supported.` notice from `cmd.exe` is
expected and harmless. Use a Command Prompt instead when a custom installation
folder is required:

```bat
"\\wsl.localhost\<distro>\home\<user>\path\to\x4-gunnery-control\scripts\launch-x4-test-lab-dev.bat" "C:\Program Files (x86)\Steam\steamapps\common\X4 Foundations"
```

Keep the launcher path on `\\wsl.localhost\...` even when passing a custom game
folder. A launcher copied to a normal Windows path can start X4, but it cannot
find the WSL checkout to reinstall loose files or start the filtered log tail.

If the launcher is unavailable, or when testing on Linux, start X4 with
`-prefersinglefiles -debug all -logfile debug.log`. Leave the `-logfile` value
unquoted; X4 silently writes no log at all if it is quoted or omitted. The log
lands in X4's own userdata folder, and the launcher prints the resolved path
before launching. Each launch truncates the previous log, so copy a run aside
before relaunching.

## One-ship workflow

Test Lab intentionally does **not** spawn ships, teleport the player, or force
the player into a chair. Use the current [Safe Cheat Panel](https://www.nexusmods.com/x4foundations/mods/1971)'s **Spawner** and
**Teleport To** features to set up one ship at a time. Those operations remain
manual so this extension does not depend on undocumented game APIs.

When testing the main Gunnery Control modes, confirm the following for the
**console** phase:

- Turret groups are listed with a **checkbox** per group row. Member turrets
  below each group show name and operational status only, with no per-turret
  action buttons.
- **Auto-engage** and **Direct-control** are greyed until at least one mutable
  group is checked.
- Checking at least one mutable group activates both buttons.

**Auto-engage** is camera-only. Verify that no turret group's mode or armed
state changes after pressing it. The live panel opens with the current turret
name, four POV buttons (Turret POV manual, Target POV manual, Turret POV
cinematic, Target POV cinematic), and Next Turret / Previous Turret. Next/Prev
cycle through every operational turret of all checked groups in console order
and wrap around; both buttons are greyed when only one operational turret
qualifies. Cycling changes only the camera focus, never what is engaged.
The camera-view frames request `keepHUDVisible=false` and
`showTickerPermanently=false`; verify live that the HUD/ticker are actually
suppressed for the installed game/UI combination. Record transient mission
updates, notifications, and the bottom-left Messages area separately: X4 can
still show them in ticker-only mode. This does not change persistent
notification settings.

**Direct-control** first opens a smaller, unblurred browser of known ships and
stations in the current sector within the player ship's radar range. It excludes
the occupied ship and its surfaces, not every player-owned object. Clicking a
target immediately engages its hull — there is no intermediate hull/element
picker screen. The browser must collapse to a compact upper-right panel at that
point. **Every checked mutable group** must be set to armed `autoassist` —
not just one.

Verify the **upper-left element panel**: it is titled with the engaged target's
name and lists Hull (greyed by default, because hull is what engage selects)
plus every operational turret, shield generator, and engine surface element.
Clicking a non-active element must re-point all overridden turret groups at it,
greying that button instead. For stations, surface elements include station
modules.

Verify the **Next Target / Previous Target** row in the upper-right panel: it
cycles through the same candidate list in the same order as the target browser
(enemy → hostile → nearest) and is greyed when only one candidate exists.
Clicking Next or Previous must re-engage the next or previous ship/station hull
and update the element panel accordingly.

The upper-right panel keeps **Select Engagement Target** and **Cease
Engagement** in addition to the shared four POV and Next/Prev turret buttons.
**Cease Engagement** restores the exact prior mode and armed state for every
overridden group. X4 remains responsible for aiming, firing, and
`mayattack`/other safety checks. Registered target brackets are clickable
outside the compact panel and should change the soft target without losing
Direct-control; arbitrary unbracketed 3D geometry is not a supported picker
path.

Note: Direct-control never re-issues the turret order on its own. If the
engaged target is destroyed, the camera moves on but the turrets fall back to
autoassist; Next Target or Previous Target is how the player re-engages a
different one.

Map is the first supported resumable interruption. From the console and the
live panel, `M` followed by Map close should reacquire the owned session;
a half-completed target picker may deliberately return to the console. Other
full-menu hotkeys are safety tests: until individually supported they must
restore any override and end the camera session without leaving input locked.
Getting up must likewise restore every overridden group, remove the camera
frame, and allow a completely fresh console when the chair is occupied again.

1. Spawn or obtain the next test ship with Safe Cheat Panel.
2. Teleport to it with Safe Cheat Panel.
3. Manually sit in its `Access Gunnery Control` chair. Force-sitting is manual.
4. Open the gunnery console and choose **Test Lab**.
5. Choose **Start Current Ship Sweep**. At completion, choose Start Current Ship
   Sweep again to begin a new run for the current ship.
6. For every turret, select Inspect. The menu hides while the Test Lab keeps its
   update loop alive; inspect the turret camera for five seconds.
7. After the game returns to the gunnery chair, explicitly choose Visual Pass,
   Visual Fail, Retry, or Skip. Technical camera stability never counts as a
   visual pass.
8. After all physical turrets have a verdict, Test Lab automatically checks each
   mutable group once: mode/armed snapshot, temporary `autoassist` + armed,
   verification, exact restoration, verification. It clears the soft target and
   never sends a fire command.
9. View the final on-screen summary or parse `[X4GC TEST]` records:

```bash
./scripts/parse-testlab-log.sh "/path/to/debug.log" > testlab-results.csv
```

Abort, getting up, undocking, changing game plan, or loading a game returns the
camera and clears the in-memory sweep.

## Recommended coverage matrix

| Axis | Minimum coverage |
|---|---|
| Bridge | Argon XL, Paranid XL, Teladi L/XL, every installed DLC bridge whose cockpit trigger declares `gunnertrigger` and whose chair reports `gunnercontrol` |
| Turret | beam, projectile, missile, mining, and at least one damaged/destroyed turret |
| Grouping | ungrouped turret (appears as its own single-member group), linked group, fully destroyed group (camera only) |
| Motion | stationary, player ship turning, NPC captain moving the ship |
| Checkbox gate | Auto-engage and Direct-control greyed with no checked groups; activated once at least one mutable group is checked |
| Auto-engage | Mode and armed state of every checked group unchanged after entering and exiting; Next/Prev cycles and wraps when two or more groups are checked; Next/Prev greyed when only one operational turret qualifies |
| Direct-control | Clicking a target in the browser engages its hull immediately with no intermediate picker; every checked mutable group set to armed `autoassist`; upper-left element panel lists Hull (greyed) plus surface elements; clicking a non-active element re-points all groups; Next/Previous Target cycles in browser order and is greyed when ≤1 candidate; Cease Engagement restores all groups. Save/load restores the session as of 2026-08-08: the console reopens engaged, same groups checked, same turret POV, same target, and Cease afterwards still returns every group to its original mode. |
| Cinematic POV | Game UI hidden while cinematic runs; `Esc` from cinematic returns to manual panel; kill the target while cinematic and confirm camera restarts on the next target (brief cut expected); confirm turrets keep firing during the cinematic |
| Lifecycle | Cease Engagement, close console/Get Up, undock, teleport/ship change, save/load, retry, skip |
| Menu lifecycle | From console and live panel: open/close Map and verify documented resume/fallback; try Player Information and another hotkey and verify safe teardown, not assumed resume |
| Re-entry | Get up from every phase, sit again, and verify no blank transparent frame or stale camera remains |
| Target input | In the live panel: click a new bracket and confirm the soft target changes without losing the engaged mode; click the already-current bracket; confirm `Esc` from the manual panel returns to the console (Auto-engage) or to the target picker (Direct-control); confirm `Esc` from a cinematic POV returns to the manual panel |
| Compatibility | clean UI Extensions setup, Turret Behaviour Resurrected, Subsystem Targeting Orders |

Record the ship macro/name, bridge, turret macro, Test Lab summary, and relevant
filtered log lines in the issue report. A technical failure is evidence for the
camera release gate; it is not a reason to mark the turret visually passed.

## Camera release gate

Test every vanilla bridge whose cockpit trigger declares `gunnertrigger`,
including Argon/Paranid XL and Teladi L/XL examples. At runtime the occupied
chair reports the distinct `gunnercontrol` control group. X4 can report no
"occupied ship" at this secondary post, so the extension resolves and validates
the ship containing the player, matching vanilla `DockedMenu` behavior. While
the ship moves, turns, and targets change, verify:

- `GetExternalTargetViewComponent()` remains the selected physical turret;
- the camera does not fall back to the whole ship;
- the player can return to the gunnery chair; and
- no Lua errors occur.

If a bridge fails, retain the diagnostic log and report it rather than claiming
turret-centered operation for that bridge.

## Seat-exit popup and Esc-cure checklist

**Prerequisite:** hints/help texts must be enabled in X4 game options
(**Settings → Interaction → Help Texts** or equivalent). If help texts are
disabled the `show_help` MD action is a no-op: the popup does not appear and
the Esc-cure does not fire. Enable them before this checklist and record
whether they were on or off if any step fails.

For each row, sit in the gunnery chair, enter the listed mode, leave the seat
via the listed route, and check both the popup text and that `Esc` opens the
game menu immediately after standing up.

| Mode entered | Exit route | Expected popup text | Esc opens game menu |
|---|---|---|---|
| Auto-engage (camera only, no group override) | Our **Get Up** button | "Gunnery Control disengaged." | Yes — immediately |
| Direct-control (at least one group overridden) | Our **Get Up** button | "Turret groups restored to their previous settings." | Yes — immediately |
| Auto-engage | Stand up via `Shift+D` or the vanilla stand-up interaction (not our button) | "Gunnery Control disengaged." | Yes — immediately |
| Direct-control | Stand up via `Shift+D` or the vanilla stand-up interaction (not our button) | "Turret groups restored to their previous settings." | Yes — immediately |
| Auto-engage | Undock (if applicable to the ship) | "Gunnery Control disengaged." | Yes — immediately |
| Direct-control | Undock (if applicable to the ship) | "Turret groups restored to their previous settings." | Yes — immediately |

**Failure mode to watch for:** if the popup appears but `Esc` is still dead,
the `show_help` MD action ran but did not reach `View.createView/DisplayView`.
If the popup does not appear at all, confirm help texts are enabled and inspect
the filtered log for any MD or Lua error during the `Notify` cue. The normal
notification-emission diagnostic is intentionally silent.

## Deterministic lifecycle reproduction

Use a disposable save and completely restart X4 after reinstalling loose files.
Run one sequence without improvising so visible transitions can be compared:

1. Sit in an empty gunnery chair and wait for Gunnery Control.
2. Check one mutable group. Press **Auto-engage**, press `Esc` once and confirm
   it returns to Gunnery Control (not X4's main menu). Wait two seconds.
3. Press **Auto-engage** again, switch to a cinematic POV, press `Esc`, and
   confirm the manual panel returns (not the console). Press `Esc` again and
   confirm it returns to the console. Wait two seconds.
4. Press **Auto-engage** once more, press `M`, close Map with one `Esc`,
   then wait two seconds.
5. Check a second mutable group. Press **Direct-control**, click a target in
   the browser, and confirm the browser immediately collapses to the compact
   panel — no intermediate hull picker. Confirm both groups are armed
   `autoassist`. Confirm the upper-left element panel lists Hull (greyed) plus
   surface elements. Confirm Next Target / Previous Target is active when more
   than one candidate exists. Choose **Select Engagement Target** to confirm
   the browser expands, then re-select and confirm the panel returns.
6. With the panel showing, press `M`, close Map, then choose **Cease
   Engagement**. Confirm both groups are restored to their original mode and
   armed state.
7. Press **Direct-control** again, enter a cinematic POV, then press `Shift+D`
   once to get up. Confirm both overridden groups are restored and no blank
   transparent frame remains. Sit in the chair again and verify a fresh console.
8. Fully exit X4 and filter the printed log path:

```bash
./scripts/filter-gunnery-log.sh "/mnt/c/Users/<Windows-user>/Documents/Egosoft/X4/<numeric-id>/debug.log" > lifecycle.log
```

Attach `lifecycle.log` and note which numbered step first differed. Do not keep
pressing keys after a failure; the first unexpected transition is the useful
one.

## Target matrix and live-fire caution

The default Test Lab sweep does not fire. Its group verification clears the
soft target before it arms `autoassist`, verifies that it is clear, and restores
the original target/settings afterward. The camera sweep also records whether
the exact target object ID and surface-element connection were preserved.

Run these target cases manually while capturing Test Lab logs:

| Target case | Expected Test Lab result |
|---|---|
| No target | Remains no-target after the camera sweep |
| Friendly whole ship | Target is preserved; do not use it for live fire |
| Other player-owned ship | It is listed/selectable, but normal autoassist does not fire |
| Hostile whole ship | Target is preserved |
| Hostile engine, turret, or shield surface element | Exact surface-component ID and any returned connection are preserved |
| Stationary hostile station surface element | Exact module-surface component ID and any returned connection are preserved |
| Target destroyed during a manual Direct-control test | Record the expected preservation failure and cleanup result |

Safe Cheat Panel's Extended mode can spawn an NPC-faction ship or station for
these manual scenarios; it cannot create arbitrary standalone modules. Live-fire
tests are explicit, manual follow-up work outside the default Test Lab and
targets may fight back. For ship targets, use a minimally armed L freighter;
for stationary surface-element work, use a station and target a module.
