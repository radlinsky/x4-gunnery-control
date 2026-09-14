# Live orientation of the selected `barrelposition` connection

This reference preserves the build-pinned route for measuring the live
orientation of the exact connection selected by `weapon.barrelposition`, and
the first accepted in-process measurement through that route. The disposable
probe lives in `research/barrelposition-orientation-probe/`; it is research
equipment and never a production dependency.

Build pin for every record below unless stated otherwise: X4 9.00 build
611726, `X4.exe` SHA-256
`19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`. RVAs assume
image base `0x140000000`.

## Supported API boundary

- X4: 9.00; build 611726; executable hash as above
- Status: shipped-source
- Source: pinned executable export inventory; shipped Lua, MD, schemas, and
  exported-function surface
- Live test: no — shipped-source and export-surface search only
- Finding: no sufficiently evidenced supported/public Lua or MD route, or
  exported function, was found that returns the live orientation of the exact
  internal connection selected by `weapon.barrelposition`. This is bounded to
  the pinned build and searched surface, not a universal impossibility claim.

The search was not name-only. Generic component transforms do not identify the
selected internal connection; positional offsets omit orientation; UI aim
offsets describe aiming/UI data rather than the selected connection transform;
component-detail APIs do not expose this runtime leaf pose; and turret
enumeration APIs identify turret instances, not the selected endpoint.

## Build-pinned native path

- X4: 9.00; build 611726; executable hash as above
- Status: inference
- Source: static disassembly and data-flow trace of the pinned executable
- Live test: partial — the target and wrapper-caller roles below were
  confirmed live (next record); the intermediate endpoint-selection and
  scene-composition roles were not instrumented individually
- Finding: the public-property evaluator calls the fixed-index transform path
  below.

```text
public-property evaluator call
  0x140d045cf / RVA 0x00d045cf
    -> 0x1407c6e80 / RVA 0x007c6e80
       weapon.barrelposition transform wrapper; endpoint index zero
       -> 0x1405bebc0 / RVA 0x005bebc0
          inferred endpoint selection from the weapon endpoint vector
       -> 0x14081c960 / RVA 0x0081c960
          complete runtime transform of the selected connection
          -> 0x140e22b70 / RVA 0x00e22b70
             inferred scene-backed connection/part transform composition
```

`0x140d04598` is the switch/case entry, not the call instruction; the actual
call into the wrapper is at `0x140d045cf`. At entry to `0x14081c960`, `RCX` is
the runtime weapon/turret pointer, `RDX` points to a 64-byte output transform
buffer, and `R8` is the exact selected connection pointer.

## Selected-connection transform measurement

- X4: 9.00; build 611726; executable hash as above; X4Native host
  `fc4b8e26d74365ca332c3b0749eb9bbe167c76a1`; repository head
  `5e82f38392f34b36dc9e3277b185a47c4008cd19`
- Status: live-tested
- Source: correlated X4 `debug.log` (Test Lab `AUTOGEO`) and probe
  `barrel-orientation.log` from one controlled Shooter A run, reviewed
  mechanically with `research/barrelposition-orientation-probe/validate-measurement.py`
- Live test: yes — one controlled run, 2026-09-13
- Finding: intercepting RVA `0x0081c960` and accepting only return address
  RVA `0x007c6eb1` measures the live transform of the selected connection.
  - STATUS reported hooked, target RVA `0x0081c960`, caller RVA `0x007c6eb1`.
  - 2,879 captures, sequences 0..2878 contiguous; every capture has caller
    RVA `0x7c6eb1`; capacity 32,768; no OVERFLOW.
  - Exactly three stable weapon/connection pointer pairs, one per Shooter A
    turret (Split Plasma, Split Beam, Split Laser).
  - 600 `AUTOGEO` ticks per turret, 1,800 samples. Target acquisition begins
    at tick 103, so the run spans rest, articulation, and settled/firing pose.
  - All 1,800 samples paired unambiguously to one native identity each;
    maximum public-`barrelposition` versus native translation difference
    about 0.049 mm. Translation was used only for pairing/provenance, never to
    solve orientation.
  - Orientation changed with articulation while identities stayed fixed.
    Initial-to-trained rotation: Split Plasma about 89.93°, Split Beam about
    58.30°, Split Laser about 57.65°.
  - Every basis was finite and nondegenerate; determinant about
    0.99999926..0.99999991; row-length and orthogonality errors at
    floating-point scale.

## Returned transform layout

- X4: 9.00; build 611726; executable hash as above
- Status: live-tested
- Source: pinned-binary source/runtime motion evidence, confirmed against the
  run above
- Live test: yes — same run, 2026-09-13
- Finding: the 64-byte output is four 16-byte float rows: translation, then
  right-handed `+X`, `+Y`, `+Z` basis rows. This interpretation was fixed from
  motion evidence before any prospective-muzzle residual scoring and was not
  chosen by minimizing geometry error. It says nothing about whether any
  generated muzzle prediction is correct.

## Probe lifecycle limitation

- X4: 9.00; build 611726; X4Native host
  `fc4b8e26d74365ca332c3b0749eb9bbe167c76a1`
- Status: live-tested
- Source: the probe log from the run above, collected after X4 exited
- Live test: yes — same run, 2026-09-13
- Finding: the shutdown `SUMMARY` line did not appear. This is non-blocking:
  contiguous sequences give the captured count, overflow is impossible below
  capacity and no OVERFLOW marker appeared, and `null_rejected` is not needed
  to validate accepted captures. Treat a missing SUMMARY as a lifecycle
  observation, not a failed measurement.

## Design choices

These are method decisions, not X4 facts:

- Copy the already-computed output after the original call returns instead of
  re-invoking the path, so capture timing matches the public-property request.
- The filtered caller plus `R8` pointer is the native identity. Do not assume
  `weapon + 0x08` is a UniverseID or read connection-hash fields.
- The validator checks only the reusable measurement contract. Geometry scoring
  for any turret batch lives with that batch, not in the validator.

## Reuse contract for later runs

Rerun `validate-measurement.py DEBUG_LOG BARREL_ORIENTATION_LOG` on each new
run. Pairing is order-aware: AUTOGEO samples are processed in debug-log order,
and each must match a later native capture within 1 mm, so matched captures
keep strictly increasing sequence order. Unmatched extra captures are allowed.

It fails on: missing/unhooked STATUS or wrong RVAs; sequence gaps; capture
count above capacity; OVERFLOW; a present SUMMARY with `dropped > 0` (missing
SUMMARY is non-blocking); foreign caller; non-finite matrices; a degenerate or
left-handed basis; a native weapon changing connection; missing AUTOGEO;
missing or duplicate AUTOGEO ticks; a sample with no in-order capture within
1 mm; an AUTOGEO weapon mapping to more than one native identity; or two AUTOGEO
weapons sharing one. It reports identities, determinant,
row-norm and row-dot diagnostics, AUTOGEO tick span, and maximum pairing
distance. Articulation magnitude and pose matching remain per-batch analysis.

The separate geometry gate is unchanged: independently matched pose, a residual
bound declared before scoring, and retained wrong-endpoint and
omitted-barrel-translation controls. `look_at` and projectile bore remain
diagnostic only.

## Still inference

- The intermediate endpoint-selection (`0x005bebc0`) and scene-composition
  (`0x00e22b70`) roles; only their combined output was measured.
- Behavior on other builds, other turret families, or other callers of
  `0x0081c960`.
- Why the X4Native shutdown path skipped SUMMARY.
