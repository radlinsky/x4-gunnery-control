"""P3c frozen AABB-assisted near-target triangulation rate study (surrogate precision). Offline only."""
import gzip, itertools, json, math, os, pickle, sys
from collections import Counter
from multiprocessing import Pool
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
OUT = HERE.parents[1] / ".x4-research-cache/issue167-p3c"
sys.path.insert(0, str(HERE.parents[1] / "scripts"))
from barrelposition_evaluator import compose, joint_matrix  # noqa: E402
from yaw_rest_gate import ZEROING, classify  # noqa: E402

u, q = 2.0 ** -24, 2.0 ** -18
delta = 2 * q
k_min, b_min, b_max, r_min = 128 * delta, 0.25, 4.0, 1e-4
RADII = (50, 100, 250, 500, 1000, 2500, 5000, 10000, 20000)
REASONS = ("INVALID_INPUT", "TINY_BOX", "ORIGIN_INSIDE_BOX", "INVALID_DIRECTION", "NO_FORWARD_BOX_ENTRY", "PROBE_INSIDE_BOX",
           "BASELINE_COLLAPSED", "ILL_CONDITIONED", "NONFORWARD_OR_NONFINITE", "SKEW_RAYS", "OUTSIDE_BOX", "REAL_RAY_DISAGREEMENT")


def F(v):
    with np.errstate(over="ignore"):
        return float(np.float32(v))


def F3(v):
    return tuple(F(x) for x in v)


fin = math.isfinite
add = lambda a, b: tuple(x + y for x, y in zip(a, b))  # noqa: E731
sub = lambda a, b: tuple(x - y for x, y in zip(a, b))  # noqa: E731
mul = lambda a, k: tuple(x * k for x in a)  # noqa: E731
dot = lambda a, b: sum(x * y for x, y in zip(a, b))  # noqa: E731
norm = lambda a: math.sqrt(dot(a, a))  # noqa: E731
ninf = lambda a: max(abs(x) for x in a)  # noqa: E731
cross = lambda a, b: (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])  # noqa: E731
unit = lambda a: mul(a, 1 / norm(a))  # noqa: E731


def rotations():
    out = []
    for perm in itertools.permutations(range(3)):
        for signs in itertools.product((-1, 1), repeat=3):
            M = tuple(tuple(float(signs[i]) if j == perm[i] else 0.0 for j in range(3)) for i in range(3))
            if round(np.linalg.det(np.array(M))) == 1:
                out.append(M)
    return sorted(out, key=lambda M: sum(M, ()))


ROT = rotations()
row = lambda p, M: tuple(sum(p[k] * M[k][j] for k in range(3)) for j in range(3))  # noqa: E731


def select(o, pts):
    """Native nearest aimtarget: binary32 x²+(y²+z²), strict <, earlier wins ties."""
    best, bd = 0, None
    for i, p in enumerate(pts):
        dx, dy, dz = (F(a - b) for a, b in zip(o, p))
        d2 = F(F(dx * dx) + F(F(dy * dy) + F(dz * dz)))
        if bd is None or d2 < bd:
            best, bd = i, d2
    return best


def Q(U, pts, log):
    U = F3(U)
    i = select(U, pts)
    d = tuple(F(a - b) for a, b in zip(pts[i], U))
    n = F(math.sqrt(F(F(d[0] * d[0]) + F(F(d[1] * d[1]) + F(d[2] * d[2])))))
    if not n > 0 or not fin(n):
        log.append((U, None, i))
        return None
    x, y, z = (F(c / n) for c in d)
    yaw, pitch = math.atan2(x, z), math.atan2(y, math.hypot(x, z))
    yaw, pitch = round(yaw / q) * q, round(pitch / q) * q
    v = F3((math.cos(pitch) * math.sin(yaw), math.sin(pitch), math.cos(pitch) * math.cos(yaw)))
    nv = norm(v)
    if not nv > 0 or not fin(nv):
        log.append((U, None, i))
        return None
    v = mul(v, 1 / nv)
    log.append((U, v, i))
    return v


