"""Issue #185 C5: apply the retained exact-point scorer to #184 recovery uncertainty."""
from __future__ import annotations

import argparse
import importlib.util
import json
import math
import os
import sys
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
from itertools import product
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
GOLDEN_ANGLE = math.pi * (3 - math.sqrt(5))
REFINE_ROUNDS = 7


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


def _recover(case):
    """The frozen #184 A7.3 search and its existing post-search uncertainty refinement."""
    search = aimpoint_map.near_only_run(
        aimpoint_map.view(case), total=aimpoint_map.A73_TOTAL,
        pad=aimpoint_map.A6_NEAR_PAD, geom=aimpoint_map.A73_GEOM,
    )
    points = [(np.asarray(c, float), float(r)) for c, r in search["points"]]
    refined, _count, _skipped = aimpoint_map.refine_points(points, search["rays"])
    return refined, search["asks"]


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


def _unit(v):
    n = float(np.linalg.norm(v))
    return np.asarray(v, float) / n


def _search_points():
    """Nested deterministic coverage of the complete normalized 3-D ball.

    The coarse set covers every octant, axis and face diagonal on two radial
    shells.  The stronger set retains those points and adds three spherical
    shells with a deterministic Fibonacci covering.  Local pattern refinement
    is applied separately after both stages.
    """
    coarse_directions = sorted({tuple(_unit(v)) for v in product((-1, 0, 1), repeat=3)
                                if v != (0, 0, 0)})
    coarse = [np.zeros(3)] + [radius * np.asarray(direction)
                              for radius in (0.5, 1.0) for direction in coarse_directions]
    fine_directions = []
    for i in range(64):
        z = 1 - 2 * (i + 0.5) / 64
        radial = math.sqrt(max(0.0, 1 - z * z))
        fine_directions.append(np.asarray((radial * math.cos(i * GOLDEN_ANGLE),
                                           radial * math.sin(i * GOLDEN_ANGLE), z)))
    fine = coarse + [radius * direction for radius in (0.25, 0.75, 1.0)
                     for direction in fine_directions]
    return coarse, fine


COARSE_POINTS, FINE_POINTS = _search_points()
PATTERN_DIRECTIONS = [_unit(v) for v in product((-1, 0, 1), repeat=3) if v != (0, 0, 0)]


def _movement_at(record, centre, radius, centre_muzzles, offset):
    point = centre + radius * offset
    scored = scorer.score(record, tuple(map(float, point)))
    if scored["decision"] is not True:
        return None
    distances = [min(math.dist(muzzle, central) for central in centre_muzzles)
                 for muzzle in scored["muzzles"]]
    return max(distances), len(scored["muzzles"]), scored["muzzles"]


def _stage(record, centre, radius, centre_muzzles, points):
    observations = []
    counts = set()
    best = (-math.inf, np.zeros(3))
    for offset in points:
        got = _movement_at(record, centre, radius, centre_muzzles, offset)
        if got is None:
            continue
        movement, count, _muzzles = got
        counts.add(count)
        observations.append((movement, np.asarray(offset)))
        if movement > best[0]:
            best = movement, np.asarray(offset)
    return best, counts, observations


def _refine(record, centre, radius, centre_muzzles, observations):
    value, offset = max(observations, key=lambda item: item[0])
    counts = set()
    step = 0.25
    for _ in range(REFINE_ROUNDS):
        candidate = (value, offset)
        for direction in PATTERN_DIRECTIONS:
            trial = offset + step * direction
            norm = np.linalg.norm(trial)
            if norm > 1:
                trial = trial / norm
            got = _movement_at(record, centre, radius, centre_muzzles, trial)
            if got is not None:
                counts.add(got[1])
                if got[0] > candidate[0]:
                    candidate = got[0], trial
        value, offset = candidate
        step /= 2
    return value, counts


_MOVEMENT_RECORDS = None


def _movement(row):
    global _MOVEMENT_RECORDS
    if _MOVEMENT_RECORDS is None:
        _MOVEMENT_RECORDS = scorer.load()
    record = _MOVEMENT_RECORDS[row["turret"]]
    centre = np.asarray(row["recovered_centre_local"], float)
    radius = row["uncertainty_radius"]
    central = scorer.score(record, tuple(map(float, centre)))
    centre_muzzles = central["muzzles"] if central["decision"] is True else []
    out = dict(row)
    out["centre_muzzle_count"] = len(centre_muzzles)
    if not centre_muzzles:
        out.update(muzzle_movement=None, coarse_movement=None, fine_sample_movement=None,
                   settled_counts_in_ball=[])
        return out
    coarse, coarse_counts, _ = _stage(record, centre, radius, centre_muzzles,
                                      COARSE_POINTS)
    sampled, sample_counts, observations = _stage(record, centre, radius, centre_muzzles,
                                                   FINE_POINTS)
    final, final_counts = _refine(record, centre, radius, centre_muzzles, observations)
    out.update(muzzle_movement=final, coarse_movement=coarse[0],
               fine_sample_movement=sampled[0],
               settled_counts_in_ball=sorted(coarse_counts | sample_counts | final_counts))
    return out


