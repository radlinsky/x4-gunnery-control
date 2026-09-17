"""A5 same-ray audit (buckets 2, 3, 4, 8) over the accepted A4 trials. Reads A4 rows; never rewrites them.

Scans the #173 scorer along the anchor ray with the same inputs A4 used. Output goes to stdout only.
"""
import os

for _var in ('OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'MKL_NUM_THREADS'):
    os.environ.setdefault(_var, '1')

import gzip  # noqa: E402
import json  # noqa: E402
import math  # noqa: E402
import sys  # noqa: E402
from collections import Counter  # noqa: E402
from multiprocessing import Pool  # noqa: E402
from pathlib import Path  # noqa: E402

import numpy as np  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'issue176-a4'))
import compare as a4  # noqa: E402

old = a4.old
SUPPORTED = ('normal', 'difficult')


def setup(index):
    """The A4 case exactly as compare.evaluate builds it: scorer body origin, anchor ray and anchor index."""
    _, _, s, ti, ri = a4.CASES[index]
    turret, R, o = old.CORPUS['turrets'][ti], old.ROT[ri], np.asarray(s['O'], float)
    seg, (lo, hi) = turret['seg'], turret['arc']
    pitch = math.radians(0. if lo <= 0 <= hi else lo if lo > 0 else hi)
    muzzle = np.asarray(old.compose(old.compose(old.compose(seg['L'], ((0., 0., 0.), old.joint_matrix(pitch, 0.))), seg['G']),
                                    old.compose(((0., 0., 0.), old.joint_matrix(0., 0.)), seg['H']))[0])
    log = []
    d0 = np.asarray(old.Q(o, s['points'], log))
    return dict(s=s, turret=turret, R=R, o=o, body=tuple(map(float, o - muzzle @ np.asarray(R))), d0=d0, anchor=log[0][2],
                offset=float(np.linalg.norm(muzzle)))


def at(c, t):
    return old.geometry(c['turret'], c['R'], c['body'], tuple(map(float, c['o'] + t * c['d0'])))


def label(r):
    return 'YES' if r['state'] == 'IN_ARC' else 'NO' if r['state'] == 'OUT_OF_ARC' else r['state']


def mechanism(c, t):
    """What changes across a transition at t: scorer UNKNOWN, yaw class/solution, or an authored pitch limit."""
    a, b = at(c, t * (1 - 2e-7)), at(c, t * (1 + 2e-7))
    if 'UNKNOWN' in a['state'] + b['state']:
        return 'unknown:' + (a if 'UNKNOWN' in a['state'] else b)['state']
    if a['yaws'] != b['yaws'] or abs(a['yaw'] - b['yaw']) > 1e-3:
        return 'yaw'
    lo, hi = c['turret']['arc']
    pitch = [math.degrees(r['pitch']) for r in (a, b)]
    return 'pitch_limit_lo' if min(abs(p - lo) for p in pitch) < 1e-2 else 'pitch_limit_hi' if min(abs(p - hi) for p in pitch) < 1e-2 else 'other'


def transitions(c, lo, hi, n):
    """Log-spaced labels, each change bisected to 1e-7 relative. Islands narrower than the grid can be missed."""
    ts = np.geomspace(lo, hi, n)
    labels = [label(at(c, t)) for t in ts]
    out = []
    for i in range(n - 1):
        if labels[i] != labels[i + 1]:
            a, b = ts[i], ts[i + 1]
            while b / a > 1 + 1e-7:
                m = math.sqrt(a * b)
                a, b = (m, b) if label(at(c, m)) == labels[i] else (a, m)
            out.append((float(a), labels[i], labels[i + 1], mechanism(c, a)))
    return labels, out


def scan_row(job):
    row, n = job
    c = setup(row['index'])
    labels, out = transitions(c, *row['bracket'], n)
    return row, labels, out, c['offset']