def inside(p, lo, hi):
    return all(l <= x <= h for x, l, h in zip(p, lo, hi))


def slab(o, d, lo, hi):
    enter, exit_ = -math.inf, math.inf
    for j in range(3):
        if d[j] == 0.0:
            if not lo[j] <= o[j] <= hi[j]:
                return None
            continue
        t1, t2 = (lo[j] - o[j]) / d[j], (hi[j] - o[j]) / d[j]
        enter, exit_ = max(enter, min(t1, t2)), min(exit_, max(t1, t2))
    if not (fin(enter) and fin(exit_) and enter > 0 and exit_ >= enter):
        return None
    return enter


def approximate(O, C, H, pts):
    """Frozen Route A. Returns (reason|None, X, E, queries log)."""
    log = []
    O, C, H = F3(O), F3(C), F3(H)
    lo, hi = F3(sub(C, H)), F3(add(C, H))
    if not all(map(fin, O + C + H + lo + hi)) or min(H) < 0 or any(a > b for a, b in zip(lo, hi)):
        return "INVALID_INPUT", None, None, log
    if norm(H) < r_min:
        return "TINY_BOX", None, None, log
    if inside(O, lo, hi):
        return "ORIGIN_INSIDE_BOX", None, None, log
    d0 = Q(O, pts, log)
    if d0 is None:
        return "INVALID_DIRECTION", None, None, log
    enter = slab(O, d0, lo, hi)
    if enter is None:
        return "NO_FORWARD_BOX_ENTRY", None, None, log
    baseline = min(max(0.01 * 2 * norm(H), b_min), b_max)
    A = F3(add(O, mul(d0, max(0.0, enter - 4 * baseline))))
    if inside(A, lo, hi):
        return "PROBE_INSIDE_BOX", None, None, log
    ax = min(range(3), key=lambda j: (abs(d0[j]), j))
    e = tuple(1.0 if j == ax else 0.0 for j in range(3))
    B = F3(add(A, mul(unit(cross(d0, e)), baseline)))
    if not norm(sub(B, A)) >= baseline / 2:
        return "BASELINE_COLLAPSED", None, None, log
    dA = d0 if A == O else Q(A, pts, log)
    if dA is None:
        return "INVALID_DIRECTION", None, None, log
    dB = Q(B, pts, log)
    if dB is None:
        return "INVALID_DIRECTION", None, None, log
    c = min(max(dot(dA, dB), -1.0), 1.0)
    k = math.sqrt(max(0.0, 1 - c * c))
    if k < k_min:
        return "ILL_CONDITIONED", None, None, log
    w = sub(A, B)
    dd, ee, den = dot(dA, w), dot(dB, w), 1 - c * c
    s, t = (c * ee - dd) / den, (ee - c * dd) / den
    XA, XB = add(A, mul(dA, s)), add(B, mul(dB, t))
    X = F3(mul(add(XA, XB), 0.5))
    S = max(1.0, ninf(C) + ninf(H), ninf(A), ninf(B), ninf(X) if all(map(fin, X)) else math.inf)
    rho = 8 * u * S
    E = 4 * (rho + delta * max(s, t)) / k
    if not all(map(fin, X + XA + XB + (s, t, E))) or s <= 0 or t <= 0:
        return "NONFORWARD_OR_NONFINITE", X, E, log
    if not norm(sub(XA, XB)) <= 4 * rho + 2 * delta * (s + t):
        return "SKEW_RAYS", X, E, log
    if not inside(X, tuple(v - E for v in lo), tuple(v + E for v in hi)):
        return "OUTSIDE_BOX", X, E, log
    rel = sub(X, O)
    if not dot(rel, d0) > 0:
        return "NONFORWARD_OR_NONFINITE", X, E, log
    r = norm(rel)
    rho0 = 8 * u * max(1.0, ninf(O), ninf(X))
    if not norm(sub(mul(rel, 1 / r), d0)) <= 4 * delta + 4 * rho0 / r:
        return "REAL_RAY_DISAGREEMENT", X, E, log
    return None, X, E, log


