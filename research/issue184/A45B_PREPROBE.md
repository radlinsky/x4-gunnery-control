# A4.5b — pre-probe classification: what a normal mod knows before it asks

Offline research. X4 9.00 build 611726, `X4.exe` SHA-256
`19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`, verified
this session. No X4 launch, no production change, no aim probe of any kind.
Starting SHA `aa2019ddc96b8ff1c44655b72eb927b8c35e3b4e` (A4.5).

Question: **before asking X4 any aim-point question, can MD/Lua tell whether a
live target behaves as a zero-, one-, or multi-point target?**

A4.5 answered "no" after checking four candidates. This pass audits the whole
runtime surface instead, and the answer splits in two:

- **Classification by metadata: still no**, now on an exhaustive audit rather
  than four samples.
- **But the premise is beatable.** Two shipped Lua FFI getters,
  `GetRelativeAimOffset` and `GetRelativeAimScreenPosition`, reach the same
  nearest-aim-point selector that `create_orientation useaimtarget` reaches,
  for the **player ship's own origin**, at no MD cost. If that trace holds
  live, A4.6 does not need to classify a target to know where X4 aims at it
  from here — it needs one free call per frame.

---

## 1. What has to be distinguished

| case | what X4 does | distinct aim positions X4 can choose |
|---|---|--:|
| zero authored points | selector's empty branch returns the runtime box centre (A4.5 §1) | 1 |
| exactly one authored point | that point, from every query origin | 1 |
| two or more | nearest authored point to the query origin | up to *n* |

No component in either census authors two coincident points (0 of 14 vanilla,
0 of 128 SWI multi-point components have a duplicate position), so "2+ authored
points" always means "2+ selectable positions". Nearest-pair separation is
4.13 m at its smallest in vanilla (`ship_gen_s_fightingdrone_01`) and 4.0 m in
SWI (`ship_mando_s_n1`).

### Are zero-point and one-point ships ever the same ship?

Recomputed from the A4.4 rows, distance from the single authored point to the
reconstructed macro-box centre — the box the A4.5 fallback *probably* returns,
see the open box question:

| tolerance | vanilla (5 one-point) | SWI (97 one-point) |
|---|--:|--:|
| exact | 0 | 8 |
| 1 mm | 0 | 18 |
| 1 m | 0 | 40 |
| 10 m | 1 | 85 |
| 50 m | 2 | 97 |

min / median / max distance: vanilla **7.61 / 158.79 / 248.56 m**, SWI
**0.00 / 1.63 / 49.08 m**.

So the two cases are *not* interchangeable where it matters. In a vanilla game
no one-point ship sits on its box centre, and the median miss is 159 m. In SWI
the single point is usually near the centre but exactly on it for only 18 of 97
at 1 mm. **Do not treat "zero or one" as one case with one answer.** Treat it
as one *shape* — a single fixed point from every origin — with two different
positions.

---

## 2. Runtime surfaces audited

Every route below was searched in the shipped 9.00 sources, not in Gunnery
Control's current call sites.

| surface | what was checked | result |
|---|---|---|
| MD `component` properties | all 147 in `scriptproperties.xml` | no connection list, no connection count, no component-definition name. `debugname` is knownname+idcode+id |
| MD `macro` properties | all 82 | geometry is `boundingbox.exists/max/center` only |
| MD `object`, `destructible`, `defensible`, `controllable`, `ship` | 98 / 26 / 225 / 122 / 71 | slot counts exist for turrets, weapons, shields, engines, modules, adsigns, signal leaks — all *equipment* collections, none of them connections in general |
| MD `componentslot` | full property set | **does** expose `name`, `tags`, `group`, `offset`, `rotation`. It is the one type that would answer the question — but a `componentslot` value can only be produced by the specific finders below |
| MD `find_*` actions | all 60 in `common.xsd` | every slot finder is bound to one slot family: npc, prop (room only), crate, airlock, hack, transporter, workbench, console, stationeditor, mapconsole, tradeoffer parking. None enumerates a ship's connections by tag. `find_object_component` finds child *objects*, and an aim connection carries no object |
| MD `create_target_points` | `target` + `tags` | creates scan/hack mission target points from tagged connections, but nothing reads them back: no `targetpoint` property exists in `scriptproperties.xml`, and the action wipes other missions' points. Unusable as a classifier |
| Lua FFI, whole UI tree | 1,920 distinct declarations indexed | connection arguments are always *inputs* (`const char* connectionname`). Tag-filtered enumeration exists only for wares, icons, sounds and cargo |
| `GetMacroData` | 54 distinct keys the game itself requests | nothing structural; nearest is `size`, `compatibility`, `primarypurpose` |
| `GetComponentData` | 115+ distinct keys requested | nothing structural |
| unnamed data-getter keys | #176 A5 left 31 macro and 111 component keys unnamed (FNV-hashed) | unchanged; a key that exposed aim connections would still have to exist in the handler, and no `aimtarget`-family key string exists in the image (`aimpoint`, `aimtargets`, `numaimtargets`, `hasaimtarget`, `connectioncount`, `numconnections`: 0 occurrences each) |
| `targetsystem.lua` `aimTarget*` | 44 hits | HUD crosshair element state, unrelated to authored `aimtarget` connections |

