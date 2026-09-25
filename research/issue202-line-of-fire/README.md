# Selected-target CLEAR LINE OF FIRE benchmark (#202)

OFFLINE research. No production change and no X4 launch.

```sh
python3 research/issue202-line-of-fire/settled.py            # physical benchmark, ~6 min, one process (run under nice)
python3 research/issue202-line-of-fire/settled.py --report   # re-report the saved rows, ~1 min
python3 research/issue202-line-of-fire/benchmark.py          # decision-rule regression tests, < 1 s (--population: #184 inputs)
lua research/issue202-line-of-fire/runtime.lua               # real ui/gunnery_control.lua pass behavior
```

`settled.py` needs the ignored #176 corpus (`python3 research/issue176-a4x/corpus.py`), the
official source sets and ANI resources under `.x4-research-cache/`, numpy, and read access to the
installed X4 catalogs (it reads collision files straight from the `.cat`/`.dat` pairs and writes
nothing into the game or the repository). Raw rows go to the ignored
`.x4-research-cache/issue202-settled/rows.jsonl.gz`.

## Physical benchmark (`settled.py`, `geometry.py`)

The source of truth is the straight path from a turret's **settled `barrelposition`** to the **X4
aim point it bears toward**, after turning toward the selected target. The tested lines of the
current and seven-point methods, and the first `useaimtarget` probe on its own, are predictions.

- **Scene**: the #202 LIVE ships. The Boron Ray with its 14 real mounts (12 M railguns, 2 L
  disruptors) fires at an Osaka carrying a stated Terran loadout, with the second Osaka as the
  shared obstacle, in three arrangements × four Osaka yaws.
- **Geometry**: every layer-3 part's `-collision.xmf` triangle mesh (MESH) and its Jolt
  `-hull.jcs` convex pieces (HULL). X4 loads both; which one the ray query uses is untraced, so
  truth requires both to agree.
- **Bearing and settling**: the accepted #176 scorer decides CAN BEAR. The #166 yaw gate plus the
  starting yaw (parked at 0, or at rest astern) decides which rest the turret reaches. Traps, a
  settled rest out of arc and scorer UNKNOWN are excluded as UNKNOWN.
- **Truth**: the segment from the settled `barrelposition` to that aim point, ignoring only the
  firing turret's own meshes. Its first hit is scored with the #202 membership rules; a segment
  with no hit is UNKNOWN. Each barrel's settled +Z projectile path is a separate diagnostic only.
- **Candidates**: `benchmark.candidate()` fed with the physical first hit of each tested segment,
  from the pre-turn muzzle and from the settled muzzle.

## Decision-rule regression tests (`benchmark.py`)

Hand-stated first-hit arrangements for blockers, membership, points, weapon classes and
uncertainty. They check the decision rules, the production drift signature and the mutants. They
are not X4 physics and are outside the physical accuracy totals.

`runtime.lua` runs the real selected-target pass code through `tests/support/runtime_fixture.lua`:
`CODE` rows check existing behavior, `SPEC` rows #202 task 3 display targets, `NOTE` rows
observations that are not failures.

See [findings.md](findings.md).
