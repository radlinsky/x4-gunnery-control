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

The player-placement records below were re-derived on 2026-09-09 from a fresh
single-document extraction of base `md/*.xml` (221 files) and
`libraries/*.{xml,xsd}`, plus a separate per-extension extraction of the seven
shipped DLC `md/` trees. The earlier 391-file "complete base census" behind the
first negative conclusion was extracted into concatenated files: several cached
paths held three to eight appended XML documents, so its line citations and its
per-file identity claims are not reliable and its cited
`libraries/medium_library.xml:548-557,600-629` was schema text appended into an
unrelated file. Line numbers below come from the clean extraction. When
re-checking any citation here, verify the cached file contains exactly one
`<?xml` declaration first.

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

### `add_actor_to_room` is the shipped operation that relocates the real player
- X4: 9.00
- Status: shipped-source
- Source: `libraries/common.xsd:18987-19086`; 7 active base call sites
  (`md/story_diplomacy_intro.xml:884,2228,6452,9109,9232`;
  `md/story_research_welfare_1.xml:378,1279`) plus a commented `WarpPlayer` cue
  in `md/gs_scientist.xml:20-33`; 42 further active call sites across the seven
  shipped DLC `md/` trees, for 49 active player call sites in total
- Live test: no — the post-Get-Up composition is untested as of 2026-09-09
- Finding: `add_actor_to_room` takes an `actor`, either an `object` room or a
  `slot`, optional `position` and `rotation` child elements, `setroomslot`,
  `triggeranimation`, `blend`, `chairtrigger`, and a `result`. The schema
  documents it as adding an actor to a room and says the action *fails* if the
  actor could not be connected to that room, so it performs a room connection
  and reports whether that connection succeeded. Vanilla drives the actual
  player with it: the two shipped call sites carrying an authored comment call
  it "Warp player to different position"
  (`md/story_diplomacy_intro.xml:883,2227`), and every scene that relocates the
  player between rooms, ships, docks, prisons, and throne rooms uses this
  action, never a bare transform write. Placement into the room the player is
  already in is also shipped
  (`ego_dlc_timelines/md/story_timelines_epilogue.xml:2417`,
  `object="player.room"`).

### `set_player_entity_position` is an in-room adjunct, never a relocation on its own
- X4: 9.00
- Status: shipped-source
- Source: `libraries/common.xsd:35603-35616`;
  `libraries/scriptproperties.xml:55-58`; the only four shipped call sites,
  `ego_dlc_timelines/md/scenario_transport_refugees.xml:440,476` and
  `ego_dlc_timelines/md/scenario_transport_refugees_engineer.xml:1896,2004`
- Live test: yes — see the disproved implicit-rebind record below
- Finding: the schema documents `set_player_entity_position` as "Set player
  position in room". It takes only `position` and `rotation`, names no room, and
  has no `result`, so it cannot express or report a room connection. It appears
  **zero** times in the 221 base MD files. All four shipped uses are in
  Timelines refugee-transport scenarios and every one of them is emitted
  immediately after an `add_actor_to_room actor="player.entity"` on the target
  room, as a follow-up that fine-tunes the offset and yaw inside the room the
  player was just connected to. Shipped source therefore never uses this action
  to move the player anywhere; it is the second half of a two-step composition.

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

### Shipped player relocation is gated on released control, and the gate is mandatory
- X4: 9.00
- Status: shipped-source
- Source: `ego_dlc_pirate/md/story_thefan.xml:5501-5525`;
  `ego_dlc_pirate/md/story_criminal.xml:10868-10892`;
  `ego_dlc_boron/md/gs_boron2.xml:241,252-283`;
  `ego_dlc_boron/md/story_boron.xml:17426`;
  `ego_dlc_timelines/md/scenario_dragonfyre.xml:1454,1478,2129,2140`;
  `ego_dlc_timelines/md/scenario_presidents_end.xml:789-793`;
  `md/story_research_welfare_1.xml:1273,1279`;
  `libraries/md.xsd:4154-4163`; `libraries/common.xsd:16001-16010`
- Live test: no — untested as of 2026-09-09
- Finding: two shipped DLC scripts carry the same authored warning in the
  source of the placement cue itself: `add_actor_to_room` for `player.entity`
  breaks the game if the player is sitting in their pilot seat,
  `dismiss_control_entity` and `remove_from_room` did not resolve it, and
  `leave_control_position` is what gets the player off the chair. Two Boron
  call sites repeat the constraint as an attribute comment reading
  `player.controlled needs to be false`. The shipped shape is therefore fixed:
  if `player.controlled`, call `leave_control_position` (documented as having
  the player leave their current control position and activate first-person
  controls), wait for `event_player_stopped_control`, then place the player
  with `add_actor_to_room`. The single base-game `leave_control_position` call
  site follows the same order. This precondition is satisfied by the accepted
  Gunnery Control route, whose native Get Up already reaches an empty control
  group before the mod does anything.

