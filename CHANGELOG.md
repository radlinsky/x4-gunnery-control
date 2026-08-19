# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

- Add a selectable Direct-control turret policy with two manual modes,
  `attackenemies` and `autoassist`, surfaced as the **Direct-control turret
  mode** selector on both the main console and the Direct-control engaged panel.
  `attackenemies` keeps the preferred-target/fallback-list path; `autoassist`
  follows the player's selected soft target/surface element and installs no
  script fallback list, so unable-to-engage turrets may remain idle. Checkbox
  membership stays authoritative and separate from policy/effective-mode
  resolution. Changing policy while Direct-control is engaged immediately
  re-modes the checked groups. Auto-engage is independent and continues to use
  `attackenemies` for checked groups. Active sessions persist and restore the
  selected policy; legacy saves without the field default to **Attack all
  enemies**.

- Remove **Update turret behavior** from the Auto-engaged and Direct-control
  engaged views. The permanent commit action now lives only on the main
  Gunnery Control console, with its existing dirty/clean enablement and commit
  semantics unchanged.

- Change the ENGAGEABLE weapon-reach gate from the mining-style
  `distanceto + size/2` heuristic to combat `bboxdistanceto le maxfirerange`, so
  reachable hull or modules on large roots (e.g. station roots) are no longer
  rejected as out of range. Test Lab `inrange` diagnostics were aligned with the
  production calculation.

