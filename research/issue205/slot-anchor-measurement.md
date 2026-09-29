# Task 4: measuring configuration-map slot anchors

2026-09-28; starting head `3f1223df2b753c4622d99cb19d7aa55157c05902`.
[Issue 205 and comments](https://github.com/radlinsky/x4-gunnery-control/issues/205)
and [draft PR 206](https://github.com/radlinsky/x4-gunnery-control/pull/206)
were read before the investigation. This task changes research only.

**Recommend exact native anchor capture for Task 5.** There is a bounded,
source-supported interception route carrying the slot-icon pivot, camera pose,
and effective matrix data together. Reuse the existing disposable X4Native
capture pattern; no new injector or general renderer exploration is needed.
Practicality is **`inference`**, not a working or live-tested new probe. No
supported Lua getter for this configuration-map anchor was found.

Dense isolated picking is a useful fallback for measuring sampling bias, but
picks alone cannot prove that a pick-region center equals the rendered pivot.
Do not turn a converged pick centroid into an exact-anchor claim.

## Evidence and scope

All native addresses below are RVAs for X4 9.00 build 611726. The installed
`version.dat` is `900`; executable SHA-256 was verified in this task, before
using the previous addresses:

`19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`

Executable: `/mnt/c/Program Files (x86)/Steam/steamapps/common/X4 Foundations/X4.exe`.
PE image base is `0x140000000`; resolve the **running** module base for ASLR.
Analyst function descriptions below are labels, not recovered engine names.
Static executable conclusions are `inference` throughout.

The 81 cached shipped UI Lua files in ignored
`.x4-research-cache/issue118-uiall-9.00/ui/` all match the latest installed
base-catalog MD5 entries. Principal catalog-relative sources, all in `08.cat`:

| Source | Catalog MD5 | Evidence |
|---|---|---|
| `ui/addons/ego_detailmonitor/menu_ship_configuration.lua` | `16c40d9cc8af7c9dc9eb7f932f0a0a79` | `shipped-source`: slot picks return type/ordinal, not coordinates; creation/update/input route at lines 9938–9968 and 10107 onward. |
| `ui/addons/ego_detailmonitor/menu_map.lua` | `505d57156f76d9e531277396ddcd81e4` | `shipped-source`: `HoloMapState` is six offset floats plus distance, lines 466–469. |
| `ui/addons/ego_detailmonitorhelper/helper.lua` | `24d93d512c5df7f7ed659b12b0107a01` | `shipped-source`: actual widget dimensions/offsets and frame origin determine render bounds, lines 861–877. |
| `ui/addons/ego_interactmenu/menu_interactmenu.lua` | `81b305bcce091520e3171244a2124f8d` | `shipped-source`: `GetCompSlotScreenPos` supplies gamepad interact-menu placement, lines 3382–3394. |
| `libraries/common.xsd` | `de2c08eabd2f3e22d705ed473b7940ce` | `shipped-source`: `raise_lua_event` supports a scalar number, string or component, not a table. |

The diagnosis, fit script, all six retained scans and exclusions in
`refine_scans.json`, and current `turretholo.lua` were reviewed. Their historical
centroids remain **experimental observations interpreted as `inference`**;
this task performed no new LIVE reproduction or evidence promotion.

## A. Lua/UI route

**`inference`, bounded negative search:** no configuration-map matrix getter,
slot transform getter, or rendered slot-coordinate getter was found across the
81 current shipped Lua files, their FFI declarations, and the current PE export
names. The current executable has **2,378 named exports**; the KB's historical
2,493-export inventory is stale for this hash and was not used as a current
inventory. Names alone do not prove a callable signature.

The relevant distinctions are:

- `GetMapState` returns an orbit-state description, not the effective view or
  projection matrices. Selection setters change selection, not visibility of
  competing slots.
- `GetPickedMapMacroSlot` returns `{upgradetype, slot}`. It does not return the
  picked point, marker pivot, region bounds, or distance.
- `GetCompSlotScreenPos` (`0x0018A7D0`) is not the desired getter: the full
  chained function reaches the global scene camera at `0x0018AA08–0x0018AA47`,
  and truncates coordinates to integer pixels at `0x0018AA84–0x0018AA9C`.
  It takes a component/connection, with no holomap argument.
- HUD `GetComponentScreenPosition` / `GetComponentOffset`, presentation
  `GetUIAnchorScreenPosition`, and sector/ecliptic map-position queries serve
  different cameras/objects. `GetComponentClassMatrix` is class relationships,
  not a geometric matrix (Helper's class-pair consumer demonstrates this).

There is therefore no evidenced direct Lua route to an exact anchor. MD turret
`relativeposition` supplies a runtime turret-instance origin, which must be
compared with, rather than substituted for, the configuration slot pivot.

## B. Minimal native route

The following extends the actual route in `diagnosis.md`; it does not depend
on the debug-description function at `0x00983FB0`. In particular, the previous
`0x009846AF/0x00984872` FOV reads are diagnostic formatting, **not proof of
render submission**. The active descriptor route below supplies that evidence.

| Step | Minimal native evidence | Conclusion (`inference`) |
|---|---|---|
| Enter configuration view | `ShowObjectConfigurationMap2` `0x00237B30` → `0x00E1B7E0` → constructor `0x00E156F0`; vtable `0x02C2CB60` | Scope interception to this view, not the sector map. |
| Build camera | view vtable `+0x28` → `0x00E16170`; cached radius at camera `+0x98` from macro `+0x160` | Preserve exact radius; retain the earlier orbit inference. |
| Per-view slot pass | view vtable `+0x58` → `0x00E163F0`; call `0x00E16695` → `0x00E176B0` | One invocation carries the view, camera, two render-helper records and additional transform. |
| Enumerate slot anchors | `0x00E17CE1–0x00E17D04`: connection record `+0xA0`, or inline `+0x60`, copied as four float rows | Identifiable configuration-scene slot pivot exists before projection. Translation is the first row; do not assume the runtime turret or muzzle identity. |
| Submit slot icon | `0x00E18146` → `0x00DA7A50`, continuation `0x00E1814B` | Slot transform and camera are passed in the same invocation; caller filter excludes other icons and recursively submitted labels. |
| Preserve icon pivot | `0x00DA7C54–0x00DA7CC6` transforms pivot relative to camera; `0x00DA8335–0x00DA8340` retains its translation in queued icon geometry | Billboard orientation/scale need not be reconstructed to obtain the icon pivot. This does not prove texture artwork is centered on it. |
| Obtain effective matrices | `0x00DA69A0` gets map render-object descriptor through vtable `+0x20` → `0x00983E40`, copies it into helper renderer `+0x10` | Read the descriptor used by the icon, not a reconstructed FOV constant. |
| Matrix writers/consumer | `0x00F40560` writes inverse camera at descriptor `+0x40`; `0x00F414C0` writes projection `+0xC0` and `view × projection` at `+0x100`; `0x00FB33B0` consumes view rows through renderer `+0x50..+0x80` | Effective view and projection are accessible before deferred rendering. Capture projection variant `+0x140` and its combined matrix `+0x180` rather than guessing which convention final rendering selects. |

The effective FOV writer `0x00979CE0` has mode/object branches; it stores at
render-object `+0x878` (`0x00979D97`). Descriptor construction `0x00983A00`
copies that effective FOV and aspects into the matrix-building record. The
constructor's `.75` half-angle tangent is a source-derived default, not proof
that every rendered state uses it. Capturing the actual descriptor avoids this
remaining assumption without changing any projection constant.

Minimal pseudocode of the chosen submission, not copied engine source:

```text
slot_transform = connection.override_transform or connection.inline_transform
submit_icon(configuration_view, slot_transform, camera_pose, render_helper)
descriptor = render_helper.renderer + 0x10
capture(slot_transform, camera_pose, descriptor.view,
        descriptor.projection, descriptor.view_projection,
        descriptor.projection_variant, descriptor.variant_view_projection)
```

### Task 5 interception contract

Use the existing X4Native host at
`fc4b8e26d74365ca332c3b0749eb9bbe167c76a1` and the bounded-buffer/trampoline
pattern in [the orientation probe](../barrelposition-orientation-probe/README.md).
That host technique is `third-party-technique`; the older selected-connection
capture is separately `live-tested` on 2026-09-13 in
[its KB record](../../.agents/skills/research-x4-modding/references/barrelposition-live-connection-orientation.md).
Neither proves this new hook.

The smallest function-entry approach needs a context hook at `0x00E176B0`
(filtered continuation `0x00E1669A`) and an icon hook at `0x00DA7A50`
(filtered continuation `0x00E1814B`). The outer hook assigns a capture sequence,
sets thread-local view context, calls the original unchanged, then clears the
context. Copy icon data before its trampoline; format/flush outside detours.
Do not call the renderer a second time. Hooks temporarily alter control flow;
measurement must not write camera, loadout, selection or render data.
The outer call carries five pointers: view, camera, helper A, helper B, and
extra transform (fifth argument at entry RSP `+0x28`). Preserve all five.

At **entry** to `0x00DA7A50`, before any prologue (Windows x64 ABI):

| Location | Capture |
|---|---|
| `RCX` | configuration view; verify it equals outer context |
| `R8`, `R9` | resource pointer and glyph/resource ID; preserve identity and call flags/scalars for the visibility control |
| `[entry RSP+0x28]` | pointer to exact slot transform; copy 64 bytes |
| `[entry RSP+0x70]` | pointer to camera pose; copy 64 bytes |
| `[entry RSP+0x78]` | render-helper pointer; its first pointer is renderer, descriptor is renderer `+0x10` |
| `[entry RSP+0x80]` | extra-transform pointer; copy 64 bytes if non-null, retaining it separately from the main icon pivot |
| descriptor `+0x00`, `+0x40`, `+0xC0`, `+0x100`, `+0x140`, `+0x180` | six 64-byte blocks: camera transform, view, projection, combined matrix, projection variant and its combined matrix |
| descriptor `+0xCC0..+0xCD0` | near/far, effective FOV, aspect X/Y (five floats) |

A C++ detour must preserve the complete **20-argument** call, not declare only
these interesting pointers. Slots 5..20 are, in order: transform pointer,
three bools, two floats, bool, color pointer, float, camera pointer, helper
pointer, extra-transform pointer, float, three bools. First four arguments
are pointer/integer-sized; return is float. These ABI roles are static inference
and need guard/hand-off verification in Task 5. Never use offsets relative to a
compiler-generated hook's own stack frame.

Preserve exact identity, not nearest-position matching: view pointer, map
pointer at view `+0x10`, macro pointer at view `+0x250`, native connection pair,
transform pointer, and all-connections ordinal. The slot pass and
`GetPickedMapMacroSlot` use the same all-connections vector; the latter reads
its current ordinal at view `+0x520` (`0x0022FFF3`) and matches the exact pair
into a type-filtered vector (`0x002300D3–0x00230120`). **The all-connections
ordinal is not the public turret slot.** For the initial identity control,
post-call interception of exported `GetPickedMapMacroSlot` can record its
successful public `{type, slot}` beside that exact native pair. This optional
third hook avoids assigning type enums or slot IDs from spelling or proximity.
Fail closed on missing, duplicate or conflicting identity joins.

The pass selects the all-connections vector by class guard: when class-table
(`0x0256D038`) entry `+0x1c & 0xc0` is set, a checked cast (`0x007A8680`)
returns macro `+0x18` and the vector is at `+0x798`; otherwise a second
checked cast (`0x0059BDB0`, guard entry `+0x8 & 0xc0`) returns the same macro
`+0x18` and the vector is at `+0xce0`. LIVE 2026-09-29
(`ship_arg_xl_carrier_02_a_macro`): macro class 94 has `+0x1c` flags `1`, so
this XL ship takes the `+0xce0` branch; the earlier `+0x798` 'ship-macro'
label was an inference error. Entries are 16-byte pairs (connection is the
second pointer). Resolve the branch under the same class guard as the engine;
reject a macro that satisfies neither guard.
Match each icon's transform pointer to the connection's override/inline
transform pointer, then record its exact pair and zero-based vector ordinal.
Require a unique match and consistent vector size; no new accessor call is
needed inside a detour. At the public pick hook, use the selected ordinal at
that call, not the next pass's pending ordinal at view `+0x528`.

Capture only a few armed frames. Recheck hash, actual target/caller signatures,
module bounds and view vtable; expose overflow/drops. Task 5 must verify ABI,
row conventions, identity, and visible-marker correspondence before accepting
any projection residual. No hook or DLL is implemented by Task 4.

## Common measurement record: native or picking

For every run, preserve build/hash, installed probe/fixture SHA, ship ID/macro,
public slot/component mapping, capture/sample IDs, UI update/render sequence,
and timestamps. Use unescaped structured data or precision-preserving scalar
records; the current log sanitizer and decimal summaries are unsuitable.
Retain native binary32 bit patterns or round-trip decimal values, including
matrix rows, rather than formatted pixel summaries.

- **Full `GetMapState`:** all seven values before/after each measurement, plus
  requested state and settled state. Log `%.17g` from Lua numbers; at least
  nine significant digits preserve binary32 values. Native capture should read
  the exported getter using the explicitly armed holomap ID before/after the
  outer slot pass, and copy raw map translation `+0x320`, orientation rows
  `+0x360..+0x380`, distance `+0x3DC`. Its getter was traced; do not infer an ID
  from a pointer. Raw rows also expose changes hidden by Euler reconstruction.
- **Actual widget rectangle:** `GetSize(renderTarget)`, `GetOffset(renderTarget)`,
  `menu.frameData[layer].x/y`, `Helper.viewWidth/viewHeight`, UI scale, and
  resulting absolute left/top/right/bottom and width/height. Log the actual
  `Helper.getRelativeRenderTargetSize` four values passed to `AddHoloMap` and
  render texture identity. Do not use hand-repeated `holo.rt` layout constants.
- **Aspect:** record both supplied `aspectx` and `aspecty`, Lua double values
  **and float-converted FFI values**. Record measured width/height ratio
  separately; do not silently replace one with the other. Capture effective
  native descriptor aspects as well when using the native method.
- **Radius and positions:** full-precision `$Ship.size / 2` and each
  `$Turret.relativeposition.{$Ship}` x/y/z with matching ship/instance/slot.
  Native capture additionally records macro `+0x160` radius and slot transform.
  Preserve these as separate identities/values, not rounded equality claims.
  To avoid MD's implicit string conversion, scalar-number `raise_lua_event`
  replies are schema-supported: serialize one request at a time with identity
  header, x/y/z/size numeric replies and completion, then format in Lua.
  Numeric transport precision/order needs a LIVE control; tables are unsupported.
- **Stability:** freeze yaw/pitch/roll/pan; stop drag/wheel input and selection
  animation; wait for multiple identical full states. Reject measurements with
  changed state, target bounds, aspect, loadout or identity. Associate native
  matrices and anchor with the same outer invocation; a wall-clock match alone
  is insufficient. Match screenshots/picks only after proving a settled plateau.

Use several separated, visible slots (at least three, at distinct bearings)
for each ship at **one fixed rotation**, repeated at distances **1.0, 0.85,
0.2724905312**. Record actual float readback; these requested decimals are not
necessarily the returned binary32 value. Retain the M/XL fixture/loadouts. If
slots overlap or leave the viewport at a distance, record rejection; obtain an
additional fixed-rotation triplet with separated slots rather than silently
changing rotation halfway through a zoom sequence. Ray needs new precise inputs.

## C. Dense isolated picking fallback

This is a proposed method (`inference`), not an established LIVE measurement.
`SetMapRelativeMousePosition` accepts floats (`shipped-source` declaration);
its native setter `0x00233CC0` stores fractional coordinates at map
`+0x310/+0x314`, without integer conversion (`inference`). It validates -1..1;
focus/input mode can override the synthetic mouse. Downstream subpixel pick
resolution and scheduling still need LIVE proof.

1. Arm **one target slot and one window** at a time. Keep all engine slots
   present; unequipping neighbors does not prove their markers disappear.
   Turn off the probe's own overlay for photographic comparison. Selection
   alone cannot isolate picking. Choose separated slots and reject competition.
2. Survey around its visible marker, then raster the entire region at **0.5 px
   or finer** in actual widget pixels. Expand independently of the prediction
   until at least a 2 px miss collar surrounds it. Reject viewport truncation,
   disconnected/ambiguous regions or any competing slot/non-turret hit in the
   target region/collar. Do not split overlapping regions with Voronoi windows;
   that would introduce a new artificial boundary. The XL 16/17 pair at the
   historical zoom is a competition diagnostic, not an isolated-center control.
3. Convert top-left-local pixels `(u,v)` to `mx=2u/W-1`, `my=1-2v/H`.
   Preserve each exact `(u,v)`, grid origin/phase, requested normalized pair,
   float-converted pair actually supplied, intended slot, result boolean,
   returned type and slot **including misses and foreign hits**, submit/result
   update IDs and before/after state. Each unique coordinate has one weight;
   other slots' windows never contribute to this slot's result.
4. Submit a coordinate, hold it across completed updates, then read the pick;
   never assign the last pick to a newly submitted point. First alternate known
   hit/miss points to measure latency, and compare forward/reverse raster order.
   If timing cannot be associated reliably, fail the run rather than guess a
   one-frame delay. Scan duration is samples × proven update interval, not the
   old ~20-second estimate; bound/allow cancellation.
5. Compute the full hit mask, area centroid, extrema/bounding-box midpoint,
   hit/miss boundary brackets and reflection symmetry about the proposed center.
   Repeat shifted/expanded windows with the **same grid phase**; then shift phase
   by `(0.25,0)`, `(0,0.25)`, `(0.25,0.25)` px. Confirm convergence on a 0.25 px
   grid, retaining all records. Require center agreement within **0.3 px per
   axis** and explain asymmetry rather than forcing a circle or averaging it away.
6. Repeat for the separated-slot, fixed-rotation distance triplets above. Save
   unscaled screenshots of the green markers and a <=0.3 px independent marker
   center measurement, with camera/viewport provenance. If glyph/region symmetry
   or image measurement cannot establish a common center, report the result as
   **pick shape only**, and return to exact capture.

A 0.5 px grid brackets a crossed edge within 0.5 px; opposite edge brackets
can bound a symmetric center to about 0.25 px. This is conditional on complete
coverage and geometry, not a universal centroid-error theorem. Phase/convergence
controls establish the practical uncertainty. A 3–4 px effect is much larger:
3.78 px is the prior XL x residual; in a 610x403 viewport, 0.3 px corresponds
to 0.000984 x / 0.001489 y in normalized coordinates. Use the **measured**
viewport for final conversions. Replaying the old +/-12 px, 3 px-window pooling
on the retained dense hit mask quantifies its bias without new calibration.

## What the comparison establishes, and LIVE gates

With exact capture, compare three quantities independently: engine projection
of the captured slot pivot, source-derived projection of that **same pivot**,
and projection of the independently measured runtime turret origin. Then
compare the measured dense-pick centroid and photographed marker center.

- Engine matrices versus formula on the same pivot isolate camera-model error.
- Native pivot versus turret origin isolates mount/marker identity or transform
  error, which is not a camera coefficient.
- Complete isolated hit-mask center versus old pooled centroid isolates sampling
  bias; image center versus native pivot tests artwork/hotspot bias.

The matrix comparison is independent of the finite clickable region, so a
3–4 px centroid shift cannot contaminate the camera-model residual. Picking
alone can prove window/grid/pooling bias, but a persistent offset from a dense
centroid is **not by itself proof of camera error**.

Still unproven: hook ABI and successful installation; actual resource/marker
visibility; descriptor versus final rendered viewport convention (including
projection variant); native connection/public-slot join; frame association;
full-precision MD scalar transport; marker artwork centering; synthetic mouse
latency/subpixel sensitivity; isolated-region symmetry; and transfer across
Ray/M/XL and all three distances. Require correlated logs and a screenshot
control before promoting any of these to `live-tested`. No new LIVE pass is
claimed and no per-ship calibration is proposed. Stop here; Task 5 implements
only the chosen minimal measurement and Task 6 remains the correction/live gate.

## Source coverage and validation

Evidence priority is project → current shipped Lua/schema → installed extension
techniques → official sources → narrow native analysis. Installed Kuertee UI
Extensions version 900 (2026-05-10) sources provide no evidenced exact-anchor
getter in the searched map/configuration files. X4Native host revision above
provides the reusable detour technique, independently of that negative search.

On 2026-09-28 the [official modding hub](https://wiki.egosoft.com/X4%20Foundations%20Wiki/Modding%20Support/),
[Lua overview](https://wiki.egosoft.com/X%20Rebirth%20Wiki/Modding%20support/UI%20Modding%20support/Lua%20function%20overview/)
and [Breaking Changes](https://wiki.egosoft.com/X4%20Foundations%20Wiki/Modding%20Support/Breaking%20Changes/)
were checked; no documentation of the desired anchor/matrix getter was found.
The [modding forum](https://forum.egosoft.com/viewforum.php?f=181) returned a bot
checkpoint; indexed exact-name searches for `ShowObjectConfigurationMap2` and
`GetCompSlotScreenPos` supplied no replacement route. Broader GitHub/Nexus/
Workshop holomap-projection searches supplied no exact-anchor implementation.
Discord/private channels were unavailable. No community claim supplies an RVA
or strengthens the conclusion. These are scoped negative searches, not API guarantees.

Scratch PE/Capstone analysis remains ignored in
`.x4-research-cache/issue205-anchor/`; chained `.pdata` ranges were followed.
No game bytes, dumps, decompiler output, instrumentation or new permanent tests
are committed. `bash scripts/validate.sh` passed, including
`tests/test_research_x4_skill.sh`; skill `quick_validate.py` and `check-kb.py`
passed (249 records). `git diff --check` passed.
