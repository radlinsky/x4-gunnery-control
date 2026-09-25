# Selected-target CLEAR LINE OF FIRE: excludeself semantics and a physical-path method

Scope: X4 9.00 build 611726, `X4.exe` SHA-256
`19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`
(re-verified 2026-09-24), image base `0x140000000`. See
[native-analysis.md](native-analysis.md) for the pin and recipe. Native RVAs are
real addresses; "include", "exclude", "leaf component", "lattice" and
"self-mesh" are analyst labels. `XPhys::XShapeFilter`, `XPhys::XBodyFilter`,
`XPhys::XObjectLayerFilter`, `CheckLineOfSightAction` and
`FindObjectSurfaceAction` are real RTTI names.

Purpose: answer, for the currently selected target only, whether a straight
segment from each selected turret's current muzzle reaches actual qualifying
target geometry first. This is a physical-path question. It is not X4's aim
point, bearing, firing permission or hit prediction. The IN RANGE rule lives in
[turret-fire-range-gate.md](turret-fire-range-gate.md) and is not reopened here.

## excludeself removes the excluded component and its ancestors' meshes

- X4: 9.00 build 611726
- Status: inference
- Source: native trace, pinned executable above
- Live test: no new run. Consistent with the retained live observations listed
  below, none of which was controlled for this mechanism.
- Finding: every ray query through the shared wrapper `0x000BC4D0` →
  `0x000BB5D0` installs two component filters built from the same
  include/exclude arguments. Before this record only the body-level filter had
  been traced.
  - `XBodyFilter` (vtable `0x02A2ACD0`; `ShouldCollideLocked` `0x000BBB00`)
    tests the **body owner**. With the descendant flag set it rejects a body
    whose owner is the excluded component or one of its descendants
    (`0x000BBC3B`–`0x000BBC7E`). A mounted turret owns no body, so at this level
    `excludeself` removes nothing.
  - `XShapeFilter` (vtable `0x02A2B370`; `ShouldCollide(shape, subShapeID)`
    `0x000BBCB0`, reached from slot 1 `0x000BC080`) tests each **hit
    sub-shape**. It resolves the leaf's component through `0x000CD480` at
    `0x000BBD62`, the same resolver the closest-hit writer `0x000B65C0` uses (see
    [weapon-path-obstruction-groups.md](weapon-path-obstruction-groups.md),
    "Attached surface meshes are identified sub-shapes of the owner's body").
    With the flag set, the exclusion loop `0x000BBE26`–`0x000BBE67` starts at the
    **excluded component and walks its ancestors**, rejecting the sub-shape if
    the leaf's component equals any of them. With the flag clear it rejects only
    an exact match (`0x000BBE69`). The include loop walks the other way: it
    accepts only leaves whose component is the include component or one of its
    descendants (`0x000BBDD8`–`0x000BBE20`).
  - The broad-phase visitor `0x0140A730` sets the shape filter's body id at
    `0x0140A84D` and passes the filter into each body's narrow-phase cast at
    `0x0140A905` → shape vtable `+0x78`. Every candidate compound member is
    therefore filtered.
  - All callers pass the same filter tag value (global RVA `0x06D113D0`) into
    the shape filter's `+0x34` field. The pre-fire gate's value is loaded at
    `0x00817AB0`, `check_line_of_sight`'s at `0x00BCBB49` and
    `find_object_surface`'s at `0x00BDEFDC`. The shape filter's tag branch
    (`0x000BBE72`–`0x000BBECC`) therefore behaves identically for all three.
    Only the include/exclude sets differ.

Consequences for a firing turret `W` mounted on ship `S`:

| Setting | Excludes | Still visible |
|---|---|---|
| Native pre-fire gate (exclude `W`, flag 0 at `0x00817AEB`/`0x00817AF0`) | `W`'s own meshes | `S` hull, sibling turrets/shields/engines on `S`, everything external |
| MD `excludeself="false"` | nothing | `W`'s own meshes, `S` hull, siblings, external |
| MD `excludeself="true"` (exclude `W`, flag 1 at `0x00BCBB9D`/`0x00BCBB98`) | `W`'s own meshes **and** meshes tagged with `W`'s ancestors, i.e. `S`'s hull | siblings on `S`, external |

