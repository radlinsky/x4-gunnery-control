# Turret weapon-path groups for line-of-fire decisions

Scope: X4 9.00 build 611726, official base game plus installed official extensions,
with Star Wars Interworlds 0.9.1 HF checked separately for compatibility.

Purpose: record the source-backed weapon behavior groups that matter when deciding
whether an obstruction can prevent a selected turret from engaging one supplied
firing-origin + aim-point pair. This record does not define the final obstruction
rule for every group.

## Supported weapon-path groups

- X4: 9.00 build 611726
- Status: inference
- Source: complete official combat-turret projectile/ammunition corpus audit,
  using the official source sets under the ignored research cache; relevant
  property and script sources are listed below
- Live test: partial — representative conventional, guided-missile, and ordinary
  unguided-missile behavior was live-tested previously; the distributing-cluster
  case has not been live-tested
- Finding: the supported official combat-turret corpus requires four materially
  different line-of-fire behavior groups:
  1. conventional straight-path weapons;
  2. guided missiles;
  3. ordinary unguided direct missiles;
  4. distributing cluster missiles whose unguided carrier later releases guided
     child missiles.

The split is based on how the loaded weapon can deliver damage from its firing
origin toward the supplied aim point. Turret names, faction names, display names,
and geometry are not classification inputs.

Official supported coverage is 124 combat/equipable turret macros: 92
conventional turrets and 32 missile turrets. The 32 missile turrets' default
ammunition divides evenly between guided and ordinary unguided defaults. Across
compatible ware-backed official turret ammunition, the audit found 15 guided
missile macros, 8 ordinary unguided missile macros, and 2 distributing-cluster
missile macros.

## Conventional combat turrets form one supported path group

- X4: 9.00 build 611726
- Status: inference
- Source: all 92 supported official conventional combat turrets, resolving 52
  unique authored bullet definitions under the official source sets
- Live test: partial — conventional own-hull masking is live-tested for
  turret_arg_m_plasma_02_mk1_macro; this corpus audit is source-only for the
  remaining conventional variants
- Finding: no supported conventional projectile introduces a second delivery
  route around an obstruction. The supported corpus may alter what happens at or
  after impact, but the initial damage-delivery path remains a direct beam or
  projectile path from the firing origin toward the aim point.

The audit covered the apparent exceptions instead of assuming that every
non-missile turret behaves identically:

- 15 turrets / 11 bullet macros use beam attachment;
- 9 turrets / 6 bullet macros use area damage;
- 8 turrets use planned self-destruction and 8 use self-destruction, covering 5
  macros;
- 5 turrets / 3 macros emit multiple projectiles;
- 2 turrets use one sticky-projectile macro;
- 7 turrets / 5 macros apply impact influences;
- 7 turrets / 5 macros use damage curves;
- no supported projectile has maxhits greater than 1;
- no supported projectile has non-zero ricochet;
- no supported projectile has guided, detached, distributing, spawned, steering,
  or chained delivery behavior.

Beam attachment changes persistence/presentation after the direct trace. Area
damage expands damage at impact or detonation. Timed destruction changes where a
projectile terminates. Multiple-projectile weapons create several direct paths in
a spread. Sticky behavior happens after contact. Influence, damage-curve, and
shield-piercing properties change effects rather than the route used to reach the
aim point.

The audited Boron weapons with "arc" presentation do not author a chained or
steering delivery route: their supported projectile definitions remain ordinary
single-hit bullets with no ricochet or beam attachment and apply their special
effect on hit.

One official projectile outside the accepted supported combat-turret corpus has
maxhits="2" and a small ricochet value. No supported combat turret references
it. Its existence is a reason not to classify an unaudited modded bullet as
conventional merely because it is a bullet.

## Guided missiles form one supported group

- X4: 9.00 build 611726
- Status: shipped-source
- Source: loaded-ammunition guidance properties in
  libraries/scriptproperties.xml; official turret-compatible missile corpus;
  fixed-launcher guidance branches in
  aiscripts/fight.attack.object.bigtarget.xml
- Live test: yes — representative guided missile turrets were live-tested on
  2026-08-23; see md-ai.md and testing-experiments.md
- Finding: all 15 compatible ware-backed guided ammunition macros relevant to
  official turret use expose affirmative guidance. Smart, retargeting, swarm,
  interceptor-style, and other guided definitions add steering/target-selection
  behavior after launch, but shipped source exposes no second guided
  line-of-fire category.

The existing controlled live test established the important minimum boundary:
guided missile turrets can launch and reach the designated surface even when the
firing ship masks the direct muzzle-to-target ray. PR #66 R1 is that LIVE
corroboration, and it covers the tested own-hull case for ordinary M/L guided
Mk1 ammunition only.

