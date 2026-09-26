# Selected-target CLEAR LINE OF FIRE benchmark (#202)

OFFLINE research. No production change and no X4 launch.

```sh
nice python3 research/issue202-line-of-fire/settled.py            # physical benchmark + #60 reconstruction, ~13 min, one process
nice python3 research/issue202-line-of-fire/settled.py --sixty    # the #60 reconstruction only, ~1 min
python3 research/issue202-line-of-fire/settled.py --report        # re-report the saved rows, under a minute
python3 research/issue202-line-of-fire/benchmark.py               # decision-rule regression tests, < 1 s
lua research/issue202-line-of-fire/runtime.lua                    # real ui/gunnery_control.lua pass behavior
```

`settled.py` needs the ignored #176 corpus (`python3 research/issue176-a4x/corpus.py`), the official
source sets, the ANI resources and the construction plans under `.x4-research-cache/`, numpy, and read
access to the installed X4 catalogs. It reads collision files straight from the `.cat`/`.dat` pairs and
writes nothing into the game or the repository. Raw rows go to the ignored
`.x4-research-cache/issue202-settled/rows.jsonl.gz` and `sixty.jsonl.gz`. The report exits non-zero if an
integrity check fails.

## Physical benchmark

- `geometry.py`: catalog reader, the MESH (`-collision.xmf`, two-sided) and HULL (`-hull.jcs`, solid
  convex) shape models, ray casts, first-hit ties and point-inside tests.
- `scenes.py`: the stratified population, every rule fixed from source metadata before scoring:
  - official A7.3 firing ships (M1, L1, L2, X1), with at most six extreme mounts each;
  - the A7.3 two-extreme turret loadout per mount, with guided turrets ranked out;
  - one extra variant for any missing turret category;
  - whole-ship targets per authored aim-point count (smallest and largest, plus median and first above
    500 m for none), their surface elements, and the Xenon mothership's four-point engine;
  - three shipped construction-plan stations with their surface elements;
  - ordinary and aim-point-switch views from #184, and one scene per external blocker class.
- `settled.py`: truth, candidates, report and integrity checks. It also runs the #202 Ray/two-Osaka
  anchor, which is reported separately, and the #60 reconstruction (below).

## #60 reconstruction

The Ray's 14 real mounts against the shipped `xen_defence` station at 96 representative poses: 24 evenly
spread bearings × 4 station yaws, with the Ray 1,500 m outside the station box. #60 logged neither the firing
ship nor the geometry, so no pose is the historical one. For each turret, under both shape models:

- the two original root probes to the union-box centre: the barrelposition with `excludeself=false`, and
  the turret component origin with `excludeself=true`;
- X4's pre-fire segment, the barrelposition to the centre with only the firing turret ignored. It
  permits on no hit or a station hit;
- the projectile path, a separate straight line along the settled barrel's +Z;
- a positive control, the barrelposition to the nearest module's box centre, under root and module
  declaration.

Turrets that cannot bear are probed from the parked barrel, and no firing path is evaluated for them.

The report gives:

- per-turret counts by primary mechanism, which is the muzzle probe's first hit: empty centre, module
  before the centre, own turret, own hull, other obstruction, or cannot bear;
- per-mount totals and per-pose classes, with their denominators.

It is geometry only: not actual firing, weapon readiness or post-launch behavior. It does not explain the
historical hits.

Every row stores its lines' endpoints and barrel direction. The report fails when the saved reconstruction
is missing, empty or incomplete. It also re-casts every stored line of every 6th pose and fails on any
difference.

## Rescue probes

The physical report also retries rows whose probe first hits the firing turret:
- `excludeself=true`;
- the ideal restart past the hit;
- an advance past `macro.boundingbox` or past the collision bounds;
- the reverse probe from the aim point, with or without an `excludeself=true` guard;
- step and look back: from a point stepped along the muzzle-to-aim-point line, forward to the aim point
  and back to the muzzle.

Each is scored against the same truth for both models and both phases (see findings, "Rescue probes").
The established tables do not change.

## Decision-rule regression tests (`benchmark.py`)

Hand-stated first-hit arrangements for blockers, membership, points, weapon classes and uncertainty. They
check the decision rules, the production drift signature and the mutants. They are not X4 physics and are
outside the physical accuracy totals.

`runtime.lua` runs the real selected-target pass code through `tests/support/runtime_fixture.lua`: `CODE`
rows check existing behavior, `SPEC` rows #202 task 3 display targets, `NOTE` rows observations that are
not failures.

See [findings.md](findings.md).
