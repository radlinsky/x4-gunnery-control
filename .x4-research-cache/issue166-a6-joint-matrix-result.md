# A6 — runtime restriction-state matrix `J_C`

## 1. Verdict

**RESOLVED** for the generic semantics of `J_C` on the selected-connection scene path, and for every restriction structure present in the 92-row conventional combat corpus.

One-sentence rule: **for a restricted connection, `J_C` is `[t = (v_tx, v_ty, v_tz); R = Rz(−v_rz) · Rx(−v_rx) · Ry(+v_ry)]` (row-vector), where each `v_*` is the raw current float of that restriction's per-instance `IKValue` object (radians for rotations, no conversion), missing types are 0, and XML min/max only clamp the scalar upstream; the engine composes `L_part ∘ J_C ∘ C_authored ∘ parentWorld`, so the joint rotates about the connection origin in the connection-local frame, before the authored connection rotation.**

Scope limits:

- **inference:** the owner-level translation scale `S` (vcall `+0x1448`) is still unresolved. It is not part of `J_C`, but it scales composed translations.
- **inference:** the scene gate of `0x14074be30` is carried over from A5 unchanged.
- **inference:** how the aim solver turns a target direction into θ was not decoded. `J_C` consumes only θ.

Evidence scope:

- **shipped-source:** X4 9.00, `X4.exe` SHA-256 `19750a65…6891` (A5-verified; unchanged). Addresses are VAs, image base `0x140000000`.
- Official XML: `.x4-research-cache/official-source-sets/`.
- Working scripts and dumps are in `.x4-research-cache/issue166-a6-work/`:
  - `emu_jc.py`: SSE emulation of `0x1404b5f20`
  - `static_examples.py` and `.out`
  - `corpus_restrictions.py`
  - `*.dis`
- Function roles are **inference** unless noted. RTTI type-name strings are compiler-emitted **shipped-source** strings, not exported symbols.
- No new `live-tested` claim. No LIVE residual was used. No X4 launch, production or test edit, commit, or GitHub edit.

Notation: `A ∘ B` means apply A, then B (row vectors, `p' = p·R + t`). Matrices are rows `[t; X; Y; Z]`, as in A5. The row-vector axis matrices are A5's:

```text
Rx(a) = [[1,0,0],[0,c,s],[0,-s,c]]   Ry(a) = [[c,0,-s],[0,1,0],[s,0,c]]   Rz(a) = [[c,s,0],[-s,c,0],[0,0,1]]
```

## 2. Authored restriction layout

