class_name ArenaBoard3D
extends SubViewportContainer
# Mappa 3D con miniature animate. Ha la stessa interfaccia di ArenaBoard (highlights,
# selected, focus_fighter, preview_facing, show_grid, cell_clicked), così i pannelli
# della partita funzionano senza modifiche. Dopo ogni aggiornamento dello stato,
# sync() confronta i combattenti con lo stato precedente e mette in coda le animazioni:
# la pedina estratta fa partire la clip corrispondente, chi si sposta cammina fino
# alla nuova cella, il facing viene rispettato, chi è colpito reagisce.
# Tutti i passi vengono registrati per il replay finale, senza pause fra i turni.

signal cell_clicked(cell: String)
signal fighter_clicked(index: int)

const U=0.6/121.0          # metri per pixel della mappa: un esagono (raggio 121 px) ≈ 1,2 m
const MODELS={"gascor":"res://assets/models/gascor/gascor.glb","anteos":"res://assets/models/anteos/anteos.glb",
	"ut":"res://assets/models/ut/ut.glb","shannon":"res://assets/models/shannon/shannon.glb",
	"nuchra":"res://assets/models/nuchra/nuchra.glb","ramok":"res://assets/models/ramok/ramok.glb",
	"zenyo":"res://assets/models/zenyo/zenyo.glb","shaara":"res://assets/models/shaara/shaara.glb",
	"zak":"res://assets/models/zak/zak.glb","kylvia":"res://assets/models/kylvia/kylvia.glb",
	"gandy":"res://assets/models/gandy/gandy.glb","thorn":"res://assets/models/thorn/thorn.glb",
	"sanguinaria":"res://assets/models/sanguinaria/sanguinaria.glb","ziggy":"res://assets/models/ziggy/ziggy.glb"}
const CLIP={"guard":"In guardia","advance":"Avanzare","run":"Correre","charge":"Carica","cleave":"Fendente",
	"left":"Taglio Sx","right":"Taglio Dx","thrust":"Affondo","kick":"Calcio","parry_l":"Parata Sx","parry_r":"Parata Dx",
	"dodge":"Schivata","roll":"Rotolare","unbalanced":"Sbilanciato","down":"A terra","rise":"Rialzarsi","again":"In guardia",
	"spin":"Taglio Dx","sweep":"Taglio Sx","meditate":"Riposo",
	"load":"Incoccare","shoot":"Tirare","weapon":"Riposo",
	# maghi: ogni incantesimo ha la sua clip, generata sul rig del mago
	"concentrate":"Concentrarsi","punch":"Pugno","float":"Fluttuare",
	"firestaff":"Bastone di fuoco","shield":"Scudo","vortex":"Vortice","sleep":"Sonno","fireball":"Palla di fuoco",
	"pustules":"Pustole","fear":"Paura","age":"Vecchiaia","summon":"Evocare","plague":"Peste",
	"wall":"Muro","teleport":"Teletrasporto","transform":"Trasformazione","livingfire":"Fuoco vivo","abyss":"Abisso",
	"shock":"Scossa","heal":"Cura","drain":"Drenare","control":"Controllo","lightning":"Fulmine","dematerialize":"Smaterializzare"}
# colore della magia: lampo sul mago e sfera che vola verso chi viene colpito
const SPELL_FX={"firestaff":Color(1,.45,.1),"shield":Color(.45,.7,1),"vortex":Color(.5,.8,1),"sleep":Color(.75,.6,1),"fireball":Color(1,.4,.05),
	"pustules":Color(.75,.85,.2),"fear":Color(.55,.2,.6),"age":Color(.7,.65,.5),"summon":Color(.6,.45,.3),"plague":Color(.55,.8,.15),
	"wall":Color(1,.35,.1),"teleport":Color(1,.3,.25),"transform":Color(.3,.9,.4),"livingfire":Color(1,.5,.1),"abyss":Color(.35,.1,.45),
	"shock":Color(.4,.8,1),"heal":Color(.4,1,.6),"drain":Color(.6,.2,.8),"control":Color(.85,.4,1),"lightning":Color(.6,.85,1),"dematerialize":Color(.5,.5,1)}   # rotazione e spazzata: le clip di taglio più vicine
const REPLAY_PACE=.8
const REST_GRIP=["Riposo","In guardia","Camminata","Correre","Avanzare","Carica","Schivata","Sbilanciato","A terra","Rialzarsi"]
const MOVING=["advance","run","charge","roll","dodge","rise"]
const DEFENSIVE=["parry_l","parry_r","dodge","guard"]
const TEAL=Color("69cec1")
const RED=Color("e68078")

var game: BloodRules
var highlights: Array=[]
var selected=""
var focus_fighter=-1
var preview_facing=-1
var show_grid=false
var zoom=1.0
var hovered=""

var viewport: SubViewport
var camera: Camera3D
var overlay: MeshInstance3D
var minis={}               # indice combattente -> {root, model, ap, base, label, token}
var prev={}                # stato visivo precedente per indice
var queue: Array=[]        # passi da animare
var history: Array=[]      # passi già animati (per il replay)
var initial={}             # posizioni iniziali (per il replay)
var playing=false
var replaying=false
var yaw=0.55
var pitch=0.82
var dist=10.5
var follow=true          # la camera segue lo scontro finché non la sposti a mano
var target=Vector3.ZERO
var arena_texture=preload("res://assets/arena/arena.webp")

func _ready() -> void:
	stretch=true;mouse_filter=Control.MOUSE_FILTER_STOP;custom_minimum_size=Vector2(460,350)
	viewport=SubViewport.new();viewport.own_world_3d=true;viewport.msaa_3d=Viewport.MSAA_2X;add_child(viewport)
	var env=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("101b1c")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("c4d6dc");env.environment.ambient_light_energy=.7
	env.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC;viewport.add_child(env)
	for cfg in [[Vector3(-4,9,6),Color("fff0d0"),2.2,true],[Vector3(6,5,-3),Color("a8dce8"),1.0,false]]:
		var l=DirectionalLight3D.new();viewport.add_child(l);l.position=cfg[0];l.look_at(Vector3.ZERO);l.light_color=cfg[1];l.light_energy=cfg[2];l.shadow_enabled=cfg[3]
	viewport.add_child(_ground())
	overlay=MeshInstance3D.new();overlay.mesh=ImmediateMesh.new();var om=StandardMaterial3D.new();om.vertex_color_use_as_albedo=true;om.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;om.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;om.no_depth_test=false;overlay.material_override=om;viewport.add_child(overlay)
	camera=Camera3D.new();camera.fov=40;viewport.add_child(camera)
	_place_camera()

func _ground() -> MeshInstance3D:
	# L'immagine dell'arena ha le celle in pixel (x,y): X = (y-1368)·U, Z = (978-x)·U
	var w=2736.0*U;var h=1956.0*U
	var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_normal(Vector3.UP)
	var corners=[[Vector3(-w/2,0,-h/2),Vector2(1,0)],[Vector3(w/2,0,-h/2),Vector2(1,1)],[Vector3(w/2,0,h/2),Vector2(0,1)],[Vector3(-w/2,0,h/2),Vector2(0,0)]]
	for idx in [0,1,2,0,2,3]:
		st.set_uv(corners[idx][1]);st.add_vertex(corners[idx][0])
	var m=MeshInstance3D.new();m.mesh=st.commit()
	var mat=StandardMaterial3D.new();mat.albedo_texture=arena_texture;mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.cull_mode=BaseMaterial3D.CULL_DISABLED;m.material_override=mat  # come la mappa 2D
	return m

func _spot(i: int,k: String) -> Vector3:
	# due alleati nello stesso esagono d'ingresso (permesso dallo scenario): affiancati
	var mates=[]
	for j in game.state.fighters.size():
		var q=game.state.fighters[j]
		if q.cell==k and q.alive:mates.append(j)
	var c=cell_pos(k)
	if mates.size()<2 or not i in mates:return c
	var n=mates.size();var a=mates.find(i)
	return c+Vector3((a-(n-1)*.5)*.62/n*1.6,0,0)
func _shared(i: int) -> bool:
	var p=game.state.fighters[i]
	return p.cell!="" and game.state.fighters.any(func(q):return q!=p and q.cell==p.cell and q.alive)
func cell_pos(k: String) -> Vector3:
	var c=game.cells[k];return Vector3((float(c.y)-1368.0)*U,0,(978.0-float(c.x))*U)
