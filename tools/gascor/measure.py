import bpy
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[2]
bpy.ops.wm.open_mainfile(filepath=str(root/'source_art/gascor/gascor-rig.blend'))
o=next(o for o in bpy.context.scene.objects if o.type=='MESH')
for z in [.1,.3,.6,.9,1.1,1.3,1.5,1.7,1.9,2.1]:
 vs=[v.co for v in o.data.vertices if abs(v.co.z-z)<.03]
 print('SLICE',z,[(round(x,2),len([v for v in vs if abs(v.x-x)<.05])) for x in [-.7,-.6,-.5,-.4,-.3,-.2,-.1,0,.1,.2,.3,.4,.5,.6,.7]])
