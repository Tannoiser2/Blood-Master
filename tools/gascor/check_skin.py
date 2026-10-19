import bpy
from pathlib import Path
root=Path(__file__).resolve().parents[2];bpy.ops.wm.open_mainfile(filepath=str(root/'source_art/gascor/gascor-rig.blend'));o=next(o for o in bpy.context.scene.objects if o.type=='MESH');arm=o.parent;arm.animation_data.action=bpy.data.actions['Affondo'];bpy.context.scene.frame_set(20);dg=bpy.context.evaluated_depsgraph_get();ev=o.evaluated_get(dg);m=ev.to_mesh();bad=[]
for e in o.data.edges:
 a,b=e.vertices;before=(o.data.vertices[a].co-o.data.vertices[b].co).length;after=(m.vertices[a].co-m.vertices[b].co).length
 if after>.2 and after>before*4:bad.append((after-before,a,b))
for delta,a,b in sorted(bad,reverse=True)[:12]:
 print('STRETCH',round(delta,2),[(tuple(round(c,3) for c in o.data.vertices[i].co),[(o.vertex_groups[g.group].name,round(g.weight,2)) for g in o.data.vertices[i].groups]) for i in [a,b]])
print('BAD_EDGES',len(bad))
ev.to_mesh_clear()
