# Expanded A4 ENGAGEABLE benchmark findings

Status: **inference**, offline mechanical bearing/arc benchmark evidence. This task does not classify A5 failure causes or select a production method.

Accepted starting scorer SHA: `4dafbf0a9211610d007996facaf40c5ca30ca220`.

The run contains 37,830 turret/scenario cases and 113,490 rows across rough-distance factors 0.5, 1, and 2. Nominal factor 1 contributes 37,830 rows. Single-point, multi-point, and boundary scenarios independently assign sorted turrets round-robin (6,990, 1,800, and 4,560 cases). All 74 known172 scenarios and all 11 synthetic stress scenarios run against all 288 turrets (21,312 and 3,168 cases). The existing 24 component rotations cycle deterministically within each subgroup and Cartesian expansion.

Each scenario/factor computes its direction, same-ray, three-ray, and three-ray4 query observations once. Turret scoring then places the selected reference endpoint at O using the record's ordered transforms and nearest-to-zero legal joint pose.

Truth UNKNOWN rows are excluded from TP/FP/TN/FN rates. Prediction UNKNOWN is counted as player-view NOT ENGAGEABLE in ordinary sensitivity and accuracy, and is also reported separately.

## Rough-distance sensitivity, all 288 turrets

### Rough factor 0.5

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 22176 | 15452 | 0 | 0 | 1.0 | 0.0 | 0.5893 | 0 | 202 | 1.0 | 0.5893 | 0.0 | 0 |
| direction | 21437 | 76 | 15376 | 739 | 0.9667 | 0.9951 | 0.9783 | 356 | 202 | 0.991 | 0.9872 | 1.0 | 1 |
| same_ray | 21525 | 2 | 15450 | 651 | 0.9706 | 0.9999 | 0.9826 | 1162 | 202 | 0.9742 | 0.9999 | 3.977 | 4 |
| three_ray | 10940 | 0 | 15452 | 11236 | 0.4933 | 1.0 | 0.7014 | 19349 | 202 | 0.4911 | 0.9999 | 3.0 | 3 |
| three_ray4 | 14210 | 0 | 15452 | 7966 | 0.6408 | 1.0 | 0.7883 | 13785 | 202 | 0.6389 | 0.9999 | 3.5 | 4 |
| three_ray > same_ray | 21778 | 0 | 15452 | 398 | 0.9821 | 1.0 | 0.9894 | 658 | 202 | 0.9875 | 0.9999 | 4.512 | 6 |
| three_ray4 > same_ray | 21807 | 0 | 15452 | 369 | 0.9834 | 1.0 | 0.9902 | 600 | 202 | 0.9891 | 0.9999 | 4.57 | 7 |
| same_ray > three_ray4 | 21807 | 2 | 15450 | 369 | 0.9834 | 0.9999 | 0.9901 | 600 | 202 | 0.9891 | 0.9999 | 4.045 | 7 |
| three_ray4 > direction | 21808 | 17 | 15435 | 368 | 0.9834 | 0.9989 | 0.9898 | 324 | 202 | 0.9919 | 0.9979 | 3.5 | 4 |
| same_ray > direction | 21625 | 50 | 15402 | 551 | 0.9752 | 0.9968 | 0.984 | 343 | 202 | 0.9914 | 0.9926 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 21836 | 13 | 15439 | 340 | 0.9847 | 0.9992 | 0.9906 | 322 | 202 | 0.9919 | 0.9987 | 4.57 | 7 |

### Rough factor 1

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 22176 | 15452 | 0 | 0 | 1.0 | 0.0 | 0.5893 | 0 | 202 | 1.0 | 0.5893 | 0.0 | 0 |
| direction | 21437 | 76 | 15376 | 739 | 0.9667 | 0.9951 | 0.9783 | 356 | 202 | 0.991 | 0.9872 | 1.0 | 1 |
| same_ray | 21236 | 2 | 15450 | 940 | 0.9576 | 0.9999 | 0.975 | 1464 | 202 | 0.9663 | 0.9999 | 3.977 | 4 |
| three_ray | 8423 | 0 | 15452 | 13753 | 0.3798 | 1.0 | 0.6345 | 24156 | 202 | 0.3633 | 0.9999 | 3.0 | 3 |
| three_ray4 | 13812 | 0 | 15452 | 8364 | 0.6228 | 1.0 | 0.7777 | 14722 | 202 | 0.614 | 0.9999 | 3.627 | 4 |
| three_ray > same_ray | 21601 | 0 | 15452 | 575 | 0.9741 | 1.0 | 0.9847 | 866 | 202 | 0.9821 | 0.9999 | 4.893 | 6 |
| three_ray4 > same_ray | 21858 | 0 | 15452 | 318 | 0.9857 | 1.0 | 0.9915 | 537 | 202 | 0.9909 | 0.9999 | 4.772 | 7 |
| same_ray > three_ray4 | 21856 | 2 | 15450 | 320 | 0.9856 | 0.9999 | 0.9914 | 537 | 202 | 0.9909 | 0.9998 | 4.066 | 7 |
| three_ray4 > direction | 21820 | 20 | 15432 | 356 | 0.9839 | 0.9987 | 0.99 | 323 | 202 | 0.9919 | 0.9981 | 3.627 | 4 |
| same_ray > direction | 21785 | 22 | 15430 | 391 | 0.9824 | 0.9986 | 0.989 | 302 | 202 | 0.9925 | 0.9965 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 21888 | 4 | 15448 | 288 | 0.987 | 0.9997 | 0.9922 | 295 | 202 | 0.9926 | 0.9996 | 4.772 | 7 |

