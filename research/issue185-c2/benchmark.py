"""Full exact supplied-aim-point CANNOT BEAR truth benchmark for issue #185 C2."""
from __future__ import annotations

import gzip
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / ".x4-research-cache/issue185-c2/benchmark.jsonl.gz"
sys.path.insert(0, str(ROOT / "research/issue176-a4x"))

import scorer  # noqa: E402


# Supplied component-frame points, applied unchanged to every turret.
POINTS = (
    ("forward", "normal supported", (0.0, 0.0, 1000.0)),
    ("forward-oblique", "normal supported", (200.0, 300.0, 1000.0)),
    ("astern", "difficult supported", (0.0, 0.0, -1000.0)),
    ("right-axis", "difficult supported", (1000.0, 0.0, 0.0)),
    ("left-axis", "difficult supported", (-1000.0, 0.0, 0.0)),
    ("up-axis", "difficult supported", (0.0, 1000.0, 0.0)),
    ("down-axis", "difficult supported", (0.0, -1000.0, 0.0)),
    ("component-origin", "stress-only", (0.0, 0.0, 0.0)),
)
EXPECTED_SOURCES = {"official": 124, "swi": 164}
EXPECTED_LAYOUTS = {"ordinary_xy": 278, "bounded_traverse": 8,
                    "reversed_xy": 1, "rotation_z": 1}
CATEGORIES = ("normal supported", "difficult supported", "stress-only")
RESULT = {True: "CAN AIM", False: "CANNOT BEAR", None: "UNKNOWN"}


def _counter(rows, field):
    return Counter(row[field] for row in rows)


def _table(counter, order):
    return "\n".join(f"| {name} | {counter[name]:,} |" for name in order)


def _write_findings(rows):
    by_source = _counter(rows, "source")
    by_layout = _counter(rows, "mechanical_layout")
    by_category = _counter(rows, "case_category")
    by_result = _counter(rows, "result")
    unusual = Counter((row["mechanical_layout"], row["result"]) for row in rows
                      if row["mechanical_layout"] != "ordinary_xy")
    unknown = Counter((row["mechanical_layout"], row["scorer_state"]) for row in rows
                      if row["result"] == "UNKNOWN")

    lines = [
        "# CANNOT BEAR exact-point benchmark findings",
        "",
        "Status: **inference**, offline mechanical bearing/arc benchmark evidence.",
        "",
        f"The benchmark contains **{len(rows):,} cases**: the same eight supplied exact "
        "component-frame points for each of all 288 supported turrets. It performs no "
        "aim-point discovery and compares no candidate method, so no accuracy metric applies.",
        "",
        "## Population", "",
        "| source | cases |", "|---|---:|", _table(by_source, ("official", "swi")), "",
        "| mechanical layout | cases |", "|---|---:|", _table(by_layout, EXPECTED_LAYOUTS), "",
        "| case category | cases |", "|---|---:|", _table(by_category, CATEGORIES), "",
        "| accepted C1 result | cases |", "|---|---:|",
        _table(by_result, ("CAN AIM", "CANNOT BEAR", "UNKNOWN")), "",
        "## Unusual layouts", "",
        "| layout | CAN AIM | CANNOT BEAR | UNKNOWN |", "|---|---:|---:|---:|",
    ]
    for layout in ("bounded_traverse", "reversed_xy", "rotation_z"):
        lines.append("| " + layout + " | " + " | ".join(
            str(unusual[(layout, result)]) for result in ("CAN AIM", "CANNOT BEAR", "UNKNOWN")) + " |")
    lines += ["", "## Scorer UNKNOWN patterns", ""]
    lines += ([f"- {count:,}: `{layout}` / `{state}`"
               for (layout, state), count in unknown.most_common()] or ["- None."])
    lines += [
        "", "## Scope", "",
        "The two normal points cover routine forward/oblique bearings. The five difficult "
        "points cover astern and the four component axes, including exact 90-degree limits "
        "and poles. The component origin is reported only as stress. Applying this static "
        "set to every turret prevents the 278 ordinary X/Y turrets from substituting for "
        "the ten unusual-layout turrets.", "",
        "The accepted #176 corpus and scorer are reused unchanged. This benchmark excludes "
        "aim-point uncertainty, range, firing solution, line of fire, firing permission, "
        "weapon readiness, projectile behavior, and final ENGAGEABLE. It adds no LIVE evidence.", "",
    ]
    (HERE / "findings.md").write_text("\n".join(lines))


def _validate(records, rows):
    if len(records) != 288:
        raise AssertionError(f"supported turret count drift: {len(records)}")
    source_turrets = Counter(record["source"] for record in records.values())
    layout_turrets = Counter(record["mechanical_class"] for record in records.values())
    if source_turrets != EXPECTED_SOURCES:
        raise AssertionError(f"source turret counts drift: {dict(source_turrets)}")
    if layout_turrets != EXPECTED_LAYOUTS:
        raise AssertionError(f"mechanical layouts drift: {dict(layout_turrets)}")
    if _counter(rows, "case_category") != {
        category: len(records) * sum(point[1] == category for point in POINTS)
        for category in CATEGORIES
    }:
        raise AssertionError("case-category coverage mismatch")
    coverage = Counter(row["turret"] for row in rows)
    if set(coverage) != set(records) or set(coverage.values()) != {len(POINTS)}:
        raise AssertionError("one or more supported turrets lack complete benchmark coverage")
    if set(_counter(rows, "result")) - set(RESULT.values()):
        raise AssertionError("invalid C1 result")
    for layout in EXPECTED_LAYOUTS:
        subset = [row for row in rows if row["mechanical_layout"] == layout]
        if not subset or set(row["case_category"] for row in subset) != set(CATEGORIES):
            raise AssertionError(f"incomplete category coverage for {layout}")
    if not {"CAN AIM", "CANNOT BEAR", "UNKNOWN"}.issubset(_counter(rows, "result")):
        raise AssertionError("benchmark no longer exercises every C1 result")


def main():
    try:
        records = scorer.load()
    except FileNotFoundError as exc:
        raise SystemExit(
            "accepted corpus cache missing; run python3 research/issue176-a4x/corpus.py"
        ) from exc

    rows = []
    for index, (turret, record) in enumerate(sorted(records.items()), 1):
        for point_id, category, aim_point in POINTS:
            truth = scorer.score(record, aim_point)
            rows.append({
                "case_id": f"{turret}:{point_id}",
                "turret": turret,
                "source": record["source"],
                "mechanical_layout": record["mechanical_class"],
                "case_category": category,
                "supplied_exact_aim_point": list(aim_point),
                "scorer_state": truth["state"],
                "result": RESULT[truth["decision"]],
            })
        if index % 24 == 0:
            print(f"scored {index}/288 turrets", flush=True)

    _validate(records, rows)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(OUT, "wt") as stream:
        for row in rows:
            stream.write(json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n")
    _write_findings(rows)
    print(f"PASS: {len(rows)} cases; wrote {OUT} and {HERE / 'findings.md'}")
    print("sources", dict(_counter(rows, "source")))
    print("layouts", dict(_counter(rows, "mechanical_layout")))
    print("categories", dict(_counter(rows, "case_category")))
    print("results", dict(_counter(rows, "result")))


if __name__ == "__main__":
    main()
