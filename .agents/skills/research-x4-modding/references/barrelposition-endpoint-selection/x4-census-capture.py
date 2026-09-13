import sys,pickle,json,copy,os
from pathlib import Path
root=Path(os.environ.get('X4_GC_ROOT', Path(__file__).resolve().parents[5]));sys.path.insert(0,str(root/'scripts'))
work=Path(os.environ.get('X4_RESEARCH_WORK', '/tmp'))
import census_pipeline
source=root/'.x4-research-cache/official-source-sets';resource=root/'.x4-research-cache/issue72-a2-ani-resources'
names=[p.name for p in source.iterdir() if p.is_dir()]
captured={}; original=census_pipeline._assemble_census_report
def capture(*args,**kw):
 captured['definitions']=copy.deepcopy(args[0]);captured['records']=copy.deepcopy(args[1])
 return original(*args,**kw)
census_pipeline._assemble_census_report=capture
report=census_pipeline.build_census({n:source/n for n in names},{n:resource/n for n in names},include_source_semantic_resolutions=True)
pickle.dump(captured,open(work/'x4-captured.pkl','wb'));json.dump(report,open(work/'x4-census.json','w'))
print('keys',list(report),'captured',len(captured['records']))
print('record',captured['records'][0])
