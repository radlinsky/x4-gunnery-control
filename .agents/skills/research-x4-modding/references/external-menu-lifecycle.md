# External-menu lifecycle and persistent Gunnery overlay

- X4 version: 9.00
- Research date: 2026-09-09
- Project starting SHA: `921cdad21ecbdd25c9766fffc40f3e609469f5ef`
- Scope: issue #117 research boundary only; no production behavior is proven by this record.

### Helper clears by registered type, not by view name

- X4: 9.00
- Status: shipped-source
- Source: `ui/addons/ego_viewhelper/viewhelper.lua:101-168,191-203`;
  `ui/addons/ego_detailmonitorhelper/helper.lua:3120-3141,4102-4115`;
  `ui/addons/ego_chatwindow/chatwindow.lua:18-67,497-535,806-832`
- Live test: no — shipped-source registry/type behavior; compositor and input ordering are covered separately.
- Finding: ordinary Helper menu opening calls `View.clearMenus({ Helper = true })`.
  `View.clearMenus` selects entries by the registered entry's exact `type` field.
  `Helper.createFrameHandle` exposes that field through `viewHelperType`, which
  defaults to `"Helper"` but may be set to another value. The shipped Chat Window
  uses Helper-created frames and widgets with `viewHelperType = "Chat"`, proving
  that Helper tables/buttons do not require the registered type to be `"Helper"`.
- Consequence: an engaged Gunnery frame registered with a custom type such as
  `"X4GunneryOverlay"` is not selected by `View.clearMenus({ Helper = true })`.

### Helper frame registration IDs still collide by layer

- X4: 9.00
- Status: shipped-source
- Source: `ui/addons/ego_viewhelper/viewhelper.lua:101-168`;
  `ui/addons/ego_detailmonitorhelper/helper.lua:4102-4115`
- Live test: no — shipped-source View registration-ID behavior.
- Finding: Helper-created frames register with ID `"Helper" .. layer` regardless
  of `viewHelperType`. `View.registerMenu` matches/replaces entries by that ID,
  independently of type. A custom-type frame therefore survives Helper-type
  clearing but can still be replaced by another Helper-created frame using the
  same layer.
- Consequence: custom type and layer allocation solve different problems. Do not
  assume a custom `viewHelperType` makes a layer globally collision-free.

### Normal world right-click reaches Helper clear without an earlier shipped cancellable hook

- X4: 9.00
- Status: shipped-source
- Source: `ui/core/lua/targetsystem.lua:1212-1319,3999-4011,4357-4377`;
  `ui/addons/ego_detailmonitorhelper/helper.lua:1339-1452`;
  `ui/addons/ego_interactmenu/menu_interactmenu.lua:3262-3358`
- Live test: no — shipped-source callback/control-flow finding.
- Finding: normal world right-click is handled by private target-system bracket
  callbacks. It eventually reaches `C.ShowInteractMenu(...)`; the ordinary
  Helper show path marks InteractMenu shown and calls
  `View.clearMenus({ Helper = true })` before InteractMenu has exposed useful
  target context to extension callbacks. No shipped cancellable interception
  point was found that lets an extension-owned Helper menu redirect that exact
  click through `Helper.openInteractMenu` first.

### Inspected third-party callbacks do not provide an earlier InteractMenu cancellation

- X4: 9.00
- Status: third-party-technique
- Source: UI Extensions 9.00 `ui/addons/ego_detailmonitorhelper/helper.xpl`;
  SirNukes Mod Support APIs Interact Menu API
- Live test: no — third-party source inspection only.
- Finding: the inspected third-party callbacks observe ordinary InteractMenu too
  late to cancel the Helper clear; they do not change the conclusion above.

Project consequence: interception is unnecessary if engaged Gunnery visuals
are no longer registered as type `"Helper"`. Vanilla world right-click can
remain untouched while the custom-type overlay survives underneath.

### Ordinary InteractMenu is an overlay relative to a persistent custom view

- X4: 9.00
- Status: shipped-source
- Source: `ui/addons/ego_interactmenu/menu_interactmenu.lua:342-344,3414-3435,7725-7750`;
  `ui/addons/ego_viewhelper/viewhelper.lua:58-70,191-227`;
  `ui/addons/ego_detailmonitorhelper/helper.lua:3120-3141,4115`
- Live test: required. Shipped Lua does not define engine-side compositor or
  hit-test ordering. Verify that InteractMenu is visibly/input-wise above the
  Gunnery overlay and that clicks do not leak to Gunnery controls underneath.
- Finding: ordinary InteractMenu uses Helper layer 2 and the default registered
  type `"Helper"`. A surviving custom-type Gunnery frame on a different layer
  remains in the shared View registry while InteractMenu is added. Closing
  InteractMenu unregisters its own `Helper2` entry; a surviving custom entry
  keeps the view alive, so no Gunnery reopen/rebuild is inherently required.

### Shipped menus distinguish floating overlays from fullscreen takeovers in tracked-menu state

