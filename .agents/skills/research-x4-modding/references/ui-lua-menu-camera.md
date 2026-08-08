# UI, Lua, menu, camera, and targeting evidence

## Gunnery-control identity and ship resolution

### Gunnery chair control group differs from cockpit trigger
- X4: 9.00
- Status: shipped-source
- Source: `assets/interiors/bridges/bridge_arg_xl_01.xml` (also present on other L/XL bridges)
- Live test: no — untested as of 2026-08-03
- Finding: bridge assets can use `gunnertrigger`, while the seated secondary
  control group reported to UI Lua is `gunnercontrol`; do not compare them as
  the same identifier.

### Secondary controls may lack an occupied-ship ID
- X4: 9.00
- Status: shipped-source
- Source: `ui/addons/ego_detailmonitor/menu_docked.lua`
- Live test: no — untested as of 2026-08-03
- Finding: resolve the player's enclosing `container`, then validate it is a
  ship when the occupied-ship query is zero at a secondary control post.

## Input-frame and camera lifecycle

### Registered frames own close handling
- X4: 9.00
- Status: shipped-source
- Source: `ui/addons/ego_detailmonitorhelper/helper.lua`
- Live test: no — untested as of 2026-08-03
- Finding: an active Helper frame registers menu close handling; a tiny
  transparent frame can retain Esc ownership while allowing player controls.
  Verify actual stack behavior in game because menu layering is asynchronous.

### Refreshing a live menu is not the same as clearing it
- X4: 9.00
- Status: shipped-source
- Source: `ui/addons/ego_detailmonitorhelper/helper.lua`;
  `ui/addons/ego_detailmonitor/menu_toplevel.lua`
- Live test: no — untested as of 2026-08-03
- Finding: `Helper.clearMenu(menu)` unregisters frame events and clears
  `menu.shown`/update ownership. Use `Helper.clearDataForRefresh(menu)` when
  rebuilding the currently shown menu so its close callback remains on the
  input stack. Vanilla TopLevel menu refreshes follow this pattern.

### Hidden-HUD frame flags do not suppress every notification
- X4: 9.00
- Status: shipped-source
- Source: `ui/addons/ego_detailmonitorhelper/helper.lua`;
  `ui/core/lua/monitors.lua`
- Live test: no — untested as of 2026-08-03
- Finding: `keepHUDVisible=false` hides the normal HUD and
  `showTickerPermanently=false` prevents a permanently visible ticker, but
  ticker-only mode can still activate for recent mission updates and queued
  notifications. Do not promise that these frame properties hide every
  bottom-left Messages item or mutate player notification settings.

### Turret target-view functions exist
- X4: 9.00
- Status: shipped-source
- Source: `ui/addons/ego_interactmenu/menu_interactmenu.lua`; `ui/core/lua/monitors.lua`
- Live test: no — untested as of 2026-08-03
- Finding: `SetPlayerCameraTargetView` and
  `GetExternalTargetViewComponent` support requesting and verifying an
  external target view; a bridge-specific live camera gate remains required.

### External Target View notice appears on every camera entry, not on repeated activation

- X4: 9.00
- Status: live-tested
- Scope: the notice is live-tested; its cause remains inference
- Source: game session on 2026-08-04, extension `x4_gunnery_control`
  build marker `2026-08-04-lifecycle-1`, Windows 11, X4 9.00 Steam;
  `ui/core/lua/infobar2.lua` (notice generation)
- Live test: yes — notice observed on Watch entry and on every Engage view
  entry on 2026-08-04; X4's "External Target View Activated (Standard View:
  F1)" banner appears each time the camera enters that mode
- Finding (live-tested): entering the external turret view shows X4's own
  "External Target View Activated (Standard View: F1)" notice. It appears for
  both Watch and every Engage view entry.

  Finding (inference): a prior hypothesis held that the notice recurs because
  the extension re-activates the camera repeatedly. That is not supported by
  the shipped source. `SetPlayerCameraTargetView` is called only in the
  camera-entry path plus one conditional retry; the per-frame update path only
  reads `GetExternalTargetViewComponent` to compare focus and never re-activates.
  The notice therefore appears to be X4's standard notice for entering that
  camera mode at all, not an artifact of redundant calls.

  Open question: whether the notice can be suppressed temporarily without
  modifying vanilla files or persistent notification settings is unresolved.
  `hideInfoBar2` and the monitor-extent functions (`GetMonitorExtents`) are
  documented as leads in Stage 5 of the project plan. Do not claim any
  suppression method works.

## Targets and surface elements

### Soft targets preserve component IDs and connection names
- X4: 9.00
- Status: shipped-source
- Source: `ui/core/lua/targetsystem.lua`
- Live test: no — untested as of 2026-08-03
- Finding: soft-target state contains a component ID and connection name;
  preserve both when restoring a target.

### Direct surface-element IDs are an installed-mod technique
- X4: 9.00
- Status: third-party-technique
- Source: `extensions/kuertee_surface_element_targeting/ui/menu_toplevel_uix.lua`
- Live test: no — untested as of 2026-08-03
- Finding: the installed Kuertee Surface Element Targeting extension sends a
  selected surface component ID to `SetSofttarget` with an empty connection.
  Re-verify against vanilla/runtime behavior before treating this as public.

### Sector containment returns arrays of IDs
- X4: 9.00
- Status: documented-public
- Source: https://wiki.egosoft.com/X%20Rebirth%20Wiki/Modding%20support/UI%20Modding%20support/Lua%20function%20overview/
- Live test: no — untested as of 2026-08-03
- Finding: `GetContainedShips([space], [showonmap])` and
  `GetContainedStations([space], [showonmap], [includeconstruction])` return
  ship/station ID arrays; pass a current-sector ID to scope a picker.

### Upgrade slots expose operational surface components
- X4: 9.00
- Status: shipped-source
- Source: `ui/addons/ego_detailmonitor/menu_interactmenu.lua`
- Live test: no — untested as of 2026-08-03
- Finding: enumerate turret, shield, and engine upgrade slots and keep only
  operational components. For stations, enumerate station modules too before
  scanning their slots.

### Vanilla turret group IDs can contain positional words
- X4: 9.00
- Status: shipped-source
- Source: `assets/units/size_l/*.xml`; `assets/units/size_xl/*.xml`;
  `ui/addons/ego_detailmonitor/menu_docked.lua`
- Live test: no — untested as of 2026-08-03
- Finding: vanilla ship macros include identifiers such as
  `group_front_up_left`, `group_back_down_right`, and `group_mid_bottom`, but
  some use opaque names such as `group01`. Runtime group data exposes the raw
  group/path and equipment macro, not a dedicated transform or localized
  positional label. Best-effort token humanization plus equipment short name
  is reasonable only with an opaque-name fallback; never infer direction from
  list order.

### Registered target brackets are mouse-pickable
- X4: 9.00
- Status: shipped-source
- Source: `ui/core/lua/targetsystem.lua`
- Live test: no — untested as of 2026-08-03
- Finding: the target system registers mouse interactions on known target icon
  and bracket elements. When choosing a different target it calls
  `CloseMenusUponMouseClick()` before setting the new soft target. Clicking the
  already-current target can close menus without changing the target. A camera
  overlay must therefore delay its comparison, and the current-target case
  remains ambiguous with Esc because the frame close callback reports no input
  source; cover both paths in live tests.

### Restoring cockpit camera after GetUp locks player input
- X4: 9.00
- Status: live-tested
- Scope: the symptom is live-tested; the precise input-lock mechanism remains inference
- Source: game session on 2026-08-04, extension `x4_gunnery_control`
  build marker `2026-08-04-lifecycle-1`, Windows 11, X4 9.00 Steam
