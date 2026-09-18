"""Issue #176 A5: adaptive multi-ray aim-point finder with an angular CANNOT BEAR stop, on the accepted A4x cases.

Offline research. Reuses the A4x design, scenarios, query model (study.Q: native nearest aimtarget, binary32,
quantized yaw/pitch) and truth scorer unchanged. Queries are chosen per (scenario, turret, factor) because the
stop rule depends on the turret. Writes ignored rows to .x4-research-cache/issue176-a5/adaptive.jsonl.gz.

    python3 research/issue176-a5/adaptive.py --selftest
    python3 research/issue176-a5/adaptive.py [--jobs 4]      # ~all 113,490 rows, niced
"""
from __future__ import annotations

import argparse
import gzip
import json
import math
import os
import sys
from multiprocessing import Pool
from pathlib import Path

for _var in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"):
    os.environ.setdefault(_var, "1")

import numpy as np  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "research/issue176-a4x")]
import compare as a4x  # noqa: E402  (A4x design + historical A4 + A2 + study)
import scorer  # noqa: E402

hist = a4x.historical
a2, old = hist.a2, hist.old
OUT = ROOT / ".x4-research-cache/issue176-a5"
BUDGET = 24          # research cap, deliberately loose
SAFETY = 2.0         # required limit margin / linearised pitch uncertainty
ALPHA0 = math.radians(2.0)   # first sideways viewing-angle change
ALPHA_MIN = math.radians(1 / 64)
SLACK = 2 * (a2.EPS + 1e-6) / hist.FORWARD  # along-ray upper-bound slack (~8%); the along-ray resolution floor


# ---------------------------------------------------------------- query primitives (observed data only)

def query(u, pts, log):
    d = old.Q(u, pts, log)
    return None if d is None else np.asarray(d, float)


def along(o, d0, s, pts, log):
    """Same-ray primitive at depth s. Returns (kind, bound): non-forward bounds t above (sound under nearest
    selection: an anchor ahead of the probe stays nearest); forward bounds t below (A4 same-ray assumption)."""
    u = np.asarray(old.F3(o + s * d0))
    d = query(u, pts, log)
    if d is None:
        return "at_point", s
    c, k = float(d @ d0), float(np.linalg.norm(np.cross(d, d0)))
    if c > 0 and k <= hist.FORWARD:
        return "forward", s
    rho = 2 * old.u * max(1., *map(abs, u))
    return "non_forward", s * (1 + 2 * (a2.EPS + rho / s) / hist.FORWARD)


def crossing(o, d0, u, d):
    """Where does the probe ray (u, d) meet the anchor ray? (tau, error bound) or None if it misses."""
    c = float(d0 @ d)
    k = float(np.linalg.norm(np.cross(d0, d)))
    if k < 1e-9:
        return None
    w = o - u
    s = (c * (d @ w) - d0 @ w) / (k * k)
    t = ((d @ w) - c * (d0 @ w)) / (k * k)
    x, y = o + s * d0, u + t * d
    rho = 2 * old.u * max(1., float(np.max(np.abs(x))), float(np.max(np.abs(u))))
    transverse = 2 * rho + a2.EPS * (abs(s) + abs(t))
    if s <= 0 or t <= 0 or np.linalg.norm(x - y) > transverse:
        return None
    return float(s), float(transverse / k)


# ---------------------------------------------------------------- known-turret certificate

