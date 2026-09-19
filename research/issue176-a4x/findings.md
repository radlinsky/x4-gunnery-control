# Expanded A4 ENGAGEABLE benchmark findings

Status: **inference**, offline mechanical bearing/arc benchmark evidence. This task does not classify A5 failure causes or select a production method.

Accepted starting scorer SHA: `4dafbf0a9211610d007996facaf40c5ca30ca220`.

The run contains 37,830 turret/scenario cases and 113,490 rows across rough-distance factors 0.5, 1, and 2. Nominal factor 1 contributes 37,830 rows. Single-point, multi-point, and boundary scenarios independently assign sorted turrets round-robin (6,990, 1,800, and 4,560 cases). All 74 known172 scenarios and all 11 synthetic stress scenarios run against all 288 turrets (21,312 and 3,168 cases). The existing 24 component rotations cycle deterministically, offset so every turret walks distinct rotations across its repeat appearances rather than aliasing onto one.

Each scenario/factor computes its direction, same-ray, three-ray, and three-ray4 query observations once. Turret scoring then places the selected reference endpoint at O using the record's ordered transforms and nearest-to-zero legal joint pose.

Truth UNKNOWN rows are excluded from TP/FP/TN/FN rates. Prediction UNKNOWN is counted as player-view NOT ENGAGEABLE in ordinary sensitivity and accuracy, and is also reported separately.

## Rough-distance sensitivity, all 288 turrets

### Rough factor 0.5

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 22494 | 15131 | 0 | 0 | 1.0 | 0.0 | 0.5978 | 0 | 205 | 1.0 | 0.5978 | 0.0 | 0 |
| direction | 21722 | 76 | 15055 | 772 | 0.9657 | 0.995 | 0.9775 | 365 | 205 | 0.9909 | 0.9865 | 1.0 | 1 |
| same_ray | 21846 | 2 | 15129 | 648 | 0.9712 | 0.9999 | 0.9827 | 1169 | 205 | 0.9741 | 0.9998 | 3.977 | 4 |
| three_ray | 11303 | 0 | 15131 | 11191 | 0.5025 | 1.0 | 0.7026 | 19350 | 205 | 0.4911 | 0.9998 | 3.0 | 3 |
| three_ray4 | 14541 | 0 | 15131 | 7953 | 0.6464 | 1.0 | 0.7886 | 13784 | 205 | 0.639 | 0.9999 | 3.5 | 4 |
| three_ray > same_ray | 22100 | 0 | 15131 | 394 | 0.9825 | 1.0 | 0.9895 | 679 | 205 | 0.987 | 0.9999 | 4.512 | 6 |
| three_ray4 > same_ray | 22119 | 0 | 15131 | 375 | 0.9833 | 1.0 | 0.99 | 625 | 205 | 0.9885 | 0.9999 | 4.57 | 7 |
| same_ray > three_ray4 | 22118 | 2 | 15129 | 376 | 0.9833 | 0.9999 | 0.99 | 625 | 205 | 0.9885 | 0.9998 | 4.046 | 7 |
| three_ray4 > direction | 22119 | 19 | 15112 | 375 | 0.9833 | 0.9987 | 0.9895 | 332 | 205 | 0.9917 | 0.9978 | 3.5 | 4 |
| same_ray > direction | 21939 | 54 | 15077 | 555 | 0.9753 | 0.9964 | 0.9838 | 341 | 205 | 0.9915 | 0.9923 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 22151 | 15 | 15116 | 343 | 0.9848 | 0.999 | 0.9905 | 322 | 205 | 0.992 | 0.9985 | 4.57 | 7 |

### Rough factor 1

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 22494 | 15131 | 0 | 0 | 1.0 | 0.0 | 0.5978 | 0 | 205 | 1.0 | 0.5978 | 0.0 | 0 |
| direction | 21722 | 76 | 15055 | 772 | 0.9657 | 0.995 | 0.9775 | 365 | 205 | 0.9909 | 0.9865 | 1.0 | 1 |
| same_ray | 21559 | 2 | 15129 | 935 | 0.9584 | 0.9999 | 0.9751 | 1477 | 205 | 0.966 | 0.9998 | 3.977 | 4 |
| three_ray | 8822 | 0 | 15131 | 13672 | 0.3922 | 1.0 | 0.6366 | 24160 | 205 | 0.3632 | 0.9998 | 3.0 | 3 |
| three_ray4 | 14150 | 0 | 15131 | 8344 | 0.6291 | 1.0 | 0.7782 | 14721 | 205 | 0.6141 | 0.9999 | 3.627 | 4 |
| three_ray > same_ray | 21911 | 0 | 15131 | 583 | 0.9741 | 1.0 | 0.9845 | 906 | 205 | 0.9811 | 0.9999 | 4.893 | 6 |
| three_ray4 > same_ray | 22163 | 0 | 15131 | 331 | 0.9853 | 1.0 | 0.9912 | 570 | 205 | 0.9901 | 0.9999 | 4.772 | 7 |
| same_ray > three_ray4 | 22159 | 2 | 15129 | 335 | 0.9851 | 0.9999 | 0.991 | 570 | 205 | 0.9901 | 0.9998 | 4.068 | 7 |
| three_ray4 > direction | 22132 | 20 | 15111 | 362 | 0.9839 | 0.9987 | 0.9898 | 328 | 205 | 0.9918 | 0.998 | 3.627 | 4 |
| same_ray > direction | 22090 | 27 | 15104 | 404 | 0.982 | 0.9982 | 0.9885 | 310 | 205 | 0.9923 | 0.9962 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 22203 | 5 | 15126 | 291 | 0.9871 | 0.9997 | 0.9921 | 299 | 205 | 0.9926 | 0.9995 | 4.772 | 7 |

