extends RefCounted
## Gesti costruiti a mano sullo scheletro comune (24 ossa): colpi e parate a destra e a sinistra, doppio colpo,
## rotazione, contrattacco, finta, spazzata, passi laterali e all'indietro.
##
## Le clip di libreria (Meshy) non distinguono bene i lati: il "taglio destro" e il "taglio sinistro" sono due
## movimenti diversi, lunghi il doppio l'uno dell'altro, e le parate quasi non si muovono. Qui ogni gesto è
## descritto da pochi comandi (torsione del busto, dove va la mano, dove punta la lama, dove vanno i piedi) e
## la versione sinistra è l'ESATTO specchio di quella destra. Braccia e gambe si risolvono con una cinematica
## inversa a due ossa (spalla-gomito-mano, anca-ginocchio-piede): il gomito e il ginocchio piegano sempre
## dalla parte giusta e l'arma punta dove dice il gesto, senza torsioni innaturali.
##
## Assi del modello: +Z davanti, +Y in alto, +X la SINISTRA del personaggio (la destra è −X).
## Angoli "az": 0 = davanti, positivi verso la destra del personaggio, negativi verso la sinistra.

const FPS:=30.0
const LIB:="g"                      # libreria delle clip costruite: "g/Colpo destro", ...
const ARMS:=["Shoulder","Arm","ForeArm","Hand"]

# ------------------------------------------------------------------ scheletro
var sk: Skeleton3D
var n:=0
var parent:=PackedInt32Array()
var idx:={}
var rest:=[]
var prefix:=""                      # percorso delle tracce: "Gascor_Rig/Skeleton3D"
var AL:=52.0                        # lunghezza del braccio (spalla-polso), l'unità di misura dei gesti
var chest:=Vector3.ZERO             # centro delle spalle nella posa di guardia
var axisR:=Vector3.ZERO             # direzione della lama nell'osso della mano destra (zero: mano vuota)
var axisL:=Vector3.ZERO
var kind:="one"                     # one, shield, dual, two, none
var guard:=[]                       # posa di guardia (trasformazioni locali)
var guard_g:=[]                     # la stessa, globale
var left_rel:=Transform3D()         # mano sinistra rispetto alla destra (armi a due mani: resta sull'asta)

func setup(model: Node3D,ap: AnimationPlayer,weapon_kind: String,guard_clip: String) -> bool:
	var l=model.find_children("*","Skeleton3D",true,false)
	if l.is_empty() or ap==null or not ap.has_animation(guard_clip):return false
	sk=l[0];n=sk.get_bone_count();kind=weapon_kind
	parent.resize(n);rest.resize(n)
	for i in n:
		parent[i]=sk.get_bone_parent(i);idx[sk.get_bone_name(i)]=i;rest[i]=sk.get_bone_rest(i)
	for b in ["Hips","Spine02","Spine01","Spine","RightArm","RightForeArm","RightHand","LeftArm","LeftForeArm","LeftHand","RightUpLeg","RightLeg","RightFoot","LeftUpLeg","LeftLeg","LeftFoot"]:
		if not idx.has(b):return false
	var ga: Animation=ap.get_animation(guard_clip)
	for t in ga.get_track_count():
		var p=str(ga.track_get_path(t))
		if p.ends_with(":Hips"):prefix=p.trim_suffix(":Hips");break
	if prefix=="":return false
	guard=sample(ga,0.0);guard_g=globals(guard)
	var rg=globals(rest)
	AL=rg[idx.RightArm].origin.distance_to(rg[idx.RightForeArm].origin)+rg[idx.RightForeArm].origin.distance_to(rg[idx.RightHand].origin)
	chest=(guard_g[idx.RightArm].origin+guard_g[idx.LeftArm].origin)*.5
	axisR=_weapon_axis("RightHand");axisL=_weapon_axis("LeftHand")
	if kind in ["one","shield","two","dual"] and axisR==Vector3.ZERO:kind="none"
	if kind=="dual" and axisL==Vector3.ZERO:kind="one"
	left_rel=guard_g[idx.RightHand].affine_inverse()*guard_g[idx.LeftHand]
	return true

## direzione dell'arma nello spazio dell'osso che la tiene (dall'impugnatura verso la punta)
func _weapon_axis(bone: String) -> Vector3:
	for c in sk.get_children():
		if not (c is BoneAttachment3D and c.bone_name==bone):continue
		for want in ["ArmaAzione","Spada","SpadaSinistra","Arma"]:
			for w in c.get_children():
				if not (w is MeshInstance3D) or str(w.name)!=want or w.mesh==null:continue
				var bb: AABB=w.mesh.get_aabb();var ax=bb.get_longest_axis()
				var a: Vector3=w.transform*(bb.get_center()+ax*bb.get_longest_axis_size()*.5)
				var b: Vector3=w.transform*(bb.get_center()-ax*bb.get_longest_axis_size()*.5)
				return (a-b).normalized() if a.length()>=b.length() else (b-a).normalized()
	return Vector3.ZERO