PR #66 R6 is not live proof of the external-blocker rule. R6 recorded blocked
per-turret rays and Gunnery Control's own ENGAGEABLE prediction behind a solid
Asgard; it never observed X4 launching guided missiles through that blocker.

### Supported guided ammunition bypasses the pre-launch obstruction section

- X4: 9.00 build 611726
- Status: inference
- Source: native trace of the pinned executable, SHA-256
  `19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`, image
  base `0x140000000`; see [native-analysis.md](native-analysis.md) for the
  recipe and the verify-before-use hash rule
- Live test: partial — own-hull case corroborated by PR #66 R1; the
  external-blocker case is native-only
- Finding: the common pre-fire gate takes one guidance decision for loaded
  ammunition, and affirmative guidance skips the entire target-directed
  obstruction section before any collision query runs.

Reproducible native surface:

- the common firing update at RVA `0x008132D0` calls the pre-fire gate at RVA
  `0x00816D20` (one `.pdata` function spanning `0x00816D20`–`0x00817CEF`);
- inside that gate, `0x008179A1` issues a virtual call through weapon vtable
  slot `+0x1F50`, and `0x008179A9` branches on a true result past the
  target-directed obstruction section `0x008179AF`–`0x00817C46`, landing where
  the permit flag is set;
- both of that section's collision queries, `0x00817B09` and `0x00817BDE`, call
  the shared physics query `0x000BC4D0` and therefore never execute for guided
  loaded ammunition;
- slot `+0x1F50` of the `U::MissileTurret` vtable (base RVA `0x02B00620`,
  confirmed by its RTTI type descriptor) is implemented at RVA `0x0060A930`,
  which resolves the loaded missile defaults and returns the guidance byte at
  `+0xBB1`.

Consequences carried by that single branch:

- the firing ship's own hull does not make a supported guided missile LINE OF
  FIRE BLOCKED;
- an unrelated external solid ship, station, or module on the direct
  firing-origin-to-target ray does not make one either, because the same
  bypassed section holds the only queries that could observe it;
- subtype does not matter. Swarm, smart/retargeting, torpedo/heat-seeking,
  interceptor-style, EMP/disruptor, and ordinary guided macros all author the
  affirmative guidance that this one byte carries, so none of them can select a
  different pre-launch obstruction branch.

No separate pre-launch local muzzle-clearance veto exists on the traced path:
neither the `U::MissileTurret` fire method at RVA `0x0060AAF0` nor
`Missile::Shoot` at RVA `0x00606F20` issues the shared physics query before the
missile is created.

Collision handling after creation is post-launch behavior and is outside
Issue #186: the launched-missile update beginning near RVA `0x00606940` runs its
own collision query at `0x00606B8B`, but by then X4 has already launched, so it
cannot withhold the launch.

This resolves the supported guided case without further source/native search or
a new LIVE test. Unknown, future, or unaudited modded ammunition still fails
closed under the UNKNOWN rule below whenever its loaded-ammunition behavior
cannot be established safely.

## Ordinary unguided direct missiles form one supported group

- X4: 9.00 build 611726
- Status: shipped-source
- Source: official turret-compatible missile corpus
- Live test: yes — representative dumb-fire missile turrets were live-tested on
  2026-08-23; see md-ai.md and testing-experiments.md
- Finding: 8 compatible ware-backed ammunition macros are ordinary unguided
  missiles: guidance is explicitly false and no distributing/detached child
  delivery stage is authored. The scatter missile remains in this group:
  multiple unguided projectiles do not create an alternate guided route.

The retained live test established that the tested dumb-fire turrets could launch
when only the firing ship masked the direct ray. It did not establish whether an
external blocker makes X4 withhold an unguided launch; see the R2/R6 distinction
below.

Read PR #66 R2 and R6 apart. R2 observed 92 real dumb-fire launches under
own-hull masking, so the own-hull half is LIVE. R6 behind the solid Asgard
recorded blocked per-turret rays and Gunnery Control's own predicate result, not
X4 withholding a launch, so the external-ship half is not LIVE-proven either.

### The unguided pre-launch obstruction query and its filters

- X4: 9.00 build 611726
- Status: inference
- Source: native trace of the pinned executable, SHA-256
  `19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`, image
  base `0x140000000`; see [native-analysis.md](native-analysis.md)
- Live test: no — the mechanism below is static-trace only
- Finding: for loaded ammunition whose guidance byte is false, the common
  pre-fire gate runs the target-directed obstruction section, which issues two
  ray casts into the physics engine under one fixed filter configuration.

What the trace establishes about the mechanism:

- the section's two queries at `0x00817B09` and `0x00817BDE` both call
  `0x000BC4D0`, a thin wrapper that transforms the endpoints and tail-calls
  `0x000BB5D0` at `0x000BC71F`;
