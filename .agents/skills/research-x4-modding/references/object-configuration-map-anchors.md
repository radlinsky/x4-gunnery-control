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
- Live test: no — untested as of 2026-09-28
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
- Limitations: practicality is static inference. Existing X4Native capture
  demonstrates a reusable third-party host, not these hooks. ABI, frame/slot
  association, descriptor variant and visible-pivot correspondence need LIVE
  verification before accepting subpixel residuals. Dense picks can measure
  sampling bias but cannot alone establish rendered-anchor coincidence.

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
