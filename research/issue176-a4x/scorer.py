"""Expanded-A4 mechanical ENGAGEABLE truth scorer over the accepted 288-turret corpus (#176).

Research only. Bearing/arc geometry of the corpus `ops` path; no range, LOS, hull masking,
projectile, guidance or readiness. Target points are in the turret component frame.

- ordinary_xy (unlimited root Y, bounded leaf X): the accepted #173 scorer
  (`research/issue167-p3c/study.py` `geometry()`) on segments split from the corpus ops.
- bounded_traverse / reversed_xy: both pivots fixed (asserted), so each joint has one
  request. Solve root then leaf in the root's clamped frame (swi-091-turret-geometry.md);
  IN_ARC iff neither joint clamps. A >=180 deg root span whose request sits on a limit is
  UNKNOWN: the mover could be parked pi away at the other limit.
- rotation_z: runtime handedness and muzzle are unresolved, so only the accepted clock-plus-
  cone reach is used, over every possible pitch pivot (root pivot or leaf pivot at any clock).
  Definite only when all pivots agree; otherwise UNKNOWN.
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
from yaw_rest_gate import ZENITH, ZEROING  # noqa: E402

CORPUS = ROOT / ".x4-research-cache/issue176-a4x/corpus.json.gz"
JOINT = {"x": lambda a: rx(-a), "y": ry, "z": lambda a: rz(-a)}  # A6 J_C = Rz(-z)·Rx(-x)·Ry(+y)
PLANE = {"x": (1, 2), "y": (0, 2)}  # request = atan2(u[i], u[j]) - atan2(a[i], a[j])
CONE_MARGIN = 0.1  # ponytail: degrees; covers 1e-3f component zeroing on an unknown pivot (<0.082 deg)


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
    out = {"state": "IN_ARC" if hit else "OUT_OF_ARC", "decision": hit, "root": r, "leaf": x, "aim": aim, "d": d}
    lo, hi = root["limits"]
    if hit and hi - lo >= 180 and not (_in_arc(root_req - 1e-5, root["limits"]) and _in_arc(root_req + 1e-5, root["limits"])):
        out.update(state="UNKNOWN_root_limit_unwrap", decision=None)
    return out


def _cone(leaf, root, seg, pt):
    L, G, H = seg["L"], seg["G"], seg["H"]
    aim = mat_mul(L[1], G[1])[2]
    assert H[1] == IDENTITY and math.dist(aim, (0.0, 0.0, 1.0)) < 1e-9, "cone is not about component +Z"
    lo, hi = leaf["limits"]
    assert lo == -hi, "asymmetric cone"
    q = tuple(p - t for p, t in zip(pt, H[0]))
    rho, r = math.hypot(q[0], q[1]), math.hypot(G[0][0], G[0][1])
    h = q[2] - G[0][2]
    angles = [math.degrees(math.atan2(rho, q[2])),  # root pivot
              math.degrees(math.atan2(abs(rho - r), h)), math.degrees(math.atan2(rho + r, h))]  # leaf pivot, any clock
    if max(angles) <= hi - CONE_MARGIN:
        return {"state": "IN_ARC", "decision": True, "off_axis": angles}
    if min(angles) > hi + CONE_MARGIN:
        return {"state": "OUT_OF_ARC", "decision": False, "off_axis": angles}
    return {"state": "UNKNOWN_rotation_z", "decision": None, "off_axis": angles}


def score(record, pt, _cache={}):
    """{"state": IN_ARC | OUT_OF_ARC | UNKNOWN_*, "decision": True | False | None, ...}."""
    cls = record["mechanical_class"]
    if cls == "ordinary_xy":
        key = record["source"] + ":" + record["macro"]
        if key not in _cache:
            _cache[key] = accepted_turret(record)
        out = study.geometry(_cache[key], IDENTITY, ZERO, pt)
        return {**out, "decision": None if out["state"].startswith("UNKNOWN") else out["decision"]}
    leaf, root, seg = segments(record)
    assert (root["axis"], leaf["axis"]) in {("y", "x"), ("x", "y"), ("z", "x")}, cls
    return (_cone if root["axis"] == "z" else _fixed_pivot)(leaf, root, seg, pt)


def load():
    return json.load(gzip.open(CORPUS, "rt"))["records"]
