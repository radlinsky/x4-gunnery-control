from pathlib import Path
import hashlib,json,os
root=Path(os.environ['X4_ROOT'])
work=Path(os.environ.get('X4_RESEARCH_WORK', '/tmp'))
names=['base','ego_dlc_split','ego_dlc_terran','ego_dlc_pirate','ego_dlc_boron','ego_dlc_timelines','ego_dlc_mini_01','ego_dlc_mini_02']
index={}; cats=[]
for name in names:
 directory=root if name=='base' else root/'extensions'/name
 for cat in sorted(directory.glob('*.cat')):
  if '_sig' in cat.name:continue
  dat=cat.with_suffix('.dat');off=0;cats.append(str(cat))
  for line in cat.read_text().splitlines():
   path,size,ts,md5=line.rsplit(' ',3);size=int(size);index[(name,path.lower().replace('\\','/'))]=(str(dat),off,size,md5,path);off+=size
  assert off==dat.stat().st_size,(cat,off,dat.stat().st_size)
def read(name,path):
 dat,off,size,digest,real=index[(name,path.lower().replace('\\','/'))]
 with open(dat,'rb') as f:f.seek(off);data=f.read(size)
 assert hashlib.md5(data).hexdigest()==digest
 return data
if __name__=='__main__':
 out=work/'x4-official-scripts';count=0
 for (name,path),record in index.items():
  if (path.startswith(('aiscripts/','md/','libraries/','ui/')) and path.endswith(('.xml','.xsd','.lua'))) or path=='scriptproperties.xml':
   p=out/name/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(read(name,path));count+=1
 print('catalogs',len(cats),'entries',len(index),'script files',count)
 json.dump(cats,open(work/'x4-catalogs.json','w'))
