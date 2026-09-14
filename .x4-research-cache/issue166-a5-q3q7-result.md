# A5 Q3/Q7 — local/default transform provenance

## 1. Verdict

**RESOLVED — for the construction and evaluator meaning of the three requested regions on the traced selected-connection path.** Runtime restriction-state evaluation remains a separate dependency; this is not a complete turret interpreter or a claim that a mounted instance necessarily takes every animation gate.

**shipped-source:** The animation default has **zero translation, the stored XML part-local rotation, and unit scale**. It does not contain the connection transform, the part's authored translation, or a geometry bind matrix. ANI position/rotation tracks replace these default components. Their loader does not first add or multiply an authored transform into the keys.

**inference:** Thus ANI supplies an **absolute component of the animation-local part transform**, relative to its owning connection. It is not an absolute component/world pose. With an identity part offset it acts like an extra motion layer before the connection transform, which can resemble addition in an unrotated example. That special case does not justify the current generic additive interpretation.

### Evidence scope and reproducibility

- **shipped-source:** X4 9.00 executable at `/mnt/c/Program Files (x86)/Steam/steamapps/common/X4 Foundations/X4.exe`, SHA-256 `19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`, independently rechecked. Addresses below are VAs; image base `0x140000000`.
- Repository HEAD remained `9db48f65a3969172643cb6380f04a22661c69592`. Neither that temporary stash nor its interpretations were treated as accepted evidence. Production/research baseline: `4087cb72855977ec69e5b3f3012e69cc0e165326`.
- **shipped-source:** Official XML/ANI inputs and hashes are in `issue166-a5-work/verification.txt`. Source roots are `official-source-sets/{base,ego_dlc_split}/` and `issue72-a2-ani-resources/{base,ego_dlc_split}/`, relative to `.x4-research-cache/`.
- Reproduce disassembly with `/tmp/x4-offline-validation/x4-re.py START END`, or `issue166-a5-work/annotate.py START END`. Explicit ends matter: `.pdata` splits several functions. Saved `.dis` files are working evidence, not public symbols.
- **inference:** All descriptive function roles in this report are reverse-engineering interpretations. No invented function-purpose name is promoted to an exported symbol. Literal diagnostic strings corroborate roles only.
- No new `live-tested` conclusion. No LIVE residual was used in selecting a rule or checking the calculations. No game launch, installation, production edit, test edit, GitHub change, commit, or push.

Notation: `C` is the connection object; `P` is its owned part when discussing a segment; a connection's parent part is a different pointer at `[C+0x40]`. `E` is the per-owner animation entry; `A=[E+0x48]` is its shared source/default object; `D` is the selected in-memory descriptor. Matrices are written as `[t; X; Y; Z]`. `L ∘ B` means apply local `L`, then parent `B`.

## 2. Proven data-flow chain

### Connection `[C+0x60..0x9f]`

**shipped-source — initialization and XML load:**

```text
official component <connection><offset>...
  → 0x140886940 component-load region
  → connection array, stride 0x160, at definition+0x170
  → 0x140955440 initializes each C
  → 0x140881db0 receives C and its XML node
  → 0x1408822ba recognizes child token 0x1b5 (offset)
  → 0x1408822d8: rcx=C+0x60, rdx=offset node
  → 0x1408822df calls 0x140484590
  → C+0x60 = XML position; C+0x70/80/90 = XML rotation rows
  → 0x14074be62..0x14074be87 copies the four rows into its output
  → connection-world composition, then parent-part recursion
```

At `0x14095545b`, `rbx=C+0x28`. `0x1409554d4` stores zero at `rbx+0x38 = C+0x60`; after advancing `rbx` by `0x160`, stores at `0x1409554e6/4f4/502` place identity X/Y/Z at the original C's `+0x70/+0x80/+0x90`. The reallocation path `0x1409607e9..0x1409608c8` also initializes those rows. Constants `0x1422c01d0/e0/f0` are `(1,0,0,0)`, `(0,1,0,0)`, `(0,0,1,0)`.

**shipped-source:** `0x1408822e4..0x14088232c` copies the resulting rotation to `C+0xb0/c0/d0` and translation to `C+0xe0`, with an explicit homogeneous-lane mask/set. These are additional representations; the selected evaluator reads `C+0x60..0x9f`.

