"""Full exact supplied-aim-point CANNOT BEAR truth benchmark for issue #185 C2."""
from __future__ import annotations

import gzip
import json
import math
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / ".x4-research-cache/issue185-c2/benchmark.jsonl.gz"
sys.path.insert(0, str(ROOT / "research/issue176-a4x"))

import scorer  # noqa: E402


DISTANCES = (100.0, 8000.0)
LIMIT_OFFSET_DEGREES = 0.1
NORMAL_DIRECTION = tuple(v / math.sqrt(1.13) for v in (0.2, 0.3, 1.0))
EXPECTED_SOURCES = {"official": 124, "swi": 164}
EXPECTED_LAYOUTS = {"ordinary_xy": 278, "bounded_traverse": 8,
                    "reversed_xy": 1, "rotation_z": 1}
EXPECTED_USABLE_LIMITS = 413
EXPECTED_TURRETS_WITH_USABLE_LIMITS = 284
KNOWN_MULTI_MUZZLE_CASE = (
    "official:turret_bor_l_disruptor_01_mk1_macro:"
    "limit-leaf-x-max-reachable-side-100m"
)
CATEGORIES = ("normal supported", "difficult supported", "stress-only")
RESULT = {True: "CAN AIM", False: "CANNOT BEAR", None: "UNKNOWN"}


def _counter(rows, field):
    return Counter(row[field] for row in rows)


def _table(counter, order):
    return "\n".join(f"| {name} | {counter[name]:,} |" for name in order)


def _neutral(limits):
    if limits is None or limits[0] <= 0 <= limits[1]:
        return 0.0
    return math.radians(sum(limits) / 2)


def _limit_point(record, role, angle_degrees, distance):
    leaf, root, segments = scorer.segments(record)
    leaf_angle, root_angle = _neutral(leaf["limits"]), _neutral(root["limits"])
    if role == "leaf":
        leaf_angle = math.radians(angle_degrees)
    else:
        root_angle = math.radians(angle_degrees)
    frame = scorer.compose(
        segments["G"],
        scorer.compose((scorer.ZERO, scorer.JOINT[root["axis"]](root_angle)), segments["H"]),
    )
    pose = scorer.compose(
        segments["L"],
        scorer.compose((scorer.ZERO, scorer.JOINT[leaf["axis"]](leaf_angle)), frame),
    )
    return tuple(frame[0][i] + distance * pose[1][2][i] for i in range(3))


def _score(turret, record, case_id, category, point, **fields):
    truth = scorer.score(record, point)
    return {
        "case_id": f"{turret}:{case_id}",
        "turret": turret,
        "source": record["source"],
        "mechanical_layout": record["mechanical_class"],
        "case_category": category,
        "supplied_exact_aim_point": list(point),
        "scorer_state": truth["state"],
        "result": RESULT[truth["decision"]],
        "predicted_muzzle_positions": [list(position) for position in truth.get("muzzles", [])],
        **fields,
    }


def _limit_rows(turret, record):
    retained = []
    leaf, root, _segments = scorer.segments(record)
    for role, joint in (("leaf", leaf), ("root", root)):
        if joint["limits"] is None:
            continue
        for edge, limit, sign in (("min", joint["limits"][0], 1),
                                  ("max", joint["limits"][1], -1)):
            rows = []
            for distance in DISTANCES:
                for side, angle in (("reachable-side", limit + sign * LIMIT_OFFSET_DEGREES),
                                    ("unreachable-side", limit - sign * LIMIT_OFFSET_DEGREES)):
                    rows.append(_score(
                        turret, record,
                        f"limit-{role}-{joint['axis']}-{edge}-{side}-{distance:g}m",
                        "difficult supported", _limit_point(record, role, angle, distance),
                        distance=distance, case_kind="mechanical-limit", joint_role=role,
                        joint_axis=joint["axis"], limit_edge=edge,
                        authored_limit_degrees=limit, side=side,
                    ))
            results = {(row["distance"], row["side"]): row["result"] for row in rows}
            states = {(row["distance"], row["side"]): row["scorer_state"] for row in rows}
            if any(results[d, "reachable-side"] == "CAN AIM" and
                   states[d, "unreachable-side"] == "OUT_OF_ARC" for d in DISTANCES):
                retained.extend(rows)
    return retained


def _distance_changes(rows):
    paired = {}
    for row in rows:
        if row["distance"] == 0:
            continue
        key = row["case_id"].rsplit("-", 1)[0]
        paired.setdefault(key, set()).add((row["result"], row["scorer_state"]))
    return sum(len(outcomes) > 1 for outcomes in paired.values())