### Rough factor 2

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 22494 | 15131 | 0 | 0 | 1.0 | 0.0 | 0.5978 | 0 | 205 | 1.0 | 0.5978 | 0.0 | 0 |
| direction | 21722 | 76 | 15055 | 772 | 0.9657 | 0.995 | 0.9775 | 365 | 205 | 0.9909 | 0.9865 | 1.0 | 1 |
| same_ray | 13660 | 0 | 15131 | 8834 | 0.6073 | 1.0 | 0.7652 | 14265 | 205 | 0.6262 | 0.9998 | 3.977 | 4 |
| three_ray | 8749 | 0 | 15131 | 13745 | 0.3889 | 1.0 | 0.6347 | 24287 | 205 | 0.3599 | 0.9998 | 3.0 | 3 |
| three_ray4 | 13032 | 0 | 15131 | 9462 | 0.5794 | 1.0 | 0.7485 | 16862 | 205 | 0.5572 | 0.9999 | 3.631 | 4 |
| three_ray > same_ray | 19957 | 0 | 15131 | 2537 | 0.8872 | 1.0 | 0.9326 | 4304 | 205 | 0.8908 | 0.9999 | 4.903 | 6 |
| three_ray4 > same_ray | 20874 | 0 | 15131 | 1620 | 0.928 | 1.0 | 0.9569 | 2729 | 205 | 0.9327 | 0.9999 | 4.945 | 7 |
| same_ray > three_ray4 | 20870 | 0 | 15131 | 1624 | 0.9278 | 1.0 | 0.9568 | 2729 | 205 | 0.9327 | 0.9998 | 4.834 | 7 |
| three_ray4 > direction | 22128 | 32 | 15099 | 366 | 0.9837 | 0.9979 | 0.9894 | 328 | 205 | 0.9918 | 0.9976 | 3.631 | 4 |
| same_ray > direction | 21914 | 47 | 15084 | 580 | 0.9742 | 0.9969 | 0.9833 | 325 | 205 | 0.9919 | 0.9913 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 22185 | 13 | 15118 | 309 | 0.9863 | 0.9991 | 0.9914 | 305 | 205 | 0.9925 | 0.999 | 4.945 | 7 |

## Nominal result by reporting dimension

### Combined all 288 turrets (37,830 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 22494 | 15131 | 0 | 0 | 1.0 | 0.0 | 0.5978 | 0 | 205 | 1.0 | 0.5978 | 0.0 | 0 |
| direction | 21722 | 76 | 15055 | 772 | 0.9657 | 0.995 | 0.9775 | 365 | 205 | 0.9909 | 0.9865 | 1.0 | 1 |
| same_ray | 21559 | 2 | 15129 | 935 | 0.9584 | 0.9999 | 0.9751 | 1477 | 205 | 0.966 | 0.9998 | 3.977 | 4 |
| three_ray | 8822 | 0 | 15131 | 13672 | 0.3922 | 1.0 | 0.6366 | 24160 | 205 | 0.3632 | 0.9998 | 3.0 | 3 |
| three_ray4 | 14150 | 0 | 15131 | 8344 | 0.6291 | 1.0 | 0.7782 | 14721 | 205 | 0.6141 | 0.9999 | 3.627 | 4 |
| three_ray > same_ray | 21911 | 0 | 15131 | 583 | 0.9741 | 1.0 | 0.9845 | 906 | 205 | 0.9811 | 0.9999 | 4.893 | 6 |
| three_ray4 > same_ray | 22163 | 0 | 15131 | 331 | 0.9853 | 1.0 | 0.9912 | 570 | 205 | 0.9901 | 0.9999 | 4.772 | 7 |
| same_ray > three_ray4 | 22159 | 2 | 15129 | 335 | 0.9851 | 0.9999 | 0.991 | 570 | 205 | 0.9901 | 0.9998 | 4.068 | 7 |
| three_ray4 > direction | 22132 | 20 | 15111 | 362 | 0.9839 | 0.9987 | 0.9898 | 328 | 205 | 0.9918 | 0.998 | 3.627 | 4 |
| same_ray > direction | 22090 | 27 | 15104 | 404 | 0.982 | 0.9982 | 0.9885 | 310 | 205 | 0.9923 | 0.9962 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 22203 | 5 | 15126 | 291 | 0.9871 | 0.9997 | 0.9921 | 299 | 205 | 0.9926 | 0.9995 | 4.772 | 7 |