- Live test: yes — symptom reproduced on 2026-08-04; ordering defect is unambiguous in
  the code path, but whether input hold was the only thing locked was not proven
- Finding: calling `C.SetPlayerCameraCockpitView(true)` after `C.GetUp()` has already
  returned true leaves the player standing with no HUD, no mouse interaction, and no
  working `Esc`; the game must be killed. Restore the camera while the player is still
  seated, then get up. A shared teardown routine must suppress the cockpit-camera
  restore on every path where the player has already left the seat, including the
  `playerGetUp` and `playerUndock` events, not just the explicit close path.

  Diagnostic trap: after such a teardown the extension can go completely silent in the
  log, because a subsequent `playerGetUp` handler early-returns when the session is
  already nil and the menu is already hidden. Silence in the log is not evidence that
  nothing happened.

### Esc delivery to a frame depends on frame properties, not playerControls

**Earlier record retracted.** A prior live test concluded that `Esc` is never
delivered to a frame when `playerControls = true` and that an extension cannot
own `Esc` there. That conclusion was wrong twice over:

1. `playerControls` was never the discriminator. In this project's own code,
   `target_select` and `target_detail` are built with `playerControls = true`
   and `Esc` works in both. The prior claim was refuted by one line of project
   source.
2. A hotkey probe logged zero `onHotkey` deliveries and was read as proof that
   no input reaches those frames. It proved nothing: no addon bindings were ever
   registered, so the game had nothing to emit.

The shipped Helper source (`ui/addons/ego_detailmonitorhelper/helper.lua`)
documents frame properties including `exclusiveInteractions` (default false),
`enableDefaultInteractions` (default true), `useMiniWidgetSystem` (default
false), and `closeOnUnhandledClick` (default false). Two mechanisms govern
`Esc` delivery in practice:

#### Mechanism A: `useMiniWidgetSystem = true` disables default Esc/Del handling

- X4: 9.00
- Status: live-tested
- Corroboration: shipped-source establishes the property meaning
- Source: `ui/addons/ego_detailmonitorhelper/helper.lua`
- Live test: yes — fix observed 2026-08-04; Watch and compact Engage frames
  set `useMiniWidgetSystem = true` and did not receive `Esc`; removing that
  flag restored delivery
- Finding: the Watch and compact Engage frames set `useMiniWidgetSystem = true`.
  That disables default `Esc`/`Del` handling for those frames. The `console`,
  `target_select`, and `target_detail` frames do not set it and receive `Esc`
  normally. `exclusiveInteractions`, `closeOnUnhandledClick`, and
  `enableDefaultInteractions` were all at their defaults on every frame and did
  not explain the difference. The only shipped vanilla menu using
  `useMiniWidgetSystem` is `ego_debuglog`, a passive overlay with no need for
  a back action.

#### Mechanism B: Esc requires `standardButtons` including `close = true`

- X4: 9.00
- Status: live-tested
- Source: game session on 2026-08-04, extension `x4_gunnery_control`
  build marker `2026-08-04-lifecycle-1`, Windows 11, X4 9.00 Steam
- Live test: yes — reproduced 2026-08-04; Watch log showed `dueToClose=close`
  together with `extmenu=OptionsMenu` before the fix, confirming X4 had taken
  the key
- Finding: every frame that received `Esc` declared `standardButtons` including
  `close = true`. The Watch frame declared only `back = true`; `Esc` therefore
  fell through to X4, which opened `OptionsMenu` and replaced the extension
  frame. Adding `close = true` is the fix. Note that the action reported to
  `onCloseElement` can still be `back` when a back button is also present, so
  the delivered action name and the button that enabled delivery are not the
  same thing.

#### Mechanism C: a Helper frame must contain a table to receive Esc (decisive fix for Watch)

- X4: 9.00
- Status: live-tested
- Corroboration: shipped-source establishes the frame/table mechanism
- Source: `ui/addons/ego_detailmonitorhelper/helper.lua` (`frame:display()`);
  game session on 2026-08-04, extension `x4_gunnery_control`
  build marker `2026-08-04-lifecycle-1`, Windows 11, X4 9.00 Steam
- Live test: yes — Watch `Esc` delivery confirmed working in game 2026-08-04
  after adding a table with real dimensions and content; Esc no longer leaked
  to `OptionsMenu`
- Finding: `frame:display()` scans frame content for a widget of type `table`
  and sets a `hastable` flag. That flag gates `Helper.handleTableDesc` and, in
  the view-created callback, `Helper.handleCreatedTables`. A frame without a
  table still receives `Helper.setScripts` binding `onHide` to the menu's close
  element handler — so the frame appears wired but is not fully interactive.
  Every frame in this project where `Esc` worked builds a table with a
  `tabOrder`; the Watch frame built none, and Watch was the only frame where
  `Esc` leaked to X4. Five frames, no exceptions. Mechanisms A and B were both
  real and both necessary; Mechanism C was the decisive third requirement that
  actually fixed the transparent full-screen Watch view.

  Practical trap: an **empty or zero-width table is rejected**. Helper logs
  `Frame content of type 'table' was not created successfully! Aborting display
  of frame!` and abandons the entire frame. The session still transitions and
  the camera still moves, so the phase looks correct in the log while nothing
  renders at all — readable as "the feature does nothing". The fix must be a
  table with real dimensions and real content. In this project the Watch view
  now carries a small top-right label showing the selected turret group and its
  operational/total count.

  Testing lesson: a stubbed test that only asserts "a table was created" passes
  for an invalid table. The suite stayed green while the feature was dead in
  game because stubs do not validate descriptors the way Helper does.

### Closing the Map re-opens DockedMenu while the player is seated
- X4: 9.00
- Status: live-tested
- Source: game session on 2026-08-04, extension `x4_gunnery_control`
  build marker `2026-08-04-lifecycle-1`, Windows 11, X4 9.00 Steam
- Live test: yes — reproduced on 2026-08-04 with the player in a control-post chair,
  closing Map with both `M` and `Esc`
- Finding: with the player in a control-post chair, closing the Map fires the UI
  Extensions `MapMenu` `on_menu_cleanup` callback and then, roughly 70 ms later, X4
  re-opens `DockedMenu`. A chair-ingress hook cannot distinguish this from the player
  actually sitting down, so a naive hook treats the suspended session as stale and
  destroys it. Map *suspension* itself works correctly; it is the resume path that is
  lost. Closing the Map with `M` or with `Esc` follows the same path.

### Generic 3D mouse scene picking is not established
- X4: 9.00
- Status: inference
- Source: `ui/core/lua/targetsystem.lua`
- Live test: no — untested as of 2026-08-03
- Finding: this is a scoped negative-search inference from the current
  target-system source: registered target-overlay brackets are click targets,
  but no generic arbitrary unbracketed scene-geometry ray-pick API was found in
  that scope. Use bracket selection plus an explicit object/surface picker
  unless broader evidence is found.

### Camera aim direction is not separable from camera anchor
- X4: 9.00
- Status: inference
- Source: full LuaJIT ffi.cdef index of `ui-9.00` (3123 unique declarations
  across 80 Lua files) via `scripts/index-lua-ffi.sh`;
  `ui/addons/ego_detailmonitor/menu_followcamera.lua`;
  `ui/core/lua/targetsystem.lua`; `schemas-9.00` MD/XSD; kuertee `helper.xpl`
