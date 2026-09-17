"""Confusion metrics, fallback stacks and failure groups from compare.py trials."""
import gzip
import json
from collections import Counter, defaultdict

from compare import OUT

# baseline is standalone only; no stack contains it.
METHODS = ('baseline', 'direction', 'same_ray', 'three_ray', 'three_ray4')
STACKS = METHODS + (('three_ray', 'same_ray'), ('three_ray4', 'same_ray'), ('same_ray', 'three_ray4'),
                    ('three_ray4', 'direction'), ('same_ray', 'direction'), ('three_ray4', 'same_ray', 'direction'))
POPULATIONS = ('normal', 'difficult', 'stress')


def label(stack):
    return stack if isinstance(stack, str) else ' > '.join(stack)


def resolve(row, stack):
    """First non-UNKNOWN answer; the anchor query is shared, so each fallback adds its queries minus one."""
    answer, queries = 'UNKNOWN', 0
    for method in (stack,) if isinstance(stack, str) else stack:
        queries += row[method + '_q'] - (queries > 0)
        answer = row[method]
        if answer != 'UNKNOWN':
            break
    return answer, queries


def metrics(rows, stack):
    c, queries = Counter(), []
    for row in rows:
        answer, q = resolve(row, stack)
        queries.append(q)
        c['model_unknown'] += answer == 'UNKNOWN'
        if row['truth'] == 'UNKNOWN':
            c['truth_unknown'] += 1
            continue
        yes = row['truth'] == 'YES'
        c[('TP' if answer == 'YES' else 'FN') if yes else ('FP' if answer == 'YES' else 'TN')] += 1
        c['unknown_on_yes' if yes else 'unknown_on_no'] += answer == 'UNKNOWN'
    ratio = lambda a, b: round(a / b, 4) if b else None  # noqa: E731
    known = c['TP'] + c['FP'] + c['TN'] + c['FN']
    decided = known - c['unknown_on_yes'] - c['unknown_on_no']
    wrong = c['FP'] + c['FN'] - c['unknown_on_yes']
    return dict(cases=len(rows), **{k: c[k] for k in ('TP', 'FP', 'TN', 'FN', 'truth_unknown', 'model_unknown',
                                                        'unknown_on_yes', 'unknown_on_no')},
                sensitivity=ratio(c['TP'], c['TP'] + c['FN']), specificity=ratio(c['TN'], c['TN'] + c['FP']),
                precision=ratio(c['TP'], c['TP'] + c['FP']), accuracy=ratio(c['TP'] + c['TN'], known),
                coverage=ratio(decided, known), decided_accuracy=ratio(decided - wrong, decided),
                mean_queries=round(sum(queries) / len(queries), 3), max_queries=max(queries))


def mechanism(row, method):
    if method == 'same_ray':
        return (f"{row['same_ray_reason']} bracket_holds={row.get('bracket_holds')} "
                f"probe_switch={row.get('probe_switch')} hidden_switch={row.get('hidden_switch')}")
    if method.startswith('three_ray'):
        return f"{row.get(method + '_status')} mixed={row.get(method + '_mixed')}"
    if method == 'baseline':
        return 'zero-prebuilt always ENGAGEABLE'
    return 'far-point direction'


def main():
    rows = [json.loads(line) for line in gzip.open(OUT / 'trials.jsonl.gz', 'rt')]
    groups = defaultdict(list)
    for row in rows:
        for key in (row['population'], f"{row['population']}/{row['subgroup']}"):
            groups[key, row['factor']].append(row)
    result = {f'{key}|factor={factor}': {label(s): metrics(g, s) for s in STACKS} for (key, factor), g in sorted(groups.items())}
    (OUT / 'metrics.json').write_text(json.dumps(result, indent=1))

    cols = ('TP', 'FP', 'TN', 'FN', 'sensitivity', 'specificity', 'precision', 'accuracy', 'truth_unknown',
            'model_unknown', 'unknown_on_yes', 'unknown_on_no', 'coverage', 'decided_accuracy', 'mean_queries', 'max_queries')
    for key in sorted({k for k, _ in groups}, key=lambda k: (POPULATIONS.index(k.split('/')[0]), k)):
        for factor in (1, .5, 2):
            m = result[f'{key}|factor={factor}']
            print(f"\n### {key}, rough factor {factor} ({m['direction']['cases']} rows)\n")
            print('| method | ' + ' | '.join(cols) + ' |\n|---|' + '---:|' * len(cols))
            for s in STACKS:
                print(f'| {label(s)} | ' + ' | '.join(str(m[label(s)][c]) for c in cols) + ' |')

    print('\n## Decided-wrong and model-UNKNOWN groups (rough factor 1)')
    for pop in POPULATIONS:
        nominal = [r for r in rows if r['population'] == pop and r['factor'] == 1]
        for method in METHODS:
            wrong, unknown = Counter(), Counter()
            for r in nominal:
                if r['truth'] == 'UNKNOWN':
                    continue
                if r[method] == 'UNKNOWN':
                    unknown[r['subgroup'], mechanism(r, method)] += 1
                elif r[method] != r['truth']:
                    side = 'false ENGAGEABLE' if r[method] == 'YES' else 'false NOT ENGAGEABLE'
                    wrong[r['subgroup'], side, r['rough'], mechanism(r, method)] += 1
            print(f'\n{pop} / {method}: wrong {sum(wrong.values())}, UNKNOWN {sum(unknown.values())}')
            for k, n in wrong.most_common(12):
                print('  wrong', n, *k)
            for k, n in unknown.most_common(8):
                print('  unknown', n, *k)

    print('\n## Same-ray switching (rough factor 1): cases / probe selected another aim point / '
          'switch read as forward / bracket excludes truth distance / wrong decided answer among switch cases')
    for pop in POPULATIONS:
        nominal = [r for r in rows if r['population'] == pop and r['factor'] == 1 and 'probes' in r]
        switched = [r for r in nominal if r['probe_switch']]
        wrong = sum(r['same_ray'] not in ('UNKNOWN', r['truth']) and r['truth'] != 'UNKNOWN' for r in switched)
        print(pop, len(nominal), len(switched), sum(r['hidden_switch'] for r in nominal),
              sum(not r['bracket_holds'] for r in nominal), wrong)


if __name__ == '__main__':
    main()