def main():
    os.nice(10)
    a4.CASES.extend(a4.cases())
    rows = [json.loads(line) for line in gzip.open(a4.OUT / 'trials.jsonl.gz', 'rt')]
    sup = [r for r in rows if r['population'] in SUPPORTED and 'probes' in r]

    print('## Bucket 3: decided same-ray errors')
    for r in sup:
        if r['same_ray'] != 'UNKNOWN' and r['truth'] != 'UNKNOWN' and r['same_ray'] != r['truth']:
            print(r['index'], r['population'], r['name'], r['turret'], 'factor', r['factor'], 'rough', r['rough'],
                  'distance', round(r['distance'], 3), 'bracket', r['bracket'], 'probes', r['probes'], r['truth'], '->', r['same_ray'])
    for index in sorted({r['index'] for r in sup if r['same_ray'] not in ('UNKNOWN', r['truth']) and r['truth'] != 'UNKNOWN'}):
        c = setup(index)
        point = np.asarray(c['s']['points'][c['anchor']])
        distance = float(np.linalg.norm(point - c['o']))
        truth = old.geometry(c['turret'], c['R'], c['body'], tuple(map(float, point)))
        print(f"\n{index}: arc {c['turret']['arc']}, |muzzle offset| {c['offset']:.3f} m, anchor {c['anchor']} of "
              f"{len(c['s']['points'])}, ray-vs-point residual {np.linalg.norm(c['o'] + distance * c['d0'] - point):.2e} m, "
              f"truth {label(truth)} pitch {math.degrees(truth['pitch']):.4f}")
        for t in (5, 10, 20, 40, distance, 1e3, 1e9):
            r = at(c, t)
            print(f"  t={t:.6g}: {label(r)} yaws={r['yaws']} yaw={math.degrees(r.get('yaw', math.nan)):.3f} "
                  f"pitch={math.degrees(r.get('pitch', math.nan)):.4f}")
        for x in transitions(c, .5, 1e9, 800)[1]:
            print('  transition', x)

    jobs = [(r, 150 if r['bracket'][1] < 1e8 else 400) for r in sup if r['factor'] == 1 and r['same_ray_reason'] == 'bracket_disagree']
    # ponytail: 24 samples per closed bracket only screens for flip-back; narrow islands can hide between samples.
    jobs += [(r, 24) for r in sup if r['factor'] == 1 and r['same_ray_reason'] == 'bracket_agree'
             and r['rough'] in (10, 100) and r['bracket'][1] < 1e8]
    disagree, agree = Counter(), Counter()
    with Pool(4) as pool:
        for row, labels, out, offset in pool.imap_unordered(scan_row, jobs, chunksize=4):
            closed = 'closed' if row['bracket'][1] < 1e8 else 'open'
            if row['same_ray_reason'] == 'bracket_disagree':
                side = labels[0] if not out or row['distance'] < out[0][0] else labels[-1]
                disagree[row['population'], row['rough'] == 10, closed, len(out), tuple(sorted({m for *_, m in out})),
                         row['truth'] == side or row['truth'] == 'UNKNOWN'] += 1
            else:
                changes = sum(a != b for a, b in zip(labels, labels[1:]))
                agree[row['population'], row['rough'], changes] += 1
                if changes:
                    print('closed bracket_agree flip-back', row['index'], row['name'], row['turret'], row['bracket'],
                          round(row['distance'], 3), row['truth'], out)
    print('\n## Bucket 2: bracket_disagree at factor 1 '
          '(population, 10 m, bracket, transitions, mechanisms, truth on predicted side): rows')
    for k, v in sorted(disagree.items(), key=str):
        print(' ', k, v)
    print('\n## Closed bracket_agree screen at 10/100 m, 24 samples (population, rough, label changes): rows')
    for k, v in sorted(agree.items()):
        print(' ', k, v)

    print('\n## Candidate A: all-forward ladder (no upper bound) -> UNKNOWN. coverage, decided errors: before | after')
    for factor in a4.FACTORS:
        for pop in SUPPORTED:
            known = [r for r in sup if r['factor'] == factor and r['population'] == pop and r['truth'] != 'UNKNOWN']
            stats = []
            for fix in (False, True):
                answers = ['UNKNOWN' if fix and r['bracket'][1] is not None and r['bracket'][1] >= a4.FAR else r['same_ray']
                           for r in known]
                decided = [(a, r['truth']) for a, r in zip(answers, known) if a != 'UNKNOWN']
                stats.append((round(len(decided) / len(known), 4), sum(a != t for a, t in decided)))
            print(' ', factor, pop, stats[0], '|', stats[1])

    print('\n## Bucket 4: first probe position versus the selected aim point (population, factor): '
          'beyond / short within 6.5% / short; first probe non-forward in each')
    for factor in a4.FACTORS:
        for pop in SUPPORTED:
            zones = Counter()
            for r in sup:
                if r['factor'] == factor and r['population'] == pop:
                    s0 = a4.LADDER[0] * factor * r['rough']
                    zone = 'beyond' if r['distance'] <= s0 else 'within' if r['distance'] <= 1.065 * s0 else 'short'
                    zones[zone, r['probes'][0][1] != 'forward'] += 1
            print(' ', pop, factor, {z: (zones[z, False] + zones[z, True], zones[z, True]) for z in ('beyond', 'within', 'short')})
    print('\n  selected distance / rough at factor 1 (population, subgroup, rough): min, median, max, fraction < 1')
    groups = {}
    for r in sup:
        if r['factor'] == 1:
            groups.setdefault((r['population'], r['subgroup'], r['rough']), []).append(r['distance'] / r['rough'])
    for k, v in sorted(groups.items()):
        v.sort()
        print(' ', k, round(v[0], 3), round(v[len(v) // 2], 3), round(v[-1], 3), round(sum(x < 1 for x in v) / len(v), 3))
    print('\n  factor 2 no_lower_bound / rows (population, subgroup, rough)')
    loss, total = Counter(), Counter()
    for r in sup:
        if r['factor'] == 2:
            total[r['population'], r['subgroup'], r['rough']] += 1
            loss[r['population'], r['subgroup'], r['rough']] += r['same_ray_reason'] == 'no_lower_bound'
    for k in sorted(total):
        print(' ', k, loss[k], '/', total[k])

    print('\n## Bucket 8: hidden switches (a probe selects another aim point and still reads forward)')
    for r in sup:
        if not r['hidden_switch']:
            continue
        c = setup(r['index'])
        points = np.asarray(c['s']['points'])
        for m, kind, selected in r['probes']:
            if selected == c['anchor'] or kind != 'forward':
                continue
            u = np.asarray(old.F3(c['o'] + m * r['rough'] * r['factor'] * c['d0']))
            p, anchor = points[selected], points[c['anchor']]
            print(f"  {r['index']} f={r['factor']} probe {m}: range {np.linalg.norm(p - u):.1f} m, aim-point separation "
                  f"{np.linalg.norm(p - anchor):.3f} m, lateral/range {np.linalg.norm(np.cross(p - u, c['d0'])) / np.linalg.norm(p - u):.2e}, "
                  f"anchor depth - probe {np.dot(anchor - u, c['d0']):.1f} m, answer {r['same_ray']} truth {r['truth']}")


if __name__ == '__main__':
    main()
