"""Issue #185 C5: apply the retained exact-point scorer to #184 recovery uncertainty."""
from __future__ import annotations

import importlib.util
import json
import math
import os
import sys
from collections import Counter
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
CACHE = ROOT / ".x4-research-cache/issue185-c5"
sys.path.insert(0, str(ROOT / "research/issue176-a4x"))
import scorer  # noqa: E402

SPEC = importlib.util.spec_from_file_location("issue184_aimpoint_map", ROOT / "research/issue184/aimpoint_map.py")
aimpoint_map = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(aimpoint_map)

RESULT = {True: "CAN AIM", False: "CANNOT BEAR", None: "UNKNOWN"}
YAW_PARTITIONS = 2048


def _local(case, point):
    return (np.asarray(point, float) - case["origin"]) @ case["frame"].T


def _ray_distance(point, origin, direction):
    distance = max(0.0, float(np.dot(point - origin, direction)))
    witness = origin + distance * direction
    return float(np.linalg.norm(point - witness)), witness


def _limit_ray(record, pitch, yaw):
    """The real target ray at one ordinary-X/Y settled pose, in turret-component space."""
    leaf, root, seg = scorer.segments(record)
    assert (root["axis"], leaf["axis"]) == ("y", "x")
    frame = scorer.compose(seg["G"], scorer.compose((scorer.ZERO, scorer.JOINT["y"](yaw)), seg["H"]))
    pose = scorer.compose(seg["L"], scorer.compose((scorer.ZERO, scorer.JOINT["x"](pitch)), frame))
    return np.asarray(frame[0]), np.asarray(pose[1][2])


def _ordinary_clearance(record, centre):
    """Minimum distance to either real pitch-limit aiming surface.

    An ordinary-X/Y turret has unlimited yaw. A point outside its pitch arc reaches the
    aimable set first at one authored pitch-limit surface. Minimise distance to each
    surface's positive target ray over the full periodic yaw domain.
    """
    leaf, _root, _seg = scorer.segments(record)
    best = (math.inf, None, None, None)
    step = 2 * math.pi / YAW_PARTITIONS

    def at(pitch, yaw):
        origin, direction = _limit_ray(record, pitch, yaw)
        distance, witness = _ray_distance(centre, origin, direction)
        return distance, witness

    for degrees in leaf["limits"]:
        pitch = math.radians(degrees)
        values = [at(pitch, -math.pi + i * step)[0] for i in range(YAW_PARTITIONS)]
        candidates = [i for i, value in enumerate(values)
                      if value <= values[i - 1] and value <= values[(i + 1) % YAW_PARTITIONS]]
        for i in candidates:
            lo, hi = -math.pi + (i - 1) * step, -math.pi + (i + 1) * step
            for _ in range(64):
                a = lo + (hi - lo) / 3
                b = hi - (hi - lo) / 3
                if at(pitch, a)[0] <= at(pitch, b)[0]:
                    hi = b
                else:
                    lo = a
            yaw = (lo + hi) / 2
            distance, witness = at(pitch, yaw)
            if distance < best[0]:
                best = distance, witness, degrees, yaw
    # UNKNOWN_pivot is genuine geometry uncertainty, not numerical precision. Find
    # whether the ball contains any pitch-pivot position on the same yaw circle.
    pitch = math.radians(leaf["limits"][0])
    values = [float(np.linalg.norm(centre - _limit_ray(record, pitch, -math.pi + i * step)[0]))
              for i in range(YAW_PARTITIONS)]
    pivot_best = math.inf
    candidates = [i for i, value in enumerate(values)
                  if value <= values[i - 1] and value <= values[(i + 1) % YAW_PARTITIONS]]
    for i in candidates:
        lo, hi = -math.pi + (i - 1) * step, -math.pi + (i + 1) * step
        for _ in range(64):
            a = lo + (hi - lo) / 3
            b = hi - (hi - lo) / 3
            da = float(np.linalg.norm(centre - _limit_ray(record, pitch, a)[0]))
            db = float(np.linalg.norm(centre - _limit_ray(record, pitch, b)[0]))
            if da <= db:
                hi = b
            else:
                lo = a
        pivot_best = min(pivot_best, float(np.linalg.norm(
            centre - _limit_ray(record, pitch, (lo + hi) / 2)[0])))
    return *best, pivot_best


