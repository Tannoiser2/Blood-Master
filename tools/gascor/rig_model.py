import bpy, math, json
from mathutils import Vector, Quaternion
from pathlib import Path
root=Path(__file__).resolve().parents[2];out=root/'assets/models/gascor'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(out/'gascor-preview.glb'))
mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
bpy.context.view_layer.objects.active=mesh;mesh.select_set(True);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
# Coordinates in Blender: Z up, character faces -Y.
import bmesh
bm=bmesh.new();bm.from_mesh(mesh.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.00001);bm.to_mesh(mesh.data);bm.free()
bones={
 'root':((.1,.3,0),(.1,.3,.18),None),
 'pelvis':((.1,.3,.95),(.1,.3,1.18),'root'),
 'spine':((.1,.3,1.18),(.1,.3,1.48),'pelvis'),
 'chest':((.1,.3,1.48),(.1,.3,1.79),'spine'),
 'head':((.1,.3,1.79),(.1,.3,2.17),'chest'),
 'upper_arm.R':((-.23,.28,1.75),(-.34,.22,1.40),'chest'),
 'forearm.R':((-.34,.22,1.40),(-.40,.17,1.10),'upper_arm.R'),
 'hand.R':((-.40,.17,1.10),(-.43,.10,.99),'forearm.R'),
 'upper_arm.L':((.40,.38,1.75),(.50,.40,1.41),'chest'),
 'forearm.L':((.50,.40,1.41),(.48,.24,1.20),'upper_arm.L'),
 'hand.L':((.48,.24,1.20),(.48,.17,1.13),'forearm.L'),
 'thigh.R':((-.15,.27,1.02),(-.20,.22,.57),'pelvis'),
 'shin.R':((-.20,.22,.57),(-.27,.16,.15),'thigh.R'),
 'foot.R':((-.27,.16,.15),(-.27,-.02,.09),'shin.R'),
 'thigh.L':((.32,.43,1.02),(.35,.43,.57),'pelvis'),
 'shin.L':((.35,.43,.57),(.40,.40,.15),'thigh.L'),
 'foot.L':((.40,.40,.15),(.45,.20,.09),'shin.L')}

armdata=bpy.data.armatures.new('Gascor_Skeleton');arm=bpy.data.objects.new('Gascor_Rig',armdata);bpy.context.collection.objects.link(arm);bpy.context.view_layer.objects.active=arm;arm.select_set(True);mesh.select_set(False);bpy.ops.object.mode_set(mode='EDIT')
for name,(a,b,parent) in bones.items():
 bone=armdata.edit_bones.new(name);bone.head=a;bone.tail=b
 if parent:bone.parent=armdata.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT');arm.show_in_front=True
for name in bones:mesh.vertex_groups.new(name=name)
def dist(v,a,b):
 a,b=Vector(a),Vector(b);ab=b-a;return (v-(a+ab*max(0,min(1,(v-a).dot(ab)/ab.length_squared)))).length
for v in mesh.data.vertices:
 x,y,z=v.co
 # Keep weapons rigidly attached to hands; avoid heat weights spreading into torso.
 if (y<.07 and x<-.25 and z<1.22 and (z>.25 or x<-.50)) or (.94<z<1.18 and x<-.30 and y<.30):weights={'hand.R':1.0}
 elif x>.22 and y<.29 and .55<z<1.77:weights={'hand.L':1.0}
 else:
  names=[n for n in bones if n!='root']
  if z<1.23 and x>-.29:names=['pelvis','thigh.R','shin.R','foot.R','thigh.L','shin.L','foot.L']
  ranked=sorted([(dist(v.co,bones[n][0],bones[n][1]),n) for n in names])[:3]
  weights={n:math.exp(-d*35) for d,n in ranked};total=sum(weights.values());weights={n:w/total for n,w in weights.items()}

 for name,w in weights.items():mesh.vertex_groups[name].add([v.index],w,'REPLACE')
# Diffuse weights across the welded surface to remove abrupt skin boundaries.
import numpy as np
count=len(mesh.data.vertices);names=list(bones);weights=np.zeros((count,len(names)),dtype=np.float32)
for v in mesh.data.vertices:
 for g in v.groups:weights[v.index,g.group]=g.weight
edges=np.array([list(e.vertices) for e in mesh.data.edges]);a=edges[:,0];b=edges[:,1]
degree=np.bincount(np.concatenate([a,b]),minlength=count).astype(np.float32);degree[degree==0]=1
anchors=np.zeros(count,dtype=bool)
for v in mesh.data.vertices:
 x,y,z=v.co
 anchors[v.index]=(x<-.50 and z<.75) or (abs(x-.1)<.15 and z>1.25) or z>1.9