# ------------------------------------------------------------------ pose
func sample(anim: Animation,time: float) -> Array:
	var pose=rest.duplicate()
	for t in anim.get_track_count():
		var ty=anim.track_get_type(t)
		if ty!=Animation.TYPE_ROTATION_3D and ty!=Animation.TYPE_POSITION_3D:continue
		var p=str(anim.track_get_path(t));var k=p.rfind(":")
		if k<0 or anim.track_get_key_count(t)==0:continue
		var b=idx.get(p.substr(k+1),-1)
		if b<0:continue
		var x: Transform3D=pose[b]
		if ty==Animation.TYPE_ROTATION_3D:x.basis=Basis(anim.rotation_track_interpolate(t,time))
		else:x.origin=anim.position_track_interpolate(t,time)
		pose[b]=x
	return pose
func globals(pose: Array) -> Array:
	var g=[];g.resize(n)
	for i in n:g[i]=pose[i] if parent[i]<0 else g[parent[i]]*pose[i]   # nello scheletro ogni osso viene dopo il suo genitore
	return g
static func _arc(a: Vector3,b: Vector3) -> Basis:
	a=a.normalized();b=b.normalized()
	var d=a.dot(b)
	if d>.99999:return Basis()
	if d<-.99999:
		var ax=a.cross(Vector3.UP)
		if ax.length()<.01:ax=a.cross(Vector3.RIGHT)
		return Basis(ax.normalized(),PI)
	return Basis(a.cross(b).normalized(),acos(clampf(d,-1,1)))
func _set_basis(pose: Array,g: Array,i: int,b: Basis) -> void:
	var x: Transform3D=pose[i]
	x.basis=((g[parent[i]].basis.inverse() if parent[i]>=0 else Basis())*b).orthonormalized();pose[i]=x
func _turn(pose: Array,i: int,r: Basis) -> void:
	var g=globals(pose);_set_basis(pose,g,i,r*g[i].basis)
func _point(pose: Array,i: int,child: int,target: Vector3) -> void:
	var g=globals(pose)
	_set_basis(pose,g,i,_arc(g[child].origin-g[i].origin,target-g[i].origin)*g[i].basis)
## due ossa (a-b-c) fino al bersaglio; "pole" è la parte verso cui piega l'articolazione di mezzo
func _ik(pose: Array,a: int,b: int,c: int,target: Vector3,pole: Vector3) -> void:
	var g=globals(pose);var A: Vector3=g[a].origin
	var l1=A.distance_to(g[b].origin);var l2=g[b].origin.distance_to(g[c].origin)
	var d=target-A;var dist=clampf(d.length(),absf(l1-l2)+.5,(l1+l2)*.985);var dir=d.normalized()
	var ca=clampf((l1*l1+dist*dist-l2*l2)/(2.0*l1*dist),-1,1)
	var pp=pole-dir*pole.dot(dir)
	if pp.length()<.001:pp=Vector3.DOWN-dir*Vector3.DOWN.dot(dir)
	var mid=A+dir*(l1*ca)+pp.normalized()*(l1*sqrt(1.0-ca*ca))
	_point(pose,a,b,mid);_point(pose,b,c,A+dir*dist)

static func dir_az(az: float,el:=0.0) -> Vector3:
	var a=deg_to_rad(az);var e=deg_to_rad(el)
	return Vector3(-sin(a)*cos(e),sin(e),cos(a)*cos(e))