static func facing_yaw(facing: int) -> float:
	var f=Vector2.UP.rotated(-PI/2+facing*PI/3);return atan2(f.x,f.y)

func fit() -> void:yaw=.55;pitch=.82;dist=10.5;zoom=1.0;follow=true;target=_action_center();_place_camera()
func fit_zoom() -> void:_place_camera()
func _action_center() -> Vector3:
	var pts=[]
	for i in minis:
		if minis[i].root.visible:pts.append(minis[i].root.position)
	if pts.is_empty():return Vector3.ZERO
	var c=Vector3.ZERO
	for q in pts:c+=q
	return c/pts.size()
func _action_spread() -> float:
	var c=_action_center();var r=0.0
	for i in minis:
		if minis[i].root.visible:r=maxf(r,minis[i].root.position.distance_to(c))
	return r
func _process(delta: float) -> void:
	if camera and is_visible_in_tree():
		for i in minis:minis[i].bar.global_basis=camera.global_basis
	if not follow or minis.is_empty() or not is_visible_in_tree():return
	target=target.lerp(_action_center()+Vector3(0,.45,0),clampf(delta*2.0,0,1))
	dist=lerpf(dist,clampf(4.2+_action_spread()*1.7,4.2,15.0),clampf(delta*1.5,0,1))
	# guarda lo scontro di fianco: perpendicolare alla linea fra i due combattenti più vicini
	var best=1e9;var axis=Vector3.ZERO;var keys=minis.keys()
	for a_i in keys.size():
		for b_i in range(a_i+1,keys.size()):
			var pa=minis[keys[a_i]].root;var pb=minis[keys[b_i]].root
			if not (pa.visible and pb.visible):continue
			var dd=pa.position.distance_to(pb.position)
			if dd<best and dd>.1:best=dd;axis=pb.position-pa.position
	if axis!=Vector3.ZERO:
		var side=atan2(axis.x,axis.z)+PI/2
		if absf(angle_difference(yaw,side))>PI/2:side+=PI
		yaw=lerp_angle(yaw,side,clampf(delta*.8,0,1))
	_place_camera()
func _place_camera() -> void:
	if camera==null:return
	camera.position=target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*dist/zoom
	camera.look_at(target)

# ---------------------------------------------------------------- miniature
func _exit_tree() -> void:Engine.time_scale=1.0
func _mini(i: int) -> Dictionary:
	if minis.has(i):return minis[i]
	var p=game.state.fighters[i];var d=game.definition(p)
	var root=Node3D.new();viewport.add_child(root)
	var team=TEAL if int(p.team)==0 else RED
	# basetta: esagono grande quanto la cella e allineato alla griglia; non ruota col facing.
	# Sui lati compaiono solo i colori della pedina giocata (rosso, verde, blu), negli stessi
	# lati in cui li ha la pedina rispetto al suo orientamento.
	var plate=MeshInstance3D.new();plate.mesh=_hex_plate(.04);root.add_child(plate)
	var pm=StandardMaterial3D.new();pm.albedo_color=Color("1d2628");pm.roughness=.8;plate.material_override=pm
	var sides=Node3D.new();root.add_child(sides)
	var pivot=Node3D.new();root.add_child(pivot)     # ruota col facing: figura e segno del fronte
	var notch=MeshInstance3D.new();var pr=PrismMesh.new();pr.size=Vector3(.16,.12,.02);notch.mesh=pr
	notch.rotation=Vector3(PI/2,0,0);notch.position=Vector3(0,.052,.4)   # punta verso +Z, il fronte dei modelli
	var nm=StandardMaterial3D.new();nm.albedo_color=team;nm.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;notch.material_override=nm;pivot.add_child(notch)
	var info={"root":root,"pivot":pivot,"sides":sides,"plate":plate,"model":null,"ap":null,"token":null}
	plate.visible=not clear_plates
	var path=MODELS.get(p.character,"")
	if path!="" and not ResourceLoader.exists(path):path=""   # modello non ancora pronto: pedina in piedi
	if path!="":
		var model=load(path).instantiate();model.scale=Vector3.ONE*.58;pivot.add_child(model);info.model=model  # ~1,1 m: proporzionata a un esagono da 1,2 m
		info.ap=_find_animation(model)
		var grip_rest=model.find_child("Arma",true,false);var grip_act=model.find_child("ArmaAzione",true,false)
		if info.ap and grip_rest and grip_act:   # bastone/tridente: dritto a riposo, testa in avanti negli incantesimi e nei colpi
			var sync_grip=func(n):
				var rest_pose=str(n) in REST_GRIP;grip_rest.visible=rest_pose;grip_act.visible=not rest_pose
			info.ap.animation_started.connect(sync_grip);sync_grip.call("Riposo")
		if p.character=="ziggy":   # lo spirito fluttua sopra la basetta
			model.position.y=.14
			var bob=create_tween().set_loops();bob.bind_node(model)
			bob.tween_property(model,"position:y",.24,1.3).set_trans(Tween.TRANS_SINE);bob.tween_property(model,"position:y",.14,1.3).set_trans(Tween.TRANS_SINE)
			var sway=create_tween().set_loops();sway.bind_node(model)   # le spire ondeggiano piano
			sway.tween_property(model,"rotation:y",.22,1.9).set_trans(Tween.TRANS_SINE);sway.tween_property(model,"rotation:y",-.22,1.9).set_trans(Tween.TRANS_SINE)
			info["spirit"]=true
		if info.ap:_extract_root_motion(info)
		for n in ["In guardia","Riposo","Avanzare","Correre","Carica"]:
			if info.ap and info.ap.has_animation(n):info.ap.get_animation(n).loop_mode=Animation.LOOP_LINEAR
		if info.ap:info.ap.play("In guardia")
	else:
		# personaggio senza modello 3D: pedina in piedi con il disegno della mossa corrente
		var s=Sprite3D.new();s.pixel_size=.0019;s.position.y=.47;s.billboard=BaseMaterial3D.BILLBOARD_FIXED_Y;s.shaded=false;pivot.add_child(s);info.token=s
	# barra di stato sopra la testa: nome e ferite (sempre rivolta alla camera)
	var bar=Node3D.new();bar.position.y=1.2+.1*(i%2);bar.scale=Vector3.ONE*.6;root.add_child(bar);info.bar=bar   # nome e barre più discreti
	var label=Label3D.new();label.text=p.name;label.font_size=26;label.outline_size=8;label.modulate=team;label.position.y=.085;label.no_depth_test=true;label.render_priority=3;bar.add_child(label);info.label=label
	var back=MeshInstance3D.new();var bq=QuadMesh.new();bq.size=Vector2(.64,.075);back.mesh=bq
	var bk=StandardMaterial3D.new();bk.albedo_color=Color(0,0,0,.75);bk.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;bk.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;bk.no_depth_test=true;bk.render_priority=1;back.material_override=bk;bar.add_child(back)
	var fill=MeshInstance3D.new();var fq=QuadMesh.new();fq.size=Vector2(.6,.05);fill.mesh=fq;fill.position.z=.001
	var fm=StandardMaterial3D.new();fm.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;fm.no_depth_test=true;fm.render_priority=2;fill.material_override=fm;bar.add_child(fill);info.fill=fill;info.fill_mat=fm
	# barra della fatica subito sotto quella della vita (piena a 10 punti di fatica)
	var back2=MeshInstance3D.new();var bq2=QuadMesh.new();bq2.size=Vector2(.64,.05);back2.mesh=bq2;back2.position.y=-.068;back2.material_override=bk;bar.add_child(back2)
	var tired=MeshInstance3D.new();var tq=QuadMesh.new();tq.size=Vector2(.6,.03);tired.mesh=tq;tired.position=Vector3(0,-.068,.001)
	var tm=StandardMaterial3D.new();tm.albedo_color=Color("b48cff");tm.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;tm.no_depth_test=true;tm.render_priority=2;tired.material_override=tm;bar.add_child(tired);info.tired=tired
	minis[i]=info;return info