### Official X4 (16,394 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 9643 | 6745 | 0 | 0 | 1.0 | 0.0 | 0.5884 | 0 | 6 | 1.0 | 0.5884 | 0.0 | 0 |
| direction | 9354 | 21 | 6724 | 289 | 0.97 | 0.9969 | 0.9811 | 124 | 6 | 0.9925 | 0.9885 | 1.0 | 1 |
| same_ray | 9272 | 2 | 6743 | 371 | 0.9615 | 0.9997 | 0.9772 | 470 | 6 | 0.9717 | 0.9998 | 3.977 | 4 |
| three_ray | 3838 | 0 | 6745 | 5805 | 0.398 | 1.0 | 0.6458 | 10342 | 6 | 0.3693 | 1.0 | 3.0 | 3 |
| three_ray4 | 6090 | 0 | 6745 | 3553 | 0.6315 | 1.0 | 0.7832 | 6276 | 6 | 0.6174 | 1.0 | 3.623 | 4 |
| three_ray > same_ray | 9413 | 0 | 6745 | 230 | 0.9761 | 1.0 | 0.986 | 270 | 6 | 0.9839 | 1.0 | 4.87 | 6 |
| three_ray4 > same_ray | 9519 | 0 | 6745 | 124 | 0.9871 | 1.0 | 0.9924 | 137 | 6 | 0.992 | 1.0 | 4.749 | 7 |
| same_ray > three_ray4 | 9518 | 2 | 6743 | 125 | 0.987 | 0.9997 | 0.9923 | 137 | 6 | 0.992 | 0.9998 | 4.043 | 7 |
| three_ray4 > direction | 9512 | 1 | 6744 | 131 | 0.9864 | 0.9999 | 0.9919 | 124 | 6 | 0.9925 | 0.9994 | 3.623 | 4 |
| same_ray > direction | 9471 | 6 | 6739 | 172 | 0.9822 | 0.9991 | 0.9891 | 124 | 6 | 0.9925 | 0.9966 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 9519 | 0 | 6745 | 124 | 0.9871 | 1.0 | 0.9924 | 124 | 6 | 0.9925 | 0.9999 | 4.749 | 7 |

### SWI 0.9.1 HF (21,436 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 12851 | 8386 | 0 | 0 | 1.0 | 0.0 | 0.6051 | 0 | 199 | 1.0 | 0.6051 | 0.0 | 0 |
| direction | 12368 | 55 | 8331 | 483 | 0.9624 | 0.9934 | 0.9747 | 241 | 199 | 0.9896 | 0.9849 | 1.0 | 1 |
| same_ray | 12287 | 0 | 8386 | 564 | 0.9561 | 1.0 | 0.9734 | 1007 | 199 | 0.9617 | 0.9999 | 3.977 | 4 |
| three_ray | 4984 | 0 | 8386 | 7867 | 0.3878 | 1.0 | 0.6296 | 13818 | 199 | 0.3586 | 0.9996 | 3.0 | 3 |
| three_ray4 | 8060 | 0 | 8386 | 4791 | 0.6272 | 1.0 | 0.7744 | 8445 | 199 | 0.6116 | 0.9998 | 3.631 | 4 |
| three_ray > same_ray | 12498 | 0 | 8386 | 353 | 0.9725 | 1.0 | 0.9834 | 636 | 199 | 0.979 | 0.9999 | 4.911 | 6 |
| three_ray4 > same_ray | 12644 | 0 | 8386 | 207 | 0.9839 | 1.0 | 0.9903 | 433 | 199 | 0.9886 | 0.9999 | 4.79 | 7 |
| same_ray > three_ray4 | 12641 | 0 | 8386 | 210 | 0.9837 | 1.0 | 0.9901 | 433 | 199 | 0.9886 | 0.9997 | 4.087 | 7 |
| three_ray4 > direction | 12620 | 19 | 8367 | 231 | 0.982 | 0.9977 | 0.9882 | 204 | 199 | 0.9913 | 0.9969 | 3.631 | 4 |
| same_ray > direction | 12619 | 21 | 8365 | 232 | 0.9819 | 0.9975 | 0.9881 | 186 | 199 | 0.9922 | 0.9959 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 12684 | 5 | 8381 | 167 | 0.987 | 0.9994 | 0.9919 | 175 | 199 | 0.9927 | 0.9992 | 4.79 | 7 |

