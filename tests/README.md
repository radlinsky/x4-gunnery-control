# Permanent test policy

Everything under `tests/` is part of the permanent release gate:
`scripts/validate.sh` executes every matching `tests/*.lua`, `tests/*.sh`, and
`tests/*.py`. A file placed here therefore becomes behavior the repository is
committing to maintain.

## What belongs here

Keep tests for stable behavior such as:

- production regressions that could affect players;
- reusable Test Lab validation, transport, safety, selection, observation, and
  lifecycle behavior;
- repository, packaging, release, and developer-tool contracts;
- small synthetic edge cases that exercise real implementation paths.

A useful regression test should be explainable as: **if this realistic bug
returns, this test fails.** Prefer the smallest behavioral test that proves that
statement.

## What does not belong here

Do not turn temporary experiment setup into a permanent CI contract. In
particular, avoid tests whose only purpose is preserving:

- a live scenario id or player-visible label;
- coordinates, rotations, distances, or target placement chosen for one run;
- field-for-field copies of a historical `scenario_spec.lua`;
- old operator click sequences or settled live measurements;
- implementation details already covered by a stronger behavior-level test.

`testlab/x4_gunnery_control_testlab/ui/scenario_spec.lua` is mutable live-test
input. A normal fixture change should require **no unit-test edit**. The Test
Lab validator and transport should be tested with small synthetic specs; the
actual live fixture is reviewed as part of preparing that live run and then
proved or rejected by X4 evidence.

When a live experiment settles a question, record the durable result in the
owning GitHub issue and, when it is reusable X4 knowledge, in
`.agents/skills/research-x4-modding/references/`. The historical fixture does
not become a permanent CI contract by default.

Before updating a brittle historical test, ask what current regression it
prevents. If there is no continuing contract, delete the test instead of
teaching it about the next experiment.
