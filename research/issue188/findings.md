# Issue #188 E8: ENGAGEABLE pipeline benchmark

`python3 research/issue188/benchmark.py` passed: **4553 generated cases** and 13 named cases; reference and ordered ENGAGEABLE answers agree throughout.

The full two-aim-point sweep covers both target authorization states, both range states, 15 per-point upstream result patterns (including zero origins), and all clear/blocked/UNKNOWN origin orderings through two origins for each supported weapon class. Four two-turret range masks and abstract normal-path query costs 0–3 are also covered. The four supported classes are conventional, guided missile, ordinary unguided missile, and distributing cluster missile. Unknown or ambiguous turret type and loaded-ammunition guidance remain LINE OF FIRE UNKNOWN. Guided missiles are clear with zero queries. Exact bbox distance equal to max fire range passes; greater distance fails.

UNKNOWN is recorded only for evaluated uncertain checks; deliberately skipped checks and later work remain NOT_EVALUATED. The consistency trap stays not ENGAGEABLE. CAN AIM with zero origins fails safely.

## Named-case work avoided versus full reference

Columns count range checks, shared searches, aim points, firing origins, LINE OF FIRE pairs, and individual queries, respectively.

| Case | ENGAGEABLE | Range | Search | Aim | Origins | Pairs | Queries |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| FIRE NOT AUTHORIZED | no | 0 | 0 | 0 | 0 | 0 | 0 |
| all OUT OF RANGE | no | 0 | 0 | 0 | 0 | 0 | 0 |
| exact range boundary | yes | 0 | 0 | 0 | 0 | 0 | 0 |
| first origin clear | yes | 0 | 0 | 0 | 1 | 1 | 1 |
| later origin clear | yes | 0 | 0 | 0 | 0 | 0 | 0 |
| all origins blocked | no | 0 | 0 | 0 | 0 | 0 | 0 |
| blocked plus UNKNOWN | no | 0 | 0 | 0 | 0 | 0 | 0 |
| early aim point ENGAGEABLE | yes | 0 | 0 | 1 | 1 | 1 | 1 |
| failed aim point before success | yes | 0 | 0 | 0 | 0 | 0 | 0 |
| aim-point consistency trap | no | 0 | 0 | 0 | 0 | 0 | 0 |
| CAN AIM without origin | no | 0 | 0 | 0 | 0 | 0 | 0 |
| guided missile zero queries | yes | 0 | 0 | 0 | 0 | 0 | 0 |
| unknown weapon classification | no | 0 | 0 | 0 | 0 | 0 | 0 |

Maximum measured ordered work in one two-surviving-turret calculation: range_checks=2, search=1, aim_points=4, origins=8, pairs=8, queries=24. The aim-point search is shared and counted once. When no result is decisive early, every remaining aim point and firing origin may need evaluation. These are abstract work counts, not gameplay-average savings.
