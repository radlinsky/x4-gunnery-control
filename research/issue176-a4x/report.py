"""Metrics, partition checks, and tracked findings for the expanded A4 benchmark."""
from __future__ import annotations

import gzip
import json
from collections import Counter
from pathlib import Path

from compare import METHODS, OUT

HERE = Path(__file__).resolve().parent
START_SHA = "4dafbf0a9211610d007996facaf40c5ca30ca220"
STACKS = METHODS + (("three_ray", "same_ray"), ("three_ray4", "same_ray"),
                    ("same_ray", "three_ray4"), ("three_ray4", "direction"),
                    ("same_ray", "direction"), ("three_ray4", "same_ray", "direction"))
DIMENSIONS = {
    "source": (("Official X4", "official"), ("SWI 0.9.1 HF", "swi")),
    "scenario": (("Feasible/realistic", "feasible_realistic"),
                 ("Synthetic stress", "synthetic_stress")),
    "weapon_behavior": (("Conventional", "conventional_gun"),
                        ("Guided", "guided_missile"), ("Dumb-fire", "dumbfire_missile"),
                        ("Other/unresolved", "unresolved_other")),
    "mechanical_class": (("Ordinary X/Y", "ordinary_xy"),
                         ("Bounded traverse", "bounded_traverse"),
                         ("Reversed X/Y", "reversed_xy"), ("Rotation-Z", "rotation_z"),
                         ("Other/unresolved", "other")),
}
COLS = ("TP", "FP", "TN", "FN", "sensitivity", "specificity", "accuracy",
        "model_unknown", "truth_unknown", "coverage", "decided_accuracy",
        "mean_queries", "max_queries")


def label(stack):
    return stack if isinstance(stack, str) else " > ".join(stack)


def resolve(row, stack):
    answer, queries = "UNKNOWN", 0
    for method in (stack,) if isinstance(stack, str) else stack:
        queries += row[method + "_q"] - (queries > 0)
        answer = row[method]
        if answer != "UNKNOWN":
            break
    return answer, queries


def metrics(rows, stack):
    c, queries = Counter(), []
    for row in rows:
        answer, q = resolve(row, stack)
        queries.append(q)
        c["model_unknown"] += answer == "UNKNOWN"
        if row["truth"] == "UNKNOWN":
            c["truth_unknown"] += 1
            continue
        yes = row["truth"] == "YES"
        c[("TP" if answer == "YES" else "FN") if yes else
          ("FP" if answer == "YES" else "TN")] += 1
        c["unknown_on_yes" if yes else "unknown_on_no"] += answer == "UNKNOWN"
    ratio = lambda a, b: round(a / b, 4) if b else None  # noqa: E731
    known = c["TP"] + c["FP"] + c["TN"] + c["FN"]
    decided = known - c["unknown_on_yes"] - c["unknown_on_no"]
    wrong = c["FP"] + c["FN"] - c["unknown_on_yes"]
    return dict(cases=len(rows), **{k: c[k] for k in
                ("TP", "FP", "TN", "FN", "truth_unknown", "model_unknown",
                 "unknown_on_yes", "unknown_on_no")},
                sensitivity=ratio(c["TP"], c["TP"] + c["FN"]),
                specificity=ratio(c["TN"], c["TN"] + c["FP"]),
                accuracy=ratio(c["TP"] + c["TN"], known), coverage=ratio(decided, known),
                decided_accuracy=ratio(decided - wrong, decided),
                mean_queries=round(sum(queries) / len(queries), 3) if queries else None,
                max_queries=max(queries) if queries else None)


def table(rows):
    return {label(stack): metrics(rows, stack) for stack in STACKS}


def markdown_table(result):
    lines = ["| method | " + " | ".join(COLS) + " |",
             "|---|" + "---:|" * len(COLS)]
    for stack in STACKS:
        m = result[label(stack)]
        lines.append("| " + label(stack) + " | " + " | ".join(str(m[c]) for c in COLS) + " |")
    return "\n".join(lines)