- Live test: no — negative result, untested as of 2026-08-04
- Finding: scoped negative search. The camera setters are
  `SetPlayerCameraTargetView`, `SetPlayerCameraCockpitView`,
  `SetPlayerCameraCinematicView`, `SetSceneCameraActive`,
  `SetCockpitCameraScaleOption` and `SetFollowCameraBasePos`. Each takes a
  single component, a bool, a float or a position; none takes an orientation or
  a look-at component distinct from the anchor. `GetCameraRotation()` returns a
  `Rotation` but has no setter counterpart in the indexed surface; its only
  shipped call site reads `.roll` to counter-rotate HUD brackets. A UI
  extension therefore appears unable to hold camera position at a turret while
  re-aiming at that turret's target. Bounded by the files and build named
  above; it cannot exclude an undeclared engine function, but no vanilla menu
  and no cached third-party extension calls one.
- CORRECTION 2026-08-04: this record is scoped to the **UI Lua** camera surface
  and must not be read as "nothing in X4 can separate aim from position".
  Cutscene assets can, and do; see the cutscene records below. The earlier
  dismissal of cutscene cameras came from searching `schemas-9.00/md/md.xsd`,
  which is a 6-line include stub, instead of `libraries/common.xsd`.
- Limitations: do not pass the target component to `SetPlayerCameraTargetView`
  as a workaround. That relocates the camera to the target and breaks the
  fixed-at-turret behaviour. The achievable alternative is a HUD direction
  indicator built from `GetCameraRotation()` and `GetSofttarget2()`, which is
  the idiom `targetsystem.lua` already uses.

### SetPlayerCameraTargetView `force` is a permission override, not framing
- X4: 9.00
- Status: shipped-source
- Source: `ui/addons/ego_detailmonitor/menu_map.lua`;
  `ui/addons/ego_interactmenu/menu_interactmenu.lua`
- Live test: no — untested as of 2026-08-04
- Finding: both shipped call sites pass one component with `force = true`, and
  `force` mirrors the argument of the companion predicate
  `IsPlayerCameraTargetViewPossible(targetid, force)`. It governs whether the
  view may be entered, not what the camera looks at.

### Follow Camera adjusts position only, never orientation
- X4: 9.00
- Status: shipped-source
- Source: `ui/addons/ego_detailmonitor/menu_followcamera.lua`
- Live test: no — untested as of 2026-08-04
- Finding: the shipped Follow Camera menu exposes three sliders, `pos_x`,
  `pos_y` and `pos_z`, scaled by the external view ref object's size, and
  commits them through `SetFollowCameraBasePos` using a `Coord3D` with no
  rotation member. The engine retains control of facing. This is the closest
  shipped analogue of a mod-adjustable camera and confirms that offset is
  exposed while orientation is not.

### Cutscene cameras DO separate position from look direction, and track live
- X4: 9.00
- Status: shipped-source
- Source: `cutscenes/lookat_anchor_keyframed_shot.xml`;
  `cutscenes/follow_a_lookat_b.xml`; `cutscenes/cutscenes.xsd`;
  `schemas-9.00/libraries/common.xsd`
- Live test: no — untested as of 2026-08-04
- Finding: cutscene assets declare `<position>` and `<lookdirection>`
  independently, each with its own reference object and x/y/z offsets supplied
  as runtime params. `cutscenes.xsd` documents `<reference object=>` as
  returning the object's position "at the time at which the value source is
  queried", i.e. continuous per-frame tracking, not a start-time snapshot.
  This is the only shipped mechanism where camera aim is genuinely separable
  from camera position. Lead supplied by kuertee via the X4 modding Discord and
  then corroborated against shipped assets.
- Limitations: `cutscene_event` carries only `key` and an `event` string, with
  no object, number or coordinate, so a running shot cannot be re-aimed without
  a stop and restart. All 15 shipped Lua `StartCutscene` calls pass a render
  target and all 15 descriptor param tables pass object references only, never
  numbers.
- CORRECTION 2026-08-04 (live-tested): the "not usable for a playable gunnery
  view" conclusion in this record was WRONG. It was inferred from Live Stream
  View (action 353, F6) being the only shipped main-view use — a letterboxed
  spectator mode with no weapon bindings. A live test proved that a custom MD
  `<play_cutscene cinematicmode="true">` from a plain extension cue renders on
  the main player camera and **the player's turret keeps firing** while the
  cinematic is active. See "Custom MD play_cutscene is a playable main-view
  camera" below. The re-aim-requires-restart limitation still stands.

### Follow camera cannot be parked on a turret: no ship-local component offset
- X4: 9.00
- Status: inference
- Scope: negative search over the full ui-9.00 FFI index
- Source: `ui/addons/ego_detailmonitor/menu_followcamera.lua`;
  `ui/core/lua/targetsystem.lua`; full FFI index of ui-9.00 (1914 unique names)
- Live test: no — negative result, untested as of 2026-08-04
- Finding: `SetFollowCameraBasePos` takes absolute engine units relative to
  `GetExternalViewRefObject()`'s centre; the `size` factor in
  `menu_followcamera.lua` only maps slider percentages. Aiming it at a turret
  needs that turret's ship-local offset, and no such getter was found. All nine
  `Coord3D`-returning functions are station build-plot geometry or the camera's
  own position. `GetComponentOffset` is camera-relative world space for 3D HUD
  markers; `GetPositionalOffset` operates on regions, sectors and clusters;
  `GetCompSlotControlPosition` returns a name string. Additionally
  `menu.onCloseElement` calls `ResetFollowCameraBasePos()` on every close path,
  and `SetThirdPersonFlightOption` is hidden in 9.00 with the shipped comment
  "not being used for the moment".
- SCOPE CORRECTION 2026-08-04: this blocks only the follow-camera route, which
  is redundant. `SetPlayerCameraTargetView(turretComponentID)` already parks the
  camera on an arbitrary turret and is confirmed working across every turret
  tested on two ships. The engine clearly resolves the turret's position itself;
  what is missing is only a Lua getter for that coordinate, which is needed
  solely to reproduce the placement by a second mechanism. Do not cite this
  record as evidence that a fixed turret camera is unavailable.
- Limitations: bounded by ui-9.00 and kuertee-ui-extensions-all; cannot exclude
  an undeclared engine function. The open question that actually matters is
  whether look input is available *within* the existing external target view,
  not how to place the camera.

### playerCameraModeChanged is an extension-consumable camera event
- X4: 9.00
- Status: shipped-source
- Source: `ui/addons/ego_detailmonitor/menu_followcamera.lua`
- Live test: no — untested as of 2026-08-04
- Finding: `RegisterEvent("playerCameraModeChanged", handler)` fires on camera
  mode change. Unlike `externalTargetViewActive` and `gameplanchange`, which are
  UI-contract events with no Lua producer, this uses the same `RegisterEvent`
  channel this project already consumes for `playerGetUp` and `playerUndock`.
  Candidate replacement for polling `GetExternalTargetViewComponent` when
  detecting camera teardown.

### Standard View (F1) is the only shipped exit from an external target view
- X4: 9.00
- Status: shipped-source
- Source: `ui/addons/ego_detailmonitor/menu_map.lua`;
  `libraries/inputmap.xml`; game text 1001,5326 and 1026,2605
- Live test: no — untested as of 2026-08-04
- Finding: `SetPlayerCameraCockpitView(true)` under the F1 handler is the single
  shipped exit. Neither shipped `SetPlayerCameraTargetView` call site releases
  the view, and the interact menu activates the camera then immediately closes
  its own menu, so menu teardown demonstrably does not release it. No
  clear/reset/disable counterpart exists in the FFI index and no shipped site
  passes 0 as the target. Vanilla never combines an external target view with
  leaving a seat: both entry points gate on the player being a pilot, so there
  is always a cockpit to return to. Whether
  `SetPlayerCameraCockpitView(true)` succeeds while on foot is an engine
  decision not determinable from Lua and needs a live test.