**shipped-source — later processing:** The post-load routine `0x140889cb0` reads this local matrix (e.g. `0x14088b935..0x14088b9fa`) to construct other matrices. It does not replace these four source rows in the inspected flow. The scene-backed path `0x140e22b70` also reads them and composes a separately produced runtime matrix with them; see the handoff correction below.

**inference:** This is an authored connection-local transform stored in component source data, not a matrix imported from mesh bind-pose data. Its physical array location and its subsequent copying distinguish it from the temporary world/result matrices.

### Part `[P+0x1a0..0x1df]`

**shipped-source — initialization and XML load:**

```text
official direct <part><offset>...
  → part allocation, 0x1408828de..0x140882a45 (size 0x200)
  → identity at P+0x1a0/1b0/1c0/1d0
  → 0x140882ad5 calls 0x1408805b0(P,C,part XML,...)
  → 0x1408805e0 stores owning C at P+0x170
  → 0x140880649 recognizes direct child offset, token 0x1b5
  → 0x140880667: rcx=P+0x1a0
  → 0x140880672 calls the SAME 0x140484590 XML reader
  → stored part-local t/R
  → static branch 0x14074c37c..0x14074c3a7 copies these four rows
  → 0x14074c406 obtains owning connection world
  → 0x14074c40b..0x14074c4bb composes part-local before connection-world
```

Identity writes are `0x1408829ff`, `0x140882a0d`, `0x140882a1b`, `0x140882a29`. No direct part offset leaves identity. The direct child search does not recursively take the owning connection's offset or offsets buried in part lights/materials.

**shipped-source:** The animated branch at `0x14074c353..0x14074c37a` calls `0x141165440` and jumps over the stored-local copy. The stored part matrix is not subsequently multiplied into the animated result.

**shipped-source — adjacent pivot, not a hidden geometry default:** A separate direct `<part><pivot><offset>` is recognized by token `0x1e5` at `0x1408806a9`, then `0x1b5` at `0x1408806fc`. `0x140880719..0x14088073b` allocates a separate 64-byte matrix, initializes/reads it through `0x14086bc50 → 0x140484590`, and stores its pointer at `P+0x1e0`. That pointer is initialized null at `0x140882a30`. It is not an alternate source for `P+0x1a0`.

**inference:** XML direct-part transforms are genuine separate local transforms. They are retained for the static path; the animation path substitutes an animation-local matrix. XML pivot data participates in separate derived/baked matrices, not in the requested default rows.

### Animation source/default `[E+0x48]+0x40..0x8f`

**shipped-source — complete part-to-default argument chain:**

```text
P initialized and loaded as above
  → 0x140880d10 obtains/creates the part's animation source A
  → 0x140880d5e: rax=P+0x1b0         # ROTATION ONLY
  → 0x140880d6c: caller stack arg5=rax
  → 0x140880d75: r8=P
  → 0x140880d83 calls 0x141161fe0
  → 0x14116201c/024 forwards arg5 as constructor arg6
  → 0x14116203a calls 0x141162210
       A+0x40 := (0,0,0,0)           # explicit xorps/store
       A+0x50 := [P+0x1b0]
       A+0x60 := [P+0x1c0]
       A+0x70 := [P+0x1d0]
       A+0x80 := (1,1,1,1)
  → 0x140880d88 caches A at P+0x1f0
  → 0x140755145 retrieves A
  → 0x140755156..175 selects E by word[P+0xe2], stride 0x90
  → 0x140755290 passes A as rdx to 0x141164460
  → 0x14116447e stores A at E+0x48
  → 0x141165494 passes A as r8 to 0x1411608b0
```

Critical constructor instructions, `0x1411622a7..0x1411622e8`:

```text
rax = callee_stack_arg6
xorps xmm0,xmm0
movups [A+0x40],xmm0
movups xmm0,[rax];      movups [A+0x50],xmm0
movups xmm1,[rax+0x10]; movups [A+0x60],xmm1
movups xmm0,[rax+0x20]; movups [A+0x70],xmm0
movaps xmm1,[0x142cc23b0]; movups [A+0x80],xmm1
```

**shipped-source — other initialization and later writes:**