# ------------------------------------------------------------------ comandi di un fotogramma
## c: {"w":peso 0..1, "twist","lean","side","spin" (gradi), "hips":Vector3 (in braccia),
##     "R"/"L": [az, raggio, altezza, az lama, elevazione lama] (raggio e altezza in braccia, dal centro delle spalle),
##     "Rw"/"Lw": peso del braccio, "follow": la sinistra resta sull'asta, "feet": {"R":Vector3,"L":Vector3} (cm)}
## base: la posa da cui si parte (guardia, o il fotogramma di una clip di libreria); frame: come si è mosso il busto
func solve(base: Array,c: Dictionary,frame:=Transform3D(),use_frame:=false) -> Array:
	var p=base.duplicate()
	var hi: int=idx.Hips
	if c.has("hips"):
		var x: Transform3D=p[hi];x.origin+=(c.hips as Vector3)*AL;p[hi]=x
	if float(c.get("spin",0.0))!=0.0:_turn(p,hi,Basis(Vector3.UP,-deg_to_rad(float(c.spin))))
	var tw=float(c.get("twist",0.0));var ln=float(c.get("lean",0.0));var sd=float(c.get("side",0.0))
	if tw!=0.0 or ln!=0.0 or sd!=0.0:
		var r=Basis(Vector3.UP,-deg_to_rad(tw)/3.0)*Basis(Vector3.RIGHT,deg_to_rad(ln)/3.0)*Basis(Vector3.BACK,deg_to_rad(sd)/3.0)
		for b in ["Spine02","Spine01","Spine"]:_turn(p,idx[b],r)
	if c.has("feet"):
		for s in ["Right","Left"]:
			if not c.feet.has(s[0]):continue
			var off: Vector3=c.feet[s[0]]
			var fi: int=idx[s+"Foot"]
			var out=Vector3(-1,0,0) if s=="Right" else Vector3(1,0,0)
			_ik(p,idx[s+"UpLeg"],idx[s+"Leg"],fi,guard_g[fi].origin+off,Vector3(0,0,1)+out*.25)
			_set_basis(p,globals(p),fi,guard_g[fi].basis)   # il piede resta piatto, orientato come in guardia
	for s in ["Right","Left"]:   # braccio girato tutto insieme (scudo): resta com'è in guardia, ma rivolto altrove
		var rk=s[0]+"r"
		if c.has(rk):
			var a: Array=c[rk]
			_turn(p,idx[s+"Arm"],Basis(Vector3.UP,-deg_to_rad(float(a[0])))*Basis(Vector3.RIGHT,-deg_to_rad(float(a[1]))))
	for s in ["Right","Left"]:
		var key=s[0]
		if s=="Left" and c.get("follow",false):continue
		if not c.has(key) or float(c.get(key+"w",1.0))<=0.0:continue
		var a: Array=c[key];var before=p.duplicate()
		var hand_pos=chest+dir_az(a[0])*float(a[1])*AL+Vector3.UP*float(a[2])*AL
		var blade=dir_az(a[3],a[4])
		if use_frame:hand_pos=frame*hand_pos;blade=frame.basis*blade
		var out=Vector3(-1,0,0) if s=="Right" else Vector3(1,0,0)
		if use_frame:out=frame.basis*out
		_ik(p,idx[s+"Arm"],idx[s+"ForeArm"],idx[s+"Hand"],hand_pos,out*.7+Vector3.DOWN+(frame.basis*Vector3(0,0,-.35) if use_frame else Vector3(0,0,-.35)))
		var ax: Vector3=axisR if s=="Right" else axisL
		var hb: int=idx[s+"Hand"];var g=globals(p)
		if ax!=Vector3.ZERO:_set_basis(p,g,hb,_arc(g[hb].basis*ax,blade)*g[hb].basis)
		else:_set_basis(p,g,hb,_arc(g[hb].origin-g[idx[s+"ForeArm"]].origin,blade)*g[hb].basis)   # mano vuota: le dita puntano lì
		var w=float(c.get(key+"w",1.0))
		if w<1.0:
			for part in ARMS:
				var bi: int=idx.get(s+part,-1)
				if bi>=0:p[bi]=(before[bi] as Transform3D).interpolate_with(p[bi],w)
	if c.get("follow",false):   # arma a due mani: la sinistra segue la destra lungo l'asta
		var g=globals(p);var want: Transform3D=g[idx.RightHand]*left_rel
		_ik(p,idx.LeftArm,idx.LeftForeArm,idx.LeftHand,want.origin,Vector3(.7,-1,-.35))
		_set_basis(p,globals(p),idx.LeftHand,want.basis)
	var w0=float(c.get("w",1.0))
	if w0<1.0:
		for i in n:p[i]=(base[i] as Transform3D).interpolate_with(p[i],w0)
	return p

# ------------------------------------------------------------------ chiavi -> comandi interpolati
static func _lerp_any(a,b,f: float):
	if a is Array:
		var o=[]
		for k in a.size():o.append(lerpf(float(a[k]),float(b[k]),f))
		return o
	if a is Vector3:return (a as Vector3).lerp(b,f)
	if a is Dictionary:
		var o={}
		for k in a:o[k]=_lerp_any(a[k],b.get(k,a[k]),f)
		return o
	if a is bool:return a
	return lerpf(float(a),float(b),f)
## keys: [[u, comandi, "s" morbido | "l" lineare], ...] con u crescente da 0 a 1
static func controls(keys: Array,u: float) -> Dictionary:
	if u<=float(keys[0][0]):return keys[0][1]
	for k in range(1,keys.size()):
		if u<=float(keys[k][0]):
			var a=keys[k-1];var b=keys[k]
			var f=(u-float(a[0]))/maxf(float(b[0])-float(a[0]),.0001)
			if str(b[2] if b.size()>2 else "s")=="s":f=smoothstep(0.0,1.0,f)
			return _lerp_any(a[1],b[1],f)
	return keys.back()[1]
## riempie i comandi mancanti in ogni chiave con quelli della chiave vicina (a peso zero dove non c'erano)
static func normalize(keys: Array) -> Array:
	var all={}
	for k in keys:
		for f in k[1]:all[f]=true
	var out=[]
	for k in keys.size():
		var c: Dictionary=keys[k][1].duplicate(true)
		for f in all:
			if c.has(f):continue
			if f in ["R","L","feet"]:
				var near=null   # la chiave più vicina che ce l'ha
				for d in range(1,keys.size()):
					for j in [k-d,k+d]:
						if j>=0 and j<keys.size() and keys[j][1].has(f) and near==null:near=keys[j][1][f]
				if f=="feet":c[f]=near.duplicate() if near!=null else {}
				if f=="feet" and near!=null:
					for fk in c[f]:c[f][fk]=Vector3.ZERO
				else:c[f]=near;c[f+"w"]=0.0
			elif f=="hips":c[f]=Vector3.ZERO
			elif f in ["Rr","Lr"]:c[f]=[0.0,0.0]
			elif f=="follow":c[f]=true
			elif f=="w":c[f]=1.0
			elif f in ["Rw","Lw"]:c[f]=1.0 if keys[k][1].has(f[0]) else 0.0
			else:c[f]=0.0
		if c.has("R") and not c.has("Rw"):c["Rw"]=1.0
		if c.has("L") and not c.has("Lw"):c["Lw"]=1.0
		out.append([keys[k][0],c,keys[k][2] if keys[k].size()>2 else "s"])
	return out