### Rough factor 2

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 22176 | 15452 | 0 | 0 | 1.0 | 0.0 | 0.5893 | 0 | 202 | 1.0 | 0.5893 | 0.0 | 0 |
| direction | 21437 | 76 | 15376 | 739 | 0.9667 | 0.9951 | 0.9783 | 356 | 202 | 0.991 | 0.9872 | 1.0 | 1 |
| same_ray | 13595 | 1 | 15451 | 8581 | 0.6131 | 0.9999 | 0.7719 | 14238 | 202 | 0.6268 | 0.9999 | 3.977 | 4 |
| three_ray | 8351 | 0 | 15452 | 13825 | 0.3766 | 1.0 | 0.6326 | 24283 | 202 | 0.3599 | 0.9999 | 3.0 | 3 |
| three_ray4 | 12690 | 0 | 15452 | 9486 | 0.5722 | 1.0 | 0.7479 | 16864 | 202 | 0.5571 | 0.9999 | 3.631 | 4 |
| three_ray > same_ray | 19609 | 0 | 15452 | 2567 | 0.8842 | 1.0 | 0.9318 | 4268 | 202 | 0.8917 | 0.9999 | 4.903 | 6 |
| three_ray4 > same_ray | 20538 | 0 | 15452 | 1638 | 0.9261 | 1.0 | 0.9565 | 2703 | 202 | 0.9333 | 0.9999 | 4.945 | 7 |
| same_ray > three_ray4 | 20536 | 1 | 15451 | 1640 | 0.926 | 0.9999 | 0.9564 | 2703 | 202 | 0.9333 | 0.9999 | 4.832 | 7 |
| three_ray4 > direction | 21812 | 30 | 15422 | 364 | 0.9836 | 0.9981 | 0.9895 | 324 | 202 | 0.9919 | 0.9976 | 3.631 | 4 |
| same_ray > direction | 21629 | 45 | 15407 | 547 | 0.9753 | 0.9971 | 0.9843 | 313 | 202 | 0.9922 | 0.992 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 21872 | 9 | 15443 | 304 | 0.9863 | 0.9994 | 0.9917 | 296 | 202 | 0.9926 | 0.9991 | 4.945 | 7 |

## Nominal result by reporting dimension

### Combined all 288 turrets (37,830 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 22176 | 15452 | 0 | 0 | 1.0 | 0.0 | 0.5893 | 0 | 202 | 1.0 | 0.5893 | 0.0 | 0 |
| direction | 21437 | 76 | 15376 | 739 | 0.9667 | 0.9951 | 0.9783 | 356 | 202 | 0.991 | 0.9872 | 1.0 | 1 |
| same_ray | 21236 | 2 | 15450 | 940 | 0.9576 | 0.9999 | 0.975 | 1464 | 202 | 0.9663 | 0.9999 | 3.977 | 4 |
| three_ray | 8423 | 0 | 15452 | 13753 | 0.3798 | 1.0 | 0.6345 | 24156 | 202 | 0.3633 | 0.9999 | 3.0 | 3 |
| three_ray4 | 13812 | 0 | 15452 | 8364 | 0.6228 | 1.0 | 0.7777 | 14722 | 202 | 0.614 | 0.9999 | 3.627 | 4 |
| three_ray > same_ray | 21601 | 0 | 15452 | 575 | 0.9741 | 1.0 | 0.9847 | 866 | 202 | 0.9821 | 0.9999 | 4.893 | 6 |
| three_ray4 > same_ray | 21858 | 0 | 15452 | 318 | 0.9857 | 1.0 | 0.9915 | 537 | 202 | 0.9909 | 0.9999 | 4.772 | 7 |
| same_ray > three_ray4 | 21856 | 2 | 15450 | 320 | 0.9856 | 0.9999 | 0.9914 | 537 | 202 | 0.9909 | 0.9998 | 4.066 | 7 |
| three_ray4 > direction | 21820 | 20 | 15432 | 356 | 0.9839 | 0.9987 | 0.99 | 323 | 202 | 0.9919 | 0.9981 | 3.627 | 4 |
| same_ray > direction | 21785 | 22 | 15430 | 391 | 0.9824 | 0.9986 | 0.989 | 302 | 202 | 0.9925 | 0.9965 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 21888 | 4 | 15448 | 288 | 0.987 | 0.9997 | 0.9922 | 295 | 202 | 0.9926 | 0.9996 | 4.772 | 7 |