- `0x141162130..0x141162208`, the no-argument initialization form, writes zero translation, identity rotation, unit scale, and identity auxiliary rotations. This is distinct from the part-binding constructor above.
- `0x1411622ef..0x14116233c` initializes auxiliary default rotations at `A+0x90..0xef` to identity. Neither connection rotation nor pivot is copied there.
- The remainder of `0x141162210` reads the optional `P+0x1e0` pivot, but stores its derived matrix at **A+0xf0/100/110/120**, at `0x1411628a5..0x1411628ba`. It does not rewrite `A+0x40..0x8f`.
- Eager binding `0x141163c00`, reached at `0x1411620e0`, fills descriptors under `A+0x28`. Lazy binding `0x141165340 → 0x141163e40` does likewise. Their full-track evaluations write **D+0xc0..0xff**, at calls `0x141163d72` and `0x141163f83`, not A's defaults. The no-resource path `0x141163fe0` fills placeholder descriptors, also separately.
- Entry copy `0x1411646a5/6a9` copies the **pointer** at E+0x48. It does not make another per-instance copy of the defaults.
- `0x1411654a8..0x1411654c7` copies the entire default local matrix when no descriptor is returned. Otherwise `0x1411608e0` supplies missing-position default and `0x141160916..92a` supplies missing-rotation defaults.

**inference:** A is a cached source/default object, while E contains mutable per-owner controller state. The exact default relationship is `A.t=0`, `A.R=P.local.R`; it is **not** `A.local=P.local`. In particular, XML direct-part translation is omitted in this construction, even when position keys are absent on an enabled animation entry.

### Writer coverage and runtime separation

**shipped-source:** The concrete allocation, XML-load, eager-bind, lazy-bind, copy, and evaluator paths above identify the writes establishing the requested regions. In these paths later operations write descriptors, derived caches, or caller output matrices. `0x140757bc0`, the conditional post-step in part-world evaluation, writes its supplied output rotation rows at `0x140757d8a/7d96/7da5`; its output pointer is not P's stored-local address.

**inference:** Targeted displacement scans (`offsetrefs.json`, `targetrefs.json`, `writer_audit.out`) corroborate this separation but are not, by themselves, a whole-program alias analysis. Equal offsets in unrelated objects were not counted as target-field writers: for example, the `0x140d7c230` family also writes vector data over `+0x170/+0x180`, whereas P has an owning-connection pointer/name there. No runtime replacement of the requested source/default regions was identified in the traced lifecycle. This report does not assert universal immutability against every unrelated subsystem or memory alias.

## 3. Exact transform semantics established

### XML reader and matrix construction

**shipped-source:** Token meanings are established by the executable's string/ID table, not guessed from neighboring code. Examples: `0x1422ca340 → offset/0x1b5`, `0x1422ca730 → position/0x1f4`, `0x1422ca870 → quaternion/0x208`, `0x1422cacb0 → rotation/0x24c`; `0x1422cbab0/ac0/ae0 → x/y/z`; `0x1422ca890..8c0 → qw/qx/qy/qz`; `0x1422ca630 → pitch`, `0x1422cac60 → roll`, `0x1422cbad0 → yaw`.

**shipped-source:** `0x140484590`:

1. Reads direct position through `0x14049d760` and writes `(x,y,z,0)` directly. The scalar attribute helper is `0x140129150 → 0x1414c2bd0`. No axis-specific negation or scaling is applied.
2. If `<rotation>` exists, `0x140484698` tail-calls `0x14049d7e0` with the output rotation-row address.
3. Otherwise `<quaternion>` is read at `0x1404846e9` by `0x14049da10`, then converted at `0x1404846f5` by `0x1400d1fb0`. Rotation takes precedence if both forms exist.

**shipped-source — quaternion operation:** `0x14049da10` packs `(qx,qy,qz,qw)` without sign changes. `0x1400d1fb0..0x1400d209e` constructs the following rows, without normalizing the quaternion. Here `x,y,z,w` are its four supplied components:

```text
X = (1-2y²-2z²,  2xy+2zw,     2xz-2yw)
Y = (2xy-2zw,     1-2x²-2z²,  2yz+2xw)
Z = (2xz+2yw,     2yz-2xw,     1-2x²-2y²)
```

**shipped-source — Euler operation order:** Define right-handed row-vector matrices explicitly:

```text
Rx(a) = [[1,0,0], [0,c,s], [0,-s,c]]
Ry(a) = [[c,0,-s], [0,1,0], [s,0,c]]
Rz(a) = [[c,s,0], [-s,c,0], [0,0,1]]
```

XML `<rotation pitch=p yaw=y roll=r>` is constructed as

```text
R_XML_Euler = Rz(-r) · Rx(-p) · Ry(y)
```

with each XML angle multiplied by float `0.01745329238474369` at `0x142cbe1c8`. Critical construction: `0x14049d821..0x14049d898` reads/converts angles; `0x14049d89d..0x14049d9db` builds/composes/stores rows. ANI's order below is different. The equations are algebraic transcriptions of the SIMD operations; descriptive angle-convention interpretation is **inference**.

### ANI file → descriptor → evaluated transform

**shipped-source:** `0x141161dd0` receives a file buffer/length, copies it at `0x141161e81`, and establishes:

```text
F+0x98 = copied file header
F+0xa0 = copied file + 16
F+0xa8 = copied file + int32(header+4)
```

See `0x141161e86..0x141161f14`; descriptor size checks use `count*160+16`, key storage checks use `count*128`. No transform conversion occurs in this initialization. The vtable entry for this method is `0x142c803d8`; the diagnostic strings explicitly concern an animation file.

**shipped-source:** `0x141161900` matches the descriptor's first and second 64-byte names, then maps file counts `+0x80/+0x84/+0x88/+0x8c/+0x90` to D's five vectors `+0x28/+0x40/+0x58/+0x70/+0x88` at `0x141161ae6..0x141161b5d`. This proves the first two file groups' association with evaluated position and Euler rotation without using converter terminology.

**shipped-source:** `0x1411615d0` advances through 128-byte file records, creating 144-byte in-memory records. Critical mapping:

| File key bytes | In-memory key bytes | Instructions |
|---|---|---|
| `+0..+11`, XYZ | `+0..+11`, same XYZ; w=0 | `0x1411616c1..0x1411616cd` |
| `+12/+16/+20` | `+0x80/+0x84/+0x88`, axis enums | `0x1411616d0..0x1411616e5` |
| `+24` | `+0x60`, time | `0x141161733/736` |
| `+28..+75` | `+0x30..+0x5f`, handles | `0x1411616eb..0x141161730` |

The remaining payload/optional indirect-key copy is at `0x141161739..0x1411618ca`; the ordinary record advance is `0x1411618ce`. None adds authored translation, multiplies a connection matrix, or negates X. Binding the resulting vectors does not perform such an operation either.

**shipped-source:** `0x1411608b0` produces:

```text
t = D.position.empty ? A.t : evaluate(D.position,time)
R = D.rotation.empty ? A.R : R_ANI(evaluate(D.rotation,time))
R_ANI(x,y,z) = Rx(-x) · Rz(-z) · Ry(y)
```

Position selection/store: `0x1411608db..0x14116090a`. Rotation-default copy: `0x141160911..0x14116092a`. ANI Euler construction: `0x141160965..0x141160b06`. There is no multiplication by A.R after selecting ANI rotation and no addition of A.t after selecting ANI position. Groups 2–4 are not read by this evaluator.

**shipped-source:** The angle helper `0x141750253` interleaves `(x,x,y,y)` and adds `(0,π/2,0,π/2)` from `0x141c685c0` before the shared trigonometric implementation. `0x141750210` supplies the single-angle pair. Sign bits used in matrix assembly come from `0x142cc2a70`. There is no degrees-to-radians factor in ANI evaluation.

**inference:** ANI XYZ translation already uses the numeric coordinate axes consumed by this scene path. The current `[-x,y,z]` position conversion has no support here and contradicts the observed unchanged-XYZ data flow. Euler sign/order differences are explicit matrix conventions; they do not establish a blanket handedness conversion of position vectors. Exporter-side history before the shipped ANI bytes is not established or needed for this rule.

### Composition and a correction to the handoff

**shipped-source:** `0x14074c40b..0x14074c438` calculates

```text
part_world.t = part_local.x * connection_world.X
             + part_local.y * connection_world.Y
             + part_local.z * connection_world.Z
             + connection_world.t
part_world.R = part_local.R · connection_world.R
```