### Feasible/realistic (34,662 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 19887 | 14646 | 0 | 0 | 1.0 | 0.0 | 0.5759 | 0 | 129 | 1.0 | 0.5759 | 0.0 | 0 |
| direction | 19596 | 75 | 14571 | 291 | 0.9854 | 0.9949 | 0.9894 | 48 | 129 | 0.9988 | 0.9905 | 1.0 | 1 |
| same_ray | 19715 | 2 | 14644 | 172 | 0.9914 | 0.9999 | 0.995 | 522 | 129 | 0.9886 | 0.9999 | 4.0 | 4 |
| three_ray | 7173 | 0 | 14646 | 12714 | 0.3607 | 1.0 | 0.6318 | 22959 | 129 | 0.3389 | 1.0 | 3.0 | 3 |
| three_ray4 | 12268 | 0 | 14646 | 7619 | 0.6169 | 1.0 | 0.7794 | 13801 | 129 | 0.6041 | 1.0 | 3.66 | 4 |
| three_ray > same_ray | 19823 | 0 | 14646 | 64 | 0.9968 | 1.0 | 0.9981 | 267 | 129 | 0.9959 | 1.0 | 4.987 | 6 |
| three_ray4 > same_ray | 19842 | 0 | 14646 | 45 | 0.9977 | 1.0 | 0.9987 | 212 | 129 | 0.9975 | 1.0 | 4.854 | 7 |
| same_ray > three_ray4 | 19842 | 2 | 14644 | 45 | 0.9977 | 0.9999 | 0.9986 | 212 | 129 | 0.9975 | 0.9999 | 4.035 | 7 |
| three_ray4 > direction | 19819 | 20 | 14626 | 68 | 0.9966 | 0.9986 | 0.9975 | 32 | 129 | 0.9993 | 0.9981 | 3.66 | 4 |
| same_ray > direction | 19808 | 26 | 14620 | 79 | 0.996 | 0.9982 | 0.997 | 10 | 129 | 0.9999 | 0.997 | 4.0 | 4 |
| three_ray4 > same_ray > direction | 19877 | 5 | 14641 | 10 | 0.9995 | 0.9997 | 0.9996 | 9 | 129 | 1.0 | 0.9996 | 4.854 | 7 |

### Synthetic stress (3,168 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 2607 | 485 | 0 | 0 | 1.0 | 0.0 | 0.8431 | 0 | 76 | 1.0 | 0.8431 | 0.0 | 0 |
| direction | 2126 | 1 | 484 | 481 | 0.8155 | 0.9979 | 0.8441 | 317 | 76 | 0.9017 | 0.9362 | 1.0 | 1 |
| same_ray | 1844 | 0 | 485 | 763 | 0.7073 | 1.0 | 0.7532 | 955 | 76 | 0.7144 | 0.9982 | 3.727 | 4 |
| three_ray | 1649 | 0 | 485 | 958 | 0.6325 | 1.0 | 0.6902 | 1201 | 76 | 0.6352 | 0.9985 | 3.0 | 3 |
| three_ray4 | 1882 | 0 | 485 | 725 | 0.7219 | 1.0 | 0.7655 | 920 | 76 | 0.7261 | 0.9987 | 3.273 | 4 |
| three_ray > same_ray | 2088 | 0 | 485 | 519 | 0.8009 | 1.0 | 0.8321 | 639 | 76 | 0.8157 | 0.9988 | 3.865 | 6 |
| three_ray4 > same_ray | 2321 | 0 | 485 | 286 | 0.8903 | 1.0 | 0.9075 | 358 | 76 | 0.9065 | 0.9989 | 3.871 | 7 |
| same_ray > three_ray4 | 2317 | 0 | 485 | 290 | 0.8888 | 1.0 | 0.9062 | 358 | 76 | 0.9065 | 0.9975 | 4.427 | 7 |
| three_ray4 > direction | 2313 | 0 | 485 | 294 | 0.8872 | 1.0 | 0.9049 | 296 | 76 | 0.9085 | 0.9961 | 3.273 | 4 |
| same_ray > direction | 2282 | 1 | 484 | 325 | 0.8753 | 0.9979 | 0.8946 | 300 | 76 | 0.9072 | 0.9861 | 3.727 | 4 |
| three_ray4 > same_ray > direction | 2326 | 0 | 485 | 281 | 0.8922 | 1.0 | 0.9091 | 290 | 76 | 0.9104 | 0.9986 | 3.871 | 7 |

