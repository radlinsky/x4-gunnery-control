"""A4 offline ENGAGEABLE comparison: direction-only, same-ray bracket, three-ray (+inward fourth).

Reuses the A2 corpus/three-ray implementation, the P3c direction-query surrogate and the accepted #173 scorer
(`study.geometry`). Stacks are combined from the per-method rows by report.py.
"""
import os

for _var in ('OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'MKL_NUM_THREADS'):
    os.environ.setdefault(_var, '1')

import gzip  # noqa: E402
import itertools  # noqa: E402
import json  # noqa: E402
import math  # noqa: E402
import sys  # noqa: E402
from multiprocessing import Pool  # noqa: E402
from pathlib import Path  # noqa: E402

import numpy as np  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'research/issue176-a2'))
import simulate as a2  # noqa: E402  (also exposes the P3c study module as a2.old)

old = a2.old
OUT = ROOT / '.x4-research-cache/issue176-a4'
RULE = 'medium'          # A2's audited three-ray rule: .03 x rough, 1-128 m, 90 degrees
FACTORS = (.5, 1, 2)     # rough-distance estimate multipliers, as in A2
LADDER = (.5, 1, 2)      # same-ray probe distances, multiples of the rough distance
FORWARD = 1e-4           # same-ray collinearity tolerance (radians), ~30x the per-query angular allowance
FAR = 1e9                # "infinitely far" point along the anchor ray; direction-only scoring
CASES = []


