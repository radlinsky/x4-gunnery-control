# Seated player presentation after control release

## Evidence scope

The source inspection used the installed Steam X4 build identified by
`version.dat` as 9.00. The named files were freshly selected from base catalogs
`01.cat` through `09.cat` with XRCatTool 1.11 on 2026-09-09. The official
Mission Director guide and Breaking Changes page were searched on the same
date; neither documents this exact composition. Targeted searches of the
English Egosoft modding forum and installed extensions found no corroborating
implementation. Forum search results were sparse, so the shipped source and
schema are the primary evidence.

## Supported candidate operations

### Native Get Up and the current control group are exposed separately
- X4: 9.00
- Status: shipped-source
- Source: `ui/addons/ego_detailmonitor/menu_docked.lua:103,115,207-213,232-236,286-290,1442-1445`
- Live test: partial — earlier X4 9.00 Gunnery Control sessions established the
  working Get Up to on-foot route; the composed seated candidate is untested as
  of 2026-09-09
- Finding: vanilla declares `GetPlayerCurrentControlGroup()` and `GetUp()` as
  separate UI functions. DockedMenu identifies a secondary control post from a
  nonempty, non-`pilotcontrol` group and its Get Up button invokes `GetUp()`.
  This is the supported release path a candidate can reuse. Shipped Lua does
  not expose the internal release operation or prove when the group becomes
  empty, so the post-Get-Up group transition must be observed live.

### MD can restore the actual player's room-relative transform
- X4: 9.00
- Status: shipped-source
- Source: `libraries/common.xsd:35603-35616`;
  `libraries/scriptproperties.xml:55-58`; active player-placement examples in
  `md/story_diplomacy_intro.xml:9109-9112,9232-9235`
- Live test: no — the post-Get-Up composition is untested as of 2026-09-09
- Finding: `set_player_entity_position` is a supported MD action documented by
  the shipped schema as setting the player position in the current room, with
  optional `position` and `rotation`. Component properties expose position and
  rotation relative to the parent. Vanilla also actively places
  `player.entity` at explicit room transforms with `add_actor_to_room`. A
  bounded candidate can therefore capture the player's chair transform before
  Get Up and restore that transform afterward without invoking an internal
  engine function. Exact chair alignment after release remains a live result.

### MD can request an `idle` / `sit` sequence on the real player body
- X4: 9.00
- Status: shipped-source
- Source: `libraries/common.xsd:33192-33231`;
  `md/story_diplomacy_intro.xml:9157-9166`;
  `libraries/character_components.xml` (all seven `class="player"`
  components, including `character_player_argon_male_01:748-756`)
- Live test: no — `idle` / `sit` on a released player is untested as of
  2026-09-09
- Finding: the supported `start_actor_sequence` action accepts an actor,
  sequence type, behavior, transition, immediate-transition, and blend
  arguments. Active vanilla MD applies the action to `player.entity`, waits for
  that player's animation-finished event, then requests another player
  sequence. Every one of the seven shipped player components has an
  `idle` / `sit` sequence backed by seated animation transitions. The supported
  candidate request is therefore `start_actor_sequence actor="player.entity"`
  with type `idle` and behavior `sit`; whether the resulting presentation meets
  the physical seated acceptance criterion must be verified live.

### Player body availability is observable, but body lifetime is not scripted
- X4: 9.00
- Status: shipped-source
- Source: `libraries/scriptproperties.xml:2562`; scoped census of base
  `md/*.xml`, `libraries/common.xsd`, and `libraries/scriptproperties.xml`
- Live test: no — untested as of 2026-09-09
- Finding: the supported keyword property is `player.hasbody`, described as
  whether the player currently has a body capable of animations. The property
  supplies a guard for a player animation request. No player-body-created or
  player-body-removed event, and no supported action for creating the player's
  body, was found in the inspected MD/XSD surface. A candidate may wait or poll
  for `player.hasbody`; it cannot assume a one-shot pose survives body removal,
  recreation, locomotion, camera changes, or another animation request.

## Candidate boundary

### The smallest source-backed candidate is bounded and ready for live testing
- X4: 9.00
- Status: inference
- Source: composition of the four shipped-source records above
- Live test: no — untested as of 2026-09-09
- Finding: a test-only candidate may capture the real player's room-relative
  chair position and rotation, let vanilla `GetUp()` complete, verify that
  `GetPlayerCurrentControlGroup()` no longer reports `gunnercontrol`, restore
  the captured transform with `set_player_entity_position`, and request
  `idle` / `sit` on `player.entity` only while `player.hasbody`. Every operation
  the mod would invoke is present in the supported shipped scripting surface.
  The sources do not prove that the engine keeps the restored transform and
  seated animation separate from released input/control state; that is the
  candidate's live-test hypothesis, not a source-proven engine guarantee.

## TARGETMOUSE boundary

### World TARGETMOUSE selection is engine-owned outside registered UI targets
- X4: 9.00
- Status: shipped-source
- Source: `ui/core/lua/targetsystem.lua:115,1209-1226,1234-1319,3850-3890`;
  Gunnery Control integration context `ui/gunnery_control.lua:247-250,2468-2509,3486-3516`
- Live test: no — the seated candidate's TARGETMOUSE behavior is untested as of
  2026-09-09