const FATIGUE_FULL=10.0
func _set_status(i: int,hp: int,max_hp: int,alive: bool,fatigue:=-1) -> void:
	var info=minis[i];var p=game.state.fighters[i]
	if fatigue<0:fatigue=int(p.fatigue)+int(p.permanent)
	var t=clampf(fatigue/FATIGUE_FULL,0,1)
	info.tired.scale.x=maxf(t,.001);info.tired.position.x=-.3*(1.0-t);info.tired.visible=alive and t>0
	info.label.text=p.name+("  †" if not alive else "")
	var f=clampf(float(hp)/maxf(1.0,max_hp),0,1)
	info.fill.scale.x=maxf(f,.001);info.fill.position.x=-.3*(1.0-f);info.fill.visible=alive and f>0
	info.fill_mat.albedo_color=Color("d9534f").lerp(Color("f0c040"),clampf(f*2,0,1)) if f<.5 else Color("f0c040").lerp(Color("5fd068"),(f-.5)*2)
func token_color(m: Dictionary) -> Color:
	if m.get("attack")!=null:return Color("ff4a3d")            # attacco: rosso
	if not m.get("blue",[]).is_empty():return Color("3d8bff")   # difesa: blu
	if not m.get("green",[]).is_empty():return Color("3ddc6a")  # movimento: verde
	return Color("8f9a9e")
const SIDE_COLORS=[["red",Color("ff4a3d")],["green",Color("3ddc6a")],["blue",Color("3d8bff")]]
var _shots_seen=0
var _dir3=[]               # direzione 3D verso la cella vicina in ciascuna delle 6 direzioni delle regole
func _directions() -> Array:
	if _dir3.is_empty():
		for k in game.cells:   # una cella con tutti e sei i vicini
			var ok=true
			for d in 6:ok=ok and game.cells.has(BloodRules.neighbor(k,d))
			if ok:
				for d in 6:_dir3.append((cell_pos(BloodRules.neighbor(k,d))-cell_pos(k)).normalized())
				break
	return _dir3
func _edge(d: int) -> int:
	# indice del lato dell'esagono (fra i vertici s e s+1) rivolto verso la direzione d
	var best=-1.0;var e=0
	for s in 6:
		var mid=(_corner(s)+_corner(s+1)).normalized().dot(_directions()[d])
		if mid>best:best=mid;e=s
	return e
func _hex_plate(h: float) -> ArrayMesh:
	var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in 6:
		var a=_corner(s);var b=_corner(s+1)
		st.set_normal(Vector3.UP);st.add_vertex(Vector3(0,h,0));st.add_vertex(a+Vector3(0,h,0));st.add_vertex(b+Vector3(0,h,0))
		var n=((a+b)*.5).normalized()
		st.set_normal(n);st.add_vertex(a);st.add_vertex(b);st.add_vertex(b+Vector3(0,h,0))
		st.set_normal(n);st.add_vertex(a);st.add_vertex(b+Vector3(0,h,0));st.add_vertex(a+Vector3(0,h,0))
	return st.commit()
func _set_rim(i: int,move_id: String,facing:=-1) -> void:
	var p=game.state.fighters[i];var m=game.definition(p).moves.get(move_id,{})
	if facing<0:facing=int(p.facing)
	var sides: Node3D=minis[i].sides
	for c in sides.get_children():c.queue_free()
	if _directions().size()<6:return
	var used={}
	for sc in SIDE_COLORS:
		for rel in m.get(sc[0],[]):
			var d=posmod(facing+int(rel),6);var e=_edge(d);var layer=used.get(e,0);used[e]=layer+1
			var a=_corner(e);var b=_corner(e+1);var inset=1.0-.075*layer
			var bar=MeshInstance3D.new();var bx=BoxMesh.new();bx.size=Vector3((b-a).length()*.9*inset,.05,.06);bar.mesh=bx
			var mid=(a+b)*.5*inset-((a+b)*.5).normalized()*.035
			bar.position=mid+Vector3(0,.035,0);bar.rotation.y=atan2(-(b-a).z,(b-a).x)
			var mat=StandardMaterial3D.new();mat.albedo_color=sc[1];mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;bar.material_override=mat
			sides.add_child(bar)
# --- Movimento senza pattinamento ------------------------------------------------
# Le clip Meshy spostano il bacino (affondo, calcio, carica, capriola fino a 2,7 m):
# la figura usciva dalla basetta e poi rientrava di scatto. Al caricamento tolgo lo
# spostamento orizzontale del bacino da tutte le clip (la figura resta centrata sulla
# basetta) e lo conservo come profilo: quando la miniatura cambia cella si sposta
# l'intera miniatura seguendo quel profilo, oppure, per camminata e corsa (clip sul
# posto), alla velocità reale dei piedi misurata in Blender.
const ROOT_MOTION=["Carica","Rotolare"]   # clip che avanzano davvero: la miniatura segue il loro tragitto
const STEP_SPEED={"Avanzare":.72,"Camminata":1.50,"Correre":3.49}   # velocità dei piedi / altezza del bacino (1/s)
var _motion={}             # id dell'Animation -> {"net": Vector3, "times": PackedFloat32Array, "prog": PackedFloat32Array}
func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:return n
	for c in n.get_children():
		var f=_find_skeleton(c)
		if f:return f
	return null
func _extract_root_motion(info: Dictionary) -> void:
	var skel=_find_skeleton(info.model)
	if skel==null:return
	var hips=skel.find_bone("Hips")
	if hips<0:return
	var M: Basis=info.root.global_transform.basis.inverse()*skel.global_transform.basis   # spazio scheletro -> spazio miniatura
	info.hips_h=(M*skel.get_bone_global_rest(hips).origin).y
	for name in info.ap.get_animation_list():
		var anim=info.ap.get_animation(name)
		var key=anim.get_instance_id()
		if _motion.has(key):continue
		var m={"net":Vector3.ZERO,"times":PackedFloat32Array(),"prog":PackedFloat32Array()};_motion[key]=m
		for t in anim.get_track_count():
			if anim.track_get_type(t)!=Animation.TYPE_POSITION_3D or not str(anim.track_get_path(t)).ends_with(":Hips"):continue
			var n=anim.track_get_key_count(t)
			if n<2:break
			var v0: Vector3=anim.track_get_key_value(t,0)
			var rest_o: Vector3=skel.get_bone_rest(hips).origin
			var deltas=[]
			for k in n:
				var v: Vector3=anim.track_get_key_value(t,k)
				var d: Vector3=M*(v-v0);d.y=0;deltas.append(d)
				var c: Vector3=M*(v-rest_o);c.y=0
				anim.track_set_key_value(t,k,v-M.inverse()*c)       # bacino sempre sopra il centro della basetta
			m.net=deltas[n-1]
			var dir=m.net.normalized();var best=0.0
			for k in n:
				best=maxf(best,clampf(deltas[k].dot(dir)/maxf(m.net.length(),.001),0,1))  # avanzamento monotono 0..1
				m.times.append(anim.track_get_key_time(t,k));m.prog.append(best)
			break
func _progress(m: Dictionary,time: float) -> float:
	var ts: PackedFloat32Array=m.times
	if ts.is_empty():return 0.0
	var i=ts.bsearch(time)
	if i<=0:return m.prog[0]
	if i>=ts.size():return 1.0
	var a=(time-ts[i-1])/maxf(ts[i]-ts[i-1],.0001)
	return lerpf(m.prog[i-1],m.prog[i],a)