**shipped-source — token ids** (string/id table, same mechanism as A5's `offset/0x1b5`):

| Token | Id | Table entry |
|---|---|---|
| `restrictions` | `0x23a` | `0x1422cab90` |
| `restriction` | `0x239` | `0x1422cab80` |
| `type` | `0x2f9` | `0x1422cb780` |
| `limits` | `0x163` | `0x1422c9e20` |
| `min` | `0x190` | `0x1422ca0f0` |
| `max` | `0x17f` | `0x1422c9fe0` |
| `value` | `0x30a` | `0x1422cb890` |

**shipped-source — restriction type enum.** Static initializer `0x140922110` registers `"TemplateRestrictionType"` (`0x142b8c848`). It reads name pointers `0x142552980..0x1425529d0` and assigns values 1..6 (`mov dword …, 1..6` at `0x1409222c7..0x14092258c`). The same `(name, value)` table is also present at `0x1422c0220`:

```text
translation_x=1  translation_y=2  translation_z=3  rotation_x=4  rotation_y=5  rotation_z=6   (0 = none)
```

**shipped-source — XML → record.** Connection loader region `0x140882c57..0x140882f4a`:

```text
<connection>
  <restrictions>                                  0x140882c57  child 0x23a
    <restriction type="rotation_x">               0x140882c70  children 0x239
      <limits><min value=".."/><max value=".."/></limits>
```

```text
C+0x150 = new std::vector<Record>             0x140882c85..0x140882caf  (reserve count 0x140882cf6)
for each <restriction>:
    s = attribute 0x2f9 ("type")              0x140882d88
    type = 0x140953b10(s)                     0x140882dcb   (string→enum; 0 → record skipped, 0x140882dd4)
    push Record{int32 type; float min=0; float max=0}      0x140882df1..0x140882e12, stride 0xc
    L = child 0x163 (limits)                  0x140882e4d
    min = attr 0x30a of child 0x190           0x140882e9f..0x140882ecf  → Record+4
    max = attr 0x30a of child 0x17f           0x140882eed..0x140882f11  → Record+8
    if (unsigned)(type-4) <= 2:               0x140882ed8 / 0x140882f16
        min,max *= 0.01745329238 (float @0x142cbe1c8)       # degrees → radians, rotations only
```

**Record layout (shipped-source):** `+0 int32 type`, `+4 float min`, `+8 float max`, size `0xc`. There are no axis-vector, pivot, reference/default-value, or state-index fields. The record-to-state link is purely **positional** (§3).

- **inference:** `0x140953b10` resolves through the `TemplateRestrictionType` enum. Its internal lookup was not traced, but the enum and the 1..6 dispatch below match exactly.
- **shipped-source:** An absent `<limits>` leaves min = max = 0.

## 3. Runtime scalar provenance

### State construction (`0x140e200e0`, caller `0x140755097`)

**shipped-source:**

```text
mgr+0x00 = owner ; mgr+0x10 = vector< vector<IKValue> >  (stride 0x18)
groups = [[owner]+0x58]+0x1c8          : vector< vector<Connection*> >
for g in groups:
    N = Σ_{C in g} count(C+0x150)                    0x140e201c0..0x140e201ee  (÷0xc)
    mgr.vec.push( vector<IKValue>(N) )               0x140e6acc0, element size 0x680
    k = 0
    for C in g, for rec in C+0x150 (in XML order):
        obj = vec[k++]
        obj+0x20 = (type-1) <= 2     # translation flag     0x140e20280..0x140e2028a
        obj+0x21 = (type-4) <= 2     # rotation flag        0x140e2028d..0x140e20298
```

**shipped-source — the `0x680` object (`0x140e6acc0`):**

- vbptr table `0x142c450c0` gives a virtual-base offset of `0x678`.
- The final vtable at `+0x678` is `0x142c450d0`; its RTTI name is **`.?AVIKValue@U@@`**. Intermediate vtables have RTTI `.?AV?$ValueSource@M@XLib@@` and `.?AV?$ValueSourceInterface@M@XLib@@`.
- Initial fields: `+0x08` float = 0, `+0x10` double = 0, `+0x18` qword = 0, `+0x20/+0x21` flags = 0.

**inference:** the executable's own type name calls this a float "IK value". The owner's groups are IK chains.

### Group membership (`0x14088b503..0x14088b72b`, post-load)

**shipped-source:** Only connections with `C+0x150 != 0` are considered. The builder inspects the owning connection of C's parent part:

- If that connection is restricted, C joins the group whose last element is that connection (`0x14088b63e..0x14088b649`).
- If that connection is unrestricted, the builder walks further ancestors while they carry a tag whose id is at global `0x14395cca4` (`0x1400cb170` tag-set test, `0x14088b570`), looking for a restricted ancestor.
- Otherwise it pushes a new group (`0x14088b5e7..0x14088b5f4`).

**inference:**

- The tested tag is `iklink`: its registration at `0x1408d7e91` sits immediately before the adjacent global `0x14395cca0`.
- Every restricted connection lands in some group. `iklink` affects IK-chain grouping, not whether a restriction gets state. The append after `0x14088b72b` was not listed.

### Lookup (`0x140e20370`, called at `0x140e22bca` with out = identity)

**shipped-source:**

```text
for g in groups:                                   0x140e203f0
    idx = 0
    for C' in g:
        if C' == C: goto found                     0x140e2041a
        idx += count(C'+0x150)                     0x140e20447
return (out stays identity)                        0x140e20458
found:
    slot[0..6] = 0.0f                              0x140e2045f..0x140e20473   (float array at rsp+0x40)
    for (i, rec) in enumerate(C+0x150):
        obj = g_states[idx + i]                    0x140e20483, +0x680 per record
        v   = obj.<vbase>.vtbl[+0x28](time)        0x140e204bd
        if 1 <= rec.type <= 6: slot[rec.type] = v  jump table 0x140e20558: all six entries → 0x140e204d9
    J = 0x1404b5f20(out, slot1, slot2, slot3, stack: slot5, slot4, slot6)     0x140e204e8..0x140e20521
```

### What `+0x28` returns

**shipped-source:** vtable `0x142c450d0` slot `+0x28` = thunk `0x140e83818`:

```text
this = vbase - vtordisp[-4] - 0x658  →  jmp 0x140474600:  movss xmm0,[this-0x18]; ret
```

- The vtordisp is 0, written in the constructor at `0x140e6ada3/0x140e6adc7`. So `this = obj+0x20` and the return value is **float `obj+0x08`**.
- The `time` argument is ignored.
- There is no sign change, clamp, or unit conversion here. The six type slots feed straight into `0x1404b5f20` with no per-type transform: all jump-table entries are the same store.

### Who writes `obj+0x08`

**shipped-source:** slot `+0x18` = thunk `0x140e837d0` → `0x140474620`, which does `obj+0x08 = *(float*)rdx; obj+0x10 = xmm2 (double time)`. Traced writers:

1. **Limited/aimed mover `0x140e1f840`**
   - Callers: `0x140e22024` (rotation aim solver chunk of `0x140e21110`, itself called from `0x1407485ac`/`0x140e22497`), `0x140e20fd6` (translation solver `0x140e209a0`), `0x140756c3c`.
   - For rotation objects (`obj+0x21`), it unwraps the target to within π of the current value: `t' = ((t mod 2π) − v + π) mod 2π + v − π` (`0x140e1f8cc..0x140e1f91c`, 2π @ `0x142cbebdc`, π @ `0x142cbeab4`). It stores `obj+0x1c = t'`.
   - Immediate branch: calls the setter with `t'` (`0x140e1fb71..0x140e1fb87`).
   - Otherwise it runs a speed/acceleration-limited step with velocity kept at `obj+0x18` and integrates `v += speed·dt`.
   - If `|min| ≥ 1e-4` or `|max| ≥ 1e-4`, it clamps `v = max(min(v, max), min)` (`0x140e1fac5..0x140e1fb05`). It then calls the setter (`0x140e1fb5e`).
   - The rotation solver has already wrapped its target into `[0, 2π)` (`0x140e21d35`). When limits are nonzero, the solver clamps a target outside the arc to the circularly nearer limit (`0x140e21d49..0x140e21e0b`) before calling the mover with `(target, min, max)`.
2. **Velocity integrator `0x140e224f0`** (caller `0x140544d8d`): for rotation objects it rate-limits the velocity (`obj+0x18`), then sets `v = (v + vel·dt) mod 2π` into `[0, 2π)` (`0x140e2279e..0x140e227f6`). No min/max clamp.

**inference:** other setter callers were not exhaustively enumerated. All traced writers deliver radians: the loader stores the limits they compare against in radians, and both paths wrap and unwrap with 2π. So the scalar reaching `0x1404b5f20` is the **current joint angle in radians**, already clamped into `[min, max]` for limited joints. Zero, the constructor value, is the authored pose.

## 4. Exact `J_C` equations

**shipped-source:** `0x1404b5f20(out, a1, a2, a3, [stack+0x20]=a5, [+0x28]=a4, [+0x30]=a6)`, where `aK = slot[K]` = current value of restriction type K (0 if absent):

```text
out.t = (a1, a2, a3, 0)                                   0x1404b5f4c..0x1404b5f5a
(sx,cx,sy,cy) = sincos(a4, a5)                            0x1404b5f70  (0x141750253)
(sz,cz)       = sincos(a6)                                0x1404b5f99  (0x141750210)
out.X,Y,Z     = rows of  Rz(-a6) · Rx(-a4) · Ry(+a5)      0x1404b5f9e..0x1404b60dd
```

- **shipped-source:** The rotation body is instruction-identical to the XML `<rotation>` builder `0x14049d89d..` (A5), but here no degrees factor is applied. The inputs are used as radians.
- **inference (byte-exact check):** `emu_jc.py` replays the SSE instructions with mathematical sin/cos at the helper boundary. Among all 48 axis orders and signs, only `Rz(−z)·Rx(−x)·Ry(+y)` matches, and translation passes through unchanged.

Per corpus-relevant operation:

```text
rotation_y (type 5), value θ:  J = [0; Ry(+θ)] = [[cosθ,0,-sinθ],[0,1,0],[sinθ,0,cosθ]], t=0
rotation_x (type 4), value θ:  J = [0; Rx(-θ)] = [[1,0,0],[0,cosθ,-sinθ],[0,sinθ,cosθ]], t=0
```

Generic, for completeness (unused by the corpus):

- `translation_*` puts the raw value into `J.t`, applied after `J.R` inside `J`: `p·R + t`.
- `rotation_z` gives `Rz(−θ)`.

`0x1404b5f20` builds from identity rows. It does not pre- or post-multiply anything passed in: `out` is overwritten.

## 5. Axis, sign, units, pivot and frame

| Property | Result | Class |
|---|---|---|
| Axis | `rotation_x` → connection-local X; `rotation_y` → connection-local Y; `rotation_z` → local Z | shipped-source |
| Sign (row-vector) | `Ry(+θ)`, `Rx(−θ)`, `Rz(−θ)`. Equivalent column form: standard right-handed `Ry(+θ)`, `Rx(−θ)`, `Rz(−θ)`. For θ>0: `rotation_y` turns local +Z toward +X; `rotation_x` turns +Z toward +Y (`static_examples.out`) | shipped-source (algebra); physical "up/right" meaning is inference |
| Units | Radians; no conversion between scalar and matrix | shipped-source |
| XML min/max | Degrees in XML; × `0.01745329238` at load, rotations only; translation limits raw | shipped-source |
| Zero/reference | θ=0 gives `J = I`, i.e. the authored connection transform. Constructor value is 0 | shipped-source |
| Min/max role | Not read by `0x140e20370`/`0x1404b5f20`. They only clamp and choose the target in the solver and mover. `rotation_y` without limits (0/0) is unbounded | shipped-source |
| Pivot | For rotation-only restrictions, `J.t = 0`. The rotation acts at the **origin of the connection's local frame**, which is where the part-local/ANI translation is measured from. `P+0x1e0` (part pivot) and `A+0xf0` are not read on this path | shipped-source |
| Frame | Applied to the child (part) side **before** `C_authored.R` and `C_authored.t`: joint-local axes are the connection's axes *before* its authored rotation, expressed through `C.R` into the parent part | shipped-source |
| Multiple restrictions on one C | Slot-keyed, not order-keyed. Translation types fill `t`, rotation types fill fixed order `Rz·Rx·Ry`; XML order is irrelevant. A duplicate type means the last record wins (plain store) | shipped-source; corpus never exercises it |

## 6. Composition order

**shipped-source** (`0x140e22b70`, A5 flow; compose instructions `0x140e22bfb..0x140e22c25` give `t' = J.t·C.R + C.t`, rows `J.R·C.R`):

```text
W_conn(C)  = ( J_C ∘ C_authored ) with t *= S  ∘  W_part(parent part [C+0x40])      # C has a parent part
W_conn(C)  = ( J_C with t *= S ) ∘ C_authored                                         # root: 0x140e22fc1
W_part(P)  = L_P (ANI replaces default t/R, else stored P-local; t *= S)  ∘  W_conn(owner [P+0x170])
```

- **inference (from the A5 gate):** a connection with no restrictions, or one that fails the `0x14074be30` scene gate, uses `C_authored` alone, which equals `J = I`.

For a point `p` in part P, owned by restricted connection C, in the parent part's frame:

```text
p_parent = ((p · L_P.R + L_P.t) · J_C.R + J_C.t) · C.R + C.t          (S = 1 shown)
```

So the ANI/part-local translation of the part owned by the joint connection **is rotated by the joint**. The joint is not inserted between the connection translation and the connection rotation.

## 7. Static examples (Paranid L Beam, official XML; `static_examples.py`)

**`rotation_y`, horizontal joint.** `Connection03` has `<restriction type="rotation_y"/>`, no offset, parent `part_socket`, and owns `part_rotator`. ANI `(part_rotator, turret_active)` position is `(0, 6.145042419, 0)` with no rotation track. With θ = 0.5 rad:

```text
J.R = [[0.877583,0,-0.479426],[0,1,0],[0.479426,0,0.877583]], J.t = 0
part_rotator→part_socket segment:  t = (0,6.145042,0)·J.R·I + 0 = (0, 6.145042, 0);  R = Ry(+0.5)
+Z row → (0.479426, 0, 0.877583)
```

The ANI translation lies on the joint axis, so it is invariant under this joint.

**`rotation_x`, elevation joint.** `Connection04` has `rotation_x` with limits −5°/80°, loaded as −0.0872665/1.3962634 rad. Offset t = (−1.731e-6, 2.926126, −16.119560), with a quaternion giving a ≈0.50° authored X tilt. It owns `anim_gun`, which has no ANI keys, so L = I. With θ = 0.3 rad (inside the limits, so the mover would not clamp it):

```text
J.R = [[1,0,0],[0,0.955336,-0.295520],[0,0.295520,0.955336]], J.t = 0
anim_gun→part_rotator segment: t = C04.t,  R = Rx(-0.3)·C04.R
anim_barrel origin (A5 §4: (−1.114e-6, −0.417018, 45.161043) in anim_gun frame)
  θ = 0   → (−2.845e-6,  2.899958, 29.043400) in part_rotator frame
  θ = 0.3 → (−2.825e-6, 16.247694, 27.033997)
```

The origin of `Connection04`, `C04.t`, is unchanged: it is the pivot. +Z rises toward +Y.

**inference:** Split M Beam 02 follows the same form. Its `rotation_y` sits on root `Connection04`, so the root branch applies (`S` scales `J.t`, which is 0, before `C`).

## 8. 92-candidate coverage

**shipped-source**, a mechanical scan of `corpus.csv` components (`corpus_restrictions.py`; all 92 components found, no duplicate files):

| Measure | Count |
|---|---|
| Total restriction records | 185 |
| `rotation_y` records | 92, all without `<limits>` |
| `rotation_x` records | 93 |
| `rotation_z` / `translation_*` records | 0 |
| Other child tags or attributes besides `type` / `limits/min/max@value` | 0 |
| Restrictions per restricted connection | Exactly 1 (185 connections) |

`rotation_x` limits (degrees):

| min / max | Count |
|---|---|
| −10/89 | 35 |
| −10/90 | 29 |
| −5/80 | 9 |
| −5/90 | 8 |
| −7/89 | 6 |
| −5/89 | 3 |
| −45/40 | 1 |
| −9/89 | 1 |
| 18/89 | 1 |

Endpoint-path signature, leaf → root: **`rotation_x ← rotation_y` in all 92.**

- `rotation_x` sits at depth 1 (45 macros) or depth 2 (47) from the endpoint's connection.
- `rotation_y` sits at depth 2 (43), 3 (47) or 4 (2).
- One extra `rotation_x`, on `ConnectionForpart_barrel` in `turret_xen_l_plasma_01_mk1`, is not an ancestor of the selected endpoint. Its `J` does not enter that endpoint's recursion.
- `iklink` is absent on 24 `rotation_y` and 12 `rotation_x` connections. **inference (§3):** this changes grouping only, not the existence of state.

**Answer:** Yes. Every restriction needed for prospective muzzle geometry in the corpus is a single `rotation_x` or `rotation_y`, and both are fully covered by the recovered `J_C`. The corpus exposes no other restriction operation.

## 9. Consequences for current production assumptions (no edits)

Production (`ui/gunnery_control.lua:10-151`, `md/x4_gunnery_control.xml:358-369`) computes `O + Ry(yaw)·(P + Rx(−pitch)·D)`:

- `yaw` and `pitch` come from `create_orientation look_at` in `$weapon` space, turned into `create_rotation` values.
- O, P and D are root-frame vectors, already rotated by all accumulated fixed quaternions.
- Per layer, the order is: translate by the connection position, then (depth4 cases) translate by the settled ANI position, **then** split, then the connection quaternion, part position and part quaternion.

| Assumption | Assessment | Reason |
|---|---|---|
| `Ry(yaw)` as the horizontal-joint operation | **Supported as the operation form, unproved as implemented** | **shipped-source:** the `rotation_y` joint is a pure rotation, `Ry(+θ)` (standard right-handed column form), in radians, with zero translation. **inference:** production matches only if MD's `create_rotation yaw` / `transform_position` use the same handedness and `look_at` yaw equals the engine scalar θ_y. That MD convention was not traced |
| `Rx(−pitch)` as the elevation-joint operation | **Supported as the operation form, unproved as implemented** | **shipped-source:** `rotation_x` gives `Rx(−θ)`, and positive θ turns +Z toward +Y. The −5..80 style limits are consistent with positive θ = elevation up (**inference**). The same MD-convention caveat applies |
| Pivot placement (split at accumulated translation) | **Contradicted as a generic rule** | **shipped-source:** the pivot is the connection-local origin, and the part-local/ANI translation belongs to the rotating side. The depth4 cases add `settled_position` *before* the split, so that translation does not rotate with the joint. The Paranid yaw layer coincides numerically only because `(0, 6.145, 0)` lies on the Y axis |
| Yaw/pitch split location (rotation applied outside the fixed stack, and before the connection quaternion) | **Contradicted as a generic rule** | **shipped-source:** the engine order is `L ∘ J ∘ C.R ∘ C.t ∘ ancestors`, which is column form `ancestors · T(C.t) · C.R · J · L`. Production splits after `C.t` but before `C.R`, and then applies `Ry`/`Rx` about root-frame axes to vectors already rotated by all fixed rotations. That equals the engine only when every intervening fixed rotation is identity or commutes with the joint. Paranid `Connection04` carries a ≈0.5° X tilt, so the depth4 cases are not identical even for pure pitch |
| Pitch nested inside yaw | **Supported** | **shipped-source:** `rotation_x` is always the leaf-side joint and `rotation_y` the root-side one on all 92 paths, so the yaw joint transform applies to the pitch subtree |

## 10. Single next dependency

**Resolve the animation state and local time the engine evaluates for each path part's controller entry `E` on a deployed, non-firing turret.** That means which `(part, subname)` ANI descriptor `[E+0x50]`→vcall `+0x38` returns and at what `0x141165cd0` local time, including how the selector on the root connection propagates to descendant parts' entries (`word[P+0xe2]`). `L_P` enters every segment ahead of `J_C`, so it decides the ANI translations, such as the Paranid `anim_barrel` `(0, −0.23982, 27.7102)` versus the `gun_firing` or `inactive` values.
