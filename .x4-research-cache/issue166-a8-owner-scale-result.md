# Issue #166 A8: owner-level translation scale `S` (owner vtable `+0x1448`)

## Verdict

**RESOLVED**

**Scope.**
- Evaluation of mounted combat turrets on the selected connection scene path (`0x14081c960`), plus the static fallback boundary.

**Evidence.**
- `X4.exe` SHA-256 `19750a65…6891`, the same binary as A5–A7. VAs use image base `0x140000000`.
- Class names are compiler RTTI strings (**shipped-source**). Purpose labels beyond those names are **inference**.
- Tools and scratch are in `.x4-research-cache/issue166-a8-work/`: `xd.py`, `rtti.py`, `strs.py`, `scan*.py`.
- No LIVE data or residual was used, and no new `live-tested` claim is made.

`scale(v, S)` below means component-wise `(v.x·S.x, v.y·S.y, v.z·S.z, v.w·S.w)`, which is SSE `mulps`. `S.w` is always 1 in the sources found.

## Concrete `+0x1448` implementation

**shipped-source**

- `Turret` (vtbl `0x142b6e910`) and `MissileTurret` (vtbl `0x142b00620`) both have slot `+0x1448` = **`0x140746370`**.
- The same function is shared by 115 `U::` component classes (`Component`, `Container`, `Controllable`, …).

```text
0x140746370(this, out=rdx, time=xmm2, reset=r9b):
    ctrl = [this+0x200]                        ; movement controller (MovementControllerInterface*)
    if ctrl: tailcall ctrl->vtbl[+0x170](out, time, reset)
    if reset: out = (1,1,1,1)                  ; constant 0x142cc23b0
```

At every call site on the selected-connection path `reset = 1` (`r9b=1`; stack byte `1`), so the output is always fully overwritten.

| Site | `this` |
|---|---|
| `0x14081c9d6/0x14081ca0e` | `[r14]`, where `r14 = [[weapon+0x208]+0x48]` is the IK manager A6 identified, and `[mgr+0] = owner` (`0x140e200e0`). So `this` = the turret/weapon component |
| `0x140e22be5` | `[[rsi]]`, where `rsi` = the same manager, so the same owner |
| `0x14074c3c8` | `r14`, the owner argument, the same component |
| `0x14074bf1e` | `rdi`, the owner argument, the same component |

**One object at all levels.** Every call on this path is on the same owning component. The owner is passed down the recursion and never changed. No part or connection has its own `+0x1448` object.

**Slot `+0x170` implementations.** Grouped by primary vtable (COL offset 0), over every `U::*Controller` RTTI class:

| Implementation | Classes | Result with `reset=1` |
|---|---|---|
| `0x14010b960` | 29 classes: `StaticMovementController`, `MovementController`, `ConnectionMovementController`, `DockMovementController`, `NPCOverHeadController`, `HighwaySceneController`, `TowingMovementController`, … | `(1,1,1,1)` |
| `0x140675f00` | Nestable/camera family, incl. `LookAtPlayerController`, `CameraMovementController` | forwards to the inner controller `[this+0x80]`; if none, `(1,1,1,1)` |
| `0x140e637c0` | nestable indirect base | forwards (nestable) |
| `0x140e3fa40` | `ScaleController` | `[this+0x90]`, then × inner controller (non-reset) |
| `0x140e40100` | `LinearScaleController` | `[this+0x90]` × inner, `+ (time−[this+0x60])·[this+0xa0]`, `min [this+0xb0]` (time-varying) |
| `0x140d4c3a0` | `AnimationController` | ANI group-2 scale of its own embedded animation entry `[this+0x38]` (`0x1411654e0`) × `[this+0xd0]`; or `[this+0xd0]` alone |
| `0x140d4d950` | `AsteroidMovementController` | asteroid-specific |

## Value provenance

**shipped-source** unless marked.