### Conventional (33,077 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 19551 | 13321 | 0 | 0 | 1.0 | 0.0 | 0.5948 | 0 | 205 | 1.0 | 0.5948 | 0.0 | 0 |
| direction | 18845 | 71 | 13250 | 706 | 0.9639 | 0.9947 | 0.9764 | 329 | 205 | 0.9906 | 0.9856 | 1.0 | 1 |
| same_ray | 18722 | 2 | 13319 | 829 | 0.9576 | 0.9998 | 0.9747 | 1353 | 205 | 0.9649 | 0.9998 | 3.977 | 4 |
| three_ray | 7686 | 0 | 13321 | 11865 | 0.3931 | 1.0 | 0.6391 | 21125 | 205 | 0.3635 | 0.9997 | 3.0 | 3 |
| three_ray4 | 12313 | 0 | 13321 | 7238 | 0.6298 | 1.0 | 0.7798 | 12880 | 205 | 0.6143 | 0.9999 | 3.627 | 4 |
| three_ray > same_ray | 19035 | 0 | 13321 | 516 | 0.9736 | 1.0 | 0.9843 | 830 | 205 | 0.9807 | 0.9999 | 4.893 | 6 |
| three_ray4 > same_ray | 19256 | 0 | 13321 | 295 | 0.9849 | 1.0 | 0.991 | 533 | 205 | 0.9897 | 0.9999 | 4.772 | 7 |
| same_ray > three_ray4 | 19253 | 2 | 13319 | 298 | 0.9848 | 0.9998 | 0.9909 | 533 | 205 | 0.9897 | 0.9998 | 4.072 | 7 |
| three_ray4 > direction | 19226 | 20 | 13301 | 325 | 0.9834 | 0.9985 | 0.9895 | 292 | 205 | 0.9918 | 0.9977 | 3.627 | 4 |
| same_ray > direction | 19194 | 27 | 13294 | 357 | 0.9817 | 0.998 | 0.9883 | 274 | 205 | 0.9923 | 0.996 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 19296 | 5 | 13316 | 255 | 0.987 | 0.9996 | 0.9921 | 263 | 205 | 0.9926 | 0.9994 | 4.772 | 7 |

### Guided (2,637 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 1715 | 922 | 0 | 0 | 1.0 | 0.0 | 0.6504 | 0 | 0 | 1.0 | 0.6504 | 0.0 | 0 |
| direction | 1685 | 3 | 919 | 30 | 0.9825 | 0.9967 | 0.9875 | 20 | 0 | 0.9924 | 0.995 | 1.0 | 1 |
| same_ray | 1656 | 0 | 922 | 59 | 0.9656 | 1.0 | 0.9776 | 69 | 0 | 0.9738 | 1.0 | 3.977 | 4 |
| three_ray | 644 | 0 | 922 | 1071 | 0.3755 | 1.0 | 0.5939 | 1704 | 0 | 0.3538 | 1.0 | 3.0 | 3 |
| three_ray4 | 1058 | 0 | 922 | 657 | 0.6169 | 1.0 | 0.7509 | 1029 | 0 | 0.6098 | 1.0 | 3.639 | 4 |
| three_ray > same_ray | 1676 | 0 | 922 | 39 | 0.9773 | 1.0 | 0.9852 | 43 | 0 | 0.9837 | 1.0 | 4.916 | 6 |
| three_ray4 > same_ray | 1695 | 0 | 922 | 20 | 0.9883 | 1.0 | 0.9924 | 20 | 0 | 0.9924 | 1.0 | 4.786 | 7 |
| same_ray > three_ray4 | 1695 | 0 | 922 | 20 | 0.9883 | 1.0 | 0.9924 | 20 | 0 | 0.9924 | 1.0 | 4.038 | 7 |
| three_ray4 > direction | 1695 | 0 | 922 | 20 | 0.9883 | 1.0 | 0.9924 | 20 | 0 | 0.9924 | 1.0 | 3.639 | 4 |
| same_ray > direction | 1690 | 0 | 922 | 25 | 0.9854 | 1.0 | 0.9905 | 20 | 0 | 0.9924 | 0.9981 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 1695 | 0 | 922 | 20 | 0.9883 | 1.0 | 0.9924 | 20 | 0 | 0.9924 | 1.0 | 4.786 | 7 |

