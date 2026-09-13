from pathlib import Path
import struct,re,hashlib,subprocess,os
p=Path(os.environ['X4_EXE']); b=p.read_bytes()
u16=lambda o:struct.unpack_from('<H',b,o)[0]
u32=lambda o:struct.unpack_from('<I',b,o)[0]
u64=lambda o:struct.unpack_from('<Q',b,o)[0]
pe=u32(60); opt=pe+24; base=u64(opt+24); sections=[]
for i in range(u16(pe+6)):
 o=opt+u16(pe+20)+40*i; name=b[o:o+8].split(b'\0')[0].decode(); vs,va,sz,raw=struct.unpack_from('<IIII',b,o+8); sections.append((name,base+va,raw,sz))
def addr(off):
 for n,v,r,s in sections:
  if r<=off<r+s:return v+off-r
def offset(a):
 for n,v,r,s in sections:
  if v<=a<v+s:return r+a-v

def refs(a):
 out=[]
 for n,v,r,s in sections:
  if n!='.text':continue
  for m in re.finditer(rb'[\x48-\x4f][\x8d\x8b][\x05\x0d\x15\x1d\x25\x2d\x35\x3d]',b[r:r+s]):
   o=r+m.start(); target=addr(o)+7+struct.unpack_from('<i',b,o+3)[0]
   if target==a:out.append(addr(o))
 return out
if __name__=='__main__':
 print('SHA256',hashlib.sha256(b).hexdigest(),'base',hex(base),'sections',sections)
 for term in [b'barrelposition\0',b'barrelamount\0',b'turret_active\0',b'laser\0']:
  for m in re.finditer(re.escape(term),b):
   a=addr(m.start()); print(term,hex(a),[hex(x) for x in refs(a)])