class Turret:
    """Required-angle view of one A4x turret placed as A4x places it (reference endpoint at O)."""

    def __init__(self, record, rotation, muzzle, o):
        self.record, self.R = record, np.asarray(rotation, float)
        self.origin = np.asarray(o, float) - muzzle @ self.R      # component origin in world
        self.xy = record["mechanical_class"] == "ordinary_xy"
        self.t = scorer.accepted_turret(record) if self.xy else None
        if self.xy:  # angles are seen from the yaw pivot; the barrel hangs L then G below it (T = L J G J H)
            L, G, H = self.t["seg"]["L"], self.t["seg"]["G"], self.t["seg"]["H"]
            self.pivot = self.origin + np.asarray(H[0], float) @ self.R
            self.lever = math.hypot(*L[0]) + math.hypot(*G[0])

    def local(self, p):
        return tuple(map(float, (np.asarray(p, float) - self.origin) @ self.R.T))

    def answer(self, p):
        d = scorer.score(self.record, self.local(p))["decision"]
        return "YES" if d is True else "NO" if d is False else "UNKNOWN"

    def margins(self, p):
        """(gate class, [(in_arc, margin deg) per resting yaw], pole margin deg) or None if not certifiable."""
        if not self.xy:
            return None  # ponytail: 10 non-ordinary turrets get no certificate; add per-class margins if they matter
        pt = self.local(p)
        tr = self.t
        gate = scorer.study.classify(tr["yaw"], pt)
        if gate["traps"] or not gate["resting"]:
            return None
        L, G, H = tr["seg"]["L"], tr["seg"]["G"], tr["seg"]["H"]
        lo, hi = tr["arc"]
        out = []
        for y in gate["resting"]:  # study.geometry's per-rest pitch, kept per rest
            frame = old.compose(G, old.compose(((0.0, 0.0, 0.0), old.joint_matrix(0.0, y)), H))
            d = old.sub(pt, frame[0])
            n = old.norm(d)
            d = tuple(0.0 if abs(c) < old.ZEROING * n else c for c in d)
            qv = old.row(d, tuple(zip(*frame[1])))
            x = math.degrees(math.remainder(math.atan2(qv[1], qv[2]) - math.atan2(L[1][2][1], L[1][2][2]), 2 * math.pi))
            inside = lo <= x <= hi
            out.append((inside, min(x - lo, hi - x) if inside else max(lo - x, x - hi), x))
        d = np.asarray(old.sub(pt, H[0]), float)
        up = old.row(tuple(d / np.linalg.norm(d)), tuple(zip(*H[1])))[1]
        return gate["class"], out, 90 - math.degrees(math.asin(min(1., abs(up))))

    def spread(self, o, d0, lo, hi):
        """Propagated required-pitch uncertainty (deg) over {o + t d0 + e : lo <= t <= hi, |e| <= EPS t + rho}.

        Linearised: |grad pitch| at the centre (central differences) times the region diameter. Only offered when
        the region is under 1% of its distance from the yaw pivot and the yaw rest is unique, so curvature and rest
        switching cannot matter at that scale; everything else is infinite (no certificate)."""
        # ponytail: first-order bound; a global Lipschitz bound per turret is the upgrade if this proves loose/unsafe
        a, b = o + lo * d0, o + min(hi, hist.FAR) * d0
        centre = 0.5 * (a + b)
        cone = a2.EPS * min(hi, hist.FAR) + 4 * old.u * max(1., *map(abs, b))
        diam = float(np.linalg.norm(b - a)) + 2 * cone
        r = float(np.linalg.norm(centre - self.pivot))
        if diam > 0.01 * r:
            return math.inf
        h = max(diam, 1e-6 * r)
        grad = []
        for axis in np.eye(3):
            m = [self.margins(centre + sign * h * axis) for sign in (1, -1)]
            if any(x is None or x[0] != "one" for x in m):
                return math.inf
            grad.append((m[0][1][0][2] - m[1][1][0][2]) / (2 * h))
        return float(np.linalg.norm(grad)) * diam

    def certify(self, o, d0, lo, hi):
        key = (lo, hi)
        if getattr(self, "_last", (None,))[0] != key:
            self._last = (key, self._certify(o, d0, lo, hi))
        return self._last[1]

    def _certify(self, o, d0, lo, hi):
        """(answer or None, spread deg, margin deg). Every point of the region provably shares the answer when
        the answer's limit margin exceeds SAFETY x spread, the gate class holds, and the yaw pole is far away."""
        spread = self.spread(o, d0, lo, hi) if hi < math.inf and self.xy else math.inf
        if not math.isfinite(spread):
            return None, spread, None
        mid = o + math.sqrt(lo * min(hi, hist.FAR)) * d0 if lo > 0 else o + 0.5 * hi * d0
        ends = [self.margins(p) for p in (o + max(lo, 1e-9) * d0, mid, o + min(hi, hist.FAR) * d0)]
        if any(m is None for m in ends) or len({m[0] for m in ends}) > 1 or ends[1][2] <= SAFETY * spread + 1:
            return None, spread, None
        rests = ends[1][1]
        yes = [m for ok, m, _x in rests if ok]
        if yes:
            margin = max(yes)
            return ("YES" if margin > SAFETY * spread else None), spread, margin
        margin = min(m for _ok, m, _x in rests)
        return ("NO" if margin > SAFETY * spread else None), spread, margin


