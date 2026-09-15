"""P3c: tables, invariants and first-three inspection from result.pkl."""
import gzip, json, pickle, statistics, sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parents[1] / ".x4-research-cache/issue167-p3c"
res = pickle.load(open(OUT / (sys.argv[1] if len(sys.argv) > 1 else "result.pkl"), "rb"))
agg, first, errors = res["agg"], res["first"], res["errors"]
fams = ("ordinary", "official", "synthetic")
agg["combined"] = sum((agg[f] for f in fams), Counter())
errors["combined"] = sum((errors[f] for f in fams), [])
PRIMARY = ("correct_accepted", "accepted_wrong", "fail_closed", "false_engageable", "false_not_engageable", "total_error")


def pct(k, n):
    return f"{k:,}/{n:,} ({100 * k / n:.6f}%)" if n else f"{k}/0"


for f in (*fams, "combined"):
    c = agg[f]
    n = c["correct_accepted"] + c["accepted_wrong"] + c["fail_closed"]
    assert c["false_engageable"] + c["false_not_engageable"] == c["total_error"], f
    assert sum(v for k, v in c.items() if k.startswith("queries=")) == n
    assert sum(v for k, v in c.items() if k.startswith("reason=")) == c["fail_closed"]
    print(f"\n## {f}  N={n:,}")
    for k in PRIMARY:
        print(f"  {k:22s} {pct(c[k], n)}")
    for k in ("identity_mismatch", "envelope_miss", "exact_point", "exact_decision=True"):
        print(f"  {k:22s} {pct(c[k], n)}")
    print("  reasons:", {k[7:]: c[k] for k in sorted(c) if k.startswith("reason=")})
    print("  queries:", {k: c[k] for k in sorted(c) if k.startswith("queries=")})
    print("  exact states:", {k[6:]: c[k] for k in sorted(c) if k.startswith("exact=")})
    print("  approx states:", {k[7:]: c[k] for k in sorted(c) if k.startswith("approx=")})
    print("  accepted buckets:", {k[9:]: c[k] for k in sorted(c) if k.startswith("accepted/")})
    if f in ("official", "combined"):
        print("  hidden_before_entry:", {k[20:]: c[k] for k in sorted(c) if k.startswith("hidden_before_entry=")})
    e = sorted(errors[f])
    if e:
        q = lambda p: e[min(len(e) - 1, int(p * len(e)))]  # noqa: E731
        print(f"  accepted |X-P| m: n={len(e):,} min={e[0]:.3g} median={statistics.median(e):.3g} p90={q(.9):.3g} "
              f"p99={q(.99):.3g} p99.9={q(.999):.3g} max={e[-1]:.6g}")
assert sum(agg[f]["fail_closed"] + agg[f]["correct_accepted"] + agg[f]["accepted_wrong"] for f in fams) == \
    agg["combined"]["fail_closed"] + agg["combined"]["correct_accepted"] + agg["combined"]["accepted_wrong"]

if "--inspect" in sys.argv:
    wanted = {}
    for (f, k), ids in first.items():
        if k.startswith("reason=") or k.startswith("accepted/") or k.startswith("hidden_before_entry=True"):
            for i in ids:
                wanted.setdefault(i, []).append(f"{f}:{k}")
    for i in sorted(wanted):
        with gzip.open(OUT / "trials" / f"{i // 2000 * 2000:07d}.jsonl.gz", "rt") as fh:
            r = next(json.loads(line) for line in fh if json.loads(line)["id"] == i)
        log = [(tuple(round(v, 3) for v in U), None if d is None else tuple(round(v, 6) for v in d), s) for U, d, s in r.pop("query_log")]
        print(f"\n# {i} {wanted[i]}")
        print(json.dumps({k: r.get(k) for k in ("family", "macro", "radius", "kind", "s", "a", "Lfactor", "epsilon", "O", "C", "H", "native",
                                                  "reason", "X", "E", "identity", "point_error", "bucket", "hidden_before_entry")}))
        print("  queries", log, "exact", r["exact"]["state"], "approx", r["approx"]["state"],
              "fE", r["false_engageable"], "fNE", r["false_not_engageable"])
