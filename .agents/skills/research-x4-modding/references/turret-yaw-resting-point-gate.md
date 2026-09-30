# Target-only turret yaw resting-point gate

Build pin for every record below: X4 9.00 build 611726, `X4.exe` SHA-256
`19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`.

The prototype is `scripts/yaw_rest_gate.py`. It uses the accepted A9 path split
(`barrelposition_evaluator.joint_segments`) and needs only turret geometry plus
a target point in turret component space. It is not a per-turret exception
system and chooses no product behavior for the `several` or `none` results.

## Decoded yaw target map

- X4: 9.00 build 611726
- Status: shipped-source
- Source: aim caller `0x140e221a0` (pivot, direction, component zeroing
  `0x140e22425..0x140e22460`, constant `0x142cbe0f8`), rotation solver
  `0x140e2132d` (renormalize `0x140e2123e`, yaw atan2 and zenith rule
  `0x140e219ba..0x140e21a12`, wrap `0x140e21d35`, limit skip `0x140e21d49`),
  mover `0x140e1f840`
- Live test: no — static trace; the engine dynamics were emulated offline
- Finding: with row vectors, `A9 T = L ∘ Rx(-pitch) ∘ G ∘ Ry(yaw) ∘ H`, and the
  yaw target the solver computes from the current yaw `y` is:

```text
pivot(y) = (t_G·Ry(y))·R_H + t_H        pitch-joint origin (moves with yaw only)
d        = normalize(target - pivot(y))  turret component frame
d_i      = 0 where |d_i| < 1e-3f; renormalize
dH       = d·R_Hᵀ
F(y)     = 0                              if |dH_x| < 1e-4f and |dH_z| < 1e-4f
         = atan2(dH_x, dH_z) - β          otherwise
β        = atan2 of the rest-pitch +Z aim axis (L's +Z row · R_G) in the yaw frame
```

The mover unwraps the target to within π of the current yaw and moves toward
it. All 92 corpus yaw joints are unlimited: both authored limits are below
1e-4 rad, so the solver and mover skip clamping. The prototype fails closed on
authored yaw limits.

Yaw never depends on pitch, pitch limits or the pitch mover: the pivot depends
on yaw only, and pitch is solved after yaw. The resting-point count is
therefore a property of this one-dimensional map.

Inference boundaries:
- The zeroing frame is the turret component frame. The caller subtracts the
  pivot after both are moved by the `0x1403db8a0` transform, then rotates the
  difference back by that transform's inverse rotation. The role of
  `0x1403db8a0` itself is not decoded.
- β uses the #164 endpoint's +Z axis. The engine reads the current launch point
  `[weapon+0x2f0]`, whose +Z axis differs by at most 0.0067° across a turret's
  laser launch points.

## Resting point definition

- X4: 9.00 build 611726
- Status: inference
- Source: the decoded map above; mover `0x140e1f840` snap (`|target-current| <
  1e-4f` at `0x140e1f944`) and its land-on-target step (`0x140e1fa90..0x140e1fac1`)
- Live test: no — offline emulation only
- Finding: let `g(y) = F(y) - y` wrapped to `[-π, π)`. Yaw moves toward
  `sign(g)`.
  - An **attractor** is a yaw where `g` changes from positive to negative.
  - Near its target the mover either snaps (distance under 1e-4f) or lands
    exactly on it. Landing needs `|y + v·dt - t| < v·dt` and
    `|v - v_desired| < acceleration·dt`. The first test compares against the
    signed step, so only positive-velocity steps can land. Negative approaches
    reach the snap window by ordinary steps. The `y ← F(y)` iteration argument
    is therefore exact only for landing or snapping frames. The retarget
    emulation below uses the exact rule and matched every rest and trap it
    tested.
  - A **resting point** is an attractor where `|g| < 1e-4f` and `|F'| < 1` on
    both sides.
  - Any other attractor is a **trap**: the turret is drawn there but never
    settles. It either holds the target astern (`|g|` near π) or oscillates
    (`F' ≤ -1`).

  Classes count resting points only: `one` = exactly one; `several` = more
  than one; `none` = no resting point, with or without traps. The gate also
  returns `state_independent`, true only for `one` with zero traps.

  Without zeroing, with pivot offsets κ (lateral) and f (forward) in the yaw
  frame, target horizontal distance ρ from the yaw axis and `s = sqrt(ρ² - κ²)`:
  - the fixed point has slope `F' = -f/(s - f)`;
  - it rests for `s > max(0, 2f)`;
  - it oscillates for `f < s < 2f`;
  - it is held astern for `0 < s < f`;
  - no fixed point exists when `ρ < |κ|`.

  The second geometric solution, present when `s < -f`, always repels.