def _write_findings(rows, usable_limits, turrets_with_limits):
    by_source = _counter(rows, "source")
    by_layout = _counter(rows, "mechanical_layout")
    by_category = _counter(rows, "case_category")
    by_result = _counter(rows, "result")
    unusual = Counter((row["mechanical_layout"], row["result"]) for row in rows
                      if row["mechanical_layout"] != "ordinary_xy")
    unknown = Counter((row["mechanical_layout"], row["scorer_state"]) for row in rows
                      if row["result"] == "UNKNOWN")

    lines = [
        "# CANNOT BEAR exact-point benchmark findings", "",
        "Status: **inference**, offline mechanical bearing/arc benchmark evidence.", "",
        f"The benchmark contains **{len(rows):,} cases** over all 288 supported turrets. It "
        "performs no aim-point discovery and compares no candidate method, so no accuracy "
        "metric applies.", "",
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
        "", "These remaining UNKNOWN rows place the aim point exactly at the fixed joint pivot. "
        "X4 skips the zero-length direction solve there, so the accepted analysis cannot establish "
        "a usable stable position. No UNKNOWN row remains because of hidden current position, "
        "movement, traps, or a wide root limit.",
        "", "## Geometry coverage", "",
        "The retained nonzero distances are **100 m and 8,000 m**. The 100 m near case is "
        "an accepted #176 distance scale where offsets remain material; 8,000 m is a realistic "
        "distant-target control. Repeating the same normal bearing and every limit pair at "
        "both distances exposes offset-rotating-part effects without a large distance sweep. "
        f"The accepted result or state changes with distance for **{_distance_changes(rows)}** "
        "otherwise-identical constructions, confirming that the population is not direction-only.", "",
        f"The benchmark retains **{usable_limits:,} usable authored joint boundaries** across "
        f"**{turrets_with_limits:,} turrets**. For each boundary it poses the accepted geometry "
        "at 0.1 degrees inside and outside the authored limit and supplies a point from the "
        "joint pivot along that posed bore at both distances. A boundary is retained only "
        "when the accepted scorer observes a CAN AIM / OUT_OF_ARC transition at one or both "
        "distances. The four uncovered turrets are ordinary X/Y "
        "layouts with unlimited traverse and a -90/+90 degree leaf arc, so they have no "
        "reachable/unreachable mechanical transition to bracket.", "",
        "Every turret also receives the two-distance normal bearing and one component-origin "
        "stress case. Unusual layouts retain their own generated limit cases and separate "
        "reporting rather than inheriting ordinary-X/Y evidence. This targeted population "
        "covers distance sensitivity and real reach transitions without recreating the "
        "37,830-case #176 benchmark.", "",
        "The accepted #176 corpus and corrected exact-point scorer are reused. This benchmark excludes "
        "aim-point uncertainty, range, firing solution, line of fire, firing permission, "
        "weapon readiness, projectile behavior, and final ENGAGEABLE. It adds no LIVE evidence.", "",
    ]
    (HERE / "findings.md").write_text("\n".join(lines))


