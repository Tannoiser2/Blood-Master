import bpy, math, json
from mathutils import Vector
from pathlib import Path
root=Path(__file__).resolve().parents[2]
out=root/'assets/models/gascor'; out.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(root/'source_art/gascor/gascor-meshy-original.glb'))
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
pts=[o.matrix_world@Vector(p) for o in meshes for p in o.bound_box]
lo=Vector([min(p[i] for p in pts) for i in range(3)]);hi=Vector([max(p[i] for p in pts) for i in range(3)])
scale=2.2/(hi.z-lo.z);center=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
for o in meshes:
 bpy.context.view_layer.objects.active=o
 # bake all import transforms into geometry, then normalize origin/height
 matrix=o.matrix_world.copy()
 for v in o.data.vertices:v.co=(matrix@v.co-center)*scale
 o.matrix_world.identity()
 before=len(o.data.polygons)
 mod=o.modifiers.new('Game ready reduction','DECIMATE');mod.ratio=min(1,80000/before);mod.use_collapse_triangulate=True
 bpy.ops.object.modifier_apply(modifier=mod.name)
 for poly in o.data.polygons:poly.use_smooth=True
 o.name='Gascor_Meshy'
 print('GEOMETRY',before,'->',len(o.data.polygons),flush=True)
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:o.select_set(True)
bpy.context.view_layer.objects.active=meshes[0]
bpy.ops.export_scene.gltf(filepath=str(out/'gascor-preview.glb'),export_format='GLB',use_selection=True,export_yup=True)
# Studio presentation saved as editable Blender source.
def mat(name,color,metal=0,rough=.5):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough;return m
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.095));bpy.context.object.data.materials.append(mat('Studio charcoal',(.025,.035,.045),0,.6))
world=bpy.data.worlds.new('Studio');bpy.context.scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.15,.2,.25,1);world.node_tree.nodes['Background'].inputs[1].default_value=.35
for name,pos,power,color,size in [('Key',(-3,-4,5),550,(1,.88,.69),4),('Fill',(4,-2,3),380,(.65,.85,1),3),('Rim',(0,3,4),700,(1,.75,.4),3)]:
 data=bpy.data.lights.new(name,'AREA');data.energy=power;data.color=color;data.shape='DISK';data.size=size;o=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(o);o.location=pos;o.rotation_euler=(Vector((0,0,1))-o.location).to_track_quat('-Z','Y').to_euler()
data=bpy.data.cameras.new('Presentation');cam=bpy.data.objects.new('Presentation',data);bpy.context.collection.objects.link(cam);bpy.context.scene.camera=cam;cam.location=(3,-6,3.1);cam.rotation_euler=(Vector((0,0,1.05))-cam.location).to_track_quat('-Z','Y').to_euler();data.type='ORTHO';data.ortho_scale=3.25
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True;scene.render.resolution_x=1200;scene.render.resolution_y=1200;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX'
bpy.ops.wm.save_as_mainfile(filepath=str(root/'source_art/gascor/gascor-studio.blend'))
scene.render.filepath=str(out/'gascor-3d-front.png');bpy.ops.render.render(write_still=True)
cam.location=(-3,6,3.1);cam.rotation_euler=(Vector((0,0,1.05))-cam.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(out/'gascor-3d-back.png');bpy.ops.render.render(write_still=True)
print('GASCOR_READY',flush=True)
