import bpy
from pathlib import Path
root=Path(__file__).resolve().parents[2];bpy.ops.wm.open_mainfile(filepath=str(root/'source_art/gascor/gascor-rig.blend'));m=next(o for o in bpy.context.scene.objects if o.type=='MESH').data
for name,test in [('blade tip',lambda v:v.x<-.6 and v.z<.2),('blade mid',lambda v:v.x<-.47 and .5<v.z<.7),('hand R',lambda v:v.x<-.3 and 1.02<v.z<1.12),('shield',lambda v:v.x>.58 and .8<v.z<1.3),('head',lambda v:v.z>2),('body',lambda v:abs(v.x-.1)<.1 and 1.4<v.z<1.6)]:
 vs=[v.co for v in m.vertices if test(v.co)];print(name,tuple(round(sum(v[i] for v in vs)/len(vs),3) for i in range(3)),[[round(min(v[i] for v in vs),3),round(max(v[i] for v in vs),3)] for i in range(3)])
