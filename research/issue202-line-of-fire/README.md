# Selected-target CLEAR LINE OF FIRE benchmark (#202)

OFFLINE research. No production change and no X4 launch.

```sh
python3 research/issue202-line-of-fire/benchmark.py                # < 1 s, stdlib only
python3 research/issue202-line-of-fire/benchmark.py --population   # + #184 aim points and endpoint layouts (~20 s, needs the ignored cache and numpy)
lua research/issue202-line-of-fire/runtime.lua                     # real ui/gunnery_control.lua pass behavior
```

`benchmark.py` does not model collision geometry. Each scene states the
ordered first hits along each tested line (`|` marks the tested endpoint) and
the evidence level for that arrangement. **Truth** applies the #202 membership
rules to those hits directly. **Candidates** issue simulated
`check_line_of_sight` calls:

- `current`: a model of the `LineOfFireTurret` cue at the checked-out head.
  `production_signature()` compares the cue's rays, blocker, module cap,
  reasons and statuses with the model and fails on drift. It does not verify
  the branch order.
- `seven`: the proposed surface scan. It runs the `useaimtarget` probe, then
  the six #69 points, classifying each failed box point as it goes.
- `lazy`: the same scan, but it classifies failed points only after all seven
  miss.
- `root_zone` and `root_ship`: station hull checks declared on the station
  root, with the zone or the firing ship as blocker.
- `legacy`: the #60 root `useaimtarget` probe.

The script also checks:

- that deliberately broken candidates (`MUTANTS`) fail;
- that the hand-written `expect` statements hold;
- that `lazy` never changes a status.

It exits non-zero only on a benchmark-integrity failure. Candidate defects
measured against the #202 rules are printed as `FAIL` rows.

`runtime.lua` runs the real selected-target pass code through
`tests/support/runtime_fixture.lua`:

- `CODE` rows check existing behavior;
- `SPEC` rows check #202 task 3 display targets;
- `NOTE` rows record observations that are not failures.

See [findings.md](findings.md).
