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

Each scene has explicit bodies (oriented boxes and spheres), hierarchy,
ownership, zones and presence states. Truth applies the native first-hit
classifier (target/descendant, same class-`object` container with X4's second
ray, unrelated, miss) to the scene's own closest hits, marking UNKNOWN where
aim-point uncertainty, near-coincident hits or unknown presence could change
the answer. The candidate is the accepted MD method: `check_line_of_sight`
against the target, its public `.object` and `weapon.zone` over one world
segment, plus the second ray to the component origin; guided ammunition is
clear with no query. Simplified shapes are decision-logic evidence, not a
reproduction of X4 collision meshes.

The script fails on wrong definite answers, missing or excess UNKNOWN, moved
origins or aim points, excess queries and missing coverage. Raw rows go to the
ignored `.x4-research-cache/issue186-line-of-fire/cases.jsonl.gz`; the
summary is regenerated into `findings.md`. Timing is offline Python cost, not
X4 runtime cost.