def _uncertainty(record, centre, radius):
    """Apply C5 to the complete #184 ball for the benchmark's retained geometry."""
    central = scorer.score(record, tuple(map(float, centre)))
    if central["decision"] is True:
        return "CAN AIM", central["state"], centre, 0.0, None, None
    if record["mechanical_class"] != "ordinary_xy" or central["state"] != "OUT_OF_ARC":
        return "UNKNOWN", central["state"], None, None, None, None
    distance, boundary, limit, yaw, pivot_distance = _ordinary_clearance(record, centre)
    if distance <= radius:
        # Move from the centre only as far as the real limit surface; the accepted scorer
        # must independently confirm that this is an actual stable CAN AIM possibility.
        got = scorer.score(record, tuple(map(float, boundary)))
        if got["decision"] is not True:
            raise AssertionError((record["macro"], distance, radius, limit, yaw, got["state"]))
        return "CAN AIM", central["state"], boundary, distance, limit, pivot_distance
    if pivot_distance <= radius:
        return "UNKNOWN", central["state"], None, distance, limit, pivot_distance
    return "CANNOT BEAR", central["state"], None, distance, limit, pivot_distance


def _recover(case, margin):
    """The retained #184 A7.2 search and its existing post-search uncertainty refinement."""
    probe, stats = aimpoint_map.angular_probe(
        aimpoint_map.view(case), margin,
        primary=aimpoint_map.A7_PRIMARY, near_target=aimpoint_map.A6_NEAR_PAD,
    )
    audit = aimpoint_map.corner_audit(aimpoint_map.view(case), margin, probe)
    points = [(np.asarray(c, float), float(r)) for c, r in audit["points"]]
    refined, _count, _skipped = aimpoint_map.refine_points(points, stats["rays"])
    return refined, audit["queries"]


def _row(case, record, label, centre, radius, truth_index, queries):
    truth_world = np.asarray(case["points"][truth_index], float)
    truth_local, centre_local = _local(case, truth_world), _local(case, centre)
    exact = scorer.score(record, tuple(map(float, truth_local)))
    c5, centre_state, witness, reachable_distance, nearest_limit, pivot_distance = _uncertainty(
        record, centre_local, radius)
    exact_result = RESULT[exact["decision"]]
    return {
        "case_id": case["id"], "group": case["a7"], "gap": case["gap"],
        "target": case["target"], "ship": case["ship"], "mount": case["mount"],
        "turret": case["turret"], "mechanical_layout": record["mechanical_class"],
        "recovered_label": label, "hidden_point_index": truth_index,
        "hidden_exact_point_local": truth_local.tolist(),
        "recovered_centre_local": centre_local.tolist(), "uncertainty_radius": radius,
        "recovery_error": float(np.linalg.norm(centre - truth_world)), "queries": queries,
        "exact_state": exact["state"], "exact_result": exact_result, "c5_result": c5,
        "recovered_centre_state": centre_state,
        "nearest_reachable_distance": reachable_distance, "nearest_pitch_limit_degrees": nearest_limit,
        "nearest_pivot_distance": pivot_distance,
        "uncertainty_clearance": None if reachable_distance is None else reachable_distance - radius,
        "can_aim_witness_local": None if witness is None else witness.tolist(),
    }


