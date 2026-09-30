# OUTSIDE_BOX evidence audit

Issue [#169](https://github.com/radlinsky/x4-gunnery-control/issues/169),
2026-09-16. Frozen study `11bd0ffa05f6f519485cfc365600e7b2a0c2d9dc`;
starting checkout `43852e95ce5110710180104c51369852585eaddd`.
**Offline audit complete; the three new runtime-box predictions below remain
experimental pending LIVE measurement.** No reconstruction or Route A change.

## Population and source structures

The cached `corpus.pkl` and `corpus.orig.pkl` have identical records. The four
study scripts are unchanged from the frozen commit. There are exactly 98
outside-point macro records / 94 component assets, all with one unparented
`con_aimtarget_01`. This includes the 22 already-resolved zero boxes from #168;
they never reach the OUTSIDE_BOX check. The other 76 records are turrets, and
every one exceeds only the box's +Y face, by 0.348431–8.853565 m.

| Reusable source structure | Records | Frozen OUTSIDE_BOX | Production surface records | Production surface OUTSIDE_BOX |
|---|---:|---:|---:|---:|
| No eligible sized geometry (#168, unchanged) | 22 | 0 | 0 | 0 |
| Direct root geometry, identity connection transforms | 35 | 253,885 | 34 | 246,047 |
| Direct root geometry, translated connections | 21 | 158,157 | 18 | 147,657 |
| Root socket plus a contained parented light/decal part | 4 | 32,232 | 3 | 23,798 |
| Referenced root socket | 16 | 112,463 | 16 | 112,463 |
| **Total** | **98** | **556,737** | **71** | **529,965** |

These are structural groups, not production dispatch rules. The translated
group includes a two-root-part asset; neither extra eligible root geometry nor
the four parented extras raises the upper face enough to contain its aim point.

Full per-record enumeration and source traces are ignored research artifacts:
`.x4-research-cache/issue169/records.md` and `records.json`. They retain each
macro/component/source path, authored point, frozen binary32 point, C/H,
bounds, per-axis excess, eligible/excluded parts, connection and parent
transforms, referenced source identities, compatible hosts, and failure count.
The throwaway audit/replay scripts are in that same cache, not the permanent
suite. This report preserves the durable interpretation and LIVE discriminator.

### Frame and reconstruction checks

Source facts (`shipped-source`), verified against **194/194 installed catalog
hashes**, with no mismatch. The population audit additionally matched all **7,524**
indexed component/macro asset files and the two targeting scripts plus
`common.xsd` against installed catalog hashes:

- All 98 aim connections have only `name` and `tags` attributes: no parent.
  Their translation is in the component frame. Mounting the component does not
  turn that translation into a hull-local point.
- None of these components supplies a component/layer `<size>`; none of the
  macros has a child-macro connection. Child placement, attach modes, layer
  overrides, and child contribution therefore cannot explain these records.
- Every eligible part has an identity part `<offset>`. The 16 referenced
  eligible sockets resolve one level to a source part with identity part and
  source-connection offsets. Their sizes are inherited and source tags merged.
  There is no unresolved or recursive part reference in this population.
- The eligible connection rotations are identity. Nonzero connection
  translations are already applied. The four eligible parented extras compose
  child-connection translation with the owning socket connection; their boxes
  are contained by the root socket box. No animated upper-part transform is
  needed for the collision-filtered result.
- `PART_OFFSETS=True` changes no affected bound materially: maximum difference
  from frozen C±H is `2.22e-16 m`. This is a bounded irrelevance result for these
  records, **not** broad proof that part offsets can always be omitted.
- The upper turret geometry is predominantly tagged `nocollision`; eligible
  socket/base geometry remains lower than the separate authored aim point.
  Including excluded parts is a counterfactual, not a correction. Even that
  enlarged union leaves six of the 98 authored points outside.

Representative direct socket: `turret_arg_m_beam_02_mk1` has a root
`Connection01` / `part_socket`, center Y `1.519605`, half-height `1.519545`.
Union with origin gives Y `[0, 3.03915]`. Its unparented aim point is
`(0, 5.425042, 0)`. Its rotator/gun/barrel connections are `nocollision`.

Representative translated/parented structure: `turret_bor_m_guided_01_mk1`
has socket center `(-0.0000007195, 0.1840877, -0.1080007)` and connection
translation `(0.0000007195, 0.4634921, 0.1251084)`. The resulting upper Y is
`1.2951596`; the aim point Y is `1.696513`. Its eligible parented socket decal
uses the composed translation `(-0.0000003017, 0.6561432, 0.2497159)` and
remains inside the socket box.

Representative referenced structure: `turret_ter_m_beam_02_mk1` explicitly
references `turret_ter_m_base_01.part_socket`; both relevant transforms are
identity. Referenced lights/decals acquire their source exclusion tags. The
socket's upper Y is `3.03915`; the aim point Y is `5.425042`.

The [focused native reference](../../.agents/skills/research-x4-modding/references/macro-box-aimtargets.md)
records the property getter, template/macro box slots, eligibility branch,
and independent raw aim selector. Native interpretations remain `inference`.
The five earlier LIVE discriminators remain accepted for their stated
transform/origin/filter/child/referenced-tag checks; they did **not** measure
these three new representative boxes.

## What actually causes the frozen failures

All 2,585,916 cached trial records were scanned; **no simulation rerun** was
performed. Exactly 556,737 ordinary records have `reason=OUTSIDE_BOX`, all
from the 76 nonzero-box records above. No official-adversarial or synthetic
trial contributes to this bucket. All three queried identities are zero in
556,734 cases; the other three cases use two queries, both identity zero.
There is no hidden switch or alternative authored point in this population.

The failure-path logger omits X/E. Re-evaluating just the algebra after the
queries, using the preserved ray origins/directions and frozen C/H, gives:

- 556,737/556,737 containment rejections reproduced;
- 0/556,737 reconstructed-point errors exceeding E;
- maximum `|X-P| = 0.00872840 m`;
- maximum E `0.08940698 m`;
- minimum distance past an E-expanded face `0.34247250 m`;
- maximum `|X-P|/E = 0.126879` (rounded up).

Thus this bucket rejects accurate reconstruction of the sole authored point
because that point is above the reconstructed collision-filtered box. This
is established for these trials, not inferred from the aggregate count or
applied to the OUTSIDE_BOX reason universally. The numerical margin also
rules out a binary32 boundary accident in this bucket.

**Cause classification:** in the frozen model, this is a **wrong universal
containment assumption** and a resulting **coverage limitation**. No offline
reconstruction/input defect is demonstrated. There is no point-switch or
numerical/setup artifact in the logged failures. For the 27 out-of-production
records below, population scope is a separate classification; it does not
make their source boxes incorrect. Runtime attribution of the nonzero socket
boxes remains experimental until the requested measurements.

## Production scope

Use the equipment component's unique `component` mating connection, remove
only the structural `component` tag, and require the remaining tags to be a
subset of an actual macro-referenced host connection's tags. Enumerate L/XL
ship and station-module classes, not name patterns. Then exclude integrated
hull definitions, resolving inherited properties.
Mount compatibility alone is not surface-target selectability. This uses the
documented ship-upgrade matching rule and shipped target-selection filters.
Check all
host classes when determining that a required combination has no host.

- The 22 zero boxes remain out of scope for the reasons accepted in #168;
  this audit does not reopen them.
- Two additional nonzero records require `unhittable` medium mounts:
  `turret_arg_m_beam_01_mk1_macro` (1,870 failures) and
  `turret_arg_m_mining_01_mk1_macro` (1,969). Matching sockets are on M ships,
  not selectable destructible L/XL/station surface mounts.
- `turret_bor_m_mining_02_mk1_macro` contributes 8,434 failures. Its required
  set is `advanced hittable medium mining turret`. No macro-referenced host
  connection in any scanned official component class contains that full set.
  Ware presence and an alias reference do not supply a compatible host.
- Two mount-compatible records explicitly author `hull integrated="1"`:
  `turret_kha_l_beam_01_mk1_macro` (7,838 failures) and
  `turret_xen_xl_battleship_01_mk1_macro` (6,661). Shipped
  `aiscripts/lib.target.selection.xml:338,344` and
  `aiscripts/order.fight.attack.object.xml:642–648` explicitly require
  `integrated="false"` for surface targets; `libraries/common.xsd:5643`
  identifies integrated components as built into their parent. The Kha'ak
  scenario macro overrides this to `integrated="0"` and is retained: shared
  component identity alone is not sufficient for population membership.
- Of the 73 mount-compatible records, the remaining **71 non-integrated
  macro records / 68 components** are source-eligible L/XL/station destructible
  surface targets: **529,965** frozen OUTSIDE_BOX trials. This retains
  missile, mining, story/scenario, and alias records when compatible; target
  scope is not the separate 92-conventional-shooter census. Compatibility is
  capability, not an assertion that every stock loadout equips every macro.

Hence **26,772** OUTSIDE_BOX failures are outside the current production
surface population; the other **529,965** remain a production-relevant
coverage concern, conditional on the runtime-box check. These are raw
population partitions, not encounter-frequency rates. The original 556,737
remains the correct broad-corpus count. No trials were deleted or re-scored.
All decision/ENGAGEABLE figures remain diagnostic until #173.

## Containment and Route A consequence

The native selector returns the raw authored translation, without a box
containment test or clamp. Shipped `aimtarget` documentation describes an aim
connection, not a requirement to stay in `macro.boundingbox`. The independent
geometry-filter and aim-selection paths provide strong **inference** that X4
allows such points; designer intent and the new runtime box values are not
LIVE-proved here. Do not promote that inference merely because the points
fit an all-parts alternative.

P3c's inside-box acceptance check is **only conditionally useful**: it is an
optional box-model admission check, not a universal validity test for an X4
aim point. It does not by itself prove that advancing toward box entry stays
before the selected point. Removing it also does not repair that advancement
assumption or prove the revised algorithm safe. No rule has been removed.

If the LIVE predictions pass, retaining Route A unchanged means accepting
this coverage loss and allowing generic fallthrough/UNKNOWN; restoring
coverage requires a separately justified rule/model change. There is no
basis for a macro-name exception or a forced reconstruction expansion.
No fallback design, production adoption, or work on the next audit issue is
part of this change.

## Minimal remaining LIVE measurement

Scenario `issue-169-outside-box-r1` replaces the obsolete #168 geometry probe
and removes its dedicated loadout. The repository spec is disabled; Test Lab
installation enables only the installed copy. One ordinary player-owned
Paranid M frigate is spawned solely to use the existing successful-scenario
trigger. Equipment, turret state, target selection and combat are irrelevant:
the measurements are static **macro** properties.

| Role / macro | Predicted C | Predicted H (`.max`) | Authored point |
|---|---|---|---|
| Direct / `turret_arg_m_beam_02_mk1_macro` | `(0, 1.519575, 0)` | `(7.796589, 1.519575, 7.886265)` | `(0, 5.425042, 0)` |
| Translated + parented / `turret_bor_m_guided_01_mk1_macro` | `(0, 0.6475798, 0.0171077)` | `(3.275054, 0.6475798, 3.987159)` | `(0, 1.696513, -0.5556629)` |
| Referenced / `turret_ter_m_beam_02_mk1_macro` | `(0, 1.518725, -0.03249645)` | `(7.502298, 1.520425, 7.903461)` | `(0, 5.425042, 0)` |
| Prior LIVE control / `engine_arg_l_allround_01_mk1_macro` | `(0, 0, -14.91819)` | `(24.54942, 24.54939, 14.91819)` | Not a new aim-point test |

Three treatments suffice: the Boron case also covers nonzero connection
translation and the contained eligible parented extra. The two referenced
socket sources have identity placement, so the Terran treatment discriminates
that shared path. No part-offset treatment is warranted because the eligible
offsets are identity. No #168 zero-box retest is included.

Distinguish **the inferred collision-filtered socket boxes** from **an
unrecovered runtime contribution/override that expands or shifts them**.
An all-parts control would raise upper Y to `6.94910027`, `4.305368`, and
`6.94910027`, respectively; those are competing diagnostics, not corrections.
The three inferred upper faces exclude their authored aim points by
`2.385892`, `0.4013534`, and `2.385892 m`.

PASS requires the matching scenario spawn acknowledgement, all four raw
`[X4GC TEST ISSUE169 MACROBBOX]` lines, the COMPLETE marker, `.exists=true`,
and all six C/H coordinates within `0.001 m` of their predictions. That
resolution is far tighter than the smallest relevant discrepancy. A mismatch
is evidence to investigate the particular generic source structure; missing
records or a failed control are inconclusive, not a reconstruction correction.
This probe does not independently remeasure aim selection or promotion of
all 76 macros to `live-tested`; it tests three structural representatives.

Operator: use the existing disposable Ray save, seated at a gunnery console
on the ship named `Ray`, with two operational turrets in `Front Upper Left`.
Open **Gunnery Control → Test Lab** from the console's bottom action row.
Confirm `issue-169-outside-box-r1`, click **Create test scenario** once, wait
for completion and another 10 seconds, then stop and upload the debug log.
Do not teleport, select the probe, or fire. Leave the default **Attack any
enemy** setting (selector **Attack all enemies**); no attack order is needed.
ChatGPT will inspect the raw values and their scenario correlation.

## Sources and boundaries

Primary evidence: installed X4 9.00 build 611726 XML/catalogs; pinned native
executable; frozen trial logs; accepted earlier LIVE scope. Official
[Tags and flags](https://wiki.egosoft.com/X4%20Foundations%20Wiki/Modding%20Support/Assets%20Modding/Guides/Tags%20and%20flags/)
was rechecked 2026-09-16 (page modified 2024-06-12) for `aimtarget`, collision
flags and ALL/OTHERALL mounting. Targeted Egosoft forum/wiki searches found
no additional containment contract. No third-party/community claim supplies
the conclusion; private Discord and other unavailable channels were not used.

## Offline validation and handoff state

Focused Test Lab observation/declarative checks, official-source loadout
preflight, research-skill validation, the full `./scripts/validate.sh` suite,
and `git diff --check` passed. The fixture was installed through
`X4GC_INSTALL_TESTLAB=1 scripts/install-dev.sh`; X4 was not launched.
The committed fixture remains disabled. No permanent experiment tests were
added. No production files or frozen study scripts were changed.