### Official X4 (16,394 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 9553 | 6829 | 0 | 0 | 1.0 | 0.0 | 0.5831 | 0 | 12 | 1.0 | 0.5831 | 0.0 | 0 |
| direction | 9293 | 25 | 6804 | 260 | 0.9728 | 0.9963 | 0.9826 | 124 | 12 | 0.9925 | 0.99 | 1.0 | 1 |
| same_ray | 9190 | 0 | 6829 | 363 | 0.962 | 1.0 | 0.9778 | 476 | 12 | 0.9717 | 1.0 | 3.977 | 4 |
| three_ray | 3712 | 0 | 6829 | 5841 | 0.3886 | 1.0 | 0.6435 | 10345 | 12 | 0.3692 | 1.0 | 3.0 | 3 |
| three_ray4 | 6006 | 0 | 6829 | 3547 | 0.6287 | 1.0 | 0.7835 | 6280 | 12 | 0.6174 | 1.0 | 3.623 | 4 |
| three_ray > same_ray | 9320 | 0 | 6829 | 233 | 0.9756 | 1.0 | 0.9858 | 271 | 12 | 0.9842 | 1.0 | 4.87 | 6 |
| three_ray4 > same_ray | 9425 | 0 | 6829 | 128 | 0.9866 | 1.0 | 0.9922 | 142 | 12 | 0.9921 | 1.0 | 4.749 | 7 |
| same_ray > three_ray4 | 9425 | 0 | 6829 | 128 | 0.9866 | 1.0 | 0.9922 | 142 | 12 | 0.9921 | 1.0 | 4.044 | 7 |
| three_ray4 > direction | 9420 | 2 | 6827 | 133 | 0.9861 | 0.9997 | 0.9918 | 124 | 12 | 0.9925 | 0.9993 | 3.623 | 4 |
| same_ray > direction | 9397 | 3 | 6826 | 156 | 0.9837 | 0.9996 | 0.9903 | 124 | 12 | 0.9925 | 0.9978 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 9428 | 1 | 6828 | 125 | 0.9869 | 0.9999 | 0.9923 | 124 | 12 | 0.9925 | 0.9998 | 4.749 | 7 |

### SWI 0.9.1 HF (21,436 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 12623 | 8623 | 0 | 0 | 1.0 | 0.0 | 0.5941 | 0 | 190 | 1.0 | 0.5941 | 0.0 | 0 |
| direction | 12144 | 51 | 8572 | 479 | 0.9621 | 0.9941 | 0.9751 | 232 | 190 | 0.9899 | 0.985 | 1.0 | 1 |
| same_ray | 12046 | 2 | 8621 | 577 | 0.9543 | 0.9998 | 0.9727 | 988 | 190 | 0.9622 | 0.9998 | 3.977 | 4 |
| three_ray | 4711 | 0 | 8623 | 7912 | 0.3732 | 1.0 | 0.6276 | 13811 | 190 | 0.3587 | 0.9997 | 3.0 | 3 |
| three_ray4 | 7806 | 0 | 8623 | 4817 | 0.6184 | 1.0 | 0.7733 | 8442 | 190 | 0.6115 | 0.9998 | 3.631 | 4 |
| three_ray > same_ray | 12281 | 0 | 8623 | 342 | 0.9729 | 1.0 | 0.9839 | 595 | 190 | 0.9805 | 0.9999 | 4.91 | 6 |
| three_ray4 > same_ray | 12433 | 0 | 8623 | 190 | 0.9849 | 1.0 | 0.9911 | 395 | 190 | 0.9899 | 0.9999 | 4.789 | 7 |
| same_ray > three_ray4 | 12431 | 2 | 8621 | 192 | 0.9848 | 0.9998 | 0.9909 | 395 | 190 | 0.9899 | 0.9997 | 4.084 | 7 |
| three_ray4 > direction | 12400 | 18 | 8605 | 223 | 0.9823 | 0.9979 | 0.9887 | 199 | 190 | 0.9914 | 0.9972 | 3.631 | 4 |
| same_ray > direction | 12388 | 19 | 8604 | 235 | 0.9814 | 0.9978 | 0.988 | 178 | 190 | 0.9924 | 0.9956 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 12460 | 3 | 8620 | 163 | 0.9871 | 0.9997 | 0.9922 | 171 | 190 | 0.9928 | 0.9994 | 4.789 | 7 |

