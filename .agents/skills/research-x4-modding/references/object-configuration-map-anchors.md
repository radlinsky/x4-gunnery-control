# Object-configuration-map slot anchors

Verify the executable pin in [native-analysis.md](native-analysis.md) before
using these RVAs: X4 9.00 build 611726, SHA-256
`19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`.
Analyst function descriptions are labels, not recovered engine names.
The [measurement contract](../../../../research/issue205/slot-anchor-measurement.md)
contains the complete ABI, identity, precision and LIVE controls.

### Configuration-map Lua gives picks and orbit state, not rendered anchors
- X4: 9.00 build 611726
- Status: inference
- Source: all 81 shipped `ui/*.lua` files verified against installed catalog MD5s
  on 2026-09-28; current PE export names; `GetCompSlotScreenPos` RVA `0x0018A7D0`
- Live test: no — untested as of 2026-09-28
- Finding: bounded negative search found no configuration-map matrix, slot
  transform or rendered-anchor getter. `GetCompSlotScreenPos` instead reaches
  the global scene camera and truncates coordinates to integer pixels; it has
  no holomap parameter. Current PE has 2,378 named exports; older 2,493/609
  inventory counts are stale, not a current undeclared-function count. Recount
  against the pinned executable and current Lua corpus before relying on them.

### Slot-icon submission carries pivot and effective camera data together
- X4: 9.00 build 611726
- Status: inference
- Source: pinned executable; `ShowObjectConfigurationMap2` RVA `0x00237B30`,
  configuration-view vtable `0x02C2CB60`, slot pass `0x00E176B0`, icon submission
  `0x00DA7A50`, helper `0x00DA69A0`, descriptor writers `0x00F40560`/`0x00F414C0`
- Live test: yes — 2026-09-29, probe `7e6fe35`, 12 structurally valid captures
  (XL `ship_arg_xl_carrier_02_a_macro` slots 12/16, M
  `ship_arg_m_frigate_01_a_macro` slots 1/4, three distances each); hooks,
  same-thread association, public-slot/native-pair join and one icon per armed
  pass held on every capture
- Finding: caller-filtered function-entry interception can associate a slot
  transform with camera pose and the effective render-helper descriptor in one
  slot-pass invocation. Slot-pass caller continuation is `0x00E1669A`; icon
  caller continuation is `0x00E1814B`. At icon entry, slot/camera/helper pointers
  are at Windows x64 entry RSP `+0x28/+0x70/+0x78`. Helper's first pointer is
  renderer; descriptor begins at renderer `+0x10`. Capture camera/view matrices
  at descriptor `+0x00/+0x40`, projection/combined at `+0xC0/+0x100`, and
  variant projection/combined at `+0x140/+0x180`. This is a 20-argument call;
  interesting arguments alone are not a valid detour signature. Native
  all-connections ordinal differs from public type-filtered slot numbering.
  Preserve exact connection/transform identity, not position/spelling matches.
  The public holomap ID can be associated with the native map by the exact
  read-only lookup used in `GetMapState` (`0x0022DFDE–0x0022DFEA`): registry
  pointer at RVA `0x06CF1500`, lookup `0x000CED70` with type argument 4; map
  `+0x2C0` is the view and view `+0x10` points back. This closes the ID/pointer
  join without inventing an ID from a pointer. Task-specific implementation is
  in [the disposable capture probe](../../../../research/issue205/native-anchor-probe/README.md);
  its thread and call-role guards still require LIVE proof.
  The FOV reads at `0x009846AF/0x00984872` are debug-string formatting;
  active matrix evidence comes from descriptor writers and geometry consumer
  `0x00FB33B0`. No final raster convention or artwork centering is proved.
- Limitations: artwork centering on the pivot and the final raster/viewport
  convention remain unproven; the LIVE captures validate the matrix route only.
  Earlier static-only limitations follow. Practicality was static inference. Existing X4Native capture
  demonstrates a reusable third-party host, not these hooks. ABI, frame/slot
  association, descriptor variant and visible-pivot correspondence need LIVE
  verification before accepting subpixel residuals. Dense picks can measure
  sampling bias but cannot alone establish rendered-anchor coincidence.

