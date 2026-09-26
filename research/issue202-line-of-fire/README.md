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
ship nor the geometry, so no pose is the historical one. Per turret it compares:

- the two original root probes: settled muzzle with `excludeself=false`, and turret component origin with
  `excludeself=true`; turrets that cannot bear are probed from the parked barrel;
- X4's first ray, which ignores only the firing turret and fires on a station hit or on no hit;
- the aimed round, the same line continued past the union-box centre (no spread, lead or slew);
- a positive control, the settled muzzle to the nearest module's box centre, under root and module
  declaration.

It reports which poses reproduce "both probes 0/14 while X4 fires", and whether any aimed round then hits.
It shows what the geometry allows. It does not explain the historical hits.

Truth is the straight path from the turret's **settled `barrelposition`** to the **point X4's shoot
controller bears on**:

- the nearest authored aim point from the turret component origin, else the box centre;
- plus the LargeTarget offset on a ship over 500 m with no authored point;
- the union-box centre for a station root.

The first hit is traced through real collision geometry, ignoring only the firing turret's own meshes. It
is UNKNOWN when the shape models disagree, the path hits nothing, or the first hit is a tie. Candidates
are `benchmark.candidate()` fed the physical first hit of each tested line, from the pre-turn and the
settled muzzle, plus the first `useaimtarget=true` probe alone.

## Decision-rule regression tests (`benchmark.py`)

Hand-stated first-hit arrangements for blockers, membership, points, weapon classes and uncertainty. They
check the decision rules, the production drift signature and the mutants. They are not X4 physics and are
outside the physical accuracy totals.

`runtime.lua` runs the real selected-target pass code through `tests/support/runtime_fixture.lua`: `CODE`
rows check existing behavior, `SPEC` rows #202 task 3 display targets, `NOTE` rows observations that are
not failures.

See [findings.md](findings.md).
