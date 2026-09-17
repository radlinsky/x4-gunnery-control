# A4 initial diagnostic results — 2026-09-16

Status: **inference**, raw offline surrogate evidence for Issue #176 A4.
These results are undiagnosed. They do not rank or choose a model and do not
say what error rate is acceptable; A5 audits the groups listed below first.
The contract, populations and reproduction commands are in the README.

Run: 14,436 cases × 3 rough-distance factors = 43,308 rows, produced by
`compare.py` and summarized by `report.py`. Full per-row data (including
subgroup tables for single-point, multi-point, boundary and known172) is in
ignored `.x4-research-cache/issue176-a4/`.

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
| direction | 4743 | 439 | 3600 | 5 | 0.9989 | 0.8913 | 0.9153 | 0.9495 | 3 | 0 | 0 | 0 | 1.0 | 0.9495 | 1.0 | 1 |
| same_ray | 4545 | 0 | 4039 | 203 | 0.9572 | 1.0 | 1.0 | 0.9769 | 3 | 342 | 203 | 136 | 0.9614 | 1.0 | 4.0 | 4 |
| three_ray | 4741 | 0 | 4039 | 7 | 0.9985 | 1.0 | 1.0 | 0.9992 | 3 | 15 | 7 | 5 | 0.9986 | 1.0 | 3.0 | 3 |
| three_ray4 | 4746 | 0 | 4039 | 2 | 0.9996 | 1.0 | 1.0 | 0.9998 | 3 | 6 | 2 | 1 | 0.9997 | 1.0 | 3.001 | 4 |
| three_ray > same_ray | 4747 | 0 | 4039 | 1 | 0.9998 | 1.0 | 1.0 | 0.9999 | 3 | 4 | 1 | 0 | 0.9999 | 1.0 | 3.005 | 6 |
| three_ray4 > same_ray | 4747 | 0 | 4039 | 1 | 0.9998 | 1.0 | 1.0 | 0.9999 | 3 | 4 | 1 | 0 | 0.9999 | 1.0 | 3.003 | 7 |
| same_ray > three_ray4 | 4747 | 0 | 4039 | 1 | 0.9998 | 1.0 | 1.0 | 0.9999 | 3 | 4 | 1 | 0 | 0.9999 | 1.0 | 4.078 | 7 |
| three_ray4 > direction | 4748 | 0 | 4039 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 3 | 0 | 0 | 0 | 1.0 | 1.0 | 3.001 | 4 |
| same_ray > direction | 4745 | 128 | 3911 | 3 | 0.9994 | 0.9683 | 0.9737 | 0.9851 | 3 | 0 | 0 | 0 | 1.0 | 0.9851 | 4.0 | 4 |
| three_ray4 > same_ray > direction | 4748 | 0 | 4039 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 3 | 0 | 0 | 0 | 1.0 | 1.0 | 3.003 | 7 |

### Difficult but supported (4,634 cases: 4,560 boundary, 74 known #172)