### Slot pass selects the connection vector by macro class guard
- X4: 9.00 build 611726
- Status: live-tested
- Source: pinned executable; slot pass `0x00E17738–0x00E17788`, class table
  RVA `0x0256D038`, checked casts `0x007A8680` and `0x0059BDB0`
- Live test: yes — 2026-09-29, XL and M ship macros above, probe `7e6fe35`
- Finding: macro class is the int at macro `+0x44`. If class-table entry
  `+0x1c & 0xc0` is set, the pass reads the all-connections vector at
  (macro `+0x18`) `+0x798`; otherwise the second cast requires entry
  `+0x8 & 0xc0` and uses `+0xce0`. Both ship macros are class 94 (`+0x1c` = 1,
  `+0x8` = 0x40) and take `+0xce0`; an earlier `+0x798` "ship branch" label was
  wrong. Entries are 16-byte {owner, connection} pairs; view `+0x520` held the
  picked all-connections ordinal (34 connections, ordinal 12 for XL slot 12).

### Holomap camera is an exact radius-scaled orbit with tan(FOV/2) 0.75
- X4: 9.00 build 611726
- Status: live-tested
- Source: captured view/projection matrices from the capture probe above
- Live test: yes — 2026-09-29, same 12 captures; distances 1, 0.85, 0.2725
  (XL) and 0.650228 (M; wheel zoom stopped there)
- Finding: projection is row-vector (`clip = [p,1]·VP`) with
  `1/tan(FOV/2) = 1.3333334` and x scale divided by the widget aspect
  (610/403). The camera orbits the ship origin at native radius × map-state
  distance using `GetMapState` yaw/pitch. With exact pivot and radius, the
  Lua-style orbit model reproduced engine NDC within 1e-6 on every capture;
  `tan = 0.7716` erred up to 0.026 NDC. Inputs, not the model, set accuracy.