static func mirror(keys: Array) -> Array:
	var out=[]
	for k in keys:
		var c: Dictionary=k[1];var m={}
		for f in c:
			match f:
				"twist","side","spin":m[f]=-float(c[f])
				"hips":m[f]=Vector3(-c[f].x,c[f].y,c[f].z)
				"R","L":
					var a: Array=c[f];m["L" if f=="R" else "R"]=[-float(a[0]),a[1],a[2],-float(a[3]),a[4]]
				"Rr","Lr":m["Lr" if f=="Rr" else "Rr"]=[-float(c[f][0]),c[f][1]]
				"Rw":m["Lw"]=c[f]
				"Lw":m["Rw"]=c[f]
				"feet":
					var ft={}
					for fk in c[f]:ft["L" if fk=="R" else "R"]=Vector3(-c[f][fk].x,c[f][fk].y,c[f][fk].z)
					m[f]=ft
				_:m[f]=c[f]
		out.append([k[0],m,k[2] if k.size()>2 else "s"])
	return out

# ------------------------------------------------------------------ dalla descrizione alla clip
func bake(keys: Array,length: float,meta:={},loop:=false) -> Animation:
	keys=normalize(keys)
	var anim=Animation.new();anim.length=length
	anim.loop_mode=Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var rt=[];rt.resize(n)
	for i in n:
		rt[i]=anim.add_track(Animation.TYPE_ROTATION_3D);anim.track_set_path(rt[i],"%s:%s"%[prefix,sk.get_bone_name(i)])
	var ht=anim.add_track(Animation.TYPE_POSITION_3D);anim.track_set_path(ht,"%s:Hips"%prefix)
	var frames=maxi(2,roundi(length*FPS))
	for f in frames+1:
		var u=float(f)/frames
		var p=solve(guard,controls(keys,u))
		for i in n:anim.rotation_track_insert_key(rt[i],u*length,(p[i] as Transform3D).basis.get_rotation_quaternion())
		anim.position_track_insert_key(ht,u*length,(p[idx.Hips] as Transform3D).origin)
	for k in meta:anim.set_meta(k,meta[k])
	return anim
## clip di libreria con un braccio tenuto in posa (seconda arma): il resto del corpo resta com'era
func overlay(src: Animation,c: Dictionary) -> Animation:
	var anim: Animation=src.duplicate(true)
	var bones=[]
	for s in ["Right","Left"]:
		if c.has(s[0]):
			for part in ARMS:
				if idx.has(s+part):bones.append(idx[s+part])
	var tracks={}
	for b in bones:
		var path="%s:%s"%[prefix,sk.get_bone_name(b)]
		for t in range(anim.get_track_count()-1,-1,-1):
			if anim.track_get_type(t)==Animation.TYPE_ROTATION_3D and str(anim.track_get_path(t))==path:anim.remove_track(t)
	for b in bones:
		var t=anim.add_track(Animation.TYPE_ROTATION_3D);anim.track_set_path(t,"%s:%s"%[prefix,sk.get_bone_name(b)]);tracks[b]=t
	var top: int=idx.Spine
	var frames=maxi(2,roundi(src.length*FPS))
	for f in frames+1:
		var time=src.length*float(f)/frames
		var base=sample(src,time);var g=globals(base)
		# come si è spostato il busto rispetto alla guardia: il braccio lo segue
		var fr: Transform3D=g[top]*(guard_g[top] as Transform3D).affine_inverse()
		var p=solve(base,c,fr,true)
		for b in bones:anim.rotation_track_insert_key(tracks[b],time,(p[b] as Transform3D).basis.get_rotation_quaternion())
	return anim
## istante in cui il colpo di una clip di libreria arriva davvero: la mano dell'arma (o il piede, nei calci)
## è al massimo dell'allungo in avanti rispetto al bacino
func impact_time(anim: Animation,foot:=false) -> float:
	if anim.has_meta("impact"):return float(anim.get_meta("impact"))
	var best=-INF;var at=anim.length*.45;var steps=24
	for k in range(2,steps-1):
		var t=anim.length*float(k)/steps
		var g=globals(sample(anim,t))
		var reach=-INF
		for b in (["RightFoot","LeftFoot"] if foot else ["RightHand"]):
			var v: Vector3=g[idx[b]].origin-g[idx.Hips].origin
			reach=maxf(reach,v.z+(v.y*.3 if foot else 0.0))
		if reach>best:best=reach;at=t
	anim.set_meta("impact",at)
	return at

# ------------------------------------------------------------------ i gesti
const HOLD_R=[38.0,.82,-.5,22.0,24.0]      # arma tenuta in guardia: davanti al fianco, punta in alto e avanti
static func _hold(side: String) -> Array:
	return HOLD_R if side=="R" else [-HOLD_R[0],HOLD_R[1],HOLD_R[2],-HOLD_R[3],HOLD_R[4]]

## taglio da destra: l'arma parte larga sul fianco destro e spazza l'arco davanti-destra fino al davanti
func k_cut_right() -> Array:
	var two=kind=="two"
	var k=[[0.0,{"w":0.0,"twist":0.0,"R":[70.0,.9,-.2,60.0,40.0]}],
		[.24,{"w":1.0,"twist":38.0,"lean":-4.0,"R":[112.0,1.0 if two else 1.08,.22,150.0,32.0]}],
		[.40,{"w":1.0,"twist":14.0,"lean":4.0,"R":[72.0,1.12 if two else 1.28,.0,84.0,6.0]},"l"],
		[.50,{"w":1.0,"twist":-12.0,"lean":9.0,"R":[22.0,1.0 if two else 1.1,-.06,18.0,0.0]},"l"],
		[.62,{"w":1.0,"twist":-30.0,"lean":8.0,"R":[-22.0,.84,-.16,-38.0,-6.0]},"l"],
		[.78,{"w":1.0,"twist":-24.0,"lean":4.0,"R":[-20.0,.8,-.2,-30.0,4.0]}],
		[1.0,{"w":0.0,"twist":0.0,"R":[30.0,.8,-.3,10.0,40.0]}]]
	if two:
		for q in k:q[1]["follow"]=true
	return k
