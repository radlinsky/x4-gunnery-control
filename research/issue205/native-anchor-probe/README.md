# Disposable configuration-map slot-anchor measurement

Issue 205 Task 5 **offline implementation only**. No X4 launch or new LIVE
measurement has occurred. Task 5 stays open; projection correction is Task 6.
[Task 4](../slot-anchor-measurement.md) is the design/evidence contract.

The separate `x4_config_anchor_probe` extension uses the existing ignored-local
X4Native host at `fc4b8e26d74365ca332c3b0749eb9bbe167c76a1`. It is development
equipment. **Production Gunnery Control and its package have no X4Native
dependency.** Test Lab still loads without the host: explicitly arming then
times out with an invalid record. No injector, renderer framework or dense
pick fallback is added. The M+XL fixture and projection formula are unchanged.

## What is captured

`Arm exact anchor` checks the optional probe, then waits for a hovered equipped
turret and three identical full map states. Fresh MD geometry is requested one
turret at a time: request/slot/spec header, actual ship/turret component replies,
then four **numeric** values (radius, x/y/z) and completion. No rounded MD string
positions are reused. A cancelled MD batch drains before another can start.

Only then is native capture armed with explicit request, holomap, ship,
component, public slot and macro. Exported `GetPickedMapMacroSlot` is intercepted
after its unchanged original call to join the public result to the exact native
connection pair/ordinal. The next matching slot pass captures **one** target
icon invocation. Its slot transform, camera pose, both projection variants and
combined matrices, effective parameters and call flags/scalars are copied into
one fixed record. Original calls receive every argument and retain their return
values; hook bodies do no formatting, logging, event delivery or allocation.

The native implementation guards the full executable SHA, ASLR base, image
bounds, function/caller signature fingerprints, view vtable, macro class,
connection vector, exact unique transform/pair join and icon argument roles.
The explicit holomap ID is resolved through the same read-only lookup used by
`GetMapState`: RVA `0x000CED70`, registry pointer at RVA `0x06CF1500`; verify the
Task 4 executable pin before reuse. UI and matching render pass must be on the
same thread; a different thread fails closed instead of adding synchronization
or another renderer hook. These static call roles remain `inference`.

Before/after public `GetMapState` and raw translation/orientation/distance
surround that exact slot pass. Changed camera state, unknown structures,
ambiguous joins, missing/duplicate target icons and dropped duplicates invalidate
it. Lua polls through the host's existing event bridge; this UI-thread callback
formats/flushes the record outside all detours. Camera/loadout/widget changes,
missing replies, numeric-transport failures and deadlines also invalidate it.

One `[X4GC TEST] ANCHOR_RECORD { ... }` in `debug.log` combines native data with
actual `GetSize`/`GetOffset`/frame origin, absolute and normalized bounds,
view dimensions/UI scale, texture, original `AddHoloMap` bounds/aspects and
their FFI float conversions, full map state, fresh positions and exact IDs.
Lua uses `%.17g`; native floats use round-trip `%.9g`. Request ID and both
capture sequences are explicit; `valid` means structural checks passed,
**never** that the engine interception has been LIVE verified.

The native log is the profile's
`x4native/x4_config_anchor_probe/config-anchor.log`; it retains the same
request/status/native JSON envelope. Delivery failure is reported separately.
The record includes native source/git SHA, dirty flag, build-input Lua/MD and
disabled-fixture-template SHA-256s, engine hash/build and host source pin.
Build-input hashes are provenance, not proof of what an already-running process
loaded. `fixture_sha` is the accepted unchanged fixture's source commit
`2cd5bab427a79790431dc7347ca6a6abc77d3414`; MD's `fixture_spec` is the live spawned
spec ID (`none` for free play). The launcher changes only installed `enabled`.

## Offline build

From a Windows Visual Studio developer shell, configure **from the clean
implementation commit** so provenance reports that SHA and `probe_dirty=false`:

```powershell
cmake -S research/issue205/native-anchor-probe -B .x4-research-cache/issue205-anchor-build -A x64 -DX4NATIVE_SDK="$PWD/.x4-research-cache/x4native/sdk"
cmake --build .x4-research-cache/issue205-anchor-build --config Release
```

Reconfigure after source changes; build-input hashes are computed at configure
time. The DLL stays in ignored `Release/`; no host, game, SDK, bytes, disassembly,
binary or permanent experiment tests are committed. Signature checks store
fingerprints, not executable fragments. The DLL links Windows `bcrypt` only.

Offline validation passed: MSVC x64 Release (`/W4 /WX`), Lua syntax, XML/schema
validation, the full repository validator, research-skill checks and whitespace
checks. Ignored synthetic harnesses checked original-call argument/return
forwarding, unarmed behavior, build/payload/thread rejection, guarded reads,
duplicate reporting, Lua correlation/cancellation/timeouts and camera/loadout
change rejection. The log checker accepted a synthetic complete record and
rejected invalid/truncated records. MSBuild emitted WSL UNC-path dependency
warnings; these checks do not exercise X4 or prove the inferred native ABI.

## Eventual installation and operator controls

This describes the later LIVE procedure; **do not run it for the offline task**.
With X4 exited, use `prepare-host.py install --host .x4-research-cache/x4native`
to register the two internal targets, then rebuild/reinstall that exact host as
for [the barrel-position probe](../../barrelposition-orientation-probe/README.md).
Copy this directory's `content.xml` and `x4native.json` into a separate
`extensions/x4_config_anchor_probe/`, with the built DLL in its `native/`
subdirectory. Install
the branch's Test Lab through the existing development launcher; keep the
native probe separate from both Gunnery Control extension directories. The
host requires Protected UI Mode disabled. No files have been installed here.

Once a later LIVE test is authorized, the visible controls are:

1. Open Test Lab → **Turret hologram probe** using the existing M+XL fixture/session.
2. **Markers: OFF** hides the probe overlay for a green-marker screenshot.
3. Rotate to several separated visible turret slots. Keep that rotation fixed.
4. Choose **d=1**, **d=0.85**, or **d=0.2724905312**. The exact decimal request and
   actual binary32 readback are logged separately. Let the camera settle.
5. Click **Arm exact anchor**, move over one green equipped turret slot, hold
   the mouse/camera still until `Captured; LIVE validation still required`.
   **Cancel exact capture** cancels. `INVALID: ...` rejects the measurement;
   details remain in the JSON/native log. Repeat for separated slots and each
   distance, then the other ship. Ray needs fresh precise measurements too.
6. Preserve the unscaled screenshot and both complete logs; check the log with
   `python3 research/issue205/native-anchor-probe/validate-capture.py debug.log`.
   This checks structure/identity/precision and truncation, without geometry
   scoring or accepting a projection correction.

The later installation requires one **full restart** because this delta combines
Test Lab Lua/MD changes and a new native extension. No reload/launch is requested
by this offline implementation handoff.

After the experiment, exit X4, delete only `extensions/x4_config_anchor_probe`,
run `prepare-host.py remove --host .x4-research-cache/x4native`, and rebuild the
local host if it will remain installed. Do not keep the two resolver entries.

LIVE 2026-09-29 (probe `7e6fe35`, logs in ignored
`.x4-research-cache/issue205-live/2026-09-29-7e6fe35/`): 12 captures passed
`validate-capture.py` on the XL and M fixture ships at three distances each.
Hooks, thread match, public-slot/native-pair identity, same-call association
and log delivery held. The first attempts exposed a wrong `+0x798`-only
connection branch, fixed in `7e6fe35`. MD numeric precision failed: positions
and radius arrive truncated to whole metres. `anchor-residuals.py` shows the
orbit model with tan(FOV/2) 0.75 matches the captured view-projection within
1e-6 NDC given exact inputs. Still unproven: final viewport convention and
artwork/pivot coincidence.