# ---------------------------------------------------------------- adaptive search

def angle_mid(turret, o, d0, lo, hi):
    """Depth that halves the viewing angle from the turret between lo and hi (hi may be infinite)."""
    def theta(t):
        v = o + t * d0 - (turret.pivot if turret.xy else turret.origin)
        return math.acos(max(-1., min(1., float(v @ d0) / np.linalg.norm(v))))
    target = 0.5 * (theta(lo) + (theta(hi) if hi < math.inf else 0.0))
    a, b = lo, hi if hi < math.inf else max(2 * lo, 1.0)
    while hi == math.inf and theta(b) > target:
        b *= 2
    for _ in range(60):
        m = 0.5 * (a + b)
        a, b = (m, b) if theta(m) > target else (a, m)
    return 0.5 * (a + b)


def run(sample, factor, turret, pts, d0, mode="adaptive"):
    """mode: adaptive (angular stop), locate (stop only at the depth-resolution floor), along (no sideways probes),
    tri2 (sideways only, two agreeing rays trusted without anchor-ray confirmation), strict (depth only from
    anchor-ray bounds; sideways crossings just place the next along-ray probes).
    Returns (answer, stop reason, log of per-query dicts)."""
    o = np.asarray(sample["O"], float)
    log, trace = [], []
    lo, hi = 0.0, math.inf
    rough = sample["rough"] * factor
    alpha, turn, misses, hits = ALPHA0, 0, [], []
    confirmed = located = False
    widen = 0
    a_axis, b_axis = a2.basis(d0)

    def record(kind, u, extra):
        entry = log[-1]
        spread = turret.certify(o, d0, lo, hi)
        trace.append(dict(q=len(log), kind=kind, u=[float(x) for x in u], selected=entry[2],
                          d=None if entry[1] is None else [float(x) for x in entry[1]],
                          lo=lo, hi=hi if hi < math.inf else None, spread=spread[1], margin=spread[2],
                          decided=spread[0], **extra))
        return spread[0]

    def resolved():
        sideways_done = mode in ("along", "strict") or alpha < ALPHA_MIN or len(log) + 3 > BUDGET
        return (located and (widen >= 2 or sideways_done)) or (sideways_done and hi < math.inf and hi / max(lo, 1e-300) - 1 <= 2.5 * SLACK)

    while len(log) < BUDGET:
        answer, spread, _m = turret.certify(o, d0, lo, hi)
        if answer and (mode != "locate" or resolved()):
            return answer, "certified", trace, len({e[2] for e in log}), len(misses)
        if resolved():
            return "UNKNOWN", "floor", trace, len({e[2] for e in log}), len(misses)
        estimate = angle_mid(turret, o, d0, lo, hi) if hi < math.inf else max(rough, 2 * lo)
        if mode != "along" and len(log) + 3 <= BUDGET and alpha >= ALPHA_MIN:
            # Sideways probe: start at depth lo/2 on the anchor ray (P stays nearest there) and step sideways by
            # the offset that changes the viewing angle of the estimated point by alpha.
            base = 0.5 * lo
            side = math.cos(turn * math.pi / 3) * a_axis + math.sin(turn * math.pi / 3) * b_axis
            u = np.asarray(old.F3(o + base * d0 + (estimate - base) * math.tan(alpha) * side))
            d = query(u, pts, log)
            hit = None if d is None else crossing(o, d0, u, d)
            record("side", u, dict(alpha_deg=math.degrees(alpha), hit=hit))
            if located and (hit is None or not (lo <= hit[0] <= hi)):
                widen = 2  # the wider view lost the aim point; the located region stands
                continue
            if hit is None or not (lo <= hit[0] <= hi) or hit[1] > 0.05 * hit[0]:
                # Another aim point (or a ray too poorly conditioned to use): keep it, look closer, turn.
                misses.append((u, d))
                alpha, turn = alpha / 2, turn + 1
                continue
            tau, err = hit
            hits.append((tau, err))
            turn += 1  # the next sideways ray comes from another direction
            if mode != "tri2" and not confirmed:
                # Coarse check on the anchor ray. A probe within SLACK short of the point reads non-forward, so the
                # lower probe stands SLACK back; the upper one sits just past the crossing. These bounds are kept.
                confirmed = True
                for s in (tau / (1 + 1.5 * SLACK) - 2 * err, tau + 2 * err):
                    if lo < s < hi:
                        kind, bound = along(o, d0, s, pts, log)
                        lo, hi = (max(lo, bound), hi) if kind == "forward" else (lo, min(hi, bound))
                        record("confirm", log[-1][0], dict(result=kind))
                if not lo <= tau <= hi:
                    alpha = 0.0  # the anchor ray disowns this crossing; bisect along the ray from here
                    continue
            a, b = hits[-2:] if len(hits) > 1 else (None, None)
            if mode != "strict" and a and abs(a[0] - b[0]) <= a[1] + b[1] and lo <= b[0] <= hi:
                # Two sideways rays from different directions agree with each other and with the anchor-ray bounds.
                lo, hi = max(lo, min(a[0] - a[1], b[0] - b[1])), min(hi, max(a[0] + a[1], b[0] + b[1]))
                if located:
                    widen += 1
                located = True
                record("located", log[-1][0], {})
                # Located but not yet decided: a wider viewing angle shrinks the crossing error ~1/alpha.
                alpha = min(4 * alpha, math.radians(30))
            elif mode == "strict":
                alpha = 0.0
            continue
        kind, bound = along(o, d0, estimate, pts, log)
        lo, hi = (max(lo, bound), hi) if kind == "forward" else (lo, min(hi, bound))
        record("along", log[-1][0], dict(result=kind))
    answer, _spread, _m = turret.certify(o, d0, lo, hi)
    if answer and (mode != "locate" or resolved()):
        return answer, "certified", trace, len({e[2] for e in log}), len(misses)
    return "UNKNOWN", "budget", trace, len({e[2] for e in log}), len(misses)