- the physics layer is Jolt (`JPH`) behind Egosoft's `XPhys` wrappers. The
  query builds a `XPhys::XCastRayCollectorClosestHit` collector with a
  `JPH::BroadPhaseLayerFilter` whose accept method is a constant-true stub at
  RVA `0x0009C980`, an `XPhys::XObjectLayerFilter` (`ShouldCollide` at RVA
  `0x000B52C0`), and an `XPhys::XBodyFilter`;
- the body filter carries the firing weapon as an exclude object, which is the
  mechanism behind the own-hull result rather than a separate rule;
- `XPhys` defines exactly five object layers. `XPhys::XBroadphaseLayer`
  (constructed at RVA `0x000C6913`) maps object layers 0..4 to broad-phase
  layers `0,1,2,2,1`, and `GetBroadPhaseLayer` at RVA `0x000B51D0` rejects any
  layer id of 5 or more;
- `XObjectLayerFilter::ShouldCollide` accepts a body iff its object layer is not
  4 and its own boolean member equals `layer == 3`. The gate passes that member
  as a literal `1`, so the pre-fire query reports hits on object layer 3 only.
  The launched-missile update at `0x00606940` passes `0`, so its collision query
  at `0x00606B8B` sees object layers 0, 1 and 2 instead;
- after the first ray cast the gate classifies the hit through a virtual call at
  `0x00817B27` that returns 0, 1 or 2; that classifier decides what the hit
  means before the second segment is cast.

This pins the mechanism but not the blocker categories. Which game objects carry
object layer 3, and what the `0x00817B27` classifier does with a hit, are not
established here; see the remaining questions.

## Distributing cluster missiles are a separate supported group

- X4: 9.00 build 611726
- Status: shipped-source
- Source: assets/props/WeaponSystems/missile/macros/ —
  missile_cluster_heavy_mk1_macro.xml and missile_cluster_light_mk1_macro.xml,
  plus their detached guided child missile definitions
- Live test: no
- Finding: the heavy and light cluster ammunition macros author an unguided
  distributing parent that later detaches guided swarm children. The loaded
  parent therefore reports as unguided even though the eventual damage-delivery
  stage can steer after detachment.

This makes a simple "guided=false means ordinary dumb-fire" classifier unsafe
for the *post-launch* delivery stage: the carrier's children can take different
paths after detachment. It does not change the pre-launch rule.

### Cluster parents take the ordinary unguided pre-launch path

- X4: 9.00 build 611726
- Status: inference
- Source: native trace of the pinned executable (hash and base as above), plus
  the two shipped cluster macros
- Live test: no
- Finding: `distribute` is not reachable by the pre-launch decision at all. Both
  cluster parents are `guided="0"`, and guidance is the only ammunition
  discriminator the pre-fire gate consults, so they enter the same
  target-directed obstruction section as ordinary unguided missiles.

The proof is the field, not the flag name:

- `distribute` is parsed into the loaded-ammunition defaults at byte `+0xCD1`
  (attribute id `0xB2`, written at RVA `0x0060905D`), a different field from the
  guidance byte `+0xBB1` (attribute id `0x10C`, written at RVA `0x00568F45`);
- a whole-image scan finds exactly one engine reader of `+0xCD1`: RVA
  `0x006063F0`, reached only through `U::Missile` vtable slot `+0x5C0`. That is
  a terminal handler on an already-created missile, and it selects between the
  child-release path at RVA `0x00608650` and ordinary detonation at RVA
  `0x00608E50`;
- neither the pre-fire gate `0x00816D20`, nor the `U::MissileTurret` fire method
  `0x0060AAF0`, nor `Missile::Shoot` `0x00606F20` reads `+0xCD1`;
- within the gate the only ammunition-behavior queries are weapon vtable slots
  `+0x1F50` (guidance, RVA `0x0060A930`) and `+0x1F18` (its negation, RVA
  `0x0060A8C0`), and both read the same `+0xBB1` byte.

So the pre-launch obstruction rule cannot differ between a cluster parent and an
ordinary unguided missile: the engine has no pre-launch access to the property
that distinguishes them. Whatever blocker rule the unguided path turns out to
use applies unchanged to both cluster macros.

## Runtime classification boundary and UNKNOWN rule

- X4: 9.00 build 611726
- Status: inference
- Source: libraries/scriptproperties.xml weapon/ammunition and launched-missile
  properties plus the audited official projectile/ammunition corpus
- Live test: no — classification rule derived from the source-visible boundary
- Finding: safe pre-fire classification needs the exact loaded ammunition macro
  and enough authored behavior information to distinguish the four path groups.

The runtime weapon surface exposes the loaded ammunition macro and guidance
state. It does not expose the loaded ammunition macro's distributing state before
launch; missile.isdistributing is a property of an already-launched missile.
Therefore guidance alone cannot distinguish ordinary unguided ammunition from the
official distributing-cluster ammunition before firing.

