"""Offline three-ray geometry experiment; never calls the P3c engagement scorer."""
import gzip
import itertools
import json
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'research/issue167-p3c'))
import study as old

OUT = ROOT / '.x4-research-cache/issue176-a2'
# Slope, minimum metres, maximum metres, angle AOB in degrees.
RULES = {'tiny': (.001, .01, 4, 90), 'small': (.01, .25, 32, 90),
         'medium': (.03, 1, 128, 90), 'wide': (.1, 4, 512, 90),
         'equilateral': (.03, 1, 128, 60), 'open': (.03, 1, 128, 120),
         'low_floor': (.03, .01, 128, 90), 'low_cap': (.03, 1, 32, 90)}
# q/2 in each of yaw/pitch plus binary32 subtraction/normalization allowance.
EPS = old.q / math.sqrt(2) + 8 * old.u
REL = .01  # Explicit experimental distance-resolution requirement, not engine truth.


def basis(d):
    e = np.eye(3)[np.argmin(np.abs(d))]
    a = np.cross(d, e)
    a /= np.linalg.norm(a)
    return a, np.cross(d, a)


def consensus(origins, directions):
    """Only observed origins/directions enter this production-style calculation."""
    result = {'status': 'invalid', 'pairs': []}
    if any(d is None for d in directions):
        return result
    o, d = np.asarray(origins), np.asarray(directions)
    if not np.isfinite(o).all() or not np.isfinite(d).all():
        return result
    flags = set()
    for i, j in itertools.combinations(range(3), 2):
        c = float(np.clip(d[i] @ d[j], -1, 1))
        k = float(np.linalg.norm(np.cross(d[i], d[j])))
        if k < 2 * EPS / REL:
            flags.add('conditioning')
        if k < 1e-10:
            continue
        w = o[i] - o[j]
        s = (c * (d[j] @ w) - d[i] @ w) / (k*k)
        t = ((d[j] @ w) - c * (d[i] @ w)) / (k*k)
        x, y = o[i] + s*d[i], o[j] + t*d[j]
        p = (x+y)/2
        # binary32 origin rounding plus angular uncertainty propagated by 1/sin(angle).
        rho = 2 * old.u * max(1., np.max(np.abs(o)), np.max(np.abs(p)))
        transverse = 2*rho + EPS*(abs(s)+abs(t))
        error = transverse/k
        miss = float(np.linalg.norm(x-y))
        if min(s,t) <= 0:
            flags.add('forward')
        if miss > transverse:
            flags.add('miss')
        if error > REL*max(abs(s),abs(t)):
            flags.add('conditioning')
        result['pairs'].append({'ij': [i,j], 's': float(s), 't': float(t),
                                'point': p.tolist(), 'error_bound': float(error),
                                'miss': miss, 'miss_bound': float(transverse), 'sin': k})
    pairs = result['pairs']
    if len(pairs) == 3:
        if any(np.linalg.norm(np.subtract(a['point'], b['point'])) > a['error_bound']+b['error_bound']
               for a,b in itertools.combinations(pairs,2)):
            flags.add('disagreement')
        best = min(pairs, key=lambda p:p['error_bound'])
        result.update(point=best['point'], error_bound=best['error_bound'])
        p = np.asarray(best['point'])
        for oi,di in zip(o,d):
            distance = float((p-oi) @ di)
            if distance <= 0:
                flags.add('forward')
            if np.linalg.norm(np.cross(p-oi,di)) > best['error_bound'] + EPS*abs(distance):
                flags.add('disagreement')
    else:
        flags.add('conditioning')
    if not all(math.isfinite(p[k]) for p in pairs for k in ('s','t','error_bound','miss')):
        flags.add('invalid')
    result['flags'] = sorted(flags)
    result['status'] = next((f for f in ('invalid','forward','conditioning','miss','disagreement') if f in flags), 'pass')
    return result