**Field.** `[component+0x200]` holds a `MovementControllerInterface*`.
- The constructor clears it (`0x140742760`).
- `0x140745e00(this, ctrl, …)` installs it (`0x140745fd9`). Components expose that installer as vtable `+0x19e8` = `0x14051b710`.
- `0x140746980` also writes it (`0x140746a62`); components expose that as vtable `+0x1468` = `0x14051b330`. It takes a transform `M`. If `M.t = 0` and `M.R = I`, it deletes the controller. Otherwise it allocates a `StaticMovementController` holding `M` and installs it.

**Default for a created component.** Component creation (`0x1407426d0`) installs a `StaticMovementController`, either built from the initial transform (`0x140742887..0x1407428d5`) or through `0x1406bb2d0`, which also builds a `StaticMovementController`.
- `0x140745e00` discards a controller whose transform is identity (`0x140745ef5..0x140745f54`).
- Either way the result is `S = (1,1,1,1)`.

**Non-unit sources and where they come from.**
- `AnimationController`, `ScaleController`, `LinearScaleController` and `AsteroidMovementController` are built only by these paths:
  - the typed controller factory `0x140d67970`. It dispatches on a type enum read from a node attribute (`0x14094bd60(node, 0x29)`); names such as `linearscale`, `lookatplayer`, `nestable`, `npcoverhead`, `static` are adjacent at `0x1429ff82f..`
  - the clone routine `0x140d64820`
  - the `ScaleController` creator `0x140d50f30`, called only from `0x1408185b0` (Turret vtable `+0x1f30`)
- `0x140d67970` is called from component state restore (`0x140742ea0` → installs through `+0x19e8`) and two other runtime paths.
- `0x1408185b0` installs the `ScaleController` on its **4th argument** (`rbx = r9`, test at `0x14081892b`), not on `this`.
- **inference:** that argument is a spawned or launched object rather than the turret itself.

**Not a source.** No component or macro XML parser, and no ANI loader, writes `+0x200` or any controller scale field.

**Corpus data check (shipped-source).** Across the 92 corpus components and their macros there are zero XML elements or attributes containing `scale`.

## Runtime behavior

**shipped-source**

- **Per instance, runtime.** `S` is a per-instance runtime property of the owning component's movement controller. It is not authored asset data, not per-part and not per-connection.
- **Default mounted turret.** With no controller, a `StaticMovementController`, a connection/dock/NPC-overhead controller, or a nestable controller without a scale-bearing inner controller, `S = (1,1,1,1)`. That value is constant and independent of animation state and time.
- **Non-unit cases.** `S` differs from unity only while a `ScaleController`/`LinearScaleController` (time-varying for linear), an `AnimationController` (animation-dependent) or an asteroid controller is installed on the owner. None of these is created from turret component or macro data.
- **inference:** they are runtime effects such as spawn/scale-in, save-restored special controllers or asteroids, and none belongs to a mounted, deployed, non-firing combat turret. The prospective offline evaluator should use `S = (1,1,1,1)`.

## Scale application sites

**shipped-source.** Notation as in A5/A6: `L ∘ B` means apply `L`, then `B`; row vectors; `t' = t·B.R + B.t`.

1. **`0x14074c2d0` part world.** `S` is obtained at `0x14074c3c8`.
   - `0x14074c3ce..0x14074c3fe`: `L.t = scale(L.t, S)`, where `L` is the animated or stored part-local matrix (A5/A7).
   - It then composes with `W_conn(owner connection)` (`0x14074c40b..`).
   - The part-local translation is scaled **before** the owning connection's rotation; `L.R` is untouched.
2. **`0x14074be30` connection world, non-scene branch** (restriction/scene gate false, e.g. unrestricted connections).
   - `out = C_authored`; `S` at `0x14074bf1e`; `0x14074bf24..0x14074bf2c`: `out.t = scale(C.t, S)`.
   - It then composes with parent-part world (or the scene part matrix, which needs arg `a7`; that is NULL on this path, A5).
   - Scaling happens before parent composition.