# ---------------------------------------------------------------- benchmark

TURRETS = ROTATIONS = None
KEEP_TRACE = ("bracket_disagree",)


def evaluate(plan):
    sid, population, subgroup, sample, assignments = plan
    rows = []
    for factor in a4x.FACTORS:
        _initial, _recovery, log, pts = hist.three_ray(sample, factor)
        _u, d0, anchor = log[0]
        truth_point = np.asarray(pts[anchor], float)
        for ti, ri in assignments:
            key, record, muzzle = TURRETS[ti]
            turret = Turret(record, ROTATIONS[ri], muzzle, sample["O"])
            row = dict(case_id=f"{sid}:{ti}", rough_factor=factor, truth=turret.answer(truth_point),
                       scenario=a4x.SCENARIO[population], aim_points=len(pts))
            if d0 is None:
                row.update(adaptive="UNKNOWN", adaptive_stop="invalid", adaptive_q=1)
                rows.append(row)
                continue
            d0v = np.asarray(d0, float)
            depth = float((truth_point - np.asarray(sample["O"], float)) @ d0v)
            for mode in ("adaptive", "locate", "strict", "along", "tri2"):
                answer, stop, trace, selected, misses = run(sample, factor, turret, pts, d0v, mode)
                final = trace[-1] if trace else dict(lo=0.0, hi=None, spread=math.inf, margin=None)
                row.update({mode: answer, mode + "_stop": stop, mode + "_q": 1 + len(trace)})
                if mode == "adaptive":
                    hi = final["hi"] if final["hi"] is not None else math.inf
                    row.update(adaptive_selected=selected, adaptive_misses=misses,
                               adaptive_spread=final["spread"], adaptive_margin=final["margin"],
                               adaptive_holds=final["lo"] <= depth <= hi, adaptive_trace=trace)
                    if answer != "UNKNOWN":
                        # Safety screen (not proof): dense truth scan of the certified depth interval.
                        ts = np.geomspace(max(final["lo"], 1e-6), min(hi, hist.FAR), 24)
                        row["adaptive_scan_flip"] = any(turret.answer(np.asarray(sample["O"]) + t * d0v) != answer for t in ts)
            rows.append(row)
    return rows


