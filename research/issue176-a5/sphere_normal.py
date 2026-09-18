"""A5: how well does a fixed sphere + outward normal approximate each turret's muzzle and bearing?

Research only (#176). Forward kinematics only, reusing the A4x corpus ops and `scorer.segments`
(T = L ∘ J_leaf ∘ G ∘ J_root ∘ H, row-vector `compose`, launch = +Z row of the endpoint frame,
exactly as scorer.py / compare.py). No hull, LOS, target solving or runtime data.

Every joint pair inside the authored limits is a mechanically legal pose, so no pose is UNKNOWN:
the scorer's UNKNOWN rules concern which pose X4 picks for a target, not whether a pose exists.

    python3 research/issue176-a5/sphere_normal.py          # writes sphere-normal.md tables to stdout
    python3 research/issue176-a5/sphere_normal.py --check  # self-checks only
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "issue176-a4x"))
import scorer  # noqa: E402

CENTERS = ("origin", "root", "leaf", "leaf_on_root_axis", "fit_radius", "fit_lines", "fit_minimax")
AXIS = {"x": 0, "y": 1, "z": 2}
BANDS = (1, 2, 5, 10, 15, 20, 30)


def angles(limits, full_step=5.0, n=37):
    """Limits and 0 always included; unlimited joints sweep 360 deg at `full_step`."""
    if limits is None:
        return np.radians(np.arange(0.0, 360.0, full_step))
    lo, hi = limits
    a = set(np.linspace(lo, hi, n)) | ({0.0} if lo <= 0 <= hi else set())
    return np.radians(sorted(a))


def _R(T):
    return np.array(T[1], float)


def poses(record):
    """(muzzle positions, unit launch directions, leaf/root angles) for the full legal grid."""
    leaf, root, seg = scorer.segments(record)
    L, G, H = seg["L"], seg["G"], seg["H"]
    rows = []
    for b in angles(root["limits"]):
        Jr = np.array(scorer.JOINT[root["axis"]](b))
        for a in angles(leaf["limits"]):
            Jl = np.array(scorer.JOINT[leaf["axis"]](a))
            M = _R(L) @ Jl @ _R(G) @ Jr @ _R(H)
            p = ((np.array(L[0]) @ Jl @ _R(G) + G[0]) @ Jr) @ _R(H) + H[0]
            rows.append((p, M[2], a, b))
    P = np.array([r[0] for r in rows])
    D = np.array([r[1] for r in rows])
    return P, D / np.linalg.norm(D, axis=1)[:, None], np.array([r[2:] for r in rows]), (leaf, root, seg)


def fixed_centers(joints):
    leaf, root, seg = joints
    G, H = seg["G"], seg["H"]
    root_c = np.array(H[0], float)
    leaf_c = np.array(G[0], float) @ _R(H) + root_c  # leaf pivot at root angle 0
    axis = _R(H)[AXIS[root["axis"]]]  # root rotation axis in the component frame
    on_axis = root_c + axis * np.dot(leaf_c - root_c, axis)
    return {"origin": np.zeros(3), "root": root_c, "leaf": leaf_c, "leaf_on_root_axis": on_axis}


def fit_radius(P):
    """Algebraic least-squares sphere |p-c|^2 = r^2 (best constant-radius center)."""
    A = np.c_[2 * P, np.ones(len(P))]
    sol = np.linalg.lstsq(A, (P ** 2).sum(1), rcond=None)[0]
    return sol[:3]


def fit_lines(P, D):
    """Least-squares point nearest every firing line (best radial center)."""
    proj = np.eye(3)[None] - D[:, :, None] * D[:, None, :]
    return np.linalg.solve(proj.sum(0), np.einsum("nij,nj->i", proj, P))


def worst_angle(P, D, c):
    v = P - c
    return np.degrees(np.arctan2(np.linalg.norm(np.cross(v, D), axis=1), np.einsum("ij,ij->i", v, D))).max()


def fit_minimax(P, D, starts):
    """Compass search for the center minimising the worst direction error (best cone center).

    ponytail: local search from every other candidate, not a global optimiser; it only upper-bounds
    the true minimax, which is enough to show how radial a turret can possibly be. Use a real
    solver if a turret lands near a decision threshold.
    """
    scale = np.linalg.norm(P - P.mean(0), axis=1).max() or 1.0
    best = min(starts, key=lambda c: worst_angle(P, D, c))
    f, step = worst_angle(P, D, best), scale / 2
    steps = np.vstack([np.eye(3), -np.eye(3)])
    for _ in range(5000):  # flat objectives (every center 90 deg) otherwise wander on float noise
        if step <= 1e-4 * scale:
            break
        trial = [best + step * e for e in steps]
        vals = [worst_angle(P, D, t) for t in trial]
        i = int(np.argmin(vals))
        if vals[i] < f - 1e-9:
            best, f = trial[i], vals[i]
        else:
            step /= 2
    return best


def metrics(P, D, c):
    v = P - c
    r = np.linalg.norm(v, axis=1)
    err = np.degrees(np.arctan2(np.linalg.norm(np.cross(v, D), axis=1), np.einsum("ij,ij->i", v, D)))
    err[r < 1e-6] = 180.0  # direction undefined at the center: worst case
    return {"err_max": err.max(), "err_med": float(np.median(err)), "r_min": r.min(), "r_max": r.max(),
            "r_mean": r.mean(), "spread": r.max() - r.min(), "spread_pct": 100 * (r.max() - r.min()) / r.mean(),
            "worst_pose": np.degrees(POSE_CTX[0][err.argmax()]) if POSE_CTX else None, "_err": err}


POSE_CTX = []


def diagnostics(P, D, joints):
    """Plain mechanical causes: sideways barrel offset from each pivot, leaf pivot off root axis."""
    leaf, root, seg = joints
    c = fixed_centers(joints)
    line_miss = lambda q: np.linalg.norm(np.cross(P - q, D), axis=1).max()  # noqa: E731
    return {"miss_leaf": line_miss(c["leaf"]), "miss_root": line_miss(c["root"]),
            "leaf_off_axis": np.linalg.norm(c["leaf"] - c["leaf_on_root_axis"]),
            "leaf_to_root": np.linalg.norm(c["leaf"] - c["root"]),
            "barrel": np.linalg.norm(np.array(seg["L"][0]))}


def analyse(record):
    P, D, A, joints = poses(record)
    POSE_CTX[:] = [A]
    c = fixed_centers(joints)
    c["fit_radius"] = fit_radius(P)
    c["fit_lines"] = fit_lines(P, D)
    c["fit_minimax"] = fit_minimax(P, D, list(c.values()))
    out = {k: metrics(P, D, v) for k, v in c.items()}
    out["_centers"] = c
    out["_diag"] = diagnostics(P, D, joints)
    out["_n"] = len(P)
    return out


def pct(x, q):
    return float(np.percentile(x, q))


def dist_row(name, vals):
    v = np.asarray(vals)
    return f"| {name} | {len(v)} | {np.median(v):.2f} | {pct(v, 90):.2f} | {pct(v, 95):.2f} | {pct(v, 99):.2f} | {v.max():.2f} |"


def report(R, res):
    classes = sorted({r["mechanical_class"] for r in R.values()})
    groups = [("all", list(R))] + [(k, [n for n, r in R.items() if r["mechanical_class"] == k]) for k in classes]
    groups += [(f"{f}={v}", [n for n, r in R.items() if r[f] == v])
               for f in ("source", "weapon_behavior") for v in sorted({r[f] for r in R.values()})]
    print("## Per-turret worst direction error (deg) by center and class\n")
    print("Distribution across turrets of each turret's worst sampled angle between (muzzle - center) and launch.\n")
    for c in CENTERS:
        print(f"### {c}\n\n| group | n | median | p90 | p95 | p99 | max |\n|---|---:|---:|---:|---:|---:|---:|")
        for g, keys in groups:
            print(dist_row(g, [res[k][c]["err_max"] for k in keys]))
        print()
    print("## Pooled per-pose direction error (deg), all sampled poses\n")
    print("| center | poses | median | p90 | p95 | p99 | max |\n|---|---:|---:|---:|---:|---:|---:|")
    for c in CENTERS:
        e = np.concatenate([res[k][c]["_err"] for k in R])
        print(f"| {c} | {len(e)} | {np.median(e):.2f} | {pct(e, 90):.2f} | {pct(e, 95):.2f} | {pct(e, 99):.2f} | {e.max():.2f} |")
    print("\n## Cone coverage: turrets whose worst sampled error is within the half-angle\n")
    print("| center | group | " + " | ".join(f"≤{b}°" for b in BANDS) + " |\n|---|---|" + "---:|" * len(BANDS))
    for c in CENTERS:
        for g, keys in groups:
            e = [res[k][c]["err_max"] for k in keys]
            print(f"| {c} | {g} | " + " | ".join(str(sum(x <= b for x in e)) for b in BANDS) + " |")
    print("\n## Radius spread by center (across turrets)\n")
    print("| center | group | median spread m | p90 m | max m | median % of mean r | p90 % | max % |\n|---|---|---:|---:|---:|---:|---:|---:|")
    for c in CENTERS:
        for g, keys in groups:
            s = np.array([res[k][c]["spread"] for k in keys])
            p = np.array([res[k][c]["spread_pct"] for k in keys])
            print(f"| {c} | {g} | {np.median(s):.3f} | {pct(s, 90):.3f} | {s.max():.3f} | {np.median(p):.1f} | {pct(p, 90):.1f} | {p.max():.1f} |")
    print("\n## Distance from each simple center to the best-fit centers (m, median / p90 / max)\n")
    print("| center | to fit_lines | to fit_radius | as % of mean fit_lines radius (median) |\n|---|---|---|---:|")
    for c in CENTERS[:4]:
        dl = np.array([np.linalg.norm(res[k]["_centers"][c] - res[k]["_centers"]["fit_lines"]) for k in R])
        dr = np.array([np.linalg.norm(res[k]["_centers"][c] - res[k]["_centers"]["fit_radius"]) for k in R])
        rel = np.array([100 * dl_ / res[k]["fit_lines"]["r_mean"] for dl_, k in zip(dl, R)])
        print(f"| {c} | {np.median(dl):.3f} / {pct(dl, 90):.3f} / {dl.max():.3f} | {np.median(dr):.3f} / {pct(dr, 90):.3f} / {dr.max():.3f} | {np.median(rel):.1f} |")
    best = {c: sum(min(CENTERS[:4], key=lambda z: res[k][z]["err_max"]) == c for k in R) for c in CENTERS[:4]}
    print(f"\nSimple center with the smallest worst direction error, turret count: {best}\n")
    print("## Per-turret table (worst 40 by leaf_on_root_axis direction error)\n")
    print("| turret | class | limits root / leaf | barrel m | line miss leaf / root m | leaf off root axis m "
          "| err° origin / root / leaf / leaf_axis / fit_lines / minimax | worst pose leaf,root° (leaf_axis) | r spread % leaf_axis / fit_radius |")
    print("|---|---|---|---:|---|---:|---|---|---|")
    for k in sorted(R, key=lambda k: -res[k]["leaf_on_root_axis"]["err_max"])[:40]:
        r, x, d = R[k], res[k], res[k]["_diag"]
        lim = " / ".join(str(j["limits"]) for j in r["joints_root_to_leaf"])
        errs = " / ".join(f"{x[c]['err_max']:.1f}" for c in ("origin", "root", "leaf", "leaf_on_root_axis", "fit_lines", "fit_minimax"))
        wp = x["leaf_on_root_axis"]["worst_pose"]
        print(f"| {k} | {r['mechanical_class']} | {lim} | {d['barrel']:.2f} | {d['miss_leaf']:.2f} / {d['miss_root']:.2f} "
              f"| {d['leaf_off_axis']:.2f} | {errs} | {wp[0]:.0f}, {wp[1]:.0f} | {x['leaf_on_root_axis']['spread_pct']:.1f} / {x['fit_radius']['spread_pct']:.1f} |")


def check():
    """Synthetic turret with a known answer, plus corpus-consistency checks."""
    R = scorer.load()
    # compare.py reference pose must equal our FK at the nearest-to-zero grid pose.
    sys.path.insert(0, str(Path(scorer.__file__).parent))
    from compare import _nearest_zero, _reference_endpoint
    for k, r in R.items():
        P, D, A, j = poses(r)
        leaf, root, _ = j
        want = (_nearest_zero(leaf["limits"]), _nearest_zero(root["limits"]))
        i = np.argmin(np.abs(A - want).sum(1))
        assert np.allclose(A[i], want) and np.allclose(P[i], _reference_endpoint(r), atol=1e-9), k
        assert np.allclose(np.linalg.norm(D, axis=1), 1)
    # Pure barrel along +Z from a pivot on the root axis: every center on that pivot is exact.
    I = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    fx = lambda t: {"kind": "fixed", "transform": {"t": t, "R": I}}  # noqa: E731
    rec = {"ops": [fx([0, 0, 5]), {"kind": "joint", "axis": "x", "limits": [-10, 80]}, fx([0, 1, 0]),
                   {"kind": "joint", "axis": "y", "limits": None}, fx([0, 2, 0])]}
    x = analyse(rec)
    for c in ("leaf", "leaf_on_root_axis", "fit_lines", "fit_radius", "fit_minimax"):
        assert x[c]["err_max"] < 1e-6 and x[c]["spread"] < 1e-6, (c, x[c]["err_max"])
    assert np.allclose(x["_centers"]["leaf"], [0, 3, 0]) and np.allclose(x["_centers"]["root"], [0, 2, 0])
    assert x["root"]["err_max"] > 1  # pivot 1 m above root: the root center is not radial
    # Sideways barrel offset of 1 m at 5 m: leaf-center error = atan(1/5) everywhere.
    rec["ops"][0] = fx([1, 0, 5])
    x = analyse(rec)
    assert abs(x["leaf"]["err_max"] - math.degrees(math.atan2(1, 5))) < 1e-6
    assert x["fit_minimax"]["err_max"] <= min(x[c]["err_max"] for c in CENTERS[:6]) + 1e-9
    print(f"PASS check: {len(R)} corpus reference poses match compare.py; synthetic sphere cases exact")


def main():
    if "--check" in sys.argv:
        return check()
    R = scorer.load()
    res = {k: analyse(r) for k, r in sorted(R.items())}
    report(R, res)


if __name__ == "__main__":
    main()