3. **`0x140e22b70` connection world, scene branch** (restricted connections). `out = J_C` (A6); `S` at `0x140e22be5`.
   - With a parent part:
     - `0x140e22bfb..0x140e22cc1`: `M = J_C ∘ C_authored`.
     - `0x140e22cc5..0x140e22ccd`: `M.t = scale(J.t·C.R + C.t, S)`.
     - Then `M ∘ W_part(parent)` (`0x140e22f0d` → `0x14074c2d0`).
   - Root connection (no parent part), `0x140e22fc1..0x140e22ffa`: `M.t = scale(J.t, S)·C.R + C.t`. Here only `J.t` is scaled and `C.t` is not.
4. **`0x14081c960` final output.**
   - `0x14081ca52`: `W = 0x140e22b70(mgr, selected connection, time, NULL)`.
   - `0x14081ca57..0x14081ca62`: `out.t = scale(W.t, S)` with `S` from `0x14081ca0e`.
   - This is the same owner's `+0x1448` value. `W.t` is the fully accumulated component-space translation, so every hierarchy level's already-scaled translation is scaled again.
   - **inference:** for non-unit `S`, the result is not a consistent similarity transform, because inner levels would carry `S²` or more. This reinforces that non-unit owner scale does not occur on mounted-turret geometry. With `S = 1` every site is the identity.

## ANI group-2 relationship

**shipped-source**

- **Consumers.** ANI group 2 (`D+0x58`) is read only by `0x141160c80` (the full five-track bake) and `0x1411654e0`.
  - `0x1411654e0` has exactly two call sites, both inside `AnimationController::+0x170` (`0x140d4c3c7/0x140d4c3e8`).
  - `0x141160c80`'s callers are the descriptor binders (`0x141163510`, `0x141163c00`, `0x141163e40`, `0x141163fe0`), which write the baked result into `D+0xc0`, and `0x14074c770`.
  - `0x14074c770` is reached only from `0x140745920`, the scene part-matrix path gated `[P+0xe8]&0x30`.
- **Selected-connection path.** The path `0x14081c960 → 0x140e22b70 → 0x14074c2d0 → 0x141165440 → 0x1411608b0` reads only `D+0x28` and `D+0x40` (A5/A7).
  - It passes NULL for the scene-matrix argument (`0x14081ca41`), so the `[P+0xe8]&0x30` scene matrix branch in `0x14074be30`/`0x140e22b70` is never taken.
  - It never reads `D+0x58` or `D+0xc0`.
- **Through `S`.** Group 2 could reach the result through `S` only if an `AnimationController` were installed on the owning turret. Its animation entry is its own member, not the turret part entries, and component data never creates one.
- **Conclusion.** ANI group 2 **does not affect** selected muzzle geometry for mounted turrets. On descriptor binding it feeds the baked full-local cache `D+0xc0` and the scene part-matrix path; **inference:** that is render/visual use.

**ARG L Beam 01 discriminator** (applied after deriving the rule):
- Its group-2 keys are `(0.997663, 0.997663, 0.997663)` on `detail_xl_gun` and `detail_xl_barrel`, for every selector including `turret_active`.
- Those values go only into `D+0x58`, and from there into `D+0xc0`/scene matrices. They do not feed `S`.
- Under the default deployed state the accepted `+0x1448` source gives `S = (1,1,1,1)`, because the owner has no scale-bearing controller.
- The selected barrel translation is therefore unaffected by the 0.23 % group-2 scale.

## Complete transform equation

Combining #164, A5, A6, A7 and A8. All translations are row vectors with `S = (1,1,1,1)` for mounted turrets; the general-`S` form is shown for exactness.