- Finding: shipped target-system Lua reads the current TARGETMOUSE mapping and
  handles clicks only for registered Anark target elements. It explicitly says
  the input system performs default handling for clicks outside those elements,
  including object geometry and empty space, and it immediately returns in
  first-person mode because those clicks are always handled by the engine.
  Public Lua can register mouse interactions on known target-system elements,
  block a mapped click on such an element, read the resulting soft target with
  `GetSofttarget2`, and explicitly call `SetSofttarget` for a known message ID.
  Gunnery Control can therefore observe target changes and correlate them with
  its own camera/session state, but shipped Lua exposes neither the engine's
  world-ray result nor a supported switch that forces the native world picker
  into a released player's seated presentation. Whether TARGETMOUSE changes
  targets in manual Turret POV and Target POV is engine-owned behavior requiring
  a controlled live comparison with the accepted standing route.

## Unresolved inference and required live gates

- The real player body will visibly enter the authored seated state after the
  control group is released.
- Restored room-relative placement will stay aligned with the moving physical
  chair and will not be corrected by collision or locomotion.
- The seated sequence will persist, or can be reapplied safely, across body
  availability changes and competing animation requests.
- Cleanup can restore a usable on-foot transform and ordinary animation without
  reacquiring `gunnercontrol` or leaving input locked.
- Native TARGETMOUSE selection will change the same whole-object and surface
  soft targets in both manual camera viewpoints as it does in the accepted
  standing route.

Binary reverse engineering may explain these outcomes, but none of these claims
is promoted by internal fields or call chains. No FFI hook, native patch,
unpublished call, or guessed engine API belongs in the candidate.

## Ordinary first-person viewpoint boundary after control release

### The supported Lua camera surface cannot bind ordinary first-person view to the player body
- X4: 9.00
- Status: shipped-source
- Source: complete base `08.cat` UI Lua census (77 files), especially
  `ui/addons/ego_detailmonitor/menu_map.lua:2020,2133-2134`,
  `ui/addons/ego_interactmenu/menu_interactmenu.lua:1171,1276,1313`, and
  `ui/addons/ego_detailmonitor/menu_followcamera.lua`; indexed with
  `scripts/index-lua-ffi.sh` on 2026-09-09
- Live test: no — source-surface result
- Finding: the shipped declarations expose mode or anchor operations for
  cockpit, external-target, cinematic, scene, and follow cameras. None accepts
  `player.entity`, a room-relative player transform, a body instance, or a
  request to attach, refresh, recalculate, or rebind the ordinary first-person
  viewpoint. `GetCameraRotation` and the MD `player.camera` properties are
  read-only observations. A turret target-view operation addresses a different
  external camera and does not establish control of ordinary first-person view.

### The supported MD surface moves the body but does not move or refresh its viewpoint
- X4: 9.00
- Status: shipped-source
- Source: `libraries/common.xsd:36508-36521`;
  `libraries/medium_library.xml:548-557,600-629`;
  `libraries/parameters.xml:408-442,488-545`;
  `libraries/scriptproperties.xsd:42-46`; complete base `md/*.xml` and
  `libraries/*.{xml,xsd}` census (391 files) on 2026-09-09
- Live test: no — source-surface result
- Finding: `set_player_entity_position` sets only the player's position and
  rotation in the current room. `leave_control_position` activates first-person
  controls, while `set_player_firstperson_override` selects movement/body
  parameters such as body dimensions, eye offset, movement speed, pitch,
  bobbing, and acceleration. The schema exposes no ordinary-viewpoint action,
  no camera/body binding action, and no refresh after player placement. The
  complete shipped MD corpus contains no hidden composition of such operations.

### Restoring the real body transform does not implicitly rebind ordinary first-person view
- X4: 9.00
- Status: live-tested
- Source: Issue #146 diagnostic run recorded 2026-09-09, build marker
  `2026-09-09-issue146-seated-player-feasibility`, candidate
  `3010595f54531a983f960266a6450a2d8028e56d`
- Live test: yes — native Get Up reached an empty control group; the chair
  transform was applied again after `player.hasbody` returned; real-player
  `idle` / `sit` succeeded; the owner-visible first-person viewpoint still
  returned to the standing location when normal Gunnery Control reopened
- Finding: the exact supported body-placement and animation composition did
  not make the ordinary player viewpoint follow the restored seated body. This
  disproves an implicit viewpoint refresh from `set_player_entity_position`,
  body recreation, or `idle` / `sit` under the tested released-control/menu
  state. The run does not establish how the engine internally selects its
  first-person viewpoint anchor.

### No supported mechanism exists for the required released-control seated viewpoint
- X4: 9.00
- Status: inference
- Source: composition of the shipped-source and live-tested records above;
  X4 9.00 `X4.exe` named export census; official Lua function overview checked
  2026-09-09; targeted installed-extension and Egosoft-forum searches
- Live test: yes — the only supported body/transform candidate failed the
  viewpoint relationship in the recorded diagnostic run
- Finding: **FAIL.** X4 9.00 exposes no supported public Lua/MD operation or
  sequence that attaches or recalculates the ordinary first-person viewpoint
  from a moved real player body, refreshes that relationship after
  `set_player_entity_position`, or preserves it with no active
  `gunnercontrol` group while normal Gunnery Control UI remains open. The
  executable exports ordinary camera-mode setters but no named body/viewpoint
  bind or refresh operation; export names do not prove signatures or public
  support in any case. Reverse-engineered player animation, body-lifetime,
  transform, control-group, and camera-selection paths may explain the split,
  but those internals remain engine-owned and cannot become a candidate API.
  There is therefore no supported next implementation operation. Retain the
  accepted standing/onboard route; a replacement or cosmetic camera and native
  hooks are outside this finding.