## rovescio: la stessa arma parte dalla spalla sinistra e spazza l'arco davanti-sinistra (armi a una mano e a due mani)
func k_cut_back() -> Array:
	var two=kind=="two"
	var k=[[0.0,{"w":0.0,"twist":0.0,"R":[10.0,.7,-.2,-20.0,45.0]}],
		[.24,{"w":1.0,"twist":-42.0,"lean":-3.0,"R":[-62.0,.62,.28,-150.0,34.0]}],
		[.40,{"w":1.0,"twist":-18.0,"lean":4.0,"R":[-48.0,1.0,.04,-82.0,6.0]},"l"],
		[.50,{"w":1.0,"twist":8.0,"lean":9.0,"R":[-12.0,1.1 if not two else 1.0,-.05,-16.0,0.0]},"l"],
		[.62,{"w":1.0,"twist":28.0,"lean":8.0,"R":[34.0,1.0,-.14,42.0,-6.0]},"l"],
		[.78,{"w":1.0,"twist":22.0,"lean":4.0,"R":[36.0,.92,-.2,34.0,4.0]}],
		[1.0,{"w":0.0,"twist":0.0,"R":[30.0,.8,-.3,10.0,40.0]}]]
	if two:
		for q in k:q[1]["follow"]=true
	if kind=="shield":   # lo scudo si apre sul fianco per lasciare passare la lama
		for q in k:
			if float(q[0])>0.0 and float(q[0])<1.0:q[1]["L"]=[-98.0,.82,-.42,-90.0,0.0]
	return k
## parata a destra: l'arma verticale ferma sul lato destro, busto girato da quella parte
func k_parry_right() -> Array:
	var blade=[68.0,.98,-.12,72.0,78.0]
	if kind=="none":blade=[42.0,.72,.12,30.0,62.0]   # a mani nude: l'avambraccio alzato a coprire
	var k=[[0.0,{"w":0.0,"twist":0.0,"R":blade}],
		[.26,{"w":1.0,"twist":32.0,"side":4.0,"R":blade}],
		[.70,{"w":1.0,"twist":34.0,"side":4.0,"R":[blade[0]+4.0,blade[1]+.03,blade[2],blade[3],blade[4]]}],
		[1.0,{"w":0.0,"twist":0.0,"R":blade}]]
	if kind=="two":
		for q in k:q[1]["follow"]=true
	return k
## parata a sinistra con l'arma della mano destra portata di traverso (una mano senza scudo, due mani)
func k_parry_across() -> Array:
	var blade=[-34.0,.78,-.06,-52.0,76.0]
	var k=[[0.0,{"w":0.0,"twist":0.0,"R":blade}],
		[.26,{"w":1.0,"twist":-30.0,"side":-4.0,"R":blade}],
		[.70,{"w":1.0,"twist":-32.0,"side":-4.0,"R":[blade[0]-4.0,blade[1]+.03,blade[2],blade[3],blade[4]]}],
		[1.0,{"w":0.0,"twist":0.0,"R":blade}]]
	if kind=="two":
		for q in k:q[1]["follow"]=true
	return k
## parata a sinistra con lo scudo: braccio alzato e portato fuori, busto girato a sinistra
func k_parry_shield() -> Array:
	return [[0.0,{"w":0.0,"twist":0.0,"Lr":[0.0,0.0]}],
		[.26,{"w":1.0,"twist":-30.0,"side":-4.0,"Lr":[-12.0,10.0]}],
		[.70,{"w":1.0,"twist":-32.0,"side":-4.0,"Lr":[-15.0,12.0]}],
		[1.0,{"w":0.0,"twist":0.0,"Lr":[0.0,0.0]}]]
## spazzata: un arco basso e largo da destra a sinistra su tutto il fronte
func k_sweep() -> Array:
	var two=kind=="two"
	var k=[[0.0,{"w":0.0,"R":[60.0,.9,-.3,50.0,20.0]}],
		[.26,{"w":1.0,"twist":48.0,"lean":6.0,"R":[116.0,1.0,-.42,140.0,-12.0]}],
		[.42,{"w":1.0,"twist":20.0,"lean":12.0,"R":[70.0,1.14,-.5,80.0,-16.0]},"l"],
		[.52,{"w":1.0,"twist":-8.0,"lean":14.0,"R":[14.0,1.06,-.52,10.0,-18.0]},"l"],
		[.64,{"w":1.0,"twist":-36.0,"lean":12.0,"R":[-40.0,.9,-.5,-60.0,-16.0]},"l"],
		[.8,{"w":1.0,"twist":-30.0,"lean":6.0,"R":[-36.0,.84,-.44,-50.0,-6.0]}],
		[1.0,{"w":0.0,"R":[30.0,.8,-.3,10.0,40.0]}]]
	if two:
		for q in k:q[1]["follow"]=true
	return k
