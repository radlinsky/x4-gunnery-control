import sys,os
from pathlib import Path
work=Path(os.environ.get('X4_RESEARCH_WORK', '/tmp'))
sys.path.insert(0,os.environ.get('X4_RE_TOOLS',str(work/'x4-re-tools')))
from x4pe import *
from capstone import *
import bisect
md=Cs(CS_ARCH_X86,CS_MODE_64)
pdata=next(s for s in sections if s[0]=='.pdata'); funcs=[]
for o in range(pdata[2],pdata[2]+pdata[3]-11,12):
 start,end,unwind=struct.unpack_from('<III',b,o)
 if start and end>start:funcs.append((base+start,base+end))
def bounds(a):
 i=bisect.bisect_right(funcs,(a,2**64))-1
 return funcs[i] if i>=0 and funcs[i][0]<=a<funcs[i][1] else (a,a+256)
def dis(a,end=None):
 start,end=bounds(a) if end is None else (a,end)
 for p,l,m,op in md.disasm_lite(b[offset(start):offset(end-1)+1],start): print(hex(p),m,op)
def rtti(name):
 o=b.index(name.encode()+b'\0')-16;va=addr(o);cols=[]
 for m in re.finditer(re.escape(struct.pack('<I',va-base)),b):
  j=m.start()-12
  if u32(j)==1 and u32(j+20)==addr(j)-base:cols.append((addr(j),u32(j+4)))
 for c,off in cols:
  for m in re.finditer(re.escape(struct.pack('<Q',c)),b):
   print(name,'COL',hex(c),'off',off,'vtable',hex(addr(m.start())+8))
if __name__=='__main__':
 if sys.argv[1]=='rtti':rtti(sys.argv[2])
 else:dis(int(sys.argv[1],16),int(sys.argv[2],16) if len(sys.argv)>2 else None)
