# C5 aim-point uncertainty benchmark

Offline research benchmark for issue #185. It applies the accepted exact-point
CANNOT BEAR scorer to the retained #184 recovered aim points and their unchanged
recovery uncertainty.

```sh
python3 research/issue185-c5/benchmark.py
```

The detailed rows are written to the ignored
`.x4-research-cache/issue185-c5/benchmark.jsonl`; committed aggregate findings
are in [findings.md](findings.md).
