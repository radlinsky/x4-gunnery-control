# A4 initial diagnostic results — 2026-09-17

Status: **inference**, raw offline surrogate evidence for Issue #176 A4.
These results are undiagnosed. They do not rank or choose a model and do not
say what error rate is acceptable; A5 audits the groups listed below first.
The contract, populations and reproduction commands are in the README.

Run: 14,436 cases × 3 rough-distance factors = 43,308 rows, produced by
`compare.py` and summarized by `report.py`. Full per-row data (including
subgroup tables for single-point, multi-point, boundary and known172) is in
ignored `.x4-research-cache/issue176-a4/`.

The sampled origin O is the prospective muzzle and every query origin; the
scorer gets the turret component origin whose rest-pose muzzle is at O (see
README). This run replaces an earlier one that put the component origin at O.

How to read the tables:

- Counts are player-view: UNKNOWN is shown as NOT ENGAGEABLE and falls into TN
  or FN. `unknown_on_yes` and `unknown_on_no` give the UNKNOWN part of FN and TN.
- `decided_accuracy` covers decided rows only.
- Query columns count the whole stack for each row.
- Truth-UNKNOWN rows are excluded from TP/FP/TN/FN and from every rate.

## Headline: rough factor 1

### Normal / current-game supported (8,790 cases: 6,990 single-point, 1,800 multi-point)

| method | TP | FP | TN | FN | sensitivity | specificity | precision | accuracy | truth_unknown | model_unknown | unknown_on_yes | unknown_on_no | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| direction | 5144 | 36 | 3510 | 96 | 0.9817 | 0.9898 | 0.9931 | 0.985 | 4 | 0 | 0 | 0 | 1.0 | 0.985 | 1.0 | 1 |
| same_ray | 5183 | 1 | 3545 | 57 | 0.9891 | 0.9997 | 0.9998 | 0.9934 | 4 | 132 | 57 | 72 | 0.9853 | 0.9999 | 4.0 | 4 |
| three_ray | 5233 | 0 | 3546 | 7 | 0.9987 | 1.0 | 1.0 | 0.9992 | 4 | 16 | 7 | 5 | 0.9986 | 1.0 | 3.0 | 3 |
| three_ray4 | 5238 | 0 | 3546 | 2 | 0.9996 | 1.0 | 1.0 | 0.9998 | 4 | 7 | 2 | 1 | 0.9997 | 1.0 | 3.001 | 4 |
| three_ray > same_ray | 5240 | 0 | 3546 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 4 | 3 | 0 | 0 | 1.0 | 1.0 | 3.005 | 6 |
| three_ray4 > same_ray | 5240 | 0 | 3546 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 4 | 3 | 0 | 0 | 1.0 | 1.0 | 3.004 | 7 |
| same_ray > three_ray4 | 5240 | 1 | 3545 | 0 | 1.0 | 0.9997 | 0.9998 | 0.9999 | 4 | 3 | 0 | 0 | 1.0 | 0.9999 | 4.03 | 6 |
| three_ray4 > direction | 5240 | 0 | 3546 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 4 | 0 | 0 | 0 | 1.0 | 1.0 | 3.001 | 4 |
| same_ray > direction | 5208 | 7 | 3539 | 32 | 0.9939 | 0.998 | 0.9987 | 0.9956 | 4 | 0 | 0 | 0 | 1.0 | 0.9956 | 4.0 | 4 |
| three_ray4 > same_ray > direction | 5240 | 0 | 3546 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 4 | 0 | 0 | 0 | 1.0 | 1.0 | 3.004 | 7 |

### Difficult but supported (4,634 cases: 4,560 boundary, 74 known #172)

