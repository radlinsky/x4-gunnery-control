"""Expanded A4 ENGAGEABLE benchmark over the accepted 288-turret corpus.

The prediction methods and target scenarios are imported unchanged from historical A4.
Query observations are built once per scenario/factor and then scored against the assigned
turrets. This is research-only bearing/arc work; scorer.py is the mechanical truth oracle.
"""
from __future__ import annotations

import argparse
import gzip
import importlib.util
import json
import math
import os
import sys
from collections import Counter
from multiprocessing import Pool
from pathlib import Path

import numpy as np

for _var in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"):
    os.environ.setdefault(_var, "1")

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE)]
_spec = importlib.util.spec_from_file_location("issue176_historical_a4_compare",
                                               ROOT / "research/issue176-a4/compare.py")
historical = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(historical)
import scorer  # noqa: E402

OUT = ROOT / ".x4-research-cache/issue176-a4x"
FACTORS = historical.FACTORS
METHODS = ("baseline", "direction", "same_ray", "three_ray", "three_ray4")
SCENARIO = {"normal": "feasible_realistic", "difficult": "feasible_realistic",
            "stress": "synthetic_stress"}
FAMILY = {"single-point": "single", "multi-point": "ordinary", "boundary": "boundary",
          "known172": "known172", "synthetic": "synthetic"}

TURRETS = None
ROTATIONS = None


def _historical_samples():
    """Return historical samples once each, before A4's 92-way synthetic expansion."""
    seen, out = set(), []
    for population, subgroup, sample, _ti, _ri in historical.cases():
        # Historical A4 expands only each synthetic sample 92 ways. Realistic rows can
        # intentionally share name/origin/radius while retaining distinct pair/case identity.
        if subgroup == "synthetic":
            key = id(sample)
            if key in seen:
                continue
            seen.add(key)
        out.append((population, subgroup, sample))
    return out