### The engine exports far more than vanilla Lua declares
- X4: 9.00
- Status: shipped-source
- Scope: X4.exe binary export table
- Source: PE export table of `X4.exe` via `objdump -p`, diffed against every
  `C.<name>` call site in `ui-9.00`
- Live test: no — untested as of 2026-08-04
- Finding: `X4.exe` exports **2493** named symbols. Vanilla UI Lua calls
  **1885** of them, leaving **609 exported functions that no shipped UI Lua
  file ever calls**. `ffi.cdef` only *declares* what the binary already
  exports, so an extension may declare and call any of these. Every previous
  "no such function exists" conclusion in this knowledge base was derived from
  what vanilla *declares*, not from what the engine *exposes*, and must be read
  with that scope.
- Notable undeclared camera exports, absent from vanilla and from
  kuertee-ui-extensions-all alike: `SetPlayerCameraExternalView` and
  `SetPlayerCameraFloatingView`. Also undeclared and relevant to this project:
  `IsPointingWithinAimingRange`, `GetWeaponDetails2`, `SetTurretGroupMode`,
  `GetSofttarget`.
- Limitations: the export table gives **names only, not signatures**. Calling a
  declared function with a wrong signature through FFI can corrupt the stack or
  crash the game. Infer a signature from a sibling that vanilla does declare
  (for example `SetPlayerCameraCockpitView(bool force)` and
  `SetPlayerCameraTargetView(UniverseID, bool)`) and test in a disposable save.
- Reproduce: `objdump -p X4.exe`, take the `[Ordinal/Name Pointer] Table`
  section. Lists are cached under the ignored
  `.x4-research-cache/exports/`; do not commit them.

### SetPlayerCameraExternalView is callable and is the standard external ship view
- X4: 9.00
- Status: live-tested
- Source: undeclared PE export of `X4.exe`; declared with inferred signature
  `void SetPlayerCameraExternalView(bool force)` and called in-game 2026-08-04
- Live test: yes — called from the compact Engage panel; `ok=true, err=nil`, no
  crash, so the `bool` signature is correct
- Finding: the call switched the camera from the external **target** view on the
  turret (`camera` was the turret component) to X4's standard external ship
  camera (`camera` became the player ship). Free look (Shift + middle mouse)
  worked afterward, but the viewpoint was centred on the ship and zoomed out,
  not on the turret. So this function is the ordinary third-person ship camera,
  not a way to free-look from a fixed turret position. Confirms the signature-
  guessing method works: infer from a declared sibling, wrap in pcall, test on a
  disposable save.

### Free look is suppressed in Engage by the enemy soft target, not the camera
- X4: 9.00
- Status: inference
- Corroboration: shipped-source paths and a partial live observation
- Source: `ui/gunnery_control.lua` `startWatch` vs `engageTarget`;
  `ui/core/lua/crosshair handling.lua` (`IsExternalTargetMode`)
- Live test: partial — Watch (no enemy soft target) has working mouse look;
  Engage (enemy set via `SetSofttarget`) does not; both use the same
  `SetPlayerCameraTargetView(turret)` call
- Finding: the only camera-relevant difference between Watch and Engage is that
  `engageTarget` sets the enemy as the soft target. With a soft target active
  the game enters external target mode (which `crosshair handling.lua` gates on)
  and mouse look is suppressed, while the camera still frames the turret rather
  than tracking the target. The same soft target also directs the turret AI, so
  whether free look and target-directed fire can coexist is the open question.
  Untested: whether clearing the soft target restores free look while the turret
  stays armed.

### SetPlayerCameraTargetView frames and follows any component, including an enemy
- X4: 9.00
- Status: live-tested
- Source: `ui/gunnery_control.lua` (Engage POV toggle); called in-game 2026-08-04
- Live test: yes — `SetPlayerCameraTargetView(softTargetID, true)` from the
  Engage panel moved the camera onto the turret's target; the engine framed and
  followed the enemy, and Shift + middle-mouse free look still worked
- Finding: the function positions the camera at whatever component it is given
  and the engine keeps that component framed as it moves. Passing the firing
  turret gives "Turret POV"; passing the current soft target gives "Target POV"
  that auto-follows the enemy. This is now a shipped feature. Both POVs allow
  manual free look. What it does NOT do is hold the camera at component A while
  aiming continuously at component B: the framed component is also the camera
  anchor. Separating those is the open goal in
  `docs/goals/engage-camera-aim.md`.
- Correction to the earlier "do not pass the target to SetPlayerCameraTargetView"
  limitation: passing the target is exactly how Target POV works and is a valid,
  desirable behaviour. The earlier note assumed the user only ever wanted the
  turret vantage; that assumption was wrong.

## Cutscene cameras from extension MD (live-tested 2026-08-04)

### Custom MD play_cutscene is a playable main-view camera
- X4: 9.00
- Status: live-tested
- Source: game session on 2026-08-04, extension `x4_gunnery_control`,
  `md/x4_gunnery_control.xml` `CutsceneAim` cue, Windows 11, X4 9.00 Steam
- Live test: yes — confirmed in both POVs (camera at turret and camera at
  target) on 2026-08-04