| method | TP | FP | TN | FN | sensitivity | specificity | precision | accuracy | truth_unknown | model_unknown | unknown_on_yes | unknown_on_no | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| direction | 2575 | 8 | 2038 | 13 | 0.995 | 0.9961 | 0.9969 | 0.9955 | 0 | 0 | 0 | 0 | 1.0 | 0.9955 | 1.0 | 1 |
| same_ray | 2563 | 1 | 2045 | 25 | 0.9903 | 0.9995 | 0.9996 | 0.9944 | 0 | 59 | 25 | 34 | 0.9873 | 0.9998 | 4.0 | 4 |
| three_ray | 1680 | 0 | 2046 | 908 | 0.6491 | 1.0 | 1.0 | 0.8041 | 0 | 1617 | 908 | 709 | 0.6511 | 1.0 | 3.0 | 3 |
| three_ray4 | 2165 | 0 | 2046 | 423 | 0.8366 | 1.0 | 1.0 | 0.9087 | 0 | 777 | 423 | 354 | 0.8323 | 1.0 | 3.349 | 4 |
| three_ray > same_ray | 2584 | 0 | 2046 | 4 | 0.9985 | 1.0 | 1.0 | 0.9991 | 0 | 21 | 4 | 17 | 0.9955 | 1.0 | 4.047 | 6 |
| three_ray4 > same_ray | 2585 | 0 | 2046 | 3 | 0.9988 | 1.0 | 1.0 | 0.9994 | 0 | 12 | 3 | 9 | 0.9974 | 1.0 | 3.852 | 7 |
| same_ray > three_ray4 | 2585 | 1 | 2045 | 3 | 0.9988 | 0.9995 | 0.9996 | 0.9991 | 0 | 12 | 3 | 9 | 0.9974 | 0.9998 | 4.03 | 7 |
| three_ray4 > direction | 2588 | 2 | 2044 | 0 | 1.0 | 0.999 | 0.9992 | 0.9996 | 0 | 0 | 0 | 0 | 1.0 | 0.9996 | 3.349 | 4 |
| same_ray > direction | 2582 | 3 | 2043 | 6 | 0.9977 | 0.9985 | 0.9988 | 0.9981 | 0 | 0 | 0 | 0 | 1.0 | 0.9981 | 4.0 | 4 |
| three_ray4 > same_ray > direction | 2588 | 0 | 2046 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 0 | 0 | 0 | 0 | 1.0 | 1.0 | 3.852 | 7 |

### Stress / possibly impossible (1,012 cases: 11 synthetic × 92 turrets)

| method | TP | FP | TN | FN | sensitivity | specificity | precision | accuracy | truth_unknown | model_unknown | unknown_on_yes | unknown_on_no | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| direction | 567 | 0 | 191 | 243 | 0.7 | 1.0 | 1.0 | 0.7572 | 11 | 92 | 91 | 0 | 0.9091 | 0.833 | 1.0 | 1 |
| same_ray | 622 | 0 | 191 | 188 | 0.7679 | 1.0 | 1.0 | 0.8122 | 11 | 288 | 188 | 89 | 0.7233 | 1.0 | 3.727 | 4 |
| three_ray | 541 | 0 | 191 | 269 | 0.6679 | 1.0 | 1.0 | 0.7313 | 11 | 377 | 269 | 97 | 0.6344 | 1.0 | 3.0 | 3 |
| three_ray4 | 632 | 0 | 191 | 178 | 0.7802 | 1.0 | 1.0 | 0.8222 | 11 | 285 | 178 | 96 | 0.7263 | 1.0 | 3.273 | 4 |
| three_ray > same_ray | 628 | 0 | 191 | 182 | 0.7753 | 1.0 | 1.0 | 0.8182 | 11 | 198 | 182 | 5 | 0.8132 | 1.0 | 3.845 | 6 |
| three_ray4 > same_ray | 719 | 0 | 191 | 91 | 0.8877 | 1.0 | 1.0 | 0.9091 | 11 | 106 | 91 | 4 | 0.9051 | 1.0 | 3.845 | 7 |
| same_ray > three_ray4 | 719 | 0 | 191 | 91 | 0.8877 | 1.0 | 1.0 | 0.9091 | 11 | 106 | 91 | 4 | 0.9051 | 1.0 | 4.392 | 7 |
| three_ray4 > direction | 672 | 0 | 191 | 138 | 0.8296 | 1.0 | 1.0 | 0.8621 | 11 | 92 | 91 | 0 | 0.9091 | 0.9484 | 3.273 | 4 |
| same_ray > direction | 719 | 0 | 191 | 91 | 0.8877 | 1.0 | 1.0 | 0.9091 | 11 | 92 | 91 | 0 | 0.9091 | 1.0 | 3.727 | 4 |
| three_ray4 > same_ray > direction | 719 | 0 | 191 | 91 | 0.8877 | 1.0 | 1.0 | 0.9091 | 11 | 92 | 91 | 0 | 0.9091 | 1.0 | 3.845 | 7 |

