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
# ---------------------------------------------------------------------------
# Pesi della pelle: assegnazione per vicinanza agli ossi, poi diffusione sulla
# superficie saldata. Sopra la vita non si scelgono mai gli ossi delle gambe.
# Spada, scudo e pugni restano rigidi sulle mani (maschere geometriche).
# ---------------------------------------------------------------------------
import numpy as np
LEGBONES=('thigh.R','shin.R','foot.R','thigh.L','shin.L','foot.L')
def dist(v,a,b):
 a,b=Vector(a),Vector(b);ab=b-a;return (v-(a+ab*max(0,min(1,(v-a).dot(ab)/ab.length_squared)))).length
for v in mesh.data.vertices:
 x,y,z=v.co
 names=[n for n in bones if n!='root']
 if z<1.23 and x>-.29:names=['pelvis',*LEGBONES]
 elif z>=1.12:names=[n for n in names if n not in LEGBONES]
 ranked=sorted([(dist(v.co,bones[n][0],bones[n][1]),n) for n in names])[:3]
 weights={n:math.exp(-d*35) for d,n in ranked};total=sum(weights.values())
 for name,w in weights.items():mesh.vertex_groups[name].add([v.index],w/total,'REPLACE')
count=len(mesh.data.vertices);names=list(bones);weights=np.zeros((count,len(names)),dtype=np.float32)
for v in mesh.data.vertices:
 for g in v.groups:weights[v.index,g.group]=g.weight
edges=np.array([list(e.vertices) for e in mesh.data.edges]);a=edges[:,0];b=edges[:,1]
degree=np.bincount(np.concatenate([a,b]),minlength=count).astype(np.float32);degree[degree==0]=1
anchors=np.zeros(count,dtype=bool)
for v in mesh.data.vertices:
 x,y,z=v.co
 anchors[v.index]=(abs(x-.1)<.15 and z>1.25) or z>1.9
fixed=weights.copy()
def seg_dist(p,a,b):
 a,b=Vector(a),Vector(b);ab=b-a;t=max(0,min(1,(p-a).dot(ab)/ab.length_squared));return (p-(a+ab*t)).length,t
def smooth(e0,e1,x):x=max(0,min(1,(x-e0)/(e1-e0)));return x*x*(3-2*x)
iL=names.index('hand.L');iR=names.index('hand.R');iP=names.index('pelvis');iTR=names.index('thigh.R');iTL=names.index('thigh.L')
SH_A=Vector((.29,-.01,0));SH_B=Vector((.74,.23,0));SH_N=Vector((-(SH_B-SH_A).y,(SH_B-SH_A).x,0)).normalized()
SW_T=Vector((-.744,-.673,.111));SW_G=Vector((-.43,.10,.99))
weapon=np.zeros(count,dtype=bool)
for v in mesh.data.vertices:
 p=v.co;flat=Vector((p.x,p.y,0))
 s=(flat-SH_A).dot(SH_N);t=(flat-SH_A).dot((SH_B-SH_A).normalized())/(SH_B-SH_A).length
 if (-.09<s<.035 and -.05<t<1.05 and .3<p.z<1.78) or (p.x>.44 and seg_dist(p,bones['hand.L'][0],bones['hand.L'][1])[0]<.10):
  fixed[v.index]=0;fixed[v.index,iL]=1;weapon[v.index]=True;continue
 # lama, guardia (fetta perpendicolare alla lama), pomolo, sfera della guardia, pugno destro
 d,t=seg_dist(p,SW_T,SW_G)
 if d<.09 or (.89<t<.965 and d<.19) or (p-Vector((-.295,.235,1.13))).length<.055 or (p-Vector((-.303,.074,.915))).length<.05 or (p.x<-.34 and seg_dist(p,bones['hand.R'][0],bones['hand.R'][1])[0]<.10):
  fixed[v.index]=0;fixed[v.index,iR]=1;weapon[v.index]=True
anchors|=weapon;weights[weapon]=fixed[weapon]
for step in range(70):
 sums=np.zeros_like(weights);np.add.at(sums,a,weights[b]);np.add.at(sums,b,weights[a]);weights=.35*weights+.65*sums/degree[:,None];weights[anchors]=fixed[anchors]
