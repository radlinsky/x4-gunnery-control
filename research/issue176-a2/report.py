"""Audit geometry buckets, angular model, and representative failures from saved trials."""
import gzip
import hashlib
import json
from collections import Counter

import numpy as np

from simulate import ROOT, OUT, EPS, consensus


def main():
    summary=json.loads((OUT/'summary.json').read_text())
    print('Samples:',summary['samples'])
    print('rule | ordinary pass | boundary pass | known172 pass | synthetic pass | false | fourth attempts/recovered/wrong')
    for rule in summary['rules']:
        counts=[summary['counts'][f'{rule}/1/{family}'] for family in summary['samples']]
        c=sum((Counter(c) for c in counts),Counter())
        print(rule, *[f"{v.get('pass',0)}/{v['total']}" for v in counts], c['false_consensus'],
              f"{c['fourth_attempt']}/{c['recovered']}/{c['recovered_wrong']}")
    measured=0.; same_wrong=0; max_ratio=0.; queries=0; n=0
    examples={}; patterns=Counter(); fourth=Counter()
    with gzip.open(OUT/'trials.jsonl.gz','rt') as stream:
        for line in stream:
            row=json.loads(line); r=row['result']; log=row['log']; n+=1; queries+=len(log)
            assert 3<=len(log)<=4
            if log[0][1] is not None:
                offsets=np.subtract([q[0] for q in log[1:3]],log[0][0])
                assert np.linalg.norm(np.cross(*offsets))>0
                rounding=4*np.finfo(np.float32).eps*max(1.,np.max(np.abs([q[0] for q in log])))
                assert max(abs(offsets @ log[0][1]))<=rounding
            for origin,direction,ident in log:
                if direction is None: continue
                delta=np.subtract(row['points'][ident],origin)
                truth=delta/np.linalg.norm(delta)
                measured=max(measured,float(np.linalg.norm(np.cross(truth,direction))))
            if r['status']=='pass' and len(set(r['selections']))==1:
                same_wrong+=r['wrong']; max_ratio=max(max_ratio,r['anchor_error']/r['error_bound'])
            if row['rule']=='medium' and row['rough_factor']==1:
                patterns[(row['family'],tuple(r['selections']))]+=1
                for bucket in ['primary='+r['status'], *r.get('flags',[])]:
                    key=(row['family'],bucket)
                    examples.setdefault(str(key),row)
                if r.get('false_consensus'): examples.setdefault('false_consensus',row)
                recovery=row['recovery']
                if recovery:
                    fourth[(row['family'],r['status'],recovery['status'],recovery.get('wrong',False))]+=1
    assert n==sum(summary['samples'].values())*len(summary['rules'])*3, n
    assert same_wrong==0, same_wrong
    assert measured<EPS,(measured,EPS)
    audit=dict(trials=n,queries=queries,max_direction_sine_error=measured,epsilon=EPS,
               same_selection_wrong=same_wrong,max_same_selection_error_bound_ratio=max_ratio,
               fourth={str(k):v for k,v in fourth.items()},
               selection_patterns={str(k):v for k,v in patterns.items()},
               input_sha256={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                   for p in [ROOT/'.x4-research-cache/issue167-p3c/corpus.pkl',
                             ROOT/'research/issue167-p3c/study.py']})
    (OUT/'audit.json').write_text(json.dumps(audit,indent=2))
    (OUT/'inspected.json').write_text(json.dumps(examples,indent=2))
    print(json.dumps(audit,indent=2))
    for key,row in examples.items():
        r=row['result']
        exact=[]
        for origin,direction,ident in row['log'][:3]:
            delta=np.subtract(row['points'][ident],origin)
            exact.append(delta/np.linalg.norm(delta) if np.linalg.norm(delta)>0 else None)
        control=consensus([q[0] for q in row['log'][:3]],exact)
        print('exact-direction control:',control['status'])
        print(key,row['id'],row['name'],row['rough'],r['selections'],r.get('flags'),
              'pairs:',[(p['s'],p['t'],p['sin'],p['miss'],p['miss_bound'],p['error_bound']) for p in r['pairs']])


if __name__=='__main__':
    main()
