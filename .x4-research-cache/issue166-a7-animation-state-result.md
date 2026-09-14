# Issue #166 A7: animation selector/state propagation and local time

## Verdict

**RESOLVED**

**Scope.** This covers the deployed, ready, non-firing reference state on the selected-endpoint path for all 92 candidates. It uses the default per-instance animation settings. Per-instance XML overrides (`time`, `reverse`, `default`, start/end path time) are listed as a non-default input in §State transition rule. None of the offline reference state depends on them.

**Evidence.**
- `X4.exe` SHA-256 `19750a65…6891` (unchanged from A5/A6); VAs with image base `0x140000000`.
- Official XML/ANI under `.x4-research-cache/official-source-sets/` and `issue72-a2-ani-resources/`.
- `/tmp/x4-official-scripts/base/libraries/animation_sequences.xml`.
- Tools, dumps and the corpus scan are in `.x4-research-cache/issue166-a7-work/`:
  - `xd.py`: chunk-following disassembler
  - `tok.py`: XML token ids
  - `rtti.py`
  - `corpus_animation.py` with `.json`/`.out`
  - `*.dis`

**Labels.** Class names come from compiler RTTI strings, which are **shipped-source** (`.?AVSlaveAnimatedValue@Animation@U@@`, `.?AVSequenceControlUnit@Animation@U@@`, `.?AVTurret@U@@`, …), as do the engine's own diagnostic strings. Other purpose labels are **inference**.

**LIVE data.** No new `live-tested` claim and no LIVE residual was used to choose a state or time.

One disclosure. While tracing, the static bind path alone seemed to leave descendant parts unanimated. That conflicts with the accepted #155 Split M Beam 02 geometry, which applies the `detail_xl_barrel` ANI translation. That conflict was used only as a signal that the trace was incomplete. The executable then showed the missing mechanism directly (§Selector propagation). It did not select any rule, state or time.

Notation follows A5/A6. `C` is a connection, `P` a part, `A = [E+0x48]` the per-part "master" source object, `E` a per-instance `SlaveAnimatedValue`, `U = [E+0x50]` its control unit, and `D` a bound descriptor (stride `0x100`).

## Part/controller binding

**shipped-source**

```text
post-load 0x14088b0bd..0x14088b12a   (for every definition connection C, owned part P=[C+0x128])
    [P+0xe8] = [C+0xf0]                                   ; flags copied, incl. bit 9
    if bit9([P+0xe8]):  word[P+0xe2] = word[def+0x194]++  ; dense index, one per animated part
    (bit 0x30 → word[P+0xe0] = def+0x192 counter; bit 7 → word[P+0xe4] = def+0x196 counter: texture animations)

instance init 0x140754d30 ("Positional::InitPartAnimations" strings)
    vector<E> [owner+0x208] resized to word[def+0x194], stride 0x90
    element default ctor 0x1407b3390:
        vtbl 0x142c801e0 (RTTI SlaveAnimatedValue); E+0x08=-1.0; E+0x30=4 (inline cap); E+0x38..0x60=0;
        E+0x68=-1.0; E+0x70=0; E+0x78=-1.0; E+0x80=-1.0; byte E+0x88=0
    for C in def connections with bit9([C+0xf0]):          0x140754fa0..0x140754ffa
        0x140755110(owner, C, P=[C+0x128], initialStateHashPtr = owner->vtbl[0x1ad0](C))
            A = 0x140880d10(P)          ; cached at P+0x1f0; created by 0x141161fe0 with [C+0x140] (else empty static)
            E = entries[word[P+0xe2]]   ; 0x140755156..0x140755175  (E+0x88&1 already set → "index … already in use" log)
            0x141164460(E, A, selectors=[C+0x140]|empty, states=[C+0x148]|empty, owner, …)
                E+0x48 = A; E+0x58 = [owner+8]; if A && owner: E+0x88 |= 1
                if A has ≥1 descriptor:  U = builder(C+0x138)->build(E, …)  ; E+0x50 = U
```

