"""Expanded-A4 mechanical ENGAGEABLE truth scorer over the accepted 288-turret corpus (#176).

Research only. Bearing/arc geometry of the corpus `ops` path; no range, LOS, hull masking,
projectile, guidance or readiness. Target points are in the turret component frame.

- ordinary_xy (unlimited root Y, bounded leaf X): the accepted #173 geometry
  (`research/issue167-p3c/study.py` `geometry()`) on segments split from the corpus ops.
- bounded_traverse / reversed_xy: both pivots fixed (asserted), so each joint has one
  request. Solve root then leaf in the root's clamped frame (swi-091-turret-geometry.md);
  IN_ARC iff neither joint clamps.
- rotation_z: the traced root-Z request (turret-target-point-joint-solver.md) is the yaw map with
  component Y and Z swapped, so the accepted yaw gate finds the resting clocks. Traps do not affect
  existence; the leaf X request is scored at every resting clock and any in arc suffices. No resting
  clock proves CANNOT BEAR; exact-pivot degeneracy remains UNKNOWN.
"""
from __future__ import annotations

import gzip
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "research/issue167-p3c"), str(ROOT / "scripts")]
import study  # noqa: E402
from barrelposition_evaluator import IDENTITY, ZERO, compose, mat_mul, rx, ry, rz, vec_mul  # noqa: E402
from yaw_rest_gate import ZENITH, ZEROING, classify  # noqa: E402

CORPUS = ROOT / ".x4-research-cache/issue176-a4x/corpus.json.gz"
JOINT = {"x": lambda a: rx(-a), "y": ry, "z": lambda a: rz(-a)}  # A6 J_C = Rz(-z)·Rx(-x)·Ry(+y)
PLANE = {"x": (1, 2), "y": (0, 2)}  # request = atan2(u[i], u[j]) - atan2(a[i], a[j])
SWAP = lambda v: (v[0], v[2], v[1])  # noqa: E731  Y<->Z: Rz(-z) becomes Ry(z), atan2(x, y) becomes atan2(x, z)


def _chain(ops, lo, hi):
    total = (ZERO, IDENTITY)
    for op in ops[lo:hi]:
        total = compose(total, (tuple(op["transform"]["t"]), tuple(map(tuple, op["transform"]["R"]))))
    return total


def segments(record):
    """T = L ∘ J_leaf ∘ G ∘ J_root ∘ H over the corpus leaf-to-root ops."""
    ops = record["ops"]
    leaf, root = [i for i, op in enumerate(ops) if op["kind"] == "joint"]
    return ops[leaf], ops[root], {"L": _chain(ops, 0, leaf), "G": _chain(ops, leaf + 1, root),
                                  "H": _chain(ops, root + 1, len(ops))}


def accepted_turret(record):
    """The #167/#173 turret dict (seg, yaw, arc) for an ordinary_xy record."""
    leaf, _root, seg = segments(record)
    aim = vec_mul(seg["L"][1][2], seg["G"][1])
    yaw = {"t_G": seg["G"][0], "t_H": seg["H"][0], "R_H": seg["H"][1], "beta": math.atan2(aim[0], aim[2])}
    return {"macro": record["macro"], "arc": tuple(leaf["limits"]), "seg": seg, "yaw": yaw}


def _in_arc(angle, limits):
    """#173 4-dp degree rule after wrapping; None when unlimited."""
    deg = round(math.degrees(math.remainder(angle, 2 * math.pi)), 4)
    return limits is None or round(limits[0], 4) <= deg <= round(limits[1], 4)


def _clamp(angle, limits):
    """Nearer wrapped authored limit (swi-091-turret-geometry.md, clamp propagation)."""
    if _in_arc(angle, limits):
        return angle
    lo, hi = (math.radians(b) for b in limits)
    return min((lo, hi), key=lambda b: abs(math.remainder(angle - b, 2 * math.pi)))


def _request(axis, u, aim):
    i, j = PLANE[axis]
    if abs(u[i]) < ZENITH and abs(u[j]) < ZENITH:
        return 0.0  # target angle = reference angle (#173 oracle 0x140e21b7c, yaw gate F = 0)
    return math.atan2(u[i], u[j]) - math.atan2(aim[i], aim[j])