## rotazione: braccia larghe e un giro completo su sé stesso
func k_spin() -> Array:
	var out_r=[84.0,1.22,-.02,88.0,2.0];var out_l=[-84.0,1.22,-.02,-88.0,2.0]
	var k=[[0.0,{"w":0.0,"spin":0.0,"R":out_r}],
		[.2,{"w":1.0,"spin":-30.0,"twist":20.0,"R":out_r}],
		[.72,{"w":1.0,"spin":330.0,"twist":-10.0,"lean":6.0,"R":out_r},"l"],
		[.86,{"w":1.0,"spin":360.0,"R":out_r}],
		[1.0,{"w":0.0,"spin":360.0,"R":out_r}]]
	for q in k:
		if kind=="dual":q[1]["L"]=out_l
		elif kind=="two":q[1]["follow"]=true
	return k
## doppio colpo: taglio da destra con la destra e subito taglio da sinistra con la sinistra
func k_double() -> Array:
	return [[0.0,{"w":0.0,"twist":0.0,"R":[70.0,.9,-.2,60.0,40.0],"L":_hold("L")}],
		[.16,{"w":1.0,"twist":36.0,"R":[112.0,1.08,.22,150.0,32.0],"L":_hold("L")}],
		[.28,{"w":1.0,"twist":10.0,"lean":5.0,"R":[66.0,1.28,.0,78.0,6.0],"L":[-70.0,.9,.1,-120.0,34.0]},"l"],
		[.36,{"w":1.0,"twist":-16.0,"lean":9.0,"R":[18.0,1.1,-.06,14.0,0.0],"L":[-110.0,1.06,.22,-150.0,32.0]},"l"],
		[.48,{"w":1.0,"twist":-34.0,"lean":8.0,"R":[-20.0,.8,-.2,-34.0,-4.0],"L":[-112.0,1.08,.22,-150.0,30.0]},"l"],
		[.58,{"w":1.0,"twist":-8.0,"lean":8.0,"R":[0.0,.66,-.34,-10.0,30.0],"L":[-66.0,1.28,.0,-78.0,6.0]},"l"],
		[.66,{"w":1.0,"twist":18.0,"lean":10.0,"R":[24.0,.7,-.4,6.0,48.0],"L":[-18.0,1.1,-.06,-14.0,0.0]},"l"],
		[.78,{"w":1.0,"twist":32.0,"lean":8.0,"R":_hold("R"),"L":[20.0,.8,-.2,34.0,-4.0]},"l"],
		[.88,{"w":1.0,"twist":22.0,"lean":4.0,"R":_hold("R"),"L":[14.0,.78,-.24,26.0,6.0]}],
		[1.0,{"w":0.0,"twist":0.0,"R":_hold("R"),"L":_hold("L")}]]
## fendente a due lame: su tutte e due, poi giù incrociate
func k_cleave_dual() -> Array:
	var up_r=[26.0,.46,.86,10.0,76.0];var up_l=[-26.0,.46,.86,-10.0,76.0]
	return [[0.0,{"w":0.0,"R":_hold("R"),"L":_hold("L")}],
		[.3,{"w":1.0,"lean":-10.0,"R":up_r,"L":up_l}],
		[.42,{"w":1.0,"lean":-8.0,"R":up_r,"L":up_l}],
		[.54,{"w":1.0,"lean":18.0,"R":[10.0,1.12,-.1,-8.0,-8.0],"L":[-10.0,1.12,-.1,8.0,-8.0]},"l"],
		[.64,{"w":1.0,"lean":22.0,"R":[-6.0,.96,-.46,-22.0,-34.0],"L":[6.0,.96,-.46,22.0,-34.0]},"l"],
		[.82,{"w":1.0,"lean":12.0,"R":[0.0,.9,-.44,-12.0,-20.0],"L":[0.0,.9,-.44,12.0,-20.0]}],
		[1.0,{"w":0.0,"R":_hold("R"),"L":_hold("L")}]]
## contrattacco: para di fronte, poi affonda
func k_counter() -> Array:
	var dual=kind=="dual"
	var block=[10.0,.8,-.02,-20.0,74.0]
	var k=[[0.0,{"w":0.0,"R":block}],
		[.18,{"w":1.0,"twist":-8.0,"lean":-4.0,"R":block}],
		[.42,{"w":1.0,"twist":-10.0,"lean":-4.0,"R":block}],
		[.52,{"w":1.0,"twist":18.0,"lean":2.0,"R":[40.0,.62,-.22,6.0,6.0]}],
		[.64,{"w":1.0,"twist":-22.0,"lean":14.0,"hips":Vector3(0,-.04,.16),"R":[4.0,1.42,-.1,0.0,0.0]},"l"],
		[.8,{"w":1.0,"twist":-18.0,"lean":10.0,"hips":Vector3(0,-.03,.1),"R":[4.0,1.3,-.12,0.0,2.0]}],
		[1.0,{"w":0.0,"R":_hold("R")}]]
	if dual:   # para con la sinistra, affonda con la destra
		var lb=[-10.0,.8,-.02,20.0,74.0]
		k[0][1]={"w":0.0,"L":lb,"R":_hold("R")};k[1][1]={"w":1.0,"twist":8.0,"lean":-4.0,"L":lb,"R":[48.0,.6,-.2,20.0,10.0]}
		k[2][1]={"w":1.0,"twist":10.0,"lean":-4.0,"L":lb,"R":[48.0,.6,-.2,20.0,10.0]}
		for j in range(3,6):k[j][1]["L"]=[-40.0,.7,-.3,-30.0,50.0]
		k[6][1]["L"]=_hold("L")
	if kind=="two":
		for q in k:q[1]["follow"]=true
	return k
