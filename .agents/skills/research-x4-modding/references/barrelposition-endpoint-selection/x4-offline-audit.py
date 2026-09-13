import sys,pickle,json,hashlib,collections,os
from pathlib import Path
root=Path(os.environ.get('X4_GC_ROOT', Path(__file__).resolve().parents[5]))
work=Path(os.environ.get('X4_RESEARCH_WORK', '/tmp'))
sys.path.insert(0,str(root/'scripts'))
from census_endpoint_paths import _derive_endpoint_authored_geometry
from census_source_semantics import _channel_records
from importlib.machinery import SourceFileLoader
official=SourceFileLoader('official',str(Path(__file__).with_name('x4-official.py'))).load_module()
x=pickle.load(open(work/'x4-captured.pkl','rb')); census=json.load(open(work/'x4-census.json'))
def h(s):
 a=0x811c9dc5
 for c in s.encode('ascii'): a=((a*0x1000193)&0xffffffffffffffff)^c
 return a
def digest(o):return hashlib.sha256(json.dumps(o,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def clean(o):
 if isinstance(o,dict):
  if 'candidate_numeric_value' in o:return o['candidate_numeric_value']
  return {k:clean(v) for k,v in o.items() if k not in ('evidence_classification','raw_text','type_token_raw_text','source_connection','restriction_index')}
 if isinstance(o,list):return [clean(v) for v in o]
 return o
rows=[];verified={};failures=[];fingerprints={}
for m in census['combat_conventional_turret_eligibility']['macro_classifications']:
 if m['eligibility']!='COMBAT_CANDIDATE':continue
 d=x['definitions'][m['component']][0]
 for source,path,cache in [(m['macro_source_set'],m['macro_source_file'],'official-source-sets'),(d['source_set'],d['source_file'],'official-source-sets'),(d.get('ani_source_set'),d.get('ani_resource'),'issue72-a2-ani-resources')]:
  if not path:continue
  key=(source,path)
  if key in verified:continue
  rel=path.replace('\\','/')
  if rel.lower().startswith('extensions/'+source.lower()+'/'):rel=rel[len('extensions/'+source+'/'):]
  try:
   data=official.read(source,rel)
   cached=root/'.x4-research-cache'/cache/source/rel
   if not cached.exists():
    matches=[p for p in (root/'.x4-research-cache'/cache/source).rglob('*') if str(p.relative_to(root/'.x4-research-cache'/cache/source)).lower()==rel.lower()];cached=matches[0] if matches else cached
   assert cached.read_bytes()==data, str(cached)
   verified[key]=hashlib.sha256(data).hexdigest()
  except Exception as e:failures.append([m['macro'],source,path,str(e)])
 endpoints=sorted(d['firing_endpoints'],key=lambda e:h(e['connection']))
 assert len(set(h(e['connection']) for e in endpoints))==len(endpoints)
 records=[]
 for e in endpoints:
  g,a=_derive_endpoint_authored_geometry(e,d['connections'],component=d['component'],source_set=d['source_set'],source_file=d['source_file']);assert not a
  ancestry={p:i for i,p in enumerate(e['source_part_path'])}
  graph=clean(g)
  for layer in graph['source_geometry_layers']:
   del layer['source_part'];del layer['owning_connection']
  graph.pop('endpoint_connection',None)
  animations=[]
  for ani in e['ani_descriptor_memberships']:
   animations.append({'edge':ani['endpoint_path_edge_index'],'state':ani['subname'],'counts':ani['channel_counts'],'duration':ani['descriptor_offset_148']['raw_bits'],'keys':[r['raw_bits'] for r in ani.get('_candidate_raw_key_records',[])]})
  connections={c['name']:c for c in d['connections']}
  attrs=[]
  for name in e['root_to_endpoint_connection_path']:
   a={k:v for k,v in connections[name]['authored_attributes'].items() if k not in ('name','parent')};a['tags']=sorted(a.get('tags','').split());attrs.append(a)
  selectors=[{'owner_edge':e['root_to_endpoint_connection_path'].index(a['connection']),'state':a['name'],'span':a['_authored_frame_span']} for a in d['authored_connection_animations'] if a['connection'] in e['root_to_endpoint_connection_path']]
  records.append({'selectors':selectors,'connection':e['connection'],'graph':graph,'attributes':attrs,'animations':animations})
 # Strict graph key retains endpoint names, state keys/metadata, all ancestry attributes. Not declared complete engine fingerprint.
 fp=digest(records);fingerprints.setdefault(fp,[]).append(m['macro'])
 active=[a for a in records[0]['animations'] if a['state'] in ('turret_active','turretloop_active')]
 semantic=next((r.get('semantic_case') for r in d.get('_source_semantic_resolutions',[]) if r['endpoint_connection']==endpoints[0]['connection']),None)
 rows.append({'macro':m['macro'],'component':m['component'],'endpoint':endpoints[0]['connection'],'lexical_index':sorted(e['connection'] for e in endpoints).index(endpoints[0]['connection'])+1,'endpoint_hash':hex(h(endpoints[0]['connection'])),'endpoints':[{ 'name':e['connection'],'hash':hex(h(e['connection']))} for e in endpoints],'endpoint_count':len(endpoints),'source_graph_fingerprint':fp,'semantic_case':semantic,'active_states':active,'selected_graph':records[0]})
result={'summary':{'macros':len(rows),'components':len(set(r['component'] for r in rows)),'endpoint_count':dict(collections.Counter(r['endpoint_count'] for r in rows)),'selected_lexical_index':dict(collections.Counter(r['lexical_index'] for r in rows)),'strict_graph_fingerprints':len(fingerprints),'semantic_cases':dict(collections.Counter(r['semantic_case'] for r in rows)),'verified_files':len(verified),'verification_failures':len(failures)},'failures':failures,'verified_files':[{'source':s,'path':p,'sha256':v} for (s,p),v in verified.items()],'fingerprints':fingerprints,'macros':rows}
json.dump(result,open(work/'x4-offline-audit.json','w'),indent=2)
print(json.dumps(result['summary'],indent=2));print('FAILURES',failures[:4]);print('SHARED', [v for v in fingerprints.values() if len(v)>1])