### Feasible/realistic (34,662 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 19545 | 14984 | 0 | 0 | 1.0 | 0.0 | 0.566 | 0 | 133 | 1.0 | 0.566 | 0.0 | 0 |
| direction | 19270 | 76 | 14908 | 275 | 0.9859 | 0.9949 | 0.9898 | 56 | 133 | 0.9986 | 0.9913 | 1.0 | 1 |
| same_ray | 19374 | 2 | 14982 | 171 | 0.9913 | 0.9999 | 0.995 | 509 | 133 | 0.989 | 0.9999 | 4.0 | 4 |
| three_ray | 6763 | 0 | 14984 | 12782 | 0.346 | 1.0 | 0.6298 | 22961 | 133 | 0.3389 | 1.0 | 3.0 | 3 |
| three_ray4 | 11918 | 0 | 14984 | 7627 | 0.6098 | 1.0 | 0.7791 | 13808 | 133 | 0.604 | 1.0 | 3.66 | 4 |
| three_ray > same_ray | 19487 | 0 | 14984 | 58 | 0.997 | 1.0 | 0.9983 | 238 | 133 | 0.9968 | 1.0 | 4.987 | 6 |
| three_ray4 > same_ray | 19510 | 0 | 14984 | 35 | 0.9982 | 1.0 | 0.999 | 190 | 133 | 0.9982 | 1.0 | 4.855 | 7 |
| same_ray > three_ray4 | 19510 | 2 | 14982 | 35 | 0.9982 | 0.9999 | 0.9989 | 190 | 133 | 0.9982 | 0.9999 | 4.034 | 7 |
| three_ray4 > direction | 19481 | 20 | 14964 | 64 | 0.9967 | 0.9987 | 0.9976 | 33 | 133 | 0.9992 | 0.9983 | 3.66 | 4 |
| same_ray > direction | 19474 | 22 | 14962 | 71 | 0.9964 | 0.9985 | 0.9973 | 8 | 133 | 0.9999 | 0.9974 | 4.0 | 4 |
| three_ray4 > same_ray > direction | 19537 | 4 | 14980 | 8 | 0.9996 | 0.9997 | 0.9997 | 6 | 133 | 1.0 | 0.9997 | 4.855 | 7 |

### Synthetic stress (3,168 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 2631 | 468 | 0 | 0 | 1.0 | 0.0 | 0.849 | 0 | 69 | 1.0 | 0.849 | 0.0 | 0 |
| direction | 2167 | 0 | 468 | 464 | 0.8236 | 1.0 | 0.8503 | 300 | 69 | 0.9071 | 0.9374 | 1.0 | 1 |
| same_ray | 1862 | 0 | 468 | 769 | 0.7077 | 1.0 | 0.7519 | 955 | 69 | 0.7135 | 0.9991 | 3.727 | 4 |
| three_ray | 1660 | 0 | 468 | 971 | 0.6309 | 1.0 | 0.6867 | 1195 | 69 | 0.6357 | 0.999 | 3.0 | 3 |
| three_ray4 | 1894 | 0 | 468 | 737 | 0.7199 | 1.0 | 0.7622 | 914 | 69 | 0.7264 | 0.9991 | 3.273 | 4 |
| three_ray > same_ray | 2114 | 0 | 468 | 517 | 0.8035 | 1.0 | 0.8332 | 628 | 69 | 0.818 | 0.9992 | 3.859 | 6 |
| three_ray4 > same_ray | 2348 | 0 | 468 | 283 | 0.8924 | 1.0 | 0.9087 | 347 | 69 | 0.9087 | 0.9993 | 3.866 | 7 |
| same_ray > three_ray4 | 2346 | 0 | 468 | 285 | 0.8917 | 1.0 | 0.908 | 347 | 69 | 0.9087 | 0.9986 | 4.425 | 7 |
| three_ray4 > direction | 2339 | 0 | 468 | 292 | 0.889 | 1.0 | 0.9058 | 290 | 69 | 0.9103 | 0.995 | 3.273 | 4 |
| same_ray > direction | 2311 | 0 | 468 | 320 | 0.8784 | 1.0 | 0.8967 | 294 | 69 | 0.909 | 0.9865 | 3.727 | 4 |
| three_ray4 > same_ray > direction | 2351 | 0 | 468 | 280 | 0.8936 | 1.0 | 0.9096 | 289 | 69 | 0.9106 | 0.9989 | 3.866 | 7 |