## finta: accenna il taglio da destra, si ferma e affonda basso
func k_feint() -> Array:
	var k=[[0.0,{"w":0.0,"R":[70.0,.9,-.2,60.0,40.0]}],
		[.2,{"w":1.0,"twist":34.0,"R":[108.0,1.04,.24,146.0,32.0]}],
		[.34,{"w":1.0,"twist":20.0,"lean":3.0,"R":[84.0,1.12,.1,104.0,16.0]},"l"],
		[.46,{"w":1.0,"twist":24.0,"lean":2.0,"R":[70.0,.7,-.3,30.0,0.0]}],
		[.6,{"w":1.0,"twist":-20.0,"lean":15.0,"hips":Vector3(0,-.05,.16),"R":[2.0,1.4,-.34,0.0,-6.0]},"l"],
		[.78,{"w":1.0,"twist":-16.0,"lean":10.0,"hips":Vector3(0,-.03,.1),"R":[2.0,1.28,-.32,0.0,-2.0]}],
		[1.0,{"w":0.0,"R":_hold("R")}]]
	if kind=="two":
		for q in k:q[1]["follow"]=true
	if kind=="dual":
		for q in k:q[1]["L"]=_hold("L")
	return k
func _front_foot() -> String:
	return "R" if guard_g[idx.RightFoot].origin.z>guard_g[idx.LeftFoot].origin.z else "L"
## affondo: l'arma si ritira al fianco e parte dritta in avanti, con il passo e il peso del corpo dietro
func k_thrust() -> Array:
	var lead=_front_foot();var step=Vector3(0,0,.42*AL)
	var k=[[0.0,{"w":0.0,"R":[40.0,.7,-.3,10.0,10.0],"feet":{lead:Vector3.ZERO}}],
		[.22,{"w":1.0,"twist":30.0,"lean":-4.0,"hips":Vector3(0,-.02,-.05),"R":[52.0,.56,-.3,10.0,4.0],"feet":{lead:Vector3.ZERO}}],
		[.32,{"w":1.0,"twist":8.0,"lean":4.0,"hips":Vector3(0,-.05,.08),"R":[26.0,.95,-.2,2.0,2.0],"feet":{lead:step*.6+Vector3(0,.08*AL,0)}},"l"],
		[.42,{"w":1.0,"twist":-26.0,"lean":15.0,"hips":Vector3(0,-.09,.24),"R":[3.0,1.46,-.12,0.0,0.0],"feet":{lead:step}},"l"],
		[.6,{"w":1.0,"twist":-24.0,"lean":14.0,"hips":Vector3(0,-.09,.23),"R":[3.0,1.42,-.13,0.0,1.0],"feet":{lead:step}}],
		[.8,{"w":1.0,"twist":-6.0,"lean":4.0,"hips":Vector3(0,-.03,.08),"R":[30.0,.8,-.3,8.0,20.0],"feet":{lead:step*.35+Vector3(0,.06*AL,0)}}],
		[1.0,{"w":0.0,"R":[38.0,.8,-.4,10.0,30.0],"feet":{lead:Vector3.ZERO}}]]
	for q in k:
		if kind=="two":q[1]["follow"]=true
		if kind=="dual":q[1]["L"]=_hold("L")
	return k
## fendente: l'arma sale sopra la testa e cala dritta davanti
func k_cleave() -> Array:
	var k=[[0.0,{"w":0.0,"R":[30.0,.7,-.2,6.0,40.0]}],
		[.28,{"w":1.0,"twist":10.0,"lean":-10.0,"R":[24.0,.44,.92,0.0,72.0]}],
		[.42,{"w":1.0,"twist":10.0,"lean":-11.0,"R":[24.0,.42,.96,0.0,76.0]}],
		[.54,{"w":1.0,"twist":-8.0,"lean":17.0,"hips":Vector3(0,-.05,.1),"R":[8.0,1.16,-.04,0.0,-6.0]},"l"],
		[.64,{"w":1.0,"twist":-12.0,"lean":23.0,"hips":Vector3(0,-.07,.12),"R":[4.0,1.0,-.52,0.0,-38.0]},"l"],
		[.82,{"w":1.0,"twist":-8.0,"lean":12.0,"hips":Vector3(0,-.03,.06),"R":[10.0,.9,-.48,0.0,-22.0]}],
		[1.0,{"w":0.0,"R":[36.0,.8,-.45,10.0,10.0]}]]
	if kind=="two":
		for q in k:q[1]["follow"]=true
	return k
