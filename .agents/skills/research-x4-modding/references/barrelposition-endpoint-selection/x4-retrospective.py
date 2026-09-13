import pickle,sys,json,re,math,statistics,hashlib,os
from pathlib import Path
root=Path(os.environ.get('X4_GC_ROOT', Path(__file__).resolve().parents[5]));sys.path.insert(0,str(root/'scripts'))
work=Path(os.environ.get('X4_RESEARCH_WORK', '/tmp'))
x=pickle.load(open(work/'x4-captured.pkl','rb'));audit=json.load(open(work/'x4-offline-audit.json'));by={r['macro']:r for r in audit['macros']}
def vec(o,field):
 default=(0,0,0) if field=='position' else (0,0,0,1)
 return [o.get(field,{}).get(k,{}).get('candidate_numeric_value',v) if o.get(field) else v for k,v in zip(list('xyz') if field=='position' else ['qx','qy','qz','qw'],default)]
def add(a,b):return [x+y for x,y in zip(a,b)]
def rot(q,v):
 x,y,z,w=q;vx,vy,vz=v;tx=2*(y*vz-z*vy);ty=2*(z*vx-x*vz);tz=2*(x*vy-y*vx)
 return [vx+w*tx+y*tz-z*ty,vy+w*ty+z*tx-x*tz,vz+w*tz+x*ty-y*tx]
def axis(i,a):
 q=[0,0,0,math.cos(a/2)];q[i]=math.sin(a/2);return q
def predict(m,e,yaw,pitch):
 d=x['definitions'][by[m]['component']][0];r=next(r for r in d['_source_semantic_resolutions'] if r['endpoint_connection']==e);g=r['applied_authored_geometry'];p=[0,0,0];qs=[]
 def trans(v):
  nonlocal p
  for q in reversed(qs):v=rot(q,v)
  p=add(p,v)
 for l in g['source_geometry_layers']:
  trans(vec(l['connection_authored_offset'],'position'))
  depth5=r['semantic_case']=='depth5_additive_x_rotation'
  if not depth5:
   trans(l.get('settled_local_position_delta',[0,0,0]))
   for a in l['authored_restrictions']:
    if a['type_token']=='rotation_y':qs.append(axis(1,yaw))
    if a['type_token']=='rotation_x':qs.append(axis(0,-pitch))
  qs.append(vec(l['connection_authored_offset'],'quaternion'));trans(vec(l['part_authored_offset'],'position'));qs.append(vec(l['part_authored_offset'],'quaternion'))
  if depth5:
   trans(l.get('settled_local_position_delta',[0,0,0]));v=l.get('settled_local_euler_xyz_delta_radians',[0,0,0]);assert v[1:]==[0,0];qs.append(axis(0,v[0]))
   for a in l['authored_restrictions']:
    if a['type_token']=='rotation_y':qs.append(axis(1,yaw))
    if a['type_token']=='rotation_x':qs.append(axis(0,-pitch))
 trans(vec(g['endpoint_authored_offset'],'position'));return p
if __name__=='__main__':
 groups={}
 for line in open(work/'x4-155-debug.log'):
  if '[X4GC TEST FIRED]' not in line:continue
  r=dict(re.findall(r'(\w+)=([^\s]+)',line));m=r['macro']
  if not m.startswith('turret_spl_m') or float(r['t'])<249104:continue
  endpoint=by[m]['endpoint'];plasma='plasma' in m;yaw=float(r['target_mount_yaw'] if plasma else r['bullet_yaw']);pitch=float(r['target_mount_pitch'] if plasma else r['bullet_pitch'])
  err=math.hypot(float(r['aim_error_yaw']),float(r['aim_error_pitch']))
  if plasma and err>.003:continue
  obs=[float(r['barrel_'+c]) for c in 'xyz'];direction=[math.sin(yaw)*math.cos(pitch),math.sin(pitch),math.cos(yaw)*math.cos(pitch)]
  errors=[]
  for e in by[m]['endpoints']:
   pred=predict(m,e['name'],yaw,pitch);delta=[a-b for a,b in zip(pred,obs)];proj=sum(a*b for a,b in zip(delta,direction));perp=math.sqrt(max(0,sum(a*a for a in delta)-proj*proj));errors.append({'connection':e['name'],'absolute':math.dist(pred,obs),'perpendicular':perp})
  groups.setdefault(m,[]).append({'t':float(r['t']),'mode':r['mode'],'errors':errors})
 json.dump(groups,open(work/'x4-retrospective.json','w'),indent=2)
 for m,rs in groups.items():
  print(m,len(rs),min(r['t'] for r in rs),max(r['t'] for r in rs))
  for e in rs[0]['errors']:
   vals=[next(q for q in r['errors'] if q['connection']==e['connection'])['perpendicular'] for r in rs]
   print(e['connection'],min(vals),statistics.median(vals),max(vals))