def corpus():
    old.init()
    records = old.CORPUS['records']
    assert len(records)==270 and len(old.CORPUS['pairs'])==38
    unique = {r['component']: r for r in records if len(r['points']) > 1}
    assert len(unique) == 15
    samples = []
    def add(family, name, origin, pts, rough, **meta):
        if family in ('ordinary', 'boundary'):
            rotation = len(samples) % 3
            theta = (0., .37, 1.13)[rotation]
            c, s = math.cos(theta), math.sin(theta)
            rx = np.array(((1,0,0),(0,c,-s),(0,s,c)))
            rz = np.array(((c,-s,0),(s,c,0),(0,0,1)))
            matrix = rx @ rz
            origin = old.F3(np.asarray(origin) @ matrix)
            pts = [old.F3(np.asarray(p) @ matrix) for p in pts]
            meta['rotation'] = rotation
        samples.append(dict(family=family, name=name, O=list(origin), points=pts, rough=rough,
                            kind='ship' if name.startswith('ship_') else 'surface', **meta))
    for name,r in sorted(unique.items()):
        pts = r['points']
        center = np.mean(pts,axis=0)
        for radius,direction in itertools.product((10,100,1000,10000,100000), old.fibonacci(24)):
            add('ordinary',name, old.F3(center+radius*np.asarray(direction)),pts,radius)
    # Frozen macro-weighted pairs retain all 38 original pair identities.
    for pi,(ri,a,b) in enumerate(old.CORPUS['pairs']):
        r=records[ri]
        mid,n,u,v=map(np.asarray,old.pair_frame(r,a,b))
        for radius,az,offset in itertools.product((10,100,1000,10000,100000),range(8),(-.01,0,.01)):
            direction=u*math.cos(az*math.pi/4)+v*math.sin(az*math.pi/4)+offset*n
            add('boundary',r['component'],old.F3(mid+radius*direction),r['points'],radius,pair=pi)
    cache=ROOT/'.x4-research-cache/issue172/cases.jsonl'
    cached={}
    if cache.exists():
        cases=[json.loads(line) for line in cache.read_text().splitlines()]
        cached={r['id']:r for r in cases}
        ids=list(cached)
    else:
        # Exact recovery from the frozen inputs; no replacement sampling.
        ids=[]
        for n in range(old.N_ORD+old.N_OFF):
            _,o,c,h,pts=old.trial(n)
            if old.approximate(o,c,h,pts)[0]=='NONFORWARD_OR_NONFINITE':
                ids.append(n)
    assert len(ids)==74 and sum(i<old.N_ORD for i in ids)==14
    for n in ids:
        meta,o,c,h,pts=old.trial(n)
        if n in cached:
            assert list(o)==cached[n]['O'] and meta['component']==cached[n]['component']
        assert old.approximate(o,c,h,pts)[0]=='NONFORWARD_OR_NONFINITE'
        add('known172',meta['component'],o,pts,meta['radius'],old_id=n,old_family=meta['family'])
    for distance,separation in ((.01,0),(1,0),(100,0),(1e7,0),(100,.001),(100,1000)):
        pts=[(0,0,distance)] if separation==0 else [(-separation/2,0,distance),(separation/2,0,distance)]
        add('synthetic',f'distance={distance}/separation={separation}',(0,0,0),pts,distance)
    for name in ('false_pair','false_triple','near_switch','at_point'):
        add('synthetic',name,(0,0,0),[(0,0,100)],100)
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'components.json').write_text(json.dumps({n:{'kind':'ship' if n.startswith('ship_') else 'surface',
        'aim_points':len(r['points'])} for n,r in unique.items()},indent=2))
    return samples