Neither MD setting reproduces native. `false` over-includes the firing turret's
own collision parts, which native ignores. `true` drops the firing ship's hull,
which native keeps. On a station-mounted turret, `true` likewise drops the
owning module's own meshes and any mesh tagged with the station root.

The ancestor link walked by both filters is the per-thread pair at component
`+0xE0`/`+0x160`, selected by a thread-state flag. It is used in both directions
by the body filter, which is why it is read as a parent link. The action's own
result walk uses `+0x70` (`0x00BCBBF8`). Treating the two links as the same
hierarchy is inference.

### Why the historic live results looked contradictory

The 2026-08-11 capture recorded in [md-ai.md](md-ai.md) ("Per-turret line of
sight and the shipped AI range heuristics") used, in revision `01cbe3a` of
`testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_observe.xml`
(lines 244–245):

- `check_line_of_sight object="$Turret" target="$Target" excludeself="true" useaimtarget="true"` (`los_ex`);
- the same call with `excludeself="false"` (`los_inc`).

Neither call passed `objectoffset`, so both rays started at the **turret
component origin**, the mount point on the hull, not at the muzzle. `false` kept
`W`'s meshes and `S`'s hull on a ray starting at that mount point and was
blocked in 7252/7252 samples. `true` removed both and discriminated
(5449 clear, 1803 blocked). The native trace above supplies the missing
condition: `true` was not a no-op, because the shape filter removes the firing
ship's hull and the turret's own meshes. The earlier inference in
[weapon-path-obstruction-groups.md](weapon-path-obstruction-groups.md) that the
two settings are equivalent for mounted weapons considered only the body filter.
That inference is corrected there.

This is also consistent with the 2026-08-23 missile-turret record in
[testing-experiments.md](testing-experiments.md): the same muzzle rays were
blocked with `false` and clear with `true`, and `true` was still blocked by a
separate solid Asgard. The ancestor rule predicts exactly that. It cannot say
whether a given `false` block came from `S`'s hull or from `W`'s own launcher
meshes.

Experimental, uncontrolled corroboration: in the owner's local 2026-09-23 Test
Lab log, 30 paired MUZZLE-origin samples (Boron Ray, two marks, target
unrecorded) never showed `muzzle_los_self=1` with `muzzle_los_ex=0`; 4 showed
`ex=1, self=0`. That is the required monotonic pattern, but it proves no cause.
The log was not retained in the repository.

### Station-root false negative remains unexplained

A 2026-08-19 station-root report (Xenon Defence Platform) recorded 0/14 from
both the muzzle `excludeself="false"` root ray and the turret-origin
`excludeself="true"` root ray while the same turrets hit the station. Neither
filter rule explains a false result for a module hit. Station components
author no aim connection, so a station's `useaimtarget` endpoint is its live
union-box centre. That is a shipped-source census: no `class="station"`
component in the official source sets has an `aimtarget` connection.

The remaining source-level explanations are:

1. The ray crossed into another zone's physics world.
2. A module hit's `+0x70` chain does not reach the station root.
3. The segment toward the centre reached no geometry.

The raw log was not retained. The method below does not depend on the
module-to-root link.

Explanation 3 is geometrically real, though not proven for that run. The
shipped `xen_defence` construction plan was assembled offline with the real
module collision shapes (see the collision-shape record below). Its union-box
centre is (0, −319, 0) in station space, in open space below the hub dock
area and inside no module. Of 200 evenly spread lines from 4 km toward it,
about 105 reach it without touching any module under either shape model, so
a root `useaimtarget` probe from those directions is false regardless of the
link. The #60 firing geometry was not retained. Source:
`research/issue202-line-of-fire/settled.py` `station60()`.

The union-box centre is also where the turrets bear (see "Where a turret's
shoot controller bears on a selected target"). In the #202 benchmark, every
settled `xen_defence` turret whose line to the centre met no module also met
nothing when the line was continued past the centre (36 of 36 rows). A
stationary station gives no lead, so rounds aimed along those lines do not
hit it. The centre gap alone therefore cannot account for turrets that hit
the station. Those hits need a path that meets a module. On such a path the
muzzle root probe is true unless:

- the module-to-root link fails;
- the ray crosses into another zone's physics world;
- the firing turret's own socket is first (see "Some launcher sockets
  enclose their own launch points").

The turret-origin `excludeself="true"` ray removes the turret's own meshes,
so the socket cannot explain that ray's 0/14. This is inference from offline
geometry; the #60 firing geometry is still unknown.

## Where a turret's shoot controller bears on a selected target

- X4: 9.00 build 611726
- Status: inference
- Source: native trace, pinned executable above. Real RTTI names:
  `LargeTargetShootController` (vtable `0x02B7D088`); `U::Station`
  (`0x02B764D8`), `U::Ship` (`0x02B84A98`) and the element classes, for
  vtable slot `+0x1BF0`. Shipped-source census of `class="station"`
  components.
- Live test: no
- Finding: the point a turret bears on, which is also the far end of its
  pre-fire ray, is:

| Selected target | Bearing point |
|---|---|
| turret, shield or engine element | nearest authored aim point from the **turret component origin**, else the element box centre |
| whole ship with authored aim points | nearest authored aim point from the turret component origin |
| whole ship without one, box radius ≤ 500 m | box centre |
| whole ship without one, box radius > 500 m | box centre plus the LargeTarget offset, if that point lies inside the ship's own body; else the box centre |
| station root (modular station) | the live union-box centre; the offset is always rejected |

The turret origin selects the aim point for both X4's firing and MD
`useaimtarget`; see [macro-box-aimtargets.md](macro-box-aimtargets.md),
"Which origin selects the aim point".

The LargeTarget offset is set once, when the target is set
(`0x007E8330`), and added after the Basic solve (`0x007E8288`–`0x007E8321`,
rotated into the current target frame). The setter:

1. clears the offset;
2. requires a turret or guided weapon (slots `+0x1F48`/`+0x1F50`);
3. takes the weapon's first `defensible` ancestor (`0x0059DED0`: `+0x70` walk
   to class `0x23`), which is the firing ship for a ship-mounted turret;
4. requires target slot `+0x1BF0`:
   - `U::Station` returns constant true (`0x0009C980`);
   - `U::Ship` returns box radius > global `+0x502C` (`0x006DF200`). The only
     writer found by a full-image scan copies a parameter struct field that
     `0x0063E5F0` initialises to 500.0 (`0x0063E687`);
   - module, shield and engine classes return constant false (`0x000B38C0`);
   - `U::Turret` and `U::MissileTurret` use an untraced lookup (`0x005BF690`).
     It matters only for a turret element with no authored aim point;
5. requires no authored aim-point collection (`+0x760` null);
6. computes `offset = (turret origin in the firing ship frame − ship box
   centre) / ship half-extents × target half-extents × (0.25, 0.25, 0.75)`
   (constant `0x02CC11C0`);
7. keeps it only if `0x0051BEB0(target, box centre + offset)` is true.

`0x0051BEB0` resolves the target's physics owner (`0x007AD1E0`: the first
self-or-ancestor with its own physics, predicate `0x00795E90`). It
transforms the point into that owner's frame and runs the Jolt
`CollidePoint` of the owner's layer-0/1 body shape (body `+0x260`, shape
vtable `+0x88`, any-hit collector). A missing body, a compound in flux, or a
placeholder sub-shape (wrapper byte `+0x40`) returns false.