def _partitions(rows):
    nominal = [r for r in rows if r["rough_factor"] == 1]
    groups = {"Combined all 288 turrets": nominal}
    for field, values in DIMENSIONS.items():
        present = {r[field] for r in nominal}
        children = []
        for display, value in values:
            subset = [r for r in nominal if r[field] == value]
            if subset:
                groups[display] = subset
                children.append(subset)
                present.discard(value)
        if present:
            raise AssertionError(f"unreported {field} values: {sorted(present)}")
        assert sum(map(len, children)) == len(nominal), field
    return nominal, groups


def _validate_rows(rows):
    assert len(rows) == 113490
    by_factor = Counter(r["rough_factor"] for r in rows)
    assert by_factor == {.5: 37830, 1: 37830, 2: 37830}
    nominal = [r for r in rows if r["rough_factor"] == 1]
    subgroup = Counter(r["historical_subgroup"] for r in nominal)
    assert subgroup == {"single-point": 6990, "multi-point": 1800, "boundary": 4560,
                       "known172": 21312, "synthetic": 3168}
    assert len({(r["source"], r["turret_macro"]) for r in nominal}) == 288
    for group in (nominal,):
        for stack in STACKS:
            m = metrics(group, stack)
            assert m["TP"] + m["FP"] + m["TN"] + m["FN"] + m["truth_unknown"] == len(group)


def _failure_summary(rows):
    lines = []
    for method in METHODS:
        failures = Counter()
        for r in rows:
            if r["truth"] == "UNKNOWN":
                continue
            outcome = "UNKNOWN" if r[method] == "UNKNOWN" else "wrong" if r[method] != r["truth"] else None
            if outcome:
                failures[(outcome, r["mechanical_class"], r["source"],
                          r["weapon_behavior"], r["historical_subgroup"])] += 1
        lines.append(f"- `{method}`: {sum(failures.values())} truth-known wrong/UNKNOWN rows.")
        for key, count in failures.most_common(5):
            lines.append(f"  - {count}: " + ", ".join(key))
    return lines


