# Live orientation of the selected `barrelposition` connection

This reference preserves the smallest accepted route for measuring the live
orientation of the exact connection selected by `weapon.barrelposition`. It
does not specify or implement a native probe.

## Supported API boundary

- X4: 9.00; `X4.exe` SHA-256
  `19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`
- Status: inference
- Source: pinned executable export inventory, relevant native callers and data
  flow; shipped Lua, MD, schemas, and exported-function surface
- Live test: no — static binary and shipped-source investigation only
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

- X4: 9.00; executable hash as above
- Status: inference
- Source: static disassembly and data-flow trace of the pinned executable
- Live test: no — inferred function roles have not been instrumented in process
- Finding: the public-property evaluator calls the fixed-index transform path
  below. Addresses are preferred-base virtual addresses; RVAs assume image base
  `0x140000000`.

```text
public-property evaluator call
  0x140d045cf / RVA 0x00d045cf
    -> 0x1407c6e80 / RVA 0x007c6e80
       inferred weapon.barrelposition transform wrapper; endpoint index zero
       -> 0x1405bebc0 / RVA 0x005bebc0
          inferred endpoint selection from the weapon endpoint vector
       -> 0x14081c960 / RVA 0x0081c960
          inferred complete runtime transform of the selected connection
          -> 0x140e22b70 / RVA 0x00e22b70
             inferred scene-backed connection/part transform composition
```

`0x140d04598` is the switch/case entry, not the call instruction; the actual
call into the wrapper is at `0x140d045cf`.

At entry to `0x14081c960`, `RCX` is the runtime weapon/turret pointer, `RDX`
points to a 64-byte output transform buffer, and `R8` is the exact selected
connection pointer. The observed output shape is four 16-byte float vectors:
one position/affine-origin vector and three basis vectors. The raw basis-vector
order, axis signs, and handedness are not proved.

## Preferred measurement

- X4: 9.00; executable hash as above
- Status: inference
- Source: build-pinned call graph and Windows x64 calling-context trace above
- Live test: no — design decision awaiting a disposable native experiment
- Finding: intercept `0x14081c960` in process and accept a record only when its
  return address is `0x1407c6eb1` / RVA `0x007c6eb1`, the continuation in the
  fixed-index `weapon.barrelposition` wrapper. After the original call returns,
  copy its already-computed 64-byte output transform.

This observes the transform evaluation requested by the public property,
retains the exact selected connection pointer from `R8`, avoids reimplementing
endpoint selection, and avoids a second scene-transform evaluation whose timing
would require synchronization. A separate direct, read-only invocation of the
known path is a fallback, not the preferred first measurement.

The filtered public-property call plus its selected `R8` pointer is the primary
native identity evidence. Do not assume `weapon + 0x08` is a runtime
UniverseID, require a connection-hash field from the runtime connection object,
or retain other speculative fields. Any readable UniverseID or hash mapping
must be verified independently before it is used.

An ignored `.x4-research-cache/x4native/` checkout currently exists locally,
but it is local research tooling, not repository-supported infrastructure. A
future implementation must inspect it separately to determine whether it can
safely hook an address-only internal function without introducing a framework.

## Minimum acceptance boundary

A future measurement is trustworthy only after it proves:

- the exact executable hash/build guard and filtered `0x1407c6eb1` caller;
- a non-null exact selected connection pointer in `R8`;
- use of the scene-backed/live path rather than the static fallback;
- a finite, nondegenerate transform basis;
- basis-axis order, signs, and handedness by independent evidence before any
  geometry evaluation;
- unambiguous pairing with the accepted Test Lab `AUTOGEO` sample;
- captured translation agreement with public `weapon.barrelposition` strictly
  as a pairing/provenance check—never as orientation-solving or fitting input;
- an articulation change that changes captured orientation while the runtime
  turret and connection identities remain fixed.

The final geometry gate remains separate: all five scoped macros, independently
matched pose, maximum residual `<= 0.020 m`, and retained wrong-endpoint and
omitted-barrel-translation controls. `look_at` and projectile bore remain
diagnostic only.

## Open implementation uncertainties

- Raw basis-vector semantic order, signs, and handedness.
- Reliable correlation of a native capture with the Test Lab weapon/sample.
- A safe interception and trampoline mechanism.
- Whether existing ignored local native research tooling can hook this
  address-only function without adding a new framework.