## Analytic gate

- X4: 9.00 build 611726
- Status: inference
- Source: `scripts/yaw_rest_gate.py`; algebra over the decoded map
- Live test: no — validated against an independent dense oracle and mover emulation
- Finding: `target - pivot(y)` is affine in `(cos y, sin y)`. Between events the
  zeroing mask and zenith flag are fixed, and `sign(g)` equals the sign of
  `dH_x cos(y+β) - dH_z sin(y+β)` (`-sin y` on a zenith arc), a trig polynomial
  of degree ≤ 2.

  Every event is a root of such a polynomial, found as roots of a quartic in
  `z = e^{iy}`:
  - zeroing boundaries: `d_i² = (1e-3f)²|d|²`;
  - zenith boundaries per mask: `dH_x² = (1e-4f)²|d_masked|²`, same for z;
  - fixed points and antipodal flips per mask;
  - yaw 0 and -π on zenith arcs.

  The circle is cut at those roots and `sign(g)` is evaluated once per arc. The
  one-sided `g` and the analytic `F'` at each positive-to-negative cut give
  rest or trap. No angle scan is used.

  Events closer than 1e-9 rad are merged: they are below the engine's float32
  yaw resolution, and extra cut points cannot change an arc sign count. Near-unit
  roots are accepted within 1e-6 of the circle for the same reason. Threshold
  constants are the executable's float32 values. The gate evaluates in float64,
  so inputs within float32 rounding of a threshold or of `F' = ±1` are
  indeterminate in X4 itself.

## Validation scope and results

- X4: 9.00 build 611726
- Status: inference
- Source: offline validation over official 9.00 source sets and ANI resources
  (not committed); independent geometry extraction and dense 200k-sample map
  (refined to 4M where needed), bisected one-sided limits, finite-difference slope
