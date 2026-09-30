"""Offline adversarial audit of the P3c ENGAGEABLE scorer against a native-derived float32 pitch oracle."""
import itertools, json, math, os, pickle, sys
from collections import Counter
from multiprocessing import Pool
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(REPO / "research/issue167-p3c"), str(REPO / "scripts")]
import study  # noqa: E402
from barrelposition_evaluator import joint_matrix, rx, ry, rz  # noqa: E402
from yaw_rest_gate import classify  # noqa: E402

f32 = np.float32
ZEROING, PROJ = f32(1e-3), f32(1e-4)       # caller 0x140e22425, solver 0x140e21b8e / limit skip 0x140e21d49
EPS = 4 * float(np.spacing(f32(2 * math.pi)))  # ~1.9e-6 rad: X4's own float32 pitch/wrap noise near 2π
I3 = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
TURRETS = pickle.load(open(REPO / ".x4-research-cache/issue167-p3c/corpus.pkl", "rb"))["turrets"]


def gate(yaw, pt, memo={}):
    key = (id(yaw), pt)
    if key not in memo:
        memo.clear()
        memo[key] = classify(yaw, pt)
    return memo[key]


study.classify = gate  # the scorer and the oracle share one yaw-gate evaluation per target


def oracle(turret, pt, y, dt=f32, zeroing=True):
    """Native pitch request and limit test (solver 0x140e2132d). None = solver skipped (hidden state)."""
    L, G, H = (turret["seg"][k] for k in "LGH")
    J = np.array(joint_matrix(0.0, float(dt(y))), dt)
    RG, RH = np.array(G[1], dt), np.array(H[1], dt)
    C = np.array(G[0], dt) @ J @ RH + np.array(H[0], dt)
    v = np.array(pt, dt) - C
    tiny = dt(1e-27)
    d = v / (np.sqrt(v @ v) + tiny)
    near = bool(np.any(np.abs(np.abs(d) - ZEROING) < 1e-9))
    if zeroing:
        d = np.where(np.abs(d) < ZEROING, dt(0), d)
    if np.all(np.abs(d) < PROJ):
        return None
    d = d / (np.sqrt(d @ d) + tiny)
    u = d @ (RG @ J @ RH).T
    a = np.array(L[1][2], dt)
    aref = np.arctan2(a[1], a[2])
    degenerate = bool(abs(u[1]) < PROJ and abs(u[2]) < PROJ)
    near |= bool(abs(abs(u[1]) - PROJ) < 1e-9 or abs(abs(u[2]) - PROJ) < 1e-9)
    two_pi = dt(2 * math.pi)

    def wrap(t):
        t = np.fmod(dt(t), two_pi)
        return t + two_pi if t < 0 else t

    x = wrap((aref if degenerate else np.arctan2(u[1], u[2])) - aref)
    lo, hi = (dt(math.radians(b)) for b in turret["arc"])
    if abs(lo) < PROJ and abs(hi) < PROJ:
        c = x
    else:
        span = wrap(hi - lo)
        c = x if wrap(x - lo) < span and wrap(hi - x) < span else lo if wrap(lo - x) < wrap(x - hi) else hi
    return {"in": bool(c == x), "x": float(x), "outside": abs(math.remainder(float(x) - float(c), 2 * math.pi)),
            "edge": min(abs(math.remainder(float(x) - float(b), 2 * math.pi)) for b in (lo, hi)),
            "degenerate": degenerate, "near": near}


def audit(case):
    pop, name, turret, pt = case
    try:
        g = gate(turret["yaw"], pt)
        scored = study.geometry(turret, I3, (0.0, 0.0, 0.0), pt)
    except Exception as e:  # noqa: BLE001
        return pop, "scorer_raises:" + type(e).__name__, None
    rests = {y: oracle(turret, pt, y) for y in g["resting"]}
    ins = {bool(r and r["in"]) for r in rests.values()}
    pattern = f"{g['class']}{'+trap' if g['traps'] else ''}:" + (
        "no_rest" if not rests else "all_in" if ins == {True} else "mixed" if True in ins else "none_in")
    if g["traps"] or not rests:
        return pop, f"hidden_state|{pattern}", None if scored["decision"] is False else case_row(case, scored, rests)
    native = True in ins
    if native == scored["decision"]:
        return pop, f"agree|{pattern}", None
    y = scored["yaw"] if scored["decision"] else next(y for y, r in rests.items() if r and r["in"])
    o, nozero = rests[y], oracle(turret, pt, y, zeroing=False)
    if o is None:
        cause = "pivot_skip"
    elif abs(math.remainder(math.radians(turret["arc"][1] - turret["arc"][0]), 2 * math.pi)) < EPS:
        cause = "full_circle_arc"
    elif o["degenerate"]:
        cause = "missing_projection_rule"
    elif (o["outside"] < EPS) != scored["decision"] and (nozero["outside"] < EPS) == scored["decision"]:
        cause = "missing_component_zeroing"
    elif o["outside"] < EPS or o["edge"] < EPS or o["near"]:  # includes the native clamp to the far limit one ulp inside
        cause = "float32_indeterminate"
    else:
        cause = "other"
    side = "false_ENGAGEABLE" if scored["decision"] else "false_NOT_ENGAGEABLE"
    return pop, f"{cause}|{pattern}|{side}", case_row(case, scored, o)


