"""Issue #176 A5: group accepted A4x ray-method failures (reads the ignored A4x trials cache only)."""
import gzip
import json
from collections import Counter
from pathlib import Path

ROWS = Path(__file__).resolve().parents[2] / ".x4-research-cache/issue176-a4x/trials.jsonl.gz"


def chain(r):
    for m in ("three_ray4", "same_ray", "direction"):
        if r[m] != "UNKNOWN":
            return m, r[m]
    return None, "UNKNOWN"


def main():
    rows = [json.loads(line) for line in gzip.open(ROWS)]
    assert len(rows) == 113490, len(rows)
    known = [r for r in rows if r["truth"] != "UNKNOWN"]
    for factor in (0.5, 1, 2):
        real = [r for r in known if r["rough_factor"] == factor and r["scenario"] == "feasible_realistic"]
        miss = [r for r in real if r["same_ray"] != r["truth"]]
        print(f"factor {factor}: realistic same_ray wrong/UNKNOWN {len(miss)}",
              Counter((r["same_ray_reason"], r["three_ray4_status"]) for r in miss).most_common(6))
    f1 = [r for r in known if r["rough_factor"] == 1]
    real = [r for r in f1 if r["scenario"] == "feasible_realistic"]
    group = [r for r in real if r["same_ray_reason"] == "bracket_disagree"]
    rest = [r for r in group if r["three_ray4_status"] != "pass"]
    print("bracket_disagree", len(group), "three_ray4 pass", len(group) - len(rest),
          "three_ray4 fails", len(rest), Counter((r["three_ray4_status"], r["three_ray4_mixed"]) for r in rest),
          "same-ray probe switch", sum(r["probe_switch"] for r in rest))
    wrong = [r for r in real if chain(r)[1] != r["truth"]]
    print("chain three_ray4>same_ray>direction realistic residual", len(wrong),
          Counter((chain(r), r["truth"], r["same_ray_reason"], r["three_ray4_status"]) for r in wrong))
    decided = [(r["case_id"], r["same_ray"], r["truth"], r["bracket"]) for r in real
               if r["same_ray"] not in ("UNKNOWN", r["truth"])]
    print("same_ray decided wrong realistic", decided)
    print("synthetic same_ray wrong/UNKNOWN", Counter(r["same_ray_reason"] for r in f1
          if r["scenario"] == "synthetic_stress" and r["same_ray"] != r["truth"]))


if __name__ == "__main__":
    main()
