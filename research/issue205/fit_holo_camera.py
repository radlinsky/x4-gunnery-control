"""Fit X4's object-configuration holomap camera to Test Lab refine scans (issue #205).

Status: inference from one ship. Data: 2026-09-28 Test Lab hologram probe on the
Ray (ship_bor_l_destroyer_01_a_macro, MD $ship.size = 1096.25 m), log lines
`event=holo action=scan_hit` (mouse = slot centroid, -1..1, y up) with the
camera state from GetMapState and ship-local turret positions from MD
$turret.relativeposition.{$ship}.

Model (turretholo.lua projectTurret): camera at
  T + d*k * (-cos(p) sin(y), -sin(p), -cos(p) cos(y)),  looking at T, up = +Y,
  screen x = -(rel . right) / z / tan(fov/2) / aspect,  screen y = (rel . up) / z / tan(fov/2)
with y/p = HoloMapState.offset.yaw/pitch, d = cameradistance, aspect = render
target width / height (1.48 here). Fits T (orbit point), k (metres per distance
unit) and tan(fov/2); also tests k fixed to size/2 and length/2.

Run: python3 research/issue205/fit_holo_camera.py   (pure Python, < 1 min)
To add a ship: append its positions and scan_hit centroids below.
"""
import math

P = {1:(0,36.663,128.849),2:(-84.122,27.507,68.473),3:(-83.362,24.601,86.064),6:(66.666,-45.906,128.783),7:(66.361,-46.256,112.565),
     8:(84.122,27.507,68.473),9:(83.362,24.601,86.064),10:(0,-46.368,-71.036),11:(0,-44.628,-89.021),13:(0,45.916,-650.241),14:(0,44.438,-635.577)}
poses = [((-1.8084,-0.5687,1.1),{1:(0.1952,0.0302),2:(0.1062,0.1199),3:(0.1427,0.1073),6:(0.1762,-0.2156),7:(0.1394,-0.2045),8:(0.0758,-0.0717),9:(0.1107,-0.0881),10:(-0.0833,-0.0491),11:(-0.1195,-0.0519),13:(-0.7828,0.2284),14:(-0.7512,0.2167)}),
         ((3.0293,-0.4604,0.7),{1:(-0.0524,-0.1321),2:(0.2233,-0.0405),3:(0.2304,-0.0939),8:(-0.2542,-0.0017),9:(-0.2757,-0.0532),13:(0.0704,0.4758),14:(0.0656,0.4418)})]
ASPECT = 1.48
def proj(T,k,t,yaw,pitch,d,p):
    cp=math.cos(pitch); cam=(T[0]-cp*math.sin(yaw)*d*k, T[1]-math.sin(pitch)*d*k, T[2]-cp*math.cos(yaw)*d*k)
    f=[T[i]-cam[i] for i in range(3)]; fl=math.sqrt(sum(v*v for v in f)); f=[v/fl for v in f]
    r=[-f[2],0,f[0]]; rl=math.hypot(r[0],r[2]); r=[r[0]/rl,0,r[2]/rl]
    u=[r[1]*f[2]-r[2]*f[1], r[2]*f[0]-r[0]*f[2], r[0]*f[1]-r[1]*f[0]]
    rel=[p[i]-cam[i] for i in range(3)]; z=sum(rel[i]*f[i] for i in range(3))
    return -sum(rel[i]*r[i] for i in range(3))/z/t/ASPECT, sum(rel[i]*u[i] for i in range(3))/z/t
def cost(x,fixk=None):
    tx,ty,tz,k,t=x
    if fixk: k=fixk
    if k<=0 or t<=0.05: return 1e9
    e=0
    for (y,p,d),obs in poses:
        for s,(mx,my) in obs.items():
            px,py=proj((tx,ty,tz),k,t,y,p,d,P[s]); e+=(px-mx)**2+(py-my)**2
    return e
def nm(f,x0,steps,iters=4000):
    n=len(x0); pts=[x0]+[[x0[j]+(steps[j] if j==i else 0) for j in range(n)] for i in range(n)]; vals=[f(p) for p in pts]
    for _ in range(iters):
        o=sorted(range(n+1),key=lambda i:vals[i]); pts=[pts[i] for i in o]; vals=[vals[i] for i in o]
        c=[sum(p[j] for p in pts[:-1])/n for j in range(n)]
        xr=[c[j]+(c[j]-pts[-1][j]) for j in range(n)]; fr=f(xr)
        if fr<vals[0]:
            xe=[c[j]+2*(c[j]-pts[-1][j]) for j in range(n)]; fe=f(xe); pts[-1],vals[-1]=(xe,fe) if fe<fr else (xr,fr)
        elif fr<vals[-2]: pts[-1],vals[-1]=xr,fr
        else:
            xc=[c[j]+0.5*(pts[-1][j]-c[j]) for j in range(n)]; fc=f(xc)
            if fc<vals[-1]: pts[-1],vals[-1]=xc,fc
            else:
                for i in range(1,n+1): pts[i]=[pts[0][j]+0.5*(pts[i][j]-pts[0][j]) for j in range(n)]; vals[i]=f(pts[i])
    i=min(range(n+1),key=lambda i:vals[i]); return pts[i],vals[i]
N=sum(len(o) for _,o in poses)*2
for label,fixk in (("free k",None),("k=size/2=548.1",548.125),("k=length/2=532.3",532.31)):
    x,v=nm(lambda q:cost(q,fixk),[0,0,0,521.4,0.798],[5,5,5,30,0.05])
    k=fixk or x[3]
    print("%-18s rms %.4f  T=(%.1f,%.1f,%.1f) k=%.1f tanhalf=%.4f (vfov %.1f deg)"%(label,math.sqrt(v/N),x[0],x[1],x[2],k,x[4],2*math.degrees(math.atan(x[4]))))
