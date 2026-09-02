# Deterministic ship and turret equipment

Read this when a Test Lab fixture needs a sparse or unusual ship/turret loadout.

Use [../../../../docs/TURRET_ASSET_KINEMATICS.md](../../../../docs/TURRET_ASSET_KINEMATICS.md)
for the distinction between equipment macros, component assets, hull connections
or groups, runtime instances, endpoints, and player-visible labels. Resolve
unfamiliar X4 identities with `research-x4-modding`; do not infer them from a
display name.

Reusable deterministic equipment belongs in
`testlab/x4_gunnery_control_testlab/libraries/loadouts.xml` under a descriptive
`x4gc_testlab_*` id. `scenario_spec.lua` references that exact id directly; do
not add a Lua whitelist or an MD branch for it. Prefer group-targeted entries such
as `<turrets macro="..." group="..." exact="N"/>` unless current X4 evidence
proves a more specific path for the exact asset.

Whenever `loadout` is set, author the exact operational totals required by the
scenario contract. READY must fail if the resolved/applied ship differs. For the
player's selected group, use `setup.expectedMemberMacros` when exact member macro
identity matters in addition to the total census.

A new experiment should add another loadout-library record only when it truly
needs a new equipment set. It should not require Test Lab Lua/MD changes.