# Tunica/falde: anello che avvolge entrambe le cosce. Segue soprattutto il bacino
# (in basso un po' le cosce), così negli affondi non si strappa all'indietro.
for v in mesh.data.vertices:
 if weapon[v.index]:continue
 p=v.co
 dR,_=seg_dist(p,bones['thigh.R'][0],bones['thigh.R'][1]);dL,_=seg_dist(p,bones['thigh.L'][0],bones['thigh.L'][1])
 side=1-smooth(.5,.6,abs(p.x-.1))
 s=smooth(.085,.15,min(dR,dL))*smooth(.58,.70,p.z)*(1-smooth(1.0,1.12,p.z))*side
 # fascia dell'anca: anche vicino alla coscia la tunica segue soprattutto il bacino
 s=max(s,.75*smooth(.84,.94,p.z)*(1-smooth(1.08,1.16,p.z))*side*smooth(.05,.09,min(dR,dL)))
 if s<=0:continue
 share=.28*(1-smooth(.62,1.0,p.z));wR=1/(dR*dR+1e-4);wL=1/(dL*dL+1e-4)
 skirt=np.zeros(len(names),dtype=np.float32);skirt[iP]=1-share;skirt[iTR]=share*wR/(wR+wL);skirt[iTL]=share*wL/(wR+wL)
 weights[v.index]=(1-s)*weights[v.index]+s*skirt
for v in mesh.data.vertices:
 values=weights[v.index];ids=np.argsort(values)[-4:];total=sum(values[ids])
 for group in mesh.vertex_groups:group.remove([v.index])
 for i in ids:
  if values[i]>.00001:mesh.vertex_groups[int(i)].add([v.index],float(values[i]/total),'REPLACE')
mesh.parent=arm;mod=mesh.modifiers.new('Gascor skin','ARMATURE');mod.object=arm
arm.animation_data_create()
# ---------------------------------------------------------------------------
# Animazioni procedurali (v2): IK a due ossa per gambe e braccia, piedi
# piantati a terra, peso del corpo su bacino/busto, anticipazione e rinculo.
# Assi (spazio armatura = mondo): X = sinistra del personaggio, -Y = avanti, Z = su.
#   rotazione +X = inclinarsi in avanti, +Z = spalla destra avanti, +Y = rollio verso sinistra.
# ---------------------------------------------------------------------------
from mathutils import Matrix, Euler
P=arm.pose.bones
REST={n:arm.data.bones[n].matrix_local.copy() for n in bones}
def V(t):return Vector(t)
HEAD={n:V(bones[n][0]) for n in bones};TAIL={n:V(bones[n][1]) for n in bones}
GRIP=TAIL['hand.R'];TIP=min((v.co.copy() for v in mesh.data.vertices),key=lambda c:c.x)
BLADE=(TIP-GRIP).normalized()
ANKLE={'R':TAIL['shin.R'].copy(),'L':TAIL['shin.L'].copy()}
SHOULDER={'R':HEAD['upper_arm.R'],'L':HEAD['upper_arm.L']}
WRIST={'R':TAIL['forearm.R'],'L':TAIL['forearm.L']}
REL={s:WRIST[s]-SHOULDER[s] for s in 'RL'}
def upd():bpy.context.view_layer.update()
def eul(x=0,y=0,z=0):return Euler((math.radians(x),math.radians(y),math.radians(z)),'XYZ').to_quaternion()
def setrot(name,q):
 upd();p=P[name];h=p.head.copy();p.matrix=Matrix.Translation(h)@q.to_matrix().to_4x4()
def turn(name,q):
 upd();setrot(name,q@P[name].matrix.to_quaternion())
def orient(name,q):setrot(name,q@REST[name].to_quaternion())
def aim(name,point):
 upd();p=P[name];h=p.head.copy();q=(p.tail-p.head).rotation_difference(point-h);setrot(name,q@p.matrix.to_quaternion())
def pole_of(up,lo):
 S,E,T=HEAD[up],HEAD[lo],TAIL[lo];u=(T-S).normalized();v=E-S;v=v-u*v.dot(u);return v.normalized() if v.length>1e-4 else V((0,-1,0))
