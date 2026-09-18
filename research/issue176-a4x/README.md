# Expanded A4 turret corpus (Issue #176)

Research-only input layer for the later generalized truth scorer. The accepted
historical A4 under `research/issue176-a4/` is evidence and is not touched.

```sh
python3 research/issue176-a4x/corpus.py
```

Writes ignored `.x4-research-cache/issue176-a4x/corpus.json.gz` and fails closed
if any accepted count drifts.

Scope: 124 official X4 9.00 combat + equipable turrets (92 conventional from
`ui/turret_muzzle_geometry.lua`, 32 `missileturret`) and the 164 SWI 0.9.1 HF
combat + equipable macros, taken from the accepted ignored ware/weapon-behavior
records under `.x4-research-cache/issue176-swi-wares/` and
`.x4-research-cache/issue176-swi-combat/`. Official geometry reuses
`scripts/barrelposition_evaluator.py` unchanged; SWI geometry is read from the
ignored SWI source XML with the same repository primitives (`read_offset`,
native endpoint-name hash, ANI descriptor parser).

Each record carries a benchmark `weapon_behavior` class — `conventional_gun`,
`guided_missile`, `dumbfire_missile` or `unresolved_other` — resolved from the
referenced projectile macro's own `class` and `missile@guided`, never from a
macro name. Official: 92 / 16 / 16 / 0, cross-checked against the turret's
authored `ammunition` `guided`/`dumbfire` token. SWI: 160 / 4 / 0 / 0.

Each record is an ordered leaf-to-root op list of fixed transforms and
axis-tagged rotation joints with authored limits, plus `mechanical_class`
(`ordinary_xy`, `bounded_traverse`, `reversed_xy`, `rotation_z`, `other`) and
explicit `uncertainty` flags. SWI parts whose components declare no animation
selector use the stored XML part local; their `turret_active` ANI descriptors
never bind, so no ANI alternative is carried. The one unresolved SWI runtime
fact is not guessed: `undeclared_parent` (11) records the assumed root
attachment.

See `.agents/skills/research-x4-modding/references/swi-091-turret-geometry.md`
and `missile-turret-endpoint-geometry.md` for the accepted evidence.
