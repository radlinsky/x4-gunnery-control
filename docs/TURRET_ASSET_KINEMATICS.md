# Turret asset and kinematics identities

The canonical vocabulary for tracing an X4 turret from authored source to a mounted weapon in a running game. This document defines identity layers; it does not provide the complete vanilla census or establish transform semantics.

## Terms used here

These names mean one specific thing throughout this project.

- **Turret component asset** — the named `<component class="turret">` source asset that describes one reusable turret assembly. It is an asset identity, not an installed weapon and not an equipment macro.
- **Equipment macro** — a named `<macro class="turret">` or `<macro class="missileturret">` equipment definition. Its `<component ref="…">` selects a turret component asset. A macro also carries gameplay properties such as weapon, rotation speed, durability, and localization references. Macro identity and component identity are independent even when their strings look related.
- **Geometry source** — the resource reference in a component's `<source geometry="…">`. It selects the authored geometry-data resource family used by that component. It is not the component name, an ANI descriptor, or a geometry-part name.
- **ANI file** — the binary animation-data resource associated with an authored geometry source. It contains animation records, but the existence of a record does not by itself establish the record's transform meaning or composition order.
- **ANI descriptor `(part, subname)`** — the two-field identity of one ANI record: the authored part identity and the animation subname for that part. Both fields are required. A part name alone, or a subname alone, is not a descriptor.
- **Geometry part** — a named `<part>` in the component's authored geometry hierarchy. A geometry part can be named by ANI data or used as a connection parent, but neither relationship may be assumed from spelling alone.
- **Component connection** — a named `<connection>` in a component. It can carry an offset, tags, restrictions, parts, and a parent-part reference. A connection is an authored hierarchy node; it is not automatically an articulated joint or a muzzle endpoint.
- **Articulated joint** — a source-resolved kinematic relationship that gives a descendant path a mechanical degree of freedom about an established pivot/axis. A restriction-looking connection is only a candidate until the required transform semantics are proved. A1 establishes no ANI transform, axis-sign, frame, order, or active-pose semantics.
- **Hull turret group** — the internal group key used to address a set of turret-compatible connections on a hull or module asset. The underlying hull `group` attribute can also be shared by non-turret connections, such as shields, and authored values can contain padding whitespace. Preserve the raw attribute as source evidence, but use the context-appropriate normalized key when matching loadout/runtime groups. A hull turret group is not a turret asset, a single slot, or a player-visible label.
- **Runtime turret instance** — one mounted turret object in a running game, occupying an exact compatible hull/module connection and equipped from an equipment macro. Multiple runtime instances may share a macro and component asset. Runtime object/component handles identify instances; source names and group names do not.
- **Muzzle endpoint** — one source-resolved firing endpoint at the end of a turret's geometry/connection path. A turret may have more than one. A source endpoint connection, a runtime `barrelposition` observation, and a visible barrel mesh are related evidence, not interchangeable identities.

## Identity chain

The chain crosses source definitions, a mounting site, and runtime objects. Each arrow means “references, contains, mounts, or instantiates”; it never means that the next name can be generated from the previous name.

```text
SOURCE DEFINITIONS
 equipment macro --component ref--> turret component asset
                                      |--source geometry--> geometry source
                                      |                     `--> ANI file
                                      |                          `--> ANI descriptor (part, subname)
                                      |--contains----------> geometry part(s)
                                      `--contains----------> component connection hierarchy
                                                                |--candidate/resolved joint(s)
                                                                `--muzzle endpoint(s)

MOUNTING DEFINITIONS                         RUNTIME
 hull/module component connection --group--> hull turret group
             `--mounts equipment macro-----> runtime turret instance
                                                  `--has runtime muzzle pose(s)
```

| Layer | Identity class | Canonical identity | Do not substitute |
|---|---|---|---|
| Equipment macro | Source identity | exact macro `name` | component name, localization text |
| Turret component asset | Source identity | exact component `name` referenced by the macro | macro name |
| Geometry source | Source identity | exact `<source geometry>` value in that component | guessed path from component spelling |
| ANI file | Source identity | exact catalog-relative resource path | geometry-source string with a guessed suffix |
| ANI descriptor | Source identity | exact `(part, subname)` pair | either field by itself |
| Geometry part | Source identity | exact `<part name>` within its component | connection name |
| Component connection | Source identity | exact `<connection name>` in its owning component | part name, runtime instance |
| Articulated joint | Derived source model identity | resolved parent/child path plus proved pivot/axis semantics | every connection carrying a restriction |
| Hull turret group | Source identity | owning hull/module plus normalized internal group key and its turret-compatible connection members | raw padded attribute, one connection, visible group label |
| Runtime turret instance | Runtime identity | engine runtime object/component identity at an exact mount | macro, component, group, or list position |
| Muzzle endpoint | Source identity when authored; runtime identity when observed | exact resolved source path and endpoint, or exact instance/endpoint observation | generic “the barrel” |
| Player-facing turret or group name | Descriptive/display label | resolved localization/UI text in the current language and context | any internal source or runtime identity |