POLE={'leg.R':pole_of('thigh.R','shin.R'),'leg.L':pole_of('thigh.L','shin.L'),'arm.R':pole_of('upper_arm.R','forearm.R'),'arm.L':pole_of('upper_arm.L','forearm.L')}
def ik(up,lo,target,pole):
 upd();S=P[up].head.copy();a=(TAIL[up]-HEAD[up]).length;b=(TAIL[lo]-HEAD[lo]).length
 T=V(target);d=T-S;dist=max(abs(a-b)+1e-3,min(d.length,(a+b)*.998));u=d.normalized()
 c=max(-1,min(1,(a*a+dist*dist-b*b)/(2*a*dist)));s=math.sqrt(1-c*c)
 pv=V(pole).normalized();v=pv-u*pv.dot(u);v=v.normalized() if v.length>1e-4 else V((0,-1,0))
 aim(up,S+a*(c*u+s*v));aim(lo,S+u*dist)
def ease(x):x=max(0,min(1,x));return x*x*(3-2*x)
def kf(t,keys):
 """Interpola valori (numeri o tuple) tra pose chiave con ease in/out."""
 if t<=keys[0][0]:return keys[0][1]
 for (f0,a),(f1,b) in zip(keys,keys[1:]):
  if t<=f1:
   w=ease((t-f0)/(f1-f0))
   if isinstance(a,tuple):return tuple(x+(y-x)*w for x,y in zip(a,b))
   return a+(b-a)*w
 return keys[-1][1]
def arc(t,f0,f1,h):
 return h*math.sin(math.pi*max(0,min(1,(t-f0)/(f1-f0))))
def pose(root=(0,0,0),pelvis=(0,0,0),spine=(0,0,0),chest=(0,0,0),head=(0,0,0),
         ankles=None,foot={'R':0,'L':0},hands=None,arms_fk=None,
         hand_aim={'R':None,'L':None},hand_rot={'R':(0,0,0),'L':(0,0,0)},poles={}):
 for p in P:p.rotation_mode='QUATERNION';p.rotation_quaternion=Quaternion();p.location=(0,0,0)
 m=REST['root'].copy();m.translation=m.translation+V(root);P['root'].matrix=m
 turn('pelvis',eul(*pelvis));turn('spine',eul(*spine));turn('chest',eul(*chest))
 orient('head',eul(*head))
 for s in 'RL':
  if hands and hands.get(s) is not None:
   upd();ik('upper_arm.'+s,'forearm.'+s,P['upper_arm.'+s].head+V(hands[s]),poles.get('arm.'+s,POLE['arm.'+s]))
  elif arms_fk and s in arms_fk:
   up,fo=arms_fk[s];turn('upper_arm.'+s,eul(up,0,0));turn('forearm.'+s,eul(fo,0,0))
  upd();follow=P['hand.'+s].matrix.to_quaternion()
  if hand_aim.get(s) is not None:
   direction,w=hand_aim[s];target=BLADE.rotation_difference(V(direction).normalized())@REST['hand.R'].to_quaternion() if s=='R' else eul(*direction)@REST['hand.L'].to_quaternion()
   setrot('hand.'+s,follow.slerp(target,w))
  turn('hand.'+s,eul(*hand_rot[s]))
 ank=ankles or {}
 for s in 'RL':
  t=V(ank.get(s,ANKLE[s]));ik('thigh.'+s,'shin.'+s,t,poles.get('leg.'+s,POLE['leg.'+s]))
  orient('foot.'+s,eul(foot.get(s,0),0,0))
 upd()
_last={}
def key(frame):
 for p in P:
  q=p.rotation_quaternion.copy();prev=_last.get(p.name)
  if prev is not None and prev.dot(q)<0:q.negate();p.rotation_quaternion=q
  _last[p.name]=q.copy()
  p.keyframe_insert('rotation_quaternion',frame=frame);p.keyframe_insert('location',frame=frame)
def action(name,length,fn):
 _last.clear();a=bpy.data.actions.new(name);a.use_fake_user=True;arm.animation_data.action=a
 for f in range(1,length+1):fn(f);key(f)
 return a
def ankle(s,dx=0,dy=0,dz=0):return tuple(ANKLE[s]+V((dx,dy,dz)))

