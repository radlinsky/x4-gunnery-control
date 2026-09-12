# Turret-to-ship mount compatibility

Use this rule for exact equipment-macro-to-ship-macro compatibility. It is a
connection-tag decision, not a race/name/size heuristic or a pair inventory.

### Ship-upgrade compatibility uses subset tag matching

- X4: current public X4 modding documentation, checked 2026-09-12
- Status: documented-public
- Source: [X Community Wiki — Tags and flags](https://wiki.egosoft.com/X4%20Foundations%20Wiki/Modding%20Support/Assets%20Modding/Guides/Tags%20and%20flags/), sections `component` and `Tag compatibility modes`
- Live test: no — static asset compatibility rule
- Finding: the child asset's single connection tagged `component` is its mating connection; the other tags on that connection define compatibility. Ship upgrades use `OTHERALL` from the slot side, equivalently `ALL` from the upgrade side: every compatibility tag required by the upgrade must exist on the ship slot, while the ship slot may have additional tags.

The same documentation identifies `turret` as a turret compatibility tag and
`hittable` / `unhittable` as opposing surface-element compatibility tags. Do
not reduce the rule to size or turret type; all authored compatibility tags on
the mating connection matter.

### Exact source identities provide the two tag sets

- X4: 9.00
- Status: shipped-source
- Source: `assets/props/WeaponSystems/energy/macros/turret_par_l_beam_01_mk1_macro.xml`; `assets/props/WeaponSystems/energy/turret_par_l_beam_01_mk1.xml`; `assets/units/size_l/macros/ship_par_l_destroyer_02_a_macro.xml`; `assets/units/size_l/ship_par_l_destroyer_02.xml`; `ego_dlc_timelines/libraries/loadouts.xml`; existing source collector `scripts/census_identity.py`
- Live test: no — offline source verification only
- Finding: an exact turret equipment macro directly identifies its exact component; the turret component has a distinct mating connection; an exact ship macro directly identifies its ship component; and ship-component connections carry exact tag sets plus optional group identities. The current official loadout for the representative Paranid L destroyer independently confirms the exact macro can mount at the source-resolved hull group. `scripts/census_identity.py` already collects equipment macro-to-component identity and exact authored component-connection tag tokens from the current official source sets.

Connection count, not group count, is the mount-count unit. Several turret
connections can share one group, and non-turret connections can reuse the same
raw group value. Preserve each compatible connection name and, when present,
its whitespace-normalized group key.

### Repository compatibility decision

- X4: 9.00
- Status: inference
- Source: documented ship-upgrade tag matching plus the X4 9.00 source identity chain above
- Live test: no — the rule selects source-compatible mounts; actual installation/runtime behavior is a separate live question
- Finding: resolve the exact turret macro and its unique component, then its unique `component`-tagged mating connection. Required tags are every tag on that connection except the structural `component` tag. Resolve the exact ship macro and ship component. A ship connection is compatible exactly when it contains every required tag; additional ship-connection tags are allowed. Compatible mount count is the number of distinct matching ship connections. Return unresolved rather than guessing when macro/component identity, the unique mating connection, source definitions, or tag data are missing, duplicated, conflicting, or otherwise ambiguous.

This also explains the failure class without an exception: an embedded medium
turret requiring `advanced` and `unhittable` does not fit a capital-ship slot
authored as `standard` and `hittable`, even when that slot has a valid turret
group id. A compatible variant is not evidence for a different exact macro.
