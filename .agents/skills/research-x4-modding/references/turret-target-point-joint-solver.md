# Target-point turret joint solver

Build pin: X4 9.00 build 611726, `X4.exe` SHA-256
`19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`.
Executable inspected:
`/mnt/c/Program Files (x86)/Steam/steamapps/common/X4 Foundations/X4.exe`.
All addresses below are RVAs; no analyst labels are native function names.

## Internal pivot and pitch input

- X4: 9.00 build 611726
- Status: inference
- Source: build-pinned static trace, route `0x0081C580` → `0x007569A0` →
  `0x00E221A0` → `0x00E21110` / body at `0x00E2132D` → `0x00E1F840`;
  disassembled using PE `.pdata` runtime-function ranges, including split
  ranges, with Capstone `skipdata=True`.
- Live test: no — static trace only
- Finding: in position mode, both joint calculations use a direction derived
  from the actual target point relative to the internal pitch-joint pivot.
  Pitch carries this same direction through the downstream angular-solving
  frames; it does not reconstruct a target direction from the prospective muzzle.

For the mounted, deployed, non-firing two-joint boundary in
[offline transform semantics](barrelposition-offline-transform-semantics.md),
use the row-vector split from `scripts/barrelposition_evaluator.py`:

```text
T = L ∘ Rx(-p) ∘ G ∘ Ry(y) ∘ H
C(y)   = t_G Ry(y) R_H + t_H
M(p,y) = (t_L Rx(-p) R_G + t_G) Ry(y) R_H + t_H
```

Here `p` is pitch, `y` is yaw, and each fixed segment has translation `t`
and rotation `R`. `C` is the pitch-joint origin; `M` is the muzzle position.
The caller forms `P - C(y)`, normalizes it in turret component space, and
zeros components whose magnitude is below `1e-3f`. The solver renormalizes.
See the [yaw reference](turret-yaw-resting-point-gate.md) for the existing yaw
map and zeroing details.

| RVA | Relevant operation |
|---|---|
| `0x00E222F6` | Obtain the internal transform associated with the pivot |
| `0x00E223BA` | Subtract the transformed pivot from the supplied target position |
| `0x00E22425–0x00E22460` | Component zeroing after normalization; solver renormalization begins at `0x00E2123E` |
| `0x00E216BE–0x00E2176B` | Downstream target/reference-axis frame transformations |
| `0x00E21B66–0x00E21B79` | Reference-axis pitch angle |
| `0x00E21B7C–0x00E21BC2` | Target-direction pitch angle and degenerate-projection handling |
| `0x00E21D1B` | Subtract reference angle |
| `0x00E21D49–0x00E21E0F` | Authored-limit handling |
| `0x00E22024` | Call joint mover |

Let `u` be `normalize(P - C(y))` after that zeroing/renormalization, and let
`a_L` be the rest launch/reference +Z axis in the pitch-joint frame. At a
settled two-joint solution, away from degenerate projections and before
wrapping/limit handling:

```text
u_G = u (R_G Ry(y) R_H)^T
p_requested = atan2(u_G.y, u_G.z) - atan2(a_L.y, a_L.z)
```

The downstream frame uses the solved upstream rotation. These equations
describe the settled relationship, not transient mover state or a guarantee
that every target has a unique settled pose.

## Information lost by substituting a muzzle ray

- X4: 9.00 build 611726
- Status: inference
- Source: algebra over the pivot input and accepted transform above
- Live test: no — mathematical counterexample only
- Finding: a muzzle-origin `useaimtarget` direction does not generically
  determine the pivot-origin direction needed by the joint solver.

If the query supplies unit direction `d` with unknown positive distance `λ`:

```text
P = M(p,y) + λ d
P - C(y) = (M(p,y) - C(y)) + λ d
```

The unknown distance is inside the vector sum before normalization. It cannot
generically be discarded when the muzzle-to-pivot offset is transverse to the
ray.

### Minimal counterexample

Choose synthetic geometry within the supported two-joint transform structure:
identity fixed rotations, both pivots at the origin, rest launch axis `+Z`,
`t_L = (0, 1, 1)`, limits containing the required angles, and yaw zero. Then:

```text
M(p) = (0, cos(p) + sin(p), cos(p) - sin(p))
M(0) = (0, 1, 1)
```

Each static target has exactly one aim point:

| Target | Aim point | Direction from M(0) | Pivot-based pitch request (radians) | Corresponding muzzle, approximately |
|---|---|---|---|---|
| A | `(0, 1, 2)` | `+Z` | `atan2(1, 2) = 0.463647609…` | `(0, 1.3416407865, 0.4472135955)` |
| B | `(0, 1, 11)` | `+Z` | `atan2(1, 11) = 0.090659887…` | `(0, 1.0864289525, 0.9053574604)` |

The muzzles differ by approximately `0.524432 m`. Values are mathematical
evaluations of the decoded relationship, not bit-exact native measurements.
The query inputs are integer coordinates with exactly collinear `+Z`
differences; the required native pitches are far from zeroing/snap thresholds.