def _fixed_pivot(leaf, root, seg, pt):
    L, G, H = seg["L"], seg["G"], seg["H"]
    pivot = [compose(G, compose((ZERO, JOINT[root["axis"]](a)), H))[0] for a in (0.0, 1.0)]
    assert math.dist(*pivot) < 1e-9, f"{leaf['connection']}: pitch pivot moves with the root joint"
    d = tuple(p - c for p, c in zip(pt, pivot[0]))
    n = math.hypot(*d)
    if not n:
        return {"state": "UNKNOWN_pivot", "decision": None}  # X4 skips the solve (#173 known limit)
    d = tuple(0.0 if abs(c) < ZEROING * n else c / n for c in d)  # caller zeroing; solver renormalizes
    d = tuple(c / math.hypot(*d) for c in d)
    Rt = lambda M: tuple(zip(*M))  # noqa: E731
    root_req = _request(root["axis"], vec_mul(d, Rt(H[1])), mat_mul(L[1], G[1])[2])
    r = _clamp(root_req, root["limits"])
    frame = mat_mul(G[1], mat_mul(JOINT[root["axis"]](r), H[1]))  # clamped root composed first
    leaf_req = _request(leaf["axis"], vec_mul(d, Rt(frame)), L[1][2])
    x = _clamp(leaf_req, leaf["limits"])
    hit = r == root_req and x == leaf_req
    aim = mat_mul(L[1], mat_mul(JOINT[leaf["axis"]](x), frame))[2]
    return {"state": "IN_ARC" if hit else "OUT_OF_ARC", "decision": hit,
            "root": r, "leaf": x, "aim": aim, "d": d}


def _rest_z(leaf, root, seg, pt):
    L, G, H = seg["L"], seg["G"], seg["H"]
    aim = vec_mul(L[1][2], G[1])  # rest launch +Z in the root frame
    yaw = {"t_G": SWAP(G[0]), "t_H": SWAP(H[0]), "R_H": tuple(SWAP(r) for r in (H[1][0], H[1][2], H[1][1])),
           "beta": math.atan2(aim[0], aim[1])}  # traced beta_z; no degenerate guard (0 for the dish)
    gate = classify(yaw, SWAP(pt))
    if not gate["resting"]:
        return {"state": "NO_STABLE_POSITION", "decision": False, "clocks": gate["class"]}
    Rt = lambda M: tuple(zip(*M))  # noqa: E731
    scored = []
    for z in gate["resting"]:
        frame = compose(G, compose((ZERO, JOINT["z"](z)), H))
        d = tuple(p - c for p, c in zip(pt, frame[0]))
        n = math.hypot(*d)
        if not n:
            continue  # X4 skips the solve; another stable clock may still be usable.
        d = tuple(0.0 if abs(c) < ZEROING * n else c for c in d)  # caller zeroing; atan2 ignores renormalization
        x = math.remainder(_request("x", vec_mul(d, Rt(frame[1])), L[1][2]), 2 * math.pi)
        scored.append((not _in_arc(x, leaf["limits"]), z, x))
    if not scored:
        return {"state": "UNKNOWN_pivot", "decision": None, "clocks": gate["class"]}
    miss, z, x = min(scored, key=lambda r: r[0])
    return {"state": "OUT_OF_ARC" if miss else "IN_ARC", "decision": not miss, "clocks": gate["class"], "root": z, "leaf": x}


def score(record, pt, _cache={}):
    """State is IN_ARC, OUT_OF_ARC, NO_STABLE_POSITION, or UNKNOWN_*.

    NO_STABLE_POSITION proves CANNOT BEAR for the supplied exact aim point.
    """
    cls = record["mechanical_class"]
    if cls == "ordinary_xy":
        key = record["source"] + ":" + record["macro"]
        if key not in _cache:
            _cache[key] = accepted_turret(record)
        out = study.geometry(_cache[key], IDENTITY, ZERO, pt)
        return {**out, "decision": None if out["state"].startswith("UNKNOWN") else out["decision"]}
    leaf, root, seg = segments(record)
    assert (root["axis"], leaf["axis"]) in {("y", "x"), ("x", "y"), ("z", "x")}, cls
    return (_rest_z if root["axis"] == "z" else _fixed_pivot)(leaf, root, seg, pt)


def load():
    return json.load(gzip.open(CORPUS, "rt"))["records"]