This proves `partLocal ∘ owningConnectionWorld`. The connection recursion composes before its parent part. The static/default part and connection matrices are separate layers, not precombined ANI keys.

**shipped-source — handoff correction:** `0x140e22bca` calls `0x140e20370` with the output initially identity. This call is not merely an ignorable update. At `0x140e20410..0x140e20447` it searches connections and counts their `[C+0x150]` restriction records. It evaluates separate runtime scalar objects (stride `0x680`) through vcall `+0x28` at `0x140e204bd`, builds a matrix into the supplied output through `0x1404b5f20` at `0x140e20521`, and returns. With no matching records, the initialized identity remains.

`0x140e22bfb..0x140e22ce7` composes this output with **C's authored local matrix**; it does not simply copy C's rows. Therefore write this part of the chain as `J_C ∘ C_authored`, where the purpose-name `J_C` is **inference**. Parent-part composition follows. This does not alter C's stored rows or A's defaults.

**inference — unresolved outside the recovered defaults:** The complete mapping from runtime restriction scalar state to physical joint axes/signs/reference values, and the runtime scale returned by owner vcall `+0x1448`, are not proved here. Numerical segment calculations below use unit instance scale and unrestricted segments, so neither supplies a fitted parameter.

## 4. Paranid static calculation

**shipped-source:** Primary input is `base/assets/props/WeaponSystems/energy/turret_par_l_beam_01_mk1.xml` and its independently cached `TURRET_PAR_L_BEAM_01_MK1_DATA.ANI`. The component's `<source geometry>` explicitly selects that resource family. For `Connection05 → anim_barrel`:

```text
connection position = (-1.113896e-6, 0.06259775, 17.45395)
connection quaternion = (0.004327045, -6.547686e-12,
                          2.825544e-14, 0.9999906)
part direct offset = absent
part pivot = absent
Connection05 restrictions = absent
ANI (anim_barrel,turret_active), zero-based descriptor 22:
    position keys = (0,-0.23982000350952148,27.710205078125), twice
    times = 0 and approximately 0.3333; enums = 2 then 1
    rotation keys = absent
```

**inference — static derivation using the generic rule:** Choose this named active descriptor; this does not assert which descriptor a particular live instance selects. Both position endpoints are identical, so linear interpolation or endpoint clamping gives the same translation. Stored P.local is identity; A.t=0, A.R=I, A.scale=(1,1,1,1). Evaluated part-local is therefore:

```text
L.t = (0,-0.23982000350952148,27.710205078125)
L.R = I
```

Using float32-rounded source inputs and the quaternion equations above:

```text
C.R ≈ [[ 1,             -1.53913e-16,  1.30955e-11],
       [-1.13175e-13,    0.999962553,  0.00865400814],
       [-1.30950e-11,   -0.00865400814,0.999962553]]

segment = L ∘ C                 # anim_barrel-local → anim_gun-local
segment.t = L.t · C.R + C.t
          ≈ (-0.000001114259, -0.417017612, 45.161042902)
segment.R = C.R
```

This is neither replacement of `Connection05.position` by ANI nor componentwise addition of ANI in the connection's parent frame. The ANI translation is rotated by the connection basis before the connection translation is added. No endpoint or ancestor transform is included in this segment result.

**inference — numeric precision boundary:** These numbers are real-arithmetic transcriptions using shipped float values, rounded for presentation. They are not a bit-exact emulation of all SSE rounding or the engine's trigonometric approximation. No LIVE value was compared.

## 5. Independent static cross-check

**shipped-source:** Use `ego_dlc_split/assets/props/WeaponSystems/energy/turret_spl_m_beam_02_mk1.xml` and `TURRET_SPL_M_BEAM_02_MK1_DATA.ANI`, specifically the unrestricted `Connection06 → detail_xl_barrel` segment:

```text
connection position = (-2.474098e-8,-0.7722228,1.42531)
connection rotation = absent; direct part offset/pivot = absent
ANI (detail_xl_barrel,turret_active):
    position = (-4.4730001036441536e-7,1.1920000275722487e-7,
                 3.431370258331299), one STEP key
    Euler = (-6.2831854820251465,-0,0), equal endpoints/handle values
    group 2 has near-unit values; ignored by 0x1411608b0
```