| method | TP | FP | TN | FN | sensitivity | specificity | precision | accuracy | truth_unknown | model_unknown | unknown_on_yes | unknown_on_no | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| direction | 2508 | 75 | 2050 | 1 | 0.9996 | 0.9647 | 0.971 | 0.9836 | 0 | 0 | 0 | 0 | 1.0 | 0.9836 | 1.0 | 1 |
| same_ray | 2369 | 0 | 2125 | 140 | 0.9442 | 1.0 | 1.0 | 0.9698 | 0 | 189 | 140 | 49 | 0.9592 | 1.0 | 4.0 | 4 |
| three_ray | 1630 | 0 | 2125 | 879 | 0.6497 | 1.0 | 1.0 | 0.8103 | 0 | 1617 | 879 | 738 | 0.6511 | 1.0 | 3.0 | 3 |
| three_ray4 | 2106 | 0 | 2125 | 403 | 0.8394 | 1.0 | 1.0 | 0.913 | 0 | 777 | 403 | 374 | 0.8323 | 1.0 | 3.349 | 4 |
| three_ray > same_ray | 2473 | 0 | 2125 | 36 | 0.9857 | 1.0 | 1.0 | 0.9922 | 0 | 54 | 36 | 18 | 0.9883 | 1.0 | 4.047 | 6 |
| three_ray4 > same_ray | 2486 | 0 | 2125 | 23 | 0.9908 | 1.0 | 1.0 | 0.995 | 0 | 35 | 23 | 12 | 0.9924 | 1.0 | 3.852 | 7 |
| same_ray > three_ray4 | 2486 | 0 | 2125 | 23 | 0.9908 | 1.0 | 1.0 | 0.995 | 0 | 35 | 23 | 12 | 0.9924 | 1.0 | 4.093 | 7 |
| three_ray4 > direction | 2509 | 22 | 2103 | 0 | 1.0 | 0.9896 | 0.9913 | 0.9953 | 0 | 0 | 0 | 0 | 1.0 | 0.9953 | 3.349 | 4 |
| same_ray > direction | 2509 | 37 | 2088 | 0 | 1.0 | 0.9826 | 0.9855 | 0.992 | 0 | 0 | 0 | 0 | 1.0 | 0.992 | 4.0 | 4 |
| three_ray4 > same_ray > direction | 2509 | 8 | 2117 | 0 | 1.0 | 0.9962 | 0.9968 | 0.9983 | 0 | 0 | 0 | 0 | 1.0 | 0.9983 | 3.852 | 7 |

### Stress / possibly impossible (1,012 cases: 11 synthetic × 92 turrets)

| method | TP | FP | TN | FN | sensitivity | specificity | precision | accuracy | truth_unknown | model_unknown | unknown_on_yes | unknown_on_no | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| direction | 383 | 180 | 394 | 26 | 0.9364 | 0.6864 | 0.6803 | 0.7904 | 29 | 92 | 0 | 84 | 0.9145 | 0.7709 | 1.0 | 1 |
| same_ray | 326 | 2 | 572 | 83 | 0.7971 | 0.9965 | 0.9939 | 0.9135 | 29 | 352 | 83 | 240 | 0.6714 | 0.997 | 3.727 | 4 |
| three_ray | 286 | 0 | 574 | 123 | 0.6993 | 1.0 | 1.0 | 0.8749 | 29 | 388 | 123 | 236 | 0.6348 | 1.0 | 3.0 | 3 |
| three_ray4 | 357 | 0 | 574 | 52 | 0.8729 | 1.0 | 1.0 | 0.9471 | 29 | 296 | 52 | 215 | 0.7284 | 1.0 | 3.273 | 4 |
| three_ray > same_ray | 335 | 0 | 574 | 74 | 0.8191 | 1.0 | 1.0 | 0.9247 | 29 | 226 | 74 | 123 | 0.7996 | 1.0 | 3.877 | 6 |
| three_ray4 > same_ray | 406 | 0 | 574 | 3 | 0.9927 | 1.0 | 1.0 | 0.9969 | 29 | 134 | 3 | 102 | 0.8932 | 1.0 | 3.877 | 7 |
| same_ray > three_ray4 | 406 | 2 | 572 | 3 | 0.9927 | 0.9965 | 0.9951 | 0.9949 | 29 | 134 | 3 | 102 | 0.8932 | 0.9977 | 4.536 | 7 |
| three_ray4 > direction | 396 | 0 | 574 | 13 | 0.9682 | 1.0 | 1.0 | 0.9868 | 29 | 92 | 0 | 84 | 0.9145 | 0.9855 | 3.273 | 4 |
| same_ray > direction | 403 | 44 | 530 | 6 | 0.9853 | 0.9233 | 0.9016 | 0.9491 | 29 | 92 | 0 | 84 | 0.9145 | 0.9444 | 3.727 | 4 |
| three_ray4 > same_ray > direction | 406 | 0 | 574 | 3 | 0.9927 | 1.0 | 1.0 | 0.9969 | 29 | 92 | 0 | 84 | 0.9145 | 0.9967 | 3.877 | 7 |

## Rough-distance estimate factor 0.5

### Normal