def _validate(records, rows):
    if len(records) != 288:
        raise AssertionError(f"supported turret count drift: {len(records)}")
    if Counter(record["source"] for record in records.values()) != EXPECTED_SOURCES:
        raise AssertionError("source turret counts drift")
    if Counter(record["mechanical_class"] for record in records.values()) != EXPECTED_LAYOUTS:
        raise AssertionError("mechanical layouts drift")
    base = Counter(row["turret"] for row in rows
                   if row["case_category"] != "difficult supported")
    if set(base) != set(records) or set(base.values()) != {3}:
        raise AssertionError("one or more supported turrets lack normal/stress coverage")
    if set(_counter(rows, "result")) - set(RESULT.values()):
        raise AssertionError("invalid C1 result")
    for layout in EXPECTED_LAYOUTS:
        subset = [row for row in rows if row["mechanical_layout"] == layout]
        if not subset or set(row["case_category"] for row in subset) != set(CATEGORIES):
            raise AssertionError(f"incomplete category coverage for {layout}")
    if not {"CAN AIM", "CANNOT BEAR", "UNKNOWN"}.issubset(_counter(rows, "result")):
        raise AssertionError("benchmark no longer exercises every C1 result")
    if any(not row["predicted_muzzle_positions"] for row in rows
           if row["result"] == "CAN AIM"):
        raise AssertionError("CAN AIM row lacks a predicted muzzle position")
    if any(row["predicted_muzzle_positions"] for row in rows
           if row["result"] != "CAN AIM"):
        raise AssertionError("CANNOT BEAR/UNKNOWN row invents a predicted muzzle position")
    muzzle_layouts = {row["mechanical_layout"] for row in rows
                      if row["predicted_muzzle_positions"]}
    if muzzle_layouts != set(EXPECTED_LAYOUTS):
        raise AssertionError(f"muzzle output layout coverage drift: {sorted(muzzle_layouts)}")
    multi = {row["case_id"]: row for row in rows
             if len(row["predicted_muzzle_positions"]) > 1}
    if KNOWN_MULTI_MUZZLE_CASE not in multi:
        raise AssertionError("known multi-stable-position case lost one or more muzzles")
    unknown = [row for row in rows if row["result"] == "UNKNOWN"]
    if {row["scorer_state"] for row in unknown} != {"UNKNOWN_pivot"}:
        raise AssertionError("hidden turret state must not make exact-point bearing UNKNOWN")
    no_rest = {(row["mechanical_layout"], row["result"])
               for row in rows if row["scorer_state"] == "NO_STABLE_POSITION"}
    if not {("ordinary_xy", "CANNOT BEAR"), ("rotation_z", "CANNOT BEAR")} <= no_rest:
        raise AssertionError("proven no-rest cases must be CANNOT BEAR")

    ball = records["swi:turret_s_gauntlet_macro"]
    wide_limit = _limit_point(ball, "root", 90.0, 100.0)
    if scorer.score(ball, wide_limit)["decision"] is not True:
        raise AssertionError("a wide-root-limit stable aiming position must be CAN AIM")
    if not _distance_changes(rows):
        raise AssertionError("benchmark no longer exposes distance-sensitive scorer behavior")

    limits = [row for row in rows if row.get("case_kind") == "mechanical-limit"]
    keys = {(row["turret"], row["joint_role"], row["joint_axis"], row["limit_edge"])
            for row in limits}
    if len(keys) != EXPECTED_USABLE_LIMITS:
        raise AssertionError(f"usable mechanical-limit count drift: {len(keys)}")
    covered = {key[0] for key in keys}
    if len(covered) != EXPECTED_TURRETS_WITH_USABLE_LIMITS:
        raise AssertionError(f"turret mechanical-limit coverage drift: {len(covered)}")
    for turret in set(records) - covered:
        leaf, root, _segments = scorer.segments(records[turret])
        if records[turret]["mechanical_class"] != "ordinary_xy" or \
                leaf["limits"] != [-90.0, 90.0] or root["limits"] is not None:
            raise AssertionError(f"turret unexpectedly lacks a usable mechanical limit: {turret}")
    for key in keys:
        group = [row for row in limits if
                 (row["turret"], row["joint_role"], row["joint_axis"], row["limit_edge"]) == key]
        if {(row["distance"], row["side"]) for row in group} != {
            (distance, side) for distance in DISTANCES
            for side in ("reachable-side", "unreachable-side")
        }:
            raise AssertionError(f"incomplete mechanical-limit pair: {key}")
        results = {(row["distance"], row["side"]): row["result"] for row in group}
        states = {(row["distance"], row["side"]): row["scorer_state"] for row in group}
        if not any(results[d, "reachable-side"] == "CAN AIM" and
                   states[d, "unreachable-side"] == "OUT_OF_ARC" for d in DISTANCES):
            raise AssertionError(f"mechanical limit has no accepted transition: {key}")
    unusual = {row["mechanical_layout"] for row in limits
               if row["mechanical_layout"] != "ordinary_xy"}
    if unusual != {"bounded_traverse", "reversed_xy", "rotation_z"}:
        raise AssertionError(f"unusual mechanical-limit coverage drift: {sorted(unusual)}")


def main():
    try:
        records = scorer.load()
    except FileNotFoundError as exc:
        raise SystemExit(
            "accepted corpus cache missing; run python3 research/issue176-a4x/corpus.py"
        ) from exc

    rows = []
    for index, (turret, record) in enumerate(sorted(records.items()), 1):
        for distance in DISTANCES:
            point = tuple(distance * component for component in NORMAL_DIRECTION)
            rows.append(_score(turret, record, f"normal-oblique-{distance:g}m",
                               "normal supported", point, distance=distance,
                               case_kind="normal-oblique"))
        rows.extend(_limit_rows(turret, record))
        rows.append(_score(turret, record, "component-origin", "stress-only", scorer.ZERO,
                           distance=0.0, case_kind="component-origin"))
        if index % 24 == 0:
            print(f"scored {index}/288 turrets", flush=True)

    _validate(records, rows)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(OUT, "wt") as stream:
        for row in rows:
            stream.write(json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n")
    limits = {(row["turret"], row["joint_role"], row["joint_axis"], row["limit_edge"])
              for row in rows if row.get("case_kind") == "mechanical-limit"}
    _write_findings(rows, len(limits), len({key[0] for key in limits}))
    print(f"PASS: {len(rows)} cases; wrote {OUT} and {HERE / 'findings.md'}")
    print("sources", dict(_counter(rows, "source")))
    print("layouts", dict(_counter(rows, "mechanical_layout")))
    print("categories", dict(_counter(rows, "case_category")))
    print("results", dict(_counter(rows, "result")))
    multi = [row for row in rows if len(row["predicted_muzzle_positions"]) > 1]
    maximum = max(len(row["predicted_muzzle_positions"]) for row in multi)
    print(f"multi-muzzle PASS: {len(multi)} cases; max {maximum} muzzles; "
          f"known case {KNOWN_MULTI_MUZZLE_CASE}")


if __name__ == "__main__":
    main()