- Live test: no — 2026-09-14 offline only
- Finding: all 92 conventional-combat candidates, 7,491 samples:
  - earlier two-solution samples: 735;
  - close targets inside 1.2× pivot radius: 3,680;
  - ordinary: 920;
  - near-zenith: 492;
  - axis-aligned: 368;
  - rest exactly at ±π: 92;
  - zeroing-boundary stress at `|d_i| = 1e-3(1±1e-2, 1e-5, 1e-8)`: 552;
  - zenith-boundary stress at `1e-4(1±1e-2, 1e-6)`: 368;
  - tangency stress at `ρ = |κ|(1±1e-3, 1e-6)`: 156;
  - `s = f(1±…)`: 64;
  - `s = 2f(1±…)`: 64.

  Gate classes: one 5,894 / several 784 / none 813.

  The oracle agreed on class and on rest and trap positions (within 1e-4 rad)
  for 7,485 samples. The 6 disagreements are all `ρ = |κ|(1±1e-6)` tangency
  samples on macros whose authored lateral pivot offset is float residue
  (`|κ|` 1.2e-6..2.4e-6 m), with the target within a few µm of the yaw axis.
  The gate's analytic slope there is `1 - F'` = 1.5e-10..4.8e-9, below the
  oracle's finite-difference precision. The neighbouring repeller lies within a
  few 1e-9 rad, so X4's float32 evaluation cannot resolve those samples either.

  Decoded-mover emulation over 552 close targets with random starts at three
  speed/frame-time settings:
  - `one`: settled at the gate's resting yaw in 3,598 of 3,600 runs; the other
    2 runs were caught in the trap the gate also reported for that target
    (`turret_kha_m_beam_01_mk1_macro`);
  - `several`: settled at one of the gate's resting yaws in 522 of 522;
  - `none`: never settled in 846 of 846.

  No-rest confirmation: 93 sampled `none` targets never settled in 372 runs.

## Consequences and remaining unknowns

- X4: 9.00 build 611726
- Status: inference
- Source: same offline validation; prospective pitch and muzzle from the A9 transform
- Live test: no
- Finding: the settled yaw depends on the target alone only for `one` with zero
  traps (`state_independent`). The other results depend on hidden state:
  - `one` with one or more traps: current yaw and mover velocity decide whether
    the turret reaches the resting point or stays caught in a trap. The census
    found 18 such samples.
  - `several`: current yaw and mover velocity select between valid resting
    points.
  - `none`: no settled yaw exists.

  Neither current yaw nor mover velocity is production-readable. Across the 784
  `several` samples:
  - the authored pitch-arc result differed in 66;
  - the prospective muzzles differed by more than 1 m in 662, up to 114.4 m;
  - the muzzle-to-target range differed by up to 27.7 m, with targets up to
    3,978 m away.

  Range, arc and line-of-fire outcomes can therefore all differ. Line of fire
  was not evaluated offline.

  No product policy for `several`, `none` or `one` with traps is chosen here.

## Yaw mover state across target changes

- X4: 9.00 build 611726
- Status: shipped-source
- Source: static trace of `X4.exe`:
  - IKValue record (0x680 stride, RTTI `U::IKValue`): constructor
    `0x140e6acc0`, virtual setter `0x140474620`;
  - `Turret` per-frame update, vtable slot 674 `0x1408132d0`;
  - aim `0x14081c580` → `0x1407569a0` → `0x140e221a0` → `0x140e21110`/`0x140e2132d`
    → mover `0x140e1f840`;
  - stop `0x14081c7a0` → park `0x140756a80`;
  - MD `AimTurretAction` `0x140bd0b20` and `TurretAction` stop event `0x9af`;
  - `Turret` vtable slot 683 `0x14080ca10`.
- Live test: no — static trace only
- Finding: normal turret retargeting does not reset the yaw mover.
  - Fields: angle `+0x08` and velocity `+0x18` persist between calls.
    - `+0x10` stores the last step time and only blocks a second step in the
      same frame; the step length is the global frame delta.
    - `+0x1c` is rewritten on every call from the current angle and the new
      yaw target, so it carries no target history.
    - `+0x21` selects the angle unwrap.
  - Writers: angle and velocity are written only by the constructor (all
    zero) and by the mover. The setter writes angle and time. An audit of every
    function that walks the 0x680 IK records found no other angle or velocity
    write.
  - Each frame, `Turret::Update` either aims at the current target or calls
    stop.
    - Aim does no mover initialisation. On the first aim it only sets
      `[turret+0x354]` and posts an event. The solver then calls the mover with
      `instant = 0`.
    - Stop calls park with `instant = 0`. Park steps every joint toward angle 0
      with the ordinary mover step. It is not a reset: a turret idle long
      enough ends at yaw 0 with zero velocity, while a shorter gap leaves it
      part way.
    - Aiming at a new target therefore starts from the current angle and
      velocity, whether it follows another target directly or after some
      stopped frames.
    - Slot 683 calls stop and then only reads the IK records to estimate the
      settle time.
  - The mover's `instant` snap is set only on a separate DockingBay-owned path
    (`0x140544cc0`), not on the turret update or MD aim paths.
  - The mover's 7th argument is the target's angular rate `(r × v)/|r|²`,
    projected onto the joint axis. It is added as a velocity feed-forward and
    is zero for a static target.

- X4: 9.00 build 611726
- Status: inference
- Source: offline float32 emulation of the traced mover and park step on the
  decoded yaw map, using the gate's test geometry (not committed). Checked first
  against ordinary behaviour:
  - a `state_independent` target settled at its rest from 60 random states;
  - `s = 5, f = 2` rests and `s = 3, f = 2` never settles, under three
    synthetic speed/acceleration/frame-time settings.
- Live test: no
- Finding: the prior mover states used were only those the traced paths can
  produce:
  - freshly constructed, or fully parked (`0, 0`);
  - settled on an ordinary previous target (8 bearings), then retargeted;
  - interrupted after 5, 20 or 60 slewing frames;
  - stopped for 10, 60 or 240 frames before retargeting.

  Same turret, same target, only the prior state varied:
  - `several`: pivot `(0, 1, -5)`, target at `ρ = 3`, bearing 0; rests at 0
    and -π. From (0, 0) or most prior targets the turret settles at yaw 0.
    Settled on a target at bearing 180°, it stays at -π indefinitely (spread
    7e-7 rad, zero velocity) in all three settings.
  - `one` with a trap: pivot `(1, 1, 2)`, `β = π/2`, target `(1, 20, 2)`. From
    (0, 0) it settles at yaw 0. With a fast setting (3 rad/s, 10 rad/s², 30 Hz),
    settled on a target at bearing 45° first, it never settles (0.9 rad
    oscillation over 20,000 frames); 23 more prior states also failed to
    settle. With the two slower settings every prior state settled at 0.
  - `none`: pivot `(0, 1, 2)`, target at `ρ = 1`, bearing 0.7. No run settles,
    from any prior state.

  `state_independent` therefore marks a real limit, not an artefact of assumed
  arbitrary state. The only deterministic start is fresh construction or a
  complete park. Whether a turret has parked completely depends on
  unobservable mover state and how long it has been stopped. A
  moving target's feed-forward also perturbs the start state.