**shipped-source:** The rotation's first enum is 5. Its two values and in/out value handles are equal. `0x1414dd440..0x1414dd4b8` implements the cubic Bernstein combination with coefficients `(1-u)^3, 3u(1-u)^2, 3u²(1-u), u³`; equal inputs remain constant algebraically. The enum-2 special case for exact float 2π is not applied to enum 5.

**inference — same calculation, no Split-specific rule:**

```text
A.t=0, A.R=I
L.t = raw ANI position
L.R = Rx(+6.2831854820251465)
segment = L ∘ C
segment.t ≈ (-0.000000472041,-0.772222698,4.856680274)
segment.R ≈ [[1,0,0],
             [0,1, 1.74846e-7],
             [0,-1.74846e-7,1]]
```

The small sine is a consequence of the stored float being near, rather than mathematically equal to, 2π; the displayed basis uses mathematical sine, not a claim of engine-bit precision. Crucially, the negative ANI X remains negative. This example independently exercises unchanged position signs, rotation-track replacement, and separate connection composition.

**inference — calculation check:** `issue166-a5-work/static_calc.py` parses only the named official XML/ANI inputs, imports no production semantic rules, and reenacts the relevant SIMD shuffles/products with mathematical sine/cosine substituted at the angle-helper boundary. Multi-axis checks recover `Rx(-x)Rz(-z)Ry(y)` for ANI and `Rz(-roll)Rx(-pitch)Ry(yaw)` for XML to floating-point arithmetic precision. `static_calc.out` preserves values and handle inputs. This is a static algebra check, not a game execution or permanent test.

## 6. Consequences for the current code

| Current assumption | Assessment | Evidence class and reason |
|---|---|---|
| ANI translation is generally additive to authored offsets | **Contradicted as a generic rule** | **shipped-source:** The evaluated value replaces animation-local t; P.local is bypassed. C remains a separate parent transform. **inference:** For zero part-local translation it can look additive, but only after expressing ANI in the connection's parent frame. |
| ANI X must be negated | **Contradicted on this path** | **shipped-source:** File XYZ → key XYZ → evaluated XYZ is unchanged; XML XYZ is also written unchanged. |
| Add ANI Euler to authored part rotation | **Contradicted as a generic rule** | **shipped-source:** A.R comes from the part's authored R, but a present rotation track replaces it. ANI also has the explicit order/sign convention above. |
| Authored part local occurs inside/before owning connection local | **Supported** | **shipped-source:** `P.local ∘ C.world` in the static branch. |
| Always retain authored part position/rotation after applying ANI | **Contradicted** | **shipped-source:** Static-local copy is skipped on the animated branch; its rotation survives only as the missing-rotation default, while its translation is not copied into A. |
| Insert raw ANI translation before applying connection rotation in the current root-to-leaf accumulation | **Contradicted** | **shipped-source:** Engine segment translation is `ANI.t · C.R + C.t`; this is equivalent to applying C's frame to the inner translation in a column-vector/root-to-leaf implementation. |
| Groups 2–4 affect this local evaluator | **Contradicted for 0x1411608b0** | **shipped-source:** It reads only D+0x28 and D+0x40. Broader scale behavior remains **inference — unresolved**. |
| Current yaw/pitch pivot, sign and split | **Still unproved** | **inference:** The restriction-driven matrix J is separate and was omitted from the handoff's simplified connection pseudocode. |

**inference:** The source rules supersede the hand-built additive/handedness assumptions; this report does not propose or authorize a production patch. It does not validate either current geometry or any prior residual diagnosis.

## 7. Single next dependency

**Resolve the runtime restriction-state matrix `J_C`: how a connection's restriction record selects the per-instance scalar state and how that value becomes the physical joint rotation, including its axis, sign, pivot and insertion frame.**

**shipped-source starting path:** `C+0x150` records → `0x140e20410..0x140e20483` record indexing → scalar-object stride `0x680` → virtual evaluation at `0x140e204bd` (`vtable+0x28`) → component dispatch at `0x140e204c0..0x140e204d9` → matrix construction `0x1404b5f20`, called at `0x140e20521` → `J_C ∘ C_authored` in `0x140e22bfb` onward.

**inference:** This is the most direct remaining engine question for a generic articulated interpreter. The default construction recovered here does not itself answer it. Stop before implementing the interpreter or validating against LIVE holdouts.