## Rough-distance estimate factor 0.5

### Normal

| method | TP | FP | TN | FN | sensitivity | specificity | precision | accuracy | truth_unknown | model_unknown | unknown_on_yes | unknown_on_no | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| direction | 5144 | 36 | 3510 | 96 | 0.9817 | 0.9898 | 0.9931 | 0.985 | 4 | 0 | 0 | 0 | 1.0 | 0.985 | 1.0 | 1 |
| same_ray | 5175 | 1 | 3545 | 65 | 0.9876 | 0.9997 | 0.9998 | 0.9925 | 4 | 161 | 65 | 93 | 0.982 | 0.9999 | 4.0 | 4 |
| three_ray | 5236 | 0 | 3546 | 4 | 0.9992 | 1.0 | 1.0 | 0.9995 | 4 | 12 | 4 | 4 | 0.9991 | 1.0 | 3.0 | 3 |
| three_ray4 | 5238 | 0 | 3546 | 2 | 0.9996 | 1.0 | 1.0 | 0.9998 | 4 | 7 | 2 | 1 | 0.9997 | 1.0 | 3.001 | 4 |
| three_ray > same_ray | 5240 | 0 | 3546 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 4 | 3 | 0 | 0 | 1.0 | 1.0 | 3.004 | 6 |
| three_ray4 > same_ray | 5240 | 0 | 3546 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 4 | 3 | 0 | 0 | 1.0 | 1.0 | 3.003 | 7 |
| same_ray > three_ray4 | 5240 | 1 | 3545 | 0 | 1.0 | 0.9997 | 0.9998 | 0.9999 | 4 | 3 | 0 | 0 | 1.0 | 0.9999 | 4.037 | 6 |
| three_ray4 > direction | 5240 | 0 | 3546 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 4 | 0 | 0 | 0 | 1.0 | 1.0 | 3.001 | 4 |
| same_ray > direction | 5190 | 16 | 3530 | 50 | 0.9905 | 0.9955 | 0.9969 | 0.9925 | 4 | 0 | 0 | 0 | 1.0 | 0.9925 | 4.0 | 4 |
| three_ray4 > same_ray > direction | 5240 | 0 | 3546 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 4 | 0 | 0 | 0 | 1.0 | 1.0 | 3.003 | 7 |

### Difficult

| method | TP | FP | TN | FN | sensitivity | specificity | precision | accuracy | truth_unknown | model_unknown | unknown_on_yes | unknown_on_no | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| direction | 2575 | 8 | 2038 | 13 | 0.995 | 0.9961 | 0.9969 | 0.9955 | 0 | 0 | 0 | 0 | 1.0 | 0.9955 | 1.0 | 1 |
| same_ray | 2566 | 1 | 2045 | 22 | 0.9915 | 0.9995 | 0.9996 | 0.995 | 0 | 74 | 22 | 52 | 0.984 | 0.9998 | 4.0 | 4 |
| three_ray | 1797 | 0 | 2046 | 791 | 0.6944 | 1.0 | 1.0 | 0.8293 | 0 | 1398 | 791 | 607 | 0.6983 | 1.0 | 3.0 | 3 |
| three_ray4 | 2201 | 0 | 2046 | 387 | 0.8505 | 1.0 | 1.0 | 0.9165 | 0 | 705 | 387 | 318 | 0.8479 | 1.0 | 3.302 | 4 |
| three_ray > same_ray | 2587 | 0 | 2046 | 1 | 0.9996 | 1.0 | 1.0 | 0.9998 | 0 | 20 | 1 | 19 | 0.9957 | 1.0 | 3.905 | 6 |
| three_ray4 > same_ray | 2588 | 0 | 2046 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 0 | 12 | 0 | 12 | 0.9974 | 1.0 | 3.758 | 7 |
| same_ray > three_ray4 | 2588 | 1 | 2045 | 0 | 1.0 | 0.9995 | 0.9996 | 0.9998 | 0 | 12 | 0 | 12 | 0.9974 | 0.9998 | 4.036 | 7 |
| three_ray4 > direction | 2588 | 2 | 2044 | 0 | 1.0 | 0.999 | 0.9992 | 0.9996 | 0 | 0 | 0 | 0 | 1.0 | 0.9996 | 3.302 | 4 |
| same_ray > direction | 2581 | 6 | 2040 | 7 | 0.9973 | 0.9971 | 0.9977 | 0.9972 | 0 | 0 | 0 | 0 | 1.0 | 0.9972 | 4.0 | 4 |
| three_ray4 > same_ray > direction | 2588 | 1 | 2045 | 0 | 1.0 | 0.9995 | 0.9996 | 0.9998 | 0 | 0 | 0 | 0 | 1.0 | 0.9998 | 3.758 | 7 |