| method | TP | FP | TN | FN | sensitivity | specificity | precision | accuracy | truth_unknown | model_unknown | unknown_on_yes | unknown_on_no | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| direction | 4743 | 439 | 3600 | 5 | 0.9989 | 0.8913 | 0.9153 | 0.9495 | 3 | 0 | 0 | 0 | 1.0 | 0.9495 | 1.0 | 1 |
| same_ray | 4499 | 0 | 4039 | 249 | 0.9476 | 1.0 | 1.0 | 0.9717 | 3 | 519 | 248 | 268 | 0.9413 | 0.9999 | 4.0 | 4 |
| three_ray | 4744 | 0 | 4039 | 4 | 0.9992 | 1.0 | 1.0 | 0.9995 | 3 | 11 | 4 | 4 | 0.9991 | 1.0 | 3.0 | 3 |
| three_ray4 | 4746 | 0 | 4039 | 2 | 0.9996 | 1.0 | 1.0 | 0.9998 | 3 | 6 | 2 | 1 | 0.9997 | 1.0 | 3.001 | 4 |
| three_ray > same_ray | 4747 | 0 | 4039 | 1 | 0.9998 | 1.0 | 1.0 | 0.9999 | 3 | 4 | 1 | 0 | 0.9999 | 1.0 | 3.004 | 6 |
| three_ray4 > same_ray | 4747 | 0 | 4039 | 1 | 0.9998 | 1.0 | 1.0 | 0.9999 | 3 | 4 | 1 | 0 | 0.9999 | 1.0 | 3.003 | 7 |
| same_ray > three_ray4 | 4746 | 0 | 4039 | 2 | 0.9996 | 1.0 | 1.0 | 0.9998 | 3 | 4 | 1 | 0 | 0.9999 | 0.9999 | 4.118 | 7 |
| three_ray4 > direction | 4748 | 0 | 4039 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 3 | 0 | 0 | 0 | 1.0 | 1.0 | 3.001 | 4 |
| same_ray > direction | 4743 | 265 | 3774 | 5 | 0.9989 | 0.9344 | 0.9471 | 0.9693 | 3 | 0 | 0 | 0 | 1.0 | 0.9693 | 4.0 | 4 |
| three_ray4 > same_ray > direction | 4748 | 0 | 4039 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 3 | 0 | 0 | 0 | 1.0 | 1.0 | 3.003 | 7 |

### Difficult

| method | TP | FP | TN | FN | sensitivity | specificity | precision | accuracy | truth_unknown | model_unknown | unknown_on_yes | unknown_on_no | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| direction | 2508 | 75 | 2050 | 1 | 0.9996 | 0.9647 | 0.971 | 0.9836 | 0 | 0 | 0 | 0 | 1.0 | 0.9836 | 1.0 | 1 |
| same_ray | 2302 | 0 | 2125 | 207 | 0.9175 | 1.0 | 1.0 | 0.9553 | 0 | 268 | 207 | 61 | 0.9422 | 1.0 | 4.0 | 4 |
| three_ray | 1744 | 0 | 2125 | 765 | 0.6951 | 1.0 | 1.0 | 0.8349 | 0 | 1398 | 765 | 633 | 0.6983 | 1.0 | 3.0 | 3 |
| three_ray4 | 2141 | 0 | 2125 | 368 | 0.8533 | 1.0 | 1.0 | 0.9206 | 0 | 705 | 368 | 337 | 0.8479 | 1.0 | 3.302 | 4 |
| three_ray > same_ray | 2462 | 0 | 2125 | 47 | 0.9813 | 1.0 | 1.0 | 0.9899 | 0 | 70 | 47 | 23 | 0.9849 | 1.0 | 3.905 | 6 |
| three_ray4 > same_ray | 2476 | 0 | 2125 | 33 | 0.9868 | 1.0 | 1.0 | 0.9929 | 0 | 51 | 33 | 18 | 0.989 | 1.0 | 3.758 | 7 |
| same_ray > three_ray4 | 2476 | 0 | 2125 | 33 | 0.9868 | 1.0 | 1.0 | 0.9929 | 0 | 51 | 33 | 18 | 0.989 | 1.0 | 4.131 | 7 |
| three_ray4 > direction | 2509 | 21 | 2104 | 0 | 1.0 | 0.9901 | 0.9917 | 0.9955 | 0 | 0 | 0 | 0 | 1.0 | 0.9955 | 3.302 | 4 |
| same_ray > direction | 2509 | 53 | 2072 | 0 | 1.0 | 0.9751 | 0.9793 | 0.9886 | 0 | 0 | 0 | 0 | 1.0 | 0.9886 | 4.0 | 4 |
| three_ray4 > same_ray > direction | 2509 | 17 | 2108 | 0 | 1.0 | 0.992 | 0.9933 | 0.9963 | 0 | 0 | 0 | 0 | 1.0 | 0.9963 | 3.758 | 7 |