```text
L_P      = A7-selected ANI local (t from group 0 at tl, R = R_ANI(group 1) or XML part R; defaults per A5/A7),
           or stored XML part local if the part is not animated
J_C      = A6 restriction matrix (I if unrestricted)
C        = XML connection offset (A5)

W_part(P)  = [ scale(L_P.t, S) ; L_P.R ] ∘ W_conn(owner(P))                                  (0x14074c2d0)

W_conn(C)  = unrestricted / non-scene:  [ scale(C.t, S) ; C.R ] ∘ W_part(parentPart(C))       (0x14074be30)
             restricted, has parent:    [ scale(J.t·C.R + C.t, S) ; J.R·C.R ] ∘ W_part(parentPart(C))   (0x140e22b70)
             restricted, root:          [ scale(J.t, S)·C.R + C.t ; J.R·C.R ]
             unrestricted, root:        [ scale(C.t, S) ; C.R ]

barrelposition(weapon) = [ scale(W_conn(selected).t, S) ; W_conn(selected).R ]                (0x14081c960)
```

- **Mounted turret form.** With `S = 1` this reduces to the accepted `L_P ∘ J_C ∘ C ∘ parent` chain, and the final output equals `W_conn(selected)` in component space.
- **Which connection enters `0x140e22b70`.** `0x14081c960` calls it with the selected connection itself. Ancestor connections take the scene branch only when restricted (A5/A6 gate).
- **Where `S` would apply for non-unit values:**
  - per hierarchy level, to the local translation before the parent's rotation;
  - after `J·C` for restricted non-root connections;
  - to `J.t` only at a restricted root;
  - once more to the accumulated translation at the output.
- **Path to reproduce.** The offline evaluator should reproduce the **scene-backed path** above.
- **Static fallback.** The fallback of `0x14081c960` (`[weapon+0x208]` or `+0x48` absent) uses connection local plus a `[[weapon+0x108+idx]+0x40]` translation factor, and then `0x14074c520` strips row scale. That is different machinery. Mounted turrets with a scene/IK manager do not use it.
- **inference:** mounted combat turrets with restrictions always own that manager (A6). Stop at that boundary.

## 92-candidate coverage

**shipped-source**, mechanical scan (A7 corpus + `issue166-a8-work`):

| Structure | Count |
|---|---|
| Component XML elements/attributes containing `scale` | 0 |
| Macro XML elements/attributes containing `scale` | 0 |
| Explicit connection/part scale (XML offset has only position/quaternion/rotation readers, A5) | 0 |
| ANI group-2 keys on A7-selected active path descriptors | 162: 158 unit, 4 non-unit (ARG L Beam/Laser 01 `detail_xl_gun`/`detail_xl_barrel`, all 0.997663) |
| Candidates whose owner `S` is sourced from data | 0: `S` is runtime controller state, and the default created component is unit |

- **Coverage.** The recovered rule covers all 92 candidates with `S = (1,1,1,1)`.
- **Group 2.** The 4 non-unit group-2 key sets are provably outside the selected-connection path.
- **Other structures.** No candidate carries any other scale-relevant structure.

## Consequences for current code

No edits.

- **Scale handling.** Production ignores `S` and ANI group 2. It is **unaffected**, because the selected path's owner scale is unity and group 2 cannot reach this output. No required scale is ignored, and none is handled accidentally somewhere else.
- **Existing research notes.** "Groups 2–4 ignorable, justified only by LIVE per signature" is now **supported by executable data flow**, not LIVE evidence. The ARG L Beam group-2 concern (~4 cm) is **contradicted** for muzzle geometry.
- **Other A5–A7 contradictions.** Pivot/split placement, additive ANI, X negation and settled-key choice remain as recorded in those results. A8 does not change them.

## Remaining blocker

> Is any transform input still unknown before writing the generic offline evaluator?

**No.** For mounted, deployed, non-firing combat turrets, every transform input on the selected-connection scene path is now determined:
- endpoint (#164)
- authored/default/ANI local semantics (A5)
- `J_C` (A6)
- descriptor and local time (A7)
- owner scale `S = 1` (A8)

The next task is to build the generic offline evaluator from the accepted #164/A5/A6/A7/A8 rules.