def cases():
    """(population, subgroup, sample, turret index, rotation index); turret/rotation cycle as in P3c."""
    samples = a2.corpus()
    records = old.CORPUS['records']
    singles = {r['component']: r for r in records if len(r['points']) == 1}
    for name, r in sorted(singles.items()):
        # Rough distance is measured from the macro box centre, so it is not the aim-point distance.
        for radius, direction in itertools.product((10, 100, 1000, 10000, 100000), old.fibonacci(6)):
            samples.append(dict(family='single', name=name, O=list(old.F3(np.add(r['C'], np.multiply(radius, direction)))),
                                points=r['points'], rough=radius))
    # Exactly collinear hidden replacement: the r probe overshoots P0 and selects P1 straight ahead.
    samples.append(dict(family='synthetic', name='collinear_replacement', O=[0., 0., 0.],
                        points=[(0., 0., 60.), (0., 0., 130.)], rough=100))
    population = {'single': ('normal', 'single-point'), 'ordinary': ('normal', 'multi-point'),
                  'boundary': ('difficult', 'boundary'), 'known172': ('difficult', 'known172'),
                  'synthetic': ('stress', 'synthetic')}
    out = []
    for s in samples:
        for t in range(92) if s['family'] == 'synthetic' else [None]:
            i = len(out)
            out.append((*population[s['family']], s, i % 92 if t is None else t, (i // 92) % 24))
    return out


def three_ray(s, factor):
    """A2 medium triple plus the retained inward fourth probe (A2 dropped the outward branch)."""
    initial, log, recovery, pts = a2.run(s, RULE, factor)
    if recovery and recovery['outward']:
        slope, lower, upper, _ = a2.RULES[RULE]
        spacing = min(upper, max(lower, slope * s['rough'] * factor))
        a, b = a2.basis(np.asarray(log[0][1]))
        del log[3:]
        old.Q(np.asarray(s['O']) + max(lower, spacing / 4) * (a + b) / math.sqrt(2), pts, log)
        recovery = None
        for triple in ((0, 1, 3), (0, 2, 3)):
            r = a2.consensus([log[j][0] for j in triple], [log[j][1] for j in triple])
            r['selections'] = [log[j][2] for j in triple]
            if recovery is None or r['status'] == 'pass':
                recovery = r
            if r['status'] == 'pass':
                break
    return initial, recovery, log, pts


def same_ray(o, d0, rough, pts):
    """Fixed three-probe ladder on the anchor ray. Returns (lo, hi, reason, probes); lo/hi None on UNKNOWN."""
    probes, upper = [], []
    for m in LADDER:
        log, s = [], m * rough
        u = old.F3(o + s * d0)
        d = old.Q(u, pts, log)
        if d is None:
            kind = 'at_point'
        else:
            c, k = float(np.dot(d, d0)), float(np.linalg.norm(np.cross(d, d0)))
            kind = 'forward' if c > 0 and k <= FORWARD else 'reversed' if c < 0 and k <= FORWARD else 'switched'
        probes.append((m, kind, log[0][2]))
        # A probe just short of the point sees anchor quantization/rounding as a large angle and reads non-forward;
        # that only happens within this relative gap, so a non-forward probe bounds the distance by s * (1 + slack).
        rho = 2 * old.u * max(1., *map(abs, u))
        upper.append(s * (1 + 2 * (a2.EPS + rho / s) / FORWARD))
    forward = [p[1] == 'forward' for p in probes]
    n = sum(forward)
    if forward != [True] * n + [False] * (len(LADDER) - n):
        return None, None, 'inconsistent', probes
    if n == 0:
        return None, None, 'no_lower_bound', probes
    return LADDER[n - 1] * rough, upper[n] if n < len(LADDER) else FAR, 'bracket', probes


def evaluate(index):
    pop, sub, s, ti, ri = CASES[index]
    turret, R, o = old.CORPUS['turrets'][ti], old.ROT[ri], np.asarray(s['O'], float)
    # Sampled O is the prospective muzzle; the scorer takes the component origin, so back out the rest-pose
    # (yaw = pitch = 0) muzzle offset L∘Rx(0)∘G∘Ry(0)∘H, rotated to world by the scorer's inverse (p-O)·Rᵀ.
    seg, rest = turret['seg'], ((0., 0., 0.), old.joint_matrix(0., 0.))
    muzzle = np.asarray(old.compose(old.compose(old.compose(seg['L'], rest), seg['G']), old.compose(rest, seg['H']))[0])
    body = o - muzzle @ np.asarray(R)
    assert np.allclose((o - body) @ np.asarray(R).T, muzzle, atol=1e-6 * max(1., *abs(o))), (index, o, body)
    body = tuple(map(float, body))
    memo = {}

    def score(p):
        key = tuple(map(float, p))
        if key not in memo:
            state = old.geometry(turret, R, body, key)['state']  # plain floats: the gate rejects numpy bools
            memo[key] = 'YES' if state == 'IN_ARC' else 'NO' if state == 'OUT_OF_ARC' else 'UNKNOWN'
        return memo[key]

    rows = []
    for factor in FACTORS:
        initial, recovery, log, pts = three_ray(s, factor)
        _, d0, anchor = log[0]
        truth_point = np.asarray(pts[anchor], float)
        row = dict(index=index, population=pop, subgroup=sub, name=s['name'], rough=s['rough'], factor=factor,
                   turret=turret['macro'], rotation=ri, aim_points=len(pts), truth=score(truth_point))
        if d0 is None:
            row.update(direction='UNKNOWN', direction_q=1, same_ray='UNKNOWN', same_ray_q=1, same_ray_reason='invalid',
                       three_ray='UNKNOWN', three_ray_q=len(log[:3]), three_ray4='UNKNOWN', three_ray4_q=len(log))
            rows.append(row)
            continue
        d0 = np.asarray(d0)
        distance = float(np.linalg.norm(truth_point - o))
        row.update(distance=distance, direction=score(o + FAR * d0), direction_q=1)

        rough = s['rough'] * factor
        lo, hi, reason, probes = same_ray(o, d0, rough, pts)
        answer = 'UNKNOWN'
        if lo is not None:
            ends = {score(o + lo * d0), score(o + hi * d0)}
            answer = ends.pop() if len(ends) == 1 and 'UNKNOWN' not in ends else 'UNKNOWN'
            reason = 'bracket_agree' if answer != 'UNKNOWN' else 'bracket_disagree'
        row.update(same_ray=answer, same_ray_q=1 + len(LADDER), same_ray_reason=reason, bracket=[lo, hi],
                   bracket_holds=lo is None or lo <= distance < hi, probes=probes,
                   probe_switch=any(p[2] != anchor for p in probes),
                   hidden_switch=any(p[2] != anchor and p[1] == 'forward' for p in probes))

        for key, r, q in (('three_ray', initial, 3), ('three_ray4', recovery or initial, len(log))):
            passed = r['status'] == 'pass'
            row.update({key: score(r['point']) if passed else 'UNKNOWN', key + '_q': q, key + '_status': r['status'],
                        key + '_mixed': len(set(r.get('selections', []))) > 1,
                        key + '_error': float(np.linalg.norm(np.asarray(r['point']) - truth_point)) if passed else None})
        rows.append(row)
    return rows


def main():
    os.nice(10)
    stride = int(sys.argv[1]) if len(sys.argv) > 1 else 1  # pilot: every Nth case
    CASES.extend(cases())
    indices = range(0, len(CASES), stride)
    OUT.mkdir(parents=True, exist_ok=True)
    with Pool(4) as pool, gzip.open(OUT / 'trials.jsonl.gz', 'wt') as stream:
        for done, rows in enumerate(pool.imap(evaluate, indices, chunksize=16), 1):
            for row in rows:
                stream.write(json.dumps(row) + '\n')
            if done % 1000 == 0:
                print(done, '/', len(indices), flush=True)
    print('cases', len(indices), 'rows', len(indices) * len(FACTORS))


if __name__ == '__main__':
    main()
