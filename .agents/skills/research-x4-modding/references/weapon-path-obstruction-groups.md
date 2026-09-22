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
firing ship masks the direct muzzle-to-target ray. That test does not by itself
prove every external-obstruction rule for every guided subtype.

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
when only the firing ship masked the direct ray, while a solid external Asgard
that blocked the direct path caused rejection. That establishes the tested
own-ship/external distinction but does not substitute for the broader L3 rule.

## Distributing cluster missiles are a separate supported group

- X4: 9.00 build 611726
- Status: shipped-source
- Source:
  assets/props/WeaponSystems/missile/macros/missile_cluster_heavy_mk1_macro.xml
  and
  assets/props/WeaponSystems/missile/macros/missile_cluster_light_mk1_macro.xml,
  plus their detached guided child missile definitions
- Live test: no
- Finding: the heavy and light cluster ammunition macros author an unguided
  distributing parent that later detaches guided swarm children. The loaded
  parent therefore reports as unguided even though the eventual damage-delivery
  stage can steer after detachment.

This makes a simple "guided=false means ordinary dumb-fire" classifier unsafe.
The carrier may require a viable launch/deployment segment while its children can
take different paths after detachment. Shipped source establishes the two-stage
path but does not establish the exact obstruction rule or detachment boundary
used by the engine.

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

## Remaining obstruction questions

These are not L2 grouping gaps. They are the unresolved behavior needed before a
complete line-of-fire rule can be frozen.

1. **Distributing cluster missiles:** source establishes the unguided
   carrier/guided-child path, but not the engine's exact launch obstruction rule,
   detachment timing, or how far the carrier must have a clear route before
   guided children can take over.

2. **Conventional variants:** the full source corpus supports one straight-path
   group, but live obstruction evidence currently covers plasma specifically.
   Source does not expose the engine-side pre-fire obstruction check for every
   beam or planned-detonation/area variant.

3. **Guided subtypes:** shipped source exposes one guidance group and no
   discriminator supporting a further split, but existing live obstruction
   evidence does not exercise every guided subtype.

Resolve these only to the extent they can materially change the retained
line-of-fire rule. Prefer further source/native proof before adding new LIVE
tests.
