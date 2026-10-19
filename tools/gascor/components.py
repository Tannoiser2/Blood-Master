import bpy
from pathlib import Path
root=Path(__file__).resolve().parents[2];bpy.ops.wm.open_mainfile(filepath=str(root/'source_art/gascor/gascor-rig.blend'));m=next(o for o in bpy.context.scene.objects if o.type=='MESH').data
parent=list(range(len(m.vertices)))
def find(i):
 while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
 return i
for e in m.edges:
 a,b=map(find,e.vertices);parent[a]=b
parts={}
for v in m.vertices:parts.setdefault(find(v.index),[]).append(v.co)
for vs in sorted(parts.values(),key=len,reverse=True)[:15]:print('PART',len(vs),[tuple(round(f,3) for f in (min(v[i] for v in vs),max(v[i] for v in vs))) for i in range(3)])