A station owns its own physics, but its modules own theirs (Module
`+0x1B50`), so the station's own body contains only the station component's
parts. None of the 40 ordinary `class="station"` components in the official
source sets has a part. The only ones that do are 7 landmark components and
a test asset. For every modular station the offset point is therefore never
inside the body, and the turret bears on the live union-box centre (Station
slot `+0x14B0`, instance box `+0xC90`). A station root has no authored aim
point either (census above).

Which layer-0/1 shape answers `CollidePoint` for a ship (the `-mesh` or
`-hull` Jolt shape) was not traced. The #202 benchmark therefore tests the
offset point against both, and treats disagreement as UNKNOWN.

What this changes:

- MD `useaimtarget` on a whole ship always ends at the box centre (it calls
  only `0x00520FC0`). For a ship above 500 m with no authored point, it tests
  a different endpoint from the one the turret bears on.
- Pre-fire classification of a station-root ray (`0x007E6CB0`): a module hit
  walks `+0x70` to the station, so it permits fire (result 1). A segment that
  reaches the union-box centre with no hit is a genuine miss, and every
  supported turret permits it. So X4 fires at a station root through the
  centre gap whether or not the line touches a module.

## find_object_surface is not a cheaper line-of-fire primitive

- X4: 9.00 build 611726
- Status: inference
- Source: `FindObjectSurfaceAction` vtable `0x02C0CA80`, run method
  `0x00BDE7E0`; XSD `libraries/common.xsd` `find_object_surface` (shipped
  source) for the attribute meanings