### X4Native re-initializes extension DLLs on every UI reload
- X4: 9.00 build 611726; X4Native host `fc4b8e26d74365ca332c3b0749eb9bbe167c76a1`
- Status: live-tested
- Source: host log `x4native/x4native.log` ("UI reloaded — DLL re-initialized
  with fresh Lua state") and the capture probe's native sequence counter
- Live test: yes — 2026-09-29, one X4 process: sequence ran 1–12, then
  restarted at 1 after a Test Lab Reload UI on the same thread
- Finding: a UI reload reloads each X4Native extension DLL, so DLL globals
  (counters, armed state) do not survive it, although detours reinstall.
  Treat a UI reload as a new native lifetime when checking native identity or
  sequence uniqueness in one debug.log.

### Render-target bounds must come from the actual widget
- X4: 9.00
- Status: shipped-source
- Source: `ui/addons/ego_detailmonitorhelper/helper.lua:861–877`, catalog MD5
  `24d93d512c5df7f7ed659b12b0107a01`; `menu_ship_configuration.lua:9938–9968`
- Live test: no — capture precision untested as of 2026-09-28
- Finding: Helper derives normalized render bounds from `GetSize`, `GetOffset`,
  frame-layer origin and `viewWidth/viewHeight`. Configuration-map creation
  supplies an explicit aspect to `AddHoloMap`. Preserve these exact inputs,
  float conversions, full `GetMapState` before/after, radius and separately
  identified slot/runtime-turret positions; layout constants are insufficient.

When reusing a focused ignored UI cache, compare every cached file with the
latest installed catalog entry before searching it; a cache directory named
for a version does not prove current contents. Keep native scratch ignored,
follow chained `.pdata` ranges, and stop at the relevant icon/matrix path.

### Rectangle handles allow a hologram to release only its own markers
- X4: 9.00 build 611726
- Status: shipped-source
- Source: `ui/addons/ego_detailmonitorhelper/helper.lua:2441–2505` and
  `ui/widget/lua/widget_fullscreen.lua:18135–18315`; current `08.cat` MD5s
  verified 2026-09-29 (`24d93d512c5df7f7ed659b12b0107a01` and
  `2ff7e833887516a41fce99eed471da71` respectively)
- Live test: no — production resource lifecycle untested as of 2026-09-29
- Finding: `Helper.drawLine` and `Helper.drawRectangle` return the handle from
  the rectangle draw queue. `HideRect(handle)` releases that rectangle; the
  global hide-all function also clears shapes owned by other callers. The
  widget rectangle pool has 1000 slots shared across callers, and exhaustion
  returns no handle. Track successful handles and stop when allocation fails.
  An 800-rectangle local cap leaves headroom but cannot reserve it against
  another extension. Coarse marker geometry is an implementation budget, not
  a new engine limit or a live performance result.
- Finding (timing): `DrawRect` only takes an element from the pool and queues
  it. The element is positioned and switched to its `active` slide in
  `widgetSystem.updateShapes()`, which the widget update calls before
  `CallUpdateScripts()`. `HideRect` switches to `inactive` immediately. Hiding
  the old shapes and drawing their replacements in the same addon update
  therefore renders one frame with neither. To avoid that blink, draw the
  replacements first and hide the old handles on the next update, which needs
  room in the pool for both sets. Pool sizes: 1000 rectangles, 100 circles and
  100 triangles (`config.shapes`). The blink itself was live-observed on
  2026-09-29; the double-buffered cure is untested.
- Finding (id reuse): the pool is a LIFO free list, so `HideRect` returns an
  element and the next `DrawRect` hands out that same id. `HideAllShapes()`
  frees every drawn rectangle for all callers. `widgetSystem.onViewClose`
  calls it, and so does `Helper.clearMenu` (`helper.lua:1613`). After such a
  wipe a caller's saved ids are stale: hiding them logs `Widget system error.
  Cannot find rectangle with id N` while they are free, and once they have
  been handed out again it silently hides whoever now owns them. With a
  deferred hide that owner is the caller's own replacement markers. That
  explains most markers disappearing on a 101-turret ship after an overlay
  rebuild (live 2026-09-29). Treat any id you are still tracking that
  `DrawRect` returns again as proof that the tracked set was wiped.

### The production and calibration holograms share the validated projection
- X4: 9.00 build 611726
- Status: live-tested
- Source: engine-capture evidence in the radius-scaled-orbit record above;
  `research/issue205/native-anchor-probe/README.md`
- Live test: yes — Test Lab on 2026-09-29; production integration remains untested
- Finding: the accepted Test Lab camera model uses `tan(FOV/2)=0.75`, ship
  radius, full-precision orbit state and actual widget aspect. The running
  probe agreed with captured engine projection within 3.1e-5 NDC on M/XL;
  hollow markers were visually centred on occupied slot icons. Production
  `gunnery_hologram.lua` now owns the function used by the retained Test Lab
  scan/refine wrapper. This refactor does not establish production layout,
  click routing, activity transport, Ray alignment or frame cost as live-tested.

### Weapon firing and impact events expose different identities
- X4: 9.00 build 611726
- Status: shipped-source
- Source: `libraries/common.xsd:13040–13069,16836–16847` and
  `md/cinematiccamera.xml:3212`; current base-catalog MD5s verified 2026-09-29
  (`de2c08eabd2f3e22d705ed473b7940ce`, `e5fd6463519f14a0f679803cc36e883f`)
- Live test: no — the production snapshot transport is untested as of 2026-09-29
- Finding: `event_weapon_fired` names the emitting weapon in `event.object`
  and its projectile in `event.param`; group-scoped registration is shipped.
  Ship-scoped `event_object_attacked_object` names the victim in `event.param`
  and provides `[attacked component, weapon]` in `event.param3`. Match the
  explicitly selected runtime weapon and current target/component rather than
  treating any ship damage event as a hit by the selected turret. No launcher
  inference for missile impacts is established by these declarations.