### Stress

| method | TP | FP | TN | FN | sensitivity | specificity | precision | accuracy | truth_unknown | model_unknown | unknown_on_yes | unknown_on_no | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| direction | 567 | 0 | 191 | 243 | 0.7 | 1.0 | 1.0 | 0.7572 | 11 | 92 | 91 | 0 | 0.9091 | 0.833 | 1.0 | 1 |
| same_ray | 662 | 0 | 191 | 148 | 0.8173 | 1.0 | 1.0 | 0.8521 | 11 | 161 | 148 | 2 | 0.8501 | 1.0 | 3.727 | 4 |
| three_ray | 541 | 0 | 191 | 269 | 0.6679 | 1.0 | 1.0 | 0.7313 | 11 | 377 | 269 | 97 | 0.6344 | 1.0 | 3.0 | 3 |
| three_ray4 | 541 | 0 | 191 | 269 | 0.6679 | 1.0 | 1.0 | 0.7313 | 11 | 377 | 269 | 97 | 0.6344 | 1.0 | 3.273 | 4 |
| three_ray > same_ray | 719 | 0 | 191 | 91 | 0.8877 | 1.0 | 1.0 | 0.9091 | 11 | 103 | 91 | 1 | 0.9081 | 1.0 | 3.845 | 6 |
| three_ray4 > same_ray | 719 | 0 | 191 | 91 | 0.8877 | 1.0 | 1.0 | 0.9091 | 11 | 103 | 91 | 1 | 0.9081 | 1.0 | 4.118 | 7 |
| same_ray > three_ray4 | 719 | 0 | 191 | 91 | 0.8877 | 1.0 | 1.0 | 0.9091 | 11 | 103 | 91 | 1 | 0.9081 | 1.0 | 4.05 | 7 |
| three_ray4 > direction | 672 | 0 | 191 | 138 | 0.8296 | 1.0 | 1.0 | 0.8621 | 11 | 92 | 91 | 0 | 0.9091 | 0.9484 | 3.273 | 4 |
| same_ray > direction | 662 | 0 | 191 | 148 | 0.8173 | 1.0 | 1.0 | 0.8521 | 11 | 92 | 91 | 0 | 0.9091 | 0.9374 | 3.727 | 4 |
| three_ray4 > same_ray > direction | 719 | 0 | 191 | 91 | 0.8877 | 1.0 | 1.0 | 0.9091 | 11 | 92 | 91 | 0 | 0.9091 | 1.0 | 4.118 | 7 |

## Rough-distance estimate factor 2

### Normal

| method | TP | FP | TN | FN | sensitivity | specificity | precision | accuracy | truth_unknown | model_unknown | unknown_on_yes | unknown_on_no | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| direction | 5144 | 36 | 3510 | 96 | 0.9817 | 0.9898 | 0.9931 | 0.985 | 4 | 0 | 0 | 0 | 1.0 | 0.985 | 1.0 | 1 |
| same_ray | 1056 | 0 | 3546 | 4184 | 0.2015 | 1.0 | 1.0 | 0.5238 | 4 | 7019 | 4184 | 2831 | 0.2016 | 1.0 | 4.0 | 4 |
| three_ray | 5225 | 0 | 3546 | 15 | 0.9971 | 1.0 | 1.0 | 0.9983 | 4 | 32 | 15 | 13 | 0.9968 | 1.0 | 3.0 | 3 |
| three_ray4 | 5238 | 0 | 3546 | 2 | 0.9996 | 1.0 | 1.0 | 0.9998 | 4 | 8 | 2 | 2 | 0.9995 | 1.0 | 3.003 | 4 |
| three_ray > same_ray | 5231 | 0 | 3546 | 9 | 0.9983 | 1.0 | 1.0 | 0.999 | 4 | 22 | 9 | 9 | 0.998 | 1.0 | 3.011 | 6 |
| three_ray4 > same_ray | 5240 | 0 | 3546 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 4 | 5 | 0 | 1 | 0.9999 | 1.0 | 3.006 | 7 |
| same_ray > three_ray4 | 5240 | 0 | 3546 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 4 | 5 | 0 | 1 | 0.9999 | 1.0 | 5.599 | 7 |
| three_ray4 > direction | 5240 | 0 | 3546 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 4 | 0 | 0 | 0 | 1.0 | 1.0 | 3.003 | 4 |
| same_ray > direction | 5162 | 27 | 3519 | 78 | 0.9851 | 0.9924 | 0.9948 | 0.988 | 4 | 0 | 0 | 0 | 1.0 | 0.988 | 4.0 | 4 |
| three_ray4 > same_ray > direction | 5240 | 0 | 3546 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 4 | 0 | 0 | 0 | 1.0 | 1.0 | 3.006 | 7 |