def geometry(turret, R, O, p):
    """#166 split T = L∘Rx(-x)∘G∘Ry(y)∘H; U13 yaw gate; arc from rotation_x limits.

    #185 existence rule: every resting yaw is scored and one in arc suffices. Traps do not
    affect existence; no resting yaw proves CANNOT BEAR. Pitch uses X4's 1e-3f component
    zeroing of the pivot direction.
    """
    pt = tuple(sum((p[k] - O[k]) * R[j][k] for k in range(3)) for j in range(3))  # (p-O)·Rᵀ
    gate = classify(turret["yaw"], pt)
    if not gate["resting"]:
        return {"state": "NO_STABLE_POSITION", "decision": False, "yaws": gate["class"]}
    L, G, H = turret["seg"]["L"], turret["seg"]["G"], turret["seg"]["H"]
    aim = L[1][2]
    lo, hi = turret["arc"]
    scored = []
    for y in gate["resting"]:
        frame = compose(G, compose(((0.0, 0.0, 0.0), joint_matrix(0.0, y)), H))
        d = sub(pt, frame[0])
        n = norm(d)
        if not n:
            continue  # X4 skips the solve; another stable yaw may still be usable.
        d = tuple(0.0 if abs(c) < ZEROING * n else c for c in d)  # caller 0x140e22425; atan2 ignores the renormalization
        qv = row(d, tuple(zip(*frame[1])))
        x = math.remainder(math.atan2(qv[1], qv[2]) - math.atan2(aim[1], aim[2]), 2 * math.pi)
        ok = round(lo, 4) <= round(math.degrees(x), 4) <= round(hi, 4)  # 4-dp degrees absorbs float noise at an authored limit
        muzzle = compose(compose(compose(L, ((0.0, 0.0, 0.0), joint_matrix(x, 0.0))), G), compose(((0.0, 0.0, 0.0), joint_matrix(0.0, y)), H))[0]
        scored.append((not ok, y, x, muzzle))
    if not scored:
        return {"state": "UNKNOWN_pivot", "decision": None, "yaws": gate["class"]}
    miss, y, x, muzzle = min(scored, key=lambda r: r[0])
    return {"state": "OUT_OF_ARC" if miss else "IN_ARC", "decision": not miss, "yaws": gate["class"], "yaw": y, "pitch": x, "muzzle": muzzle}


def engageable(turret, R, O, solutions):
    """#79/#176: ENGAGEABLE if any passing solution (A2 consensus dict) scores in arc."""
    return any(s["status"] == "pass" and geometry(turret, R, O, s["point"])["decision"] for s in solutions)


def fibonacci(n=1024):
    ga = math.pi * (3 - math.sqrt(5))
    out = []
    for i in range(n):
        z = 1 - (2 * i + 1) / n
        r = math.sqrt(1 - z * z)
        out.append((r * math.cos(i * ga), r * math.sin(i * ga), z))
    return out


DIRS = fibonacci() + [unit(v) for v in itertools.product((-1, 0, 1), repeat=3) if v != (0, 0, 0)]
assert len(DIRS) == 1050
AXIAL = [(sg, ep) for sg in (-1, 1) for ep in (0.0, 1e-7, 1e-5, 1e-3)]
BISECT = [(az, ep) for az in range(16) for ep in (-0.01, -0.0001, 0.0, 0.0001, 0.01)]
SYN = list(itertools.product((1, 10, 100, 1000), (0.5, 8, 12), (32, 128, 512), (0.0, 2 ** -20, 2 ** -16, 2 ** -12, 2 ** -8), range(24)))
N_ORD, N_OFF, N_SYN = 270 * 1050 * 9, 38 * 9 * 88, len(SYN)
assert (N_ORD, N_OFF, N_SYN) == (2_551_500, 30_096, 4_320)
TOTAL = N_ORD + N_OFF + N_SYN
assert TOTAL == 2_585_916