# --- RIPOSO: respiro, oscillazione del peso, spada che "vive" in mano -------
def idle(f):
 t=(f-1)/60*2*math.pi
 pose(root=(.012*math.sin(t),0,-.025+.008*math.sin(2*t)),pelvis=(0,1.5*math.sin(t),0),
      spine=(1+1.2*math.sin(2*t),0,0),chest=(1.5*math.sin(2*t+.6),-1.5*math.sin(t),2*math.sin(t)),
      head=(-2+1.5*math.sin(2*t+1),0,3*math.sin(t*.5)),
      arms_fk={'R':(-4+3*math.sin(2*t+.8),-6+4*math.sin(2*t+1.2)),'L':(-2+2*math.sin(2*t+.4),-4)})
action('Riposo',60,idle)

# --- CAMMINATA: ciclo sul posto, piedi che scorrono a terra -----------------
WALK=32;STRIDE=.26;LIFT=.13
def foot_cycle(p):
 """p in [0,1): 0 = contatto di tallone davanti; 0..0.55 appoggio; 0.55..1 volo."""
 if p<.55:
  w=p/.55;y=-STRIDE+2*STRIDE*w;z=0
  pitch=kf(w,[(0,-18),(.18,0),(.75,0),(1,28)])
  z=kf(w,[(0,.02),(.18,0),(.75,0),(1,.09)])
 else:
  w=(p-.55)/.45;y=STRIDE-2*STRIDE*ease(w);z=LIFT*math.sin(math.pi*w)**1.3+kf(w,[(0,.09),(.3,.04),(1,.02)])
  pitch=kf(w,[(0,28),(.35,-8),(.85,-18),(1,-18)])
 return y,z,pitch
def walk(f):
 p=(f-1)/WALK;t=p*2*math.pi
 yR,zR,pR=foot_cycle(p%1);yL,zL,pL=foot_cycle((p+.5)%1)
 c=(ANKLE['R'].y+ANKLE['L'].y)/2
 ank={'R':(ANKLE['R'].x+.06,c+yR,ANKLE['R'].z+zR),'L':(ANKLE['L'].x-.08,c+yL,ANKLE['L'].z+zL)}
 bob=-.045-.026*math.cos(2*t)            # più basso al contatto, più alto a metà appoggio
 sway=-.03*math.cos(t)                  # il peso passa sulla gamba d'appoggio
 pose(root=(sway,-.02,bob),
      pelvis=(4,4*math.cos(t),9*math.cos(t)),
      spine=(4,-2*math.cos(t),-6*math.cos(t)),
      chest=(3+1.5*math.cos(2*t),-2*math.cos(t),-9*math.cos(t)),
      head=(-3+1.5*math.cos(2*t),0,0),
      ankles=ank,foot={'R':pR,'L':pL},
      arms_fk={'R':(-6+12*math.cos(t),-14-6*max(0,math.cos(t))),'L':(-6-14*math.cos(t),-14-6*max(0,-math.cos(t)))})
action('Camminata',WALK,walk)