### Difficult

| method | TP | FP | TN | FN | sensitivity | specificity | precision | accuracy | truth_unknown | model_unknown | unknown_on_yes | unknown_on_no | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| direction | 2575 | 8 | 2038 | 13 | 0.995 | 0.9961 | 0.9969 | 0.9955 | 0 | 0 | 0 | 0 | 1.0 | 0.9955 | 1.0 | 1 |
| same_ray | 1027 | 1 | 2045 | 1561 | 0.3968 | 0.9995 | 0.999 | 0.6629 | 0 | 2695 | 1561 | 1134 | 0.4184 | 0.9995 | 4.0 | 4 |
| three_ray | 1621 | 0 | 2046 | 967 | 0.6264 | 1.0 | 1.0 | 0.7913 | 0 | 1728 | 967 | 761 | 0.6271 | 1.0 | 3.0 | 3 |
| three_ray4 | 2086 | 0 | 2046 | 502 | 0.806 | 1.0 | 1.0 | 0.8917 | 0 | 912 | 502 | 410 | 0.8032 | 1.0 | 3.373 | 4 |
| three_ray > same_ray | 2087 | 0 | 2046 | 501 | 0.8064 | 1.0 | 1.0 | 0.8919 | 0 | 858 | 501 | 357 | 0.8148 | 1.0 | 4.119 | 6 |
| three_ray4 > same_ray | 2326 | 0 | 2046 | 262 | 0.8988 | 1.0 | 1.0 | 0.9435 | 0 | 467 | 262 | 205 | 0.8992 | 1.0 | 3.963 | 7 |
| same_ray > three_ray4 | 2326 | 1 | 2045 | 262 | 0.8988 | 0.9995 | 0.9996 | 0.9432 | 0 | 467 | 262 | 205 | 0.8992 | 0.9998 | 5.348 | 7 |
| three_ray4 > direction | 2588 | 3 | 2043 | 0 | 1.0 | 0.9985 | 0.9988 | 0.9994 | 0 | 0 | 0 | 0 | 1.0 | 0.9994 | 3.373 | 4 |
| same_ray > direction | 2576 | 5 | 2041 | 12 | 0.9954 | 0.9976 | 0.9981 | 0.9963 | 0 | 0 | 0 | 0 | 1.0 | 0.9963 | 4.0 | 4 |
| three_ray4 > same_ray > direction | 2588 | 2 | 2044 | 0 | 1.0 | 0.999 | 0.9992 | 0.9996 | 0 | 0 | 0 | 0 | 1.0 | 0.9996 | 3.963 | 7 |

### Stress