def main():
    rows = [json.loads(line) for line in gzip.open(OUT / "trials.jsonl.gz", "rt")]
    _validate_rows(rows)
    nominal, groups = _partitions(rows)
    results = {"starting_scorer_sha": START_SHA,
               "row_counts": dict(Counter(str(r["rough_factor"]) for r in rows)),
               "subgroup_case_counts": dict(Counter(r["historical_subgroup"] for r in nominal)),
               "rough_factor_all": {str(f): table([r for r in rows if r["rough_factor"] == f])
                                    for f in (.5, 1, 2)},
               "nominal_dimensions": {name: table(group) for name, group in groups.items()}}
    parent = results["nominal_dimensions"]["Combined all 288 turrets"]
    for field, values in DIMENSIONS.items():
        child_names = [display for display, _value in values if display in groups]
        for stack in STACKS:
            for count in ("cases", "TP", "FP", "TN", "FN", "truth_unknown"):
                assert sum(results["nominal_dimensions"][name][label(stack)][count]
                           for name in child_names) == parent[label(stack)][count], (field, label(stack), count)
    (OUT / "metrics.json").write_text(json.dumps(results, indent=1) + "\n")

    lines = ["# Expanded A4 ENGAGEABLE benchmark findings", "",
             "Status: **inference**, offline mechanical bearing/arc benchmark evidence. "
             "This task does not classify A5 failure causes or select a production method.", "",
             f"Accepted starting scorer SHA: `{START_SHA}`.", "",
             "The run contains 37,830 turret/scenario cases and 113,490 rows across rough-distance "
             "factors 0.5, 1, and 2. Nominal factor 1 contributes 37,830 rows. Single-point, "
             "multi-point, and boundary scenarios independently assign sorted turrets round-robin "
             "(6,990, 1,800, and 4,560 cases). All 74 known172 scenarios and all 11 synthetic "
             "stress scenarios run against all 288 turrets (21,312 and 3,168 cases). The existing "
             "24 component rotations cycle deterministically, offset so every turret walks distinct "
             "rotations across its repeat appearances rather than aliasing onto one.", "",
             "Each scenario/factor computes its direction, same-ray, three-ray, and three-ray4 query "
             "observations once. Turret scoring then places the selected reference endpoint at O using "
             "the record's ordered transforms and nearest-to-zero legal joint pose.", "",
             "Truth UNKNOWN rows are excluded from TP/FP/TN/FN rates. Prediction UNKNOWN is counted as "
             "player-view NOT ENGAGEABLE in ordinary sensitivity and accuracy, and is also reported separately.", "",
             "## Rough-distance sensitivity, all 288 turrets", ""]
    for factor in (.5, 1, 2):
        lines += [f"### Rough factor {factor}", "", markdown_table(results["rough_factor_all"][str(factor)]), ""]
    lines += ["## Nominal result by reporting dimension", ""]
    order = ["Combined all 288 turrets", "Official X4", "SWI 0.9.1 HF",
             "Feasible/realistic", "Synthetic stress", "Conventional", "Guided", "Dumb-fire",
             "Ordinary X/Y", "Bounded traverse", "Reversed X/Y", "Rotation-Z"]
    for name in order:
        if name in groups:
            lines += [f"### {name} ({len(groups[name]):,} rows)", "",
                      markdown_table(results["nominal_dimensions"][name]), ""]
    rare = lambda name, stack: metrics(groups[name], stack)  # noqa: E731
    bt_dir, bt_ray = rare("Bounded traverse", "direction"), rare("Bounded traverse", "same_ray")
    rx, rz = rare("Reversed X/Y", "direction"), rare("Rotation-Z", "direction")
    lines += ["## Observed group differences", "",
              "Expanded ordinary/official behavior is broadly consistent with historical A4 in showing "
              "few decided false-ENGAGEABLE results for same-ray and three-ray methods, while the changed "
              "corpus and exposure design produce different aggregate coverage and accuracy.", "",
              f"The rare classes are not hidden by the {len(groups['Ordinary X/Y']):,} nominal ordinary-X/Y rows. "
              f"Bounded-traverse direction has {bt_dir['FN']} false-NOT-ENGAGEABLE rows "
              f"(UNKNOWN counted as NOT ENGAGEABLE) and {bt_dir['model_unknown']} prediction-UNKNOWN rows among "
              f"{bt_dir['cases']:,} rows; same-ray has {bt_ray['FN']} false-NOT-ENGAGEABLE and "
              f"{bt_ray['model_unknown']} prediction-UNKNOWN. The reversed-X/Y turret has only "
              f"{rx['TP'] + rx['FN']} truth-ENGAGEABLE rows among {rx['cases']}, and direction identifies "
              f"{rx['TP']} of them as ENGAGEABLE. The rotation-Z turret has {rz['TP'] + rz['FN']} "
              f"truth-ENGAGEABLE rows among {rz['cases'] - rz['truth_unknown']} truth-known rows; "
              f"direction identifies {rz['TP']}.", "",
              "Known172 exposure is the largest prediction-UNKNOWN concentration for three-ray and three-ray4. "
              "Synthetic stress is the main concentration for direction and same-ray UNKNOWN behavior. These are "
              "failure groups for A5, not cause classifications.", ""]
    truth_unknown = Counter((r["mechanical_class"], r["truth_state"]) for r in nominal if r["truth"] == "UNKNOWN")
    lines += ["## Failure groups for later A5 analysis", ""] + _failure_summary(nominal)
    lines += ["", "Truth-UNKNOWN patterns:", ""]
    if truth_unknown:
        lines += [f"- {count}: `{mechanical}` / `{state}`" for (mechanical, state), count in truth_unknown.most_common()]
    else:
        lines += ["- None."]
    lines += ["", "## Limitations", "",
              "The selected A4x endpoint/reference pose is the offline coordinate definition. This run "
              "does not provide new live proof of emitted-muzzle runtime behavior. It also excludes range, "
              "line of sight, own-hull masking, projectile flight, missile guidance, and firing readiness.", ""]
    (HERE / "findings.md").write_text("\n".join(lines))
    print("rows", len(rows), "nominal", len(nominal), "truth UNKNOWN", sum(truth_unknown.values()))
    print("wrote", OUT / "metrics.json", "and", HERE / "findings.md")


if __name__ == "__main__":
    main()