The only two occurrences of the NUL-terminated string `aimtarget` in the image
are the MD attribute pool entry (`useaimtarget`) and an entry in the engine's
connection-tag name table, next to `adspot`, `airmarshal` and `console_01`.
There is no key, property or function named for it.

**Conclusion for classification: a normal mod cannot read the count.** The
A4.5 claim is *supported* for metadata, and now rests on the full surface
rather than four fields.

---

## 3. Candidate classifier rules, against both censuses

| candidate | runtime facts used | vanilla 0 / 1 / 2+ | SWI 0 / 1 / 2+ | counterexample | safe for unknown ships? |
|---|---|---|---|---|---|
| ship class | `component.class` | 184 / 5 / 14 all spread across `ship_s`–`ship_xl` | 1 / 97 / 128 likewise | `ship_s`: 0-, 1- and 2+-point ships in both games | no |
| runtime box diagonal | `macro.boundingbox` | zero-point spans 22–12,098 m, containing one-point (48–1,576) and multi (18–2,630) entirely | one-point 7–271 m inside multi 3–19,725 m | `ship_gen_s_fightingdrone_01` (2 pts) sits inside the same bucket as 15 zero-point S ships | no |
| class + box within 1 m | both | 178 groups, 0 mixed | 144 groups, 3 mixed | a rule with one ship per group is a lookup table, not a rule; and SWI already breaks it | no |
| class + box within 10 m | both | 104 groups, **2 mixed** | 106 groups, **8 mixed** | vanilla: `ship_pir_s_fighter_01` (1) vs `ship_pir_s_heavyfighter_01` (2) vs two zero-point transdrones in one group | no |
| type / purpose within a class | `shiptype`, `primarypurpose` | `ship_arg_l_destroyer_01` 0 vs `_02` 3; `ship_arg_xl_carrier_01` 0 vs `_02` 4; same for L miners, L container transports, S fighters, XL resuppliers | one purpose family per hull | the destroyer pair | no |
| equipment structure (turret / weapon / shield / engine / module slot counts) | `defensible.*.numslots` | not tested per ship because it cannot be sound: slot collections are authored independently of `aimtarget` connections, and SWI patches retag connections that feed them without touching a single aim point (A4.4) | — | — | no |
| macro count per component | `component.macro` | 1–2 macros in vanilla for every category | 1–3 likewise | `ship_tel_l_destroyer_01` (2 pts, 2 macros) vs `ship_arg_l_destroyer_01` (0 pts, 2 macros) | no |
| naming / faction patterns | macro name | rejected by the issue | rejected | — | no |

No single fact and no combination of them separates the categories, and every
near-miss degenerates into a per-ship table as the tolerance tightens. That is
the expected outcome: the authored aim connections and every runtime-visible
fact are independent authoring decisions, so any agreement between them is an
accident of the current census and says nothing about a DLC or mod ship.

**Partial classifiers, reported separately as asked:** none survives either.
There is no generic zero-point marker, and no generic "at most one selectable
point" test. SWI's one-point ships cluster near the box centre (85 of 97 within
10 m) but that is an authoring habit of one overhaul, not a contract, and
vanilla's five one-point ships break it outright.

