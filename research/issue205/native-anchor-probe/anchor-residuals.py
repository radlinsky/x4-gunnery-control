# Engine anchor NDC (pivot x captured view-projection) vs the probe projectTurret model.
# Run: python3 research/issue205/native-anchor-probe/anchor-residuals.py debug.log
import json, math, sys
def model(p, st, radius, aspect, tanhalf):
    yaw, pitch, d = st[3], st[4], st[6] * radius
    cp = math.cos(pitch)
    cam = (-cp*math.sin(yaw)*d, -math.sin(pitch)*d, -cp*math.cos(yaw)*d)
    fl = math.sqrt(sum(c*c for c in cam)); f = [-c/fl for c in cam]
    r = [-f[2], 0, f[0]]; rl = math.hypot(r[0], r[2]); r = [r[0]/rl, 0, r[2]/rl]
    u = [r[1]*f[2]-r[2]*f[1], r[2]*f[0]-r[0]*f[2], r[0]*f[1]-r[1]*f[0]]
    rel = [p[i]-cam[i] for i in range(3)]
    z = sum(rel[i]*f[i] for i in range(3))
    return (-(rel[0]*r[0]+rel[2]*r[2])/z/tanhalf/aspect, sum(rel[i]*u[i] for i in range(3))/z/tanhalf)
def engine(p, vp):
    v = [p[0], p[1], p[2], 1.0]
    c = [sum(v[i]*vp[4*i+j] for i in range(4)) for j in range(4)]
    return c[0]/c[3], c[1]/c[3]
rows = []
for line in open(sys.argv[1], errors='replace'):
    if 'ANCHOR_RECORD' not in line: continue
    j = json.loads(line[line.index('{'):]); n = j['native']
    if not j['valid']: continue
    w, h = j['widget_before']['width'], j['widget_before']['height']
    piv, st = n['slot_pivot'], j['before']
    md = next(q for q in j['positions'] if q['slot'] == j['slot'])
    ex, ey = engine(piv, n['view_projection'])
    out = {'req': j['request'], 'ship': j['macro'][9:13], 'slot': j['slot'], 'd': st[6], 'engine': (ex, ey)}
    for name, pos, rad, t in (('fixed', piv, n['radius'][0], .75), ('fixed_mdint', md['position'], md['radius'], .75), ('current', piv, n['radius'][0], .7716)):
        mx, my = model(pos, st, rad, w / h, t)
        out[name] = (mx-ex, my-ey, (mx-ex)*w/2, (my-ey)*h/2)
    rows.append(out)
for name in ('fixed', 'fixed_mdint', 'current'):
    print(f"\n{name}: model - engine (NDC dx, dy | px dx, dy)")
    for o in rows:
        dx, dy, px, py = o[name]
        print(f"  {o['ship']} slot {o['slot']:>2} d={o['d']:.4f} engine=({o['engine'][0]:+.4f},{o['engine'][1]:+.4f})  {dx:+.6f} {dy:+.6f} | {px:+7.2f} {py:+7.2f}")
    print(f"  max |NDC|: x {max(abs(o[name][0]) for o in rows):.6f}  y {max(abs(o[name][1]) for o in rows):.6f}")