### Conventional (33,077 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 19181 | 13694 | 0 | 0 | 1.0 | 0.0 | 0.5835 | 0 | 202 | 1.0 | 0.5835 | 0.0 | 0 |
| direction | 18512 | 69 | 13625 | 669 | 0.9651 | 0.995 | 0.9776 | 320 | 202 | 0.9908 | 0.9866 | 1.0 | 1 |
| same_ray | 18355 | 2 | 13692 | 826 | 0.9569 | 0.9999 | 0.9748 | 1329 | 202 | 0.9655 | 0.9999 | 3.977 | 4 |
| three_ray | 7290 | 0 | 13694 | 11891 | 0.3801 | 1.0 | 0.6383 | 21121 | 202 | 0.3636 | 0.9998 | 3.0 | 3 |
| three_ray4 | 11952 | 0 | 13694 | 7229 | 0.6231 | 1.0 | 0.7801 | 12881 | 202 | 0.6142 | 0.9999 | 3.627 | 4 |
| three_ray > same_ray | 18676 | 0 | 13694 | 505 | 0.9737 | 1.0 | 0.9846 | 791 | 202 | 0.9818 | 0.9999 | 4.893 | 6 |
| three_ray4 > same_ray | 18901 | 0 | 13694 | 280 | 0.9854 | 1.0 | 0.9915 | 498 | 202 | 0.9907 | 0.9999 | 4.772 | 7 |
| same_ray > three_ray4 | 18899 | 2 | 13692 | 282 | 0.9853 | 0.9999 | 0.9914 | 498 | 202 | 0.9907 | 0.9998 | 4.07 | 7 |
| three_ray4 > direction | 18864 | 20 | 13674 | 317 | 0.9835 | 0.9985 | 0.9897 | 287 | 202 | 0.9918 | 0.9979 | 3.627 | 4 |
| same_ray > direction | 18839 | 22 | 13672 | 342 | 0.9822 | 0.9984 | 0.9889 | 266 | 202 | 0.9925 | 0.9964 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 18930 | 4 | 13690 | 251 | 0.9869 | 0.9997 | 0.9922 | 259 | 202 | 0.9927 | 0.9996 | 4.772 | 7 |

### Guided (2,637 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 1750 | 887 | 0 | 0 | 1.0 | 0.0 | 0.6636 | 0 | 0 | 1.0 | 0.6636 | 0.0 | 0 |
| direction | 1710 | 1 | 886 | 40 | 0.9771 | 0.9989 | 0.9845 | 20 | 0 | 0.9924 | 0.992 | 1.0 | 1 |
| same_ray | 1686 | 0 | 887 | 64 | 0.9634 | 1.0 | 0.9757 | 76 | 0 | 0.9712 | 1.0 | 3.977 | 4 |
| three_ray | 642 | 0 | 887 | 1108 | 0.3669 | 1.0 | 0.5798 | 1704 | 0 | 0.3538 | 1.0 | 3.0 | 3 |
| three_ray4 | 1081 | 0 | 887 | 669 | 0.6177 | 1.0 | 0.7463 | 1029 | 0 | 0.6098 | 1.0 | 3.639 | 4 |
| three_ray > same_ray | 1712 | 0 | 887 | 38 | 0.9783 | 1.0 | 0.9856 | 41 | 0 | 0.9845 | 1.0 | 4.916 | 6 |
| three_ray4 > same_ray | 1730 | 0 | 887 | 20 | 0.9886 | 1.0 | 0.9924 | 21 | 0 | 0.992 | 1.0 | 4.786 | 7 |
| same_ray > three_ray4 | 1730 | 0 | 887 | 20 | 0.9886 | 1.0 | 0.9924 | 21 | 0 | 0.992 | 1.0 | 4.043 | 7 |
| three_ray4 > direction | 1729 | 0 | 887 | 21 | 0.988 | 1.0 | 0.992 | 20 | 0 | 0.9924 | 0.9996 | 3.639 | 4 |
| same_ray > direction | 1721 | 0 | 887 | 29 | 0.9834 | 1.0 | 0.989 | 20 | 0 | 0.9924 | 0.9966 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 1730 | 0 | 887 | 20 | 0.9886 | 1.0 | 0.9924 | 20 | 0 | 0.9924 | 1.0 | 4.786 | 7 |