| method | TP | FP | TN | FN | sensitivity | specificity | precision | accuracy | truth_unknown | model_unknown | unknown_on_yes | unknown_on_no | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| direction | 567 | 0 | 191 | 243 | 0.7 | 1.0 | 1.0 | 0.7572 | 11 | 92 | 91 | 0 | 0.9091 | 0.833 | 1.0 | 1 |
| same_ray | 273 | 0 | 191 | 537 | 0.337 | 1.0 | 1.0 | 0.4635 | 11 | 737 | 537 | 189 | 0.2747 | 1.0 | 3.727 | 4 |
| three_ray | 541 | 0 | 191 | 269 | 0.6679 | 1.0 | 1.0 | 0.7313 | 11 | 377 | 269 | 97 | 0.6344 | 1.0 | 3.0 | 3 |
| three_ray4 | 632 | 0 | 191 | 178 | 0.7802 | 1.0 | 1.0 | 0.8222 | 11 | 285 | 178 | 96 | 0.7263 | 1.0 | 3.273 | 4 |
| three_ray > same_ray | 541 | 0 | 191 | 269 | 0.6679 | 1.0 | 1.0 | 0.7313 | 11 | 377 | 269 | 97 | 0.6344 | 1.0 | 3.845 | 6 |
| three_ray4 > same_ray | 632 | 0 | 191 | 178 | 0.7802 | 1.0 | 1.0 | 0.8222 | 11 | 285 | 178 | 96 | 0.7263 | 1.0 | 3.845 | 7 |
| same_ray > three_ray4 | 632 | 0 | 191 | 178 | 0.7802 | 1.0 | 1.0 | 0.8222 | 11 | 285 | 178 | 96 | 0.7263 | 1.0 | 5.457 | 7 |
| three_ray4 > direction | 672 | 0 | 191 | 138 | 0.8296 | 1.0 | 1.0 | 0.8621 | 11 | 92 | 91 | 0 | 0.9091 | 0.9484 | 3.273 | 4 |
| same_ray > direction | 624 | 0 | 191 | 186 | 0.7704 | 1.0 | 1.0 | 0.8142 | 11 | 92 | 91 | 0 | 0.9091 | 0.8956 | 3.727 | 4 |
| three_ray4 > same_ray > direction | 672 | 0 | 191 | 138 | 0.8296 | 1.0 | 1.0 | 0.8621 | 11 | 92 | 91 | 0 | 0.9091 | 0.9484 | 3.845 | 7 |

## Same-ray behaviour and aim-point switching (factor 1)

Same-ray outcomes, as `bracket_agree / bracket_disagree / no_lower_bound /
inconsistent / invalid`:

| Population | Outcomes |
|---|---|
| normal | 8,658 / 115 / 17 / 0 / 0 |
| difficult | 4,575 / 38 / 21 / 0 / 0 |
| stress | 724 / 12 / 184 / 0 / 92 |

At factor 2 the lower bound is usually lost: normal has 6,975 `no_lower_bound`
and difficult has 2,675. The ladder then starts at the true centre distance,
so the first probe already overshoots. At factor 0.5, difficult has two
`inconsistent` rows.

Switching counts per population, factor 1:

| Population | Rows with probes | A probe selected another aim point | Switch read as forward | Bracket excludes true distance | Wrong decided answer among switch rows |
|---|---:|---:|---:|---:|---:|
| normal | 8,790 | 1,046 | 0 | 0 | 0 |
| difficult | 4,634 | 2,009 | 6 | 0 | 0 |
| stress | 920 | 92 | 92 | 92 | 0 |

- **Switching after overshoot is common and mostly harmless.** The switched
  probe reads as reversed or switched, which is the intended overshoot signal.
- **Hidden switches in supported geometry:** at 100 km, three boundary origins
  on `ship_gen_s_fightingdrone_01` pick a neighbouring aim point that lies
  within the 1e-4 rad forward tolerance. Each origin appears twice because two
  macros use that component. The bracket still contains the true distance, and
  no answer was wrong.
- **Stress `collinear_replacement`:** every row hides the switch, as the
  construction intends, and every bracket misses 60 m. With the muzzle on O the
  wrong bracket flips no answer at any factor: all 92 rows are `bracket_agree`
  and match truth (91 YES, 1 NO).

## Failure groups for A5 (factor 1 unless stated)

1. **Direction-only errors near the target.** Normal has 132 wrong answers:
   36 false ENGAGEABLE and 96 false NOT ENGAGEABLE. By radius, 103 are at 10 m,
   24 at 100 m and 5 at 1 km. Difficult has 21 (8 false ENGAGEABLE), 16 of them
   at 10 m. The counts are identical at every factor. Many 10 m origins sit
   inside large hulls. A5 must decide how much of this normal population is
   plausible combat geometry before these counts carry weight.