- Add a per-module line-of-fire fallback to the ENGAGEABLE probe. A raycast is
  point-to-point and `useaimtarget` can resolve to a target's bounding-box
  centre, which for a station root sits inside its own hull and self-blocks the
  root ray even while turrets fire at its modules. When the root line of sight
  fails, and only when the evaluated target is the whole defensible root
  (`$target == $target.defensible`) with more than one operational module, the
  probe scans that root's operational then construction modules and re-checks
  line of fire, stopping at the first visible in-range module or when the list is
  exhausted (no module-count cap). The module loop mirrors vanilla
  `move.attack.object.capital`, which retargets a whole-object attack to a
  visible module; admitting the root is gated on `defensible.ismodular or
  canhaveattackablemodules`, which follows vanilla target selection
  (`lib.target.selection`) rather than the capital attack move itself, so the
  rare capital ship with an embedded targetable defence module is covered too.
  An individually selected surface element keeps its own direct root
  line-of-fire test and never triggers the module fallback (#62). The range
  predicate, deliberate own-hull masking, arc handling, and denominator/
  membership are unchanged.

- Resolve Direct-control surface-element loss asynchronously. On loss the
  same-root surface snapshot is refreshed and the next candidate is chosen in
  order: the other ENGAGEABLE surface elements on the same ship or station root,
  ranked and paged 20 at a time; then the root hull; then the ranked other
  objects in range. An incomplete-coverage ENGAGEABLE zero is never treated as a
  settled zero, a candidate that died after its positive evidence is never
  engaged, and
  turning Auto-next off or leaving Direct-control mid-resolution cancels the
  pending fallback.

- Enrich **Select Engagement Target** with the player-facing S/M/L/XL class (or
  Station), localized ship type, distance, top/bottom Refresh controls, and an
  `N / total ENGAGEABLE` result for every candidate. Once engageability results
  settle, candidates for which every selected/evaluated turret is ENGAGEABLE
  sort ahead of the existing relationship/distance order.

- Rebuild the engaged surface element browser for large ships and stations.
  Operational turret, shield, and engine surface elements can be filtered by
  type. Alternatives use explicit size-first ordering
  (XL → L → M → S → XS, then type, distance, stable ID), are paged 20 at a
  time, and retain the current aim point as a pinned row outside the filters.
  The pinned row refreshes distance/ENGAGEABLE independently and shows shield
  and hull percentage; the parent hull remains directly selectable from a
  surface element target. Manual refresh is retained and optional automatic
  refresh rebuilds the surface element snapshot every 10 seconds.

- Add the current **ENGAGEABLE** geometry service for exact selected operational
  turret membership. Each known turret contributes only when its official
  traverse arc contains the aim direction, the target is within weapon range,
  and a muzzle-origin line-of-fire check remains clear while including the
  firing ship for self-occlusion. Unknown/modded turret arcs remain in the
  denominator and are reported as **UNKNOWN** rather than being promoted by
  range/line-of-fire alone. Requests use bounded batches of at most 20 targets,
  preserve nonce/session/signature/denominator guards, reject stale replies, and
  coalesce repaints so large station surface element lists do not issue one
  transport round-trip and full render per surface element.

- Standardize current player-facing fire-control terminology on **ENGAGEABLE**,
  **CANNOT BEAR**, and **LINE OF FIRE BLOCKED**. This was a terminology/service
  rename only; the accepted engagement geometry was not broadened into a claim
  about readiness, authorization, moving-target intercept, or actual firing.

- Add staged-vs-committed turret behavior. Console Mode/Armed edits are staged
  during the Gunnery Control session. When the player gets up, closes the
  console, undocks, or changes ships, the previous turret settings are restored
  unless **Update turret behavior** was clicked first. That action commits the
  current Mode/Armed settings so they persist after leaving the chair.

- **Loading a save no longer loses your gunnery session.** Save/load restoration
  rebuilds the live session against the loaded ship and turret-group identities
  instead of trusting stale component IDs. Controlled live acceptance restored
  the checked groups, control mode, turret POV, and active target in both
  Direct-control and Auto-engage; the committed turret baseline is also
  re-keyed onto live group identities for safe teardown.

- **Target POV works after loading.** The restored target/camera state is now
  re-applied so Target POV works immediately rather than only after switching to
  another surface element and back.

- Removed **Other Turrets: Prefer My Target** and **Release Other Turrets**. The
  Release behavior was unreachable with the X4 API: re-feeding the hostile list
  does not revert `defend`, `missiledefence`, or `mining` modes because those
  modes use a curated target list rather than the standard hostile list.
  Direct-control (ticking turret groups) covers directing turrets at a chosen
  target without leaving an unrevertable ship-wide override.

- Put engaged-panel target cycling controls in conventional order: **Previous**
  on the left and **Next** on the right.

## [0.30] - 2026-08-07

- New **All Turrets: Prefer My Target** during Direct-control: no more idle
  turrets. Every turret on the ship shoots your target when it can, and shoots
  something else in range when it cannot. **Release Other Turrets** hands the
  rest of the ship back while your checked groups stay on your target; ceasing
  or getting up releases everything. Mining and towing turrets are left alone
  in both directions, so a mixed ship keeps doing its other jobs.

- Hitting **Release Other Turrets** immediately after **Prefer My Target** now
  really releases. The apply is sent a tick late so the turret modes land first,
  and a release in that gap used to arrive ahead of it: the panel said released,
  the ship stayed overridden, and nothing afterwards could clear it because the
  console already believed it was off. The pending apply is now dropped if you
  released or picked a new target first.

- The turret Mode column now updates when you cease an engagement. It used to
  keep showing `autoassist` afterwards even though the turrets had already gone
  back to their own mode, so the panel disagreed with the ship.
- Direct-control works on small ships again. On a Katana the target browser
  appeared for a split second and then dumped the player back on the console.
  `enterCamera()` asks the engine for a target view on one turret and then reads
  the view back to confirm it took. On S/M ships the engine accepts the request
  but resolves the view to the turret's *container*, the ship, so the readback
  never matched the turret id, the gate declared failure, and it tore the session
  down 100 ms after the browser painted. Capital ships resolve to the turret
  component itself, which is why this was never seen there.

  The container now counts as a match: the camera is where we pointed it, just
  wider. Auto-engage ran through the same gate and is fixed with it. The wider
  view is a real consequence and is noted under Limitations in the README.

  Second change on the same path: a camera that genuinely cannot attach no longer
  closes the target browser. It is logged and target selection carries on. Losing
  the camera should never cost the player the ability to pick a target.

- Turret groups are no longer locked to camera-only when two of them share a
  name. `readGroups()` walks turret slots to build each group's member list, and
  because the slot API reports no context ID it could not always tell same-named
  groups apart. That uncertainty was wired into `canMutate()`, so an unresolved
  group had its mode dropdown and armed button greyed and was dropped from
  Auto-engage and Direct-control.

  It was guarding nothing. Mode and armed commands address a group by
  `contextID`+`path`+`group`, which `GetUpgradeGroups2` always reports exactly;
  the slot walk never feeds the write path. Vanilla does the same thing: it
  walks turret slots only for *ungrouped* turrets and drives grouped ones purely
  through the context ID. `canMutate()` now asks only whether the group still
  has an operational turret.

  Known limitation, left as-is: if two groups really do share a name, turrets
  other than each group's representative all get listed under the first of them,
  so member rows can sit under the wrong group name and Direct-control may open
  the camera on a sibling group's turret. Commands still reach the right group.
  No X4 API resolves this, and no shipped ship macro produces the case. All 53
  turret group declarations across the 126 stock 9.00 ship macros use path `..`
  with unique names.

- Fix every null-ID guard in the runtime. A `UniverseID` read out of an FFI
  struct is boxed cdata, so `tostring()` on an unset one gives `"0ULL"`, not
  `"0"`. Nine guards tested `tostring(x) == "0"` and therefore never fired in
  game. `State.isNullID()` now owns the check (nil, `0`, `"0"`, `"0ULL"`) and
  all nine route through it. Comparing a raw cdata id against the number `0`
  was always safe. LuaJIT compares boxed uint64 numerically, so the sites
  written that way were never affected.

  This makes the soft-target restore in 0.20 real: `restoreSofttarget()` was
  reaching `C.SetSofttarget(0, "")` rather than `RemoveSofttarget()` on every
  session that started with no soft target, which is exactly the call that
  release said it had stopped making. See the correction under 0.20 below.

  No Lua test could have caught this. Every harness stubs ids as plain
  numbers, where `tostring(0)` really is `"0"`, so `test_runtime_ui_contract.sh`
  now rejects the `tostring(x) == "0"` shape outright.

- Remove the post-exit diagnostic sampler. It wrote `DebugError` lines for 90
  seconds every time you left the gunnery seat; the bug it was hunting was
  fixed in 0.20.

## [0.20] - 2026-08-06

- Widen the console's turret group and turret name column so full names are
  readable. The name cell now spans columns 2-4 of the 8-column table instead
  of sitting in column 2 alone; columns 6-8 were dead filler. The action row
  still uses all 8 columns, so the column count is unchanged.

- Widen the Esc-cure popup coverage to the `playerGetUp` and `playerUndock`
  routes. Previously the notify event was emitted only from `leaveChair` (the
  Get Up button path); a player who stood up via `Shift+D` or the vanilla
  stand-up interaction, or who undocked, would still get a dead `Esc`. The
  emission is now in `discardSession`, guarded by `seatLeaving = true`, so
  both teardown routes share the same fix. The "stale session before chair
  redirect" path (player has just sat down) stays silent as before.

- Show a helptext popup when the player leaves the gunnery seat. If the session
  was Direct-control and turret groups were overridden, it reads "Turret groups
  restored to their previous settings."; otherwise it reads "Gunnery Control
  disengaged." (Auto-engage never mutates settings). This popup is also
  load-bearing: three in-game trials confirmed that calling
  `SetPlayerCameraTargetView` from a turret seat leaves `Esc` dead after the
  player stands up. This is a bug invisible to every readable engine flag, and
  the `show_help` MD action cures it by forcing `CreateView`/`DisplayView` via
  `View.createView()` in `ego_viewhelper`. See
  `.agents/skills/research-x4-modding/references/ui-lua-menu-camera.md` for
  the full three-arm trial record.

- Never leave X4's global soft target on the player's own ship. `enterCamera()`
  borrows the soft target to force the camera onto a turret and restores it a
  tick later, but restored an empty one with `C.SetSofttarget(0, "")`, which is
  not a documented clear since no vanilla call ever passes 0. `RemoveSofttarget()`
  is the engine's clear (`targetsystem.lua:1747,2097,2130`). The restore
  callback is also epoch-guarded, so a session ending inside that 0.05 s window
  never restored at all; `clearOwnShipSofttarget()` now runs on every teardown
  as the belt. Candidate fix for Esc not opening the game menu after a session
  that moved the camera. The post-exit sampler logs `soft=<id>/root=<id>` so
  the next log confirms or kills it.

  **Correction:** this did not ship working. The new guard read
  `tostring(previousID) == "0"`, which is false for the `"0ULL"` that FFI
  actually hands back, so `RemoveSofttarget()` was never reached and
  `C.SetSofttarget(0, "")` went out exactly as before. Same for
  `clearOwnShipSofttarget()`, whose early-out never fired either. Fixed under
  Unreleased above.

- Add an **Auto-next Target** checkbox to the compact Direct-control panel,
  checked by default (`session.autoNextTarget`). Checked, the death of the
  engaged object re-engages the next candidate through `engageTarget()`, so the
  soft target, `session.targetObjectID` and the camera all move together. If
  unchecked, or checked with no candidate left, the view resets to manual
  Turret POV and the target browser reopens. Previously only
  `session.aimTargetID` moved: the camera followed the next ship while every
  overridden group stayed armed against a wreck and the panel still named the
  dead target.

- Replace the per-turret Watch and Engage buttons with group-level checkboxes
  and two shared action buttons: **Auto-engage** (camera-only, mutates nothing)
  and **Direct-control** (arms every checked mutable group to `autoassist`
  against one chosen target element). Selection is at group level because X4
  only exposes `SetTurretGroupMode2` and `SetTurretGroupArmed` per linked group;
  a per-turret checkbox would silently command its unchecked siblings. Ungrouped
  turrets appear as their own single-member group and remain individually
  selectable.
- Both modes land in one compact live panel: current turret name plus four POV
  buttons (Turret/Target × manual/cinematic) and Next/Previous Turret to cycle
  the camera circularly through every operational turret of the checked groups.
  Direct-control additionally shows the engaged target element and keeps
  Select Engagement Target and Cease Engagement.
- Collapse the old `watch` and `direct` phases into `phase = "engaged"` with
  a `controlMode` field (`"auto"` or `"direct"`). Camera state now has two
  independent axes: `session.povAnchor` (`"turret"` or `"target"`) and
  `session.povMode` (`"manual"` or `"cinematic"`). `applyPov()` is the single
  camera-entry point that reads both.
- `session.directSnapshot` replaced by `session.directSnapshots`, a list. One
  snapshot per overridden group. `restoreDirect` loops over every entry;
  per-entry failures (group destroyed) are logged and skipped so one
  unresolvable snapshot never strands the remaining groups on armed `autoassist`.
  The MD bridge is opaque passthrough; `RestoreSession` accepts a legacy single
  snapshot from saves made before this change.
- Auto-retarget: `chooseAimTarget()` picks the aim point from
  `readTargetCandidates()` (enemy → nearest hostile → nearest). Direct-control
  holds it until the target dies; Auto-engage re-checks on a 5 s cadence (each
  check is a whole-sector sweep, so it must not run on the 4 Hz refresh tick)
  and may switch to a better target. Because X4 exposes no way to
  read what a turret is currently shooting at (verified against the full FFI
  export table and MD script properties), the cinematic camera's aim point is
  chosen by the mod and usually matches the turret but can disagree.
  Retargeting while a cinematic is running stops and restarts the cutscene;
  the player sees a brief camera cut.
- Document two engine ceilings: (1) the cinematic POV hides all UI, so
  Next/Prev and all panel controls are unreachable while a cinematic runs;
  `Esc` is the only exit and returns to the manual panel. (2) No turret-target
  getter exists in the public FFI surface or among the 609 undeclared engine
  exports examined so far.
- Remove the `target_detail` phase. Clicking a target in the browser now
  engages its hull immediately; the intermediate hull/element picker screen is
  gone. Valid phases are now `console | target_select | engaged`.
- Add a **Next Target / Previous Target** row to the compact upper-right panel
  (direct mode only). Cycles the engaged target through the same candidate list
  and order as the target browser (enemy → hostile → nearest). Greyed when one
  candidate or fewer. Re-issuing the engagement via these buttons is also how
  the player recovers after the current target is destroyed. Direct-control
  never re-issues the turret order by itself on target death.
- Add an upper-left **element panel** (direct mode only), titled with the
  engaged target's name. Lists Hull and every operational turret, shield, and
  engine surface element; the currently attacked one is greyed. Clicking another
  element re-points all overridden turret groups at it. The "Engaged Target"
  row that was in the upper-right panel is replaced by this panel's title.
- Restore the vanilla teardown order: `Helper.closeMenu()` untracks the menu
  and only then unregisters its views (`helper.lua:1908-1947`). The get-up path
  used to unregister the views first, which was a guess at the missing-HUD bug
  and never helped. It is the one thing this menu did that no vanilla menu does,
  and it lines up with the remaining report: after a session that opened a
  `playerControls` frame (target browser or live panel), `Esc` stopped opening
  the game menu until another menu opened and closed. Console-only sessions,
  which never register such a frame, always kept `Esc` working. A smoke test
  asserts the teardown trace starts with the close.
- Fix the table header rows: they asked for `Color["row_background_header"]`,
  which the game does not define, so every `display()` logged a "Tried to access
  non-existing color" error with a stack traceback. Now `row_title_background`
  (vanilla, e.g. `menu_trader_inventory.lua:298`). A contract test checks every
  colour name used against a list verified in the 9.00 UI source.
- Log the registered View entries (`views=<n>[id/menu,...]`) on every session
  state line and in the post-exit sampler, plus
  `CanSetPlayerCameraCinematicView()` after exit. Diagnostic for the remaining
  report: after a session that ran a cinematic, `Esc` no longer opens the game
  menu until another menu (or a seat click) opens and closes. A view that
  outlives its menu would keep the engine in menu-input mode; the logged
  session without a cinematic did not reproduce it.
- Return to the default Turret POV as soon as the engine ends the cutscene,
  without waiting for an `Esc` to reach the panel. The player's first `Esc`
  during a cinematic goes to the cutscene, so the panel used to keep claiming
  the cinematic was current: a second `Esc` to repaint it and a third to go back
  a menu. Polled with `C.IsFullscreenCutsceneActive()` on the 4 Hz refresh, and
  only after the cutscene has been seen running, so the stop/start gap of a
  retarget restart is not read as the player leaving.
- Log the camera-gate mismatch once per refresh instead of once per frame; it
  was emitting ~60 lines/s and burying everything else in the log.
- Stop hiding the HUD on every frame that takes player controls (the target
  browser, the compact panel, the element panel). A HUD hidden by such a frame
  is never restored: a logged trial that opened only the fullscreen console kept
  its HUD, while one that opened the target browser and pressed `Esc` twice with
  no cinematic or engagement lost it. Only the fullscreen console still hides
  the HUD. A contract test rejects `keepHUDVisible = false` outright.
  Follow-up: the console kept hiding it, and the logged
  browser(`hud=true`) -> console(`hud=false`) -> exit sequence still lost the
  HUD, so **every** frame of this menu now agrees on `keepHUDVisible = true`.
  The HUD is therefore drawn behind the fullscreen console too.
- One `Esc` out of a cinematic now returns to **Turret POV manual**, the default
  view, whichever anchor was on screen, instead of staying on the same anchor.
- Log `hud=` (`C.IsHUDActive()`) on every session state line, not only in the
  post-exit sampler: after get-up the cutscene is stopped, `IsExternalViewActive`
  and `IsExternalTargetMode` are both false, and the HUD render state is still
  off, so the next thing to establish is exactly when it flips.
- Defer the frame teardown on get-up by one tick. Vanilla's Get Up button only
  calls `C.GetUp()` and lets the `playerGetUp` event close the menu
  (`menu_docked.lua:283,1442`); closing synchronously unregisters our
  `keepHUDVisible=false` view in the middle of the engine's get-up transition.
  The session state is still discarded immediately; only `Helper.closeMenu()`
  and the view unregistration wait. Still unconfirmed as the HUD fix; the
  post-exit sampler now also logs `IsExternalViewActive()` and
  `IsExternalTargetMode()`, since `GetExternalTargetViewComponent()` keeps
  returning a component after get-up.
- Fix `Esc` out of a cinematic POV. It fell through to the ordinary close path,
  so the cutscene (`duration 999999`, `cinematicmode="true"`) kept running
  invisibly beneath the panels for the rest of the session, and the HUD stayed
  off because cinematic mode owns the HUD toggle. `Esc` now stops the cutscene
  and returns to the manual panel, as the README already claimed. `leaveChair()`
  also emits `cutscene_aim_stop` before `GetUp()` rather than relying on
  `discardSession()`, whose event MD only handles a tick later, after the
  camera has already changed.
- Use `": "` instead of an em dash in every composed label; the game font
  renders the em dash as a placeholder glyph.
- Add a **select-all** checkbox in the console's group-column header: checks
  every mutable group, or clears the selection when they are all already checked.
- Give every frame a solid semi-transparent background
  (`Color["frame_background_semitransparent"]`, the vanilla pattern) so cell text
  is legible over the live view, and inset the console table by 20px so the
  group checkboxes are not flush with the left screen edge.
- Unregister our own frame views in `endSession()` before `Helper.closeMenu()`.
  `Helper.clearMenu()` skips `View.unregisterMenu()` for any frame it considers
  invalid, and a still-registered view keeps its `keepHUDVisible=false` in force
  after the menu is gone. This was the suspected cause of the HUD staying hidden
  after leaving the chair. The post-exit sampler now logs `hud=` from
  `C.IsHUDActive()` to tell "engine says HUD off" apart from "HUD on but not
  redrawn" if the symptom survives.
- Fix the upper-left element panel outliving its phase: `Helper.clearDataForRefresh`
  does not touch `menu.frames`, so the panel stayed registered as its own view
  (`Helper3`) and kept rendering over the target browser and the console until
  the whole menu closed after three `Esc` presses. `menu.display()` now calls
  `Helper.clearFrame(menu, elementFrameLayer)` whenever it is not rebuilding the
  panel. The missing HUD after the final `Esc` is expected to share this cause
  (two views unregistering at once) and needs live confirmation.
- Fix `sameID()`: raw FFI ids (e.g. from `targetRoot()`) stringify with a
  `ULL` suffix while `id()`-converted ones do not, causing the same component
  to compare unequal. `sameID()` now delegates to the exported `State.normID()`.
  For the same reason all `GetComponentData` calls are routed through the
  `componentData()` wrapper, which applies `id()` first. Passing a raw FFI id
  silently returns nil for every key.

- Fix `Esc` delivery in Watch and compact Engage by removing
  `useMiniWidgetSystem = true` from camera-phase frames and adding `close =
  true` to their `standardButtons`; `Esc` in Watch is now intended to return
  to Gunnery Control and `Esc` in compact Engage is intended to reopen the
  target picker (fix in code; not yet confirmed in game).
- Fix target detail so pressing `Esc` steps back one level to the object list
  rather than jumping directly to the console.
- Add a visible Back button to the Watch frame so the camera phase has a
  supported exit control in addition to `Esc`.
- Model UI ownership separately from console/Watch/target/Engage phase, restore
  an Engage override if X4 auto-clears the Helper frame, and discard stale
  sessions before chair re-entry.
- Treat Map as the first explicitly resumable interruption; unsupported menu
  hotkeys fail safe instead of relying on a generic visible-menu heuristic.
- Mark the tracked menu non-fullscreen and add visible compact-Engage Back/Close
  controls to improve pause, input, and recovery behavior pending live testing.
- Write Windows development logs with an unquoted bare `-logfile debug.log`,
  which X4 requires to produce any log, print the resolved userdata path before
  launching, and add a focused Gunnery/Test Lab log filter plus a deterministic
  lifecycle procedure.
- Fully close transparent camera frames and return to the cockpit/chair camera
  on get-up or undock, fixing blank-view re-entry after sitting down again.
- Decode directional ship-macro turret groups into labels such as Front Upper
  Left and append the installed turret type, with safe fallbacks for opaque IDs.
- Keep a transparent Watch frame on the menu stack and fail safe if an X4
  target-bracket click or automatic hide removes it without delivering a normal
  close callback.
- Place the Engage browser over the live, unblurred turret view and collapse it
  after target selection to a compact upper-right control panel; the panel's
  Back button reopens the browser.
- Exclude the occupied ship and its surface elements from Engage while allowing
  other owned/friendly/neutral objects to be selected. Document that normal
  `autoassist` still refuses targets which fail X4's `mayattack` checks.
- Request HUD and ticker suppression without changing persistent notification
  settings; document that transient Messages/notifications can still appear.
- Rename Direct to Engage and add an in-console current-sector known
  ship/station browser limited by the player's ship radar range, followed by a
  hull or operational turret/shield/engine surface element choice. Station
  modules are included when enumerating station surface elements.
- Engage now arms the selected linked group in `autoassist`; X4 remains
  responsible for aiming, firing, and `mayattack` legality.
- Resolve the current ship through the player's enclosing container when X4
  reports no occupied ship at a secondary bridge control post.
- Reinstall the mod automatically when `launch-x4-dev.bat` starts, so Windows
  users no longer need to run `install-dev.sh` by hand before launching. The
  launcher derives the WSL distro from its own UNC path and calls the installer
  through `wsl.exe -d <distro>`; if the install fails, the launcher exits with
  code `4` without starting X4. Exit codes are now `0` success, `2` X4.exe not
  found, `3` Windows failed to start X4, `4` install failed. The installer now
  wipes and replaces the full extension directory so deleted files do not linger.
- Add a Windows development launcher with X4 path detection, loose-file
  preference, full debug logging, documentation, and regression checks.
- Fix custom-menu transitions so the vanilla Docked menu cannot race the
  Gunnery Control or Test Lab menu, and display frames with the X4 9.00 API.
- Add UI initialization and gunnery-chair redirect diagnostics.
- Detect the runtime `gunnercontrol` chair group instead of mistaking the
  bridge asset's `gunnertrigger` cockpit tag for the control-group value.
- Defer and retry UI host-menu hook registration, with a `gameplanchange`
  fallback, so extension load order cannot silently disable chair redirection.

## [0.1.0] - 2026-08-03

- Initial practical gunnery-chair console for X4 9.00.