CORPUS = None


def pair_frame(rec, a, b):
    pa, pb = rec["points"][a], rec["points"][b]
    n = unit(sub(pb, pa))
    ax = min(range(3), key=lambda j: (abs(n[j]), j))
    e = tuple(1.0 if j == ax else 0.0 for j in range(3))
    uu = unit(sub(e, mul(n, dot(e, n))))
    return mul(add(pa, pb), 0.5), n, uu, cross(n, uu)


def trial(n):
    recs = CORPUS["records"]
    if n < N_ORD:
        ri, rest = divmod(n, 1050 * 9)
        di, ki = divmod(rest, 9)
        rec = recs[ri]
        pts = rec["points"]
        M = tuple(sum(p[j] for p in pts) / len(pts) for j in range(3))
        O = F3(add(M, mul(DIRS[di], RADII[ki])))
        meta = {"family": "ordinary", "macro": rec["macro"], "component": rec["component"], "dir": di, "radius": RADII[ki]}
        return meta, O, rec["C"], rec["H"], pts
    if n < N_ORD + N_OFF:
        pi, rest = divmod(n - N_ORD, 792)
        ki, ci = divmod(rest, 88)
        ri, a, b = CORPUS["pairs"][pi]
        rec = recs[ri]
        M, nn, uu, vv = pair_frame(rec, a, b)
        rad = RADII[ki]
        if ci < 8:
            sg, ep = AXIAL[ci]
            O = F3(add(M, mul(add(nn, mul(uu, ep)), sg * rad)))
            case = {"kind": "axial", "sign": sg, "epsilon": ep}
        else:
            az, ep = BISECT[ci - 8]
            th = 2 * math.pi * az / 16
            O = F3(add(M, mul(add(add(mul(uu, math.cos(th)), mul(vv, math.sin(th))), mul(nn, ep)), rad)))
            case = {"kind": "bisector", "azimuth": az, "epsilon": ep}
        meta = {"family": "official", "macro": rec["macro"], "component": rec["component"], "pair": [a, b], "radius": rad, **case}
        return meta, O, rec["C"], rec["H"], rec["points"]
    s, a, Lf, ep, ri = SYN[n - N_ORD - N_OFF]
    Rs = ROT[ri]
    O = F3(row((0.0, 0.0, -Lf * s), Rs))
    pts = [F3(row((ep * s, 0.0, -a * s), Rs)), F3(row((0.0, 0.0, 0.0), Rs))]
    meta = {"family": "synthetic", "s": s, "a": a, "Lfactor": Lf, "epsilon": ep, "rotation": ri}
    return meta, O, (0.0, 0.0, 0.0), (float(s), float(s), float(s)), pts


