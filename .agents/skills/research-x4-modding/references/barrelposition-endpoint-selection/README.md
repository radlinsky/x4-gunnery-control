# `weapon.barrelposition` endpoint selection

These artifacts support GitHub issue #164. They preserve the compact inputs,
results, and reverse-engineering notes needed to review or reproduce the
endpoint-selection finding without relying on files uploaded to ChatGPT or
left in `/tmp`.

The analyzed X4 executable has SHA-256
`19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`.
The accepted, build-pinned finding is that `weapon.barrelposition` selects the
`laser`-tagged connection with the smallest unsigned native connection-name
hash. Endpoint identity is proved separately from the still-unfinished
transform and animation geometry work.

The native hash algorithm is:

```python
h = 0x811c9dc5
for byte in connection_name.encode("ascii"):
    h = ((h * 0x1000193) & 0xffffffffffffffff) ^ byte
```

`report.md` records the original offline prospective-muzzle conclusions.
`corpus.csv` is the compact 92-row endpoint census, while `summary.json`
preserves source-verification hashes and conservative graph groupings. The
address and instruction evidence supporting the native trace is recorded in
`report.md` and in GitHub issue #164. The Python files are the ad hoc analysis
and reproduction helpers used to produce and inspect these results.

The large generated `x4-calls.json` and `x4-allrefs.json` reference indexes are
intentionally omitted. So are the executable, extracted official X4 files,
pickles, caches, logs, and multi-megabyte intermediate reports. Recreate those
temporary inputs from a locally installed executable and official catalogs;
do not commit them. The executable-dependent tools must only be used after its
SHA-256 matches the value above.