### Dumb-fire (2,116 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 1245 | 871 | 0 | 0 | 1.0 | 0.0 | 0.5884 | 0 | 0 | 1.0 | 0.5884 | 0.0 | 0 |
| direction | 1215 | 6 | 865 | 30 | 0.9759 | 0.9931 | 0.983 | 16 | 0 | 0.9924 | 0.9905 | 1.0 | 1 |
| same_ray | 1195 | 0 | 871 | 50 | 0.9598 | 1.0 | 0.9764 | 59 | 0 | 0.9721 | 1.0 | 3.977 | 4 |
| three_ray | 491 | 0 | 871 | 754 | 0.3944 | 1.0 | 0.6437 | 1331 | 0 | 0.371 | 1.0 | 3.0 | 3 |
| three_ray4 | 779 | 0 | 871 | 466 | 0.6257 | 1.0 | 0.7798 | 812 | 0 | 0.6163 | 1.0 | 3.621 | 4 |
| three_ray > same_ray | 1213 | 0 | 871 | 32 | 0.9743 | 1.0 | 0.9849 | 34 | 0 | 0.9839 | 1.0 | 4.864 | 6 |
| three_ray4 > same_ray | 1227 | 0 | 871 | 18 | 0.9855 | 1.0 | 0.9915 | 18 | 0 | 0.9915 | 1.0 | 4.75 | 7 |
| same_ray > three_ray4 | 1227 | 0 | 871 | 18 | 0.9855 | 1.0 | 0.9915 | 18 | 0 | 0.9915 | 1.0 | 4.042 | 7 |
| three_ray4 > direction | 1227 | 0 | 871 | 18 | 0.9855 | 1.0 | 0.9915 | 16 | 0 | 0.9924 | 0.999 | 3.621 | 4 |
| same_ray > direction | 1225 | 0 | 871 | 20 | 0.9839 | 1.0 | 0.9905 | 16 | 0 | 0.9924 | 0.9981 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 1228 | 0 | 871 | 17 | 0.9863 | 1.0 | 0.992 | 16 | 0 | 0.9924 | 0.9995 | 4.75 | 7 |

### Ordinary X/Y (36,523 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 21595 | 14738 | 0 | 0 | 1.0 | 0.0 | 0.5944 | 0 | 190 | 1.0 | 0.5944 | 0.0 | 0 |
| direction | 20978 | 76 | 14662 | 617 | 0.9714 | 0.9948 | 0.9809 | 278 | 190 | 0.9926 | 0.9882 | 1.0 | 1 |
| same_ray | 20688 | 2 | 14736 | 907 | 0.958 | 0.9999 | 0.975 | 1381 | 190 | 0.9671 | 0.9999 | 3.977 | 4 |
| three_ray | 8223 | 0 | 14738 | 13372 | 0.3808 | 1.0 | 0.632 | 23306 | 190 | 0.3637 | 0.9998 | 3.0 | 3 |
| three_ray4 | 13464 | 0 | 14738 | 8131 | 0.6235 | 1.0 | 0.7762 | 14205 | 190 | 0.6142 | 0.9999 | 3.627 | 4 |
| three_ray > same_ray | 21035 | 0 | 14738 | 560 | 0.9741 | 1.0 | 0.9846 | 824 | 190 | 0.9823 | 0.9999 | 4.892 | 6 |
| three_ray4 > same_ray | 21287 | 0 | 14738 | 308 | 0.9857 | 1.0 | 0.9915 | 510 | 190 | 0.9909 | 0.9999 | 4.771 | 7 |
| same_ray > three_ray4 | 21285 | 2 | 14736 | 310 | 0.9856 | 0.9999 | 0.9914 | 510 | 190 | 0.9909 | 0.9998 | 4.064 | 7 |
| three_ray4 > direction | 21283 | 20 | 14718 | 312 | 0.9856 | 0.9986 | 0.9909 | 278 | 190 | 0.9926 | 0.9982 | 3.627 | 4 |
| same_ray > direction | 21229 | 22 | 14716 | 366 | 0.9831 | 0.9985 | 0.9893 | 278 | 190 | 0.9926 | 0.9967 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 21317 | 4 | 14734 | 278 | 0.9871 | 0.9997 | 0.9922 | 278 | 190 | 0.9926 | 0.9996 | 4.771 | 7 |

### Bounded traverse (1,046 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 565 | 472 | 0 | 0 | 1.0 | 0.0 | 0.5448 | 0 | 9 | 1.0 | 0.5448 | 0.0 | 0 |
| direction | 456 | 0 | 472 | 109 | 0.8071 | 1.0 | 0.8949 | 76 | 9 | 0.9335 | 0.9587 | 1.0 | 1 |
| same_ray | 539 | 0 | 472 | 26 | 0.954 | 1.0 | 0.9749 | 60 | 9 | 0.9508 | 1.0 | 3.977 | 4 |
| three_ray | 188 | 0 | 472 | 377 | 0.3327 | 1.0 | 0.6365 | 682 | 9 | 0.351 | 1.0 | 3.0 | 3 |
| three_ray4 | 336 | 0 | 472 | 229 | 0.5947 | 1.0 | 0.7792 | 418 | 9 | 0.6056 | 1.0 | 3.638 | 4 |
| three_ray > same_ray | 551 | 0 | 472 | 14 | 0.9752 | 1.0 | 0.9865 | 36 | 9 | 0.974 | 1.0 | 4.933 | 6 |
| three_ray4 > same_ray | 556 | 0 | 472 | 9 | 0.9841 | 1.0 | 0.9913 | 23 | 9 | 0.9865 | 1.0 | 4.814 | 7 |
| same_ray > three_ray4 | 556 | 0 | 472 | 9 | 0.9841 | 1.0 | 0.9913 | 23 | 9 | 0.9865 | 1.0 | 4.112 | 7 |
| three_ray4 > direction | 523 | 0 | 472 | 42 | 0.9257 | 1.0 | 0.9595 | 43 | 9 | 0.9653 | 0.994 | 3.638 | 4 |
| same_ray > direction | 547 | 0 | 472 | 18 | 0.9681 | 1.0 | 0.9826 | 22 | 9 | 0.9855 | 0.9971 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 556 | 0 | 472 | 9 | 0.9841 | 1.0 | 0.9913 | 15 | 9 | 0.9923 | 0.999 | 4.814 | 7 |

