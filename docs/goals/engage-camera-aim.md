# Goal: hold the camera position, aim it continuously at another component

> I want the camera to auto always point towards the
> turret when in Target POV and always auto point to Target while in Turret POV,
> holding the position of the camera by the constant, so I can see the turret's target
> getting shot at from either POV.

Restated concretely:

- **Turret POV**: hold the camera *at the turret*, and continuously aim it *at
  the target*. The player watches, from their gun, the enemy being tracked and
  shot.
- **Target POV**: hold the camera *at the target*, and continuously aim it *back
  at the turret*. The player watches, from the enemy's position, their own gun
  firing at them.

In both cases: **position is pinned to one component, look direction tracks the
other, and the aim updates every frame as either object moves.**

## What already ships (do not need to rebuild this)

The Engage panel has a working **Camera POV toggle** (`ui/gunnery_control.lua`,
`applyEngagePov` / `toggleEngagePov`, commit 03b9122):

- Turret POV: `SetPlayerCameraTargetView(turretComponentID, true)`
- Target POV: `SetPlayerCameraTargetView(softTargetID, true)`

`SetPlayerCameraTargetView` places the camera *at* the given component and the
engine keeps *that same component* framed as it moves. Shift + middle-mouse free
look works in both. Watch mode is separate and already perfect: turret camera
with manual free look.

So today the player can sit at the turret (framing the turret) or jump to the
target (framing the target). What they cannot do is sit at one and *look at* the
other. The camera anchor and the framed/aimed component are the same thing in
this function. That fusion is the entire problem.

## Why this is hard: the evidence gathered so far

All of this is recorded in
`.agents/skills/research-x4-modding/references/ui-lua-menu-camera.md`; the
summary here is so the next session does not repeat the searches.

1. **The UI Lua camera surface cannot separate aim from position.** Enumerated
   the full `ffi.cdef` surface of the shipped UI (1914 unique function names).
   Every camera setter takes one component, a bool, a float, or a position:
   `SetPlayerCameraTargetView`, `SetPlayerCameraCockpitView`,
   `SetPlayerCameraCinematicView`, `SetPlayerCameraExternalView`,
   `SetPlayerCameraFloatingView`, `SetFollowCameraBasePos`,
   `SetCockpitCameraScaleOption`. None takes an orientation or a separate
   look-at component. `GetCameraRotation()` exists but has **no setter**.

2. **The two undeclared camera functions were tested live and are not it.**
   `SetPlayerCameraExternalView(true)` = the standard external ship camera
   (free look, ship-centred, zoomed out). `SetPlayerCameraFloatingView(true)` =
   detaches the camera to a fixed point in space; the ship flies away from it.
   Both confirmed by in-game test, not inference.

3. **`SetFollowCameraBasePos` cannot be parked on a turret.** It offsets the
   camera relative to the followed ship's *centre*, and there is no function
   that returns a turret's ship-local position, so the offset cannot be aimed
   at a specific turret. It is also reset on menu close.

4. **Cutscene assets ARE the one shipped mechanism that separates position from
   look direction, and they track continuously.** Files under `cutscenes/`,
   notably `lookat_anchor_keyframed_shot.xml` and `follow_a_lookat_b.xml`,
   declare `<position>` and `<lookdirection>` independently, each referencing a
   different object with x/y/z offsets. `cutscenes.xsd` documents a reference
   object's position as queried *per frame*, so the aim genuinely follows a
   moving target. **This is the most promising lead by far.** The blockers found
   so far, each of which needs re-checking rather than trusting:
   - A running cutscene cannot be re-aimed: `cutscene_event` carries only a
     string cue, no object or coordinate, so changing target means stop and
     restart.
   - The only shipped *main-view* cutscene is Live Stream View (F6), a
     letterboxed spectator mode with no weapon or steering controls.
   - All 15 shipped Lua `StartCutscene` calls render into a small render-target
     panel, never the main camera, and all pass object references, never the
     numbers the x/y/z offsets would need.

5. **The engine exports far more than vanilla declares.** `X4.exe` exports 2493
   named functions; vanilla UI Lua calls only 1885, leaving **609 callable but
   undeclared**. `ffi.cdef` only declares what already exists in the binary, so
   any of these can be declared and called. The 609 were grepped for
   camera/aim/look/track terms and only VR/head-tracking hits turned up, but
   that was a name grep, not an exhaustive study. The export list is cached at
   `.x4-research-cache/exports/undeclared-9.00.txt`.

## Community input already obtained

Asked kuertee (author of the UI Extensions mod) on the X4 modding Discord. His
two suggestions, both since investigated:

- **Cutscene look-at** (lead 4 above): correct that the mechanism exists and
  tracks; the open question is whether it can run on the *playable* main camera
  with ship control retained, and whether a Lua-started cutscene accepts number
  params and a non-render-target destination.