### Dumb-fire (2,116 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 1228 | 888 | 0 | 0 | 1.0 | 0.0 | 0.5803 | 0 | 0 | 1.0 | 0.5803 | 0.0 | 0 |
| direction | 1192 | 2 | 886 | 36 | 0.9707 | 0.9977 | 0.982 | 16 | 0 | 0.9924 | 0.9895 | 1.0 | 1 |
| same_ray | 1181 | 0 | 888 | 47 | 0.9617 | 1.0 | 0.9778 | 55 | 0 | 0.974 | 0.9995 | 3.977 | 4 |
| three_ray | 492 | 0 | 888 | 736 | 0.4007 | 1.0 | 0.6522 | 1331 | 0 | 0.371 | 1.0 | 3.0 | 3 |
| three_ray4 | 779 | 0 | 888 | 449 | 0.6344 | 1.0 | 0.7878 | 812 | 0 | 0.6163 | 1.0 | 3.621 | 4 |
| three_ray > same_ray | 1200 | 0 | 888 | 28 | 0.9772 | 1.0 | 0.9868 | 33 | 0 | 0.9844 | 1.0 | 4.864 | 6 |
| three_ray4 > same_ray | 1212 | 0 | 888 | 16 | 0.987 | 1.0 | 0.9924 | 17 | 0 | 0.992 | 1.0 | 4.75 | 7 |
| same_ray > three_ray4 | 1211 | 0 | 888 | 17 | 0.9862 | 1.0 | 0.992 | 17 | 0 | 0.992 | 0.9995 | 4.037 | 7 |
| three_ray4 > direction | 1211 | 0 | 888 | 17 | 0.9862 | 1.0 | 0.992 | 16 | 0 | 0.9924 | 0.9995 | 3.621 | 4 |
| same_ray > direction | 1206 | 0 | 888 | 22 | 0.9821 | 1.0 | 0.9896 | 16 | 0 | 0.9924 | 0.9971 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 1212 | 0 | 888 | 16 | 0.987 | 1.0 | 0.9924 | 16 | 0 | 0.9924 | 1.0 | 4.75 | 7 |

### Ordinary X/Y (36,523 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 21887 | 14446 | 0 | 0 | 1.0 | 0.0 | 0.6024 | 0 | 190 | 1.0 | 0.6024 | 0.0 | 0 |
| direction | 21235 | 76 | 14370 | 652 | 0.9702 | 0.9947 | 0.98 | 278 | 190 | 0.9926 | 0.9872 | 1.0 | 1 |
| same_ray | 20987 | 2 | 14444 | 900 | 0.9589 | 0.9999 | 0.9752 | 1391 | 190 | 0.9668 | 0.9998 | 3.977 | 4 |
| three_ray | 8586 | 0 | 14446 | 13301 | 0.3923 | 1.0 | 0.6339 | 23308 | 190 | 0.3636 | 0.9998 | 3.0 | 3 |
| three_ray4 | 13768 | 0 | 14446 | 8119 | 0.629 | 1.0 | 0.7765 | 14203 | 190 | 0.6142 | 0.9999 | 3.627 | 4 |
| three_ray > same_ray | 21322 | 0 | 14446 | 565 | 0.9742 | 1.0 | 0.9844 | 862 | 190 | 0.9813 | 0.9999 | 4.892 | 6 |
| three_ray4 > same_ray | 21566 | 0 | 14446 | 321 | 0.9853 | 1.0 | 0.9912 | 539 | 190 | 0.9901 | 0.9999 | 4.771 | 7 |
| same_ray > three_ray4 | 21562 | 2 | 14444 | 325 | 0.9852 | 0.9999 | 0.991 | 539 | 190 | 0.9901 | 0.9997 | 4.066 | 7 |
| three_ray4 > direction | 21568 | 20 | 14426 | 319 | 0.9854 | 0.9986 | 0.9907 | 278 | 190 | 0.9926 | 0.998 | 3.627 | 4 |
| same_ray > direction | 21512 | 27 | 14419 | 375 | 0.9829 | 0.9981 | 0.9889 | 278 | 190 | 0.9926 | 0.9963 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 21606 | 5 | 14441 | 281 | 0.9872 | 0.9997 | 0.9921 | 278 | 190 | 0.9926 | 0.9995 | 4.771 | 7 |

