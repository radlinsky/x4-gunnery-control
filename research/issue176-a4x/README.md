# Expanded A4 turret corpus and ENGAGEABLE benchmark (Issue #176)

Research-only corpus, generalized mechanical truth scorer, and separate expanded
A4 benchmark. The accepted historical A4 under `research/issue176-a4/` remains
unchanged evidence.

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
never bind, so no ANI alternative is carried. Connections naming an
undeclared parent part attach to the component root, as the X4 loader does.
The former missing-selector ANI and undeclared-parent uncertainties therefore
do not require UNKNOWN in this corpus; narrower SWI caveats remain recorded in
the research reference below.

See `.agents/skills/research-x4-modding/references/swi-091-turret-geometry.md`
and `missile-turret-endpoint-geometry.md` for the accepted evidence.

## Truth scorer

```sh
python3 research/issue176-a4x/corpus.py
python3 research/issue176-a4x/validate.py   # ~4 min, one niced process
```

`scorer.score(record, point)` gives mechanical bearing/arc truth for a target in
the turret component frame: `IN_ARC`, `OUT_OF_ARC` or `UNKNOWN_*`. It reads the
record's ordered `ops` path. It does not check range, line of sight, own-hull
masking, projectile flight, guidance or readiness. `weapon_behavior` is not used.

- `ordinary_xy` (278): the accepted #173 `study.geometry()` on segments split
  from the ops. That keeps component zeroing, the 4-dp limit rule, any-rest
  scoring and trap/no-rest `UNKNOWN`. The split is bit-identical to the
  accepted 92-turret pickle and to `joint_segments` for all 124 official
  turrets.
- `bounded_traverse` (8) and `reversed_xy` (1): both pivots are fixed, which is
  asserted. The root joint is solved by its authored axis and clamped to the
  nearer limit, then the leaf is solved in the clamped frame. `IN_ARC` means
  neither joint clamps. A 180° root span with the request exactly on a limit is
  `UNKNOWN_root_limit_unwrap`, because a mover parked at the other limit is π
  away.
- `rotation_z` (1, arrestor dish): resolves the actual root-Z resting clocks
  with the accepted yaw gate, then scores leaf pitch at every resting clock.
  Trap or no-rest outcomes remain UNKNOWN; any in-arc resting clock suffices.

## Expanded benchmark

`compare.py` imports the historical A4 scenarios and prediction methods rather
than changing them. It evaluates `baseline`, `direction`, `same_ray`,
`three_ray`, and `three_ray4`, plus the historical fallback stacks in
`report.py`, at rough-distance factors 0.5, 1, and 2.

Sampling is deterministic over the sorted `source:macro` corpus keys:

- each of single-point, multi-point, and boundary independently assigns its
  scenarios round-robin over all 288 turrets and cycles the 24 accepted
  component rotations;
- all 74 known172 scenarios run against all 288 turrets;
- all 11 retained synthetic scenarios, including `collinear_replacement`, run
  against all 288 turrets.

This gives 37,830 turret/scenario cases and 113,490 factor rows. Query
observations are computed once per scenario/factor and reused for the assigned
turrets. For truth scoring, the selected endpoint's ordered A4x transforms and
nearest-to-zero legal joint angles define a reference pose. The component is
placed so that endpoint lands at the query/prospective-muzzle origin O.

Run a small structural pilot before the full benchmark:

```sh
python3 research/issue176-a4x/compare.py --pilot
python3 research/issue176-a4x/check.py --pilot
python3 research/issue176-a4x/compare.py
python3 research/issue176-a4x/report.py
python3 research/issue176-a4x/check.py
```

Raw rows, the pilot, and machine-readable metrics are ignored under
`.x4-research-cache/issue176-a4x/`. Stable results are written to
`findings.md`. The benchmark is mechanical bearing/arc evidence only. The
selected endpoint/reference pose is its offline coordinate definition and is
not new live proof of emitted-muzzle runtime behavior.