- **Translate the turret position to a vector, place the follow camera, switch
  to third person**: blocked by the missing ship-local turret offset getter
  (lead 3).

The Discord and egosoft forums are a live, valuable channel the local research tools cannot reach.
Use it.

## Possible next steps

1. **Put the two sharp questions to the Discord** (phrased for a modder):
   - "Is there a function returning a turret's or connection's position in its
     parent ship's local coordinates? `GetComponentOffset` appears to be
     camera-relative world space, not ship-local."
   - "Can a Lua `StartCutscene` render to the main player camera rather than a
     render target, and does `CreateCutsceneDescriptor`'s params table accept
     number params (x/y/z), or only object references? And can a running
     cutscene's look-at anchor be updated without a restart?"
   A yes to the cutscene questions makes lead 4 the whole solution.

2. **Study the 609 undeclared exports properly**, not by name grep. Cross-
   reference against the game's export table with any available symbol
   information. Look specifically for camera orientation, look-at, or a target-
   view variant that takes two components. The signature-guessing method is
   proven: infer from a declared sibling (`SetPlayerCameraTargetView(UniverseID,
   bool)`), declare it, wrap the call in `pcall`, add a temporary button in the
   Engage panel, and test on a disposable save. `TestAPI` in
   `ui/gunnery_control.lua` and the `experiment_actions` button pattern (see
   git history around commit b6e2b36) are the established harness.

3. **If the cutscene route opens**, prototype a look-at cutscene that anchors on
   the turret and looks at the soft target, driven from MD and triggered from
   Lua via `AddUITriggeredEvent` / `RegisterEvent` (this project already bridges
   Lua and MD that way). Verify weapon and steering control survive; a camera
   that tracks but disables firing is not acceptable.

4. **Fallback if nothing separates aim from position**: the shipped Target POV
   already auto-follows the enemy, which delivers most of the value ("see my
   target getting shot at"). Document that as the supported behaviour and treat
   true fixed-position aim as a stretch goal.

## Status 2026-08-05: solved for Sit@Target, deferred for Sit@Turret

The MD `<play_cutscene cinematicmode="true">` route works and is live-tested:
`Follow_A_Lookat_B` anchors on one component and looks at the other, and
**turrets keep firing** while it runs. Sit@Target framing (anchor.size + 50m
behind, offset off the sight line) is confirmed good.

Sit@Turret still clips into the parent hull whenever the turret aims
perpendicular to the ship, because this asset always puts the camera on the
anchor→target line. The intended structural fix is a custom cutscene asset with
turret-**local** position offsets so the camera rides the turret's rotation:
`cutscenes/x4gc_shoulder_cam.xml` is written, but it is **not wired up** — no MD
cue references it and it is not in `scripts/install-dev.sh` or
`scripts/package.sh`. The one unknown is whether the engine loads
`extensions/<name>/cutscenes/*.xml` at all; a single launch answers it.

Deferred at the user's request. When resuming, restore the four contract greps
removed from `tests/test_runtime_ui_contract.sh` in the same commit as the MD
cue and the packaging changes.

## Open to test other ideas

- Hacking the game engine
- Hacking a way to use existing Set*() commands to continuously update the camera view to point it in the right direction
- ??? 

## Hard constraints

- Test every guessed FFI signature on a disposable save; a wrong signature can
  crash the engine, not just error.
- Do not modify vanilla files or persistent player settings (camera position
  presets, notification settings). The project ships on Nexus and must not
  conflict or alter saved preferences.
- Follow the test-driven working agreement in [DEVELOPMENT.md](../../DEVELOPMENT.md): a failing test
  first, then the change, then `bash scripts/validate.sh`, then commit together.
  The smoke harness (`tests/test_runtime_smoke.lua`) executes the runtime file
  under stubs and is the only test that catches runtime type errors.
- Classify every research conclusion honestly (`shipped-source`, `inference`,
  `live-tested`, ...). Several confident negatives in this project turned out
  wrong because "I searched and found nothing" was reported as "impossible". A
  scoped negative naming what was searched is the correct form.

## Where to read in

- `.agents/skills/research-x4-modding/references/ui-lua-menu-camera.md` — every
  camera finding, dated and classified.
- `ui/gunnery_control.lua` — `applyEngagePov`, `toggleEngagePov`, `enterCamera`,
  the `TestAPI` surface.
- `.x4-research-cache/exports/undeclared-9.00.txt` — the 609 undeclared exports.
- `.x4-research-cache/extracted/cutscenes-9.00/cutscenes/` — the cutscene assets,
  including `lookat_anchor_keyframed_shot.xml` and `follow_a_lookat_b.xml`.
