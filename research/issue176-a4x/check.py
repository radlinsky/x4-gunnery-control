"""Structural and reporting checks for expanded A4 pilot/full outputs."""
import argparse
import gzip
import json
from collections import Counter

from compare import OUT


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pilot", action="store_true")
    args = parser.parse_args()
    path = OUT / ("pilot.jsonl.gz" if args.pilot else "trials.jsonl.gz")
    rows = [json.loads(line) for line in gzip.open(path, "rt")]
    turrets = {(r["source"], r["turret_macro"]) for r in rows}
    classes = Counter(r["mechanical_class"] for r in rows)
    sources = Counter(r["source"] for r in rows)
    behaviors = Counter(r["weapon_behavior"] for r in rows)
    scenarios = Counter(r["scenario"] for r in rows)
    subgroups = Counter(r["historical_subgroup"] for r in rows)
    assert len(turrets) == 288
    assert set(classes) == {"ordinary_xy", "bounded_traverse", "reversed_xy", "rotation_z"}
    assert set(sources) == {"official", "swi"}
    assert set(behaviors) == {"conventional_gun", "guided_missile", "dumbfire_missile"}
    assert set(scenarios) == {"feasible_realistic", "synthetic_stress"}
    if args.pilot:
        assert len(rows) == 579
        assert subgroups == {"single-point": 1, "multi-point": 1, "boundary": 1,
                            "known172": 288, "synthetic": 288}
    else:
        assert len(rows) == 113490
        assert subgroups == {"single-point": 6990 * 3, "multi-point": 1800 * 3,
                            "boundary": 4560 * 3, "known172": 74 * 288 * 3,
                            "synthetic": 11 * 288 * 3}
        assert Counter(r["rough_factor"] for r in rows) == {.5: 37830, 1: 37830, 2: 37830}
    if not args.pilot:
        # Each turret must actually walk the 24 benchmark rotations, not alias onto one.
        seen = {}
        for r in rows:
            seen.setdefault(r["historical_subgroup"], {}).setdefault(
                (r["source"], r["turret_macro"]), set()).add(r["rotation_id"])
        minimum = {"single-point": 24, "multi-point": 6, "boundary": 15,
                   "known172": 24, "synthetic": 11}
        for subgroup, need in minimum.items():
            per_turret = seen[subgroup]
            assert len(per_turret) == 288, (subgroup, len(per_turret))
            worst = min(len(v) for v in per_turret.values())
            assert worst >= need, (subgroup, worst, need)
            print("rotation coverage", subgroup, "min per turret", worst, ">=", need)
    print("PASS", path, "rows", len(rows), "turrets", len(turrets))
    print("classes", dict(classes), "sources", dict(sources))
    print("behaviors", dict(behaviors), "scenarios", dict(scenarios))
    print("subgroups", dict(subgroups))


if __name__ == "__main__":
    main()