### Stress

| method | TP | FP | TN | FN | sensitivity | specificity | precision | accuracy | truth_unknown | model_unknown | unknown_on_yes | unknown_on_no | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| direction | 383 | 180 | 394 | 26 | 0.9364 | 0.6864 | 0.6803 | 0.7904 | 29 | 92 | 0 | 84 | 0.9145 | 0.7709 | 1.0 | 1 |
| same_ray | 354 | 2 | 572 | 55 | 0.8655 | 0.9965 | 0.9944 | 0.942 | 29 | 252 | 55 | 168 | 0.7731 | 0.9974 | 3.727 | 4 |
| three_ray | 286 | 0 | 574 | 123 | 0.6993 | 1.0 | 1.0 | 0.8749 | 29 | 386 | 123 | 234 | 0.6368 | 1.0 | 3.0 | 3 |
| three_ray4 | 286 | 0 | 574 | 123 | 0.6993 | 1.0 | 1.0 | 0.8749 | 29 | 386 | 123 | 234 | 0.6368 | 1.0 | 3.273 | 4 |
| three_ray > same_ray | 375 | 0 | 574 | 34 | 0.9169 | 1.0 | 1.0 | 0.9654 | 29 | 163 | 34 | 100 | 0.8637 | 1.0 | 3.872 | 6 |
| three_ray4 > same_ray | 375 | 0 | 574 | 34 | 0.9169 | 1.0 | 1.0 | 0.9654 | 29 | 163 | 34 | 100 | 0.8637 | 1.0 | 4.144 | 7 |
| same_ray > three_ray4 | 375 | 2 | 572 | 34 | 0.9169 | 0.9965 | 0.9947 | 0.9634 | 29 | 163 | 34 | 100 | 0.8637 | 0.9976 | 4.279 | 7 |
| three_ray4 > direction | 396 | 20 | 554 | 13 | 0.9682 | 0.9652 | 0.9519 | 0.9664 | 29 | 92 | 0 | 84 | 0.9145 | 0.9633 | 3.273 | 4 |
| same_ray > direction | 403 | 55 | 519 | 6 | 0.9853 | 0.9042 | 0.8799 | 0.9379 | 29 | 92 | 0 | 84 | 0.9145 | 0.9321 | 3.727 | 4 |
| three_ray4 > same_ray > direction | 406 | 1 | 573 | 3 | 0.9927 | 0.9983 | 0.9975 | 0.9959 | 29 | 92 | 0 | 84 | 0.9145 | 0.9956 | 4.144 | 7 |

## Rough-distance estimate factor 2

### Normal

