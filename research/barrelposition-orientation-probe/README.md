# Disposable `barrelposition` orientation probe

This X4Native extension captures the raw 64-byte transform returned for the
exact connection selected by `weapon.barrelposition`. It is research equipment,
not production or Test Lab code. It does not interpret the three basis vectors.

## Why X4Native

The ignored local checkout `.x4-research-cache/x4native/` at commit
`fc4b8e26d74365ca332c3b0749eb9bbe167c76a1` already loads extension DLLs and
uses MinHook to detour internal functions, provide a trampoline, and remove the
detour when its owning hook is released. Its internal resolver uses ASLR-safe
image-base-plus-RVA addressing and verifies a byte signature. The probe adds
its own exact executable SHA-256 and path-byte guards. Reusing those interfaces
is smaller than adding an injector or hook library here.

The host does not expose an arbitrary-address hook directly. Therefore
[`internal-function.json`](internal-function.json) supplies the single ignored-
local resolver entry needed by `_ensure_detour`. Nothing from X4Native, MinHook,
or the generated host project is copied into this repository.

## Prerequisites and build

- Windows x64 C++ compiler and CMake.
- The inspected local X4Native checkout/installation and its `sdk/` headers.
- X4 9.00 build 611726 with `X4.exe` SHA-256
  `19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`.

From a Visual Studio developer shell:

```powershell
cmake -S research/barrelposition-orientation-probe -B .x4-research-cache/barrel-orientation-build -DX4NATIVE_SDK="$PWD/.x4-research-cache/x4native/sdk"
cmake --build .x4-research-cache/barrel-orientation-build --config Release
```

The build directory and DLL remain ignored. The probe links only Windows
`bcrypt` in addition to the normal runtime.

## Prepare and install for the later LIVE run

Do not do this until the commit has been reviewed. Stop X4 first.

1. Add the resolver entry to the ignored local host source, then rebuild and
   reinstall that exact X4Native checkout:

   ```text
   python3 research/barrelposition-orientation-probe/prepare-host.py install --host .x4-research-cache/x4native
   ```

2. Create `extensions/x4_barrel_orientation_probe/native/` in the X4 install.
   Copy `content.xml`, `x4native.json`, and the built
   `x4_barrel_orientation_probe.dll` into the matching locations. Do not copy
   source, the JSON fragment, or the helper.
3. Disable Protected UI Mode as required by the local X4Native loader, enable
   the disposable extension, and follow the separately reviewed controlled
   launch procedure.

At initialization the probe refuses to load unless all of these agree:

- host API/build `1`/`900`, executable module base, and PE image bounds;
- complete on-disk executable SHA-256 shown above;
- target RVA `0x0081c960` bytes
  `4c 8b dc 55 53 57 41 56 49 8d 6b a1 48 81 ec 88`;
- wrapper call/continuation bytes spanning RVA `0x007c6ea6..0x007c6eb5`;
- public-property call bytes `e8 ac 28 ac ff` at RVA `0x00d045cf`;
- X4Native's resolved address equals image base plus the target RVA.

The detour calls the trampoline first, returns its result unchanged, and only
records non-null output/connection pointers whose return address is exactly RVA
`0x007c6eb1`. Hook removal occurs during extension shutdown. The fixed capture
buffer holds 32,768 records; excess records increment a visible dropped count.

## Output and cleanup

X4Native writes the redirected extension log under the profile's
`x4native/x4_barrel_orientation_probe/barrel-orientation.log`. Each useful
payload begins with one of these parseable markers despite the host's normal
timestamp/level prefix:

```text
STATUS {"hooked":true,...}
CAPTURE {"sequence":0,"weapon":"0x...","connection":"0x...","caller_rva":"0x7c6eb1","matrix":[16 raw floats]}
OVERFLOW {"capacity":32768,"dropped":1}
SUMMARY {"captured":...,"dropped":...,"null_rejected":...}
```

Formatting and file output occur from the native frame callback, never inside
the detour. Sequence order is retained. Overflow cannot be silent.

After capture, exit X4 before removing files. Delete the disposable extension
directory and remove the ignored-local resolver entry:

```text
python3 research/barrelposition-orientation-probe/prepare-host.py remove --host .x4-research-cache/x4native
```

Rebuild/reinstall the local host after removal if it will remain installed.
The first LIVE run must still establish scene-backed evaluation, stable
weapon/connection identity, Test Lab pairing, articulation-dependent orientation
change, and independent basis order/sign/handedness. Translation agreement with
public `weapon.barrelposition` is correlation evidence only and must not be used
to solve orientation or score geometry.