## passo senza girarsi (laterale, in diagonale o all'indietro): la gamba dal lato del movimento parte, l'altra
## la segue; nel frattempo la miniatura scorre di "dist" centimetri. side: lato dell'esagono (1..5), 0 = davanti
func k_step(side: int,dist: float,hop:=false) -> Array:
	var e=dir_az(60.0*side)   # direzione del passo nello spazio del modello
	var lead="R" if side in [1,2] else "L"
	if side==3 or side==0:   # indietro parte il piede arretrato, in avanti quello avanzato
		var rz=guard_g[idx.RightFoot].origin.z;var lz=guard_g[idx.LeftFoot].origin.z
		lead=("R" if rz<lz else "L") if side==3 else ("R" if rz>lz else "L")
	var trail="L" if lead=="R" else "R"
	var lift=Vector3(0,(.2 if hop else .13)*AL,0)
	var sway=-e*.06;var drop=Vector3(0,-.07 if hop else -.045,0)
	var tw=(10.0 if side in [1,2] else (-10.0 if side in [4,5] else 0.0))
	var k=[]
	for q in [0.0,.125,.25,.375,.5,.625,.75,.875,1.0]:
		var u: float=q
		var s1=smoothstep(0.0,1.0,clampf(u/.5,0,1));var s2=smoothstep(0.0,1.0,clampf((u-.5)/.5,0,1))
		var fl: Vector3=e*dist*(s1-u)+(lift*sin(PI*clampf(u/.5,0,1)) if u<.5 else Vector3.ZERO)
		var ft: Vector3=e*dist*(s2-u)+(lift*sin(PI*clampf((u-.5)/.5,0,1)) if u>.5 else Vector3.ZERO)
		var spread=sin(PI*u)
		k.append([u,{"w":1.0,"hips":drop*spread+sway*sin(TAU*u),"twist":tw*spread*.5,"side":(4.0 if side in [1,2] else (-4.0 if side in [4,5] else 0.0))*sin(TAU*u),
			"lean":(-5.0 if side==3 else 0.0)*spread,"feet":{lead:fl,trail:ft}},"l"])
	return k

# ------------------------------------------------------------------ libreria completa di una miniatura
const DUAL_OVERLAY=["In guardia","Avanzare","Camminata","Correre","Carica","Calcio","Schivata","Sbilanciato","Sgambetto","Riposo"]
const CUT_LEN:=1.15
const PARRY_LEN:=1.1
## crea la libreria "g" sull'AnimationPlayer; step_dist = centimetri (dello scheletro) di mezzo esagono
func build(ap: AnimationPlayer,step_dist: float,sfx:="") -> void:
	var lib=AnimationLibrary.new()
	var add=func(name: String,a: Animation):lib.add_animation(name,a)
	var armed=kind in ["one","shield","dual","two"]
	if armed:
		var cut=k_cut_right()
		add.call("Colpo destro",bake(cut,CUT_LEN,{"impact":CUT_LEN*.5,"sweep":[CUT_LEN*.36,CUT_LEN*.62],"side":-1.0}))
		var left=mirror(cut) if kind=="dual" else k_cut_back()
		if kind=="dual":   # ogni lama il suo lato: l'altra resta in guardia
			for q in cut:q[1]["L"]=_hold("L")
			lib.remove_animation("Colpo destro");add.call("Colpo destro",bake(cut,CUT_LEN,{"impact":CUT_LEN*.5,"sweep":[CUT_LEN*.36,CUT_LEN*.62],"side":-1.0}))
			left=mirror(cut)
		add.call("Colpo sinistro",bake(left,CUT_LEN,{"impact":CUT_LEN*.5,"sweep":[CUT_LEN*.36,CUT_LEN*.62],"side":1.0}))
		add.call("Affondo",bake(k_thrust(),1.25,{"impact":1.25*.42}))
		if kind!="dual":add.call("Fendente",bake(k_cleave(),1.5,{"impact":1.5*.56}))
		add.call("Rotazione",bake(k_spin(),1.5,{"impact":.75}))
		add.call("Contrattacco",bake(k_counter(),1.7,{"impact":1.7*.64,"block":1.7*.18}))
		add.call("Finta",bake(k_feint(),1.5,{"impact":1.5*.6}))
		if kind!="dual":add.call("Spazzata",bake(k_sweep(),1.3,{"impact":1.3*.52}))
	var pr=k_parry_right()
	if kind=="dual":
		for q in pr:q[1]["L"]=_hold("L")
	add.call("Para destra",bake(pr,PARRY_LEN,{"block":PARRY_LEN*.26,"side":-1.0}))
	var pl=mirror(pr) if kind in ["dual","none"] else (k_parry_shield() if kind=="shield" else k_parry_across())
	add.call("Para sinistra",bake(pl,PARRY_LEN,{"block":PARRY_LEN*.26,"side":1.0}))
	if kind=="dual":
		add.call("Doppio colpo",bake(k_double(),1.7,{"impact":1.7*.36,"impact2":1.7*.66}))
		add.call("Fendente",bake(k_cleave_dual(),1.5,{"impact":1.5*.56}))
		for name in DUAL_OVERLAY:   # nelle altre mosse la seconda lama resta in guardia invece di ciondolare
			if ap.has_animation(name+sfx):
				var a=overlay(ap.get_animation(name+sfx),{"L":_hold("L")})
				a.loop_mode=ap.get_animation(name+sfx).loop_mode;add.call(name,a)
	for side in [1,2,3,4,5]:
		add.call("Passo %d"%side,bake(k_step(side,step_dist),.62,{"cycle":step_dist},true))
	if ap.has_animation_library(LIB):ap.remove_animation_library(LIB)
	ap.add_animation_library(LIB,lib)