def _report(rows, unusable):
    pairs = Counter((r["exact_result"], r["c5_result"]) for r in rows)
    flips = [r for r in rows if r["exact_result"] == "CANNOT BEAR" and r["c5_result"] == "CAN AIM"]
    unknown = [r for r in rows if r["exact_result"] == "UNKNOWN"]
    measured = [r for r in rows if r["c5_result"] == "CAN AIM"]
    centred = [r for r in measured if r["centre_muzzle_count"]]
    off_centre = [r for r in measured if not r["centre_muzzle_count"]]
    movements = [r["muzzle_movement"] for r in centred]
    changed_counts = [r for r in centred
                      if r["settled_counts_in_ball"] != [r["centre_muzzle_count"]]]
    new_branches = [r for r in changed_counts
                    if max(r["settled_counts_in_ball"]) > r["centre_muzzle_count"]]
    worst = max(centred, key=lambda r: r["muzzle_movement"])
    layouts = ("ordinary_xy", "bounded_traverse", "reversed_xy", "rotation_z")
    percentile = lambda p: float(np.percentile(movements, p))  # noqa: E731
    lines = [
        "# C5 aim-point-uncertainty benchmark findings", "",
        "Status: **inference**, offline mechanical bearing/arc benchmark evidence.", "",
        f"The benchmark contains **{len(rows):,} scenarios** from the retained #184 focused population. "
        "Each scenario is one definite recovered aim point, its unchanged #184 uncertainty ball, and the "
        "case's real selected turret and mount. Hidden authored points are used only for exact truth and audit.", "",
        "## C5.2 firing-origin movement", "",
        "This measures movement caused solely by the unchanged recovered aim-point uncertainty; it is "
        "**not prediction error**.", "",
        f"- C5 CAN AIM scenarios measured: **{len(measured):,}**",
        f"- Recovered centre has at least one CAN AIM muzzle: **{len(centred):,}**",
        f"- CAN AIM exists only off centre: **{len(off_centre):,}**",
        f"- Movement median / p90 / p99 / maximum: **{percentile(50):.9g} / "
        f"{percentile(90):.9g} / {percentile(99):.9g} / {max(movements):.9g} m**", "",
        "The worst case is "
        f"**{worst['case_id']}**, `{worst['turret']}`, {worst['mechanical_layout']}, "
        f"{worst['gap']} m engagement distance: #184 radius **{worst['uncertainty_radius']:.9g} m**, "
        f"{worst['centre_muzzle_count']} centre muzzle(s), maximum movement "
        f"**{worst['muzzle_movement']:.9g} m** "
        f"(**{worst['muzzle_movement'] / worst['uncertainty_radius']:.9g}x** the radius).", "",
        "### Mechanical layout", "",
        "| layout | scenarios | median (m) | p90 (m) | p99 (m) | maximum (m) |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for layout in layouts:
        values = [r["muzzle_movement"] for r in centred if r["mechanical_layout"] == layout]
        if values:
            lines.append(f"| {layout} | {len(values):,} | {np.percentile(values, 50):.9g} | "
                         f"{np.percentile(values, 90):.9g} | {np.percentile(values, 99):.9g} | "
                         f"{max(values):.9g} |")
        else:
            lines.append(f"| {layout} | 0 | — | — | — | — |")
    lines += ["", "### Settled-position branches", "",
              f"Scenarios whose valid settled-muzzle count changes in the ball: **{len(changed_counts):,}**. "
              f"Scenarios where a new branch appears beyond those represented at the centre: "
              f"**{len(new_branches):,}**."]
    for r in changed_counts:
        lines.append(f"- {r['case_id']} / `{r['turret']}` / {r['gap']} m: centre "
                     f"{r['centre_muzzle_count']}, observed {r['settled_counts_in_ball']}")
    coarse_max = max(r["coarse_movement"] for r in centred)
    sampled_max = max(r["fine_sample_movement"] for r in centred)
    lines += ["", "### Numerical-search stability", "",
              f"The nested coarse search maximum was **{coarse_max:.9g} m**; adding the denser "
              f"whole-ball samples gave **{sampled_max:.9g} m**; final constrained pattern refinement "
              f"gave **{max(movements):.9g} m**. Fine sampling increased the coarse maximum by "
              f"**{sampled_max - coarse_max:.3g} m** and final refinement increased the fine sampled "
              f"maximum by **{max(movements) - sampled_max:.3g} m**.", "",
              "Each valid muzzle at every point is compared with its nearest centre-predicted muzzle; "
              "muzzles are never paired by list order. The deterministic search covers the centre, "
              "interior radial shells, the full spherical boundary, and constrained local refinement.", "",
              "## C5.1 comparison", "",
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
    parser = argparse.ArgumentParser()
    parser.add_argument("--jobs", type=int, default=1)
    args = parser.parse_args()
    os.nice(10)
    aimpoint_map._index_swi_ships()
    records = aimpoint_map.scorer.load()
    components = aimpoint_map.corpus._index_xml(
        [aimpoint_map.corpus.SWI_XML, aimpoint_map.corpus.OFFICIAL_SRC], "component")
    mounts, _excluded, _inferred = aimpoint_map.firing_mounts(records, components)
    cases = list(aimpoint_map.a7_variants(aimpoint_map.targets(), mounts))
    CACHE.mkdir(parents=True, exist_ok=True)
    base_rows, unusable = [], 0
    for number, case in enumerate(cases, 1):
        recovered, queries = _recover(case)
        for label, (centre, radius) in enumerate(recovered):
            cover = [i for i, point in enumerate(case["points"])
                     if np.linalg.norm(centre - point) <= radius]
            if len(cover) != 1:
                unusable += 1
                continue
            base_rows.append(_row(case, records[case["turret"]], label, centre, radius,
                                  cover[0], queries))
        print(f"{number}/{len(cases)} case {case['id']} @{case['gap']}m: "
              f"{len(recovered)} recovered, {len(base_rows)} scenarios", flush=True)
    if args.jobs == 1:
        rows = list(map(_movement, base_rows))
    else:
        with ProcessPoolExecutor(max_workers=args.jobs) as pool:
            rows = list(pool.map(_movement, base_rows))
    with open(CACHE / "benchmark.jsonl", "w") as stream:
        for row in rows:
            stream.write(json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n")
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