def case_row(case, scored, o):
    pop, name, turret, pt = case
    return {"population": pop, "case": name, "macro": turret["macro"], "arc": turret["arc"], "target": pt,
            "scorer": {k: v for k, v in scored.items() if k != "muzzle"}, "oracle": o}


def synthetic(name, arc, t_g=(0.0, 0.0, 0.0), rg=I3, rl=I3):
    aim = np.array(rl[2]) @ np.array(rg)
    return {"macro": name, "arc": arc, "seg": {"L": ((0.0, 0.0, 1.0), rl), "G": (t_g, rg), "H": ((0.0, 0.0, 0.0), I3)},
            "yaw": {"t_G": t_g, "t_H": (0.0, 0.0, 0.0), "R_H": I3, "beta": math.atan2(aim[0], aim[2])}}


def at_pitch(turret, p, phi, r):
    """Target at requested pitch p from the pitch pivot with the aim plane at yaw phi."""
    L, G, H = (turret["seg"][k] for k in "LGH")
    J = np.array(joint_matrix(0.0, phi))
    a = L[1][2]
    t = p + math.atan2(a[1], a[2])
    u = np.array((0.0, math.sin(t), math.cos(t))) @ (np.array(G[1]) @ J @ np.array(H[1]))
    C = np.array(G[0]) @ J @ np.array(H[1]) + np.array(H[0])
    return tuple(float(c) for c in C + r * u)


def cases():
    for t in TURRETS:
        for di, d in enumerate(study.DIRS):
            r = study.RADII[di % 9]
            yield "ordinary", f"dir{di}/r{r}", t, tuple(r * c for c in d)
    deltas = sorted({s * m for s in (-1, 1) for m in (0, 1e-7, 4e-7, math.radians(4e-5), math.radians(6e-5), 2e-6,
                                                       1e-5, 1e-4, 5e-4, 9.99e-4, 1.001e-3, 1e-2)})
    for t in TURRETS:
        for side, b in enumerate(t["arc"]):
            for dl, phi, r in itertools.product(deltas, (0.3, 1.9, 3.5, 5.0), (100.0, 5000.0)):
                yield "adversarial", f"{'lo' if side == 0 else 'hi'}{dl:+.3g}/phi{phi}/r{r:g}", t, at_pitch(t, math.radians(b) + dl, phi, r)
    arcs = ((-10.0, 90.0), (-45.0, 40.0), (18.0, 89.0), (-60.0, -5.0), (-180.0, 180.0))
    for arc in arcs:
        plain, tilted = synthetic(f"id{arc}", arc), synthetic(f"tilt{arc}", arc, rl=rx(0.3))
        axial = synthetic(f"pitchaxis{arc}", arc, rg=rz(math.pi / 2), rl=rx(0.3))
        for t in (plain, tilted, axial):
            for name, pt in [("pivot", (0.0, 0.0, 0.0)), ("pivot+1e-30", (0.0, 1e-30, 0.0)), ("pivot+1e-12", (1e-12, 1e-12, 1e-12)),
                             ("up", (0.0, 1000.0, 0.0)), ("up-back5e-4", (0.0, 1000.0, -0.5)), ("up-back2e-3", (0.0, 1000.0, -2.0)),
                             ("up-off", (1e-5, 1000.0, 1e-5)), ("down", (0.0, -1000.0, 0.0)), ("behind-below", (0.0, -1e-3, -1000.0)),
                             ("nan", (math.nan, 0.0, 1.0)), ("inf", (math.inf, 0.0, 1.0))]:
                yield "stress", name, t, pt
            for dl in (-1e-2, -1e-3, -1e-6, 0.0, 1e-6, 1e-3, 1e-2):
                for side, b in enumerate(arc):
                    yield "stress", f"{'lo' if side == 0 else 'hi'}{dl:+g}", t, at_pitch(t, math.radians(b) + dl, 0.7, 1000.0)
                yield "stress", f"wrap{dl:+g}", t, at_pitch(t, math.pi + dl, 0.7, 1000.0)