### The smallest source-backed candidate is the shipped two-step placement
- X4: 9.00
- Status: inference
- Source: composition of the shipped-source records above
- Live test: no — untested as of 2026-09-09
- Finding: a test-only candidate may capture the real player's room-relative
  chair position and rotation, let vanilla `GetUp()` complete, verify that
  `GetPlayerCurrentControlGroup()` no longer reports `gunnercontrol` and that
  `player.controlled` is false, connect the player back to the captured room
  with `add_actor_to_room actor="player.entity" object="<captured room>"`
  carrying the captured `position` / `rotation` and checking `result`,
  optionally fine-tune with `set_player_entity_position`, and request `idle` /
  `sit` on `player.entity` only while `player.hasbody`. That order is the
  shipped composition, not an invention. Most shipped player placements write
  the vertical coordinate as body height above the room floor —
  `y="player.entity.race.height"`, `y="1.808m"`, or `$FloorPos.y + 1.8m` —
  though throne-room and observation-room sites use room-local origins where it
  is negative or several metres up, so the value is plainly room-space and not
  a floor offset. A candidate reusing a captured `player.entity.position` must
  confirm the capture is in the same room space before reading a vertical
  discrepancy as a failure. The sources do not prove that the engine keeps the
  restored transform and seated animation separate from released input/control
  state, nor that the ordinary first-person viewpoint follows a room
  connection; those are the candidate's live-test hypotheses, not source-proven
  engine guarantees.

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

- The ordinary first-person viewpoint follows `add_actor_to_room` when the
  player is reconnected to a room after control release. This is the open
  question the corrected records below narrow the workstream to.
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

### No MD action binds or refreshes the viewpoint, but placement is not a bare transform write
- X4: 9.00
- Status: shipped-source
- Source: `libraries/common.xsd:18987-19086,35603-35616`;
  `libraries/md.xsd:4154-4163,4206-4233`;
  `libraries/parameters.xml:191-225`;
  clean single-document base `md/*.xml` (221 files) and
  `libraries/*.{xml,xsd}` census plus the seven shipped DLC `md/` trees,
  2026-09-09
- Live test: no — source-surface result
- Finding: the corrected surface reading is narrower than the earlier one.
  There is still no MD action that names a camera, attaches a viewpoint, or
  refreshes a viewpoint after placement. But `set_player_entity_position` is
  not the shipped player-placement surface at all — it is the in-room adjunct
  recorded above, and it never appears alone. The shipped placement operation
  is `add_actor_to_room`, which connects the actor to a room, can report
  failure, and is authored in-source as warping the player. The earlier claim
  that the supported MD surface "moves the body but does not move its
  viewpoint" was drawn from the only operation shipped source never uses for
  this purpose, and it also rested on a citation to
  `libraries/medium_library.xml` that was a concatenated-cache artifact. The
  absence of an explicit camera-binding API is therefore not evidence that the
  engine leaves the viewpoint behind when the player is connected to a room.

### `set_player_firstperson_override` is immaterial to the viewpoint question
- X4: 9.00
- Status: shipped-source
- Source: `libraries/md.xsd:4206-4233`; `libraries/parameters.xml:191-225`;
  the only shipped call sites,
  `ego_dlc_timelines/md/scenario_presidents_end.xml:840,1279`
- Live test: no — source-surface result
- Finding: the action takes one argument, an `id` selecting a preauthored entry
  under `playerfirstperson/overrides` in `parameters.xml`. Those entries carry
  first-person *movement and body* parameters — `body`
  width/height/`eyeoffset`, speed, acceleration, crouch, jump, pitch limits,
  bobbing, max slope. Base game ships two overrides, `race="boron"` (bobbing
  only) and `id="argon_slow_stumble"` (a shorter, slower, wobblier walking
  player), and the only shipped use applies the stumble override to a player
  who has just been placed on foot and clears it later. `eyeoffset` shifts the
  eye a fixed distance on the standing body capsule; neither it nor any sibling
  parameter names a target transform, a room, or an anchor. It cannot re-anchor
  a viewpoint and is out of scope for this question.

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
- Finding: the tested composition did not make the ordinary player viewpoint
  follow the restored seated body. This disproves an implicit viewpoint refresh
  from `set_player_entity_position`, body recreation, or `idle` / `sit` under
  the tested released-control/menu state. It disproves nothing about
  `add_actor_to_room`: the candidate at `3010595` calls
  `set_player_entity_position` in both its apply and its body-transition path
  (`md/x4_gunnery_control.xml:602-605,642-645`) and never calls
  `add_actor_to_room`, so the run omitted the room-connection step that every
  shipped player relocation performs first, and had no `result` to report
  whether placement took effect at all. The run does not establish how the
  engine internally selects its first-person viewpoint anchor.