2. **Same-ray `bracket_disagree` UNKNOWN.** There are 115 normal and 38
   difficult rows, concentrated at 10 m (99 normal, 31 difficult). The ½–2×
   bracket is too wide where the pivot offset matters. The bracket rule also
   assumes the answer does not change within the bracket and flip back, which
   A5 must check against a dense scan along the ray.
3. **Same-ray decided errors.** One false ENGAGEABLE per population, both at
   10 m with the bracket holding and no switch: normal
   `ship_xen_m_fighter_01` × `turret_spl_l_plasma_01_mk1_macro` (factors .5 and
   1), difficult `engine_xen_xl_mothership_01_allround_mk1` ×
   `turret_tel_m_laser_01_mk1_macro` (every factor). These are direct
   counterexamples to the no-flip-back assumption in group 2. They reach
   `same_ray > three_ray4` as its only decided errors.
4. **Same-ray dependence on the rough distance.** Coverage at factors .5 / 1 / 2
   is 0.982 / 0.9853 / 0.2016 for normal and 0.984 / 0.9873 / 0.4184 for
   difficult. An overestimate removes the lower bound. A production rough
   source (centre `distanceto` or `bboxdistanceto`) and its bias versus
   aim-point distance are unmeasured.
5. **Three-ray mixed-selection failures on difficult geometry.** Three-ray
   alone returns 1,617 UNKNOWN; forward failures on the boundary are 1,392.
   The inward fourth probe leaves 777 (643 boundary forward, 45 known172). On
   known172, three-ray covers 0/74 at factor 1, three_ray4 covers 29/74 and
   same-ray covers 74/74.
6. **Normal three_ray4 residual UNKNOWN.** Three truth-known rows remain at
   factor 1 and ten over all factors: 10 m on
   `engine_xen_xl_mothership_01_allround_mk1` (two turrets), 10 m on
   `ship_pir_s_heavyfighter_01`, and at factor 2 one at 1 km on the Xenon
   engine.
7. **Stacks that end in direction-only.** They reach full coverage but bring
   direction-only errors back wherever the earlier methods are UNKNOWN.
   `same_ray > direction` has 7 false ENGAGEABLE and 32 false NOT ENGAGEABLE in
   normal (16/50 at .5, 27/78 at 2). `three_ray4 > direction` has 2 false
   ENGAGEABLE in difficult (3 at factor 2). `three_ray4 > same_ray > direction`
   has no decided error in normal or difficult at factor 1, 1 false ENGAGEABLE
   in difficult at .5 and 2 at 2. Stacks without the direction fallback have
   no decided errors in normal or difficult at any factor, except the same-ray
   rows of group 3.
8. **Supported same-ray hidden switch** on the 100 km fighting drone (above).
   It caused no error but is a real tolerance-dependent mechanism.
9. **Stress mechanisms.**
   - The false consensus of the A2 `false_triple` passes in all 92 rows at
     each factor, yet flips no answer here.
   - `collinear_replacement` hides the switch in every row but flips no answer.
   - The `at_point` anchor is invalid, so every method is UNKNOWN on it.
   - Direction-only gives 152 false NOT ENGAGEABLE, on 1 m, 1 cm and near-switch geometry; `three_ray4 > direction` keeps 47
     of those false NOT ENGAGEABLE.
10. **Truth UNKNOWN.** There are 4 normal rows per factor, single-point at
    10 m: `turret_ter_m_beam_02_mk1`, `turret_ter_m_gatling_02_mk1` and
    `turret_spl_l_guided_01_mk1` against `turret_arg_m_beam_01_mk1_macro`, and
    `turret_par_m_mining_02_mk1` against `turret_arg_m_gatling_01_mk1_macro`.
    There are 11 stress rows: `turret_arg_m_beam_01` (5), then
    `turret_arg_m_gatling_01`, `turret_spl_m_beam_01` and
    `turret_spl_m_gatling_01` (2 each), all in near-pivot synthetic geometry.
    The scorer returns UNKNOWN for all trap/no-rest states. This includes
    trap-plus-out-of-arc cases, which #176 A3 argues are NOT ENGAGEABLE either
    way. A5 should reclassify those if they occur.
11. **Large three-ray point error without answer error.** The largest accepted
    anchor error outside stress is 234.93 m, at long range. Only the final
    answer is scored, so this is recorded rather than counted.

No production code changed. No LIVE test was needed for this offline
diagnostic.