- Live test: no new run. An archived experimental branch recorded null results
  for engine surface elements; that result is not promoted.
- Finding:
  - `position` is the ray start. `end`, `component` or the object's frame origin
    sets the ray target.
  - `tolerateneighbour` defaults true. When true, the object is passed as the
    **include** component (`0x00BDF08B`), so the ray sees only sub-shapes of the
    object or its descendants and ignores the firing ship and any blocker.
    When false, the ray is cast against the world. The hit must belong to the
    object (`0x00BDF0E7`), and a further clearance query along the surface
    normal (`0x00BDF2B5`) can reject the point.
  - The first query uses object layers 0–2 (layer flag 0 at `0x00BDF05D`). A
    reverse layer-3 query must hit the same component within a squared-distance
    limit (`0x00BDF1C0`–`0x00BDF20D`).
  - Retries are built in:
    - With a `position` and no `end`: one outer pass (`0x00BDEBA8`) of up to 20
      attempts, each drawing random angular offsets from the engine RNG
      `0x1414DDC90` (range constants 90 and 45 at `0x02CBED5C`/`0x02CBED24`).
    - With no `position`: up to 10 outer passes over a random sphere.
    - With `end` supplied: a lattice over the object's `+0x14B0` box. The
      points are {-1,0,1}³ × half-extents + centre, skipping the centre
      (`0x00BDFBB5`–`0x00BDFF73`). It is reached at least when the
      `tolerateneighbour=false` clearance query hits within 1 m
      (`0x00BDFB81`–`0x00BDFBAF`).
  - Each attempt issues up to three ray queries. The result is a position and
    normal only: no hit identity and no reason for a null.

Not resolved: the unit of the ±45 offsets, whether the first attempt is already
jittered, and every entry path into the lattice. None of these can make the
action useful here. It is randomized. By default it ignores blockers. Its point
may lie off the muzzle-to-target line. A null cannot separate BLOCKED from a
miss. And it costs at least as many queries as the explicit-point method.

## Selected-target method (DESIGN CHOICE, not X4 firing behavior)

This is a design built on the traced action semantics.


- X4: 9.00 build 611726
- Status: inference
- Source: this file; same-ray hierarchy and zone-declared miss detection in
  [weapon-path-obstruction-groups.md](weapon-path-obstruction-groups.md);
  target-local box sources in [macro-box-aimtargets.md](macro-box-aimtargets.md)
  and [turret-fire-range-gate.md](turret-fire-range-gate.md); MD
  `create_position` object/space semantics in `libraries/common.xsd`
  (`position` attribute group, shipped source)
- Live test: not required to adopt it. Its failure modes under the unresolved
  station-root link and cross-zone boundary are UNKNOWN, never a false CLEAR.
  End-to-end behavior is still checked by the owning feature's normal LIVE
  validation.

Every query uses `object="$weapon" objectoffset="$weapon.barrelposition"`,
`useaimtarget="false"` and `excludeself="false"`. `false` is required: it is the
only MD setting that keeps the firing ship's hull. The firing turret's own
meshes, which native ignores, are identified separately rather than
over-excluded. Each line uses one world-space endpoint `E`, expressed in the
declared target's frame with
`create_position object=<frame owner of E> space=<declared target> value=<E>`.
Call `Q(X,E)` the query that declares target `X`. It is true iff the closest
filtered hit on the segment is `X` or a descendant of `X`.

Endpoints, all target-local so a rotating or moving target is handled by the
frame conversion at call time:

| Target | Declared target | `E` |
|---|---|---|
| Whole ship `T` | `T` | `T.macro.boundingbox.center`, pushed away from the muzzle by up to 0.9 × the smallest half-extent so it stays inside the box. This gives a hollow centre a chance to hit hull behind it. |
| Station | the chosen **module** `M` | `M.macro.boundingbox.center`. Modules are ranked once per pass by distance from the firing ship. Try the nearest module, then the second-nearest only if the first line is not CLEAR. |
| Turret/shield/engine element `T` | exactly `T` | `T.macro.boundingbox.center`. That box contains only collision-eligible parts. |

Declaring the module rather than the station root keeps CLEAR independent of
the unverified module-to-root link. The trade-off is that a hit on a different
module is reported UNKNOWN rather than CLEAR.

Per line, `W` is the firing turret, `S` the firing ship and `Z` `$weapon.zone`:

| Outcome | Rule | Calls |
|---|---|---|
| `Q(T,E)` or `Q(M,E)` true | **CLEAR**: first hit is the target, or for a station that module | 1 |
| Ship/element: `Q(T)` false, `Q(Z)` false | UNKNOWN: the line reached no geometry | 2 |
| Ship/element: `Q(Z)` true, `Q(W)` true | UNKNOWN: first hit is the firing turret's own mesh, which native ignores | 3 |
| Ship/element: `Q(Z)` true, `Q(W)` false | **BLOCKED ON TESTED PATH**: something else is hit first (own hull, a sibling element, the target's own parent hull or a neighbouring element, or an external object) | 3 |
| Station: `Q(M)` false, `Q(S)` true, `Q(W)` true | UNKNOWN (own turret mesh) | 3 |
| Station: `Q(M)` false, `Q(S)` true, `Q(W)` false | **BLOCKED ON TESTED PATH** (firing ship in the way) | 3 |
| Station: `Q(M)` false, `Q(S)` false | UNKNOWN: another module, an external object, or nothing | 2 |

UNKNOWN before any ray is cast:

- the weapon and target zones differ;
- a frame or endpoint cannot be built;
- turret class is unknown;
- missile guidance is missing.

A zone-declared call counts a hit only if the hit's parent walk reaches `Z`
(see [weapon-path-obstruction-groups.md](weapon-path-obstruction-groups.md)).
A broken chain yields UNKNOWN.

Guided loaded missile ammunition: **GUIDED**, with no ray. X4 skips its
pre-launch obstruction section for it
([weapon-path-obstruction-groups.md](weapon-path-obstruction-groups.md),
"Supported guided ammunition bypasses the pre-launch obstruction section").
GUIDED means X4 does not require a direct line. It is not a physical CLEAR claim
and not a prediction of impact. Conventional turrets, unguided missiles and
cluster carriers use the rules above.

Aggregate reporting:

- CLEAR is claimed only for a turret with at least one CLEAR line.
- A turret with no CLEAR line and at least one BLOCKED line is **blocked on a
  tested path**. This never implies that every path to a whole ship or station
  is obstructed, and it is not an overall LINE OF FIRE BLOCKED statement.
- A turret with only UNKNOWN lines is UNKNOWN.
- Report CLEAR, blocked-on-tested-path, UNKNOWN and GUIDED counts separately;
  never fold UNKNOWN or GUIDED into CLEAR or BLOCKED.

Worst-case work per turret per pass (operation counts from the source, not
timings):

| Case | Rays |
|---|---|
| Guided missile turret | 0 `check_line_of_sight` |
| Ship or element | 3 |
| Station | 6 (two lines × 3) |

Each `check_line_of_sight` is one closest-hit query with no internal retry.
Add a few `create_position` conversions per line and, for stations, one
distance read per module per pass for the module ranking. No cadence is implied.

Known physical limits of these endpoints, all resolved conservatively as UNKNOWN:

- a hollow ship centre with nothing within the pushed endpoint;
- sparse or zero-radius modules (a docking bay can fall back to its parent box);
- a thin or curved element whose box centre lies off its mesh;
- a ship whose runtime box is delegated to a child object, so it differs from
  `macro.boundingbox`.

If a muzzle lies inside its own ship's hull, the line reports BLOCKED or
UNKNOWN, never CLEAR. Whether Jolt reports a hit for a segment starting inside a
mesh was not traced.

## Collision shapes offline

### Layer-3 collision geometry is readable from the catalogs in two shape models

- X4: 9.00 build 611726
- Status: inference
- Source: geometry loader `0x140F51360` (format strings `%s\%s-mesh`,
  `%s\%s-hull` stored at geometry `+0x20`/`+0x28`, then `-collision`/`-collision1`
  XMF at `+0x30`; "Missing collision mesh/hull shape file"); catalog files
  `<part>-mesh.jcs`, `<part>-hull.jcs`, `<part>-collision.xmf`; reader
  `research/issue202-line-of-fire/geometry.py`
- Live test: no
- Finding:
  - Every collision part ships a Jolt triangle `MeshShape` (`-mesh.jcs`,
    subtype 12) and a convex shape (`-hull.jcs`): one `ConvexHullShape`
    (subtype 6) or, for large hulls, a `StaticCompoundShape` (7) of convex
    pieces. The Boron Ray `part_main` has 128 pieces and the Osaka 256.
  - `-collision.xmf` carries the same triangles as the mesh shape's source.
    On the Ray hull, `-collision` and `-collision1` are the same 95,372
    triangles; on turret parts `-collision1` is a reduced mesh.
  - Which shape the layer-3 query body uses was **not traced**. Offline
    physics should cast against both and treat disagreement as UNKNOWN.
  - Hull `.jcs` points are stored about the shape's centre of mass. Compound
    children are unrotated, and each is placed by its sub-shape centre-of-mass
    position.

### Turret moving parts carry no layer-3 collision

- X4: 9.00 build 611726
- Status: shipped-source
- Source: component XML of `turret_bor_m_railgun_02_mk1` and
  `turret_bor_l_disruptor_01_mk1` (connection tags); layer-3 part filter in
  [weapon-path-obstruction-groups.md](weapon-path-obstruction-groups.md)
- Live test: no
- Finding: the rotator, gun and barrel part connections are tagged
  `nocollision`; only the fixed `part_socket` (and, on the railgun, an
  untagged socket decal) is layer-3 geometry. Both ships' hulls collide only
  through `part_main`. The firing turret's own layer-3 mesh, which MD
  `excludeself="false"` sees, is its socket. A line from a parked barrel toward
  a target behind it crosses that socket. Other turret families were not
  censused.

### Some launcher sockets enclose their own launch points

- X4: 9.00 build 611726
- Status: inference
- Source: offline geometry from the shipped `-collision.xmf` and `-hull.jcs` of the socket parts;
  `research/issue202-line-of-fire/settled.py` (#202 benchmark)
- Live test: no
- Finding:
  - `turret_arg_m_dumbfire_02_mk1`'s only layer-3 part is a 12-triangle
    socket box, 16 × 8 × 16 m, around the whole launcher. Its first launch
    point lies inside that box in 368 of 400 sampled settled poses, under
    both shape models.
  - `turret_kha_m_beam_01_mk1`'s layer-3 socket (`anim_socket`) is about
    34 × 21 × 36 m. `turret_par_l_dumbfire_01_mk1`'s socket is a 446-triangle
    mesh.
  - A `check_line_of_sight` from `barrelposition` with
    `excludeself="false"` therefore first hits the firing turret itself for
    these turrets, even when the turret has turned toward the target. X4's
    pre-fire gate ignores those meshes, so this is not an obstruction.
  - #202 benchmark counts of settled rows whose bearing path is clear but
    whose probe first hit the firing turret:
    - `arg_m_dumbfire_02`: 610 of 670;
    - `par_l_dumbfire_01`: 48 of 276;
    - `kha_m_beam_01`: 16 of 676;
    - every other benchmark turret: 0.

## Remaining uncertainties

None of these blocks adopting the method, because each one resolves toward
UNKNOWN:

1. The cause of the station-root false negative above. Declaring the station
   root, so that any module hit counts as CLEAR, would first need a controlled
   LIVE check of root-declared versus module-declared rays on one explicit
   module-centre endpoint.
2. How often the firing turret's own mesh is the first hit from its muzzle.
   Offline it is high for some launchers and one beam turret (see "Some
   launcher sockets enclose their own launch points"). Every such line is
   UNKNOWN (`self`), however many points are tried.
3. The cross-zone and pair-collision-filter caveats already recorded in
   [weapon-path-obstruction-groups.md](weapon-path-obstruction-groups.md).
4. Frame-time cost, which is not measured here.
