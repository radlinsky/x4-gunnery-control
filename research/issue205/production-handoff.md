# Production hologram implementation handoff

2026-09-29, branch `issue-205-turret-map-probe`.

Tasks 7–12 are implemented locally. The production integration has **not** been
live-tested. Task 13 remains the acceptance gate; the earlier M/XL projection
measurements do not prove this new menu integration or activity transport.

## Implementation

- `ui/gunnery_state.lua`: one `<group position>; <turret name>` formatter, used
  in the member list, camera header and hologram hover; ten surface rows/page.
- `ui/gunnery_hologram.lua`: configuration-map lifetime, exact shared projection,
  actual widget bounds/aspect, rotation and zoom memory keyed by runtime ship,
  picking, own rectangle handles and a maximum 800-rectangle local budget.
  The calibration probe delegates projection to this same function.
- Console: all installed turrets; clicking toggles the turret's whole mutable
  group through the same staging helper as the list checkbox.
- Direct-control: selected turrets only, above the surface list. Clicking an
  operational camera-supported turret selects its manual turret POV and rebuilds
  the header. Auto-engage has no hologram.
- `md/x4_gunnery_hologram.xml`: nonce-scoped open/member/commit setup using scalar
  messages, one position read per roster entry, one ship-size read per view.
  String replies preserve fractional metres. Geometry/activity survive cosmetic
  menu rebuilds; target/selection/ship changes replace the subscription.
- MD holds firing and hit timestamps for 1.5 simulation seconds. A delayed
  0.5-second loop sends changed snapshots only; display expiry therefore occurs
  on the next sample after the hold ends. Weapon event handlers emit no Lua
  messages. Hits require current-target and selected-weapon attribution;
  missile turrets never acquire a hit state. A five-second heartbeat lease
  bounds orphaned listeners, including incomplete roster setup.
- Marker shapes: hollow ring (unselected), filled disc (selected idle), orange
  burst (firing), green square reticle (hitting). Far-side dimming uses the
  existing keel-normal heuristic; it does not claim geometric hull occlusion.
- Camera memory lasts across menu and Gunnery session teardown within the same
  Lua lifetime. UI reload or restarting X4 clears it.
- Test Lab's old graph/grid/shape probe was removed. The hologram scan/refine
  tool remains. Its unrelated `onUpdate` problem remains outside this change.
  The existing M/XL fixture remains unchanged and disabled in the repository.
  No native probe or X4Native dependency was added to production.

## Offline evidence

The repository validation suite and focused hologram tests pass. Tests exercise
projection/aspect, stale and malformed replies, missile state filtering,
click-versus-drag, unchanged-frame drawing, retained subscriptions, camera
memory, widget recreation, foreign-shape preservation, and 100 markers within
800 rectangles. MD contract checks guard periodic-delay safety, changed-only
snapshots, target/weapon filtering and string geometry transport. The MD file
also validates against the locally extracted X4 schema.

Current installed base catalogs were checked against the helper, widget,
common-schema, script-property and cinematic-camera sources used here. The
research KB records the rectangle ownership/budget and event identity evidence
with their source classifications. Neither schema validation nor stubs execute
MD expressions or X4's renderer.

## Task 13 live checks

1. On the Ray, open the first Gunnery menu. Confirm actual ship appearance and
   occupied turret alignment while rotating and zooming. Hover labels must
   agree with the list. Click a turret and verify every member of its group
   changes selection; dragging must never toggle selection. Empty slot icons
   must not trigger a turret action.
2. Enter Direct-control. Confirm the hologram is above the surface list, pages
   contain at most ten alternatives, and only checked groups have markers.
   Click another selected turret: its camera and top-right label must agree.
3. With Test Lab Observe enabled for evidence, engage an appropriate target.
   Correlate `[X4GC TEST FIRED]` / `[X4GC TEST HIT]` with `[X4GC HOLO] roster`
   ordinals and `snapshot` state strings (`0` idle, `1` firing, `2` hitting).
   Verify hit precedence, hold/expiry after firing stops, correct target changes,
   and no hitting marker for a missile turret. Per-shot menu rebuilds must not
   occur.
4. Reopen the menu, change between console and Direct-control, change ships and
   return. Rotation/zoom must be remembered separately per ship. Open/close the
   fullscreen map and Test Lab; check that no stale hologram or marker remains.
5. Repeat on a much larger ship; use the retained M/XL setup for alignment
   comparisons. On a high-turret-count ship, inspect `[X4GC HOLO] markers`:
   rectangle counts must stay at or below 800, with coarse rings around 100
   turrets. Check visual smoothness and engine shape-allocation errors.
6. Check Auto-engage and normal turret controls for regressions. Preserve logs
   and observations with the owning issue before declaring Task 13 passed.