---

## 4. The route that does work: the HUD aim getters

**Status: inference (native trace), same build and SHA-256. Not live-tested.**

```
GetRelativeAimOffset        (export, RVA 0x00AFE510)  ─┐
GetRelativeAimScreenPosition(export, RVA 0x00AFE7F0)  ─┤ call virtual slot +0x2210
                                                       │ (0x00AFE692, 0x00AFE9E5)
  slot +0x2210  →  0x004DE590   (only 3 implementations of this slot exist in
                                 the 10,488 vtables scanned; this one is in 11)
      ├─ weapon resolved → 0x00815330 → 0x007E7460
      │                                   ├─ 0x007E76AA → 0x00520FC0  (selector)
      │                                   └─ 0x007E7B46 → 0x005210E0  (selector)
      └─ no weapon      → 0x003DDE10, which never touches the aim-point collection
```

`0x005210E0` and `0x00520FC0` are exactly the two selectors A4.5 traced: the
`-1.0f`-seeded nearest-authored-point loop over the defaults collection at
`+0x760`, with the box-centre fallback at `0x00521187` / `0x005210B8`.
`create_orientation useaimtarget` and `check_line_of_sight useaimtarget` reach
the same two functions.

Both call sites of slot `+0x2210` in the whole image are these two exports, so
this is the complete Lua-reachable surface of that path.

The weapon branch is taken via `0x004DFFD0`, which indexes the caller's active
weapon-group vector (`+0x638`, index at `+0x668`). **If the player's active
weapon group yields no weapon, the getter silently takes the other branch and
returns something that is not a selected aim point.** Any production use has to
treat that as a distinct answer, not as a position.

`targetsystem.lua` calls `GetRelativeAimOffset(componentID)` for the aim-at
indicator and reads `x, y, z, yaw, pitch, roll`; the returned position is put
through `0x00979EF0` against the player object before it is written, so it is
relative to the player, not target-local. Gunnery Control already owns a
UI↔MD bridge (`ui/gunnery_control.lua`, `md/x4_gunnery_control.xml`), so the
value is reachable from production without new plumbing.

**What is not settled statically:** whether `0x00815330` returns the selected
aim point itself or a lead-corrected firing position derived from it, and the
exact frame. That is the one live question below.

### Why #176 A5 missed this

A5 listed `GetRelativeAimOffset` as a dead end on its *declaration* —
"player-ship or HUD scope, with no turret argument". That was the right call
for A5's question, which was turret arc limits. For #184's question the lack of
a turret argument is not a defect: the query origin Gunnery Control cares about
is the player's own ship.

---

## 5. Required result table

Read per case. "Runtime facts used" means facts available before any aim probe.

| pre-probe case | can normal mod identify it? | runtime facts used | vanilla coverage | SWI coverage | safe for unknown ships? | aim position directly known? |
|---|---|---|---|---|---|---|
| zero points | **no** | none exists | 0 of 184 | 0 of 1 | n/a — no rule to be safe | position is the runtime box centre *if* membership were known; `$target.macro.boundingbox.center`, subject to the open box question |
| exactly one | **no** | none exists | 0 of 5 | 0 of 97 | n/a | **UNKNOWN** — not the origin (0/5, 47/97), not the box centre (0/5, 8/97 exact), no other structural relation survives either census |
| two or more | **no** | none exists | 0 of 14 | 0 of 128 | n/a | UNKNOWN |
| zero-or-one combined | **no** | none exists | 0 of 189 | 0 of 98 | n/a | UNKNOWN — and combining them is unsafe anyway: the two answers differ by a median 159 m in vanilla |
| *(alternative)* any case, position only, player-ship origin | **yes, pending live check** | `C.GetRelativeAimOffset(componentid)` from UI Lua | all 203 | all 226 | yes — it is the engine's own selector, so DLC and mod ships are covered by construction | **yes**, for the player ship's current origin, one free call |

---

## 6. Answers to the six questions

1. **Strongest exact classifier found:** none. No runtime fact or combination
   of facts classifies 0 / 1 / 2+.