### Reversed X/Y (130 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 7 | 123 | 0 | 0 | 1.0 | 0.0 | 0.0538 | 0 | 0 | 1.0 | 0.0538 | 0.0 | 0 |
| direction | 0 | 0 | 123 | 7 | 0.0 | 1.0 | 0.9462 | 1 | 0 | 0.9923 | 0.9535 | 1.0 | 1 |
| same_ray | 2 | 0 | 123 | 5 | 0.2857 | 1.0 | 0.9615 | 11 | 0 | 0.9154 | 1.0 | 3.977 | 4 |
| three_ray | 6 | 0 | 123 | 1 | 0.8571 | 1.0 | 0.9923 | 80 | 0 | 0.3846 | 1.0 | 3.0 | 3 |
| three_ray4 | 6 | 0 | 123 | 1 | 0.8571 | 1.0 | 0.9923 | 48 | 0 | 0.6308 | 1.0 | 3.608 | 4 |
| three_ray > same_ray | 6 | 0 | 123 | 1 | 0.8571 | 1.0 | 0.9923 | 2 | 0 | 0.9846 | 1.0 | 4.823 | 6 |
| three_ray4 > same_ray | 6 | 0 | 123 | 1 | 0.8571 | 1.0 | 0.9923 | 1 | 0 | 0.9923 | 1.0 | 4.692 | 7 |
| same_ray > three_ray4 | 6 | 0 | 123 | 1 | 0.8571 | 1.0 | 0.9923 | 1 | 0 | 0.9923 | 1.0 | 4.154 | 7 |
| three_ray4 > direction | 6 | 0 | 123 | 1 | 0.8571 | 1.0 | 0.9923 | 1 | 0 | 0.9923 | 1.0 | 3.608 | 4 |
| same_ray > direction | 2 | 0 | 123 | 5 | 0.2857 | 1.0 | 0.9615 | 1 | 0 | 0.9923 | 0.969 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 6 | 0 | 123 | 1 | 0.8571 | 1.0 | 0.9923 | 1 | 0 | 0.9923 | 1.0 | 4.692 | 7 |

### Rotation-Z (131 rows)

| method | TP | FP | TN | FN | sensitivity | specificity | accuracy | model_unknown | truth_unknown | coverage | decided_accuracy | mean_queries | max_queries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 9 | 119 | 0 | 0 | 1.0 | 0.0 | 0.0703 | 0 | 3 | 1.0 | 0.0703 | 0.0 | 0 |
| direction | 3 | 0 | 119 | 6 | 0.3333 | 1.0 | 0.9531 | 1 | 3 | 1.0 | 0.9531 | 1.0 | 1 |
| same_ray | 7 | 0 | 119 | 2 | 0.7778 | 1.0 | 0.9844 | 12 | 3 | 0.9297 | 1.0 | 3.977 | 4 |
| three_ray | 6 | 0 | 119 | 3 | 0.6667 | 1.0 | 0.9766 | 88 | 3 | 0.3359 | 1.0 | 3.0 | 3 |
| three_ray4 | 6 | 0 | 119 | 3 | 0.6667 | 1.0 | 0.9766 | 51 | 3 | 0.625 | 1.0 | 3.649 | 4 |
| three_ray > same_ray | 9 | 0 | 119 | 0 | 1.0 | 1.0 | 1.0 | 4 | 3 | 0.9922 | 1.0 | 4.992 | 6 |
| three_ray4 > same_ray | 9 | 0 | 119 | 0 | 1.0 | 1.0 | 1.0 | 3 | 3 | 1.0 | 1.0 | 4.794 | 7 |
| same_ray > three_ray4 | 9 | 0 | 119 | 0 | 1.0 | 1.0 | 1.0 | 3 | 3 | 1.0 | 1.0 | 4.168 | 7 |
| three_ray4 > direction | 8 | 0 | 119 | 1 | 0.8889 | 1.0 | 0.9922 | 1 | 3 | 1.0 | 0.9922 | 3.649 | 4 |
| same_ray > direction | 7 | 0 | 119 | 2 | 0.7778 | 1.0 | 0.9844 | 1 | 3 | 1.0 | 0.9844 | 3.977 | 4 |
| three_ray4 > same_ray > direction | 9 | 0 | 119 | 0 | 1.0 | 1.0 | 1.0 | 1 | 3 | 1.0 | 1.0 | 4.794 | 7 |