- X4: 9.00
- Status: shipped-source
- Source: `ui/addons/ego_detailmonitorhelper/helper.lua:1331-1436,1907`;
  `ui/addons/ego_interactmenu/menu_interactmenu.lua:3309`;
  `ui/addons/ego_detailmonitor/menu_toplevel.lua:80`;
  `ui/addons/ego_detailmonitor/menu_transporter.lua:125`;
  `ui/addons/ego_detailmonitor/menu_platformundock.lua:83`;
  `ui/addons/ego_detailmonitor/menu_map.lua:6383,6509,6595-6617`;
  `ui/addons/ego_helptext/helptext.lua:532`
- Live test: no — shipped-source tracked-menu classification behavior.
- Finding: Helper initially tracks a newly shown menu with
  `C.TrackMenu(menu.name, true)`. Floating/overlay menus such as InteractMenu,
  TopLevelMenu, TransporterMenu, and PlatformUndockMenu explicitly change their
  tracked record to non-fullscreen with `SetTrackedMenuFullscreen(..., false)`.
  Normal Map retains the initial fullscreen classification; its explicitly
  floating/context modes set it false.

### Empty-name fullscreen query is the name-independent takeover discriminator

- X4: 9.00
- Status: inference
- Source: `ui/addons/ego_detailmonitorhelper/helper.lua:1331-1436,1907`;
  `ui/addons/ego_interactmenu/menu_interactmenu.lua:3309`;
  `ui/addons/ego_detailmonitor/menu_toplevel.lua:80`;
  `ui/addons/ego_detailmonitor/menu_transporter.lua:125`;
  `ui/addons/ego_detailmonitor/menu_platformundock.lua:83`;
  `ui/addons/ego_detailmonitor/menu_map.lua:6383,6509,6595-6617`;
  `ui/addons/ego_helptext/helptext.lua:532`
- Live test: required — confirm the behavior during real overlay/fullscreen menu transitions.
- Finding: bounded by shipped call patterns and FFI signatures,
  `IsFullscreenMenuDisplayed(true, "")` is the intended name-independent query
  for whether any displayed tracked menu is classified fullscreen;
  `IsFullscreenMenuDisplayed(false, menuName)` queries a specific tracked menu.
  The flag is presentation classification, not input ownership and not
  tracked/untracked state.
- Consequence: active Gunnery should distinguish overlay versus takeover by the
  tracked fullscreen behavior, not by a menu-name allowlist. A third-party menu
  that leaves Helper's default fullscreen classification will conservatively be
  treated as a takeover; that is an API-contract limitation rather than a reason
  to make unknown names destructive.

### Takeover timing and Map layer collision

- X4: 9.00
- Status: shipped-source
- Source: `ui/addons/ego_detailmonitorhelper/helper.lua:1423-1436,1907`;
  `ui/addons/ego_detailmonitor/menu_map.lua:1051-1055,6595-6617`;
  `ui/addons/ego_viewhelper/viewhelper.lua:58-70,101-168`
- Live test: required. Polling cannot run between `TrackMenu` and synchronous Map
  frame creation. Verify that takeover hiding/restoration has no visible one-frame
  overlap or input leak, and verify the first safe render tick after takeover
  closure. Also verify camera continuity; the view-registry path itself contains
  no Gunnery camera operation, but engine composition is runtime behavior.
- Finding: fullscreen tracking is established before a menu's `onShowMenu` builds
  its frames, and removal occurs during Helper close. No shipped Lua callback was
  found that announces a fullscreen-classification transition; shipped code
  polls `IsFullscreenMenuDisplayed`.
- Finding: Map uses layers 6, 5, 4, and 2. If a persistent Gunnery overlay uses
  Helper layer 4, Map's `Helper4` registration replaces the Gunnery registry
  entry by ID without invoking Gunnery's clear callback. The Lua frame handle and
  session can therefore become stale relative to the View registry.

### Project lifecycle boundary for issue #117

This section is a project design consequence of the evidence above, not an X4
engine fact by itself.

- An already-engaged Gunnery session should own a persistent custom-type overlay
  separately from ordinary Helper-menu ownership.
- Opening an ordinary external overlay must not end the session, hide/rebuild the
  Gunnery overlay, or restore the player camera merely because the menu name is
  unknown.
- A displayed fullscreen-tracked menu is a generic takeover: temporarily hide
  only the Gunnery overlay while preserving the session, target, selected groups,
  engagement mode, POV, and camera, then restore visibility when no fullscreen
  takeover remains.
- Current Map-named lifecycle states/branches can be generalized to takeover
  visibility. Map `on_menu_cleanup` and reopen-by-name are not the generic
  lifecycle boundary once fullscreen polling is live-proven.
- `cleanup()` should remain an unexpected-loss/orphan-safety path, not the normal
  detector for legitimate external menus.
- Physical-console pre-open handoff safety remains separate: issue #118's
  incomplete handoff can still be cancelled if another menu intervenes before
  Gunnery is fully engaged.
- Issue #116 world left-click target synchronization and
  `CloseMenusUponMouseClick()` behavior remain preserved requirements.

### Remaining live acceptance questions

1. With Gunnery engaged in a custom-type persistent overlay, normal world
   InteractMenu must render and receive input above Gunnery without changing the
   Gunnery camera, hiding panels, ending the session, or rebuilding on close.
2. A fullscreen takeover such as normal Map must cause only overlay visibility to
   suspend and restore, with no visible transition artifact, input leak, session
   recreation, target/group/mode/POV change, or camera restoration.

Until those are observed in X4, classify the architecture as source-supported,
not live-tested.