| method | TP | FP | TN | FN | sensitivity | specificity | precision | accuracy | truth_unknown | model_unknown | unknown_on_yes | unknown_on_no | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| direction | 4743 | 439 | 3600 | 5 | 0.9989 | 0.8913 | 0.9153 | 0.9495 | 3 | 0 | 0 | 0 | 1.0 | 0.9495 | 1.0 | 1 |
| same_ray | 765 | 0 | 4039 | 3983 | 0.1611 | 1.0 | 1.0 | 0.5467 | 3 | 7131 | 3983 | 3145 | 0.1888 | 1.0 | 4.0 | 4 |
| three_ray | 4733 | 0 | 4039 | 15 | 0.9968 | 1.0 | 1.0 | 0.9983 | 3 | 31 | 15 | 13 | 0.9968 | 1.0 | 3.0 | 3 |
| three_ray4 | 4746 | 0 | 4039 | 2 | 0.9996 | 1.0 | 1.0 | 0.9998 | 3 | 7 | 2 | 2 | 0.9995 | 1.0 | 3.003 | 4 |
| three_ray > same_ray | 4739 | 0 | 4039 | 9 | 0.9981 | 1.0 | 1.0 | 0.999 | 3 | 21 | 9 | 9 | 0.998 | 1.0 | 3.011 | 6 |
| three_ray4 > same_ray | 4748 | 0 | 4039 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 3 | 4 | 0 | 1 | 0.9999 | 1.0 | 3.006 | 7 |
| same_ray > three_ray4 | 4748 | 0 | 4039 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 3 | 4 | 0 | 1 | 0.9999 | 1.0 | 5.625 | 7 |
| three_ray4 > direction | 4748 | 0 | 4039 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 3 | 0 | 0 | 0 | 1.0 | 1.0 | 3.003 | 4 |
| same_ray > direction | 4745 | 293 | 3746 | 3 | 0.9994 | 0.9275 | 0.9418 | 0.9663 | 3 | 0 | 0 | 0 | 1.0 | 0.9663 | 4.0 | 4 |
| three_ray4 > same_ray > direction | 4748 | 0 | 4039 | 0 | 1.0 | 1.0 | 1.0 | 1.0 | 3 | 0 | 0 | 0 | 1.0 | 1.0 | 3.006 | 7 |

### Difficult

| method | TP | FP | TN | FN | sensitivity | specificity | precision | accuracy | truth_unknown | model_unknown | unknown_on_yes | unknown_on_no | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| direction | 2508 | 75 | 2050 | 1 | 0.9996 | 0.9647 | 0.971 | 0.9836 | 0 | 0 | 0 | 0 | 1.0 | 0.9836 | 1.0 | 1 |
| same_ray | 937 | 0 | 2125 | 1572 | 0.3735 | 1.0 | 1.0 | 0.6608 | 0 | 2762 | 1572 | 1190 | 0.404 | 1.0 | 4.0 | 4 |
| three_ray | 1572 | 0 | 2125 | 937 | 0.6265 | 1.0 | 1.0 | 0.7978 | 0 | 1728 | 937 | 791 | 0.6271 | 1.0 | 3.0 | 3 |
| three_ray4 | 2027 | 0 | 2125 | 482 | 0.8079 | 1.0 | 1.0 | 0.896 | 0 | 912 | 482 | 430 | 0.8032 | 1.0 | 3.373 | 4 |
| three_ray > same_ray | 2003 | 0 | 2125 | 506 | 0.7983 | 1.0 | 1.0 | 0.8908 | 0 | 877 | 506 | 371 | 0.8107 | 1.0 | 4.119 | 6 |
| three_ray4 > same_ray | 2246 | 0 | 2125 | 263 | 0.8952 | 1.0 | 1.0 | 0.9432 | 0 | 476 | 263 | 213 | 0.8973 | 1.0 | 3.963 | 7 |
| same_ray > three_ray4 | 2246 | 0 | 2125 | 263 | 0.8952 | 1.0 | 1.0 | 0.9432 | 0 | 476 | 263 | 213 | 0.8973 | 1.0 | 5.381 | 7 |
| three_ray4 > direction | 2509 | 23 | 2102 | 0 | 1.0 | 0.9892 | 0.9909 | 0.995 | 0 | 0 | 0 | 0 | 1.0 | 0.995 | 3.373 | 4 |
| same_ray > direction | 2508 | 57 | 2068 | 1 | 0.9996 | 0.9732 | 0.9778 | 0.9875 | 0 | 0 | 0 | 0 | 1.0 | 0.9875 | 4.0 | 4 |
| three_ray4 > same_ray > direction | 2509 | 12 | 2113 | 0 | 1.0 | 0.9944 | 0.9952 | 0.9974 | 0 | 0 | 0 | 0 | 1.0 | 0.9974 | 3.963 | 7 |

### Stress