def design(pilot=False):
    """(scenario id, population, subgroup, sample, [(turret index, rotation index)])."""
    samples = _historical_samples()
    by_subgroup = {name: [] for name in FAMILY}
    for item in samples:
        by_subgroup[item[1]].append(item)
    expected = {"single-point": 6990, "multi-point": 1800, "boundary": 4560,
                "known172": 74, "synthetic": 11}
    assert {k: len(v) for k, v in by_subgroup.items()} == expected

    plans = []
    scenario_id = 0
    for subgroup in FAMILY:
        selected = by_subgroup[subgroup][:1] if pilot else by_subgroup[subgroup]
        for original_index, (population, _subgroup, sample) in enumerate(selected):
            if subgroup in ("known172", "synthetic"):
                assignments = [(ti, (ti + original_index) % 24) for ti in range(288)]
            else:
                # 288 turrets and 24 rotations alias; offset by the round-robin round so each
                # turret's repeat appearances walk the rotation set instead of repeating one.
                ti = original_index % 288
                assignments = [(ti, (ti + original_index // 288) % 24)]
            plans.append((scenario_id, population, subgroup, sample, assignments))
            scenario_id += 1
    if not pilot:
        counts = Counter()
        appearances = {s: Counter() for s in ("single-point", "multi-point", "boundary")}
        for _sid, _p, subgroup, _sample, assignments in plans:
            counts[subgroup] += len(assignments)
            for ti, _ri in assignments:
                if subgroup in appearances:
                    appearances[subgroup][ti] += 1
        assert counts == {"single-point": 6990, "multi-point": 1800, "boundary": 4560,
                          "known172": 74 * 288, "synthetic": 11 * 288}
        assert all(len(c) == 288 and min(c.values()) > 1 for c in appearances.values())
        _assert_rotation_coverage(plans)
    return plans


def _assert_rotation_coverage(plans):
    """Fail closed if any turret gets stuck on one benchmark rotation in any subgroup."""
    seen = {name: {} for name in FAMILY}
    for _sid, _p, subgroup, _sample, assignments in plans:
        for ti, ri in assignments:
            seen[subgroup].setdefault(ti, set()).add(ri)
    minimum = {"single-point": 24, "multi-point": 6, "boundary": 15,
               "known172": 24, "synthetic": 11}
    for subgroup, need in minimum.items():
        per_turret = seen[subgroup]
        assert len(per_turret) == 288, (subgroup, len(per_turret))
        worst = min(len(v) for v in per_turret.values())
        assert worst >= need, (subgroup, worst, need)


def _observation(sample, factor):
    """Build every prediction candidate once; no turret-specific truth work here."""
    initial, recovery, log, points = historical.three_ray(sample, factor)
    _origin, d0, anchor = log[0]
    out = {"points": points, "anchor": anchor, "truth_point": np.asarray(points[anchor], float),
           "baseline": "candidate", "baseline_q": 0}
    if d0 is None:
        out.update(direction_point=None, direction_q=1, same_ray_points=None, same_ray_q=1,
                   same_ray_reason="invalid", probes=None, bracket=None, bracket_holds=None,
                   probe_switch=None, hidden_switch=None,
                   three_ray_point=None, three_ray_q=len(log[:3]), three_ray_status="invalid",
                   three_ray_mixed=False, three_ray_error=None,
                   three_ray4_point=None, three_ray4_q=len(log), three_ray4_status="invalid",
                   three_ray4_mixed=False, three_ray4_error=None)
        return out

    o, d0 = np.asarray(sample["O"], float), np.asarray(d0, float)
    truth = out["truth_point"]
    out.update(direction_point=o + historical.FAR * d0, direction_q=1,
               distance=float(np.linalg.norm(truth - o)))
    rough = sample["rough"] * factor
    lo, hi, reason, probes = historical.same_ray(o, d0, rough, points)
    out.update(same_ray_points=None if lo is None else (o + lo * d0, o + hi * d0),
               same_ray_q=1 + len(historical.LADDER), same_ray_reason=reason,
               probes=probes, bracket=[lo, hi],
               bracket_holds=lo is None or lo <= out["distance"] < hi,
               probe_switch=any(p[2] != anchor for p in probes),
               hidden_switch=any(p[2] != anchor and p[1] == "forward" for p in probes))
    for key, result, queries in (("three_ray", initial, 3),
                                  ("three_ray4", recovery or initial, len(log))):
        passed = result["status"] == "pass"
        out[key + "_point"] = np.asarray(result["point"], float) if passed else None
        out[key + "_q"] = queries
        out[key + "_status"] = result["status"]
        out[key + "_mixed"] = len(set(result.get("selections", []))) > 1
        out[key + "_error"] = float(np.linalg.norm(out[key + "_point"] - truth)) if passed else None
    return out


def _nearest_zero(limits):
    if limits is None or limits[0] <= 0 <= limits[1]:
        return 0.0
    return math.radians(min(limits, key=abs))


def _reference_endpoint(record):
    pose = (scorer.ZERO, scorer.IDENTITY)
    for op in record["ops"]:
        if op["kind"] == "fixed":
            transform = (tuple(op["transform"]["t"]), tuple(map(tuple, op["transform"]["R"])))
        else:
            transform = (scorer.ZERO, scorer.JOINT[op["axis"]](_nearest_zero(op["limits"])))
        pose = scorer.compose(pose, transform)
    return np.asarray(pose[0], float)


def _answer(record, rotation, muzzle, world_origin, world_point):
    """Place the selected reference endpoint at O, then score in component coordinates."""
    R = np.asarray(rotation, float)
    o, p = np.asarray(world_origin, float), np.asarray(world_point, float)
    component_origin = o - muzzle @ R
    local = tuple(map(float, (p - component_origin) @ R.T))
    truth = scorer.score(record, local)
    return ("YES" if truth["decision"] is True else
            "NO" if truth["decision"] is False else "UNKNOWN"), truth["state"]


def evaluate(plan):
    scenario_id, population, subgroup, sample, assignments = plan
    rows = []
    for factor in FACTORS:
        obs = _observation(sample, factor)
        for ti, ri in assignments:
            _key, record, muzzle = TURRETS[ti]
            rotation = ROTATIONS[ri]
            truth, truth_state = _answer(record, rotation, muzzle, sample["O"], obs["truth_point"])
            row = dict(case_id=f"{scenario_id}:{ti}", scenario_id=scenario_id,
                       source=record["source"], turret_macro=record["macro"],
                       mechanical_class=record["mechanical_class"],
                       weapon_behavior=record["weapon_behavior"], scenario=SCENARIO[population],
                       historical_population=population, historical_subgroup=subgroup,
                       rough_factor=factor, rough_distance=sample["rough"],
                       target_id=sample["name"], rotation_id=ri, aim_points=len(obs["points"]),
                       truth=truth, truth_state=truth_state, baseline="YES", baseline_q=0)
            if obs["direction_point"] is None:
                for method in METHODS[1:]:
                    row[method], row[method + "_q"] = "UNKNOWN", obs[method + "_q"]
            else:
                row["direction"], _ = _answer(record, rotation, muzzle, sample["O"], obs["direction_point"])
                row["direction_q"] = obs["direction_q"]
                if obs["same_ray_points"] is None:
                    row["same_ray"] = "UNKNOWN"
                else:
                    ends = {_answer(record, rotation, muzzle, sample["O"], p)[0]
                            for p in obs["same_ray_points"]}
                    row["same_ray"] = ends.pop() if len(ends) == 1 and "UNKNOWN" not in ends else "UNKNOWN"
                row["same_ray_q"] = obs["same_ray_q"]
                for method in ("three_ray", "three_ray4"):
                    point = obs[method + "_point"]
                    row[method] = ("UNKNOWN" if point is None else
                                   _answer(record, rotation, muzzle, sample["O"], point)[0])
                    row[method + "_q"] = obs[method + "_q"]
            reason = obs["same_ray_reason"]
            if reason == "bracket":
                # Historical A4 diagnostic: did the two scored bracket ends agree?
                reason = "bracket_agree" if row["same_ray"] != "UNKNOWN" else "bracket_disagree"
            row.update(same_ray_reason=reason, bracket=obs["bracket"],
                       bracket_holds=obs["bracket_holds"], probes=obs["probes"],
                       probe_switch=obs["probe_switch"], hidden_switch=obs["hidden_switch"])
            for method in ("three_ray", "three_ray4"):
                row[method + "_status"] = obs[method + "_status"]
                row[method + "_mixed"] = obs[method + "_mixed"]
                row[method + "_error"] = obs[method + "_error"]
            rows.append(row)
    return rows


def _init_worker(turrets, rotations):
    global TURRETS, ROTATIONS
    TURRETS, ROTATIONS = turrets, rotations


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pilot", action="store_true", help="one scenario per subgroup; factor 1 only")
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()
    os.nice(10)
    records = scorer.load()
    turrets = [(key, records[key], _reference_endpoint(records[key])) for key in sorted(records)]
    assert len(turrets) == 288
    rotations = historical.old.ROT
    assert len(rotations) == 24
    plans = design(args.pilot)
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / ("pilot.jsonl.gz" if args.pilot else "trials.jsonl.gz")
    total_cases = sum(len(p[4]) for p in plans)
    written = 0
    with Pool(args.jobs, initializer=_init_worker, initargs=(turrets, rotations)) as pool, gzip.open(path, "wt") as stream:
        for done, batch in enumerate(pool.imap(evaluate, plans, chunksize=8), 1):
            if args.pilot:
                batch = [r for r in batch if r["rough_factor"] == 1]
            for row in batch:
                stream.write(json.dumps(row, separators=(",", ":")) + "\n")
            written += len(batch)
            if done % 1000 == 0:
                print(done, "/", len(plans), flush=True)
    expected_rows = total_cases if args.pilot else total_cases * len(FACTORS)
    assert written == expected_rows
    print("scenarios", len(plans), "cases", total_cases, "rows", written, "wrote", path)


if __name__ == "__main__":
    main()