def _report(rows, unusable):
    pairs = Counter((r["exact_result"], r["c5_result"]) for r in rows)
    flips = [r for r in rows if r["exact_result"] == "CANNOT BEAR" and r["c5_result"] == "CAN AIM"]
    unknown = [r for r in rows if r["exact_result"] == "UNKNOWN"]
    lines = [
        "# C5 aim-point-uncertainty benchmark findings", "",
        "Status: **inference**, offline mechanical bearing/arc benchmark evidence.", "",
        f"The benchmark contains **{len(rows):,} scenarios** from the retained #184 focused population. "
        "Each scenario is one definite recovered aim point, its unchanged #184 uncertainty ball, and the "
        "case's real selected turret and mount. Hidden authored points are used only for exact truth and audit.", "",
        "## Comparison", "",
        "| exact truth | C5 result | scenarios |", "|---|---|---:|",
    ]
    for exact in ("CAN AIM", "CANNOT BEAR"):
        for c5 in ("CAN AIM", "CANNOT BEAR", "UNKNOWN"):
            lines.append(f"| {exact} | {c5} | {pairs[exact, c5]:,} |")
    lines += ["", f"Genuine exact geometry UNKNOWN: **{len(unknown):,}**.", "",
              "## Exact CANNOT BEAR becoming C5 CAN AIM", ""]
    if flips:
        lines += ["| case | turret | layout | radius (m) | exact state | witness |",
                  "|---|---|---|---:|---|---|"]
        for r in flips:
            boundary = "near a real turret limit" if r["exact_state"] == "OUT_OF_ARC" else r["exact_state"]
            lines.append(f"| {r['case_id']} | `{r['turret']}` | {r['mechanical_layout']} | "
                         f"{r['uncertainty_radius']:.9g} | {r['exact_state']} | {boundary} |")
    else:
        lines.append("None.")
    negatives = sorted((r for r in rows if r["exact_result"] == "CANNOT BEAR"),
                       key=lambda r: r["uncertainty_clearance"])
    if negatives:
        closest = negatives[0]
        lines += ["", f"All {len(negatives):,} exact CANNOT BEAR scenarios are ordinary-X/Y OUT_OF_ARC "
                  "cases beyond a real authored pitch limit. None is near enough for the recovered uncertainty "
                  "to touch that limit: the closest uncertainty ball remains "
                  f"**{closest['uncertainty_clearance']:.6g} m** clear (limit surface "
                  f"{closest['nearest_reachable_distance']:.6g} m from the recovered centre versus a "
                  f"{closest['uncertainty_radius']:.6g} m #184 radius, "
                  f"{closest['nearest_reachable_distance'] / closest['uncertainty_radius']:.0f}x the radius).", "",
                  "Closest five exact CANNOT BEAR cases to a real limit:", "",
                  "| case | gap (m) | turret | limit | radius (m) | centre to limit (m) | clearance (m) |",
                  "|---|---:|---|---:|---:|---:|---:|"]
        for r in negatives[:5]:
            lines.append(f"| {r['case_id']} | {r['gap']} | `{r['turret']}` | "
                         f"{r['nearest_pitch_limit_degrees']:g}° | {r['uncertainty_radius']:.6g} | "
                         f"{r['nearest_reachable_distance']:.6g} | {r['uncertainty_clearance']:.6g} |")
    lines += ["", "## UNKNOWN and exclusions", ""]
    if unknown:
        lines += [f"- {r['case_id']}: `{r['exact_state']}` / C5 `{r['c5_result']}`" for r in unknown]
    else:
        lines.append("- No genuine exact geometry UNKNOWN scenario.")
    lines.append(f"- {unusable:,} recovered estimates were not definite: their uncertainty ball covered zero or multiple hidden points.")
    lines += ["", "## Scope", "",
              "For an ordinary-X/Y recovered centre outside the pitch arc, the C5 evaluation minimizes distance "
              "to both real authored pitch-limit aiming surfaces over the complete unlimited-yaw circle. The "
              f"periodic minimization partitions yaw {YAW_PARTITIONS:,} ways, refines every local minimum, and "
              "rechecks every overlap witness with the accepted exact-point scorer. This is search resolution, "
              "not an aim-point uncertainty or precision margin. Other negative geometry returns UNKNOWN rather "
              "than claiming complete coverage.", "",
              "It does not change the retained #185 scorer, #184 discovery, production code, range, firing solution, "
              "line of fire, firing permission, weapon readiness, projectile behavior, or final ENGAGEABLE.", ""]
    (HERE / "findings.md").write_text("\n".join(lines))


def main():
    os.nice(10)
    records, margins, mounts, _excluded, _inferred = aimpoint_map.load()
    cases = list(aimpoint_map.a7_variants(aimpoint_map.targets(), mounts))
    CACHE.mkdir(parents=True, exist_ok=True)
    rows, unusable = [], 0
    with open(CACHE / "benchmark.jsonl", "w") as stream:
        for number, case in enumerate(cases, 1):
            recovered, queries = _recover(case, margins[case["ship_class"]][0])
            for label, (centre, radius) in enumerate(recovered):
                cover = [i for i, point in enumerate(case["points"])
                         if np.linalg.norm(centre - point) <= radius]
                if len(cover) != 1:
                    unusable += 1
                    continue
                row = _row(case, records[case["turret"]], label, centre, radius, cover[0], queries)
                rows.append(row)
                stream.write(json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n")
            stream.flush()
            print(f"{number}/{len(cases)} case {case['id']} @{case['gap']}m: "
                  f"{len(recovered)} recovered, {len(rows)} scenarios", flush=True)
    _report(rows, unusable)
    pairs = Counter((r["exact_result"], r["c5_result"]) for r in rows)
    print(f"PASS: {len(rows)} scenarios; {unusable} unusable recovered estimates")
    for pair in (("CAN AIM", "CAN AIM"), ("CAN AIM", "CANNOT BEAR"), ("CAN AIM", "UNKNOWN"),
                 ("CANNOT BEAR", "CANNOT BEAR"), ("CANNOT BEAR", "CAN AIM"),
                 ("CANNOT BEAR", "UNKNOWN")):
        print(f"exact {pair[0]} -> C5 {pair[1]}: {pairs[pair]}")
    print("genuine exact geometry UNKNOWN:", sum(r["exact_result"] == "UNKNOWN" for r in rows))


if __name__ == "__main__":
    main()
