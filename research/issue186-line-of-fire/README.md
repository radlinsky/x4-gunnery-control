# LINE OF FIRE benchmark (Issue #186 L6)

Research-only. Asks one question per supplied firing-origin + aim-point pair:
**clear**, **LINE OF FIRE BLOCKED** or **UNKNOWN**, using the accepted L2-L4
rules. Production adoption is #189.

```sh
python3 research/issue176-a4x/corpus.py   # if the #176 corpus cache is missing
python3 research/issue186-line-of-fire/benchmark.py
```

Inputs are reused, not rebuilt: #184 `targets()` and the A4.4 census caches
(official and SWI-applied, kept separate) supply real targets, runtime boxes,
authored aim points and host attachment frames; the frozen #184 A7.3 search
recovers each target view's point once; #185's C2 row builder supplies every
firing origin from that same recovered centre.

Each scene has synthetic hit shapes (oriented boxes and spheres), hierarchy,
ownership, zones and known body-presence states. Truth applies the native
first-hit classifier (target/descendant, same class-`object` container with
X4's second ray, unrelated, miss) to the constructed closest hits. The
candidate is the accepted MD method: `check_line_of_sight`
against the target, its public `.object` and `weapon.zone` over one world
segment, plus the second ray to the component origin; guided ammunition is
clear with no query. Runtime boxes stand in for whole-ship hit shapes; artificial
host-part spheres exercise surface branches; the two-module station has invented
offsets. These fixtures test decision rules and the #184/#185 handoff. They do
not reproduce X4 collision geometry or prove a hit arrangement physically
attainable. The `off-box-uncertainty` construction remains an unresolved research
example, excluded from correctness scoring.

The script fails on wrong definite answers, missing or excess UNKNOWN, moved
origins or aim points, excess queries and missing coverage. Raw rows go to the
ignored `.x4-research-cache/issue186-line-of-fire/cases.jsonl.gz`; the
summary is regenerated into `findings.md`. Timing is offline Python cost, not
X4 runtime cost.