def run(n):
    meta, O, C, H, pts = trial(n)
    turret = CORPUS["turrets"][n % 92]
    R = ROT[(n // 92) % 24]
    i = select(F3(O), [F3(p) for p in pts])
    P = F3(pts[i])
    reason, X, E, log = approximate(O, C, H, pts)
    rec = {"id": n, **meta, "O": O, "C": C, "H": H, "turret": turret["macro"], "R": (n // 92) % 24,
           "queries": len(log), "query_log": log, "native": i, "reason": reason}
    if meta["family"] == "official":
        lo, hi = F3(sub(F3(C), F3(H))), F3(add(F3(C), F3(H)))
        rel = sub(P, O)
        dist = norm(rel)
        enter = slab(O, mul(rel, 1 / dist), lo, hi) if dist > 0 else None
        rec["hidden_before_entry"] = enter is not None and dist < enter
    exact = geometry(turret, R, O, P)
    rec["exact"] = exact
    if reason is None:
        ident = min(range(len(pts)), key=lambda j: (dot(sub(X, pts[j]), sub(X, pts[j])), j))
        err = norm(sub(X, P))
        rec.update(X=X, E=E, identity=ident, point_error=err, identity_mismatch=ident != i,
                   envelope_miss=err > E, exact_point=X == P)
        rec["bucket"] = "correct_accepted" if ident == i and err <= E else "accepted_wrong"
        approx = geometry(turret, R, O, X)
    else:
        rec["bucket"] = "fail_closed"
        approx = {"state": "FAIL_CLOSED", "decision": False}
    rec["approx"] = approx
    rec["false_engageable"] = approx["decision"] and not exact["decision"]
    rec["false_not_engageable"] = exact["decision"] and not approx["decision"]
    return rec


def init():
    global CORPUS
    CORPUS = pickle.load(open(OUT / "corpus.pkl", "rb"))


def chunk(bounds):
    start, end = bounds
    agg = {f: Counter() for f in ("ordinary", "official", "synthetic")}
    first, errors = {}, {f: [] for f in agg}
    with gzip.open(OUT / "trials" / f"{start:07d}.jsonl.gz", "wt") as fh:
        for n in range(start, end):
            r = run(n)
            fh.write(json.dumps(r, separators=(",", ":")) + "\n")
            c = agg[r["family"]]
            keys = [r["bucket"], f"queries={r['queries']}", f"exact={r['exact']['state']}", f"approx={r['approx']['state']}"]
            if r["reason"]:
                keys.append("reason=" + r["reason"])
            else:
                keys += ["identity_mismatch"] * r["identity_mismatch"] + ["envelope_miss"] * r["envelope_miss"] + ["exact_point"] * r["exact_point"]
                keys.append(f"accepted/{r['bucket']}/ident_mismatch={r['identity_mismatch']}/fE={r['false_engageable']}/fNE={r['false_not_engageable']}")
                errors[r["family"]].append(r["point_error"])
            keys += ["false_engageable"] * r["false_engageable"] + ["false_not_engageable"] * r["false_not_engageable"]
            keys += ["total_error"] * (r["false_engageable"] or r["false_not_engageable"])
            keys += [f"exact_decision={r['exact']['decision']}"]
            if r["family"] == "official":
                acc = "accepted" if r["reason"] is None else "fail_closed"
                keys.append(f"hidden_before_entry={r['hidden_before_entry']}/{acc}/ident_mismatch={r.get('identity_mismatch')}")
            for k in keys:
                c[k] += 1
                first.setdefault((r["family"], k), [])
                if len(first[(r["family"], k)]) < 3:
                    first[(r["family"], k)].append(n)
    return agg, first, errors


if __name__ == "__main__":
    (OUT / "trials").mkdir(parents=True, exist_ok=True)
    step = 2000
    bounds = [(s, min(s + step, TOTAL)) for s in range(0, TOTAL, step)]
    if len(sys.argv) > 1:
        bounds = bounds[: int(sys.argv[1])]
    agg = {f: Counter() for f in ("ordinary", "official", "synthetic")}
    first, errors, done = {}, {f: [] for f in agg}, 0
    with Pool(os.cpu_count(), initializer=init) as pool:
        for a, fi, er in pool.imap_unordered(chunk, bounds):
            for f in agg:
                agg[f].update(a[f])
                errors[f] += er[f]
            for k, v in fi.items():
                first[k] = sorted(first.get(k, []) + v)[:3]
            done += 1
            if done % 50 == 0:
                print(f"{done}/{len(bounds)} chunks", flush=True)
    pickle.dump({"agg": agg, "first": first, "errors": errors, "chunks": len(bounds)}, open(OUT / "result.pkl", "wb"))
    print("done", {f: sum(v[b] for b in ("correct_accepted", "accepted_wrong", "fail_closed")) for f, v in agg.items()})
