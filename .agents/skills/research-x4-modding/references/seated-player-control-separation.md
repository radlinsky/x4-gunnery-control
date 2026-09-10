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
