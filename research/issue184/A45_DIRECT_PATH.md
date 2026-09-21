# A4.5 — the empty-aim-point branch, and what a mod can tell apart

Offline research. X4 9.00 build 611726, `X4.exe` SHA-256
`19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`, verified
this session. No X4 launch, no production change. Starting SHA
`83389c32eb6416747e67d056d053dffc4e24c967` (A4.4). Static native scratch stays
in the ignored `.x4-research-cache/issue176-a5-native/`; the durable engine
facts are in
[`macro-box-aimtargets.md`](../../.agents/skills/research-x4-modding/references/macro-box-aimtargets.md).

## 1. What the engine does with no authored aim point

**Status: inference (native trace).** The selector at `0x005210E0` reaches its
fallback at `0x00521187` by three routes, and only the first two can occur:

1. the defaults collection pointer at `+0x760` is null (`0x00521103`);
2. the collection is empty, `begin == end` (`0x0052112E`);
3. the loop kept nothing. It cannot: the running best distance is seeded with
   `-1.0f` (`0x00521113`, constant at RVA `0x02CBF01C`) and the `comiss` at
   `0x00521140` against zero takes the accept branch for that seed, so the first
   entry is always kept. A non-empty collection therefore never falls through.

The fallback is two instructions:

```
00521187  mov  rax, [rdi]                 ; target object's vtable
0052118d  call qword ptr [rax + 0x14b0]   ; virtual bounding-box getter
00521193  add  rax, 0x10                  ; -> the box's centre vector
```

It returns **the centre of the target's runtime bounding box**, in the same
target-local frame as an authored point, which the caller then transforms with
`0x003DB8A0` exactly as it transforms a selected authored translation. No box
containment, clamp or per-type special case appears anywhere on this path.

### The box struct layout, and a correction

The 0x24-byte box struct is `{ half-extents @+0x00, centre @+0x10, radius
@+0x20 }`. The union helper `0x014E1BD0` proves it: it reconstructs
`min = box[0x10] - box[0x00]` and `max = box[0x10] + box[0x00]`
(`0x014E1BDE–0x014E1BF0`) and writes back `(max-min)*0.5` to `+0x00`,
`(max+min)*0.5` to `+0x10` and `|half-extents|` to `+0x20`
(`0x014E1E6B–0x014E1EBD`).

This **corrects** `macro-box-aimtargets.md`, which labelled macro `+0x150` the
half-extents. Macro `+0x140` is the half-extents and macro `+0x150` is the
centre. The macro box *slot* `+0x140` and every reconstruction built on it are
unaffected; only the two member labels change.

### Which box, exactly

The default implementation of vtable slot `0x14b0` (`0x0034EE10`, in 72 of the
vtables carrying this slot) tail-jumps to slot `0x14a8`, whose default
(`0x0034EE00`) is `return macro + 0x140` — the same macro box slot the project
already reconstructs offline and the same one MD exposes as
`$target.macro.boundingbox`.

**Not every class uses the default.** A second family (39 vtables, `0x006DF940`
for `0x14b0`, `0x006DF7C0` for `0x14a8`) checks a macro-data flag at `+0x8F2`
and an object list at `this+0xA8`; when both are present it delegates to the
first eligible child object's own `0x14b0` box, and otherwise returns
`macro + 0x140`. Three further vtables use wrappers (`0x00773D40`,
`0x0053C5C0`) that substitute a `this+0x70` object's box when the own box's
radius is ~0, and three return instance-resident boxes (`0x00354470`:
`this+0x390`). The engine classes are not named — X4 ships no RTTI for them —
so static evidence does **not** prove which implementation a *ship* uses.

### `check_line_of_sight` reaches the same fallback

`CheckLineOfSightAction` (RTTI `.?AVCheckLineOfSightAction@Scripts@@`, vtable
`0x02C0D738`, run method slot 3 = `0x00BCB4D0`) calls sibling selector
`0x00520FC0` at `0x00BCBAFF`. `CreateOrientationAction` (vtable `0x02C0CDA8`,
run `0x00BE1970`) reaches `0x005210E0` through the accepted
`0x00C707A0 → 0x003EC190 → 0x003EC313` trace. The two selectors are the same
code: same `-1.0f` seed, same binary32 squared-distance loop over `+0x760`,
same fallback (`0x005210B8`: `call [rax+0x14b0]`, `add rax, 0x10`).
`0x00520FC0` differs only by transforming the caller-supplied origin into the
target frame first (`0x003DDE10`). **Both keywords share one fallback.**

### Verdict on the old "box centre" comment