### Bounded traverse (1,046 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 579 | 457 | 0 | 0 | 1.0 | 0.0 | 0.5589 | 0 | 10 | 1.0 | 0.5589 | 0.0 | 0 |
| direction | 471 | 0 | 457 | 108 | 0.8135 | 1.0 | 0.8958 | 85 | 10 | 0.9276 | 0.9657 | 1.0 | 1 |
| same_ray | 548 | 0 | 457 | 31 | 0.9465 | 1.0 | 0.9701 | 63 | 10 | 0.9488 | 1.0 | 3.977 | 4 |
| three_ray | 218 | 0 | 457 | 361 | 0.3765 | 1.0 | 0.6515 | 683 | 10 | 0.3504 | 1.0 | 3.0 | 3 |
| three_ray4 | 360 | 0 | 457 | 219 | 0.6218 | 1.0 | 0.7886 | 418 | 10 | 0.6062 | 1.0 | 3.638 | 4 |
| three_ray > same_ray | 562 | 0 | 457 | 17 | 0.9706 | 1.0 | 0.9836 | 35 | 10 | 0.9759 | 1.0 | 4.936 | 6 |
| three_ray4 > same_ray | 570 | 0 | 457 | 9 | 0.9845 | 1.0 | 0.9913 | 24 | 10 | 0.9865 | 1.0 | 4.814 | 7 |
| same_ray > three_ray4 | 570 | 0 | 457 | 9 | 0.9845 | 1.0 | 0.9913 | 24 | 10 | 0.9865 | 1.0 | 4.116 | 7 |
| three_ray4 > direction | 537 | 0 | 457 | 42 | 0.9275 | 1.0 | 0.9595 | 48 | 10 | 0.9633 | 0.996 | 3.638 | 4 |
| same_ray > direction | 554 | 0 | 457 | 25 | 0.9568 | 1.0 | 0.9759 | 30 | 10 | 0.9807 | 0.9951 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 570 | 0 | 457 | 9 | 0.9845 | 1.0 | 0.9913 | 19 | 10 | 0.9913 | 1.0 | 4.814 | 7 |

### Reversed X/Y (130 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 21 | 109 | 0 | 0 | 1.0 | 0.0 | 0.1615 | 0 | 0 | 1.0 | 0.1615 | 0.0 | 0 |
| direction | 14 | 0 | 109 | 7 | 0.6667 | 1.0 | 0.9462 | 1 | 0 | 0.9923 | 0.9535 | 1.0 | 1 |
| same_ray | 20 | 0 | 109 | 1 | 0.9524 | 1.0 | 0.9923 | 8 | 0 | 0.9385 | 1.0 | 3.977 | 4 |
| three_ray | 13 | 0 | 109 | 8 | 0.619 | 1.0 | 0.9385 | 80 | 0 | 0.3846 | 1.0 | 3.0 | 3 |
| three_ray4 | 16 | 0 | 109 | 5 | 0.7619 | 1.0 | 0.9615 | 48 | 0 | 0.6308 | 1.0 | 3.608 | 4 |
| three_ray > same_ray | 20 | 0 | 109 | 1 | 0.9524 | 1.0 | 0.9923 | 3 | 0 | 0.9769 | 1.0 | 4.823 | 6 |
| three_ray4 > same_ray | 20 | 0 | 109 | 1 | 0.9524 | 1.0 | 0.9923 | 2 | 0 | 0.9846 | 1.0 | 4.692 | 7 |
| same_ray > three_ray4 | 20 | 0 | 109 | 1 | 0.9524 | 1.0 | 0.9923 | 2 | 0 | 0.9846 | 1.0 | 4.115 | 7 |
| three_ray4 > direction | 20 | 0 | 109 | 1 | 0.9524 | 1.0 | 0.9923 | 1 | 0 | 0.9923 | 1.0 | 3.608 | 4 |
| same_ray > direction | 20 | 0 | 109 | 1 | 0.9524 | 1.0 | 0.9923 | 1 | 0 | 0.9923 | 1.0 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 20 | 0 | 109 | 1 | 0.9524 | 1.0 | 0.9923 | 1 | 0 | 0.9923 | 1.0 | 4.692 | 7 |

### Rotation-Z (131 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 7 | 119 | 0 | 0 | 1.0 | 0.0 | 0.0556 | 0 | 5 | 1.0 | 0.0556 | 0.0 | 0 |
| direction | 2 | 0 | 119 | 5 | 0.2857 | 1.0 | 0.9603 | 1 | 5 | 1.0 | 0.9603 | 1.0 | 1 |
| same_ray | 4 | 0 | 119 | 3 | 0.5714 | 1.0 | 0.9762 | 15 | 5 | 0.9206 | 1.0 | 3.977 | 4 |
| three_ray | 5 | 0 | 119 | 2 | 0.7143 | 1.0 | 0.9841 | 89 | 5 | 0.3333 | 1.0 | 3.0 | 3 |
| three_ray4 | 6 | 0 | 119 | 1 | 0.8571 | 1.0 | 0.9921 | 52 | 5 | 0.627 | 1.0 | 3.649 | 4 |
| three_ray > same_ray | 7 | 0 | 119 | 0 | 1.0 | 1.0 | 1.0 | 6 | 5 | 0.9921 | 1.0 | 5.015 | 6 |
| three_ray4 > same_ray | 7 | 0 | 119 | 0 | 1.0 | 1.0 | 1.0 | 5 | 5 | 1.0 | 1.0 | 4.817 | 7 |
| same_ray > three_ray4 | 7 | 0 | 119 | 0 | 1.0 | 1.0 | 1.0 | 5 | 5 | 1.0 | 1.0 | 4.221 | 7 |
| three_ray4 > direction | 7 | 0 | 119 | 0 | 1.0 | 1.0 | 1.0 | 1 | 5 | 1.0 | 1.0 | 3.649 | 4 |
| same_ray > direction | 4 | 0 | 119 | 3 | 0.5714 | 1.0 | 0.9762 | 1 | 5 | 1.0 | 0.9762 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 7 | 0 | 119 | 0 | 1.0 | 1.0 | 1.0 | 1 | 5 | 1.0 | 1.0 | 4.817 | 7 |