# --- AFFONDO: carica indietro, slancio con gamba destra, lama tesa, rientro --
REST_R=tuple(REL['R']);REST_L=tuple(REL['L'])
def thrust(f):
 root=kf(f,[(1,(0,0,-.02)),(9,(.03,.07,-.09)),(15,(-.03,-.40,-.17)),(19,(-.03,-.44,-.18)),(28,(-.03,-.42,-.17)),(38,(0,-.05,-.05)),(46,(0,0,-.02))])
 pelvis=kf(f,[(1,(0,0,0)),(9,(-4,0,-18)),(15,(10,0,16)),(19,(12,0,18)),(28,(10,0,16)),(38,(2,0,-2)),(46,(0,0,0))])
 chest=kf(f,[(1,(0,0,0)),(9,(-6,3,-24)),(15,(12,-4,26)),(19,(14,-4,28)),(28,(12,-4,25)),(38,(1,0,0)),(46,(0,0,0))])
 hR=kf(f,[(1,REST_R),(9,(-.06,.22,-.44)),(15,(.12,-.60,-.10)),(19,(.12,-.64,-.08)),(28,(.12,-.60,-.10)),(38,(-.12,-.20,-.55)),(46,REST_R)])
 aimw=kf(f,[(1,0),(7,.85),(15,1),(28,1),(40,0),(46,0)])
 blade=kf(f,[(1,(0,-1,.25)),(9,(.25,-1,.30)),(15,(.04,-1,-.03)),(28,(.04,-1,-.03)),(46,(0,-1,.1))])
 hL=kf(f,[(1,REST_L),(9,(-.10,-.32,-.40)),(15,(.20,.28,-.44)),(19,(.22,.30,-.44)),(28,(.20,.26,-.45)),(38,(.04,-.08,-.55)),(46,REST_L)])
 yR=kf(f,[(1,0),(9,.02),(15,-.80),(28,-.80),(38,-.05),(46,0)])
 zR=arc(f,9,15,.16)+arc(f,29,38,.10)
 footR=kf(f,[(1,0),(9,5),(13,-20),(15,-14),(18,0),(29,0),(33,8),(38,-6),(46,0)])
 footL=kf(f,[(1,0),(13,0),(15,22),(28,22),(36,0)])
 zL=kf(f,[(1,0),(13,0),(15,.07),(28,.07),(36,0)])
 pose(root=root,pelvis=pelvis,spine=(chest[0]*.4,0,chest[2]*.3),chest=chest,head=kf(f,[(1,(0,0,0)),(9,(-4,0,6)),(15,(-10,0,-8)),(28,(-10,0,-8)),(46,(0,0,0))]),
      ankles={'R':ankle('R',-.02,yR,zR),'L':ankle('L',0,0,zL)},foot={'R':footR,'L':footL},
      hands={'R':hR,'L':hL},hand_aim={'R':(blade,aimw),'L':None},
      poles={'arm.R':(-.7,.3,-1),'arm.L':(1,.2,-.8)})
action('Affondo',46,thrust)

# --- PARATA: passo avanti col piede dello scudo, scudo alto, urto, riposta ---
def parry(f):
 root=kf(f,[(1,(0,0,-.02)),(7,(.03,-.05,-.12)),(10,(.04,.06,-.15)),(14,(.03,-.08,-.12)),(26,(.03,-.05,-.12)),(36,(0,0,-.02))])
 pelvis=kf(f,[(1,(0,0,0)),(7,(6,0,-20)),(10,(2,-2,-22)),(14,(8,0,-18)),(26,(6,0,-20)),(36,(0,0,0))])
 chest=kf(f,[(1,(0,0,0)),(7,(8,0,-18)),(10,(-8,-3,-22)),(14,(12,0,-14)),(26,(8,0,-18)),(36,(0,0,0))])
 head=kf(f,[(1,(0,0,0)),(7,(-6,0,14)),(10,(4,4,18)),(14,(-6,0,12)),(26,(-6,0,14)),(36,(0,0,0))])
 hL=kf(f,[(1,REST_L),(7,(-.22,-.40,-.12)),(10,(-.18,-.24,-.08)),(14,(-.22,-.46,-.14)),(26,(-.22,-.40,-.12)),(36,REST_L)])
 shield=kf(f,[(1,(0,0,0)),(7,(-12,0,24)),(10,(-24,0,30)),(14,(-8,0,22)),(26,(-12,0,24)),(36,(0,0,0))])
 wL=kf(f,[(1,0),(6,1),(28,1),(36,0)])
 hR=kf(f,[(1,REST_R),(7,(-.02,.12,-.28)),(10,(-.02,.18,-.24)),(14,(.02,.04,-.30)),(26,(-.02,.12,-.28)),(36,REST_R)])
 wR=kf(f,[(1,0),(6,1),(28,1),(36,0)])
 blade=(.15,-.75,.65)
 yL=kf(f,[(1,0),(7,-.30),(28,-.30),(36,0)]);zL=arc(f,1,7,.12)+arc(f,27,36,.10)
 yR=kf(f,[(1,0),(9,0),(11,.06),(28,.06),(36,0)]);zR=arc(f,8,11,.05)
 pose(root=root,pelvis=pelvis,spine=(chest[0]*.5,0,chest[2]*.3),chest=chest,head=head,
      ankles={'R':ankle('R',0,yR,zR),'L':ankle('L',-.05,yL,zL)},
      foot={'R':kf(f,[(1,0),(9,0),(10,10),(12,0)]),'L':kf(f,[(1,0),(4,8),(7,-10),(9,0)])},
      hands={'R':hR,'L':hL},hand_aim={'R':(blade,wR),'L':(shield,wL)},
      poles={'arm.R':(-1,.6,-.4),'arm.L':(1,.3,-.6)})
