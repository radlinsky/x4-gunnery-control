---
name: research-x4-modding
description: Research X4 Foundations modding APIs, capabilities, and feasibility; interpret unpacked Lua, Mission Director, AI, and XSD files; and maintain this repository's source-backed X4 evidence knowledge base. Use for X4 modding research requests, explicit $research-x4-modding invocation, or requests to record or update verified X4 findings.
---

# Research X4 Modding

Use evidence before recommendation. Treat the installed X4 build as the truth
for runtime details and the knowledge base as a dated index, not a substitute
for it.

## Write boundary

- On explicit `$research-x4-modding` invocation or an explicit request to
  record/update findings, update only durable, verified claims in
  `references/`.
- On implicit use to answer a question, do not mutate the repository. Return
  proposed findings with classification, source, version, and live-test need.
- Keep user observations experimental until reproduced. Never upgrade them to
  a durable claim from a report alone.
- For an active live-test workstream, keep hypotheses, planned discriminators,
  failed-fixture diagnoses, and provisional conclusions in the issue/log until
  the decisive run has completed. Do not pre-write a durable KB conclusion and
  then try to make the run fit it. After the run, inspect the correlated engine
  log yourself and record only what its accepted controls actually establish.
- Never copy unpacked game files, third-party extension files, catalogs, or
  data files into tracked repository paths. Use the ignored
  `.x4-research-cache/` or an explicit external temporary directory.

## Evidence workflow

1. Read [references/index.md](references/index.md), then search the knowledge
   base before investigating a duplicate question.
2. Compare each relevant record's X4 version, UI Extensions version when
   applicable, source path/URL, classification, and live-test date with the
   current request. Mark mismatches stale; do not silently reuse them.
3. Inspect this project for the existing integration and its tests.
4. Inspect current unpacked game Lua/MD/AI/XSD sources. Use the discovery and
   search helpers under this skill's `scripts/` directory; use the schema cache
   helper only with an explicit cache directory.
5. Inspect installed extension sources after vanilla sources. Treat them as
   third-party techniques, not proof of public support.
6. Consult official Egosoft documentation next. Use community discussion only
   for leads, then verify it against one of the earlier sources.
   Follow [references/source-registry.md](references/source-registry.md) so the
   official wiki, Egosoft forums, upstream mod sources, Nexus/Workshop, and
   unavailable community channels are covered and disclosed consistently.
7. Classify every conclusion as exactly one of:
   `documented-public`, `shipped-source`, `third-party-technique`, `inference`,
   or `live-tested`.
8. Answer the question with the evidence, limitations, and the smallest safe
   implementation or test recommendation. Update the KB only when authorized.

Use this record shape for new durable claims:

```text
### Claim title
- X4: 9.00
- Status: shipped-source
- Source: `catalog/relative/path` or official URL
- Live test: no — untested as of 2026-08-03
- Finding: paraphrase only; do not copy proprietary source.
```

Use `experimental` in the finding text for unreproduced user observations; do
not give it a higher classification.

## Read the focused reference

- Read [../../../docs/TURRET_ASSET_KINEMATICS.md](../../../docs/TURRET_ASSET_KINEMATICS.md)
  before tracing turret assets, mounts, runtime instances, ANI descriptors, or
  muzzle endpoints; it is the canonical identity vocabulary.
- Read [references/source-policy.md](references/source-policy.md) for source
  order, classification, and KB update criteria.
- Read [references/source-registry.md](references/source-registry.md) for every
  external-source investigation or source-coverage audit.
- Read [references/ui-lua-menu-camera.md](references/ui-lua-menu-camera.md)
  for UI FFI, menus, camera, input-frame, target, and surface findings.
- Read [references/md-ai.md](references/md-ai.md) for MD/XSD lookup and AI
  semantics.
- Read [references/tooling.md](references/tooling.md) before using XRCatTool.
- Read [references/debug-logging.md](references/debug-logging.md) for X4
  `-logfile` argument form, log location, and missing-log diagnosis.
- Read [references/testing-experiments.md](references/testing-experiments.md)
  for live-test design and evidence promotion.

## Use the helpers safely

Resolve `SKILL_DIR` to the directory containing this `SKILL.md`; from this
repository's root, `SKILL_DIR=.agents/skills/research-x4-modding`. Do not assume
the current working directory is the skill directory. Invoke every helper as
`"$SKILL_DIR/scripts/<helper>"`.

- Run `"$SKILL_DIR/scripts/discover-x4-roots.sh" --help` before relying on
  default paths.
  Prefer `X4GC_X4_ROOT` and `X4GC_EXTRACTED_ROOT` or explicit options; do not
  use a home-directory variable as a target.
- Run `"$SKILL_DIR/scripts/search-x4.sh" --help`. Search with
  `"$SKILL_DIR/scripts/search-x4.sh" --dry-run -- PATTERN`; the `--` before the
  pattern is mandatory. It searches the KB/project and discovered or selected
  extracted/extension roots with `rg`; `--dry-run` prints scope only. Pass
  `--x4-root` when the install is outside the discovered locations.
- Run `"$SKILL_DIR/scripts/index-lua-ffi.sh" --source PATH` to emit FFI
  declarations to stdout. Use `--output FILE` only for an explicit new file;
  it refuses to overwrite it.
- Run `"$SKILL_DIR/scripts/prepare-xsd-cache.sh" --source EXTRACTED
  --cache-root .x4-research-cache` only after selecting an explicit ignored
  cache root. It copies the recursive `md/md.xsd` include/import tree from an
  already extracted source and refuses an existing destination.
- Run `"$SKILL_DIR/scripts/extract-selected-xrcat.sh" --help` before
  extraction. Supply an explicit executable or the verified v1.11 ZIP plus
  explicit tool cache, existing `.cat` inputs, a new non-X4 output directory,
  and include regexes. The helper verifies the recorded v1.11 ZIP SHA-256 and
  the extracted cache on every reuse; use `--expected-sha256` only with an
  independently verified mirror or a controlled test fixture.
  Inside this repository, output and tool caches must stay under the ignored
  `.x4-research-cache/`; external temporary directories are also allowed.
  Use `--dry-run` first; it prints the escaped command. Never add `-append` or
  `-diff`, use a catalog as output, or point output at an X4 installation.

## Verify before handoff

Run `python3 /home/pc/.codex/skills/.system/skill-creator/scripts/quick_validate.py
.agents/skills/research-x4-modding` and `tests/test_research_x4_skill.sh` after
skill changes. Do not install, package, deploy, or commit as part of research
unless separately asked.