2. **Strongest useful partial classifier:** none either — but the goal behind
   the classification is met another way. `GetRelativeAimOffset` returns the
   selected aim position directly for the player-ship origin, which is what the
   zero- and one-point cases were wanted for, and it works for the multi-point
   case too at that origin.
3. **Why each rejected candidate fails:** section 3. The representative
   counterexamples are `ship_arg_l_destroyer_01` (0) against `_02` (3) for
   type/purpose; `ship_pir_s_fighter_01` (1), `ship_pir_s_heavyfighter_01` (2)
   and two zero-point transdrones in one class+box bucket; and the box-diagonal
   ranges, where the zero-point range contains both others entirely.
4. **Is A4.5's "no normal runtime fact can distinguish the cases" supported?**
   Supported for *classification*, and now on much stronger evidence. **Too
   strong as written**, because it was read as "runtime gives us nothing here",
   and that is false: a runtime *value* route to the selector's own answer
   exists and A4.5 did not look for one.
5. **What this means for A4.6:**
   - **Skip probing entirely:** every ship, for the player ship's own origin,
     if the live check in section 7 confirms the getter. That is the origin
     Gunnery Control fires from.
   - **Cheap fixed-point path:** none by classification. Do not build one on
     "zero or one" membership — it cannot be decided, and the two positions
     differ.
   - **Genuinely needs multi-point discovery:** any question about an origin
     that is *not* the player ship's current position — another ship's turret,
     a predicted future position, or a full point map. The getter answers for
     one origin at a time, but it answers for free and repeatedly as the ship
     moves, which is a much better input to a discovery loop than an MD probe
     budget.
   - The A4.5 direct-position rule for the 184 vanilla zero-point ships stays
     blocked on the same open box question, and stays unusable anyway without
     membership.
6. **The one remaining LIVE test.** One Test Lab capture, one fixture, settling
   both open questions at once:
   - Spawn `ship_arg_l_destroyer_01` (0 authored points, `ship_l`, box centre
     far from component origin) and `ship_tel_l_destroyer_01` (2 points) as the
     control.
   - With the player ship at two widely separated known positions, log
     `C.GetRelativeAimOffset(targetid)` and, for the same targets,
     `$target.macro.boundingbox.center` and the target's world transform.
   - Outcomes: on the zero-point ship the getter either resolves to the macro
     box centre (settles A4.5's "which box" question *and* confirms the getter
     returns the raw selected point), to the component origin, or to neither
     (an override box, or lead correction — distinguishable because a lead
     offset moves with the target's velocity and a box centre does not; log one
     capture with the target stationary and one moving).
   - On the two-point control the reported position must switch between the two
     authored points as the player crosses their bisector. That confirms the
     getter is the selector's answer and not a HUD-smoothed artefact.
   - Design it, do not run it, as part of this task.

---

## 7. Asides relevant to #184

- **The engine's own weapon aiming uses this selector.** `0x00520FC0` is called
  from vtable slot `+0x30` of six classes whose RTTI names are
  `BasicShootController`, `MindlessShootController`, `MultipleShootController`,
  `LargeTargetShootController`, `PlayerShootController` and
  `PlayerBombLauncherShootController`. Turret AI and the player's own guns aim
  at the same selected point Gunnery Control is trying to locate, which is
  worth knowing when reasoning about what "where the ship is aiming" means.
- **`create_target_points` exists and takes a tag filter on a destructible.**
  It is the only MD action that selects connections by tag on a ship. It is
  write-only from MD's side — no property reads the points back — and it
  removes other missions' target points, so it must not be used. Recorded so a
  future session does not rediscover it as a lead.
- **Vanilla authors no coincident aim points and no ship with fewer than 4.13 m
  between its nearest pair.** If A4.6 ever needs a minimum-separation
  assumption to reject a merged label (the A3 failure at stress range), 4.13 m
  vanilla / 4.0 m SWI is the measured floor — from the census, not a guess.
- **SWI one-point ships are a near-box-centre population** (median 1.63 m,
  85 of 97 within 10 m) while vanilla's five are not (median 158.79 m). Any
  tolerance tuned on one game will mislead about the other.