**Identity rule:** always read an explicit reference or enumerate an exact owning scope. Do not imply that macro, component, file, part, connection, group, runtime, or display names can be derived from each other. Similar strings are corroboration at most. Missing, orphaned, or ambiguous links fail closed.

## X4 9.00 illustrative example

This example was rechecked directly against the currently installed base-game 01–09 catalogs and the installed official extension catalogs named in Issue #72. It illustrates the vocabulary only; it is not a census and says nothing about other turret assets.

The current source chain for the exact Paranid L Beam internal macro is:

```text
turret_par_l_beam_01_mk1_macro
  --component ref--> turret_par_l_beam_01_mk1
  --source geometry--> assets\props\WeaponSystems\energy\turret_par_l_beam_01_mk1_data

catalog enumeration (not a derived filename)
  --> assets/props/WeaponSystems/energy/TURRET_PAR_L_BEAM_01_MK1_DATA.ANI
```

The component contains geometry parts including `part_rotator`, `anim_gun`, and `anim_barrel`; component connections `Connection03`, `Connection04`, and `Connection05` parent portions of that hierarchy. It also contains two laser-tagged endpoint connections, `con_laser_01` and `con_laser_02`, parented to `anim_barrel`, plus the separate turret-side mating connection `con_turret_beam_l`. These facts establish distinct authored identities and hierarchy links only. They do **not** prove prospective muzzle transforms, ANI transform order, axis sign, pivot interpretation, or which runtime endpoint an engine observation reports. ANI descriptors still require their exact `(part, subname)` pairs; matching strings in the component and binary are not enough to assert a descriptor or its semantics.

On `ship_par_l_destroyer_02`, the raw hull connection `con_turret_laser_l_01` has `group="group_front_up_mid2  "`, including padding. The same raw group value is also used by shield connections. A current shipped official loadout for `ship_par_l_destroyer_02_a_macro` addresses normalized key `group_front_up_mid2` and assigns `turret_par_l_beam_01_mk1_macro` to it. Thus the owning hull, hull connection, normalized group key, group membership subset, equipment macro, component asset, and a mounted runtime copy are all different identities.

The beam macro's name localization is `{20105,5494}`. Current English X4 9.00 text resolves it to **PAR L Mass Driver Turret Mk1**. In this document, “Paranid L Beam” identifies the internal `turret_par_l_beam_01_mk1_macro`; it is not asserted as that equipment's current display label. A descriptive phrase or resolved display text cannot replace the exact macro identity.

### Evidence record

- X4: 9.00
- Status: shipped-source
- Source: `assets/props/WeaponSystems/energy/macros/turret_par_l_beam_01_mk1_macro.xml`; `assets/props/WeaponSystems/energy/turret_par_l_beam_01_mk1.xml`; `assets/props/WeaponSystems/energy/TURRET_PAR_L_BEAM_01_MK1_DATA.ANI`; `assets/units/size_l/macros/ship_par_l_destroyer_02_a_macro.xml`; `assets/units/size_l/ship_par_l_destroyer_02.xml`; `ego_dlc_timelines/libraries/loadouts.xml`; `t/0001-l044.xml`
- Live test: no — offline source verification only
- Finding: the named macro explicitly references the named component; that component explicitly names its geometry source and authored hierarchy/endpoints; catalog enumeration confirms the separate ANI resource; the hull and loadout explicitly provide separate raw connection, normalized group, and equipment identities. The ANI binary was checked for this current resource, but its descriptors and transform semantics remain unproven.

## Evidence and fail-closed boundaries

Use the `$research-x4-modding` source order and evidence classifications for every concrete X4 claim. For later Issue #72 work:

1. Start from exact equipment macro definitions and follow explicit references. Do not start from remembered component names or a historical count.
2. Preserve one-to-many and many-to-one relationships. Different equipment macros may reference one component asset, and one group may contain multiple mount connections.
3. Scope part and connection names to their owning component. Scope runtime observations to the exact runtime instance and endpoint when the API exposes that distinction.
4. Keep descriptive/display labels outside identity joins. They may vary by language, context, or UI formatting.
5. Treat ANI position, rotation, scale, interpolation, timing, frame, axis, sign, pivot, and transform-order semantics as **unknown** until the later source and independent corroboration work proves each required semantic.
6. Do not call a candidate connection an articulated joint, or an endpoint a prospective muzzle pose, merely because its tags, restriction, parent, or spelling look plausible.
7. Do not generalize conventional-turret kinematics to missile turrets. Both classes belong in later identity accounting, but eligibility and behavior are separate questions.

A1 deliberately does not establish ANI transform/order semantics, enumerate the complete official turret corpus, reproduce a historical asset count, build an extractor, or change production behavior.