| method | TP | FP | TN | FN | sensitivity | specificity | precision | accuracy | truth_unknown | model_unknown | unknown_on_yes | unknown_on_no | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| direction | 383 | 180 | 394 | 26 | 0.9364 | 0.6864 | 0.6803 | 0.7904 | 29 | 92 | 0 | 84 | 0.9145 | 0.7709 | 1.0 | 1 |
| same_ray | 163 | 2 | 572 | 246 | 0.3985 | 0.9965 | 0.9879 | 0.7477 | 29 | 761 | 246 | 486 | 0.2553 | 0.992 | 3.727 | 4 |
| three_ray | 286 | 0 | 574 | 123 | 0.6993 | 1.0 | 1.0 | 0.8749 | 29 | 386 | 123 | 234 | 0.6368 | 1.0 | 3.0 | 3 |
| three_ray4 | 357 | 0 | 574 | 52 | 0.8729 | 1.0 | 1.0 | 0.9471 | 29 | 294 | 52 | 213 | 0.7304 | 1.0 | 3.273 | 4 |
| three_ray > same_ray | 286 | 0 | 574 | 123 | 0.6993 | 1.0 | 1.0 | 0.8749 | 29 | 386 | 123 | 234 | 0.6368 | 1.0 | 3.872 | 6 |
| three_ray4 > same_ray | 357 | 0 | 574 | 52 | 0.8729 | 1.0 | 1.0 | 0.9471 | 29 | 294 | 52 | 213 | 0.7304 | 1.0 | 3.872 | 7 |
| same_ray > three_ray4 | 357 | 2 | 572 | 52 | 0.8729 | 0.9965 | 0.9944 | 0.9451 | 29 | 294 | 52 | 213 | 0.7304 | 0.9972 | 5.504 | 7 |
| three_ray4 > direction | 396 | 0 | 574 | 13 | 0.9682 | 1.0 | 1.0 | 0.9868 | 29 | 92 | 0 | 84 | 0.9145 | 0.9855 | 3.273 | 4 |
| same_ray > direction | 383 | 147 | 427 | 26 | 0.9364 | 0.7439 | 0.7226 | 0.824 | 29 | 92 | 0 | 84 | 0.9145 | 0.8076 | 3.727 | 4 |
| three_ray4 > same_ray > direction | 396 | 0 | 574 | 13 | 0.9682 | 1.0 | 1.0 | 0.9868 | 29 | 92 | 0 | 84 | 0.9145 | 0.9855 | 3.872 | 7 |

## Same-ray behaviour and aim-point switching (factor 1)

Same-ray outcomes, as `bracket_agree / bracket_disagree / no_lower_bound /
inconsistent / invalid`:

| Population | Outcomes |
|---|---|
| normal | 8,448 / 325 / 17 / 0 / 0 |
| difficult | 4,445 / 168 / 21 / 0 / 0 |
| stress | 660 / 76 / 184 / 0 / 92 |

At factor 2 the lower bound is usually lost: normal has 6,975 `no_lower_bound`
and difficult has 2,675. The ladder then starts at the true centre distance,
so the first probe already overshoots. At factor 0.5, difficult has two
`inconsistent` rows.

Switching counts per population, factor 1:

| Population | Rows with probes | A probe selected another aim point | Switch read as forward | Bracket excludes true distance | Wrong decided answer among switch rows |
|---|---:|---:|---:|---:|---:|
| normal | 8,790 | 1,046 | 0 | 0 | 0 |
| difficult | 4,634 | 2,009 | 6 | 0 | 0 |
| stress | 920 | 92 | 92 | 92 | 2 |

- **Switching after overshoot is common and mostly harmless.** The switched
  probe reads as reversed or switched, which is the intended overshoot signal.
- **Hidden switches in supported geometry:** at 100 km, three boundary origins
  on `ship_gen_s_fightingdrone_01` pick a neighbouring aim point that lies
  within the 1e-4 rad forward tolerance. Each origin appears twice because two
  macros use that component. The bracket still contains the true distance, and
  no answer was wrong.
- **Stress `collinear_replacement`:** every row hides the switch, as the
  construction intends, and every bracket misses 60 m. That flips the answer to
  false ENGAGEABLE for `turret_bor_l_disruptor_01_mk1_macro` and
  `turret_bor_l_laser_01_mk1_macro`. Of 92 rows, 17 more become
  `bracket_disagree` UNKNOWN because the wrong bracket spans an arc edge.