### `add_actor_to_room` on the released player is a bounded LIVE hypothesis
- X4: 9.00
- Status: inference
- Source: composition of the shipped-source records above; the inherited X4
  9.00 `X4.exe` named export census, official Lua function overview,
  installed-extension and Egosoft-forum searches of 2026-09-09 still return no
  camera-binding API
- Live test: no — the operation has never been run in this workstream
- Finding: **NOT DISPROVED — LIVE-ONLY.** The earlier **FAIL** verdict is
  withdrawn. It generalised one live falsification of
  `set_player_entity_position` into a claim about the whole supported surface,
  and the operation shipped source actually uses for this purpose was never
  tried. What source does establish: `add_actor_to_room` performs a room
  connection rather than a transform write, reports success or failure, is
  authored in-source as warping the player, is used at 49 active call sites
  across base and DLC to relocate the real player — including into the player's
  current room — and is documented as requiring released control before it
  touches the player. What source cannot establish: whether the ordinary
  first-person viewpoint follows that connection. The engine owns viewpoint
  selection and no shipped script observes it. The strongest available
  circumstantial reading is
  `ego_dlc_timelines/md/scenario_presidents_end.xml:789-793,834-840`, where
  `leave_control_position` is followed immediately by `add_actor_to_room` into
  a freshly created interior, and then by a second identical placement carrying
  the authored comment that the player is being moved again because they could
  have moved during the hold time. That correction only makes sense if the
  player was walking in ordinary first person from the first placement, so the
  shipped corpus contains no case of the first-person player being left behind
  by this action. That is suggestive, not proof, and every shipped placement
  leaves the player standing — none holds a seated pose.

### The smallest live discriminator
- X4: 9.00
- Status: inference
- Source: `md/x4_gunnery_control.xml:586-652` at candidate
  `3010595f54531a983f960266a6450a2d8028e56d`; shipped two-step composition above
- Live test: no — this is the proposed experiment
- Finding: one action added, nothing else changed. In the existing opt-in
  seated probe, immediately before each `set_player_entity_position`, insert
  `add_actor_to_room actor="player.entity" object="SeatedPlayerProbe.$room"`
  carrying the same captured chair `position` / `rotation` and a `result` that
  is logged, gated on the already-observed released state (`not
  player.controlled`, empty control group). Keep the existing
  `set_player_entity_position`, `player.hasbody` guard, and `idle` / `sit`
  request exactly as they are; that yields the shipped two-step order rather
  than a substitution. Re-run the same Test Lab fixture and the same operator
  procedure as the 2026-09-09 diagnostic. The single discriminating observation
  is whether the ordinary first-person viewpoint moves to and stays at the
  chair when Gunnery Control reopens. Because the only delta from the falsified
  run is the room-connection step, either result is attributable to it. The
  known MD parse and `<delay>`-condition defects in that candidate must be
  fixed first or cleanup will not be trustworthy.

### Limits that survive either outcome
- X4: 9.00
- Status: shipped-source
- Source: `libraries/common.xsd:18987-19086`; all 49 active shipped
  `add_actor_to_room actor="player.entity"` call sites (7 base, 42 DLC)
- Live test: no — untested as of 2026-09-09
- Finding: three limits hold regardless. First, no shipped call site places
  `player.entity` by `slot`; all use `object` plus an explicit transform, and
  the schema describes the action as adding an *NPC* actor and `setroomslot` as
  applying only to a valid NPC slot, so seating the player on a
  control-position roomslot the way `md/scenario_combat.xml` seats an NPC
  gunner is unattested. Second, `triggeranimation` defaults to true and fires
  the room slot's default animations, and `chairtrigger` defaults to
  `activate_chair`; on an `object` placement with no slot there is no slot
  animation to trigger, so the seated pose still has to come from the separate
  `idle` / `sit` request and remains subject to body recreation and ordinary
  locomotion. Third, the authored in-source warning that this action breaks the
  game when the player is still in their pilot seat means the released-control
  gate is a correctness requirement, not a stylistic one. If the discriminator
  above fails, the honest conclusion is that the supported surface has been
  exhausted for this requirement: retain the accepted standing/onboard route. A
  replacement or cosmetic camera and native hooks remain outside this finding
  either way.