action('Parata',36,parry)

# Il modello Meshy è una pelle unica: dove la mano tocca il fianco ci sono facce
# "ponte" che, con le pose ampie, si allungano in bastoni. Le individuo campionando
# tutte le animazioni e le stacco (sono superfici di contatto, invisibili a riposo).
import bmesh
rest_co=np.array([v.co[:] for v in mesh.data.vertices]);ed=np.array([e.vertices[:] for e in mesh.data.edges])
L0=np.linalg.norm(rest_co[ed[:,0]]-rest_co[ed[:,1]],axis=1);stretched=np.zeros(len(ed),dtype=bool)
for act in bpy.data.actions:
 arm.animation_data.action=act
 try:arm.animation_data.action_slot=act.slots[0]
 except Exception:pass
 for f in range(1,int(act.frame_range[1])+1,2):
  bpy.context.scene.frame_set(f);ev=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get());m=ev.to_mesh()
  co=np.empty(len(m.vertices)*3);m.vertices.foreach_get('co',co);co=co.reshape(-1,3);ev.to_mesh_clear()
  L1=np.linalg.norm(co[ed[:,0]]-co[ed[:,1]],axis=1);stretched|=(L1>L0*4)&(L1>L0+.07)
bad_edges={tuple(sorted(e)) for e in ed[stretched].tolist()}
bm=bmesh.new();bm.from_mesh(mesh.data)
was_open={tuple(sorted((e.verts[0].index,e.verts[1].index))) for e in bm.edges if e.is_boundary}
# Contatti arma/pugno ↔ corpo: facce che uniscono un vertice rigido della mano a uno
# dominato da bacino/busto/cosce. Le stacco sempre (il pugno faceva da "pelle").
dom=weights.argmax(1);BODYI={names.index(n) for n in ('pelvis','spine','chest','thigh.R','thigh.L')}
contact=lambda f:any(weapon[v.index] for v in f.verts) and any((not weapon[v.index]) and dom[v.index] in BODYI for v in f.verts)
faces=[f for f in bm.faces if contact(f) or any(tuple(sorted((e.verts[0].index,e.verts[1].index))) in bad_edges for e in f.edges)]
print('BRIDGE_FACES',len(faces),'of',len(bm.faces),flush=True)
bmesh.ops.delete(bm,geom=faces,context='FACES_ONLY')
# Richiudo i buchi rimasti sul corpo (non sulle armi), con UV prese dai vicini.
bm.verts.ensure_lookup_table();uv=bm.loops.layers.uv.active
vuv={}
if uv:
 for f in bm.faces:
  for l in f.loops:vuv.setdefault(l.vert.index,[]).append(l[uv].uv.copy())
open_edges=[e for e in bm.edges if e.is_boundary and tuple(sorted((e.verts[0].index,e.verts[1].index))) not in was_open and not weapon[e.verts[0].index] and not weapon[e.verts[1].index]]
res=bmesh.ops.holes_fill(bm,edges=open_edges,sides=400)
for f in res['faces']:
 if uv:
  for l in f.loops:
   us=vuv.get(l.vert.index)
   if us:l[uv].uv=sum(us,Vector((0,0)))/len(us)
print('HOLES_FILLED',len(res['faces']),flush=True)
bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
bm.to_mesh(mesh.data);bm.free();mesh.data.update()
bpy.context.scene.frame_set(1)
arm.animation_data.action=None
for p in arm.pose.bones:
 p.rotation_quaternion=Quaternion();p.location=(0,0,0)
bpy.context.scene.render.fps=24
bpy.ops.object.select_all(action='DESELECT');arm.select_set(True);mesh.select_set(True);bpy.context.view_layer.objects.active=arm
for mat in bpy.data.materials:mat.use_backface_culling=False  # doppia faccia: niente "finestre" nella pelle
# Export one named animation per action.
bpy.ops.export_scene.gltf(filepath=str(out/'gascor-animated.glb'),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,export_frame_range=False)
(root/'source_art/gascor').mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(root/'source_art/gascor/gascor-rig.blend'))
print('RIG_READY',len(bones),'bones',list(bpy.data.actions.keys()),flush=True)