- Each animated part gets exactly one entry `E = [[owner+0x208]] + word[P+0xe2]*0x90`. The engine links it to the ANI part identity through `A+8`, the part name string; `A+0x140 = P`.
- A part without bit 9 has no index or entry. `0x14074c2d0` then takes the static branch and uses stored `P+0x1a0`. A part with bit 9 but without descriptors has an entry with `U = NULL`. `0x141165440` then copies A's default matrix: `t = 0`, `R =` authored part R.
- Builder selection is shipped-source.
  - Post-load `0x14088b4a7..0x14088b4fc` stores the builder's type hash in `C+0x138`. For bit-9 connections that is `SequenceControlUnitBuilder`: vtbl `0x142c80440`, `+0x20` = `0x14116a830` tests bit 9, and its hash is `0x882f5fdc9151729b`.
  - The factory list also holds `CargoBayFill`, `EngineJet`, `Highway`, `LookAt` and `Fog` builders.
  - `U` is a `SequenceControlUnit`: vtbl `0x142c80090`, ctor `0x1411691e0`, `U+8 = E`, `U+0x38 = states`.

## Selector propagation

**shipped-source**

1. **Load.** `<connection><animations><animation name start end starteffect>` records are loaded by `0x140882b37..0x140882c52` → `0x140880f40`.
   - Each record is `0xa8` bytes: `+0` start (int), `+4` end (int).
   - `+8` holds the name, lowercased at `0x141a18e24` and stored as FNV-1a-64 hash plus string. This uses the same hash as #164: basis `0x811c9dc5`, prime `0x1000193`.
   - `+0x30` is a pointer to the `animation_sequences` state with that name hash (`0x141168480`), or NULL. `+0x70` is starteffect.
   - The vector goes in `C+0x140`. `C+0x148` holds the non-NULL state pointers (`0x140883800`).
   - An empty `<animations/>` leaves `C+0x140 = NULL`.
2. **Bit 9 (animated).** Computed at `0x14088a203..0x14088a287`:

   ```text
   bit9(C) = ownList(C) != NULL
          || (parentPart(C) && bit9(parentPart) && (tag 'animation' || !(tag 'trigger_nearby' || tag 'trigger_interact')))
   ```

   The tag globals are `0x14395ca6c`, `0x14395cf48` and `0x14395cf40`. Their names come from the tag-registration pairing; the same pairing gives A6's `iklink`.
3. **Inheritance.** At `0x14088b154..0x14088b173`, unless bit 10 is set (tag `truncateanimations`, `0x14088a293..0x14088a2c1`, global `0x14395cf58`), the engine calls `0x140883570(&C+0x140, &C+0x148, parentPart)`:

   ```text
   parentList = [[parentPart+0x170]+0x140]           ; the parent part's owning connection, already merged
   if parentList empty: return
   if own list: own = own ++ parentList; erase every later record whose name-hash equals an earlier one  (0x140883642..0x1408836e8)
   else:        own = copy(parentList)
   C+0x148 = state pointers of the (new) records      (0x140883800)
   ```

   Connections are processed in depth buckets. `word[C+0x48]` is the ancestor-connection count computed at `0x140889d52..0x140889d8f`, and the buckets are filled at `0x140889ec0..0x140889f04`. Parents are therefore merged before their children, so lists chain to any depth.

**Rule.** A connection's effective selector list is its own `<animation>` records followed by its parent connection's effective list. Merging uses exact, case-insensitive name matching (hash of the lowercased name). The inner record wins and ancestor duplicates are dropped. Inheritance stops at a connection tagged `truncateanimations`. The list belongs to the connection, and its single owned part uses it. There is no per-part or subtree object, and descendants receive copies.

- The project's "same-name ancestor coverage" assumption is **confirmed as engine behaviour**, but only with the caveats above.
- The corpus exercises inheritance on 285 of 379 path parts.
- Override is not exercised: `turret_arg_m_flak_01` `anim_barrel` owns only `gun_firing` and inherits the other four names without overlap.

## Descriptor selection

**shipped-source**

- **Binding.** `0x141161fe0` → `0x141162210` sets `A+0 = hash(part name)`, `A+8 = part name`, `A+0x140 = P`, `A+0x148 = list`. It also sets the A5 defaults, then eager-binds through `0x141163c00`, or lazily through `0x141165340` → `0x141163e40` with the same list.
  - One `D` per unique selector hash, sorted by hash in `A+0x28` (stride `0x100`).
  - `D+0 = hash`, `D+8 = selector name`, `D+0xa8 =` record.
  - `0x141161900` scans the ANI descriptors and compares `(part name, subname)` case-insensitively with `tolower` at `0x1411619f0..0x141161a97`.
  - On a match it sets `D+0xa0 =` file descriptor `+148` (duration, float seconds), with tracks `D+0x28/+0x40/+0x58/+0x70/+0x88` from the five counts.
  - On no match it logs `"Failed to match the animation [%s,%s] in '%s' referenced by '%s' at connection '%s'"` (`0x141161d9c`). D keeps empty tracks and `D+0xa0 = 1.0` (`0x141161966`).