fixed=weights.copy()
for step in range(70):
 sums=np.zeros_like(weights);np.add.at(sums,a,weights[b]);np.add.at(sums,b,weights[a]);weights=.35*weights+.65*sums/degree[:,None];weights[anchors]=fixed[anchors]
for v in mesh.data.vertices:
 values=weights[v.index];ids=np.argsort(values)[-4:];total=sum(values[ids])
 for group in mesh.vertex_groups:group.remove([v.index])
 for i in ids:
  if values[i]>.00001:mesh.vertex_groups[int(i)].add([v.index],float(values[i]/total),'REPLACE')
mesh.parent=arm;mod=mesh.modifiers.new('Gascor skin','ARMATURE');mod.object=arm
arm.animation_data_create()
def pose(frame,rotations={},location=(0,0,0)):
 for p in arm.pose.bones:
  p.rotation_mode='QUATERNION';p.rotation_quaternion=Quaternion();p.location=(0,0,0)
 for name,(axis,deg) in rotations.items():
  p=arm.pose.bones[name];q=Quaternion(Vector(axis),math.radians(deg));basis=p.bone.matrix_local.to_quaternion();p.rotation_quaternion=basis.inverted()@q@basis
 arm.pose.bones['root'].location=location
 for p in arm.pose.bones:p.keyframe_insert('rotation_quaternion',frame=frame);p.keyframe_insert('location',frame=frame)
def action(name,frames,loop=False):
 a=bpy.data.actions.new(name);arm.animation_data.action=a
 for frame,rots,loc in frames:pose(frame,rots,loc)
 for fc in a.fcurves:
  for k in fc.keyframe_points:k.interpolation='BEZIER'
 track=arm.animation_data.nla_tracks.new();track.name=name;strip=track.strips.new(name,1,a);strip.action_frame_start=1;strip.action_frame_end=frames[-1][0];track.mute=True
 a.use_fake_user=True
 return a
X=(1,0,0);Y=(0,1,0);Z=(0,0,1)
action('Riposo',[(1,{},(0,0,0)),(30,{'chest':(X,-1),'head':(Z,1)},(0,0,.006)),(60,{},(0,0,0))],True)
walk=[]
for frame in [1,7,13,19,25,31,37,43,49]:
 t=(frame-1)/48*2*math.pi;s=math.sin(t)
 r={'thigh.R':(X,12*s),'thigh.L':(X,-12*s),'shin.R':(X,max(0,-s)*18),'shin.L':(X,max(0,s)*18),'upper_arm.R':(X,-20-4*s),'upper_arm.L':(X,-5+3*s)}
 walk.append((frame,r,(0,0,.012*abs(s))))
action('Camminata',walk,True)
action('Affondo',[(1,{},(0,0,0)),(12,{'upper_arm.R':(X,-20),'forearm.R':(X,-20),'chest':(Z,-5)},(0,0,0)),(20,{'upper_arm.R':(X,-35),'forearm.R':(X,-10),'chest':(X,8),'thigh.R':(X,-12)},(0,-.14,0)),(28,{'upper_arm.R':(X,-30),'forearm.R':(X,-12)},(0,-.10,0)),(48,{},(0,0,0))])
action('Parata',[(1,{},(0,0,0)),(12,{'upper_arm.L':(X,-15),'forearm.L':(Z,-12),'chest':(Z,-7),'upper_arm.R':(X,-15)},(0,0,0)),(26,{'upper_arm.L':(X,-15),'forearm.L':(Z,-12),'chest':(Z,-7),'upper_arm.R':(X,-15)},(0,0,0)),(42,{},(0,0,0))])
arm.animation_data.action=None
for p in arm.pose.bones:
 p.rotation_quaternion=Quaternion();p.location=(0,0,0)
bpy.context.scene.render.fps=24
bpy.ops.object.select_all(action='DESELECT');arm.select_set(True);mesh.select_set(True);bpy.context.view_layer.objects.active=arm
# Export one named animation per action.
bpy.ops.export_scene.gltf(filepath=str(out/'gascor-animated.glb'),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,export_frame_range=False)
bpy.ops.wm.save_as_mainfile(filepath=str(root/'source_art/gascor/gascor-rig.blend'))
print('RIG_READY',len(bones),'bones',list(bpy.data.actions.keys()),flush=True)