func _find_animation(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:return n
	for c in n.get_children():
		var f=_find_animation(c)
		if f:return f
	return null

func _clip_for(i: int,id: String,bow: bool) -> String:
	# arcieri: in modalità arco le clip "… arco" (guardia, avanzata, corsa, sbilanciato)
	var base=CLIP.get(id,"In guardia")
	var info=minis.get(i,{})
	if bow and info.get("ap")!=null and info.ap.has_animation(base+" arco"):return base+" arco"
	return base
func _view(p: Dictionary) -> Dictionary:
	return {"cell":p.cell,"facing":int(p.facing),"current":p.current,"done":p.done,"hp":int(p.hp),"unbalanced":p.unbalanced,"down":p.down,"alive":p.alive,"team":int(p.team),"character":p.character}

# ---------------------------------------------------------------- sincronizzazione
func copy_from(b) -> void:
	highlights=b.highlights;selected=b.selected;focus_fighter=b.focus_fighter;preview_facing=b.preview_facing;show_grid=b.show_grid
	sync()

func sync() -> void:
	if game==null or game.state.is_empty() or replaying:return
	var step=[]   # tracce del passo: {i, clip, from, to, yaw, delay}
	var actors=[];var victims=[]
	for i in game.state.fighters.size():
		var p=game.state.fighters[i];var now=_view(p)
		if p.cell=="" or not game.cells.has(p.cell):prev[i]=now;continue
		var info=_mini(i)
		if not prev.has(i) or prev[i].cell=="":
			info.root.position=_spot(i,p.cell);info.pivot.rotation.y=facing_yaw(int(p.facing));_token(i)
			if not initial.has(i):initial[i]=now
			prev[i]=now;continue
		var was=prev[i]
		if now.done and not was.done and now.alive:actors.append(i)
		elif now.cell!=was.cell or now.facing!=was.facing:actors.append(i)
		if now.hp<was.hp or (now.unbalanced and not was.unbalanced) or (now.down and not was.down) or (was.alive and not now.alive):victims.append(i)
		elif was.down and not now.down and not i in actors:actors.append(i)
	for i in actors:
		var p=game.state.fighters[i];var was=prev[i];var id=p.current
		if i in victims and game.move(p).get("attack")==null and not id in MOVING:continue
		var track={"i":i,"clip":_clip_for(i,id,bool(p.get("bow",false))),"bow":bool(p.get("bow",false)),"loaded":bool(p.get("loaded",false)) or id=="shoot","from":_spot(i,was.cell),"to":_spot(i,p.cell),"yaw":facing_yaw(int(p.facing)),"facing":int(p.facing),"delay":0.0,"move":id,"strike":game.move(p).get("attack")!=null}
		if SPELL_FX.has(id):track["targets"]=victims.filter(func(v):return v!=i)
		if id=="shoot" and int(game.state.get("shots",0))>_shots_seen:
			_shots_seen=int(game.state.get("shots",0))
			var v=int(game.state.get("last_shot",{}).get("victim",-1))
			track["arrow"]={"victim":v,"hit":v>=0 and v in victims and int(game.state.fighters[v].hp)<int(prev.get(v,{}).get("hp",0))}
		step.append(track)
		# il difensore di fronte mostra la sua pedina difensiva mentre arriva il colpo
		if track.strike:
			var front=game.at(BloodRules.neighbor(p.cell,int(p.facing)),i)
			if front!=-1 and not front in victims and game.state.fighters[front].current in DEFENSIVE and minis.has(front):
				step.append({"i":front,"clip":CLIP[game.state.fighters[front].current],"from":cell_pos(game.state.fighters[front].cell),"to":cell_pos(game.state.fighters[front].cell),"yaw":facing_yaw(int(game.state.fighters[front].facing)),"facing":int(game.state.fighters[front].facing),"delay":.1,"move":game.state.fighters[front].current,"strike":false})
	var strike_delay=0.0
	for t in step:
		if t.get("strike",false) and minis[t.i].ap:strike_delay=maxf(strike_delay,minis[t.i].ap.get_animation(t.clip).length*.45)
	for i in victims:
		var p=game.state.fighters[i]
		var clip="A terra" if (p.down or not p.alive) else _clip_for(i,"unbalanced",bool(p.get("bow",false)))
		var moved=step.any(func(t):return t.get("i",-1)==i)
		if not moved and prev[i].cell!=p.cell:
			# si è spostato ma la mossa corrente è già cambiata (es. sbilanciato durante lo sprint):
			# prima il movimento con la mossa che aveva, poi la reazione sul posto
			var was_move: String=prev[i].current if CLIP.has(prev[i].current) and prev[i].current in MOVING else "run"
			step.append({"i":i,"clip":CLIP[was_move],"from":cell_pos(prev[i].cell),"to":cell_pos(p.cell),"yaw":facing_yaw(int(p.facing)),"facing":int(p.facing),"delay":0.0,"move":was_move,"strike":false})
			moved=true
		# chi ha anche un suo movimento in questo passo prima lo completa, poi reagisce sul posto
		step.append({"i":i,"clip":clip,"from":cell_pos(p.cell if moved else prev[i].cell),"to":cell_pos(p.cell),"yaw":facing_yaw(int(p.facing)),"facing":int(p.facing),"delay":strike_delay,"after":moved,"move":"down" if clip=="A terra" else "unbalanced","strike":false,"hit":prev[i].hp-int(p.hp),"stay":p.down or not p.alive,"dead":not p.alive})
	for i in game.state.fighters.size():
		if game.state.fighters[i].cell!="":prev[i]=_view(game.state.fighters[i])
	if not step.is_empty():
		var labels={}   # etichette dopo questo passo, per il replay
		for i in minis:
			var q=game.state.fighters[i];labels[i]=[int(q.hp),int(q.max_hp),q.alive]
		step.append({"labels":labels,"turn":int(game.state.get("turn",0)),"effects":game.state.effects.duplicate(true)})
		if is_visible_in_tree():
			queue.append(step)
			if not playing:_play_queue()
		else:history.append(step)   # mappa 3D nascosta: registro per il replay, senza animare
	_draw_overlay()
	_refresh_tokens()

# --- Replay salvato insieme alla partita ------------------------------------------
func _v3(v): return [v.x,v.y,v.z] if v is Vector3 else v
func export_replay() -> Dictionary:
	var h=[]
	for step in history:
		var st=[]
		for t in step:
			var c={}
			for k in t:c[k]=_v3(t[k])
			if t.has("labels"):
				var lb={}
				for i in t.labels:lb[str(i)]=t.labels[i]
				c["labels"]=lb
			st.append(c)
		h.append(st)
	var ini={}
	for i in initial:ini[str(i)]=initial[i]
	return {"history":h,"initial":ini}
func import_replay(d: Dictionary) -> void:
	history=[];initial={}
	for i in d.get("initial",{}):initial[int(i)]=d.initial[i]
	for st in d.get("history",[]):
		var step=[]
		for t in st:
			var c={}
			for k in t:
				var v=t[k]
				c[k]=Vector3(v[0],v[1],v[2]) if k in ["from","to"] else v
			for k in ["i","facing","hit","turn"]:
				if c.has(k):c[k]=int(c[k])                     # il JSON restituisce numeri decimali
			if c.has("arrow"):c.arrow={"victim":int(c.arrow.victim),"hit":bool(c.arrow.hit)}
			if c.has("labels"):
				var lb={}
				for i in t.labels:
					var a=t.labels[i];lb[int(i)]=[int(a[0]),int(a[1]),bool(a[2]),int(a[3]) if a.size()>3 else -1]
				c.labels=lb
			step.append(c)
		history.append(step)
func busy() -> bool:return playing or not queue.is_empty()

func _token(i: int) -> void:
	var info=minis[i]
	if info.token:info.token.texture=load(game.move(game.state.fighters[i]).get("texture","res://assets/tokens/effect_wall.webp"))
func _refresh_tokens() -> void:
	for i in minis:
		var p=game.state.fighters[i];var info=minis[i]
		if not replaying:
			_set_status(i,int(p.hp),int(p.max_hp),p.alive)
			if not playing:_set_rim(i,p.current)
		info.root.visible=p.cell!=""
		if not playing:
			if info.token:_token(i)
			_set_gear(i,bool(p.get("bow",false)),bool(p.get("loaded",false)))
			if p.cell!="":info.root.position=_spot(i,p.cell)
			var sm=.5 if _shared(i) else 1.0                       # basette ridotte quando l'esagono è condiviso
			info.plate.scale=Vector3(sm,1,sm);info.sides.scale=Vector3(sm,1,sm)
			if info.ap and p.down and info.ap.current_animation!="A terra":info.ap.play("A terra",0.0);info.ap.seek(info.ap.get_animation("A terra").length-.05,true)
			var f=int(p.facing)
			if i==focus_fighter and preview_facing>=0:f=preview_facing
			info.pivot.rotation.y=lerp_angle(info.pivot.rotation.y,facing_yaw(f),1.0)

# ---------------------------------------------------------------- riproduzione
func _play_queue() -> void:
	playing=true
	while not queue.is_empty():
		var step=queue.pop_front();history.append(step)
		await _play_step(step,false)
	playing=false;_refresh_tokens()

func _play_step(step: Array,fluid: bool) -> void:
	var longest=0.0;var ends={}
	for pass_after in [false,true]:   # le reazioni "after" partono quando finisce il movimento dello stesso personaggio
		for t in step:
			if t.has("labels") or t.get("after",false)!=pass_after:continue
			var info=minis.get(t.i)
			if info==null:continue
			if pass_after:t.delay=maxf(t.delay,ends.get(t.i,0.0))
			var dur=_run_track(t,info,fluid)
			ends[t.i]=maxf(ends.get(t.i,0.0),t.delay+dur)
			longest=maxf(longest,t.delay+dur)
	await get_tree().create_timer(longest).timeout
	for t in step:
		if t.has("labels"):
			if t.has("effects"):_show_effects(t.effects)
			if fluid:
				for i in t.labels:
					if minis.has(i):_set_status(i,t.labels[i][0],t.labels[i][1],t.labels[i][2])
			continue
		var info=minis.get(t.i)
		if info and info.ap and not t.get("stay",false) and t.clip!="A terra":info.ap.play("In guardia",.25)

func _plan(t: Dictionary,info: Dictionary) -> Dictionary:
	# come verrà animata la traccia: modalità, durata naturale, ripetizioni
	var ap=info.ap;var pivot=info.pivot
	var anim: Animation=ap.get_animation(t.clip) if ap and ap.has_animation(t.clip) else null
	var length=anim.length if anim else 1.2
	if t.clip in ["In guardia","Avanzare","Correre","Carica"]:length=minf(length,1.6)
	length=minf(length,3.2)
	var turn=.22 if absf(angle_difference(pivot.rotation.y,t.yaw))>.05 else 0.0
	var dist=t.from.distance_to(t.to)
	var m=_motion.get(anim.get_instance_id(),{}) if anim else {}
	var mode="fermo"
	if dist>.05:
		if anim and STEP_SPEED.has(t.clip) and info.has("hips_h"):
			mode="passi";length=dist/(STEP_SPEED[t.clip]*info.hips_h)    # stessa velocità dei piedi
		elif not m.is_empty() and m.net.length()>.15 and t.clip in ROOT_MOTION:
			mode="profilo"                                                  # la clip avanza da sola
		else:
			mode="lineare"
	var loops=1
	if mode=="profilo":
		loops=maxi(1,roundi(dist/m.net.length()));length=anim.length*loops
	return {"anim":anim,"length":length,"turn":turn,"dist":dist,"m":m,"mode":mode,"loops":loops}
func _run_track(t: Dictionary,info: Dictionary,fluid: bool,forced:=-1.0) -> float:
	# forced: durata imposta al movimento (replay fluido: tutti arrivano insieme)
	var ap=info.ap;var root=info.root;var pivot=info.pivot
	var pl=_plan(t,info)
	if pl.mode=="lineare" and info.ap and info.ap.has_animation("Camminata") and not info.get("spirit",false) and not t.get("split",false) and not t.get("move","") in ["teleport","dematerialize"]:
		# si sposta con una clip che non cammina (es. Concentrarsi): prima cammina fino alla cella, poi la esegue lì
		var walk=t.duplicate();walk.clip="Camminata";walk.split=true;walk.move="advance";walk.strike=false
		for k in ["hit","arrow","targets","bow"]:walk.erase(k)
		var d1=_run_track(walk,info,fluid,forced)
		var act=t.duplicate();act.split=true;act.from=t.to;act.delay=t.delay+d1
		return d1+_run_track(act,info,fluid)
	var anim: Animation=pl.anim;var length: float=pl.length;var turn: float=pl.turn
	var dist: float=pl.dist;var m: Dictionary=pl.m;var mode: String=pl.mode;var loops: int=pl.loops
	var natural=length;var rate=1.0
	if forced>0 and mode!="fermo":rate=clampf(natural/forced,.35,2.5);length=forced
	if OS.get_environment("BM_DEBUG")=="1":print("TRACK ",game.state.fighters[t.i].character," ",t.clip," ",mode," dist %.2f len %.2f loops %d"%[dist,length,loops])
	var tw=create_tween()
	if t.delay>0:tw.tween_interval(t.delay)
	if turn>0:tw.tween_property(pivot,"rotation:y",pivot.rotation.y+angle_difference(pivot.rotation.y,t.yaw),turn)
	tw.tween_callback(func():
		_set_rim(t.i,t.move,t.get("facing",-1))
		if anim:
			if mode=="passi" or mode=="profilo":anim.loop_mode=Animation.LOOP_LINEAR
			ap.play(t.clip,.12 if fluid else .18);ap.speed_scale=rate
		if t.has("bow"):_set_gear(t.i,t.bow,t.get("loaded",false))
		if t.has("arrow"):_shoot(t,info,anim.length/rate if anim else 1.0)
		if SPELL_FX.has(t.get("move","")):_cast_fx(t,info,anim.length/rate if anim else 1.0)
		if info.get("spirit",false):_spirit_move(t,info)
		_sound_track(t,info,length,mode)
		if t.get("hit",0)>0:
			_float(root.position,"-%d" % t.hit)
			if blood:_bleed(root.position,int(t.hit)))
	if mode=="fermo":
		tw.tween_interval(length)
	elif t.get("move","") in ["teleport","dematerialize"]:
		# sparisce in un lampo e ricompare nella cella di arrivo
		var to3: Vector3=t.to
		tw.tween_interval(length*.35);tw.tween_property(pivot,"scale",Vector3(.05,1.6,.05),.18)
		tw.tween_callback(func():root.position=to3);tw.tween_property(pivot,"scale",Vector3.ONE,.22)
		tw.tween_interval(maxf(length*.65-.4,.05))
	else:
		root.position=t.from
		var from: Vector3=t.from;var to: Vector3=t.to
		if mode=="profilo":
			var clip_len=anim.length
			tw.tween_method(func(x: float):
				var k=floorf(x/clip_len);var p=(k+_progress(m,x-k*clip_len))/loops
				root.position=from.lerp(to,minf(p,1.0)),0.0,natural,length)
		else:
			tw.tween_property(root,"position",to,length)
		if mode=="profilo" and anim and not t.clip in ["Carica"]:
			tw.tween_callback(func():anim.loop_mode=Animation.LOOP_NONE)
		# arrivato: smette di camminare e si mette in guardia (niente passi sul posto mentre aspetta)
		if ap and not t.get("stay",false):
			tw.tween_callback(func():
				if anim:anim.loop_mode=Animation.LOOP_NONE
				if ap.current_animation==t.clip and ap.has_animation("In guardia"):ap.play("In guardia",.2))
		if rate!=1.0 and ap:tw.tween_callback(func():ap.speed_scale=1.0)
	return turn+length

# --- Arcieri: arco o spada in mano, freccia in volo ---------------------------------
# Il modello contiene i nodi Arco (mano sinistra), ArcoSchiena, Spada e FrecciaIncoccata.
# In modalità arco l'arco è in mano (con la freccia incoccata se carico); in mischia la
# spada è in mano e l'arco a tracolla. Al tiro la freccia vola dall'arco al bersaglio:
# se fa danno resta conficcata nella miniatura, se manca si pianta a terra lì vicino.
var arrows: Array=[]
func _gear(info: Dictionary,name: String) -> Node3D:
	if info.get("model")==null:return null
	var key="gear_"+name
	if not info.has(key):info[key]=info.model.find_child(name,true,false)
	return info[key]
func _set_gear(i: int,bow: bool,loaded: bool) -> void:
	var info=minis.get(i,{})
	var hand=_gear(info,"Arco")
	if hand==null:return
	hand.visible=bow;_gear(info,"ArcoSchiena").visible=not bow
	var sw=_gear(info,"Spada")
	if sw:sw.visible=not bow
	var nock=_gear(info,"FrecciaIncoccata")
	if nock:nock.visible=bow and loaded
func clear_arrows() -> void:
	for a in arrows:
		if is_instance_valid(a):a.queue_free()
	arrows=[]
func _arrow_mesh() -> Node3D:
	var root=Node3D.new();var a=Node3D.new();a.scale=Vector3.ONE*.58;root.add_child(a)   # stessa scala delle miniature
	var shaft=MeshInstance3D.new();var c=CylinderMesh.new();c.top_radius=.006;c.bottom_radius=.006;c.height=.66;shaft.mesh=c;shaft.rotation.x=PI/2
	var wm=StandardMaterial3D.new();wm.albedo_color=Color("8a6a43");shaft.material_override=wm;a.add_child(shaft)
	var tip=MeshInstance3D.new();var cn=CylinderMesh.new();cn.top_radius=0;cn.bottom_radius=.014;cn.height=.05;tip.mesh=cn;tip.rotation.x=PI/2;tip.position.z=.35
	var tm=StandardMaterial3D.new();tm.albedo_color=Color("c9ccd0");tm.metallic=.8;tm.roughness=.3;tip.material_override=tm;a.add_child(tip)
	for k in 3:
		var f=MeshInstance3D.new();var q=QuadMesh.new();q.size=Vector2(.03,.08);f.mesh=q;f.position.z=-.28;f.rotation=Vector3(0,PI/2,k*TAU/3)
		var fm=StandardMaterial3D.new();fm.albedo_color=Color("e8e2d0");fm.cull_mode=BaseMaterial3D.CULL_DISABLED;f.material_override=fm;a.add_child(f)
	return root   # punta verso +Z
# la freccia conficcata segue l'osso più vicino al punto colpito (si muove col corpo)
func _stick_parent(victim: Dictionary,at: Vector3) -> Node3D:
	if victim.get("model")==null:return victim.pivot
	var found=victim.model.find_children("*","Skeleton3D",true,false)
	if found.is_empty():return victim.pivot
	var sk: Skeleton3D=found[0]
	var best=-1;var bd=1e9
	for b in sk.get_bone_count():
		var n=sk.get_bone_name(b).to_lower()
		if not ("spine" in n or "chest" in n or "hips" in n) or "arm" in n:continue
		var d=(sk.global_transform*sk.get_bone_global_pose(b).origin).distance_to(at)
		if d<bd:bd=d;best=b
	if best<0:return victim.pivot
	var ba=BoneAttachment3D.new();ba.bone_idx=best;sk.add_child(ba);ba.transform=sk.get_bone_global_pose(best)   # subito sull'osso, prima di agganciare
	return ba
func _shoot(t: Dictionary,info: Dictionary,clip_time: float) -> void:
	var shooter=info.root;var v=int(t.arrow.victim);var hit=bool(t.arrow.hit)
	var release=clip_time*.55
	# l'arciere si gira verso il bersaglio per mirare, poi torna al suo orientamento
	var aim_at=minis.get(v,{})
	if not aim_at.is_empty() and info.get("model")!=null:   # ruota solo la figura, non il segno del fronte
		var d: Vector3=aim_at.root.global_position-shooter.global_position
		if Vector2(d.x,d.z).length()>.01:
			var fig: Node3D=info.model
			var yaw=wrapf(atan2(d.x,d.z)-info.pivot.global_rotation.y,-PI,PI)
			var tw0=create_tween();tw0.tween_property(fig,"rotation:y",yaw,minf(.25,release*.5))
			tw0.tween_interval(maxf(clip_time-minf(.25,release*.5)-.2,.05));tw0.tween_property(fig,"rotation:y",0.0,.2)
	await get_tree().create_timer(release).timeout
	var nock=_gear(info,"FrecciaIncoccata")
	var from: Vector3=nock.global_position if nock and nock.is_visible_in_tree() else shooter.global_position+Vector3(0,.8,0)
	if nock:nock.visible=false
	var target: Vector3
	var victim=minis.get(v,{})
	if victim.is_empty():return
	if hit:target=victim.root.global_position+Vector3(randf_range(-.05,.05),randf_range(.55,.8),randf_range(-.05,.05))
	else:
		var off=Vector3(randf_range(-.45,.45),0,randf_range(-.45,.45))
		target=victim.root.global_position+off+Vector3(0,.02,0)
	var a=_arrow_mesh();viewport.add_child(a);a.global_position=from;arrows.append(a)
	var dur=clampf(from.distance_to(target)/14.0,.12,.6)
	var tw=create_tween()
	tw.tween_method(func(x: float):
		var p=from.lerp(target,x)+Vector3(0,sin(x*PI)*.18*from.distance_to(target)/4.0,0)
		var ahead=from.lerp(target,minf(x+.02,1.0))+Vector3(0,sin(minf(x+.02,1.0)*PI)*.18*from.distance_to(target)/4.0,0)
		a.global_position=p
		if ahead.distance_to(p)>.001:a.look_at(ahead,Vector3.UP,true),0.0,1.0,dur)
	tw.tween_callback(func():
		a.global_position=target-(-a.global_basis.z)*0.0
		_sfx("arrow_hit" if hit else "arrow_ground",target,0.0,-3.0)
		if hit and victim.has("pivot"):
			var gt=a.global_transform;a.get_parent().remove_child(a);_stick_parent(victim,target).add_child(a);a.global_transform=gt   # resta conficcata
			a.translate_object_local(Vector3(0,0,-.12))   # la punta resta dentro, l'asta fuori
		else:
			a.rotate_object_local(Vector3.RIGHT,randf_range(.2,.5)))   # piantata a terra, un po' inclinata
# --- Magie: lampo sul mago, sfera verso i bersagli, effetti che restano sulle celle ----
func _glow(color: Color,amount: int,radius: float) -> CPUParticles3D:
	var g=CPUParticles3D.new();g.one_shot=true;g.amount=amount;g.lifetime=.8;g.explosiveness=.85
	g.emission_shape=CPUParticles3D.EMISSION_SHAPE_SPHERE;g.emission_sphere_radius=radius;g.direction=Vector3.UP;g.spread=180
	g.initial_velocity_min=.2;g.initial_velocity_max=.9;g.gravity=Vector3(0,.6,0);g.scale_amount_min=.5;g.scale_amount_max=1.2
	var q=SphereMesh.new();q.radius=.025;q.height=.05;q.radial_segments=6;q.rings=3;g.mesh=q
	var m=StandardMaterial3D.new();m.albedo_color=color;m.emission_enabled=true;m.emission=color;m.emission_energy_multiplier=3.0
	m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;g.material_override=m
	return g
# Ziggynowskij non ha scheletro: si anima ruotando, pulsando e tremando
func _spirit_move(t: Dictionary,info: Dictionary) -> void:
	var fig: Node3D=info.pivot
	var mv=str(t.get("move",""))
	if not (SPELL_FX.has(mv) or t.get("hit",0)>0 or mv in ["unbalanced","float","advance"]):return
	var tw=create_tween()
	if SPELL_FX.has(t.get("move","")):          # incantesimo: vortice veloce e gonfiarsi
		tw.tween_property(fig,"scale",Vector3(1.18,1.1,1.18),.25).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(fig,"rotation:y",fig.rotation.y+TAU,.7).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(fig,"scale",Vector3.ONE,.3)
	elif t.get("hit",0)>0 or t.get("move","")=="unbalanced":   # colpito: si contrae e trema
		tw.tween_property(fig,"scale",Vector3(.85,.92,.85),.12)
		for k in 4:tw.tween_property(fig,"rotation:z",(.12 if k%2==0 else -.12),.06)
		tw.tween_property(fig,"rotation:z",0.0,.08);tw.tween_property(fig,"scale",Vector3.ONE,.2)
	elif t.get("move","") in ["float","advance"]:     # si allunga nella direzione del volo
		tw.tween_property(fig,"scale",Vector3(.92,1.12,.92),.3);tw.tween_interval(.4);tw.tween_property(fig,"scale",Vector3.ONE,.3)
func _cast_fx(t: Dictionary,info: Dictionary,clip_time: float) -> void:
	var color: Color=SPELL_FX[t.move];var caster: Node3D=info.root
	await get_tree().create_timer(clip_time*.45).timeout
	if not is_instance_valid(caster):return
	var burst=_glow(color,40,.25);viewport.add_child(burst);burst.global_position=caster.global_position+Vector3(0,.75,0);burst.emitting=true
	get_tree().create_timer(1.5).timeout.connect(burst.queue_free)
	for v in t.get("targets",[]):
		var victim=minis.get(int(v),{})
		if victim.is_empty():continue
		var orb=MeshInstance3D.new();var sm=SphereMesh.new();sm.radius=.07;sm.height=.14;orb.mesh=sm
		var om=StandardMaterial3D.new();om.albedo_color=color;om.emission_enabled=true;om.emission=color;om.emission_energy_multiplier=4.0;om.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;orb.material_override=om
		viewport.add_child(orb);var from=caster.global_position+Vector3(0,.8,0);var to=victim.root.global_position+Vector3(0,.65,0);orb.global_position=from
		var tw=create_tween();tw.tween_property(orb,"global_position",to,clampf(from.distance_to(to)/9.0,.12,.5))
		tw.tween_callback(func():
			var hit=_glow(color,30,.18);viewport.add_child(hit);hit.global_position=to;hit.emitting=true
			get_tree().create_timer(1.5).timeout.connect(hit.queue_free);orb.queue_free())
var effect_nodes: Array=[]
func _show_effects(list) -> void:
	for n in effect_nodes:
		if is_instance_valid(n):n.queue_free()
	effect_nodes=[]
	if list==null:return
	for e in list:
		var k=str(e.get("cell",""))
		if not game.cells.has(k):continue
		var kind=str(e.get("kind",""));var root=Node3D.new();viewport.add_child(root);root.position=cell_pos(k);effect_nodes.append(root)
		var tex=load("res://assets/tokens/effect_"+("fire" if kind=="livingfire" else kind)+".webp") if ResourceLoader.exists("res://assets/tokens/effect_"+("fire" if kind=="livingfire" else kind)+".webp") else null
		if tex:
			var q=MeshInstance3D.new();var pm=PlaneMesh.new();pm.size=Vector2(1.0,1.0);q.mesh=pm;q.position.y=.075
			var mm=StandardMaterial3D.new();mm.albedo_texture=tex;mm.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mm.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;q.material_override=mm;root.add_child(q)
		var col={"wall":Color(1,.4,.1),"livingfire":Color(1,.55,.1),"vortex":Color(.5,.8,1),"abyss":Color(.35,.1,.5)}.get(kind,Color(1,1,1))
		var f=CPUParticles3D.new();f.amount=36;f.lifetime=1.1;f.emission_shape=CPUParticles3D.EMISSION_SHAPE_BOX;f.emission_box_extents=Vector3(.35,.02,.35)
		f.direction=Vector3.UP;f.spread=12;f.initial_velocity_min=.4;f.initial_velocity_max=1.1 if kind!="abyss" else .3
		f.gravity=Vector3(0,.3,0) if kind!="abyss" else Vector3(0,-1.2,0);f.scale_amount_min=.6;f.scale_amount_max=1.6
		if kind=="vortex":f.tangential_accel_min=2.0;f.tangential_accel_max=3.0
		var sm=SphereMesh.new();sm.radius=.03;sm.height=.06;sm.radial_segments=6;sm.rings=3;f.mesh=sm
		var fm=StandardMaterial3D.new();fm.albedo_color=col;fm.emission_enabled=true;fm.emission=col;fm.emission_energy_multiplier=2.5;fm.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;f.material_override=fm
		f.position.y=.1;root.add_child(f);f.emitting=true
# --- Suoni (opzione): armi, passi, urla, magie -----------------------------------
# I file sono in assets/audio (sintetizzati da tools/audio/synth.py): nome_1, nome_2, ...
var sound=true
var _sfx_cache={}
const FEMALE=["kylvia","sanguinaria","shaara","shannon"]
func _variants(name: String) -> Array:
	if not _sfx_cache.has(name):
		var list=[]
		for k in range(1,6):
			for ext in [".ogg",".wav"]:
				var path="res://assets/audio/%s_%d%s"%[name,k,ext]
				if ResourceLoader.exists(path):list.append(load(path));break
		_sfx_cache[name]=list
	return _sfx_cache[name]
func _sfx(name: String,at: Vector3,delay:=0.0,db:=0.0,pitch:=1.0) -> void:
	if not sound:return
	var list=_variants(name)
	if list.is_empty():return
	if delay>0:await get_tree().create_timer(delay).timeout
	var p=AudioStreamPlayer3D.new();p.stream=list[randi()%list.size()];p.volume_db=db;p.unit_size=6.0
	p.pitch_scale=pitch*randf_range(.94,1.06);viewport.add_child(p);p.global_position=at;p.play()
	p.finished.connect(p.queue_free)
func _voice(i: int) -> String:
	var c=str(game.state.fighters[i].character)
	if c=="thorn" or c=="golem":return "monster"
	if c=="ziggy":return "spirit"
	return "f" if c in FEMALE else "m"
func _sound_track(t: Dictionary,info: Dictionary,length: float,mode: String) -> void:
	if not sound or not minis.has(t.i):return
	var pos: Vector3=info.root.global_position+Vector3(0,.6,0);var v=_voice(t.i);var mv=str(t.get("move",""))
	if t.get("strike",false) and mv!="shoot":
		if v!="spirit":_sfx("grunt_"+("monster" if v=="monster" else v),pos,.05,-4.0)
		_sfx("swing",pos,length*.3,-3.0)
	if mv in ["parry_l","parry_r"]:_sfx("clash",pos,length*.35,-2.0)
	if mv=="load":_sfx("bow_draw",pos,.1,-6.0)
	if mv=="shoot":_sfx("bow_release",pos,length*.55,-2.0)
	if SPELL_FX.has(mv):
		_sfx("cast",pos,.1,-4.0)
		var kind={"firestaff":"fire","fireball":"fire","wall":"fire","livingfire":"fire","lightning":"lightning","shock":"lightning",
			"heal":"heal","shield":"heal","vortex":"wind","teleport":"wind","dematerialize":"wind","float":"wind"}.get(mv,"dark")
		_sfx("spell_"+kind,pos,length*.45,-3.0)
	var hit=int(t.get("hit",0))
	if hit>0:
		_sfx("hit",pos,t.get("delay",0.0)*0.0,-1.0)
		var dying=bool(t.get("dead",false))
		_sfx(("death_" if dying else "pain_")+v,pos,.08,-1.0 if dying else -3.0,1.0)
	if mv=="down" and t.get("stay",false):_sfx("fall",pos,.35,-2.0)
	if mode=="passi" or (mode=="lineare" and v!="spirit"):   # passi sulla sabbia lungo il tragitto
		var fast=t.clip in ["Correre","Carica"];var gap=.27 if fast else .42
		var n=mini(int(length/gap),24)
		for k in n:_sfx("step",info.root.global_position,k*gap+.05,-14.0 if not fast else -11.0)
# --- Sangue (opzione) -------------------------------------------------------------
# Uno sbuffo proporzionato alle ferite; poi le gocce cadono nell'esagono e restano lì.
var blood=false
var clear_plates=false        # basette trasparenti: restano solo i lati colorati
func set_clear_plates(v: bool) -> void:
	clear_plates=v
	for i in minis:minis[i].plate.visible=not v
var blood_marks: Array=[]      # macchie rimaste sull'arena (nodi)
var _splat_tex: Texture2D
func clear_blood() -> void:
	for m in blood_marks:
		if is_instance_valid(m):m.queue_free()
	blood_marks=[]
func _splat() -> Texture2D:
	if _splat_tex==null:
		var g=Gradient.new();g.set_color(0,Color(.42,0,.02,.95));g.set_color(1,Color(.3,0,.0,0));g.add_point(.55,Color(.38,0,.02,.8))
		var t=GradientTexture2D.new();t.gradient=g;t.fill=GradientTexture2D.FILL_RADIAL;t.fill_from=Vector2(.5,.5);t.fill_to=Vector2(.5,0);t.width=64;t.height=64
		_splat_tex=t
	return _splat_tex
func _bleed(at: Vector3,wounds: int) -> void:
	var n=clampi(wounds,1,12)
	var puff=CPUParticles3D.new();puff.one_shot=true;puff.amount=clampi(n*10,10,120);puff.lifetime=.9;puff.explosiveness=.92
	puff.position=at+Vector3(0,.75,0);puff.direction=Vector3(0,1,0);puff.spread=70;puff.initial_velocity_min=.6;puff.initial_velocity_max=1.4+n*.12
	puff.gravity=Vector3(0,-6.5,0);puff.scale_amount_min=.6;puff.scale_amount_max=1.4
	var drop=SphereMesh.new();drop.radius=.018;drop.height=.036;drop.radial_segments=6;drop.rings=3;puff.mesh=drop
	var dm=StandardMaterial3D.new();dm.albedo_color=Color(.55,0,.03);dm.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;puff.material_override=dm
	viewport.add_child(puff);puff.emitting=true
	get_tree().create_timer(1.6).timeout.connect(puff.queue_free)
	# le macchie compaiono quando le gocce toccano terra
	get_tree().create_timer(.45).timeout.connect(func():
		for k in mini(2+n,14):
			var q=MeshInstance3D.new();var pm=PlaneMesh.new();var sz=randf_range(.08,.16)+n*.012;pm.size=Vector2(sz,sz*randf_range(.6,1.0));q.mesh=pm
			var mm=StandardMaterial3D.new();mm.albedo_texture=_splat();mm.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mm.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;q.material_override=mm
			var r=randf_range(0,.44);var a=randf_range(0,TAU)
			q.position=Vector3(at.x+cos(a)*r,.046+k*.0004,at.z+sin(a)*r);q.rotation.y=randf_range(0,TAU)
			viewport.add_child(q);blood_marks.append(q))
func _float(at: Vector3,text: String) -> void:
	var l=Label3D.new();l.text=text;l.font_size=72;l.outline_size=14;l.modulate=Color("ff7b6b");l.billboard=BaseMaterial3D.BILLBOARD_ENABLED;l.no_depth_test=true
	viewport.add_child(l);l.position=at+Vector3(0,1.35,0)
	var t=create_tween();t.tween_property(l,"position:y",l.position.y+.7,1.2);t.parallel().tween_property(l,"modulate:a",0.0,1.2);t.tween_callback(l.queue_free)

func replay() -> void:
	# Riproduce tutto lo scontro dall'inizio, un passo dopo l'altro senza pause fra i turni.
	if replaying or history.is_empty():return
	replaying=true;Engine.time_scale=REPLAY_PACE   # il replay va un po' più piano della partita
	while playing:await get_tree().create_timer(.1).timeout   # aspetto che finisca la mossa in corso
	playing=true
	var final={}
	for i in minis:final[i]={"pos":minis[i].root.position,"yaw":minis[i].pivot.rotation.y}
	for i in initial:
		if not minis.has(i):continue
		minis[i].root.position=cell_pos(initial[i].cell);minis[i].pivot.rotation.y=facing_yaw(int(initial[i].facing));minis[i].root.visible=true
		if minis[i].ap:minis[i].ap.play("In guardia",0.0)
		var q=game.state.fighters[i];_set_status(i,int(q.max_hp),int(q.max_hp),true,0);_set_rim(i,initial[i].current,int(initial[i].facing))
	clear_blood();clear_arrows();_show_effects([])
	await get_tree().create_timer(.6).timeout
	# Replay fluido: per ogni turno tutti i movimenti partono insieme e arrivano insieme
	# (ognuno alla sua velocità), poi attacchi e difese; il turno dopo parte subito.
	var turns=[];var cur=[];var cur_turn=-1
	for step in history:
		var tn=-1
		for t in step:
			if t.has("labels"):tn=int(t.get("turn",-1))
		if (tn!=cur_turn or tn<0) and not cur.is_empty():turns.append(cur);cur=[]   # senza turno registrato: un passo alla volta
		cur_turn=tn;cur.append(step)
	if not cur.is_empty():turns.append(cur)
	for group in turns:
		await _play_turn(group)
	replaying=false;playing=false;Engine.time_scale=1.0;_refresh_tokens()

func _play_turn(group: Array) -> void:
	var moves={};var acts=[];var labels={}
	for step in group:
		for t in step:
			if t.has("labels"):labels=t.labels;continue
			if not minis.has(t.i):continue
			if t.from.distance_to(t.to)>.05 and not t.get("after",false):
				if moves.has(t.i):moves[t.i].to=t.to;moves[t.i].yaw=t.yaw;moves[t.i].facing=t.get("facing",-1)   # più spostamenti nello stesso turno: un solo tragitto
				else:moves[t.i]=t.duplicate();moves[t.i].delay=0.0
			else:acts.append(t)
	var span=0.0
	for i in moves:span=maxf(span,_plan(moves[i],minis[i]).length)
	var longest=0.0
	for i in moves:longest=maxf(longest,_run_track(moves[i],minis[i],true,span))
	if longest>0:await get_tree().create_timer(longest).timeout
	longest=0.0
	for t in acts:longest=maxf(longest,t.delay+_run_track(t,minis[t.i],true))
	if longest>0:await get_tree().create_timer(longest).timeout
	for step in group:
		for t in step:
			if t.has("effects"):_show_effects(t.effects)
	for i in labels:
		if minis.has(i):_set_status(i,labels[i][0],labels[i][1],labels[i][2],labels[i][3] if labels[i].size()>3 else -1)
	for t in moves.values()+acts:
		var info=minis.get(t.i)
		if info and info.ap and not t.get("stay",false) and t.clip!="A terra":info.ap.play("In guardia",.25)

# ---------------------------------------------------------------- celle evidenziate
func _draw_overlay() -> void:
	# disegnato sopra le basette (che sono alte 4 cm), così bersagli e selezione si vedono
	var im: ImmediateMesh=overlay.mesh;im.clear_surfaces()
	if game==null or game.state.is_empty():return
	var fills=[]
	if game.state.get("phase","")=="deploy":
		for k in game.cells:
			if game.cells[k].entry:fills.append([k,Color(.1,.8,.7,.22)])
	for k in highlights:fills.append([k,Color(.85,.68,.3,.3)])
	var lines=[]
	if show_grid:
		for k in game.cells:lines.append([k,Color(1,1,1,.85),.03])
	for k in highlights:lines.append([k,Color("e0ba77"),.045])
	if hovered!="":lines.append([hovered,Color(1,1,1,.85),.035])
	if selected!="":lines.append([selected,Color("fff0bf"),.06])
	if fills.is_empty() and lines.is_empty():return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in fills:
		var c=cell_pos(f[0])+Vector3(0,.062,0)
		for s in 6:
			for v in [c,c+_corner(s),c+_corner(s+1)]:im.surface_set_color(f[1]);im.surface_add_vertex(v)
	for l in lines:   # linee spesse: un nastro per lato (le linee GL sono larghe un pixel)
		var c=cell_pos(l[0])+Vector3(0,.07,0)
		for s in 6:
			var a=c+_corner(s);var b=c+_corner(s+1);var n=(b-a).cross(Vector3.UP).normalized()*l[2]*.5
			for v in [a-n,b-n,b+n,a-n,b+n,a+n]:im.surface_set_color(l[1]);im.surface_add_vertex(v)
	im.surface_end()
func _corner(s: int) -> Vector3:
	# stessi vertici dell'esagono 2D (punta in alto sullo schermo), riportati sul pavimento
	var a=s*PI/3-PI/2;return Vector3(cos(a),0,sin(a))*121.0*U*.97

func redraw() -> void:_draw_overlay();_refresh_tokens()

# ---------------------------------------------------------------- input
func _cell_at(pos: Vector2) -> String:
	var from=camera.project_ray_origin(pos);var dir=camera.project_ray_normal(pos)
	if absf(dir.y)<.0001:return ""
	var hit=from+dir*(-from.y/dir.y);var best=1e9;var cell=""
	for k in game.cells:
		var dd=cell_pos(k).distance_to(hit)
		if dd<best:best=dd;cell=k
	return cell if best<110.0*U else ""

var _press=Vector2.ZERO
var _dragging=false
func rotate_view(step: float) -> void:
	follow=false;yaw+=step;_place_camera()
func _gui_input(event: InputEvent) -> void:
	if game==null:return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_UP:zoom=clampf(zoom*1.1,.6,3.0);_place_camera();accept_event()
		elif event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_DOWN:zoom=clampf(zoom/1.1,.6,3.0);_place_camera();accept_event()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:_press=event.position;_dragging=false
			elif not _dragging and hovered!="":cell_clicked.emit(hovered)   # clic = rilascio senza trascinamento
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			follow=false
			yaw-=event.relative.x*.008;pitch=clampf(pitch+event.relative.y*.005,.25,1.45);_place_camera()
		elif event.button_mask & (MOUSE_BUTTON_MASK_LEFT|MOUSE_BUTTON_MASK_MIDDLE):
			if event.position.distance_to(_press)>6 or _dragging or event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
				_dragging=true;follow=false
				var right=camera.global_transform.basis.x;var fwd=Vector3(-sin(yaw),0,-cos(yaw))
				target+=(-right*event.relative.x+fwd*event.relative.y)*.012*dist/(zoom*10);_place_camera()
		var cell=_cell_at(event.position)
		if cell!=hovered:hovered=cell;_draw_overlay()
		tooltip_text=""
		if hovered!="" and not game.state.is_empty():
			var j=game.at(hovered)
			if j!=-1:
				var p=game.state.fighters[j];tooltip_text="%s · %s\n%d ferite rimaste · %d fatica" % [p.name,game.move(p).get("name",""),p.hp,p.fatigue]