## Failure groups for A5 (factor 1 unless stated)

1. **Direction-only false ENGAGEABLE near the target.** Normal has 444 wrong
   answers: 439 false ENGAGEABLE and 5 false NOT ENGAGEABLE. By radius, 342
   are at 10 m, 82 at 100 m, 14 at 1 km and 6 at 10 km. Difficult has 76
   (75 false ENGAGEABLE), 55 of them at 10 m. Many 10 m origins sit inside
   large hulls. A5 must decide how much of this normal population is plausible
   combat geometry before these counts carry weight.
2. **Same-ray `bracket_disagree` UNKNOWN.** There are 325 normal and 168
   difficult rows, concentrated at 10 m (259 normal, 149 difficult). The ½–2×
   bracket is too wide where the pivot offset matters. The bracket rule also
   assumes the answer does not change within the bracket and flip back, which
   A5 must check against a dense scan along the ray.
3. **Same-ray dependence on the rough distance.** Coverage at factors .5 / 1 / 2
   is 0.9413 / 0.9614 / 0.1888 for normal and 0.9422 / 0.9592 / 0.404 for
   difficult. An overestimate removes the lower bound. A production rough
   source (centre `distanceto` or `bboxdistanceto`) and its bias versus
   aim-point distance are unmeasured.
4. **Three-ray mixed-selection failures on difficult geometry.** Three-ray
   alone returns 1,617 UNKNOWN; forward failures on the boundary are 1,392.
   The inward fourth probe leaves 777 (643 boundary forward, 45 known172). On
   known172, three-ray covers 0/74 at factor 1, three_ray4 covers 29/74 and
   same-ray covers 74/74.
5. **Normal three_ray4 residual UNKNOWN.** Three rows remain at factor 1 and
   ten over all factors: 10 m on `engine_xen_xl_mothership_01_allround_mk1`,
   10 m on `ship_pir_s_heavyfighter_01`, and one at 1 km on the Xenon engine.
6. **Stacks that end in direction-only.** They reach full coverage but bring
   direction-only errors back wherever the earlier methods are UNKNOWN.
   `three_ray4 > same_ray > direction` has 8 false ENGAGEABLE in difficult at
   factor 1, 17 at .5 and 12 at 2. `same_ray > direction` has 128 in normal.
   `three_ray4 > direction` has 22 in difficult. Stacks without the
   direction fallback have no decided errors in normal or difficult at any
   factor.
7. **Supported same-ray hidden switch** on the 100 km fighting drone (above).
   It caused no error but is a real tolerance-dependent mechanism.
8. **Stress mechanisms.**
   - The false consensus of the A2 `false_triple` passes in all 92 rows at
     each factor, yet flips no answer here.
   - `collinear_replacement` gives 2 same-ray false ENGAGEABLE at each factor.
   - The `at_point` anchor is invalid, so every method is UNKNOWN on it.
   - Direction-only fails widely on 1 m, 1 cm and near-switch geometry.
9. **Truth UNKNOWN.** There are 3 normal rows per factor:
   `shield_spl_l_standard_01_mk2`, `turret_tel_m_dumbfire_01_mk1` and
   `turret_ter_m_gatling_02_mk1`. There are 29 stress rows, spread over 8 turrets led by
   `turret_gen_m_yacht_01` (6), then `turret_arg_m_beam_01`,
   `turret_arg_m_gatling_01` and `turret_ter_m_laser_04` (5 each), all in
   near-pivot synthetic geometry. The
   scorer returns UNKNOWN for all trap/no-rest states. This includes
   trap-plus-out-of-arc cases, which #176 A3 argues are NOT ENGAGEABLE either
   way. A5 should reclassify those if they occur.
10. **Large three-ray point error without answer error.** The largest accepted
    anchor error outside stress is 234.93 m, at long range. Only the final
    answer is scored, so this is recorded rather than counted.

No production code changed. No LIVE test was needed for this offline
diagnostic.