- Finding: a plain extension MD cue calling
  `<play_cutscene cinematicmode="true" key="'Follow_A_Lookat_B'">` renders the
  cutscene on the MAIN player camera — no render target, no mission, no
  vanilla cutscene manager involvement needed. Decisively: **the player's
  turret keeps firing while the cinematic is active** (confirmed in both
  POVs), so a cutscene camera IS usable as a live gunnery view. `Esc` exits
  the cinematic cleanly back to the previous camera state. The game UI —
  including this extension's own Helper-frame menu and buttons — is hidden
  while the cinematic runs, so an on-screen Stop button is unreachable
  mid-scene; `Esc` is the working exit. This supersedes the earlier
  "letterboxed spectator only / not usable for playable gunnery" scoped
  negative (see the CORRECTION on "Cutscene cameras DO separate position from
  look direction" above).

### A turret surface element is a valid cutscene anchor object
- X4: 9.00
- Status: live-tested
- Source: game session on 2026-08-04, extension `x4_gunnery_control`,
  `md/x4_gunnery_control.xml` `CutsceneAim` cue, Windows 11, X4 9.00 Steam
- Live test: yes — camera observed positioned at the turret on 2026-08-04
- Finding: passing a turret (surface element) component as the
  `Follow_A_Lookat_B` `anchor` param works; the camera is positioned at the
  turret. Cutscene params are not limited to top-level objects like ships and
  stations.

### Lua→MD AddUITriggeredEvent transport contract
- X4: 9.00
- Status: live-tested
- Source: three live rounds on 2026-08-04, extension `x4_gunnery_control`
  (`ui/gunnery_control.lua` `sendCutsceneAimStart` →
  `md/x4_gunnery_control.xml` `CutsceneAim.Start`), Windows 11, X4 9.00 Steam;
  value-conversion pattern from
  `ui/addons/ego_detailmonitor/menu_ship_configuration.lua:1399`
- Live test: yes — each rule below was isolated by a separate in-game round
  with the raw `event.param3` table dumped via `debug_text`
- Finding: the engine PREPENDS `$` to every Lua string key during Lua→MD
  conversion. Lua `{ anchor = v }` arrives in MD as the variable key
  `$anchor`, readable as `event.param3.$anchor`. Pre-prefixing `$` in Lua
  (`["$anchor"]`) yields the invalid variable name `$$anchor`, stuck as an
  unreadable string key — never do it. Raw ffi uint64 component ids arrive
  null-ish/unusable; convert them with `ConvertStringToLuaID(tostring(id))`
  (the vanilla pattern), which arrives in MD as a real component object —
  no `component.{}` lookup needed on the MD side.

### anchordist=0 clips the camera inside the anchor; use the vanilla negative-distance idiom
- X4: 9.00
- Status: live-tested
- Source: game session on 2026-08-04, extension `x4_gunnery_control`;
  vanilla idiom in `md/cinematiccamera.xml:2504`
- Live test: yes — anchordist=0 observed clipping through anchor geometry with
  the object filling the whole frame, both POVs, on 2026-08-04
- Finding: `Follow_A_Lookat_B` with `anchordist=0` places the camera INSIDE
  the anchor's hull: the view clips through geometry and the object fills the
  frame. The vanilla framing idiom is a NEGATIVE distance derived from the
  anchor's size — `<set_value name="$Distance" min="$Anchor.size + 50m"
  max="$Anchor.size + 200m"/>` then `<param name="anchordist"
  number="-$Distance"/>` — which places the camera behind the anchor along
  the anchor→target axis with the anchor fully in frame and the target in
  view beyond it.

## Turret targeting — what a turret is shooting at

### No turret-target getter exists in the public FFI surface or in the undeclared engine exports examined so far

- X4: 9.00
- Status: inference
- Corroboration: negative searches of shipped public declarations, the binary
  export table, and MD script properties
- Source: full LuaJIT ffi.cdef index of `ui-9.00` (3123 unique declarations
  across 80 Lua files) via `scripts/index-lua-ffi.sh`; PE export table of
  `X4.exe` via `objdump -p` (2493 named symbols; 609 not called by any shipped
  Lua file), cached under `.x4-research-cache/exports/`; `schemas-9.00/md/md.xsd`
  and `schemas-9.00/libraries/common.xsd` (MD script properties and actions)
- Live test: no — negative-search result as of 2026-08-05
- Finding: no function that returns what a specific turret is currently
  targeting was found in any of the three sources examined:
  1. The full declared Lua FFI surface for ui-9.00 contains no getter whose
     name plausibly refers to a current turret target or attack target.
  2. The 609 undeclared engine exports (names that `X4.exe` exports but that
     no shipped Lua file ever declares) were inspected by name. None is
     recognisably a per-turret current-target getter.
  3. The Mission Director `$attacktarget` variable is an AI-script blackboard
     variable, not a component property readable by UI Lua. It is not accessible
     from Lua through any known mechanism.
- Consequence: the cinematic camera's aim point cannot be read from the turret.
  The current implementation picks it via `readTargetCandidates()` (enemy →
  nearest hostile → nearest operational), holds it while the chosen target is
  alive, and re-picks on death or loss of radar contact. This matches the turret's
  own selection in the common case but can disagree if the turret is ordered or
  scripted to fire on something outside the normal priority order.
- Upgrade path: a targeted search of the 609 undeclared exports for any function
  that takes a turret `UniverseID` and returns another component might yield a
  getter. Infer the signature from declared siblings and test in a disposable
  save using `pcall` (the established safe-call pattern for undeclared exports).
- Limitations: this result is bounded by the ui-9.00 build and the export-table
  snapshot cached in `.x4-research-cache/exports/`. It cannot exclude a function
  that exists under a non-obvious name.

## Turret upgrade groups — mapping a turret slot to its group

### A turret slot cannot be attributed to a group, and on a ship it never needs to be

- X4: 9.00
- Status: inference
- Corroboration: a 2026-08-07 Boron L destroyer live probe plus shipped FFI
  declarations, vanilla callers, and ship macros
- Source: live probe logged as `[X4GC PROBE]` on
  `ship_bor_l_destroyer_01_a_macro` (14 turret slots, 9 groups);
  1924 unique FFI declarations across `ui-9.00`;
  `ui/addons/ego_interactmenu/menu_interactmenu.lua` `areTurretsArmed()`;
  `ui/addons/ego_detailmonitor/menu_docked.lua`;
  `libraries/scriptproperties.xml` (extracted to
  `.x4-research-cache/extracted/props-9.00`);
  126 stock ship macros in `.x4-research-cache/extracted/ships-9.00`
- Live test: yes — 2026-08-07, X4 9.00, Boron L destroyer
- Finding: `GetUpgradeSlotGroup` returns `{path, group}` with **no context ID**,
  and `GetUpgradeGroupInfo2` returns a single representative component rather
  than a member list. There is no `GetUpgradeSlotGroup2`. So when two groups
  share `path`+`group`, the turrets between them cannot be attributed. Four
  candidate resolutions were tested live and all failed or were useless:
  1. `GetComponentData(turret, "grouptag")` → `nil` on all 14 turrets. The
     `grouptag` property exists on the `component` datatype in
     `scriptproperties.xml` ("Parent group tag") but is not populated for
     turrets.
  2. `GetComponentData(turret, "parent")` and `"container"` → both return the
     ship. `"defensible"` → `nil`.
  3. `GetParentComponent(turret)` → returns the ship for every turret. The
     function is declared in `menu_map.lua` but called by no shipped Lua file;
     it works, it just cannot disambiguate.
  4. `GetNumUpgradeSlots(contextID, ...)` → untested in effect, because every
     context on the probed ship *was* the ship.
- Consequence: the case does not arise on a ship. `GetUpgradeGroups2` keys
  groups by `contextid`+`path`+`group`, so two entries sharing `path`+`group`
  must differ in `contextid` — otherwise they are the same group. Every group on
  the probed ship reported `contextid == ship`, and all 53 `<turrets>`
  declarations across the 126 stock ship macros use `path=".."` with unique
  group names. Vanilla's `entry.context == menu.object -- mainship` check in
  `menu_ship_configuration.lua` implies contexts only diverge for stations with
  modules. Treat `#candidates > 1` on a ship as unreachable defensive code.
- Vanilla does not attempt this mapping at all: `areTurretsArmed()` and
  `menu_docked.lua` walk turret slots **only** for ungrouped turrets
  (`path == ".."` and empty group) and drive grouped turrets purely through
  `contextid`+`path`+`group`. Any per-turret member list for a group is a
  mod-only construct.
- Upgrade path, if a modded ship ever produces duplicate group names: on the
  probed ship the representative component was always the group's **first slot
  in scan order** (`group_front_up_left` rep=445809 → slot 2 of 2,3;
  `group_rear_down_mid` rep=445808 → slot 13 of 13,14; and so on for all 9
  groups). Combined with `GetUpgradeGroupInfo2().total`, that partitions slots
  exactly: on hitting a representative, claim the next `total` slots for it.
  Ceiling: one ship of evidence for an undocumented ordering guarantee. Confirm
  on several hulls before relying on it.

### 15 shipped ships have two turret groups that humanize to the same label

- X4: 9.00
- Status: inference
- Corroboration: shipped-source group identifiers replayed through this
  project's `State.turretGroupLabel()`
- Source: `assets/units/size_l/ship_*.xml` and `assets/units/size_xl/ship_*.xml`
  across base game and all seven DLC catalogs, extracted to
  `.x4-research-cache/extracted/ships-comp-base-9.00`,
  `ships-comp-dlc-9.00`, `dlc-{terran,split,boron,pirate}-comp-xl-9.00`,
  `dlc-timelines-comp-9.00`, `dlc-mini0{1,2}-comp-9.00`; 135 component files
- Live test: partial — the label output is confirmed by an in-game screenshot
  (`release/main_menu.png`, Boron hull, 2026-08-07); the collision list itself
  is source-derived and untested in game as of 2026-08-07
- Finding: distinct raw group identifiers on one hull can humanize to one
  string, because the labeller drops information three ways: token order is
  discarded (slots are emitted depth, center, vertical, lateral, radial
  regardless of input order); a standalone numeric tail such as `_01` matches no
  direction word and vanishes; and a repeated direction word is ignored once its
  slot is filled. So `group_mid_up_rear` and `group_rear_up_mid` both give
  "Rear Center Upper" (Phoenix E), and `group_mid_mid_top_01/_02/_03` all give
  "Center Upper" (Raptor, a three-way collision).
- Affected hulls: base game Phoenix E (`ship_tel_l_destroyer_02`), Obliterator,
  Zeus Vanguard, Zeus E; Terran Syn, Osaka, Asgard; Split Rattlesnake, Wyvern
  Mineral, Python, Raptor; Boron Walrus, Shark; Timelines Xenon Mothership
  (`ship_xen_xl_mothership_01` and `_01_a`). Boron and Pirate L hulls and both
  Compact DLC packs are clean. All seven DLCs were present in this installation
  and checked.
- Consequence: none for correctness, and this is **not** the `#candidates > 1`
  ambiguity recorded above. Members are attributed by the raw `path`+`group`
  string, which still differs, so each group keeps its own turrets; commands
  address `contextID`+`path`+`group` and stay exact. Only the rendered name
  collides, and a de-duplicating counter that appends ` · 2`, ` · 3` keeps the
  console readable. Do not treat a shared label as a shared group.
- Reproduce: `grep -ao 'group="[^"]*"'` over the component XMLs, strip the
  padding (see the record below), then run each distinct identifier through
  `State.turretGroupLabel()` and count collisions per hull.

### Group identifiers in ship component XML carry surrounding whitespace

- X4: 9.00
- Status: inference
- Corroboration: shipped-source proves padding; runtime trimming is inferred
- Source: `.x4-research-cache/extracted/ships-comp-dlc-9.00/assets/units/size_l/
  ship_bor_l_destroyer_01.xml`, which contains `group="group_front_up_left "`,
  `group=" group_front_up_mid "`, `group="  group_front_down_mid "` and even
  `group="  "`; the same padding appears across the base-game hulls
- Live test: partial — `release/main_menu.png` (2026-08-07) shows this project's
  console rendering "Front Upper Left", "Center Lower Left" and "Front Center
  Lower" on a Boron hull
- Finding: the `group=` attribute on turret connections is not a clean token. It
  frequently carries leading and trailing spaces, inconsistently between
  connections that name the same group, and at least one connection carries a
  whitespace-only value. The runtime evidently hands back a trimmed identifier:
  this project never trims (`ffi.string` straight out of the
  `GetUpgradeGroups2` buffer), and an untrimmed value would break the labeller
  in two visible ways. A trailing space makes the final token fail the
  `^(%a+)(%d*)$` match, dropping the last direction word ("Front Upper" instead
  of "Front Upper Left"); a leading space makes the whole identifier fail the
  `^group_` guard, falling back to the generic "Turret N" name. The screenshot
  shows neither, on a hull whose XML has both kinds of padding.
- Consequence: treat the runtime identifier as trimmed but never assume it of
  the file. Any tool that reads the XML directly must strip the value first, or
  it will count `group_x ` and ` group_x ` as two groups.
- Do NOT trim at the `str()`/FFI boundary. The same string is handed straight
  back to the engine (`SetTurretGroupMode2`, `SetTurretGroupArmed`,
  `GetTurretGroupMode2`, `IsTurretGroupArmed`) and is persisted into the MD save
  record. If the engine's own table is keyed by the padded form, a trimmed write
  misses silently and the turrets never move. Trim only what stays internal:
  this project trims in `State.turretGroupLabel()` (display) and when building
  and looking up the turret-slot-to-group candidate key (which spans two
  separate APIs, `GetUpgradeGroups2` and `GetUpgradeSlotGroup`, so inconsistent
  padding between them would break attribution). Engine-facing and persisted
  values stay byte-exact.
- Open question, self-diagnosing: `readGroups()` logs
  `raw group id carries padding: "..."` at most once per session when a returned
  path or group differs from its trimmed form. Zero lines means the engine
  trims and this record's inference is confirmed. Check a session log to settle
  it.

## Engine bug: SetPlayerCameraTargetView leaves Esc dead after get-up

### Trigger and symptom

- X4: 9.00
- Status: live-tested
- Source: game sessions on 2026-08-06, extension `x4_gunnery_control`
  build markers `2026-08-06-viewcycle-20` / `2026-08-06-notify-21`,
  Windows 11, X4 9.00 Steam; debug log archived at `debug with trial 2.log`
- Live test: yes — reproduced and cured on 2026-08-06 across three trials
- Finding: calling `C.SetPlayerCameraTargetView(turretComponentID, true)` while
  the player is seated in a gunnery chair leaves the game's `Esc` key dead after
  the player stands up. Esc no longer opens the game menu; the game must be
  relaunched or an unrelated menu event must occur to restore it.

### What does NOT cure it

All of the following were tested and confirmed **not** to cure the dead Esc:

- `C.SetPlayerCameraCockpitView(true)` called before `C.GetUp()` — the bug
  persists regardless of whether the camera is restored to cockpit before the
  player stands.
- The player actually getting up — the symptom survives the full get-up
  transition.
- Turret mode mutation (changing armed state or mode) — no effect on the Esc
  state.
- Using an `element` frame (a separate Helper frame on a different layer) —
  frame layer choice is irrelevant.
- Setting `softtarget` — no effect.
- Transitioning through the `engaged` phase specifically.
- Calling `C.ActivatePlayerControls()` — not exposed; not a known cure.
- `C.ClearTrackedMenus()` — not exposed; not tested.

### The bug is invisible to every readable engine flag

After the player stands up, the following flags were sampled and are
**byte-identical** whether Esc is working or broken:

- `GetPlayerViewMode()` / view flags
- `IsFullscreenMenuOpen()` / fsmenu
- `GetSofttarget2()` / softtarget
- HUD flags
- Cutscene / cinematic mode flag
- `GetExternalTargetViewComponent()` / external view
- `IsConversationActive()`
- `IsEncryptedDirectInputModeActive()`
- `GetPlayerControlsActive()` / player controls

Because no readable flag distinguishes the broken state, the bug can only be
diagnosed behaviorally (observe whether Esc opens the game menu after standing
up from a camera session). Do not attempt to detect or gate the workaround on
any flag value.

### The only observed cures

All three of the following independently cured the dead Esc:

1. A vanilla helptext popup from an unrelated mod (observed to cure it first,
   providing the clue).
2. `MapMenu` opening.
3. `OptionsMenu` opening.

The common thread: all three invoke `View.createView()` in
`ego_viewhelper/viewhelper.lua:38`, which calls `CreateView()` + `DisplayView()`
— but only when `View.frames` is empty. The extension's normal teardown path
calls `View.hideView()` → `HideView()`, which never creates again.

### How the cure was isolated (three-arm A/B/C trial)

The three in-game trials ran as a controlled A/B/C comparison:

- **Arm A (negative control)**: session with NO `SetPlayerCameraTargetView`
  call — no dead Esc. Confirmed the Esc bug is specific to that call.
- **Arm B (the bug)**: session WITH `SetPlayerCameraTargetView`, no workaround
  — dead Esc confirmed after get-up.
- **Arm C (the cure)**: session WITH `SetPlayerCameraTargetView` plus the Notify
  popup on exit — Esc working after get-up confirmed.

A `post-exit sample` recorder was used, timestamping when `extmenu=OptionsMenu`
first appeared (the moment Esc would open the game menu if working), to
distinguish "Esc works" from "Esc is dead" without restarting the game each
trial.

### The fix and its ceiling

The `Notify` MD cue (`md/x4_gunnery_control.xml`) listens for the
`X4GunneryControl/notify` event emitted by `discardSession` in
`ui/gunnery_control.lua` (guarded by `seatLeaving = true`) and runs
`<show_help custom="..." .../>`. The `show_help` action triggers
`View.createView/DisplayView`, which resets the engine's input context.

**Ordering fragility.** `View.registerMenu` only reaches `View.createView()`
when `View.frames` is empty; otherwise it takes the `updateMenu` path
(`viewhelper.lua:110-166`), which does *not* cure the bug. Our own frame is
still registered when the notify is emitted — `leaveChair` defers
`Helper.closeMenu` by 0.05 s — and the cure works only because MD handles the
UI-triggered event a tick later, after that teardown. Do not "tidy" the notify
to fire earlier, and do not make the frame teardown synchronous, without
re-running the live Esc check. There is no unit test that can catch this; the
Lua tests stub the view layer.

The emission lives in `discardSession` rather than `leaveChair` because there
are two seat-exit routes that both converge there:

1. **`leaveChair`** — our Get Up button; sets `seatLeaving = true` before
   calling `discardSession`.
2. **`endForMovement`** — registered on `playerGetUp` and `playerUndock`;
   also sets `seatLeaving = true` before calling `endSession → discardSession`.

A third path — the `gameplanchange` handler's "stale session before chair
redirect" call — reaches `discardSession` without setting `seatLeaving`, so
it stays silent (the player just sat down; a popup would be wrong).

The fix is LIVE-VERIFIED working in game: three in-game trials on 2026-08-06
confirmed Esc is restored after the popup appears on every exit route tested
(Get Up button). The `playerGetUp`/`playerUndock` coverage was added in the
same commit that moved the emission to `discardSession`; those routes were
not individually live-tested but share the same discardSession code path.

Known ceiling: if the player has hints/help texts disabled in game options the
popup may not display and the Esc bug would return.

Fallback that was removed: commit `2f8691d` implemented an invisible 1×1
offscreen throwaway frame on a dedicated layer (`viewCycleLayer = 2`) as an
earlier workaround. That was replaced by the popup in commit `5b6738b` because
the popup is a real user-facing feature and uses the identical cure mechanism.
The throwaway approach is documented here as a fallback if the show_help route
ever stops working.

Upgrade path: if a direct engine call to reset the input context is ever found
among the 609 undeclared engine exports (see "The engine exports far more than
vanilla Lua declares" above), it could replace this workaround entirely and
would not depend on hint settings. Any candidate must be tested in a disposable
save using `pcall`.

## Reloading UI Lua without restarting X4 (live-tested 2026-08-08)

### ScheduleReloadUI exists in the menus environment and re-reads loose files from disk
- X4: 9.00
- Status: live-tested
- Source: live session on 2026-08-08, extensions `x4_gunnery_control` and
  `x4_gunnery_control_testlab`, X4 9.00 Steam, Windows 11; game debug.log
- Live test: yes — four reloads triggered from a Test Lab button during one session on
  2026-08-08, each confirmed against the log
- Finding: `ScheduleReloadUI` was present as a global in the menus environment
  (logged `fn_present=true`) and calling it with no arguments reloaded the extension's
  UI Lua without restarting the game.

  Timing observed: the reload log line and the extension's own init line were 0.01 in-game
  seconds apart.

  It re-reads loose files from disk. A build-marker string was edited in the repository and
  copied into the game's `extensions/` directory while X4 was running; the next reload
  logged the new marker. No restart, no save reload.

  The player was seated in a gunnery chair for every reload. Behaviour when not seated, and
  the effect on `md/`, `t/`, `ui.xml`, or `content.xml`, were not tested.

### A UI reload does not preserve Lua globals
- X4: 9.00
- Status: live-tested
- Source: live session on 2026-08-08, extension `x4_gunnery_control`, X4 9.00 Steam,
  Windows 11; game debug.log
- Live test: yes — a counter global incremented at init and logged across two consecutive
  reloads on 2026-08-08
- Finding: a global set to `(X or 0) + 1` at init logged `1` on every reload, never `2` or
  `3`. The global did not carry across.

  Measured alongside it: `#Menus` was 35 after each reload, not growing. The vanilla menu
  table is rebuilt rather than appended to, and the extension's own entry did not accumulate
  a duplicate.

  Also observed across four inits in the session: each init logged exactly one of each of
  the extension's two hook registrations, four in total, with no doubling.

  Consequence measured in this extension: its session table is a file-local, and after each
  reload it logged `session created from chair ingress` — a new session, not a resumed one.
  Any in-memory UI state is therefore lost on reload.

  Not established by this test: whether any category of global is exempt. Vanilla stores
  cross-menu UI state in globals named `__CORE_*` (for example
  `__CORE_DETAILMONITOR_MAPFILTER_SAVE`), and no engine registration or persistence hook for
  that prefix was found in `ui/core`. Whether those survive a reload was not measured.

### Vanilla carries a delimited string through raise_lua_event and parses it in Lua
- X4: 9.00
- Status: shipped-source
- Source: `scripts-9.00/md/scenario_advanced.xml:414` raises
  `<raise_lua_event name="'mapfilter'" param="'layer_trade;false'"/>`;
  `ui-9.00/ui/addons/ego_detailmonitor/menu_map.lua:1942` registers the handler and
  `:4031-4032` parses it with `string.match(params, "(.+);(.+)")`
- Live test: no — read from shipped source on 2026-08-08, not exercised
- Finding: the MD-to-Lua direction carries a string, and vanilla packs two values into one
  by delimiting them and splitting the result in Lua.

  This bounds the repository's earlier note that a table sent through
  `raise_lua_event` arrives as `nil`. That note lived at `ui/gunnery_control.lua:1927-1938`
  until the string transport replaced it; the surviving summary is now the comment on
  `persistSession()`. That live-tested result is about tables. It does not
  establish that the channel is unusable, and the shipped delimited-string pattern above is
  the vanilla way to move more than one value through it.

  The string leg was live-tested the same day; see the next record. The separate defect noted
  at that code location — component IDs are reassigned on save/load — is unaffected by
  transport and would still apply.

### A string survives a UI reload by way of an MD cue variable
- X4: 9.00
- Status: live-tested
- Source: live session on 2026-08-08, extension `x4_gunnery_control`, X4 9.00 Steam,
  Windows 11; game debug.log
- Live test: yes — a marker string stored from Lua, then fetched back after a reload, on
  2026-08-08
- Finding: Lua sent a unique marker to MD, which stored it in a cue variable. After a
  `ScheduleReloadUI` wiped every Lua global, the reloaded file asked MD for the value before
  storing a new one, and the marker written by the PREVIOUS life of the file came back as
  `type=string`.

  Measured sequence: `probe_store sending: probe-14`, then after the next reload
  `probe_fetch: raising State.$probe=probe-14` and
  `probe_restore: type=string; value=probe-14`.

  The store leg used the Lua-to-MD table transport recorded above, carrying one string key,
  so the only untested step was the return. The return used `raise_lua_event` with the cue
  variable as `param`.

  An MD cue variable is therefore the only storage measured in this session that outlives a
  UI reload. Lua globals do not.

  Also measured: MD logged its receipt roughly 0.6 to 0.7 in-game seconds after the Lua send,
  so delivery crosses a tick and is not synchronous.

  Not established by this test: any length limit on the payload, and whether the same value
  survives save/load rather than only a reload.

### A whole UI session round-trips through MD as one delimited string
- X4: 9.00
- Status: live-tested
- Source: live session on 2026-08-08, extension `x4_gunnery_control` build
  `2026-08-08-session-persist-2`, X4 9.00 Steam, Windows 11; game debug.log
- Live test: yes — an engaged turret session reloaded and resumed, on 2026-08-08
- Finding: the single-string transport scales past a marker to a real payload. A session of
  11 scalar fields plus 4 turret-group snapshots plus 4 checked-group entries was encoded as
  one delimited string, stored in an MD cue variable, raised back after `ScheduleReloadUI`,
  and decoded into a working session. Lua logged `payload type=string` and
  `restored=true phase=engaged groups=8 snapshots=4`, and the player kept the turret camera,
  the checked groups and the engaged target across the reload.

  The same run reproduced the table failure it replaces. On the immediately preceding build
  MD logged a fully populated `State.$active` while Lua logged `payload type=nil` on the same
  tick, which is the third such reproduction after 2026-08-06 and earlier on 2026-08-08.

  MD needed no knowledge of the format. The cue stores `event.param3` and raises it back
  verbatim, so encoding stayed entirely on the Lua side.

  Per-group values survived intact, including a non-default `mining` mode on one group, so
  the round trip is not flattening values to a default.

  Not established by this test: any length limit. This payload was roughly 700 characters and
  no truncation was observed, but no boundary was probed. Also not established: whether the
  string survives an actual save/load as opposed to the UI reload measured here. The
  separately recorded defect that component IDs are reassigned on load was not exercised.

### The engine soft target reads 0 after a UI reload
- X4: 9.00
- Status: live-tested
- Source: live session on 2026-08-08, extension `x4_gunnery_control` build
  `2026-08-08-testlab-anyphase-probe-2`, X4 9.00 Steam, Windows 11; game debug.log
- Live test: yes — a probe logging `GetSofttarget2()` at menu-file init, on 2026-08-08
- Finding: with a target engaged, the mod having called `SetSofttarget` on it and the turrets
  firing at it, a `ScheduleReloadUI` was taken. The reloaded file logged
  `PROBE softtarget id=0ULL connection= name=<none>` at init. The soft target was not
  readable after the reload, so a UI that needs its target back must carry it in its own
  payload rather than re-reading it from the engine.

  Not established by this test: which action cleared it. Reaching the reload button required
  opening another menu, and the player was in that menu for several seconds before clicking,
  so the reload, the intervening menu, and the closing of the mod's own menu are not
  separated. Only the end state was measured.

  Measured alongside: the external target view camera was NOT cleared. The engine still
  reported the turret component from `GetExternalTargetViewComponent()` after the reload
  while Lua state was gone, so the camera and the soft target did not behave the same way.

### A Lua error during a menu file's init removes the mod from the UI until restart
- X4: 9.00
- Status: live-tested
- Source: live session on 2026-08-08, extension `x4_gunnery_control` build
  `2026-08-08-testlab-anyphase-probe-1`, X4 9.00 Steam, Windows 11; game debug.log
- Live test: yes — an accidental FFI field-name typo, on 2026-08-08
- Finding: a menu file's top-level `init()` read a struct field that did not exist on the
  cdef'd type, `connectionname` instead of `softtargetConnectionName` on
  `SofttargetDetails2`. The error aborted `init()` after its first log line. Everything after
  that point never ran: the `Menus` insertion, `Helper.registerMenu`, the DockedMenu redirect
  hook, and the event registrations.

  The observable result was total. The mod's menu did not appear, and interacting with the
  chair opened the vanilla menu instead. Because this extension's reload button lives inside
  its now-unreachable menu, there was no in-game route back and the game had to be restarted.

  The failure was silent in the way that mattered: the log showed `initializing UI` and then
  stopped, with no Lua traceback among the extension-tagged lines. Diagnosis came from
  noticing which init log lines were missing, not from an error message.

  Not established by this test: whether a traceback appeared elsewhere in the log under a
  different tag, and whether the engine retries a failed menu init. `initializing UI` was
  logged twice in succession, which was not explained.

### An MD cue variable holding a component survives a save/load and returns to Lua remapped
- X4: 9.00
- Status: live-tested
- Source: live session on 2026-08-08, extension `x4_gunnery_control` build
  `2026-08-08-target-probe-1`, X4 9.00 Steam, Windows 11; game debug.log
- Live test: yes — a target engaged, the game saved, then loaded twice, on 2026-08-08
- Finding: a UI menu that must name a specific object again after a save/load cannot do it
  with an id. Component ids are reassigned on load, so an id written into a string payload
  addresses a different object afterwards. Parking the same object in an MD cue variable as
  a component does work.

  Lua sent the target's id to MD with `AddUITriggeredEvent`, MD stored `event.param3` into a
  cue variable and logged `typeof=component idcode=SFL-948`. The game was saved, then loaded
  twice. On both loads MD logged the same `idcode=SFL-948` and raised the variable back with
  `raise_lua_event`; Lua received `type=number` and `IsComponentOperational` returned true.

  The numeric id differed on each load — `2089492` on the first, `34178848` on the second,
  against a pre-save id of `444138`. That difference is the result, not noise: the same
  object arrived under a new id each time, so the engine is remapping the reference rather
  than storing a number. The player's own ship was reassigned across the same loads
  (`443747` → `2089092` → `34180899`), reproducing the recorded reassignment behaviour.

  The string payload written on the same tick carried the pre-save target id and was
  correctly refused by the restoring code, so both routes were observed side by side in one
  run: `fromPayload=nil fromMD=2089492`.

  A second run on 2026-08-08 (build `2026-08-08-target-restore-1`) repeated this with a
  **surface element** rather than a whole object: a `XEN L Shield Generator Mk1` on a Xenon
  defence platform. MD logged `typeof=component idcode=null` when storing it and
  `typeof=component idcode=null name=XEN L Shield Generator Mk1` after the load, and Lua
  received a usable id. So surface elements ride this route too. Note the weaker evidence
  there: surface elements report `idcode=null`, so the same-object claim rests on the name
  and on the reference being raised at all, not on a unique id as in the SFL-948 case above.

  Measured in that second run and NOT part of this finding: `SetSofttarget` returned false
  for the recovered surface element immediately after the load, while the identical call on
  the identical element had succeeded at engagement moments before. The engaged element was
  out of range by the time the save was loaded, per the player. Range as the cause is the
  player's report, not a measurement — no distance was logged on that run.

  Not established by this test: what happens when the referenced component is destroyed
  while the game is closed. The MD side guards with `@` and does not raise in that case, but
  that branch was never reached. No limit on how many such references can be held was
  probed; one was used.

### refreshmd re-reads MD from disk, keeps cue variables, and does not re-fire completed cues
- X4: 9.00
- Status: live-tested
- Source: live session on 2026-08-08, extension `x4_gunnery_control`, X4 9.00 Steam,
  Windows 11; game debug.log
- Live test: yes — an on-demand cue's text edited mid-session, with a UI-only reload as the
  control, on 2026-08-08
- Finding: `ExecuteDebugCommand` was present in the menus environment (logged
  `fn_present=true`), and `ExecuteDebugCommand("refreshmd", 0)` picked up an edit made to
  `md/` while the game was running.

  A `debug_text` string inside an on-demand cue was edited and copied into the game's
  `extensions/` directory mid-session. A UI reload alone fired that cue and logged the OLD
  text. After `refreshmd`, the same cue logged the NEW text. The control rules out the UI
  reload having re-read MD.

  Two behaviours measured alongside it. A cue variable set before `refreshmd` was still
  readable after it. A conditionless root cue that had already fired did not fire again, so a
  marker placed in such a cue cannot detect that a refresh happened — an earlier attempt in
  this session failed for exactly that reason.

  Not established by this test: the effect on cues mid-execution, on `instantiate="true"`
  instances in flight, or on newly ADDED cues rather than edited ones.