For official supported weapons, generated source-derived metadata can safely
carry the missing authored behavior. It should be derived from ammunition or
projectile properties rather than a hand-maintained weapon-name list.

Return UNKNOWN instead of guessing when any of the following can materially
change the path rule:

- there is no loaded ammunition macro;
- the macro cannot be resolved or has an unrecognized class;
- guidance state is missing or ambiguous;
- an unguided missile's distribution/detachment behavior is unavailable;
- a modded bullet has not been audited for multiple-hit/penetration, ricochet,
  detachment, spawning, steering, chaining, or another alternate-path facility;
- a modded guided missile combines guidance with additional unaudited behavior
  that could materially change the obstruction rule.

## SWI 0.9.1 HF compatibility

- X4: 9.00 build 611726; SWI: 0.9.1 HF
- Status: third-party-technique
- Source: the accepted 164 combat + equipable SWI turret corpus and its
  projectile/ammunition definitions in the ignored SWI source cache
- Live test: no — SWI 0.9.1 HF is not available in the current X4 9.00 live
  environment
- Finding: the same behavior classification covers the accepted SWI corpus with
  no extra SWI-specific group:
  - 160 conventional straight-path turrets;
  - 4 guided missile turrets;
  - 0 ordinary unguided missile turrets;
  - 0 distributing-cluster missile turrets;
  - 0 unresolved under the audited source data.

The four supported SWI missile-turret ammunition definitions explicitly author
guided behavior. No SWI-specific alternate delivery route requires another
line-of-fire group.

## Reproducible source surface

Principal source locations used by the audit:

- libraries/scriptproperties.xml:
  weapon.ammo.macro, weapon.ammo.iscompatible, weapon.isbeam,
  weapon.ammo.isguided, turret/missile-turret datatypes, macro guidance/beam
  properties, and launched-missile swarm/distributing properties;
- aiscripts/fight.attack.object.bigtarget.xml: fixed-launcher ammunition and
  guidance branches. Turret weapons are excluded from that ship-aim branch, so
  it proves guidance is a fire-control discriminator but not the
  missile-turret launch obstruction rule;
- aiscripts/move.attack.object.capital.xml: generic weapon range/LOS handling;
  it is not the engine-side missile-turret launch rule;
- libraries/common.xsd: check_line_of_sight and its explicit endpoint
  attributes;
- official turret, bullet, and missile macros under
  assets/props/WeaponSystems/*/macros/ in the accepted official source sets;
- cluster parents missile_cluster_heavy_mk1_macro.xml and
  missile_cluster_light_mk1_macro.xml, whose authored behavior is unguided and
  distributing and whose detach stage resolves to guided swarm children;
- representative guided child missile_swarm_heavy_mk1_macro.xml;
- representative unguided scatter ammunition
  missile_scatter_heavy_mk1_macro.xml;
- accepted SWI 0.9.1 HF turret/projectile/ammunition source cache.

The shipped AI-script census found only five uses of check_line_of_sight
(lockbox, mass-traffic police/watchdog, capital mining, and capital
attack/movement code). None exposes the engine's missile-turret launch
obstruction decision.

No new native-executable analysis was needed to establish the path-group census.
The guided bypass, the unguided/cluster path convergence, and the pre-fire
query's Jolt/XPhys filter configuration are separate native results.

## Remaining obstruction questions

These are not L2 grouping gaps. They are the unresolved behavior needed before a
complete line-of-fire rule can be frozen.

1. **Blocker categories for the unguided/cluster path:** the pre-fire query is
   a Jolt closest-hit ray cast restricted to object layer 3, with the firing
   weapon excluded, and its hit is then classified by the virtual call at
   `0x00817B27`. What remains unproved is which game objects carry object
   layer 3 — ships, stations/modules, asteroids and other terrain geometry each
   need to be placed — and what the classifier's 0/1/2 result does with a hit.
   A scan for object-layer assignment was too ambiguous to settle this: the
   assignment is not a single named site. The next source/native attempt should
   resolve the classifier at `0x00817B27` first, since it sits closer to the
   fire/no-fire decision than the layer table does.

2. **Conventional terrain:** determine whether asteroid/terrain collision
   geometry participates in the conventional pre-fire obstruction query. This is
   the same object-layer question seen from the conventional side, and the two
   should be resolved together.

Two earlier questions are now closed. Guided subtypes: the pre-fire gate takes
one guidance decision and supported guided ammunition bypasses the obstruction
section entirely. Cluster parents: `distribute` is unreachable before launch, so
they share the ordinary unguided path by construction.

Resolve these only to the extent they can materially change the retained
line-of-fire rule. Prefer further source/native proof before adding new LIVE
tests.