def yaw_cases():
    """Reference geometries: several rests (all in / mixed / all out), one rest + trap, no rest; multi-solution engageable()."""
    several = synthetic("several", (-10.0, 60.0), t_g=(0.0, 1.0, -5.0))
    trap = synthetic("trap", (-10.0, 90.0), t_g=(1.0, 1.0, 2.0), rg=ry(math.pi / 2))
    none = synthetic("none", (-10.0, 90.0), t_g=(0.0, 1.0, 2.0))
    pts = {"several_mixed": (several, (0.0, 9.0, 3.0)), "several_all_in": (several, (0.0, 1.5, 3.0)),
           "several_all_out": (several, (0.0, -2.0, 3.0)), "one_out": (several, (0.0, -500.0, 1000.0)),
           "one_in": (several, (0.0, 100.0, 1000.0)),
           "one_trap": (trap, (1.0, 20.0, 2.0)), "none": (none, (math.sin(0.7), 1.0, math.cos(0.7)))}
    want = {"several_mixed": ("several", {True, False}, True), "several_all_in": ("several", {True}, True),
            "several_all_out": ("several", {False}, False), "one_out": ("one", {False}, False), "one_in": ("one", {True}, True),
            "one_trap": ("one", {True}, False), "none": ("none", set(), False)}
    report = {}
    for k, (t, pt) in pts.items():
        g = classify(t["yaw"], pt)
        rests = [(round(y, 6), oracle(t, pt, y)["in"]) for y in g["resting"]]
        scored = study.geometry(t, I3, (0.0, 0.0, 0.0), pt)
        report[k] = {"class": g["class"], "traps": len(g["traps"]), "rest_in_arc": rests, "scorer": scored["state"]}
        assert (g["class"], {v for _, v in rests}, scored["decision"]) == want[k], (k, report[k])
    assert report["one_trap"]["traps"] and not report["several_mixed"]["traps"]

    def sol(k, status="pass"):
        return {"status": status, "point": pts[k][1]}

    sets = {"empty": ([], False), "one_in+one_out": ([sol("one_in"), sol("one_out")], True),
            "one_out+failed_one_in": ([sol("one_out"), sol("one_in", "miss")], False),
            "several_mixed+one_out": ([sol("several_mixed"), sol("one_out")], True),
            "several_all_out+one_out+failed_mixed": ([sol("several_all_out"), sol("one_out"), sol("several_mixed", "miss")], False),
            "several_all_out+several_all_in+one_out": ([sol("several_all_out"), sol("several_all_in"), sol("one_out")], True)}
    for k, (s, expected) in sets.items():
        got = {study.engageable(several, I3, (0.0, 0.0, 0.0), list(p)) for p in itertools.permutations(s)}
        assert got == {expected}, (k, got)
        report["engageable:" + k] = expected
    trap_sets = [[sol("one_trap")], []]
    assert not any(study.engageable(trap, I3, (0.0, 0.0, 0.0), s) for s in trap_sets)
    assert not study.engageable(none, I3, (0.0, 0.0, 0.0), [{"status": "pass", "point": pts["none"][1]}])
    return report


def main():
    os.nice(10)
    counts, rows = Counter(), []
    with Pool(4) as pool:
        for pop, cause, row in pool.imap_unordered(audit, cases(), chunksize=64):
            counts[pop, cause] += 1
            if row:
                rows.append(row)
    out = REPO / ".x4-research-cache/issue173-scorer-audit"
    out.mkdir(exist_ok=True)
    result = {"eps_rad": EPS, "counts": {f"{p}|{c}": n for (p, c), n in sorted(counts.items())},
              "yaw_and_solutions": yaw_cases(), "disagreements": rows}
    json.dump(result, open(out / "result.json", "w"), indent=1, default=str)
    print(json.dumps(result["counts"], indent=1))
    print(json.dumps(result["yaw_and_solutions"], default=str))


if __name__ == "__main__":
    main()
