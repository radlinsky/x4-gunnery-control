# Issue #166 A5 — evidence packet for the selected-connection transform research

Temporary, ignored handoff (`.x4-research-cache/`). Context gathering only. No production code, tests, commits, GitHub edits, or X4 launches were made.

Evidence labels used below:

- **shipped-source**: bytes/text read directly from official files or the pinned `X4.exe`. Instructions, offsets and constants count; function *purposes* do not.
- **live-tested**: from accepted LIVE records (#155, #75 A4). Holdout only, never an input to rule derivation.
- **inference**: my reading of disassembly or data. Every function "role" is inference. Addresses are leads, not symbols.
- **unresolved**: not established.

---

## 1. Baseline (verified 2026-09-14)

| Item | Value |
|---|---|
| Repo | `/home/pc/projects/x4-gunnery-control` |
| Branch / HEAD | `issue-75-strict-geometry` / `4087cb72855977ec69e5b3f3012e69cc0e165326` |
| Tracked tree | clean (`git status --porcelain --untracked-files=no` empty) |
| `X4.exe` | `/mnt/c/Program Files (x86)/Steam/steamapps/common/X4 Foundations/X4.exe`, SHA-256 `19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891` (**matches**) |
| Image base | `0x140000000` (RVA = VA − base) |

Volatile `/tmp` inputs (all survived; none rebuilt):

| Path | Size | mtime |
|---|---|---|
| `/tmp/x4-calls.json` | 9,900,352 | 2026-09-13 08:16:08 |
| `/tmp/x4-allrefs.json` | 17,590,538 | 2026-09-13 08:16:08 |
| `/tmp/x4-census.json` | 58,231,638 | 2026-09-13 08:23:24 |
| `/tmp/x4-captured.pkl` | 31,699,320 | 2026-09-13 08:23:22 |
| `/tmp/x4pe.py` | 1,254 | 2026-09-13 08:13:23 |
| `/tmp/x4-offline-validation/` | 276 K, 12 files (`x4-re.py`, `x4pe.py`, `x4-official.py`, `report.md`, `corpus.csv`, `summary.json`, …) | 2026-09-13 08:45–08:54 |
| `/tmp/x4-re-tools/` | 12 M (pefile 2024.8.26, capstone 5.0.9; no `x4pe.py`) | 2026-09-13 08:15 |
| `/tmp/x4-catalogs.json` | 2,889 | 2026-09-13 08:16 |
| `/tmp/x4-official-scripts/` | extracted official libraries/md/aiscripts/ui (has `base/libraries/animation_sequences.xml`) | — |

Tooling notes:

- Disassemble with `cd /tmp/x4-offline-validation && python3 x4-re.py <VA_hex> [<end_VA_hex>]`. It uses `.pdata` bounds. **Several targets are split into `.pdata` chunks** (`0x14081c960`, `0x1411608b0`, `0x14115fdc0`, `0x141165cd0`, `0x14074c7c0`), so pass an explicit end VA or you get a truncated listing.
- `/tmp/x4-calls.json` maps `str(callee_VA)` → `[call-site VAs]`. `/tmp/x4-allrefs.json` maps `str(target_VA)` → `[[site, mnemonic, op]]` (RIP-relative refs only).
- For a RIP-relative operand the target is `instr_addr + instr_size + disp`. Use capstone `disasm_lite` sizes; don't hand-count.
- This session's disassembly dumps are in `/tmp/claude-1000/-home-pc-projects-x4-gunnery-control/14aff91b-f9ed-46ea-97bb-8080bd6e49cb/scratchpad/dis/` (also volatile).

Official data caches:

- XML: `.x4-research-cache/official-source-sets/<set>/…`
- ANI: `.x4-research-cache/issue72-a2-ani-resources/<set>/…` (181 turret ANI files)

**#164 archive gap:** `.agents/skills/research-x4-modding/references/barrelposition-endpoint-selection/` holds only an untracked `__pycache__` on this branch. `README.md`, `report.md` and the helpers exist only at commit `4de44faa` (branch `issue-164`). Read them with `git show 4de44fa:.agents/skills/research-x4-modding/references/barrelposition-endpoint-selection/report.md`. `/tmp/x4-offline-validation/report.md` differs from that committed copy.

---

## 2. Authority and boundary

- #166 body: A0–A4 are done. A5 means recovering X4's generic selected-connection scene/animation transform for the endpoint that the #164 rule already selects.
- Endpoint selection is solved; do not revisit it. Rule: smallest unsigned native hash among `laser`-tagged connections, hash `h=0x811c9dc5; h=((h*0x1000193)&2^64-1)^byte`.
- #79 product boundary: prospective muzzle geometry is one input to "would be ENGAGEABLE if directed". Exact millimetre residual is a research discriminator, not the product requirement. Production must never depend on native hooks.
- LIVE authority for this build and path: the X4Native capture at target RVA `0x0081c960`, filtered to caller RVA `0x007c6eb1`. Its 64-byte output is a translation row followed by right-handed +X, +Y, +Z basis rows (**live-tested**, `barrelposition-live-connection-orientation.md`).
- `docs/TURRET_ASSET_KINEMATICS.md`: the five ANI "candidate channels", "byte slots", selectors and joints all have **unproven** meanings. Do not infer meaning from names.

---

## 3. Current offline interpretation (to explain, replace, or delete)

| File | Contributes | Raw source fact | Inferred semantics |
|---|---|---|---|
| `scripts/census_ani_parser.py` | ANI v1 framing: 16-byte header `(descriptor_count, key_offset, version=1, 0)`; 160-byte descriptors (`part[64]`, `subname[64]`, `u32×5` counts at +128, `u32` at +148, zeros at +152); key records of 128 bytes, grouped per descriptor in channel order | Framing is exact: the whole file is consumed and it fails closed otherwise | Channel names `position, rotation, scale, pre_scale, post_scale` come **from X4Converter**. Slot types are candidate `3f,3i,18f,i,6f,u`. Descriptor +148 is decoded as a float |
| `scripts/census_ani_analysis.py` | Statistics and inventories over slots, descriptor +148, slot 24, and restriction correlations | Counts and values | None applied to geometry |
| `scripts/census_ani_relationships.py` | Subname inventories. "Ancestry-covered `turret_active`" membership sets, used by the semantics module | Name joins | Coverage means an exact `turret_active` selector at or above the descriptor's edge. This is structural only |
| `scripts/census_endpoint_paths.py` | Connection-parent hierarchy, `laser`-tag endpoints, selector/subname joins, endpoint path. `_derive_endpoint_authored_geometry` (line 636) emits per-layer `{source_part, owning_connection, connection_authored_offset, part_authored_offset, authored_restrictions}` plus the endpoint leaf offset | Verbatim XML offsets | The layering assumption is **one part owned by one connection per layer**. No matrices composed |
| `scripts/census_source_semantics.py` | `_resolve_supported_endpoint_source_semantics` | — | **Hand-built semantic cases enter here.** Each case matches literal raw bits, key counts, depth, restriction limits and sometimes exact authored positions, then injects hard-coded vectors. `_apply()` negates ANI X (`[-x,y,z]`, "opposite handedness") and stores `settled_local_position_delta` / `settled_local_euler_xyz_delta_radians` per layer |
| `scripts/census_pipeline.py` | `build_census` calls path derivation (line 244), then the semantic resolver (line 270) | — | — |
| `scripts/generate-turret-muzzle-geometry.py` | `MACROS` allow-list of macro → `(semantic_case, layer_count)`. Emits `ui/turret_muzzle_geometry.lua`. `barrelposition_connection` is emitted only for `depth3_one_key_barrel_translation`; other cases keep "endpoints[2]" | — | Turret-name allow-list |
| `ui/gunnery_control.lua` lines 10–151 | `deriveProspectiveMuzzle` walks the layers. Per layer it does `chainTranslate(conn.pos)`, then the case behavior: `depth4_dual_translation` = `[settled_position]` → split at runtime rotation → conn quat → part pos → part quat. `depth5_additive_x_rotation` = conn quat, part pos, part quat, Rx(settled), then split. The yaw split captures `O`, the pitch split captures `P`, the remainder with the endpoint captures `D` | — | **Production representation `O + Ry(yaw)·(P + Rx(−pitch)·D)` enters here.** It assumes yaw and pitch pivot exactly at the accumulated translation up to the restriction layer, with no fixed rotations between the joints except the accumulated frame |

Hand-built cases and the literals they carry:

- `depth4_dual_translation` (Paranid L Beam/Laser/Plasma). Edge 1 gets `(0, 6.145042419433594, 0)` and edge 3 gets `(0, -0.23982000350952148, 27.710205078125)`. These are **the #75 defect location**.
- `depth4_zero_translation` (Split L): zero vectors on edges 2 and 3.
- `depth4_p6_translation`: literal authored-position guards; edge 3 gets `(0, -1.9073e-6, 0)`.
- `depth4_p8_translation`: edge 3 gets `(0, 0, 3.8146e-6)`.
- `depth4_one_key_barrel_translation` and `depth3_one_key_barrel_translation`: rotator and barrel channel-0 key values. Guards: STEP enums `1,1,1`, one-frame selector, activating/deactivating boundary equality, rotation_x limits −10/90.
- `depth5_additive_x_rotation`: X rotations ±0.6108652 rad on edges 1 and 2, plus an optional µm residue.

Assumptions #166 must prove, replace, or delete:

1. Channel 0 is "position" and is **additive** to the authored offsets (rather than replacing a stored local transform).
2. ANI X must be negated relative to XML.
3. Channel 1 is Euler radians and additive.
4. Channels 2–4 are ignorable, justified only by LIVE per signature.
5. Which layer the ANI value is inserted into, and at which point relative to the connection offset, part offset, and joint split.
6. Joint pivot = connection origin, axis = local Y/X, and the pitch sign convention `Rx(-pitch)`.
7. "Settled active" = any `turret_active` key value, with STEP and boundary checks as proxies.
8. The part offset and connection quaternion order.
9. The consumer's `endpoints[2]` fallback (endpoint debt from #164).

---

## 4. Executable map (all roles are inference; instructions and offsets are shipped-source)

Row-matrix convention observed everywhere (**shipped-source** instructions): a 4×4 transform is stored as four 16-byte `vec4` rows, `[t][X][Y][Z]`. A repeated compose pattern takes `A` (child) and `B` (parent) and computes:

```
A.t' = A.t.x*B.X + A.t.y*B.Y + A.t.z*B.Z + B.t
A.R' = rows of A.R each expanded in B's basis   (row-vector: p_parent = p_child · A · B)
```

Below I write this `A ∘ B` (apply A, then B). Identity rows are constants at `0x1422c01d0/e0/f0` (and `0x1423127c0..e0`).

### Call chain

```
0x1407c6e80 (barrelposition wrapper, #164) → vtable+0x1ec8 → 0x14081c960
0x14081c960(rcx=weapon, rdx=out64, r8=selected connection)
  ├─ scene-backed: if [weapon+0x208] && [[weapon+0x208]+0x48]
  │    r14=[[weapon+0x208]+0x48]; S=vcall [[r14]]+0x1448 (time = TLS[0x58][0]+0x300 double)
  │    M = 0x140e22b70(rcx=r14, rdx=tmp, r8=conn, xmm3=time, arg5=NULL)
  │    out = M with out.t *= S
  └─ static fallback: M = conn local [conn+0x60..0x9f];
       if parent part [conn+0x40]: M.t *= [[weapon+0x108+(idx<<7)]+0x40]
       (idx from 0x1438f4eb4 / 0x1438f4ee0 selected by TLS+0x314); then 0x14074c520(weapon,&M)
     (no connection: constant matrix at 0x143926fa0)
```

### `0x14081c960` (RVA `0x0081c960`); callers via vtable only (the calls index has none)

- Branch between scene-backed data and stored data on `[rcx+0x208]` and `[..+0x48]`. **The LIVE capture measured this function's output.**
- Scene-backed path passes **arg5 = 0** (`mov qword [rsp+0x20],0` at `0x14081ca41`). That NULL is propagated, so the "external per-part matrix array" branch inside `0x140e22b70` and `0x14074be30` is never taken on this path (see below).
- Applies a per-axis vector from vcall `+0x1448` to the final translation only. Its role (object/instance scale?) is **unresolved**.
- Static fallback `0x14074c520`: calls `0x14074ccb0` to get a matrix, strips scale (divides rows by their lengths; if any length < `1e-4` at `0x142cbe0ac`, it logs and uses identity), then composes `M ∘ normalized`. Whether #79 needs this path is **unresolved**. It is not the path LIVE measured, provided the gate holds in-game.

### `0x140e22b70` (callers `0x14081ca52`, `0x14074bed3`): connection world transform

```
out = identity; call 0x140e20370
S   = vcall [[rsi]]+0x1448(time)
P   = [conn+0x40]                     ; parent part
if !P: out = conn_local ; out.t *= S  ; return          (0x140e22fc1)
out = conn_local ; out.t *= S
if ([P+0xe8] & 0x30) && arg5 && [arg5+0x30]:            ; NOT taken from 0x14081c960 (arg5=0)
    W = [[arg5+0x30]] + word[P+0xe0]*64 ; rows normalized (scale stripped) ; out = out ∘ W
else:
    W = 0x14074c2d0(rcx=[rsi], rdx=tmp, r8=P, xmm3=time, a5=1, a6=1, a7=arg5)
    out = out ∘ W
```

**Ordering (shipped-source instructions):** connection local, then the parent part's world transform.

### `0x14074c2d0` (called from `0x140e22f0d`, `0x14074c178`, and many others): part world transform

```
L = identity
if a6 && [owner+0x208] nonempty && bit9([P+0xe8]) :
    E = [[owner+0x208]] + word[P+0xe2]*0x90          ; animation controller entry
    if [E+0x88] & 1:  L = 0x141165440(rcx=E, rdx=L, xmm2=time)     ; animated local
else-or-fallthrough: L = stored part local [P+0x1a0..0x1df]
S = vcall owner+0x1448(time) ; L.t *= S
C = [P+0x170]                                          ; owning connection
Wc = 0x14074be30(rcx=owner, rdx=tmp, r8=C, xmm3=time, a5, a6, a7)
L = L ∘ Wc
if a6 && [owner+0x68]==0 && ([C+0xf0] & 0x40): 0x140757bc0(owner, L, P, time)   ; unresolved post-step
return L
```

**Ordering:** the part local transform (animated or stored) comes first, then the owning connection's world transform. The animated local **replaces** the stored part local; it is not multiplied with it.

### `0x14074be30` (about 20+ callers, including `0x14074c178`): connection world transform, recursive variant

```
out = conn_local [C+0x60..0x9f]
if a5 && [owner+0x208] && [..+0x48] && [C+0x150]!=0 && !([C+0xf0]&0x40):
    return 0x140e22b70(owner, out, C, time, arg5=a7)          ; scene-backed variant
P = [C+0x40]; if !P: return out
S = vcall owner+0x1448 ; out.t *= S
if ([P+0xe8]&0x30) && a7 && [a7+0x30]: out = out ∘ normalized(scene matrix[word P+0xe0])
else: out = out ∘ 0x14074c2d0(owner, P, time, …)
```

This is the recursion. `connection → parent part (animated or stored) → owning connection → parent part → …` until a connection has no parent part.

### `0x141165440` (callers include `0x14074c375`): animated local for one controller entry `E`

```
if ![[E+0x48]+0x130]: 0x141165340(E)        ; lazy bind: resource id [..+0x134] → 0x1414bab90 → 0x141163e40
D = [E+0x50] ? vcall [[E+0x50]]+0x38(time) : NULL      ; current state's ANI descriptor
if D: tl = 0x141165cd0(E, time) ; 0x1411608b0(rcx=D, rdx=out, r8=[E+0x48], xmm3=tl)
else: out = [[E+0x48]+0x40 .. +0x7f]                    ; default local matrix
```

### `0x141165cd0`: state-local time (partial)

- If `[E+0x88] & 2`: `t = time − [E+8]` (double). If `time < [E+8]` it returns 0.
- If `[E+0x40]` is set, it returns `dur − f(t, dur)` with `dur = [[E+0x40]+0xa0]` and `f = 0x141b44180` (fmod-like, **unresolved**). Otherwise it subtracts `[E+0x78]` when positive and clamps negatives to 0 unless `[E+0x80]` > threshold.
- If the flag bit is clear it tail-jumps to `0x141166050` (not inspected).

### `0x1411608b0` (callers `0x1411654a1`, `0x14116bb6d`): descriptor → local matrix, translation and rotation only

```
if vec D+0x28 empty: out.t = [def+0x40]            else out.t = key_eval(D+0x28, tl, wrap=0, indirect=0)
if vec D+0x40 empty: out.R = [def+0x50..0x7f]      else e = key_eval(D+0x40, tl, wrap=1, indirect=0)
                                                        (sx,cx,sy,cy) = 0x141750253(e.x,e.y); (sz,cz)=0x141750210(e.z)
                                                        out.R = product of three axis matrices built from identity rows
                                                                0x1422d40a0/b0/c0 (exact order and signs unresolved)
```

- **Observed:** this path reads only descriptor vectors `+0x28` and `+0x40`. It does **not** read `+0x58`, `+0x70`, or `+0x88`.
- **Observed:** evaluated translation replaces `def.t`, and evaluated rotation replaces `def.R`. Rotation is built from sin/cos of three angles, so the unit is radians (inference).

### `0x141160c80` (callers `0x14074c8b6`, `0x141163a28`, `0x141163d72`, `0x141163f83`, `0x1411642ef`): full five-track local

- Reads `D+0x28` (position, default `def+0x40`), `D+0x40` (Euler, default `def+0x50..0x70`), `D+0x58` (vec3, `andps` mask drops w, default `def+0x80`), and `D+0x70` and `D+0x88` (each through `0x141160b30`, defaults `def+0x90..0xb0` and `def+0xc0..0xe0`).
- `0x141160b30` evaluates the same key vector twice: `(wrap=1, indirect=0)` gives an axis, and `(wrap=1, indirect=1)` gives a magnitude from `.x`. It then builds a quaternion (`0.5` at `0x142cbe430`, sin/cos) and converts it through `0x1400d1fb0`. This looks like axis-angle (inference).
- The composite applies the `+0x70` rotation, then its inverse (sign-mask `xorps` `0x142441660` / transpose-like), along with the scale vector, Euler R and T. That is consistent with a "scale-orientation" decomposition, **but the order is unresolved**.
- Reached from `0x14074c770` (caller `0x140745920`, gated `[P+0xe8]&0x30`) and a loader/bake cluster around `0x141163xxx`, **not** from the barrelposition chain above.
- `0x1411654e0` (caller `0x140d4c3a0`) evaluates `D+0x58` alone. Its default is `[E+0x48]+0x80`, or constant `(1,1,1,1)` at `0x142cc23b0` when the state has no keys.

### `0x14115fdc0` (callers `0x1411608f6`, `0x141160965`, `0x141160b6a/84`, `0x141160d77`, `0x141160e13/53`, `0x141165551`): key track evaluator

Arguments: `rcx=out vec4`, `rdx=&vector<key>`, `xmm3=time`. Stack byte "wrap" is `callee[rsp+0xb0]` (caller `[rsp+0x20]`); "indirect" is `callee[rsp+0xb8]` (caller `[rsp+0x28]`).

- In-memory key stride is **`0x90` (144 bytes)**; the file record is 128. With `indirect=1` each element's payload is the pointer at `+0x78`.
- Observed in-memory key fields: `+0x00` value vec (x,y,z); `+0x60` time (float); `+0x80/+0x84/+0x88` interpolation enum per axis x/y/z; `+0x34/+0x3c`, `+0x44/+0x4c`, `+0x54/+0x5c` per-axis handle values (used by enum 5); `+0x70`/`+0x74` used by enum 7.
- Key selection: `t <= k0.time` → index 0. Otherwise the first `i` with `t < k[i+1].time`, else the last key. `frac = (t−k[i].time)/(k[i+1].time−k[i].time)`. With no next key, `frac = 0` and `next = 0`.
- If `enum_x == 7`, the whole key is handed to `0x141160280`: Hermite/TCB with ease at `+0x70/+0x74`, constants 2.0 and 3.0; with wrap it takes a quaternion path via `0x14115ed10` and `0x141175880`.
- Otherwise each axis is evaluated independently:
  - `1`: hold `k[i]` (step)
  - `2`: linear `k + (next−k)·frac`; with wrap, if `k != next` and `|k| == 6.2831855` (`0x142cbebdc`) it uses `k = 0`
  - `5`: `0x1414dd440(k, k.out_handle, next.in_handle, frac)` (cubic with handles, inference); with no next key it returns `k.out_handle`
  - `6`: `0x1414dd4c0(k, prev, next_next, frac)` (Catmull/TCB-like, inference)
  - anything else: 0
- **Defaults (observed):** when a track vector is empty, the caller substitutes the default matrix/vector from `[E+0x48]` (`+0x40` t, `+0x50..0x7f` R, `+0x80` scale). What produces those defaults (bind pose from geometry? the XML part offset?) is **unresolved**.

### File → memory mapping (the key open linkage)

- **Likely inference, not observed:** file slot 6 (byte 24) is time → `+0x60`; bytes 12–23 (three int32) are enums → `+0x80..+0x88`; bytes 28–75 (12 floats, per-axis quads) → `+0x30..+0x5f`.
- Support: for Split M Beam 02 rotator `turret_activating` rec 3, file per-axis quad y = `(0.888833, 2.341499, 0.611333, 1.98049)`. `+0x44`/`+0x4c` would be 2.341499/1.98049, which fits the enum-5 out/in value handles for a curve rising to 2.368.
- The five in-memory vectors `D+0x28/+0x40/+0x58/+0x70/+0x88` (stride 0x18 = `std::vector`) plausibly receive file channel groups 0..4 in order.
- **The loader was not located.** Leads: `0x141165340` → `0x1414bab90` (resource lookup by `[..+0x134]`) → `0x141163e40` (a tiny `.pdata` chunk). The callers of `0x141160c80` in `0x141163510..0x1411642ef` sit near it. No NUL-terminated or UTF-16 `turret_active` string exists in the exe (so the `animation_sequences.xml` comment "hardcoded check in x4-code" is not a plain string compare; possibly hashed, **unresolved**).

### Five channel groups vs executable (§5 of the task)

| Group (parser name) | Direct observation | Likely inference | Unresolved |
|---|---|---|---|
| 0 "position" | Vector at `D+0x28` is evaluated as xyz and **replaces** local `t` in both `0x1411608b0` and `0x141160c80` | = file channel 0 | File→`D+0x28` mapping; X sign vs XML; whether "replace stored local" equals "additive to authored offset" (depends on what `def`/`[P+0x1a0]` contains) |
| 1 "rotation" | `D+0x40`, evaluated with the 2π wrap flag, sin/cos of three angles → rotation rows that replace local R | Euler radians = file channel 1 | Axis order, signs, X handedness |
| 2 "scale" | `D+0x58` read only by `0x141160c80` and `0x1411654e0`; default `(1,1,1,1)` or `def+0x80`. **Not read by `0x1411608b0`** (the barrelposition chain) | = file channel 2 | Whether any barrelposition evaluation reaches `0x141160c80` |
| 3/4 "pre/post scale" | `D+0x70`/`D+0x88` are axis-angle-like tracks used only in `0x141160c80` | Scale-orientation rotations | Meaning. No turret ANI in the 181-file cache has any key in groups 3 or 4 (shipped-source scan), so these are irrelevant to the corpus data |
| Key record | 144-byte in-memory key: value, time, per-axis enum, handles | 128-byte file record maps to it | Loader |
| Time | Local state time from `0x141165cd0`; key search clamps to first/last | Descriptor +148 = state duration in seconds (values 2.0 / 0.0333 / 0.3333 match selector frame spans / 30) | How the "settled active" instant is chosen; whether `turret_active` time stays inside `[0, dur]` |

---

## 5. Representative examples (shipped-source)

Endpoint per the #164 rule, from `corpus.csv`@`4de44fa`. Path format: endpoint ← parent part (owning connection) … root. Offsets are XML; blank means none authored.

### A. `turret_par_l_beam_01_mk1_macro` → `turret_par_l_beam_01_mk1` (base)

- Files: `assets/props/WeaponSystems/energy/turret_par_l_beam_01_mk1.xml` and `TURRET_PAR_L_BEAM_01_MK1_DATA.ANI`. Selected `con_laser_02` (hash `0x0c9442e72bbe5380`).
- Path:
  - `con_laser_02`: offset pos (−0.361773, 0.2692866, 10.70685), parent part `anim_barrel`
  - `anim_barrel` owned by `Connection05`: pos (−1.113896e-6, 0.06259775, 17.45395), quat (4.327045e-3, −6.55e-12, 2.8e-14, 0.9999906); parent part `anim_gun`
  - `anim_gun` owned by `Connection04`: **rotation_x min −5 / max 80**; pos (−1.730653e-6, 2.926126, −16.11956), quat (−4.327158e-3, 3.27e-12, −7.57e-10, 0.9999906); parent part `part_rotator`
  - `part_rotator` owned by `Connection03`: **rotation_y (unbounded)**; no offset; parent part `part_socket`
  - `part_socket` owned by `Connection01` (root): pos (1.877547e-6, 2.018104, −1.043081e-5). **Selectors here:** `turret_inactive 150–150`, `turret_activating 1–60`, `turret_active 60–61`, `turret_deactivating 90–150`, `gun_firing 70–80`
- No part-level offsets on the path. Mating connection: `con_turret_beam_l`.
- ANI: 25 descriptors (5 parts × 5 subnames). Descriptor +148: inactive 0.0333, activating 2.0, active 0.0333, deactivating 2.0, gun_firing 0.3333.
  - `(part_socket, *)` and `(anim_gun, *)`: all counts `[0,0,0,0,0]`
  - `(part_rotator, turret_active)` `[2,0,0,0,0]`: rec 8 value (0, 6.145042419, 0), enum 2,2,2, time 0.0; rec 9 same value, enum 1,1,1, time 1.0
  - `(anim_barrel, turret_active)` `[2,0,0,0,0]`: rec 17 value (0, **−0.239820004**, 27.710205078), enum 2,2,2, time 0.0; rec 18 same value, enum 1,1,1, time 0.3333
  - `(anim_barrel, turret_activating)` `[2,…]`: (0, −4.77e-7, 0) at t0 → (0, −0.23982, 27.7102) at t 2.0. `turret_deactivating` is the reverse; `turret_inactive` is 1 key (0, −4.77e-7, 0)
  - `(anim_barrel, gun_firing)` `[3,…]`: (0,−0.23982,27.7102) → (0,−0.170728,19.72694) at t 0.0333 → back at 0.3333 (recoil)
  - `(part_rotator, turret_inactive)` 1 key (0,0,0); activating (0,0,0) → (0,6.145,0)
- **Structure exposed:** there are no connection offsets on `Connection03`, and the ANI position on `anim_barrel` (z 27.71, y −0.2398) is of comparable magnitude to the authored `Connection05` offset (z 17.45, y 0.0626). So "replace the stored part local" and "add to the authored offset" give different results only if the stored/default part local differs from zero. That is the decisive unknown. Rotation_x sits on the owner of `anim_gun`; there are small ±0.0043 X quaternions on `Connection04`/`Connection05`.

### B. `turret_spl_m_beam_02_mk1_macro` → `turret_spl_m_beam_02_mk1` (ego_dlc_split); accepted #155 exact match

- Selected `con_beam_02` (hash `0x5836806a11999f04`).
- Path:
  - `con_beam_02`: pos (−2.397867, 2.193451e-4, 1.274741), parent part `detail_xl_barrel`
  - `detail_xl_barrel` owned by `Connection06`: pos (−2.474098e-8, −0.7722228, 1.42531); parent part `detail_xl_gun`
  - `detail_xl_gun` owned by `Connection05`: **rotation_x −10/90**; pos (−1.754811e-6, −0.09415483, −5.053287e-4); parent part `detail_xl_rotator`
  - `detail_xl_rotator` owned by `Connection04` (root, no parent): **rotation_y**; pos (0, 3.464102, 0). **Selectors here:** inactive 0–0, activating 0–45, active **50–50**, deactivating 55–100, gun_firing 50–55
- Depth 3 (the rotator's owner is the root). `part_socket` is a `ref="turret_spl_m_base_01.part_socket"` under a separate root `Connection01`.
- ANI: 25 descriptors. Durations: activating 1.5, active 0.0333, deactivating 1.5, firing 0.1667.
  - `(detail_xl_rotator, turret_active)` `[2,0,0,0,0]`: (0, 2.368033409, 0), enum **5,5,5** at t −0.6667 and enum 1,1,1 at t 0.6667. The handles hold 2.368033
  - `(detail_xl_gun, *)`: all zero counts
  - `(detail_xl_barrel, turret_active)` `[1,2,2,0,0]`:
    - ch0 (−4.47e-7, 1.19e-7, 3.431370258), enum 1, t 0.0
    - ch1 (−6.283185482, −0, 0) twice, enum 5 at t −1.0 and enum 1 at t 1.0
    - ch2 (0.999999821, 1.0, 1.000000238) twice, enum 5 then 1
  - `(detail_xl_barrel, turret_activating)` ch0: (0,0,1.19e-7) → … → (−4.47e-7,1.19e-7,3.43137) at t 1.5
- **Structure exposed:** channel-1 −2π (wrap-special-cased only for enum 2; here the enum is 5/1); a near-unit channel-2 scale; enum-5 keys with times outside `[0, dur]`. The current model ignores ch1/ch2 and matched LIVE to ~5e-5 m.

### C. `turret_arg_l_beam_01_mk1_macro` → `turret_arg_l_beam_01_mk1` (base); added for material non-unit scale

- Selected `con_laser_02` (hash `0x0c9442e72bbe5380`); current status "general composition unresolved" (no LIVE).
- Path:
  - `con_laser_02` (−5.052104, −0.03610229, 6.502319)
  - `detail_xl_barrel` owned by `Connection08`: (0, 0.1483345, 15.80571)
  - `detail_xl_gun` owned by `Connection06`: **rotation_x −5/90**, (−0.01497424, 0.2278442, −5.573472)
  - `detail_xl_rotator` owned by `Connection03`: **rotation_y**, (−0.0244168, 17.52643, −0.1001702)
  - `part_socket` owned by `Connection01` (root; selectors active 60–61 etc.)
- ANI `turret_active` on the path:
  - `(part_socket)` `[1,0,0,0,0]` (0,0,0)
  - `(detail_xl_rotator)` `[1,0,0,0,0]` (0,0,0)
  - `(detail_xl_gun)` `[2,0,1,0,0]`: ch0 (0,−1.9e-6,0) ×2; **ch2 (0.9976629, 0.9976629, 0.9976629)**, enum 1, t −2.0
  - `(detail_xl_barrel)` `[2,2,2,0,0]`: ch0 (0,3.4e-6,1.9e-6); ch1 (0,−0,0); **ch2 (0.997663 ×3)**
- **Structure exposed:** a uniform ~0.23% scale on both the gun and the barrel. Applied or ignored, it changes the barrel+endpoint lever (~16 m) by roughly 4 cm. This is the scale discriminator that A/B cannot provide, and it touches the `0x1411608b0` "no scale read" observation directly.

Corpus facts (shipped-source scan of 181 turret ANI files): **zero** keys in groups 3/4. Per the #164 report, active-path scale is present on 42 macros, and material non-unit on ARG/TEL L Beam 01 only.

---

## 6. Animation-state source

`/tmp/x4-official-scripts/base/libraries/animation_sequences.xml` (shipped-source; the pirate copy has no turret states):

- `turret_inactive` –(trigger `activate`)→ `turret_activating` –(no trigger)→ `turret_active`
- `turret_active` –(`deactivate`)→ `turret_deactivating` → `turret_inactive`
- `turret_active` –(`fire`)→ `gun_firing` –(no trigger)→ `turret_active`
- There is **no** `turret_active → turret_active` self-loop. `turretloop_active` does self-loop and has `turretloop_firing` (a separate family).
- File comment: "Hardcoded check for "turret_active" in x4-code".

Component selectors (shipped-source): `<animation name start end>` on one connection (`Connection01` for A/C, `Connection04` for B), frame spans as in §5. No component-level inheritance attribute exists. Propagation from that connection to descendant parts' ANI descriptors is **not established by source**. The executable shows one state object per controller entry (`[E+0x50]`, vcall +0x38 → descriptor); how entries map to parts and selectors is **unresolved**.

Not established by shipped source:

- Which state or time the prospective "deployed, non-recoiling" reference uses. A reasonable candidate is `turret_active` at any `t ∈ [0, dur]`, or the terminal value of `turret_activating`, but that is a design choice.
- Whether yaw/pitch joint rotation is inserted into `def`, into the stored part local, or into a separate scene matrix (`[P+0xe8]&0x30` path). How restrictions map to runtime joints is not visible in the inspected functions.

---

## 7. Validation holdouts (do NOT use to derive rules)

Known-good, recorded #155 results (live-tested; raw paired native logs for these were **not** found locally, per A4):

| Macro | Max error |
|---|---|
| Split M Beam 02 | ~0.000050 m |
| Split M Laser 02 | ~0.000028 m |
| Split M Plasma 02 | ~0.000048 m |
| Terran M Beam 02 | ~0.000038 m |
| Terran M Laser 02 | ~0.000048 m |

`/tmp/x4-155-debug.log` (621,881 B) survives: debug side only.

Known-bad raw #75 case (live-tested; A4 at `4087cb7`):

- `turret_par_l_beam_01_mk1_macro`, intended endpoint `con_laser_02`. Settled ticks 276..414 error 0.2398683..0.2398685 m; wrong endpoint `con_laser_01` 0.7622569..0.7622876 m.
- Residual is overwhelmingly endpoint-local +Y.
- Removing only the current descriptor-22 channel-0 Y term (−0.23982000350952148) collapses it to ~0.001031 m. **Diagnostic only; not proof of any rule.**
- Paired logs still exist, untouched:
  - `/mnt/c/Users/PC/Documents/Egosoft/X4/51053644/debug.log`: 743,879 B, 2026-09-14 08:37:56; 620 lines mention the macro
  - `/mnt/c/Users/PC/Documents/Egosoft/X4/51053644/x4native/x4_barrel_orientation_probe/barrel-orientation.log`: 530,450 B, 2026-09-14 08:37:56
  - Validator: `research/barrelposition-orientation-probe/validate-measurement.py`

---

## Exact questions the expensive model must answer

In dependency order. "Where" is the most likely place to answer each.

1. **Which runtime path does the barrelposition call actually take for a mounted turret?**
   - Evidence: gate `[weapon+0x208]`/`[..+0x48]` in `0x14081c960`; arg5 = NULL; LIVE pairs to this function's output.
   - Unknown: whether the gate is ever false in-game; whether `bit9([P+0xe8])` / `[E+0x88]&1` holds for every path part; whether `0x14074be30`'s scene branch (`[C+0x150]`, `[C+0xf0]&0x40`) fires mid-chain.
   - Where: `0x14081c960`, `0x14074be30`, `0x14074c2d0` gates; the setters of `[P+0xe8]` bits 9/0x30 and `[C+0x150]` (search writes to those offsets).
2. **Fixed parent/child order.**
   - Evidence: observed `conn_local ∘ parentPartWorld` and `partLocal ∘ ownerConnWorld` in a row-vector convention.
   - Unknown: confirm there is no other matrix between them (`0x140e20370`, `0x140757bc0` side effects); what vcall `+0x1448` returns and why translation is scaled at every level and again at the end.
   - Where: `0x140e22b70`, `0x14074c2d0`, `0x14074be30`, `0x140757bc0`, vtable `+0x1448` implementation.
3. **What is `conn_local` (`[C+0x60..0x9f]`) and the stored part local (`[P+0x1a0]`) / animation default (`[E+0x48]+0x40..0x7f`, `+0x80`) built from?**
   - Evidence: none linking them to XML yet.
   - Unknown: whether conn_local = XML connection offset (pos+quat); whether the part default = XML part offset, identity, or geometry bind pose; the X-handedness conversion at load.
   - Where: the component loader near `0x140886940..0x140889193` (#164 connection storage, stride `0x160`); writes to `+0x60` there; writers of `+0x1a0` and `[E+0x48]+0x40`.
4. **Joint pivot, axis, sign, and frame insertion.**
   - Evidence: none in the inspected functions (no restriction/angle input visible).
   - Unknown: where yaw/pitch enter. Candidates: modifying `conn_local`, the stored part local, `def`, or the scene matrix array (`[P+0xe8]&0x30`, `word[P+0xe0]`) that this path bypasses.
   - Where: readers of the `rotation_x`/`rotation_y` restriction data; the turret aiming update that writes a part/connection matrix; writers of `[C+0x60]` or `[P+0x1a0]` at runtime.
5. **ANI file → in-memory descriptor and key layout.**
   - Evidence: 144-byte keys; vectors at `D+0x28/+0x40/+0x58/+0x70/+0x88`; plausible slot mapping (§4).
   - Unknown: the actual loader; channel order → vector offsets; X negation or other conversion; time units/offset; what file slots 19–31 feed.
   - Where: `0x141165340` → `0x1414bab90` → `0x141163e40` and the `0x141163510..0x1411642ef` cluster; search for stride-`0x90` allocation or a copy from a 128-byte stride.
6. **Key evaluation for the reference state.**
   - Evidence: `0x14115fdc0` search/clamp, enums 1/2/5/6/7, 2π wrap on enum 2.
   - Unknown: exact `0x1414dd440`/`0x1414dd4c0`/`0x141160280` math (only needed where enums 5/6/7 carry unequal values); `0x141165cd0` local time and the `0x141166050` branch.
   - Where: those addresses.
7. **How the ANI result combines with authored/static transforms.**
   - Evidence: in `0x1411608b0` the ANI position/rotation **replace** `def.t`/`def.R`; in `0x14074c2d0` the animated local **replaces** `[P+0x1a0]`.
   - Unknown: whether `def` already contains the XML part/connection offset (making ANI absolute) or ANI is relative to something else. Only this distinguishes "additive" from "replacement".
   - Where: depends on Q3 and Q5.
8. **Selector/state propagation.**
   - Evidence: the XML selector sits on one connection; `[E+0x50]` state object, vcall `+0x38(time)` returns the descriptor; no `turret_active` string in the exe.
   - Unknown: controller entry ↔ part mapping (`word[P+0xe2]`); how an entry resolves `(part, subname)`; hash-based state names; how the entry's state follows the selector-bearing connection.
   - Where: the vtable of `[E+0x50]` (slot +0x38, +0x50); `0x1411655b7` onward (uses `0x811c9dc5`, a name hash).
9. **Defaults when a channel has no keys.**
   - Evidence: missing position → `def+0x40`; rotation → `def+0x50..`; scale → `def+0x80` or `(1,1,1,1)`; no descriptor → the whole default matrix.
   - Unknown: the default contents (Q3).
10. **Scale / pre / post-scale.**
    - Evidence: the barrelposition chain's `0x1411608b0` ignores `D+0x58/+0x70/+0x88`; groups 3/4 are empty corpus-wide.
    - Unknown: whether any barrelposition evaluation reaches `0x141160c80` (e.g. via `0x14074c770` / `[P+0xe8]&0x30`); what vcall `+0x1448` is. Example C is the discriminator.
    - Where: `0x14074c770` (caller `0x140745920`), `0x141160c80`, vtable `+0x1448`.
11. **Scene-backed vs static fallback.**
    - Evidence: `0x14074c520` normalizes rows (strips scale); the scene path doesn't.
    - Unknown: whether the #79 offline evaluator should model only the scene-backed path.
    - Where: Q1 answer plus `0x14074ccb0`.
12. **Final ancestor composition.**
    - Evidence: recursion ends at a connection with no parent part; the output is component-space (then weapon/ship?).
    - Unknown: whether the result is turret-component-local, or includes the mount/ship world transform. Needed to compare against LIVE capture rows.
    - Where: the root case of `0x14074be30` (`[C+0x40]==0`) and the object at `[weapon+0x208]+0x48`.

## Recommended first expensive-model move

**Resolve Q3 and Q7 together: find where the component loader fills connection local `[C+0x60..0x9f]`, the stored part local `[P+0x1a0]`, and the animation default matrix `[E+0x48]+0x40..0x8f`, and relate each byte-for-byte to the XML connection offset, the XML part offset, and ANI channel-0/1 values** (using example A's `Connection05` / `anim_barrel` values as a static data check, not a LIVE residual fit).

Why this is first: `0x1411608b0` shows ANI position/rotation *replacing* a default local transform, so "additive vs replacement" and the handedness conversion are decided entirely by what those defaults contain. Every downstream question (ANI combination, defaults, joint insertion frame, and whether the Paranid −0.23982 term is double-counted) depends on it. Start from the #164 connection-storage loader (`0x140886940..0x140889193`, stride `0x160`) and trace the writes to connection offset `+0x60` and part offset `+0x1a0`.