def _init(turrets, rotations):
    global TURRETS, ROTATIONS
    TURRETS, ROTATIONS = turrets, rotations


def setup():
    records = scorer.load()
    turrets = [(k, records[k], a4x._reference_endpoint(records[k])) for k in sorted(records)]
    return turrets, hist.old.ROT


def selftest():
    """Pilot scenarios, 4 turrets each: no false answer, every region holds the true depth, something certifies."""
    turrets, rotations = setup()
    _init(turrets, rotations)
    plans = a4x.design(pilot=True)
    rows = [r for p in plans for r in evaluate((*p[:4], p[4][:4]))]
    assert rows and all(r["truth"] in ("YES", "NO", "UNKNOWN") for r in rows)
    wrong = [r for r in rows if r.get("adaptive", "UNKNOWN") not in ("UNKNOWN", r["truth"])]
    assert not wrong, wrong[:1]
    assert all(r.get("adaptive_holds", True) for r in rows)
    assert any(r.get("adaptive") in ("YES", "NO") for r in rows)
    print("selftest ok:", len(rows), "rows, decided", sum(r.get("adaptive") not in (None, "UNKNOWN") for r in rows))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--focus", action="store_true", help="the 361 A5 focus cases (A4x factor-1 realistic failures)")
    parser.add_argument("--sample", type=int, default=0, help="also N seeded random cases for broad screening")
    args = parser.parse_args()
    os.nice(10)
    if args.selftest:
        return selftest()
    turrets, rotations = setup()
    plans = a4x.design()
    if args.focus or args.sample:
        import random
        from ray_failure_groups import ROWS, chain
        keep = set()
        if args.focus:
            for line in gzip.open(ROWS, "rt"):
                r = json.loads(line)
                if (r["truth"] != "UNKNOWN" and r["scenario"] == "feasible_realistic" and r["rough_factor"] == 1
                        and (r["same_ray_reason"] == "bracket_disagree" or chain(r)[1] != r["truth"]
                             or r["same_ray"] not in ("UNKNOWN", r["truth"]))):
                    keep.add(r["case_id"])
        every = [f"{p[0]}:{ti}" for p in plans for ti, _ri in p[4]]
        keep |= set(random.Random(176).sample(every, args.sample))
        plans = [(*p[:4], [a for a in p[4] if f"{p[0]}:{a[0]}" in keep]) for p in plans]
        plans = [p for p in plans if p[4]]
    name = "adaptive-focus" if args.focus and not args.sample else f"adaptive-sample{args.sample}" if args.sample else "adaptive"
    OUT.mkdir(parents=True, exist_ok=True)
    with Pool(min(args.jobs, 4), initializer=_init, initargs=(turrets, rotations)) as pool, \
            gzip.open(OUT / (name + ".jsonl.gz"), "wt") as stream:
        for done, rows in enumerate(pool.imap_unordered(evaluate, plans, chunksize=1), 1):
            for row in rows:
                stream.write(json.dumps(row, separators=(",", ":"), default=lambda x: x.item()) + "\n")
            print(done, "/", len(plans), flush=True)
    print("DONE", OUT / (name + ".jsonl.gz"), flush=True)


if __name__ == "__main__":
    main()
