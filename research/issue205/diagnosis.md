# Issue 205 projection diagnosis — 2026-09-28

The dominant error is the FOV coefficient. The smallest **source-derived**
correction is `tan(vertical_FOV / 2) = 0.75` (about 73.739795 degrees), replacing
`0.7716`. Retain the ship-origin orbit, radius scale, and linear camera distance.
This is a native-code **inference**, not a newly passed live validation gate.
The existing scan centroids cannot establish exact screen positions or an
all-pose 0.01 pass. Do not replace this constant with the joint-fit value.

Production code, `turretholo.lua`, scenario, and loadouts were not changed.
The accepted fixture remains `2cd5bab427a79790431dc7347ca6a6abc77d3414`.
Context: [Issue 205](https://github.com/radlinsky/x4-gunnery-control/issues/205)
and [draft PR 206](https://github.com/radlinsky/x4-gunnery-control/pull/206).

## Captured inputs and two offline-analysis errors

`refine_scans.json` preserves 32 usable centroids: 18 existing Ray observations,
6 M observations, and 8 XL observations. M/XL provenance includes line numbers,
scan states, counts, logged predictions, macro/size/dimensions/box centers,
fixture SHA, log header, and log SHA-256. The newest local log was
`/mnt/c/Users/PC/Documents/Egosoft/X4/51053644/debug.log`, starting
2026-09-28 16:50:33. Its research snapshot is in ignored
`.x4-research-cache/issue205-diagnosis/live-2026-09-28.log`.

Usable scans are M lines 811–823 and 903–918, XL lines 1085–1100 and
1194–1211. M lines 969–972 had no hits; XL lines 1121–1127 picked only unequipped
slot 15 with no position/prediction. Both are explicitly excluded. The preceding
M coarse scan is excluded. Each retained M/XL scan's rounded before/after state
matches. Fixture/loadout success agrees with the latest issue comment. The
captured mount positions also agree with the current shipped Cerberus and
Colossus hull connections to logged precision; no evidence implicates loadouts
or placement in the projection failure.

1. The old analysis hardcoded aspect **1.48**. Replaying the new log's *predicted*
   values, without fitting the pick centroids, recovers aspect **about 1.51365**.
   `610 / 403` reproduces all 14 predictions to a maximum **0.000079** per axis.
   A 610x403 render target is also consistent with the present window/UI config
   and the probe's scaled 700x460 layout with borders. Actual render-target
   dimensions/aspect were not logged; this is reconstruction, not a direct
   measurement. Ray's original aspect was not preserved, so applying this same
   layout to Ray is explicitly an assumption. `--ray-aspect 1.48` checks the
   historical alternative; neither alternative establishes a Ray pass.
2. `stateKey()` logs distance using `%.1f`. The XL zoomed pose's logged **0.3**
   is actually **0.27249053120613**, recovered from the last `zoom_past_limit.after`
   and independently corroborated by prediction replay. Using 0.3 creates
   false residuals up to **0.036572 x / 0.027583 y** even with the native FOV.
   Ray distances 1.1 and 0.7 remain rounded inputs: their exact values are not
   recoverable from the preserved script data. Do not turn fitted replacements
   for those unknown inputs into ship calibration.

The old Ray fit's axis RMS was about 0.0069; RMS alone hid individual errors
above 0.01. The new analysis reports maximum error on each axis for every pose.

## Engine route instead of calibration

X4 9.00 build 611726; executable SHA-256 rechecked in this task:
`19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`.
All addresses below are RVAs. Analyst descriptions are not recovered public
function names. No executable bytes or disassembly are committed.

| Question | Native evidence | Interpretation (`inference`) |
|---|---|---|
| Camera instance used by this view | `ShowObjectConfigurationMap2` export `0x00237B30`, call at `0x00237DD0` to `0x00E1B7E0`; object-view construction `0x00E156F0` and vtable `0x02C2CB60`, slot `+0x28` → `0x00E16170` | Follow the actual object-configuration view, not the sector-map camera. |
| World scale | `0x00E161D4–0x00E161DB` reads ship macro `+0x160`; `0x00E163A9` stores it in the view camera `+0x98` | Cached macro box radius, not length/2 or a fitted per-ship scale. The existing box reference establishes macro `+0x140` as the box, with radius at box `+0x20`. |
| Origin and zoom | Camera vtable `0x02C3F988`, slot `+0x30` → leaf `0x00DA1D90`; `0x00DA1D90–0x00DA1DE0` | Camera translation = negative orientation backward row × map distance (`+0x3DC`) × cached radius (`+0x98`). No box-center addition or zoom-threshold branch. |
| Returned distance | `GetMapState` export `0x0022DFC0`, read `0x0022E057–0x0022E074` | Returns map `+0x3DC` directly. |
| Written distance | `SetMapState` export `0x00234CF0`, `0x00234F16–0x00234F76` | Supplied distance is written directly to current/target distance. There is no minimum clamp here. The ordinary wheel has separate limits. |
| FOV | Map render-object constructor `0x00979160`, read at `0x009793F4` from `0x029F70F8`, store at `0x009793FC` to `+0x85C` | Binary32 FOV is `1.2870022058486938` radians = float(2 atan(0.75)). |
| Use of FOV | `0x00979D71–0x00979DAF` updates effective FOV and computes its half-angle tangent; Task 4 follows the active descriptor writer `0x00983A00` → `0x00F414C0` | Constructor default is source-derived. Effective FOV has mode/object branches and must be captured; earlier `0x009846AF/0x00984872` reads format debug text, not render arguments. See [Task 4 measurement research](slot-anchor-measurement.md). |
| Angles | `GetMapState` reconstructs Euler angles from the map orientation rows `+0x360/+0x370/+0x380`; `SetMapState` reconstructs and writes those rows | Radians and the current yaw/pitch convention agree with the captures. All captures have zero roll and pan; arbitrary roll/pan is outside this result. |

The existing source-backed box record is
[macro-box-aimtargets.md](../../.agents/skills/research-x4-modding/references/macro-box-aimtargets.md).
MD size/2 agrees with the norm of logged half-extents within 0.02% on M and XL
(the game uses a cached floating-point radius; do not infer exact bits from
rounded log dimensions). The native correction magnifies both projected axes
by `0.7716 / 0.75 = 1.0288`, with no new ship coefficients.

For zero pan/roll, let `R` be that radius, `d` the full-precision map distance,
`y` yaw, and `p` pitch. The source-derived geometry is:

```text
f = (cos(p) sin(y), sin(p), cos(p) cos(y))
h = (cos(y), 0, -sin(y))
u = (-sin(p) sin(y), cos(p), -sin(p) cos(y))
camera = -R d f
Z = R d + dot(position, f)
screen_x = dot(position, h) / (Z * 0.75 * actual_aspect)
screen_y = dot(position, u) / (Z * 0.75)
```

This projects a specified ship-local point. It does not make a picked slot's
region centroid identical to that point. An engine slot-marker anchor, mounted
turret origin, and muzzle endpoint must still be kept distinct.

## Residuals and individual hypotheses

Maximum absolute error per screen axis (-1..1), **against captured pick
centroids**, using reconstructed aspect and full XL distance; Ray distances
remain rounded. These are offline comparisons, not a repeated live test.

| Ship / pose (yaw, pitch, distance) | n | Existing max x / y | Native-derived max x / y | Native axis RMS |
|---|---:|---:|---:|---:|
| Ray-1 (-1.8084, -0.5687, rounded 1.1) | 11 | 0.017631 / 0.011593 | **0.020558 / 0.013341** | 0.007549 |
| Ray-2 (3.0293, -0.4604, rounded 0.7) | 7 | 0.015663 / 0.024304 | **0.008174 / 0.017709** | 0.006678 |
| M-1 (2.5307, -0.3491, 1) | 3 | 0.020674 / 0.008616 | **0.001628 / 0.003233** | 0.001779 |
| M-2 (-0.0288, -0.4420, 1) | 3 | 0.010873 / 0.007468 | **0.002756 / 0.003293** | 0.002434 |
| XL-1 (2.5307, -0.3491, 1) | 4 | 0.019679 / 0.013444 | **0.002627 / 0.002583** | 0.001840 |
| XL-3 (-0.5023, -0.4635, 0.27249053120613) | 4 | 0.023306 / 0.022900 | **0.012402 / 0.005862** | 0.005663 |

The native-derived model's combined axis RMS is **0.005884**, versus **0.009679**
for the existing probe model. It still fails the captured-centroid gate on
both Ray poses and XL zoom slot 16 (x). No all-ship pass is claimed.

| Individually tested hypothesis | Joint axis RMS | Result |
|---|---:|---|
| Fit just FOV, keep origin/size/angles/linear distance | 0.005615 | `tanhalf=0.75385121`; all M/XL centroids pass, Ray does not. Smallest empirical improvement, but replace it with the native constant for implementation. |
| Fit just one common size multiplier | 0.006769 | About 0.98416; worse than FOV-only and no all-pose pass. |
| Fit FOV and one common size multiplier | 0.005576 | Scale about 0.99723; negligible improvement over FOV-only, no justification for a new scale rule. |
| Fit just shared orbit translation / radius | 0.008096 | Cannot explain errors. |
| Fit FOV plus shared orbit translation | 0.005482 | Tiny offsets, no all-pose pass; not evidence for a new orbit origin. |
| Substitute actual box center (M/XL only) | 0.187428 | Strongly rejected; max 0.244852 x / 0.479465 y. |
| Substitute length/2 | 0.101697 | Strongly rejected; max 0.543039 x / 0.265352 y. |
| Fit common yaw/pitch biases only | 0.008349 | Does not resolve the gate. |
| Fit FOV and common yaw/pitch biases | 0.005554 | Negligible gain over FOV-only; no all-pose pass. |
| Degrees, swapped yaw/pitch, or reversed signs | rejected / 0.41–0.49 | Wrong visible-point geometry or very large errors. |
| Fit affine distance alongside FOV and scale | 0.005310 | More parameters, no all-pose pass; confounded with rounded Ray inputs. |
| Fit distance exponent alongside FOV and scale | 0.005188 | More parameters, no all-pose pass; does not establish a below-limit scale change. |
| Clamp XL zoom distance to normal minimum 1 | 0.292813 (XL zoom only) | Strongly rejected; max 0.407788 x / 0.324199 y. |

Leave-one-ship-out FOV fits vary from approximately 0.75154 to 0.75633.
The fitted value's variation and Ray residuals argue against adding a calibrated
runtime coefficient. Allowing Ray's distance to vary within its logging
rounding interval still leaves y maxima above 0.01; rounding alone does not
explain every residual. The script retains these as nuisance-input sensitivity
checks, not design parameters.

## What remains ambiguous, and the measurement that resolves it

`startRefine()` samples a 9x9 window around each *old predicted* location, at
3 px spacing over +/-12 px. `stepScan()` pools all hits per slot, including
samples from other slots' overlapping windows, without recording which window
produced each hit or which misses bordered them. Picking resolves one slot at
a time. Thus these averages can reflect clipping, duplicated sample density,
neighbor competition, or the geometry of the finite slot marker/pick region.
The log does not preserve the samples needed to remove these effects.

For XL zoom, native-projected slots 16 and 17 are only **about 4.82 px apart**
in the reconstructed viewport, compared with a 3 px grid spacing and 24 px-wide
windows. Slot 16's 0.012402 x residual is about **3.78 px**. Sampling bias is a
plausible explanation, not established by the aggregate log. A genuine
slot-anchor offset or effective-projection difference remains another possible
explanation. Do not absorb either into ship constants.

An exact discriminating capture, with the **same fixture and loadouts**, is:

1. At the current XL zoom pose, and at a Ray pose with widely separated slots,
   capture full-precision `GetMapState` before and after (at least nine
   significant digits for all floats), actual render-target bounds/width/height,
   and the **exact aspect passed to `AddHoloMap`**. Capture the cached radius
   and MD positions without the present decimal truncation. This removes the
   known aspect/distance uncertainties; changing zoom and rotation together
   should not be used to infer a zoom law.
2. At one fixed yaw/pitch on each of Ray and XL, capture several separated
   slot-marker anchors at distances **1.0, 0.85, and 0.2724905312**. Recording the
   engine's effective view/projection matrices and the actual rendered slot
   anchor transform in the same frame is the definitive measurement: compare
   homogeneous projected anchors to the formula above. That directly separates
   camera error from mount-to-marker-anchor offset and pick-centroid bias.
   This is a proposed native measurement, not an already available Lua getter
   or an instrumentation implementation included in this update.
3. If using picks first, record *every unique sample coordinate and returned
   slot*, including misses, on a uniform <=0.5 px grid covering the complete
   slot regions, extending until misses bound each region. Repeat at the same
   camera with shifted sampling windows. A moving centroid with an unchanged
   camera/anchor demonstrates sampling bias. Photograph/render-measure the
   isolated marker center to <=0.3 px, or use the native anchor capture if
   neighbor competition prevents an unambiguous center.

For an isolated anchor near |screen_x|=0.75, `tanhalf=.75` versus the joint fitted
`.75385121` differs by about **0.00383 normalized x**, or **1.17 px** in a 610 px
viewport. A <=0.001-axis center measurement distinguishes them. The exact
same-pose distance sequence distinguishes linear distance from an affine or
power law; opposite ship bearings distinguish a genuine orbit translation
from a screen-scale error. Existing scans lack these controls.

The next correction should use source-derived camera inputs and validate exact
anchors; this task stops at diagnosis. No game reset or new live fixture is
needed to run this offline analysis.

## Offline verification

```sh
python3 research/issue205/fit_holo_camera.py
python3 research/issue205/fit_holo_camera.py --ray-aspect 1.48
python3 -m py_compile research/issue205/fit_holo_camera.py
git diff --check
```

The script checks capture cardinality, stable logged states, native FOV value,
independent elementary perspective cases, and replay of all M/XL logged
predictions before it fits centroids. No permanent CI tests were added for
historical fixture identities. Sources used: current project, current live log,
installed shipped Lua/assets/parameters, and the hash-pinned executable.
Official wiki/forum searches for `HoloMapState` / `GetMapState projection`
returned no matching public documentation; no community claim supplies a
camera constant. A useful proposed research-skill improvement is a focused
holomap source route for these native addresses and the sample-centroid
limitations, after the exact-anchor validation; no KB claim was promoted here.