## Observed group differences

Expanded ordinary/official behavior is broadly consistent with historical A4 in showing few decided false-ENGAGEABLE results for same-ray and three-ray methods, while the changed corpus and exposure design produce different aggregate coverage and accuracy.

The rare classes are not hidden by the 36,523 nominal ordinary-X/Y rows. Bounded-traverse direction has 108 false-NOT-ENGAGEABLE rows (UNKNOWN counted as NOT ENGAGEABLE) and 85 prediction-UNKNOWN rows among 1,046 rows; same-ray has 31 false-NOT-ENGAGEABLE and 63 prediction-UNKNOWN. The reversed-X/Y turret has only 21 truth-ENGAGEABLE rows among 130, and direction identifies 14 of them as ENGAGEABLE. The rotation-Z turret has 7 truth-ENGAGEABLE rows among 126 truth-known rows; direction identifies 2.

Known172 exposure is the largest prediction-UNKNOWN concentration for three-ray and three-ray4. Synthetic stress is the main concentration for direction and same-ray UNKNOWN behavior. These are failure groups for A5, not cause classifications.

## Failure groups for later A5 analysis

- `baseline`: 15131 truth-known wrong/UNKNOWN rows.
  - 4871: wrong, ordinary_xy, swi, conventional_gun, known172
  - 3074: wrong, ordinary_xy, official, conventional_gun, known172
  - 1277: wrong, ordinary_xy, swi, conventional_gun, single-point
  - 905: wrong, ordinary_xy, official, conventional_gun, single-point
  - 898: wrong, ordinary_xy, swi, conventional_gun, boundary
- `direction`: 848 truth-known wrong/UNKNOWN rows.
  - 141: UNKNOWN, ordinary_xy, swi, conventional_gun, synthetic
  - 91: UNKNOWN, ordinary_xy, official, conventional_gun, synthetic
  - 88: wrong, ordinary_xy, swi, conventional_gun, known172
  - 88: wrong, ordinary_xy, official, conventional_gun, synthetic
  - 85: wrong, ordinary_xy, swi, conventional_gun, single-point
- `same_ray`: 1284 truth-known wrong/UNKNOWN rows.
  - 458: UNKNOWN, ordinary_xy, swi, conventional_gun, synthetic
  - 286: UNKNOWN, ordinary_xy, official, conventional_gun, synthetic
  - 87: UNKNOWN, ordinary_xy, swi, conventional_gun, known172
  - 84: UNKNOWN, ordinary_xy, swi, conventional_gun, single-point
  - 77: UNKNOWN, ordinary_xy, swi, conventional_gun, boundary
- `three_ray`: 23961 truth-known wrong/UNKNOWN rows.
  - 11073: UNKNOWN, ordinary_xy, swi, conventional_gun, known172
  - 6808: UNKNOWN, ordinary_xy, official, conventional_gun, known172
  - 1184: UNKNOWN, ordinary_xy, official, dumbfire_missile, known172
  - 1184: UNKNOWN, ordinary_xy, official, guided_missile, known172
  - 783: UNKNOWN, ordinary_xy, swi, conventional_gun, boundary
- `three_ray4`: 14522 truth-known wrong/UNKNOWN rows.
  - 6734: UNKNOWN, ordinary_xy, swi, conventional_gun, known172
  - 4140: UNKNOWN, ordinary_xy, official, conventional_gun, known172
  - 720: UNKNOWN, ordinary_xy, official, dumbfire_missile, known172
  - 720: UNKNOWN, ordinary_xy, official, guided_missile, known172
  - 436: UNKNOWN, ordinary_xy, swi, conventional_gun, synthetic

Truth-UNKNOWN patterns:

- 188: `ordinary_xy` / `UNKNOWN_none_trap`
- 10: `bounded_traverse` / `UNKNOWN_root_limit_unwrap`
- 5: `rotation_z` / `UNKNOWN_none_trap`
- 2: `ordinary_xy` / `UNKNOWN_one_trap`

## Limitations

The selected A4x endpoint/reference pose is the offline coordinate definition. This run does not provide new live proof of emitted-muzzle runtime behavior. It also excludes range, line of sight, own-hull masking, projectile flight, missile guidance, and firing readiness.
