"""Issue #176 A5: summarise adaptive.py rows against the accepted A4x same_ray / three_ray4 / chain answers."""
import gzip
import json
import math
import sys
from collections import Counter
from pathlib import Path

from ray_failure_groups import ROWS, chain

CACHE = Path(__file__).resolve().parents[2] / ".x4-research-cache/issue176-a5"
MODES = ("adaptive", "locate", "strict", "along", "tri2")


def quantiles(v):
    v = sorted(v)
    return tuple(v[int(p * (len(v) - 1))] for p in (.5, .9, .99, 1.)) if v else ()


def table(rows, a4, label):
    print(f"\n### {label}: {len(rows)} truth-known rows")
    print("| method | correct YES | correct NO | UNKNOWN | false ENGAGEABLE | false NOT | queries med/p90/p99/max |")
    print("|---|---|---|---|---|---|---|")
    for m in ("same_ray", "three_ray4", "chain") + MODES:
        tally = Counter()
        for r in rows:
            ref = a4[r["case_id"], r["rough_factor"]]
            ans = chain(ref)[1] if m == "chain" else ref[m] if m in ("same_ray", "three_ray4") else r.get(m, "UNKNOWN")
            tally["UNKNOWN" if ans == "UNKNOWN" else "ok_" + ans if ans == r["truth"] else "false_" + ans] += 1
        q = "/".join(map(str, quantiles([r[m + "_q"] for r in rows if m + "_q" in r]))) if m in MODES else ""
        print(f"| {m} | {tally['ok_YES']} | {tally['ok_NO']} | {tally['UNKNOWN']} | {tally['false_YES']} | {tally['false_NO']} | {q} |")


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "adaptive-focus"
    a4 = {}
    for line in gzip.open(ROWS, "rt"):
        r = json.loads(line)
        a4[r["case_id"], r["rough_factor"]] = r
    rows = [json.loads(line) for line in gzip.open(CACHE / (name + ".jsonl.gz"), "rt")]
    rows = [r for r in rows if r["truth"] != "UNKNOWN"]
    for factor in (1, .5, 2):
        for scenario in ("feasible_realistic", "synthetic_stress"):
            sel = [r for r in rows if r["rough_factor"] == factor and r["scenario"] == scenario]
            if not sel:
                continue
            table(sel, a4, f"factor {factor} {scenario}")
            f1 = [r for r in sel if "adaptive_stop" in r]
            spreads = [r["adaptive_spread"] for r in f1 if r["adaptive"] != "UNKNOWN" and "adaptive_spread" in r]
            print("\nstop:", dict(Counter(r["adaptive_stop"] for r in f1)),
                  "| certified before locating:", sum(r["adaptive"] != "UNKNOWN" and not any(
                      e["kind"] == "located" for e in r.get("adaptive_trace", ())) for r in f1),
                  "| >1 aim point selected:", sum(r.get("adaptive_selected", 0) > 1 for r in f1),
                  "| sideways misses seen:", sum(r.get("adaptive_misses", 0) > 0 for r in f1),
                  "| region misses truth:", sum(r.get("adaptive_holds") is False for r in f1),
                  "| scan flips in certified region:", sum(bool(r.get("adaptive_scan_flip")) for r in f1),
                  "| spread at decision deg med/p90/p99/max:",
                  tuple(round(x, 4) for x in quantiles(spreads)))
            if factor == 1 and scenario == "feasible_realistic":
                groups = {
                    "359 bracket_disagree": lambda ref: ref["same_ray_reason"] == "bracket_disagree",
                    "79 three_ray4 aim-point switch": lambda ref: ref["same_ray_reason"] == "bracket_disagree"
                    and ref["three_ray4_status"] != "pass",
                    "15 chain residual": lambda ref: chain(ref)[1] != ref["truth"],
                    "same_ray decided wrong (flip-back)": lambda ref: ref["same_ray"] not in ("UNKNOWN", ref["truth"]),
                }
                for g, test in groups.items():
                    sub = [r for r in sel if test(a4[r["case_id"], 1])]
                    table(sub, a4, g)
                    for r in sub if len(sub) <= 20 else ():
                        print(" ", r["case_id"], "truth", r["truth"], "adaptive", r["adaptive"], r["adaptive_stop"],
                              "q", r["adaptive_q"], "spread", r["adaptive_spread"] if math.isfinite(r["adaptive_spread"] or math.inf) else "inf",
                              "margin", r["adaptive_margin"])


if __name__ == "__main__":
    main()