**Proved, with one named gap.** The empty case returns a bounding-box centre —
this is no longer an assumption inherited from old Gunnery Control comments.
What remains unproved is *which* box a ship-class object returns: the macro box
`+0x140` that production can read, or a delegated child/instance box from one of
the override implementations.

### Smallest discriminating LIVE test

One Test Lab capture, one fixture, no new tooling:

- Spawn one **vanilla ship that authors no `aimtarget`** and whose macro box
  centre is far from its component origin, so the two candidates cannot be
  confused. `ship_arg_l_destroyer_01` (0 points, `ship_l`) is the natural pick.
- From two widely separated known origins, run `create_orientation
  useaimtarget="true"` and log the resulting orientation.
- The two rays either intersect at `$target.macro.boundingbox.center`
  transformed to world (macro-box hypothesis), at the component origin, or
  elsewhere (an override box). One control ship with authored points
  (`ship_tel_l_destroyer_01`, 2 points) confirms the capture path itself.

That single capture settles the only remaining UNKNOWN in the table below. Do
not run it as part of A4.5.

## 2. Can a normal mod tell which case a target is in?

No. Every candidate shortcut has a counterexample in the A4.4 census, and the
two games disagree, so nothing survives that would also be safe for an unknown
DLC or mod ship. Checked against the census rows, per game:

| candidate runtime fact | vanilla counterexample | SWI counterexample |
|---|---|---|
| ship class / size | `ship_l`: 37 zero-point, 3 one-point, 9 multi. `ship_s` and `ship_xl` likewise mixed | `ship_m`: 35 one-point, 22 multi; `ship_s`: 62 / 8 |
| runtime box diagonal | zero-point spans 22–12,098 m and completely contains the one-point (48–1,576 m) and multi (18–2,630 m) ranges | one-point 6.6–271 m overlaps multi 3.3–19,725 m |
| ship type / purpose (same class + role) | `ship_arg_l_destroyer_01` 0 vs `ship_arg_l_destroyer_02` 3; `ship_arg_xl_carrier_01` 0 vs `_02` 4; also L miners, L container transports, S fighters, S heavy fighters, XL resuppliers | n/a — one purpose family per hull |
| component / macro metadata already reachable | the point list is a property of the component and is not exposed by any MD or Lua surface (settled in #176 A5); the box is macro-level and varies up to 25.2 m between a component's own macros | same |

Excluded by the issue and not revisited: hard-coded ship names, a baked
official/SWI table, X4Native or native helpers, and runtime parsing of installed
game files.

## 3. Can any one-point ship be solved directly?

No. A runtime-visible rule would have to give both membership and position, and
neither exists:

- membership fails for the reasons in section 2;
- position: A4.4 already showed the single point is not the component origin
  (0/5 vanilla, 47/97 SWI) and not the runtime-box centre (0/5, 18/97). The only
  exceptionless rule, `x = 0` (5/5 and 97/97), fixes one coordinate of three and
  is itself only usable once membership is known.

There is no safe direct one-point rule. No approximation is proposed.

## 4. A4.5 decision table

Read per game; a production rule must hold in both and for unknown ships.

### Vanilla X4 9.00 (203 ships)

| case | ships | status |
|---|--:|---|
| no authored point — **position** | 184 (91%) | **directly reconstructable, no probing**: the selected point is the runtime box centre, i.e. `$target.macro.boundingbox.center` in world, for every query origin. Subject to the one LIVE check in section 1 |
| no authored point — **membership** | 184 | **identifiable only by discovery**: no runtime fact separates it from the one-point case, and both look like a single fixed point from every origin |
| exactly one authored point | 5 | **discovery required**: membership unidentifiable, position not reconstructable |
| two or more authored points | 14 | **generic path**: not distinguishable, not reconstructable |
| which box the fallback returns for a ship object | all | **UNKNOWN** — macro box `+0x140` vs an override implementation; section 1 LIVE test |

### SWI 0.9.1 HF (226 ships)

| case | ships | status |
|---|--:|---|
| no authored point | 1 (`mandator`) | same direct position rule, same unidentifiable membership. Negligible population |
| exactly one authored point | 97 | **discovery required** |
| two or more authored points | 128 | **generic path** |
| which box the fallback returns | all | **UNKNOWN**, same test |

**Consequence for A4.6.** The zero-point and one-point cases are
indistinguishable *a priori* but identical in shape: both behave as one fixed
point from every origin. In a vanilla game 189 of 203 ships (93%) are in that
shape, so the cheapest useful discovery is a consistency check against the
already-known box centre, not a general multi-point search. Designing, tuning
and bounding that check is A4.6.
