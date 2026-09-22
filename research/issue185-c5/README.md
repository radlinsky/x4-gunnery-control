# C5 aim-point uncertainty benchmark

Offline research benchmark for issue #185. It applies the accepted exact-point
CANNOT BEAR scorer to the retained #184 recovered aim points and their unchanged
recovery uncertainty. C5.2 also searches each complete 3-D uncertainty ball and
measures how far any valid settled muzzle can move from its nearest muzzle at the
recovered centre. This is firing-origin movement due to aim-point uncertainty,
not prediction error.

```sh
python3 research/issue185-c5/benchmark.py --jobs 12
```

`--jobs` changes only parallel execution; the search and results are
deterministic. The detailed rows are written to the ignored
`.x4-research-cache/issue185-c5/benchmark.jsonl`; committed aggregate findings
are in [findings.md](findings.md).
