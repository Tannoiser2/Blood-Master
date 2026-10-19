import bpy, json, sys
from mathutils import Vector
from pathlib import Path
args=sys.argv[sys.argv.index('--')+1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=args[0])
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
points=[o.matrix_world@Vector(p) for o in meshes for p in o.bound_box]
print('MODEL_REPORT',json.dumps({'meshes':[{'name':o.name,'vertices':len(o.data.vertices),'faces':len(o.data.polygons),'materials':[m.name if m else None for m in o.data.materials]} for o in meshes],'bounds':[[min(p[i] for p in points),max(p[i] for p in points)] for i in range(3)],'armatures':[o.name for o in bpy.context.scene.objects if o.type=='ARMATURE'],'actions':[a.name for a in bpy.data.actions]}))