def run(sample, rule, rough_factor):
    slope,lower,upper,angle=RULES[rule]
    o=np.asarray(sample['O']); pts=sample['points']
    spacing=min(upper,max(lower,slope*sample['rough']*rough_factor))
    log=[]
    constructed = sample['family']=='synthetic' and sample['name'] in (
        'false_triple', 'false_pair', 'near_switch', 'at_point')
    d0=(0.,0.,1.) if constructed else old.Q(o,pts,log)
    if d0 is None:
        return {'status':'invalid','pairs':[]},log,None,pts
    a,b=basis(d0)
    av=spacing*a
    bv=spacing*(math.cos(math.radians(angle))*a+math.sin(math.radians(angle))*b)
    if constructed:
        # Contracting the probe triangle toward X makes each probe select its own
        # nearer point, yet all observed rays converge exactly at the false X.
        x=o+100*np.asarray(d0)
        if sample['name']=='false_triple':
            pts=[(o+x)/2,(o+av+x)/2,(o+bv+x)/2]
        elif sample['name']=='false_pair':
            pts=[(o+x)/2,(o+av+x)/2]
        elif sample['name']=='near_switch':
            pts=[x,x+.2*a]
        elif sample['name']=='at_point':
            pts=[o]
        old.Q(o,pts,log)
    for p in (o+av,o+bv):
        old.Q(p,pts,log)
    def check(indices):
        obs=[log[i] for i in indices]
        r=consensus([x[0] for x in obs],[x[1] for x in obs])
        r['selections']=[x[2] for x in obs]
        if r['status']=='pass':
            error=float(np.linalg.norm(np.asarray(r['point'])-pts[obs[0][2]]))
            r.update(anchor_error=error,wrong=error>r['error_bound'],
                     false_consensus=len(set(r['selections']))>1 and error>r['error_bound'])
        return r
    initial=check((0,1,2)); recovery=None
    if initial['status'] not in ('pass','invalid'):
        # One additional observation; two fixed anchored triples, no hidden truth routing.
        outward=initial.get('flags')==['conditioning']
        length=min(upper,spacing*4) if outward else max(lower,spacing/4)
        v=(a+b)/math.sqrt(2)
        old.Q(o+length*v,pts,log)
        alternatives=[check((0,1,3)),check((0,2,3))]
        recovery=next((r for r in alternatives if r['status']=='pass'),alternatives[0])
        recovery['outward']=outward
    return initial,log,recovery,pts


def main():
    samples=corpus(); counts=defaultdict(Counter); examples={}; errors=defaultdict(list)
    with gzip.open(OUT/'trials.jsonl.gz','wt') as stream:
        for rule in RULES:
            for factor in (.5,1,2):
                for sid,s in enumerate(samples):
                    r,log,recovery,pts=run(s,rule,factor)
                    row=dict(id=sid,rule=rule,rough_factor=factor,**s,result=r,log=log,recovery=recovery)
                    row['points'] = np.asarray(pts).tolist()
                    stream.write(json.dumps(row)+'\n')
                    keys=[f'{rule}/{factor}/{s["family"]}',f'{rule}/{factor}/{s["family"]}/{s["kind"]}',
                          f'{rule}/{factor}/{s["family"]}/distance={s["rough"]}']
                    for key in keys:
                        c=counts[key]; c['total']+=1; c[r['status']]+=1
                        pattern=''.join(str(r.get('selections',[]).index(i)) for i in r.get('selections',[]))
                        c['pattern='+pattern]+=1
                        c['queries']+=len(log)
                        c['false_consensus']+=r.get('false_consensus',False)
                        c['wrong']+=r.get('wrong',False)
                        for flag in r.get('flags',[]): c['flag='+flag]+=1
                        if r['status']=='pass': errors[key].append(r['anchor_error'])
                        if recovery:
                            c['fourth_attempt']+=1
                            c['recovered']+=recovery['status']=='pass'
                            c['recovered_wrong']+=recovery.get('wrong',False)
                            c['recovered_false']+=recovery.get('false_consensus',False)
                    bucket=(rule,s['family'],r['status'],r.get('false_consensus',False))
                    examples.setdefault(str(bucket),row)
            print(rule,'complete',flush=True)
    report={'samples':dict(Counter(s['family'] for s in samples)), 'rules':RULES,'epsilon':EPS,
            'counts':counts,'errors':{k:{'n':len(v),'median':float(np.median(v)), 'max':max(v)} for k,v in errors.items()}}
    (OUT/'summary.json').write_text(json.dumps(report,indent=2))
    (OUT/'examples.json').write_text(json.dumps(examples,indent=2))
    print(report['samples'])


if __name__=='__main__':
    main()