## Observed group differences

Expanded ordinary/official behavior is broadly consistent with historical A4 in showing few decided false-ENGAGEABLE results for same-ray and three-ray methods, while the changed corpus and exposure design produce different aggregate coverage and accuracy.

The rare classes are not hidden by the 36,523 nominal ordinary-X/Y rows. Bounded-traverse direction has 109 false-NOT-ENGAGEABLE rows and 76 prediction-UNKNOWN rows among 1,046 rows; same-ray has 26 false-NOT-ENGAGEABLE and 60 prediction-UNKNOWN. The reversed-X/Y turret has only 7 truth-ENGAGEABLE rows among 130, and direction identifies none of them as ENGAGEABLE. The rotation-Z turret has 9 truth-ENGAGEABLE rows among 128 truth-known rows; direction identifies 3.

Known172 exposure is the largest prediction-UNKNOWN concentration for three-ray and three-ray4. Synthetic stress is the main concentration for direction and same-ray UNKNOWN behavior. These are failure groups for A5, not cause classifications.

## Failure groups for later A5 analysis

- `baseline`: 15452 truth-known wrong/UNKNOWN rows.
  - 4837: wrong, ordinary_xy, swi, conventional_gun, known172
  - 3118: wrong, ordinary_xy, official, conventional_gun, known172
  - 1513: wrong, ordinary_xy, swi, conventional_gun, single-point
  - 1036: wrong, ordinary_xy, official, conventional_gun, single-point
  - 920: wrong, ordinary_xy, swi, conventional_gun, boundary
- `direction`: 815 truth-known wrong/UNKNOWN rows.
  - 141: UNKNOWN, ordinary_xy, swi, conventional_gun, synthetic
  - 91: UNKNOWN, ordinary_xy, official, conventional_gun, synthetic
  - 82: wrong, ordinary_xy, swi, conventional_gun, known172
  - 77: wrong, ordinary_xy, official, conventional_gun, synthetic
  - 70: wrong, ordinary_xy, swi, conventional_gun, synthetic
- `same_ray`: 1272 truth-known wrong/UNKNOWN rows.
  - 461: UNKNOWN, ordinary_xy, swi, conventional_gun, synthetic
  - 284: UNKNOWN, ordinary_xy, official, conventional_gun, synthetic
  - 86: UNKNOWN, ordinary_xy, swi, conventional_gun, single-point
  - 75: UNKNOWN, ordinary_xy, swi, conventional_gun, boundary
  - 63: UNKNOWN, ordinary_xy, swi, conventional_gun, known172
- `three_ray`: 23959 truth-known wrong/UNKNOWN rows.
  - 11071: UNKNOWN, ordinary_xy, swi, conventional_gun, known172
  - 6808: UNKNOWN, ordinary_xy, official, conventional_gun, known172
  - 1184: UNKNOWN, ordinary_xy, official, dumbfire_missile, known172
  - 1184: UNKNOWN, ordinary_xy, official, guided_missile, known172
  - 783: UNKNOWN, ordinary_xy, swi, conventional_gun, boundary
- `three_ray4`: 14525 truth-known wrong/UNKNOWN rows.
  - 6733: UNKNOWN, ordinary_xy, swi, conventional_gun, known172
  - 4140: UNKNOWN, ordinary_xy, official, conventional_gun, known172
  - 720: UNKNOWN, ordinary_xy, official, dumbfire_missile, known172
  - 720: UNKNOWN, ordinary_xy, official, guided_missile, known172
  - 438: UNKNOWN, ordinary_xy, swi, conventional_gun, synthetic

Truth-UNKNOWN patterns:

- 188: `ordinary_xy` / `UNKNOWN_none_trap`
- 9: `bounded_traverse` / `UNKNOWN_root_limit_unwrap`
- 3: `rotation_z` / `UNKNOWN_none_trap`
- 2: `ordinary_xy` / `UNKNOWN_one_trap`

## Limitations

The selected A4x endpoint/reference pose is the offline coordinate definition. This run does not provide new live proof of emitted-muzzle runtime behavior. It also excludes range, line of sight, own-hull masking, projectile flight, missile guidance, and firing readiness.