- **Runtime.** `0x141165440` does `D = U->vtbl[+0x38](time)` = `0x14115e320` → `0x141165ee0(E, time)`:

  ```text
  if time < E+8:                       return E+0x40            ; "defaultpath" (NULL by default)
  if |time − E+0x68| < 1e-7:           return E+0x60            ; cache
  loop:
    s = E+8
    for D in queue E+0x10[0..E+0x38):  s += D.dur; if time < s: cache; return D
    if U && U->vtbl[+0x30](dl=1, r8=0) returned true:  goto loop  ; apply pending transition (0x141169f40)
  if queue empty:                      return E+0x40
  cache last; return last queued D                             ; hold
  ```

  The queue is filled only by `0x141165930(E, state, now)` on state entry.
  - Finished front descriptors are dropped (`E+8 += dur`); if all are finished, `E+8 = now` and the queue is cleared.
  - It then binary-searches `A+0x28` for `state.hash` and appends that `D` (`0x141165a52..0x141165ac4`).
- **Absent descriptor.** A selector present in the effective list but missing from ANI yields a trackless `D`. `0x1411608b0` then returns A's defaults, `t = 0` and `R =` authored part rotation, for the state's duration of 1.0 s. It does not hold the previous pose.
- **Missing selector.** A state whose name is not in the part's effective list has no `D`, so nothing is queued. Once the queue drains, `E+0x40` (NULL) gives the default matrix.

## State transition rule

**shipped-source**, from `animation_sequences.xml` (`AnimationSequenceLibrary`) and `SequenceControlUnit`:

- **Initial state.** In the `0x1411691e0` ctor, the hash comes from `owner->vtbl[+0x1ad0](C)`. For `Turret`/`MissileTurret` (vtables `0x142b6e910`/`0x142b00620`, slot `0x14080cf40`) this is `turret_active` if `byte[turret+0x368]`, else `turret_inactive`. If that hash is not in `U+0x38`, the ctor uses the first state of the list. `0x14116a1f0` enters it.
  - If the state flag `+0x29` is set, the ctor randomizes `E+8 = now − rand·dur` (`0x141169324..0x1411693e6`). This matters only for the phase of an initial looping state.
- **Entry.** `0x14116a1f0` → `0x141165930` queues the descriptor. Then `0x14116a060` scans the state's transitions (stride `0x90`).
  - A transition with an empty trigger vector is automatic: `0x141169dd0` → `U+0x30 =` target → `U->vtbl[+0x30](dl=state+0x28, 0)` = `0x141169f40`.
  - If `dl == 0` and the target's descriptor hash is already queued, the transition stays pending. Otherwise the target is entered at once, which appends its descriptor behind the unfinished one.
  - A pending transition is applied when the queue drains (`0x141165ee0`, `dl=1`).
  - Triggered transitions (`activate`/`deactivate`/`fire`) arrive through `U->vtbl[+0x48]` → `0x141169cc0`. That call matches the trigger id and a part scope: target part equal or ancestor-related via `0x140880ce0`.
- **turret family.**

  ```text
  inactive --activate--> activating --auto--> active            queue [activating, active] → plays activating, then active
  active   --fire-->     gun_firing --auto--> active            queue [gun_firing, active] → recoil, then active
  active   --deactivate--> deactivating --auto--> inactive
  ```

  `turret_active` has **no** automatic transition. When its descriptor finishes, nothing is pending, so the last `D` (active) **holds**.