Directly substituting the returned muzzle direction for the joint input,
starting at pitch zero, yields `+Z`, keeps pitch zero, and recomputes the same
muzzle. Repetition therefore stays at a stable but incorrect fixed point for
either target. There is no selector tie or switch, bounding box, or hidden
mover-state ambiguity in this example.

This disproves the direct muzzle-direction-to-pose fixed-point substitution.
It does not disprove another query strategy that obtains additional
information: a displaced query can distinguish these two single-point targets.

## Rotation-Z request and the arrestor-dish root clock

- X4: 9.00 build 611726
- Status: inference
- Source: build-pinned static trace. Solver type dispatch at `0x00E217E8`
  (restriction type 4 → `0x00E21B66`, 5 → `0x00E219BA`, 6 → `0x00E2180C`);
  the solved angle is stored at slot `[rsp+0x38+4·type]` (`0x00E21E20`), and
  type 6 lands in the slot rebuilt through `0x01750210` as the Z rotation. The
  reference comes from `0x0081C5BC` (`[turret+0x2F0]`) → `0x007569A0` →
  `0x0074BE30`, and the pivot from caller `0x00E222D5`. IK chain membership
  comes from builder `0x00889CB0`: `iklink` tag id `[0x0395CCA4]`, and the
  unrestricted-connection skip at `0x0088B503`. A float32 emulation of the
  solver's straight-line vector code (`0x00E211C0–0x00E21776`, not committed)
  checked the frame. Analyst labels only; no native names.
- Live test: no — static trace and offline emulation only
- Finding: a `rotation_z` restriction is solved with the same shared code as
  X and Y. Only the plane changes. Before dispatch, the target direction `u`
  and the reference axis `a` are both expressed in the joint connection's
  **rest** pre-joint frame, with the already-solved upstream rotations
  composed. Then:

```text
β_z      = atan2(a.x, a.y)                        0x00E2180C, no guard
target_z = β_z                     if |u.x| < 1e-4f and |u.y| < 1e-4f
         = atan2(u.x, u.y)         otherwise       0x00E21822–0x00E2185B
request  = fmod(target_z - β_z, 2π) (+2π if < 0)  0x00E21D1B–0x00E21D44
```

`atan2` here is the CRT `atan2f` at `0x01A1A398` (first argument `y`). With
`J_C.R = Rz(-v_rz)`, a request `θ` maps the joint's local `+Y` to clock
`(sin θ, cos θ)`. The joint therefore turns its local `+Y` toward the
target's `xy` projection, measured from `+Y` toward `+X`. The reference side
has no degenerate-projection guard, but the target side does.

`a` is the launch connection's `+Z` row from `0x0074BE30` with a zero
instance argument and a zero scene flag. That path never reaches the
restriction-state composition `0x00E22B70` → `0x00E20370`, so `a` is the rest
axis. The flag-gated `0x00757BC0` rotation on the same path is not decoded.
It reads connection matrix data, not the `0x680` IK records.

`u` is the caller's zeroed direction `normalize(P - C)`, with `|u_i| < 1e-3f`
set to `+0`, renormalized by the solver. `C` is the origin of the **last
connection in the IK chain**, taken at the current joint state. A connection
joins a chain only if it has restrictions, so a trailing unrestricted
`iklink` part (common in official and SWI turrets) is never the pivot.

Arrestor dish (`turret_arrestor_dish_macro`, SWI 0.9.1 HF source geometry):
every rotation on the path is identity. The chain is `[Connection02 Z,
Connection03 X]`, and `Connection04` is excluded. Therefore:

```text
a      = (0, +0, 1)  →  β_z = 0        (a.y = +0; see below)
C(z)   = (2.74807·sin z, 2.74807·cos z, 0.874849)   z = current root angle
u      = zero_renorm(normalize(P - C(z)))           component frame
Z(z)   = 0                         if |u.x| < 1e-4f and |u.y| < 1e-4f
       = atan2(u.x, u.y) mod 2π    otherwise
```

`a.y` is a sum containing the term `a_rest.y · 1`. For identity rotations
built from constants, zero Euler angles, or an identity quaternion,
`a_rest.y = +0`. In round-to-nearest, a zero sum with one `+0` addend is `+0`.
The emulation confirmed `β_z = 0` for all 128 signed-zero patterns of the
root frame's off-diagonal entries and `a.x`. So the reference cannot introduce
a `π` branch. The `1e-3f` zeroing can still produce the exact `0` or `π`
requests of `atan2(±0, ·)` and `atan2(·, +0)`. The mover unwraps the request
to within `π` of the current angle, as for yaw.

Remaining unresolved, not chosen here:
- `C` rotates with the current root angle, so the request is a map `Z(z)`,
  not a function of `P` alone. Its structure matches the yaw map in the
  [resting-point gate](turret-yaw-resting-point-gate.md), with the pivot offset
  `f = 2.74807` along the clock direction and `κ = 0`. The settled clock and
  its hidden-state dependence have not been analysed for this joint.
- The `0x003DB8A0` caller transform is still undecoded, as recorded for yaw.
- No live measurement confirms handedness or the settled pose.