- **turretloop family.** `turretloop_active --auto--> turretloop_active`. The self-transition stays pending while its own `D` is queued. When the queue drains it re-enters, which clears the finished queue, sets `E+8 = now` and appends the same `D`. The result **loops**, with a phase restart at the draining evaluation.
- **Hardcoded check.** `Turret::vtbl[+0x20b0]` = `0x1405bf730` reads `entries[0]`'s current descriptor hash. It returns "active" iff the hash is `turret_active` (`0xc54d24dcd2b7658c`), `gun_firing` (`0x09be77d4210ea5a9`) or `turretloop_active` (`0x8109bb06a857ab16`). These are the "hardcoded check in x4-code" and the only immediates of those names.
  - `Turret::vtbl[+0x1558]` = `0x14080ca10` uses the maximum `turret_deactivating` duration over all entries.
- **Selector start/end frames.** They are stored in the record at `+0/+4`, but no traced evaluation reads them. Durations come from ANI descriptor `+148` (**inference**: frames are exporter data).
- **Per-instance overrides (non-default).** `0x141164920(E, node)` runs only when the owner has an instance XML node in the `0x142f5a340` map. It reads `time` (`E+8`), `reverse` (`E+0x88` bit value 2), `start`/`end` path time (`E+0x78`/`E+0x80`) and `default` (the hash that sets `E+0x40`). Token names come from the element table.
  - Default construction leaves `E+0x78 = E+0x80 = −1`, `E+0x88` bit 2 clear and `E+0x40 = NULL`.
  - The offline reference assumes that default, which is **inference** for spawned or loaded turrets without such an override.

## Local-time equation

**shipped-source**: `0x141165cd0(E, time)`, reached from `0x141165440` right after `0x141165ee0` has updated the queue. Units:
- `time` is game time, a double in seconds (TLS `[gs:58]→+0x300`).
- `E+8` is a double in seconds.
- `D.dur = D+0xa0` is a float in seconds, from ANI `+148`.
- Key times are float seconds (file key `+24`).
- The result is a float passed as `xmm3` to `0x1411608b0`.

```text
const NEVER = −0.99996                                  ; 0x142cbf088, sentinel test for "unset (−1)"
if E.flags & 2 (reverse):                               ; 0x141165cd4
    if time < E+8: return 0
    t = time − E+8
    if E+0x40: return dur40 − fmod(t, dur40)            ; 0x141b44180 = CRT fmod
    if E+0x78 > NEVER: t −= E+0x78
    if t < 0 and !(E+0x80 > NEVER): t = 0
    return t
; default path  0x141166050
if time < E+8: return 0
if E+0x78 > NEVER or E+0x80 > NEVER:                    ; override path
    t = (time − E+8) + E+0x78 ; if t > E+0x80 + E+8: t = E+0x80 ; return t
s = E+8
for D in queue:  if time < s + D.dur: return time − s ;  s += D.dur
if E+0x40 and dur40 > 0: return fmod(time − s, dur40)
if queue non-empty:      return last(queue).dur          ; 0x141166126..0x141166143  (hold at end)
return 0
```

Timeline with no overrides:

| Phase | Local time `tl` |
|---|---|
| One-shot activation | `tl = time − E+8 ∈ [0, dur_activating)` |
| Active, just after activation | `tl = time − (E+8 + dur_activating) ∈ [0, dur_active)` |
| Stable active (turret family) | `tl = dur_active`, exactly the float32 value of ANI `(part, turret_active)` `+148`; held indefinitely |
| Looped active (turretloop family) | `tl = time − E+8_cycle ∈ [0, dur_loop)`; `E+8_cycle` resets to the evaluation time at which the previous cycle's queue drained |
| Firing/recoil | `tl = time − E+8 ∈ [0, dur_gun_firing)`, then active `[0, dur_active)`, then hold `dur_active` |
| Deactivation | `tl ∈ [0, dur_deactivating)`, then inactive `[0, dur_inactive)`, then hold `dur_inactive` |

`0x1411608b0` evaluates keys at `tl` with A5's `0x14115fdc0` rules. `tl = dur` selects the last key whose time is at or below `dur`. If no key follows it, the value is used as-is: enum 1/2 give the value, enum 5 gives its out-handle. If a later key exists, the segment is interpolated.

## Deployed non-firing reference

For each part P on the selected endpoint path:

```text
C = owner connection of P
if !bit9(C):                              L_P = stored part local (A5: XML part offset)
elif effective(C) empty:                  L_P = default (t = 0, R = XML part R)
else:
    F   = 'turretloop' if 'turretloop_active' ∈ ∪ effective(path) else 'turret'
    sel = F + '_active'
    if sel ∉ effective(C):                L_P = default
    D = ANI(P.name, sel)  (case-insensitive); absent → trackless → L_P = default
    tl  = D.dur                                   (float32 from descriptor +148)      [turret]
          any φ ∈ [0, D.dur)  — equal for every corpus loop descriptor (see below)     [turretloop]
    L_P.t = D.position ? eval(D.position, tl) : 0
    L_P.R = D.rotation ? R_ANI(eval(D.rotation, tl)) : XML part R        (A5 order Rx(−x)·Rz(−z)·Ry(y))
```

- **`gun_firing` is excluded.** It is queued only by a `fire` trigger and always returns to `turret_active`, whose hold is the reference.
- **`turret_activating` is excluded.** Its end pose is **not** used. The engine holds the active descriptor, and the two differ in shipped data: Boron L Laser `part_rotator` activating end `y = 1.4935139` versus active hold `y = 1.5`.
- **Stable active holds.** It does not loop for the turret family. The hold time is `dur_active`, not the first key and not "any key value".

This reference is fully determinable offline from official component XML, the ANI file, and `animation_sequences.xml`. Groups 2–4 are still ignored by `0x1411608b0` (A5).

## Static examples

**shipped-source** data; derivations are **inference**, evaluated by `corpus_animation.py`.

### Paranid L Beam 01 (`turret_par_l_beam_01_mk1`)

`Connection01` owns 5 selectors. `Connection03/04/05` own none, have no `truncateanimations`, carry no trigger tags, and have animated parent parts. All of them get bit 9 and inherit `[turret_inactive, turret_activating, turret_active, turret_deactivating, gun_firing]`. Every `turret_active` duration is 0.0333333 s.

| Path part (leaf → root) | ANI `(part, turret_active)` | `tl` | `L_P` |
|---|---|---|---|
| `anim_barrel` / `Connection05` | position: 2 keys, (0,−0.23982000,27.710205) at t0 enum 2 and t 0.33333 enum 1 | 0.0333333 | t = (0, −0.23982000, 27.710205), R = part R (identity) |
| `anim_gun` / `Connection04` | no tracks | — | t = 0, R = identity |
| `part_rotator` / `Connection03` | position: 2 keys, (0,6.1450424,0) | 0.0333333 | t = (0, 6.1450424, 0) |
| `part_socket` / `Connection01` | no tracks | — | t = 0 |

The other selectors play only on the way to that hold, and each one's end pose equals the hold:
- activating `anim_barrel` goes (0,−4.8e-7,0) → (0,−0.23982,27.7102) over 2.0 s
- `gun_firing` recoils to (0,−0.170728,19.72694) and back over 0.3333 s
- inactive is (0,−4.8e-7,0)

### `turretloop_active` representative: Xenon L Plasma 01 (`turret_xen_l_plasma_01_mk1`)

`ConnectionForpart_socket` owns `turretloop_inactive/activating/active/deactivating`. There is no `gun_firing`, so nothing uses `turretloop_firing`. The path `part_gun ← part_rotator ← part_rotator_base ← part_arm ← part_socket` inherits all four.

- Initial state: `turret_*` hashes are absent, so the ctor starts at the first state, `turretloop_inactive`.
- Stable state: `turretloop_active` re-enters itself every 0.2666667 s.

| Part | `(part, turretloop_active)` | Value over `φ ∈ [0, 0.2666667)` |
|---|---|---|
| `part_arm` | rotation: 2 keys (−0.5235988,0,0), enum 5 then 1, equal handles | constant (−0.5235988,0,0) |
| `part_rotator_base` | rotation: (+0.5235988,0,0) likewise | constant |
| `part_gun`, `part_rotator` | no tracks | default |
| `part_socket` | only group 2 (scale), ignored by `0x1411608b0` | default |

The phase does not change any path transform.

Off the path, `ConnectionForpart_barrel` also inherits. `ConnectionFordetail_l_radar` owns `loop`, which is not a sequence state, so it binds a descriptor but no state. Neither is on the endpoint path.

## 92-candidate coverage

**shipped-source**, mechanical scan with `corpus_animation.py`:

| Measure | Result |
|---|---|
| Candidates / path parts | 92 / 379 |
| Family `turret_active` | **90** |
| Family `turretloop_active` | **1** (`turret_xen_l_plasma_01_mk1`) |
| No animated path part (all static, bit 9 false) | 1 (`turret_xen_xl_battleship_01_mk1`: 2 static parts → stored part local) |
| Own-selector connections on path | 90 candidates with 1, 1 with 2 (`arg_m_flak_01`: inner `gun_firing` + ancestor set, no name overlap), 1 with 0 |
| Path parts with animation entries by inheritance only | 285 |
| `truncateanimations` / trigger tags on path | 0 |
| Selector names on paths | only `turret_{inactive,activating,active,deactivating}`, `gun_firing` (48 candidates), and the `turretloop_*` four |
| Active descriptor present for every animated path part | yes: 377 descriptors (220 with position/rotation tracks, 157 trackless = default) |
| Key enums in active tracks | 1, 2, 5 only (mixed 5/2 per axis in 10 keys); no 6/7 |
| Active parts with group 2–4 keys (ignored here) | 83 |
| `turret_active` value varies inside `[0, dur)` | 19 parts / 11 candidates, mostly enum-5 handle curves; irrelevant because the reference is the hold at `tl = dur` |
| Loop descriptors varying with phase | 0 |
| Hold ≠ activating end | Boron L Laser `part_rotator` (0.0065 m); Xenon L Laser `part_barrel` (9.5e-7 m) |

- **Firing and deployment descriptors.** `gun_firing`, `turret_activating`, `turret_deactivating` and `turret_inactive` never contribute to the deployed reference.
- **Other mechanisms.** No asset structure needs another generic state mechanism: no per-instance override data, no `truncateanimations`, no trigger-tag cut, and no override-by-name collision on any path.
- **Coverage.** The recovered rule covers **all 92** selected endpoint-path animation structures.

## Consequences for existing code

No production edits.

| Current assumption (`census_ani_relationships.py`, `census_source_semantics.py`, generator) | Assessment | Class and reason |
|---|---|---|
| Same-name `turret_active` ancestor coverage decides whether a part animates | **Supported, but incomplete** | shipped-source: engine inheritance is by lowercase name. Still to model: own-first dedupe, `truncateanimations` cut, and the bit-9 tag gate (`animation` / `trigger_nearby` / `trigger_interact`). None is exercised on corpus paths |
| "Settled active" = any `turret_active` key value | **Contradicted as a rule** | shipped-source: the value is at `tl = dur_active` (hold). Boron L Laser active keys run 0 → 1.5 |
| STEP enums, one-frame selectors, activating/deactivating boundary equality as proof of the settled value | **Contradicted as proxies** | shipped-source: timing comes from ANI durations and queue/hold logic, not selector frames or enum pattern. Boron L Laser shows activating end ≠ active hold |
| Using the final activation pose | **Contradicted** | shipped-source: see above |
| Firing/recoil excluded | **Supported** | shipped-source: `gun_firing` only via the `fire` trigger; automatic return to active |
| `turretloop_active` interchangeable with `turret_active` | **Contradicted mechanically, harmless for corpus geometry** | shipped-source: loop re-queue versus hold. Corpus loop descriptors are phase-constant (inference from data) |
| A part missing a selector or descriptor keeps the previous or authored transform | **Contradicted** | shipped-source: a trackless or missing descriptor yields `t = 0, R =` part R; a non-animated part uses the stored XML part local |
| Per-semantic-case literal injection (e.g. Paranid edge vectors) | **Replaceable** | inference: every path descriptor/time is now mechanically selectable |
| Default per-instance overrides absent for mounted turrets | **Still unproved** | inference: the override map `0x142f5a340` population was not traced |
| State template flags `+0x28` (immediate) and `+0x29` (random initial phase) | **Still unproved** | not decoded; irrelevant to the hold and to phase-constant corpus loops |
| Meaning of `[turret+0x368]` (initial active) | **Still unproved** | irrelevant: both initial states converge on the same hold |

## Single next dependency

Resolve the owner-level translation scale `S = owner->vtbl[+0x1448](time)`. It multiplies every composed translation in `0x14074c2d0`, `0x14074be30` and `0x140e22b70`, and again at the end of `0x14081c960`. It is still the only unproven per-segment transform input left after A5 (locals/defaults), A6 (`J_C`) and A7 (descriptor and time). A6 already names it as outstanding, so it is the highest-value remaining blocker to writing the generic offline evaluator.
