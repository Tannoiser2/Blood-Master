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
	"sanguinaria":"res://assets/models/sanguinaria/sanguinaria.glb","ziggy":"res://assets/models/ziggy/ziggy.glb",
	"golem":"res://assets/models/golem/golem.glb","skelos":"res://assets/models/skelos/skelos.glb","sketos":"res://assets/models/sketos/sketos.glb"}
const CLIP={"guard":"In guardia","advance":"Avanzare","run":"Correre","charge":"Carica","cleave":"Fendente",
	"left":"Taglio Dx","right":"Taglio Sx","thrust":"Affondo","kick":"Calcio","parry_l":"Parata Sx","parry_r":"Parata Dx",
	"dodge":"Schivata","roll":"Rotolare","unbalanced":"Sbilanciato","down":"A terra","rise":"Rialzarsi","again":"In guardia",
	"spin":"Taglio Dx","sweep":"Taglio Sx","meditate":"Riposo",
	"load":"Incoccare","shoot":"Tirare","weapon":"Riposo",
	# maghi: ogni incantesimo ha la sua clip, generata sul rig del mago
	"concentrate":"Concentrarsi","punch":"Pugno","float":"Fluttuare","pieces":"A terra",
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
const OWN_CLIP={"thrust":"Calcio volante","right":"Pugno Dx","left":"Pugno Sx","sweep":"Spazzata","meditate":"Meditazione"}
# gradi di torsione del modello per clip (positivo = verso la sinistra del personaggio)
# (le clip "Taglio" di Meshy colpiscono dal lato opposto al nome: "Taglio Dx" chiude a sinistra, quindi fa il taglio sinistro)
const TWIST={"Taglio Dx":32.0,"Taglio Sx":-32.0,"Parata Sx":38.0,"Parata Dx":-38.0,"Pugno Sx":25.0,"Pugno Dx":-25.0}
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
	viewport=SubViewport.new();viewport.own_world_3d=true;viewport.audio_listener_enable_3d=true;   # senza questo i suoni 3D del viewport non si sentono
	viewport.msaa_3d=Viewport.MSAA_2X;add_child(viewport)
	var env=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("140e0a")
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
	var pm=StandardMaterial3D.new();pm.albedo_color=team.darkened(.45);pm.roughness=.7;plate.material_override=pm   # basetta del colore della squadra
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
		if info.ap and p.character!="ziggy":
			# torsione del corpo: i colpi e le parate a sinistra si girano a sinistra, quelli a destra a destra,
			# così le due versioni si distinguono anche dall'alto; gli arcieri finiscono Incoccare in posa di tiro (vedi _rest_pose)
			var mdl: Node3D=model
			info.ap.animation_started.connect(func(n):
				var yaw=TWIST.get(n,0.0)
				var tw=create_tween();tw.tween_property(mdl,"rotation:y",deg_to_rad(yaw),.18 if yaw!=0.0 else .3).set_trans(Tween.TRANS_SINE))
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
	var bar=Node3D.new();bar.position.y=1.2+.1*(i%2);bar.scale=Vector3.ONE*.6;root.add_child(bar);info.bar=bar;bar.visible=labels_on   # nome e barre più discreti
	if p.character=="golem":bar.position.y+=.35
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
	info.bar.visible=labels_on and alive   # i caduti non coprono più gli altri nomi
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
var _spells_seen=0
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
	if id=="guard" and str(game.state.fighters[i].character)=="golem" and game.move(game.state.fighters[i]).get("attack")!=null and info.get("ap")!=null and info.ap.has_animation("Schianto"):
		return "Schianto"   # la guardia del golem è un colpo: pugni giù sul nemico
	if bow and info.get("ap")!=null and info.ap.has_animation(base+" arco"):return base+" arco"
	# mosse proprie del modello, se le ha (Shaara: calcio volante, pugni, spazzata, meditazione)
	var own=OWN_CLIP.get(id,"")
	if own!="" and info.get("ap")!=null and info.ap.has_animation(own):return own
	return base
func _view(p: Dictionary) -> Dictionary:
	return {"cell":p.cell,"facing":int(p.facing),"current":p.current,"done":p.done,"hp":int(p.hp),"unbalanced":p.unbalanced,"down":p.down,"alive":p.alive,"team":int(p.team),"character":p.character,"pieces":bool(p.get("pieces",false))}

# ---------------------------------------------------------------- sincronizzazione
func copy_from(b) -> void:
	highlights=b.highlights;selected=b.selected;focus_fighter=b.focus_fighter;preview_facing=b.preview_facing;show_grid=b.show_grid
	sync()

var scenery_root: Node3D;var scenery_key=""
var pickup_nodes={}          # zone di ristoro in scena: "cella|tipo" -> nodo
var initial_pickups=null     # come erano a inizio partita (per il replay)
# pozioni e mana (regola modificata): compaiono, e quando vengono presi esplodono in scintille e spariscono
func _show_pickups(list) -> void:
	if list==null:list=[]
	var want={}
	for o in list:
		if game.cells.has(str(o.cell)):want[str(o.cell)+"|"+str(o.kind)]=o
	for key in pickup_nodes.keys():
		if want.has(key):continue
		var n=pickup_nodes[key];pickup_nodes.erase(key)
		if not is_instance_valid(n):continue
		var col=Color(1,.35,.35) if key.ends_with("potion") else Color(.45,.8,1)
		_burst(n.global_position+Vector3(0,.2,0),col,70,.45);_sfx("heal",n.global_position,0.0,-4.0)
		var tw=create_tween();tw.tween_property(n,"scale",Vector3(1.4,.05,1.4),.35);tw.tween_callback(n.queue_free)
	for key in want:
		if pickup_nodes.has(key) and is_instance_valid(pickup_nodes[key]):continue
		var o=want[key];var n=Scenery3D.build(str(o.kind),str(o.cell).hash())
		n.position=cell_pos(str(o.cell));viewport.add_child(n);pickup_nodes[key]=n
		n.scale=Vector3.ONE*.05;create_tween().tween_property(n,"scale",Vector3.ONE,.5).set_trans(Tween.TRANS_BACK)
		var b=n.get_node_or_null("Bottiglia")
		if b:   # la boccetta galleggia e gira piano
			var bt=b.create_tween().set_loops();bt.tween_property(b,"position:y",.07,1.2).set_trans(Tween.TRANS_SINE);bt.tween_property(b,"position:y",.03,1.2).set_trans(Tween.TRANS_SINE)
			var rt=b.create_tween().set_loops();rt.tween_property(b,"rotation:y",TAU,6.0).from(0.0)
func _ensure_scenery() -> void:
	# gli elementi di scena (regola modificata) non cambiano durante la partita: si costruiscono una volta
	var obs: Array=game.state.get("obstacles",[]) if game!=null and not game.state.is_empty() else []
	var k=JSON.stringify(obs)
	if k==scenery_key:return
	scenery_key=k
	if scenery_root!=null and is_instance_valid(scenery_root):scenery_root.queue_free()
	scenery_root=Node3D.new();viewport.add_child(scenery_root)
	for o in obs:
		if not game.cells.has(str(o.cell)):continue
		var piece=Scenery3D.build(str(o.kind),str(o.cell).hash())
		piece.position=cell_pos(str(o.cell));piece.rotation.y=int(o.get("turn",0))*PI/3.0
		scenery_root.add_child(piece)
func sync() -> void:
	if game==null or game.state.is_empty():return
	_ensure_scenery()
	if initial_pickups==null and int(game.state.get("turn",0))<=1:initial_pickups=game.state.get("pickups",[]).duplicate(true)
	if replaying:return
	_ui_events()
	var step=[]   # tracce del passo: {i, clip, from, to, yaw, delay}
	var actors=[];var victims=[]
	for i in game.state.fighters.size():
		var p=game.state.fighters[i];var now=_view(p)
		if p.cell=="" or not game.cells.has(p.cell):prev[i]=now;continue
		var info=_mini(i)
		if not prev.has(i) or prev[i].cell=="":
			info.root.position=_spot(i,p.cell);info.pivot.rotation.y=facing_yaw(int(p.facing));_token(i)
			if int(p.get("owner",-1))>=0 and int(game.state.get("turn",0))>0:
				# evocato a partita in corso (golem): nel replay compare qui, non all'inizio
				step.append({"i":i,"clip":"In guardia","from":_spot(i,p.cell),"to":_spot(i,p.cell),"yaw":facing_yaw(int(p.facing)),"facing":int(p.facing),"delay":.4,"move":"summon","strike":false})
			elif not initial.has(i):initial[i]=now
			prev[i]=now;continue
		var was=prev[i]
		if now.done and not was.done and now.alive:actors.append(i)
		elif now.cell!=was.cell or now.facing!=was.facing:actors.append(i)
		var got_up=was.down and not now.down and now.alive   # si è rialzato da solo (con passi resta sbilanciato): non è un colpo subito
		if now.hp<was.hp or (now.unbalanced and not was.unbalanced and not got_up) or (now.down and not was.down) or (now.pieces and not was.get("pieces",false)) or (was.alive and not now.alive):victims.append(i)
		elif was.down and not now.down and not i in actors:actors.append(i)
	for i in game.state.fighters.size():
		if prev.has(i) and prev[i].get("pieces",false) and not game.state.fighters[i].get("pieces",false) and minis.has(i) and game.state.fighters[i].cell!="":
			step.append({"i":i,"clip":"Rialzarsi","from":cell_pos(game.state.fighters[i].cell),"to":cell_pos(game.state.fighters[i].cell),"yaw":facing_yaw(int(game.state.fighters[i].facing)),"facing":int(game.state.fighters[i].facing),"delay":.6,"move":"rise","strike":false,"rebuild":true})
			actors.erase(i)
	for i in actors:
		var p=game.state.fighters[i];var was=prev[i];var id=p.current
		if was.down and not p.down and p.alive:id="rise"   # Rialzarsi (anche quando la regola lo lascia sbilanciato)
		if i in victims and game.move(p).get("attack")==null and not id in MOVING:continue
		var track={"i":i,"clip":_clip_for(i,id,bool(p.get("bow",false))),"bow":bool(p.get("bow",false)),"loaded":bool(p.get("loaded",false)) or id=="shoot","from":_spot(i,was.cell),"to":_spot(i,p.cell),"yaw":facing_yaw(int(p.facing)),"facing":int(p.facing),"delay":0.0,"move":id,"strike":game.move(p).get("attack")!=null}
		if id=="roll" and p.down:   # rotola restando a terra: disteso, scivola fino alla nuova cella senza rialzarsi
			track.clip="A terra";track["lying"]=true;track["split"]=true;track["stay"]=true
		var route: Array=p.get("path",[])
		if route.size()>1 and str(route.back())==str(p.cell) and BloodRules.distance(str(was.cell),str(route[0]))==1:
			track["path"]=route.map(func(c):return _spot(i,str(c)))   # segue il percorso vero, esagono per esagono
		if SPELL_FX.has(id):
			track["targets"]=victims.filter(func(v):return v!=i)
			var ls=game.state.get("last_spell",{})
			if int(game.state.get("spells",0))>_spells_seen and int(ls.get("actor",-1))==i:
				_spells_seen=int(game.state.spells)
				if game.cells.has(str(ls.get("target",""))):track["spell_at"]=cell_pos(str(ls.target))
				for v in game.state.fighters.size():   # bersaglio non ferito ma colpito (sonno, controllo, peste...)
					if game.state.fighters[v].cell==str(ls.get("target","")) and v!=i and not v in track.targets:track.targets.append(v)
		if id=="shoot" and int(game.state.get("shots",0))>_shots_seen:
			_shots_seen=int(game.state.get("shots",0))
			var v=int(game.state.get("last_shot",{}).get("victim",-1))
			track["arrow"]={"victim":v,"hit":v>=0 and v in victims and int(game.state.fighters[v].hp)<int(prev.get(v,{}).get("hp",0))}
		step.append(track)
		# lancia: colpo a due esagoni (regola modificata), con la casella in mezzo libera
		if track.strike and game.hr("reach") and str(p.character) in BloodRules.SPEARS and id in ["thrust","charge"]:
			var mid=BloodRules.neighbor(p.cell,int(p.facing));var far=BloodRules.neighbor(mid,int(p.facing))
			if game.at(mid,i)==-1 and game.at(far,i)!=-1 and game.cells.has(far):track["reach"]=cell_pos(far)
		# il difensore di fronte mostra la sua pedina difensiva mentre arriva il colpo
		if track.strike:
			var front=game.at(BloodRules.neighbor(p.cell,int(p.facing)),i)
			var la=game.state.get("last_attack",{})
			if int(la.get("actor",-1))==i and int(la.get("victim",-1))>=0:front=int(la.victim)   # il vero bersaglio (anche di lato o a due esagoni)
			if front!=-1 and not front in victims and minis.has(front):
				var fq=game.state.fighters[front];var defensive=fq.current in DEFENSIVE
				var hit_at=minis[i].ap.get_animation(track.clip).length*.45 if minis[i].ap and minis[i].ap.has_animation(track.clip) else .5
				var word="SCHIVATA!" if fq.current in ["dodge","roll"] else ("PARATA!" if defensive else "MANCATO")
				step.append({"i":front,"clip":CLIP[fq.current] if defensive and CLIP.has(fq.current) else _clip_for(front,"parry_r" if minis[front].ap and minis[front].ap.has_animation("Parata Dx") else "guard",bool(fq.get("bow",false))),
					"from":cell_pos(fq.cell),"to":cell_pos(fq.cell),"yaw":facing_yaw(int(fq.facing)),"facing":int(fq.facing),"delay":maxf(.05,hit_at-.35),"move":fq.current,"strike":false,"parried":i,"parry_word":word})
	var strike_delay=0.0
	for t in step:
		if t.get("strike",false) and minis[t.i].ap:strike_delay=maxf(strike_delay,minis[t.i].ap.get_animation(t.clip).length*.45)
	for i in victims:
		var p=game.state.fighters[i]
		var clip="A terra" if (p.down or not p.alive or p.get("pieces",false)) else _clip_for(i,"unbalanced",bool(p.get("bow",false)))
		if not p.alive and minis.has(i) and minis[i].ap and minis[i].ap.has_animation("Morte"):clip="Morte"   # caduto per sempre: disteso sulla schiena
		var moved=step.any(func(t):return t.get("i",-1)==i)
		if not moved and prev[i].cell!=p.cell:
			# si è spostato ma la mossa corrente è già cambiata (es. sbilanciato durante lo sprint):
			# prima il movimento con la mossa che aveva, poi la reazione sul posto
			var was_move: String=prev[i].current if CLIP.has(prev[i].current) and prev[i].current in MOVING else "run"
			if (p.unbalanced or p.down) and not prev[i].current in MOVING:
				# spinto indietro dal colpo: barcolla all'indietro senza girarsi, dopo che il colpo è arrivato
				step.append({"i":i,"clip":_clip_for(i,"unbalanced",bool(p.get("bow",false))),"from":cell_pos(prev[i].cell),"to":cell_pos(p.cell),"yaw":facing_yaw(int(p.facing)),"facing":int(p.facing),"delay":strike_delay,"after_strike":true,"move":"unbalanced","strike":false,"pushed":true,"hit":prev[i].hp-int(p.hp)})
				step.append({"i":i,"clip":clip,"from":cell_pos(p.cell),"to":cell_pos(p.cell),"yaw":facing_yaw(int(p.facing)),"facing":int(p.facing),"delay":0.0,"after":true,"move":"down" if clip in ["A terra","Morte"] else "unbalanced","strike":false,"stay":p.down or not p.alive or p.get("pieces",false),"dead":not p.alive,"pieces":bool(p.get("pieces",false))})
				continue
			step.append({"i":i,"clip":CLIP[was_move],"from":cell_pos(prev[i].cell),"to":cell_pos(p.cell),"yaw":facing_yaw(int(p.facing)),"facing":int(p.facing),"delay":0.0,"move":was_move,"strike":false})
			moved=true
		# chi ha anche un suo movimento in questo passo prima lo completa, poi reagisce sul posto
		step.append({"i":i,"clip":clip,"from":cell_pos(p.cell if moved else prev[i].cell),"to":cell_pos(p.cell),"yaw":facing_yaw(int(p.facing)),"facing":int(p.facing),"delay":strike_delay,"after_strike":true,"after":moved,"move":"down" if clip in ["A terra","Morte"] else "unbalanced","strike":false,"hit":prev[i].hp-int(p.hp),"stay":p.down or not p.alive or p.get("pieces",false),"dead":not p.alive,"pieces":bool(p.get("pieces",false))})
	for i in game.state.fighters.size():
		if game.state.fighters[i].cell!="":prev[i]=_view(game.state.fighters[i])
	if not step.is_empty():
		var labels={}   # etichette dopo questo passo, per il replay
		for i in minis:
			var q=game.state.fighters[i];labels[i]=[int(q.hp),int(q.max_hp),q.alive]
		var states={}
		for i in minis:
			var q=game.state.fighters[i]
			states[i]={"burning":bool(q.get("burning",false)) and q.alive,"shield":bool(q.get("shield",false)) and q.alive,"plague":int(q.get("plague",-1))>=0 and q.alive,
				"control":int(q.get("controller_by",-1))>=0 and q.alive,"frog":bool(q.get("frog",false))}
		step.append({"labels":labels,"turn":int(game.state.get("turn",0)),"effects":game.state.effects.duplicate(true),"states":states,"pickups":game.state.get("pickups",[]).duplicate(true)})
		for tr in step:   # chi muore resta visibile finché la sua animazione non è finita
			if tr.get("dead",false) and minis.has(int(tr.get("i",-1))):minis[int(tr.i)]["dying"]=true
		if is_visible_in_tree():
			queue.append(step)
			if not playing:_play_queue()
		else:history.append(step)   # mappa 3D nascosta: registro per il replay, senza animare
	elif not playing:_show_pickups(game.state.get("pickups",[]))
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
			if t.has("states"):
				var sd={}
				for i in t.states:sd[str(i)]=t.states[i]
				c["states"]=sd
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
				c[k]=Vector3(v[0],v[1],v[2]) if k in ["from","to","spell_at"] else v
			for k in ["i","facing","hit","turn"]:
				if c.has(k):c[k]=int(c[k])                     # il JSON restituisce numeri decimali
			if c.has("arrow"):c.arrow={"victim":int(c.arrow.victim),"hit":bool(c.arrow.hit)}
			if c.has("targets"):c.targets=c.targets.map(func(x):return int(x))
			if c.has("states"):
				var sd={}
				for i in t.states:sd[int(i)]=t.states[i]
				c.states=sd
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
			_tired(i,int(p.fatigue)+int(p.permanent))
		# i caduti escono dall'arena (come la miniatura tolta dal tabellone): nessuno resta sopra un corpo
		var gone=not p.alive and (info.get("buried",false) or (not info.get("dying",false) and not replaying))
		info.root.visible=p.cell!="" and not gone and not (p.character=="golem" and not p.alive)   # il golem sbriciolato non torna
		if not playing:
			if info.token:_token(i)
			_set_gear(i,bool(p.get("bow",false)),bool(p.get("loaded",false)))
			if p.cell!="":info.root.position=_spot(i,p.cell)
			var sm=.5 if _shared(i) else 1.0                       # basette ridotte quando l'esagono è condiviso
			info.plate.scale=Vector3(sm,1,sm);info.sides.scale=Vector3(sm,1,sm)
			var lie="Morte" if not p.alive and info.ap and info.ap.has_animation("Morte") else "A terra"
			if info.ap and (p.down or not p.alive) and info.ap.assigned_animation!=lie:info.ap.play(lie,0.0);info.ap.seek(info.ap.get_animation(lie).length-.05,true)
			var f=int(p.facing)
			if i==focus_fighter and preview_facing>=0:f=preview_facing
			info.pivot.rotation.y=lerp_angle(info.pivot.rotation.y,facing_yaw(f),1.0)

# Fatica visibile senza modelli nuovi: il personaggio stanco si curva in avanti, si muove più
# lentamente e ha il respiro affannoso (il busto si alza e si abbassa). Pieno effetto da 8 di fatica.
func _tired(i: int,fat: int) -> void:
	var info=minis.get(i,{});var mdl: Node3D=info.get("model")
	if mdl==null or str(game.state.fighters[i].character) in ["ziggy","golem","skelos","sketos"]:return
	var lvl=clampf(float(fat)/8.0,0.0,1.0)
	if is_equal_approx(float(info.get("fatigue_lvl",-1.0)),lvl):return
	info["fatigue_lvl"]=lvl
	if not info.has("base_scale"):info["base_scale"]=mdl.scale
	var base: Vector3=info.base_scale
	var tw=create_tween();tw.tween_property(mdl,"rotation:x",deg_to_rad(18.0*lvl),.6)
	if info.get("breath")!=null and is_instance_valid(info.breath):info.breath.kill()
	mdl.scale=base
	if lvl>=.25:
		var amp=.012+.02*lvl;var per=1.1-.45*lvl
		var br=create_tween().set_loops();br.bind_node(mdl)
		br.tween_property(mdl,"scale",Vector3(base.x,base.y*(1.0+amp),base.z*(1.0+amp*.5)),per*.45).set_trans(Tween.TRANS_SINE)
		br.tween_property(mdl,"scale",base,per*.55).set_trans(Tween.TRANS_SINE)
		info["breath"]=br
# ---------------------------------------------------------------- riproduzione
func _play_queue() -> void:
	playing=true
	while not queue.is_empty():
		var step=queue.pop_front();history.append(step)
		await _play_step(step,false)
	playing=false;_refresh_tokens()

func _play_step(step: Array,fluid: bool) -> void:
	var longest=0.0;var ends={}
	# prima chi colpisce: da lì si sa l'istante esatto dell'impatto (dopo eventuali rotazioni e passi),
	# poi parate e reazioni partono in quell'istante, così colpo e parata si vedono insieme
	var impact=-1.0
	for t in step:
		if t.has("labels") or not t.get("strike",false) or t.get("after",false):continue
		var info=minis.get(t.i)
		if info==null:continue
		var dur=_run_track(t,info,fluid);t["_done"]=true
		ends[t.i]=maxf(ends.get(t.i,0.0),t.delay+dur);longest=maxf(longest,t.delay+dur)
		impact=maxf(impact,float(t.get("impact_at",-1.0)))
	for pass_after in [false,true]:   # le reazioni "after" partono quando finisce il movimento dello stesso personaggio
		for t in step:
			if t.has("labels") or t.get("after",false)!=pass_after or t.get("_done",false):continue
			var info=minis.get(t.i)
			if info==null:continue
			if impact>=0.0 and t.has("parried"):t.delay=maxf(.05,impact-.35)
			elif impact>=0.0 and t.get("after_strike",false):t.delay=maxf(t.delay,impact)
			if pass_after:t.delay=maxf(t.delay,ends.get(t.i,0.0))
			var dur=_run_track(t,info,fluid)
			ends[t.i]=maxf(ends.get(t.i,0.0),t.delay+dur)
			longest=maxf(longest,t.delay+dur)
	await get_tree().create_timer(longest).timeout
	for t in step:
		if t.has("labels"):
			if t.has("effects"):_show_effects(t.effects)
			if t.has("pickups"):_show_pickups(t.pickups)
			if t.has("states"):_apply_states(t.states)
			if fluid:
				for i in t.labels:
					if minis.has(i):_set_status(i,t.labels[i][0],t.labels[i][1],t.labels[i][2])
			continue
		var info=minis.get(t.i)
		if info and info.ap and not t.get("stay",false) and not t.clip in ["A terra","Morte"]:_end_pose(t.i)

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
	if pl.mode=="lineare" and info.ap and info.ap.has_animation("Camminata") and not info.get("spirit",false) and not t.get("split",false) and not t.get("pushed",false) and not t.get("move","") in ["teleport","dematerialize"]:
		# si sposta con una clip che non cammina (es. Concentrarsi): prima cammina fino alla cella, poi la esegue lì
		var walk=t.duplicate();walk.clip="Camminata";walk.split=true;walk.move="advance";walk.strike=false
		for k in ["hit","arrow","targets","bow"]:walk.erase(k)
		if t.get("move","")=="rise":   # da terra: prima si rialza sul posto, poi si sposta
			var up=t.duplicate();up.split=true;up.to=t.from;up.erase("path")
			var d0=_run_track(up,info,fluid)
			walk.from=t.from;walk.delay=t.delay+d0
			return d0+_run_track(walk,info,fluid,forced)
		var d1=_run_track(walk,info,fluid,forced)
		var act=t.duplicate();act.split=true;act.from=t.to;act.delay=t.delay+d1;act.erase("path")
		var d2=_run_track(act,info,fluid);t["impact_at"]=act.get("impact_at",-1.0)
		return d1+d2
	var anim: Animation=pl.anim;var length: float=pl.length;var turn: float=pl.turn
	var dist: float=pl.dist;var m: Dictionary=pl.m;var mode: String=pl.mode;var loops: int=pl.loops
	var natural=length;var rate=1.0
	if forced>0 and mode!="fermo":rate=clampf(natural/forced,.35,2.5);length=forced
	if OS.get_environment("BM_DEBUG")=="1":print("TRACK ",game.state.fighters[t.i].character," ",t.clip," ",mode," dist %.2f len %.2f loops %d"%[dist,length,loops])
	if t.get("strike",false):   # istante del colpo: a metà circa della clip (in fondo alla corsa per le cariche)
		t["impact_at"]=t.delay+turn+((length*.85) if mode in ["passi","profilo"] else (anim.length/rate*.45 if anim else .5))
	var tw=create_tween()
	if t.delay>0:tw.tween_interval(t.delay)
	if turn>0:tw.tween_property(pivot,"rotation:y",pivot.rotation.y+angle_difference(pivot.rotation.y,t.yaw),turn)
	tw.tween_callback(func():
		if t.get("move","")=="summon":   # l'evocato emerge dalla sabbia
			root.position=t.from;pivot.rotation.y=t.yaw;pivot.scale=Vector3.ONE;pivot.visible=true
			_burst(root.global_position+Vector3(0,.15,0),Color(.55,.42,.3),90,.5)
		root.visible=true
		_set_rim(t.i,t.move,t.get("facing",-1))
		if anim:
			if mode=="passi" or mode=="profilo":anim.loop_mode=Animation.LOOP_LINEAR
			ap.play(t.clip,.12 if fluid else .18);ap.speed_scale=rate*(1.0-.3*float(info.get("fatigue_lvl",0.0)))   # stanco: più lento
			if t.get("lying",false):ap.seek(ap.get_animation(t.clip).length-.05,true)   # già disteso: niente caduta
		if t.has("bow"):_set_gear(t.i,t.bow,t.get("loaded",false))
		if t.has("arrow"):_shoot(t,info,anim.length/rate if anim else 1.0)
		if SPELL_FX.has(t.get("move","")):_cast_fx(t,info,anim.length/rate if anim else 1.0)
		if info.get("spirit",false):_spirit_move(t,info)
		if t.has("reach"):_reach_fx(root.position,t.reach,(anim.length/rate if anim else 1.0)*.35)
		if t.has("parried") and minis.has(int(t.parried)):_parry_fx(info,minis[int(t.parried)],str(t.get("parry_word","PARATA!")))
		if t.get("dead",false) and str(game.state.fighters[t.i].character)=="golem":_shatter(info)
		elif t.get("dead",false) and not str(game.state.fighters[t.i].character) in ["skelos","sketos","ziggy"]:_bury(info,(anim.length/rate if anim else 1.5)+1.0)
		if str(game.state.fighters[t.i].character) in ["skelos","sketos"]:
			if t.get("pieces",false) or t.get("dead",false):_bones(info,t.get("dead",false))
			elif t.get("rebuild",false):_rebuild(info)
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
		var pts: Array=[from]+t.get("path",[to])   # tappe del percorso: niente scorciatoie attraverso gli altri
		if mode=="profilo":
			var clip_len=anim.length
			tw.tween_method(func(x: float):
				var k=floorf(x/clip_len);var p=(k+_progress(m,x-k*clip_len))/loops
				root.position=_along(pts,minf(p,1.0)),0.0,natural,length)
		elif pts.size()>2:   # percorso con curve: si gira lungo il tragitto e alla fine riprende l'orientamento scelto
			tw.tween_method(func(f: float):
				var a=_along(pts,f);var b=_along(pts,minf(f+.04,1.0));root.position=a
				var dv=b-a
				if dv.length()>.01:pivot.rotation.y=lerp_angle(pivot.rotation.y,atan2(dv.x,dv.z),.25),0.0,1.0,length)
			tw.tween_property(pivot,"rotation:y",pivot.rotation.y+angle_difference(pivot.rotation.y,t.yaw),.2)
		else:
			tw.tween_property(root,"position",to,length)
		if mode=="profilo" and anim and not t.clip in ["Carica"]:
			tw.tween_callback(func():anim.loop_mode=Animation.LOOP_NONE)
		# arrivato: smette di camminare e si mette in guardia (niente passi sul posto mentre aspetta)
		if ap and not t.get("stay",false):
			tw.tween_callback(func():
				if anim:anim.loop_mode=Animation.LOOP_NONE
				if ap.current_animation==t.clip and ap.has_animation("In guardia"):_rest_pose(t.i,.2))
		if rate!=1.0 and ap:tw.tween_callback(func():ap.speed_scale=1.0)
	return turn+length

func _along(pts: Array,f: float) -> Vector3:
	# punto alla frazione f della spezzata pts (tappe esagono per esagono)
	var total=0.0
	for k in pts.size()-1:total+=(pts[k+1]-pts[k]).length()
	if total<=.0001:return pts.back()
	var d=f*total
	for k in pts.size()-1:
		var seg=(pts[k+1]-pts[k]).length()
		if d<=seg:return pts[k].lerp(pts[k+1],d/maxf(seg,.0001))
		d-=seg
	return pts.back()
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
# Posa d'attesa: in guardia; l'arciere con la freccia incoccata resta in mira, arco teso
# fine della traccia: chi è ancora a terra (es. ha rotolato) resta disteso, non si rimette in guardia
func _end_pose(i: int) -> void:
	var p=game.state.fighters[i];var ap: AnimationPlayer=minis.get(i,{}).get("ap")
	if ap and p.alive and p.down and ap.has_animation("A terra"):
		ap.play("A terra",.25);ap.seek(ap.get_animation("A terra").length-.05,true);return
	_rest_pose(i,.25)
func _rest_pose(i: int,blend:=.25) -> void:
	var info=minis.get(i,{});var ap: AnimationPlayer=info.get("ap")
	if ap==null:return
	var st=info.get("bow_state",[false,false])
	if st[0] and st[1] and ap.has_animation("Tirare"):
		# freccia incoccata e puntata al fronte: posa ferma senza dissolvenza (in pausa la dissolvenza
		# resterebbe a metà, con l'arciere girato di lato come alla fine di Incoccare)
		ap.play("Tirare",0.0);ap.seek(ap.get_animation("Tirare").length*.45,true);ap.pause()
	elif st[0] and ap.has_animation("In guardia arco"):ap.play("In guardia arco",blend)
	elif ap.has_animation("In guardia"):ap.play("In guardia",blend)
func _set_gear(i: int,bow: bool,loaded: bool) -> void:
	var info=minis.get(i,{})
	info["bow_state"]=[bow,loaded]
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
	var root=Node3D.new();var a=Node3D.new();a.scale=Vector3.ONE*.85;root.add_child(a)   # un po' più grande delle miniature: si vede in volo
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
	info["bow_state"]=[true,false]   # tirato: non è più incoccato
	var target: Vector3
	var victim=minis.get(v,{})
	if victim.is_empty():return
	if hit:target=victim.root.global_position+Vector3(randf_range(-.05,.05),randf_range(.55,.8),randf_range(-.05,.05))
	else:
		var off=Vector3(randf_range(-.45,.45),0,randf_range(-.45,.45))
		target=victim.root.global_position+off+Vector3(0,.02,0)
	var a=_arrow_mesh();viewport.add_child(a);a.global_position=from;arrows.append(a)
	# scia luminosa dietro la freccia, che si spegne all'arrivo
	var trail=CPUParticles3D.new();trail.amount=60;trail.lifetime=.35;trail.local_coords=false;trail.explosiveness=0
	var tq=QuadMesh.new();tq.size=Vector2(.05,.05);trail.mesh=tq;var tm=_fx_mat(Color(1,.95,.75,.8),2.5);tm.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED;tm.blend_mode=BaseMaterial3D.BLEND_MODE_ADD;tm.albedo_texture=_soft();trail.material_override=tm
	trail.direction=Vector3.UP;trail.spread=180;trail.initial_velocity_min=0;trail.initial_velocity_max=.05;trail.gravity=Vector3.ZERO
	trail.scale_amount_curve=_curve([[0,1],[1,.1]]);trail.color_ramp=_ramp([[0,Color(1,1,.9,.9)],[1,Color(1,.9,.6,0)]])
	viewport.add_child(trail);trail.global_position=from;trail.emitting=true
	_sfx("swing",from,0.0,-8.0,1.6)   # fischio della freccia
	var dur=clampf(from.distance_to(target)/8.0,.25,1.0)
	var tw=create_tween()
	tw.tween_method(func(x: float):
		var p=from.lerp(target,x)+Vector3(0,sin(x*PI)*.18*from.distance_to(target)/4.0,0)
		var ahead=from.lerp(target,minf(x+.02,1.0))+Vector3(0,sin(minf(x+.02,1.0)*PI)*.18*from.distance_to(target)/4.0,0)
		a.global_position=p;trail.global_position=p
		if ahead.distance_to(p)>.001:a.look_at(ahead,Vector3.UP,true),0.0,1.0,dur)
	tw.tween_callback(func():trail.emitting=false;get_tree().create_timer(.5).timeout.connect(trail.queue_free))
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
	if t.get("dead",false):   # lo spirito si dissolve
		var tw0=create_tween();tw0.tween_property(fig,"rotation:y",fig.rotation.y+TAU*2,1.2);tw0.parallel().tween_property(fig,"scale",Vector3(.01,1.6,.01),1.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		tw0.tween_callback(func():fig.visible=false);return
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
	# ogni incantesimo ha il suo effetto: proiettile, fulmine, flusso, onda, nube...
	var mv: String=t.move;var color: Color=SPELL_FX[mv];var caster: Node3D=info.root
	await get_tree().create_timer(clip_time*.45).timeout
	if not is_instance_valid(caster):return
	var hand=caster.global_position+Vector3(0,.8,0)
	var targets=[]
	for v in t.get("targets",[]):
		if minis.has(int(v)):targets.append(minis[int(v)].root.global_position+Vector3(0,.6,0))
	var at: Vector3=t.get("spell_at",Vector3.INF)
	if at==Vector3.INF and not targets.is_empty():at=targets[0]-Vector3(0,.6,0)
	_burst(hand,color,40,.25)   # lampo sulle mani del mago
	match mv:
		"fireball":
			var dest=at+Vector3(0,.5,0) if at!=Vector3.INF else hand
			await _projectile(hand,dest,color,.16,true)
			_explosion(dest,color,1.2)
		"firestaff":
			for p in targets:_fire_jet(hand,p,.7)
		"lightning","shock":
			var chain=[hand]+targets
			for k in chain.size()-1:_bolt(chain[k],chain[k+1],color)
			if mv=="shock":_ring(caster.global_position,color,1.6,.45)
		"drain":
			for p in targets:_stream(p,hand,color,.9,true)   # l'energia va dal bersaglio al mago
		"heal":
			_rise(caster.global_position,Color(.4,1,.6),60,1.4);_ring(caster.global_position,Color(.4,1,.6),.7,.6)
		"shield":_ring(caster.global_position,color,.8,.5)
		"sleep":
			for p in targets:_zzz(p)
		"fear":_ring(caster.global_position,color,5.5,1.1)
		"pustules":_ring(caster.global_position,color,2.6,.6);_burst(hand,color,80,.5)
		"age":
			for p in targets:_fall_dust(p,color)
		"plague","control":
			for p in targets:_stream(hand,p,color,.7,false)
		"summon":
			if at!=Vector3.INF:_burst(at+Vector3(0,.15,0),Color(.55,.42,.3),90,.5);_ring(at,Color(.55,.42,.3),.9,.5)
		"transform":
			for p in targets:_burst(p,color,70,.35)
		"vortex","wall","livingfire","abyss":
			if at!=Vector3.INF:
				await _projectile(hand,at+Vector3(0,.3,0),color,.1,false)
				_burst(at+Vector3(0,.2,0),color,70,.45)
		"concentrate":_rise(caster.global_position,color,24,.8)
		_:
			for p in targets:
				await _projectile(hand,p,color,.07,false);_burst(p,color,30,.18)
func _fx_mat(color: Color,energy:=3.0) -> StandardMaterial3D:
	var m=StandardMaterial3D.new();m.albedo_color=color;m.emission_enabled=true;m.emission=color;m.emission_energy_multiplier=energy
	m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;return m
func _burst(at: Vector3,color: Color,amount: int,radius: float) -> void:
	var g=_glow(color,amount,radius);viewport.add_child(g);g.global_position=at;g.emitting=true
	get_tree().create_timer(1.6).timeout.connect(g.queue_free)
func _projectile(from: Vector3,to: Vector3,color: Color,size: float,trail: bool) -> void:
	var orb=MeshInstance3D.new();var sm=SphereMesh.new();sm.radius=size;sm.height=size*2;orb.mesh=sm;orb.material_override=_fx_mat(color,4.0)
	viewport.add_child(orb);orb.global_position=from
	if trail:   # scia di fiamme
		var tr=_glow(color,60,size*.6);tr.one_shot=false;tr.explosiveness=0;tr.lifetime=.45;tr.local_coords=false;orb.add_child(tr);tr.emitting=true
	var tw=create_tween();tw.tween_property(orb,"global_position",to,clampf(from.distance_to(to)/8.0,.15,.6))
	await tw.finished
	orb.queue_free()
# --- Fuoco: fiamme vere (sprite morbidi additivi con rampa giallo-arancio-rosso), fumo, scintille
var _soft_tex: Texture2D
func _soft() -> Texture2D:
	if _soft_tex==null:
		var g=Gradient.new();g.set_color(0,Color(1,1,1,1));g.set_color(1,Color(1,1,1,0));g.add_point(.35,Color(1,1,1,.75))
		var t=GradientTexture2D.new();t.gradient=g;t.fill=GradientTexture2D.FILL_RADIAL;t.fill_from=Vector2(.5,.5);t.fill_to=Vector2(.5,0);t.width=64;t.height=64
		_soft_tex=t
	return _soft_tex
func _sprite_particles(amount: int,additive: bool) -> CPUParticles3D:
	var p=CPUParticles3D.new();p.amount=amount;var q=QuadMesh.new();q.size=Vector2(.16,.16);p.mesh=q
	var m=StandardMaterial3D.new();m.albedo_texture=_soft();m.vertex_color_use_as_albedo=true;m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;m.billboard_mode=BaseMaterial3D.BILLBOARD_PARTICLES;m.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED
	if additive:m.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
	p.material_override=m;p.angle_min=0;p.angle_max=360
	return p
func _ramp(cols: Array) -> Gradient:
	var g=Gradient.new();g.offsets=PackedFloat32Array(cols.map(func(c):return c[0]));g.colors=PackedColorArray(cols.map(func(c):return c[1]));return g
func _curve(pts: Array) -> Curve:
	var c=Curve.new()
	for pt in pts:c.add_point(Vector2(pt[0],pt[1]))
	return c
var _fx_tex={}
func _fx_texture(name: String) -> Texture2D:
	if not _fx_tex.has(name):_fx_tex[name]=load("res://assets/fx/%s.png"%name)
	return _fx_tex[name]
func _flame(amount: int,extent: Vector3,rise: float,size: float=1.0) -> CPUParticles3D:
	var f=_sprite_particles(amount,true)
	f.material_override.albedo_texture=_fx_texture("flame");f.angle_min=-12;f.angle_max=12;(f.mesh as QuadMesh).size=Vector2(.13,.26);f.lifetime=.75;f.explosiveness=0;f.randomness=.5;f.local_coords=false
	f.emission_shape=CPUParticles3D.EMISSION_SHAPE_BOX;f.emission_box_extents=extent
	f.direction=Vector3.UP;f.spread=6;f.initial_velocity_min=rise*.6;f.initial_velocity_max=rise;f.gravity=Vector3(0,rise*.6,0);f.damping_min=.3;f.damping_max=.8;f.lifetime=.6
	f.radial_accel_min=-.6;f.radial_accel_max=-.2   # le lingue di fuoco si stringono verso l'alto
	f.scale_amount_min=.8*size;f.scale_amount_max=1.6*size;f.scale_amount_curve=_curve([[0,.4],[.25,1],[1,.1]])
	f.color_ramp=_ramp([[0,Color(1,1,.75,0)],[.06,Color(1,.92,.55,.85)],[.3,Color(1,.55,.12,.75)],[.65,Color(.9,.22,.05,.45)],[1,Color(.35,.06,.02,0)]])
	return f
func _smoke(amount: int,extent: Vector3,rise: float) -> CPUParticles3D:
	var s=_sprite_particles(amount,false);s.lifetime=1.8;s.explosiveness=0;s.randomness=.6;s.local_coords=false
	s.emission_shape=CPUParticles3D.EMISSION_SHAPE_BOX;s.emission_box_extents=extent
	s.direction=Vector3.UP;s.spread=20;s.initial_velocity_min=rise*.3;s.initial_velocity_max=rise*.7;s.gravity=Vector3(0,rise*.3,0)
	s.scale_amount_min=2.0;s.scale_amount_max=3.5;s.scale_amount_curve=_curve([[0,.3],[1,1]])
	s.color_ramp=_ramp([[0,Color(.55,.52,.48,0)],[.25,Color(.5,.47,.44,.22)],[1,Color(.62,.6,.57,0)]])
	return s
func _sparks(amount: int,speed: float,color:=Color(1,.8,.35)) -> CPUParticles3D:
	var k=CPUParticles3D.new();k.amount=amount;k.one_shot=true;k.explosiveness=.95;k.lifetime=.7;k.local_coords=false
	var q=QuadMesh.new();q.size=Vector2(.015,.09);k.mesh=q;k.material_override=_fx_mat(color,6.0)
	k.material_override.billboard_mode=BaseMaterial3D.BILLBOARD_FIXED_Y;k.material_override.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
	k.direction=Vector3.UP;k.spread=180;k.initial_velocity_min=speed*.5;k.initial_velocity_max=speed;k.gravity=Vector3(0,-6,0)
	k.color_ramp=_ramp([[0,Color(1,1,1,1)],[1,Color(1,1,1,0)]])
	return k
func _flicker_light(at: Vector3,color: Color,energy: float,rng_: float,dur: float) -> void:
	var l=OmniLight3D.new();l.light_color=color;l.light_energy=energy;l.omni_range=rng_;viewport.add_child(l);l.global_position=at
	var tw=create_tween()
	for k in int(dur/.08):tw.tween_property(l,"light_energy",energy*randf_range(.5,1.1)*(1.0-float(k)*.08/dur),.08)
	tw.tween_callback(l.queue_free)
func _one_shot(n: Node3D,at: Vector3,life: float) -> void:
	viewport.add_child(n);n.global_position=at
	if n is CPUParticles3D:n.emitting=true
	get_tree().create_timer(life).timeout.connect(n.queue_free)
func _explosion(at: Vector3,color: Color,radius: float) -> void:
	# palla di fuoco: vampata, fumo che sale, scintille, onda d'urto e luce che tremola
	var f=_flame(90,Vector3.ONE*.12,2.2,1.6);f.one_shot=true;f.explosiveness=.9;f.direction=Vector3.UP;f.spread=180;f.initial_velocity_min=1.0;f.initial_velocity_max=2.4;f.gravity=Vector3(0,1.5,0);f.lifetime=.9
	_one_shot(f,at,2.0)
	var s=_smoke(40,Vector3.ONE*.25,1.0);s.one_shot=true;s.explosiveness=.7;_one_shot(s,at+Vector3(0,.2,0),3.5)
	_one_shot(_sparks(60,4.0),at,1.5)
	_sfx("explosion",at,0.0,0.0)
	var ball=MeshInstance3D.new();var sm=SphereMesh.new();sm.radius=.2;sm.height=.4;ball.mesh=sm;var m=_fx_mat(Color(1,.7,.3,.6),2.5);m.blend_mode=BaseMaterial3D.BLEND_MODE_ADD;ball.material_override=m
	viewport.add_child(ball);ball.global_position=at
	var tw=create_tween();tw.tween_property(ball,"scale",Vector3.ONE*radius*2.6,.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(m,"albedo_color:a",0.0,.35);tw.tween_callback(ball.queue_free)
	_ring(Vector3(at.x,.05,at.z),Color(1,.6,.2),radius*1.4,.45)
	_flicker_light(at,Color(1,.55,.2),3.5,4.0,1.0)
# Il golem caduto va in mille pezzi: i sassi volano, rimbalzano, poi sprofondano e spariscono
func _shatter(info: Dictionary) -> void:
	var root: Node3D=info.root;var base=root.global_position
	await get_tree().create_timer(.25).timeout
	if not is_instance_valid(root):return
	root.visible=false
	var mats=[]
	var stone: Material=null
	if info.get("model")!=null:
		for mi in info.model.find_children("*","MeshInstance3D",true,false):
			if mi.mesh and mi.mesh.get_surface_count()>0:stone=mi.get_active_material(0);break
	for c in [Color(.75,.72,.65),Color(.6,.58,.5),Color(.85,.82,.72),Color(.55,.58,.45)]:
		var m: StandardMaterial3D=stone.duplicate() if stone is StandardMaterial3D else StandardMaterial3D.new()
		if stone is StandardMaterial3D:m.albedo_color=m.albedo_color*c
		else:m.albedo_color=c
		m.roughness=.95;m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mats.append(m)
	var rocks=[]
	for k in 46:
		var r=MeshInstance3D.new();var sm=SphereMesh.new();var sz=randf_range(.05,.16);sm.radius=sz;sm.height=sz*2;sm.radial_segments=5;sm.rings=3;r.mesh=sm
		r.material_override=mats[k%mats.size()];r.scale=Vector3(randf_range(.7,1.3),randf_range(.6,1.1),randf_range(.7,1.3))
		viewport.add_child(r)
		var start=base+Vector3(randf_range(-.3,.3),randf_range(.1,1.4),randf_range(-.3,.3))
		var out=(start-base);out.y=0;out=out.normalized() if out.length()>.01 else Vector3(1,0,0)
		var vel=out*randf_range(.8,2.6)+Vector3(0,randf_range(.5,2.6),0)
		var spin=Vector3(randf_range(-8,8),randf_range(-8,8),randf_range(-8,8))
		r.global_position=start;rocks.append(r)
		var tw=create_tween()
		tw.tween_method(func(x: float):
			# caduta con gravità e un rimbalzo smorzato sul terreno
			var pos=start+vel*x+Vector3(0,-4.9*x*x,0)
			if pos.y<sz*.6:pos.y=sz*.6+absf(sin(x*9.0))*.05*maxf(0,1.3-x)
			r.global_position=pos;r.rotation=spin*minf(x,.7),0.0,1.3,1.3)
	_one_shot(_smoke(50,Vector3(.35,.4,.35),.5),base+Vector3(0,.5,0),3.0)
	var dust=_glow(Color(.6,.55,.45),80,.4);dust.gravity=Vector3(0,-1.0,0);_one_shot(dust,base+Vector3(0,.7,0),2.0)
	_sfx("rocks",base+Vector3(0,.5,0),0.0,0.0)
	await get_tree().create_timer(2.8).timeout
	for r in rocks:   # i sassi sprofondano nella sabbia e svaniscono
		if not is_instance_valid(r):continue
		var tw=create_tween();tw.tween_property(r,"global_position:y",r.global_position.y-.25,1.2);tw.parallel().tween_property(r.material_override,"albedo_color:a",0.0,1.2)
		tw.tween_callback(r.queue_free)
# Scheletro in pezzi: le ossa si sparpagliano e restano a terra finché un mago non lo rigenera;
# alla rigenerazione volano di nuovo insieme e lo scheletro si rialza. Se muore davvero, svaniscono.
# il corpo, dopo la morte, sprofonda nella sabbia in una nube di polvere e lascia libero l'esagono
func _bury(info: Dictionary,after: float) -> void:
	info["buried"]=false
	await get_tree().create_timer(after).timeout
	var root: Node3D=info.root
	if not is_instance_valid(root):return
	_burst(root.global_position+Vector3(0,.1,0),Color(.6,.5,.38),60,.45)
	var fig: Node3D=info.pivot;var y0=fig.position.y
	var tw=create_tween();tw.tween_property(fig,"position:y",y0-.5,1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():root.visible=false;fig.position.y=y0;info["buried"]=true;info["dying"]=false)
func _bones(info: Dictionary,gone: bool) -> void:
	if info.has("bones"):return
	var root: Node3D=info.root;var base=root.global_position
	await get_tree().create_timer(.2).timeout
	if not is_instance_valid(root):return
	if info.get("model")!=null:info.model.visible=false
	var bone=StandardMaterial3D.new();bone.albedo_color=Color(.74,.6,.34);bone.metallic=.5;bone.roughness=.5;bone.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	var cloth=StandardMaterial3D.new();cloth.albedo_color=Color(.55,.06,.05);cloth.roughness=.9;cloth.cull_mode=BaseMaterial3D.CULL_DISABLED;cloth.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	var pieces=[]
	for k in 30:
		var m=MeshInstance3D.new()
		if k==0:   # il teschio
			var sm=SphereMesh.new();sm.radius=.075;sm.height=.13;m.mesh=sm;m.material_override=bone
		elif k<24:   # ossa lunghe e corte
			var cm=CapsuleMesh.new();cm.radius=randf_range(.012,.026);cm.height=randf_range(.08,.3);cm.radial_segments=6;cm.rings=2;m.mesh=cm;m.material_override=bone
		else:   # brandelli del mantello rosso
			var q=QuadMesh.new();q.size=Vector2(randf_range(.12,.25),randf_range(.1,.2));m.mesh=q;m.material_override=cloth
		viewport.add_child(m);pieces.append(m)
		var start=base+Vector3(randf_range(-.15,.15),randf_range(.2,1.1),randf_range(-.15,.15))
		var land=base+Vector3(randf_range(-.42,.42),.04,randf_range(-.42,.42))
		var rot_end=Vector3(PI/2+randf_range(-.3,.3),randf_range(0,TAU),randf_range(-.3,.3))
		m.global_position=start;m.set_meta("land",land);m.set_meta("start",start)
		var tw=create_tween()
		tw.tween_method(func(x: float):
			var hgt=sin(x*PI)*.35*(1.0-x)+(1.0-x)*(start.y-.04)
			m.global_position=Vector3(lerpf(start.x,land.x,x),.04+maxf(0,hgt),lerpf(start.z,land.z,x));m.rotation=rot_end*x,0.0,1.0,randf_range(.45,.8)).set_ease(Tween.EASE_IN)
	info.bones=pieces
	_one_shot(_smoke(20,Vector3(.25,.2,.25),.4),base+Vector3(0,.3,0),2.5)
	_sfx("death_bones",base+Vector3(0,.5,0),0.0,0.0)
	if gone:
		await get_tree().create_timer(3.0).timeout
		for m in pieces:
			if is_instance_valid(m):var tw=create_tween();tw.tween_property(m,"global_position:y",-.15,1.2);tw.tween_callback(m.queue_free)
		info.erase("bones")
func _rebuild(info: Dictionary) -> void:
	# le ossa si rialzano in volo e lo scheletro torna intero
	var pieces: Array=info.get("bones",[])
	info.erase("bones")
	var base=info.root.global_position
	for m in pieces:
		if not is_instance_valid(m):continue
		var tw=create_tween();tw.tween_property(m,"global_position",base+Vector3(randf_range(-.1,.1),randf_range(.4,1.0),randf_range(-.1,.1)),.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(m.queue_free)
	_burst(base+Vector3(0,.7,0),Color(.75,.5,1),60,.35)
	await get_tree().create_timer(.5).timeout
	# lo scheletro risale dalla sabbia: terra che si apre, bagliore viola, poi emerge lentamente
	_ring(base,Color(.75,.5,1),.7,.8);_ring(base,Color(.55,.45,.35),.9,1.0)
	var dirt=_glow(Color(.55,.45,.32),90,.35);dirt.direction=Vector3.UP;dirt.spread=35;dirt.initial_velocity_min=1.0;dirt.initial_velocity_max=2.2;dirt.gravity=Vector3(0,-5,0);dirt.lifetime=1.0
	_one_shot(dirt,base+Vector3(0,.08,0),2.0)
	var glow=_sprite_particles(40,true);glow.lifetime=1.2;glow.emission_shape=CPUParticles3D.EMISSION_SHAPE_SPHERE;glow.emission_sphere_radius=.3;glow.direction=Vector3.UP;glow.spread=10
	glow.initial_velocity_min=.4;glow.initial_velocity_max=.9;glow.gravity=Vector3.ZERO;glow.color_ramp=_ramp([[0,Color(.8,.5,1,0)],[.3,Color(.8,.5,1,.7)],[1,Color(.5,.2,1,0)]]);glow.one_shot=true;glow.explosiveness=.3
	_one_shot(glow,base+Vector3(0,.1,0),2.0)
	_sfx("bones_rise",base,0.0,-2.0)
	if info.get("model")!=null:
		var mdl: Node3D=info.model;var y0=mdl.position.y
		mdl.position.y=y0-1.1;mdl.visible=true
		if info.ap and info.ap.has_animation("Rialzarsi"):info.ap.play("Rialzarsi",0.0)
		var tw=create_tween();tw.tween_property(mdl,"position:y",y0,1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
func _fireball(from: Vector3,to: Vector3) -> void:
	# sfera incandescente con una scia di fiamme e fumo
	var orb=MeshInstance3D.new();var sm=SphereMesh.new();sm.radius=.09;sm.height=.18;orb.mesh=sm;var om=_fx_mat(Color(1,.8,.45),3.0);om.blend_mode=BaseMaterial3D.BLEND_MODE_ADD;orb.material_override=om
	viewport.add_child(orb);orb.global_position=from
	var tr=_flame(80,Vector3.ONE*.06,.4,1.2);tr.lifetime=.4;orb.add_child(tr);tr.emitting=true
	var sk=_smoke(25,Vector3.ONE*.05,.3);sk.lifetime=1.0;orb.add_child(sk);sk.emitting=true
	var l=OmniLight3D.new();l.light_color=Color(1,.55,.2);l.light_energy=1.8;l.omni_range=2.0;orb.add_child(l)
	var arc=from.distance_to(to)*.18
	var tw=create_tween();tw.tween_method(func(x: float):orb.global_position=from.lerp(to,x)+Vector3(0,sin(x*PI)*arc,0),0.0,1.0,clampf(from.distance_to(to)/6.0,.25,.8))
	await tw.finished
	orb.queue_free()
func _fire_jet(from: Vector3,to: Vector3,dur: float) -> void:
	# getto di fiamme dal bastone al bersaglio
	var f=_flame(120,Vector3.ONE*.04,.3,1.0);f.lifetime=.35;viewport.add_child(f);f.global_position=from;f.emitting=true
	var d=(to-from);f.direction=d.normalized();f.spread=6;f.initial_velocity_min=d.length()/.35*.8;f.initial_velocity_max=d.length()/.35;f.gravity=Vector3(0,.5,0)
	get_tree().create_timer(dur).timeout.connect(func():f.emitting=false)
	get_tree().create_timer(dur+1.0).timeout.connect(f.queue_free)
	var hit=_flame(40,Vector3(.12,.2,.12),1.2,1.0);viewport.add_child(hit);hit.global_position=to;hit.emitting=true
	get_tree().create_timer(dur+.3).timeout.connect(func():hit.emitting=false)
	get_tree().create_timer(dur+1.3).timeout.connect(hit.queue_free)
	_flicker_light(to,Color(1,.5,.15),2.0,2.5,dur+.3)
func _bolt_points(a: Vector3,b: Vector3,jag: float,n: int) -> Array:
	var pts=[a]
	for k in range(1,n):pts.append(a.lerp(b,float(k)/n)+Vector3(randf_range(-jag,jag),randf_range(-jag,jag),randf_range(-jag,jag)))
	pts.append(b);return pts
func _ribbon(im: ImmediateMesh,pts: Array,width: float,cam: Vector3) -> void:
	for k in pts.size()-1:
		var a: Vector3=pts[k];var b: Vector3=pts[k+1]
		var side=(b-a).cross(cam-a).normalized()*width
		if side.length()<.0001:side=Vector3(width,0,0)
		var w2=side*(1.0-float(k)/pts.size()*.5)   # si assottiglia verso la fine
		for v in [a-side,a+side,b+w2,a-side,b+w2,b-w2]:im.surface_add_vertex(v)
func _bolt(from: Vector3,to: Vector3,color: Color) -> void:
	# fulmine: nucleo bianco, alone azzurro, rami secondari; sfarfalla e illumina la scena
	var core=MeshInstance3D.new();var im=ImmediateMesh.new();core.mesh=im;var cm=_fx_mat(Color(.95,.97,1),3.0);cm.blend_mode=BaseMaterial3D.BLEND_MODE_ADD;cm.cull_mode=BaseMaterial3D.CULL_DISABLED;core.material_override=cm;viewport.add_child(core)
	var halo=MeshInstance3D.new();var ih=ImmediateMesh.new();halo.mesh=ih;var hm=_fx_mat(Color(color.r,color.g,color.b,.22),1.5);hm.blend_mode=BaseMaterial3D.BLEND_MODE_ADD;hm.cull_mode=BaseMaterial3D.CULL_DISABLED;halo.material_override=hm;viewport.add_child(halo)
	var cam: Vector3=camera.global_position if camera else from+Vector3(0,5,5)
	var light=OmniLight3D.new();light.light_color=color;light.omni_range=6.0;viewport.add_child(light);light.global_position=(from+to)/2
	var n=maxi(6,int(from.distance_to(to)/.12))
	for flick in 7:
		im.clear_surfaces();ih.clear_surfaces()
		var pts=_bolt_points(from,to,.18,n)
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES);_ribbon(im,pts,.009,cam)
		var branches=[]
		for b in 3:   # rami che si staccano dal fulmine principale
			var k=randi_range(1,pts.size()-2);var start: Vector3=pts[k]
			var end=start+((to-from).normalized()*.35+Vector3(randf_range(-.3,.3),randf_range(-.25,.1),randf_range(-.3,.3)))
			var bp=_bolt_points(start,end,.08,4);branches.append(bp);_ribbon(im,bp,.004,cam)
		im.surface_end()
		ih.surface_begin(Mesh.PRIMITIVE_TRIANGLES);_ribbon(ih,pts,.035,cam)
		for bp in branches:_ribbon(ih,bp,.015,cam)
		ih.surface_end()
		light.light_energy=randf_range(2.5,4.5) if flick%2==0 else 1.0
		core.visible=flick!=3;halo.visible=core.visible
		await get_tree().create_timer(.05).timeout
	core.queue_free();halo.queue_free();light.queue_free()
	_one_shot(_sparks(40,3.0,Color(.75,.9,1)),to,1.2)
	var g=_glow(color,30,.12);_one_shot(g,to,1.4)
func _stream(from: Vector3,to: Vector3,color: Color,dur: float,reverse_glow: bool) -> void:
	# flusso di particelle che scorre da un punto all'altro
	var g=_glow(color,90,.08);g.one_shot=false;g.explosiveness=0;g.local_coords=false;g.lifetime=.35;g.gravity=Vector3.ZERO;g.initial_velocity_min=0;g.initial_velocity_max=.1
	viewport.add_child(g);g.global_position=from;g.emitting=true
	var tw=create_tween();tw.tween_property(g,"global_position",to,dur);tw.tween_property(g,"global_position",from,0.0)
	tw.tween_property(g,"global_position",to,dur);tw.tween_callback(func():g.emitting=false)
	get_tree().create_timer(dur*2+.8).timeout.connect(g.queue_free)
	if reverse_glow:get_tree().create_timer(dur*2).timeout.connect(func():_burst(to,color,40,.2))
func _ring(center: Vector3,color: Color,radius: float,dur: float) -> void:
	# onda circolare che si allarga sul terreno
	var ring=MeshInstance3D.new();var tm=TorusMesh.new();tm.inner_radius=.42;tm.outer_radius=.5;ring.mesh=tm;var m=_fx_mat(color,3.0);ring.material_override=m
	viewport.add_child(ring);ring.global_position=center+Vector3(0,.1,0);ring.scale=Vector3(.2,.2,.2)
	var tw=create_tween();tw.tween_property(ring,"scale",Vector3(radius*2,.3,radius*2),dur).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(m,"albedo_color:a",0.0,dur);tw.tween_callback(ring.queue_free)
func _rise(center: Vector3,color: Color,amount: int,dur: float) -> void:
	var g=_glow(color,amount,.35);g.emission_shape=CPUParticles3D.EMISSION_SHAPE_RING;g.emission_ring_axis=Vector3.UP;g.emission_ring_radius=.35;g.emission_ring_inner_radius=.25;g.emission_ring_height=.05
	g.direction=Vector3.UP;g.spread=8;g.initial_velocity_min=.6;g.initial_velocity_max=1.0;g.gravity=Vector3.ZERO;g.lifetime=dur;g.explosiveness=.3
	viewport.add_child(g);g.global_position=center+Vector3(0,.1,0);g.emitting=true;get_tree().create_timer(dur+1.0).timeout.connect(g.queue_free)
func _zzz(at: Vector3) -> void:
	for k in 3:
		var l=Label3D.new();l.text="Z";l.font_size=96;l.pixel_size=.0025;l.modulate=Color(.8,.7,1);l.outline_size=10;l.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		viewport.add_child(l);l.global_position=at+Vector3(.1*k,.2,0)
		var tw=create_tween();tw.tween_interval(k*.3);tw.tween_property(l,"global_position",at+Vector3(.25+.1*k,.9,0),1.2);tw.parallel().tween_property(l,"modulate:a",0.0,1.2);tw.tween_callback(l.queue_free)
func _fall_dust(at: Vector3,color: Color) -> void:
	var g=_glow(color,70,.3);g.direction=Vector3.DOWN;g.gravity=Vector3(0,-1.5,0);g.initial_velocity_min=.1;g.initial_velocity_max=.3;g.lifetime=1.3
	viewport.add_child(g);g.global_position=at+Vector3(0,.5,0);g.emitting=true;get_tree().create_timer(2.0).timeout.connect(g.queue_free)
# Stati che durano: fiamme addosso, scudo magico, peste, controllo mentale, rana
func _apply_states(states) -> void:
	if states==null:return
	for i in minis:
		var st: Dictionary=states.get(i,states.get(str(i),{}))
		var info=minis[i]
		_state_node(info,"burning",st.get("burning",false),func():
			var n=Node3D.new();var f=_flame(40,Vector3(.13,.3,.13),.9,.8);f.position.y=.5;f.emitting=true;n.add_child(f)
			var s2=_smoke(12,Vector3(.1,.1,.1),.6);s2.position.y=1.0;s2.emitting=true;n.add_child(s2)
			var l=OmniLight3D.new();l.light_color=Color(1,.5,.15);l.light_energy=1.6;l.omni_range=1.8;l.position.y=.7;n.add_child(l)
			var tw=l.create_tween().set_loops()
			for k in 4:tw.tween_property(l,"light_energy",randf_range(.9,2.2),.09)
			return n)
		_state_node(info,"shield",st.get("shield",false),func():
			# scudo di energia: bolla luminosa che pulsa, tre anelli d'energia che girano, scintille e luce azzurra
			var n=Node3D.new();n.position.y=.62
			var b=MeshInstance3D.new();var sm=SphereMesh.new();sm.radius=.6;sm.height=1.35;b.mesh=sm
			var m=_fx_mat(Color(.4,.75,1,.32),2.2);m.blend_mode=BaseMaterial3D.BLEND_MODE_ADD;m.cull_mode=BaseMaterial3D.CULL_DISABLED;b.material_override=m;n.add_child(b)
			var pulse=b.create_tween().set_loops();pulse.tween_property(m,"albedo_color:a",.5,.55).set_trans(Tween.TRANS_SINE);pulse.tween_property(m,"albedo_color:a",.22,.55).set_trans(Tween.TRANS_SINE)
			for k in 3:
				var r=MeshInstance3D.new();var tm=TorusMesh.new();tm.inner_radius=.6;tm.outer_radius=.64;tm.rings=48;r.mesh=tm
				var rm=_fx_mat(Color(.55,.9,1,.95),4.0);rm.blend_mode=BaseMaterial3D.BLEND_MODE_ADD;r.material_override=rm
				r.rotation=Vector3([0.0,1.2,-1.2][k],0,[0.0,.5,-.5][k]);r.scale=Vector3(1,1.1,1);n.add_child(r)
				var tw=r.create_tween().set_loops();tw.tween_property(r,"rotation:y",TAU*(1 if k%2==0 else -1),2.0+k*.5).as_relative()
			var sp=_sprite_particles(26,true);sp.lifetime=1.2;sp.emission_shape=CPUParticles3D.EMISSION_SHAPE_SPHERE;sp.emission_sphere_radius=.6;sp.direction=Vector3.UP;sp.spread=20
			sp.initial_velocity_min=.05;sp.initial_velocity_max=.2;sp.gravity=Vector3(0,.3,0);sp.local_coords=true;(sp.mesh as QuadMesh).size=Vector2(.05,.05)
			sp.color_ramp=_ramp([[0,Color(.6,.9,1,0)],[.3,Color(.7,.95,1,1)],[1,Color(.3,.6,1,0)]]);n.add_child(sp);sp.emitting=true
			var lt=OmniLight3D.new();lt.light_color=Color(.45,.75,1);lt.light_energy=1.2;lt.omni_range=1.8;n.add_child(lt)
			return n)
		_state_node(info,"plague",st.get("plague",false),func():
			var g=_glow(Color(.5,.8,.15,.6),30,.35);g.one_shot=false;g.explosiveness=0;g.lifetime=1.6;g.gravity=Vector3(0,.15,0);g.initial_velocity_max=.2;g.position.y=.4;g.emitting=true;return g)
		_state_node(info,"control",st.get("control",false),func():
			# controllo mentale: doppio alone viola che gira sopra la testa, spirale di scintille e luce che pulsa
			var n=Node3D.new()
			for k in 2:
				var r=MeshInstance3D.new();var tm=TorusMesh.new();tm.inner_radius=.2+k*.08;tm.outer_radius=.24+k*.08;r.mesh=tm
				var rm=_fx_mat(Color(.85,.35,1,.85),3.0);rm.blend_mode=BaseMaterial3D.BLEND_MODE_ADD;r.material_override=rm;r.position.y=1.2+k*.12;r.rotation.x=.25*(1-2*k);n.add_child(r)
				var tw=r.create_tween().set_loops();tw.tween_property(r,"rotation:y",TAU*(1-2*k),1.6+k*.6).from(0.0)
			var sp=_sprite_particles(40,true);sp.lifetime=1.2;sp.emission_shape=CPUParticles3D.EMISSION_SHAPE_RING;sp.emission_ring_axis=Vector3.UP;sp.emission_ring_radius=.35;sp.emission_ring_inner_radius=.3;sp.emission_ring_height=.02
			sp.direction=Vector3.UP;sp.spread=5;sp.initial_velocity_min=.4;sp.initial_velocity_max=.7;sp.gravity=Vector3.ZERO;sp.tangential_accel_min=2.0;sp.tangential_accel_max=3.0;(sp.mesh as QuadMesh).size=Vector2(.06,.06)
			sp.color_ramp=_ramp([[0,Color(.9,.5,1,0)],[.2,Color(.9,.5,1,1)],[1,Color(.6,.2,1,0)]]);sp.position.y=.3;sp.emitting=true;n.add_child(sp)
			var l=OmniLight3D.new();l.light_color=Color(.8,.3,1);l.light_energy=1.5;l.omni_range=1.6;l.position.y=1.2;n.add_child(l)
			var lt=l.create_tween().set_loops();lt.tween_property(l,"light_energy",2.8,.5);lt.tween_property(l,"light_energy",.8,.5)
			return n)
		_frog(info,st.get("frog",false))
func _state_node(info: Dictionary,key: String,on: bool,make: Callable) -> void:
	var k="state_"+key
	if on and not (info.has(k) and is_instance_valid(info[k])):
		var n: Node3D=make.call();info.root.add_child(n);info[k]=n
		if key=="control":var tw=n.create_tween().set_loops();tw.tween_property(n,"rotation:y",TAU,2.0).from(0.0)   # alone che gira sopra la testa
	elif not on and info.has(k):
		if is_instance_valid(info[k]):info[k].queue_free()
		info.erase(k)
func _frog(info: Dictionary,on: bool) -> void:
	# trasformato in rana: la miniatura sparisce e al suo posto c'è una rana
	if info.get("model")==null:return
	if on and not info.has("frog_node"):
		var f: Node3D
		if ResourceLoader.exists("res://assets/models/frog/frog.glb"):f=load("res://assets/models/frog/frog.glb").instantiate();f.scale=Vector3.ONE*.5
		else:
			f=MeshInstance3D.new();var sm=SphereMesh.new();sm.radius=.18;sm.height=.25;f.mesh=sm;f.material_override=_fx_mat(Color(.3,.75,.3),.3);f.position.y=.15
		info.pivot.add_child(f);info.frog_node=f;info.model.visible=false
		var hop=f.create_tween().set_loops();hop.tween_interval(1.2);hop.tween_property(f,"position:y",f.position.y+.15,.15);hop.tween_property(f,"position:y",f.position.y,.15)
		hop.tween_callback(func():if randf()<.25:_sfx("frog",f.global_position,0.0,-6.0))   # ogni tanto gracida
	elif not on and info.has("frog_node"):
		if is_instance_valid(info.frog_node):info.frog_node.queue_free()
		info.erase("frog_node");info.model.visible=true
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
		match kind:
			"wall","livingfire":
				var tall=kind=="wall"
				if sound and not _variants("fire_loop").is_empty():   # crepitio continuo delle fiamme
					var st=_variants("fire_loop")[0].duplicate();if st is AudioStreamOggVorbis:st.loop=true
					var fp=AudioStreamPlayer3D.new();fp.stream=st;fp.volume_db=-12.0 if tall else -16.0;fp.unit_size=3.0;root.add_child(fp);fp.play(randf()*8.0)
				var lt=OmniLight3D.new();lt.omni_range=2.2;root.add_child(lt)
				if tall:
					# MURO INFERNALE: basamento esagonale di roccia rovente con crepe rosse e una cortina di fiamme rosso cupo
					var base=MeshInstance3D.new();var cyl=CylinderMesh.new();cyl.radial_segments=6;cyl.rings=1;cyl.top_radius=.5;cyl.bottom_radius=.54;cyl.height=.22;base.mesh=cyl
					base.position.y=.11;base.rotation.y=PI/6
					var rm=StandardMaterial3D.new();rm.albedo_color=Color(.16,.07,.05);rm.roughness=.9;rm.emission_enabled=true;rm.emission=Color(.9,.12,.02);rm.emission_energy_multiplier=.9
					base.material_override=rm;root.add_child(base)
					var hot=base.create_tween().set_loops();hot.tween_property(rm,"emission_energy_multiplier",1.6,.6);hot.tween_property(rm,"emission_energy_multiplier",.7,.6)
					var fl=_flame(110,Vector3(.3,.02,.3),1.8,1.4);fl.position.y=.2;fl.local_coords=true;root.add_child(fl)
					fl.emission_shape=CPUParticles3D.EMISSION_SHAPE_RING;fl.emission_ring_axis=Vector3.UP;fl.emission_ring_radius=.46;fl.emission_ring_inner_radius=.36;fl.emission_ring_height=.02
					fl.color_ramp=_ramp([[0,Color(1,.35,.05,0)],[.15,Color(1,.25,.03,.95)],[.6,Color(.75,.06,.02,.7)],[1,Color(.25,.02,.01,0)]]);fl.emitting=true
					var sm2=_smoke(16,Vector3(.3,.05,.3),.8);sm2.position.y=1.2;root.add_child(sm2);sm2.emitting=true
					lt.light_color=Color(1,.25,.08);lt.light_energy=1.6;lt.position.y=.5
				else:
					# FUOCO VIVENTE: una palla di fuoco giallo-bianca che fluttua e pulsa, con fiamme che le girano attorno
					var orb=Node3D.new();orb.position.y=.55;root.add_child(orb)
					var core=MeshInstance3D.new();var sm=SphereMesh.new();sm.radius=.17;sm.height=.34;core.mesh=sm
					var cm=_fx_mat(Color(1,.92,.55),4.0);cm.blend_mode=BaseMaterial3D.BLEND_MODE_ADD;core.material_override=cm;orb.add_child(core)
					var halo=MeshInstance3D.new();var hm2=SphereMesh.new();hm2.radius=.28;hm2.height=.56;halo.mesh=hm2
					var hmat=_fx_mat(Color(1,.6,.1,.35),2.0);hmat.blend_mode=BaseMaterial3D.BLEND_MODE_ADD;halo.material_override=hmat;orb.add_child(halo)
					var bob=orb.create_tween().set_loops();bob.tween_property(orb,"position:y",.75,.7).set_trans(Tween.TRANS_SINE);bob.tween_property(orb,"position:y",.5,.7).set_trans(Tween.TRANS_SINE)
					var beat=core.create_tween().set_loops();beat.tween_property(core,"scale",Vector3.ONE*1.25,.25);beat.tween_property(core,"scale",Vector3.ONE*.9,.35)
					var swirl=_flame(60,Vector3(.05,.05,.05),.7,.7);swirl.local_coords=true;orb.add_child(swirl)
					swirl.emission_shape=CPUParticles3D.EMISSION_SHAPE_RING;swirl.emission_ring_axis=Vector3.UP;swirl.emission_ring_radius=.32;swirl.emission_ring_inner_radius=.25;swirl.emission_ring_height=.05
					swirl.tangential_accel_min=3.0;swirl.tangential_accel_max=4.5;swirl.gravity=Vector3(0,.8,0)
					swirl.color_ramp=_ramp([[0,Color(1,1,.7,0)],[.2,Color(1,.9,.35,.9)],[.7,Color(1,.5,.1,.6)],[1,Color(.6,.2,.05,0)]]);swirl.emitting=true
					var spin=orb.create_tween().set_loops();spin.tween_property(orb,"rotation:y",TAU,1.2).from(0.0)
					var drip=_flame(20,Vector3(.1,.02,.1),.5,.6);drip.position.y=.05;drip.local_coords=true;root.add_child(drip);drip.emitting=true   # tracce di brace sotto
					lt.light_color=Color(1,.75,.3);lt.light_energy=1.8;lt.position.y=.7
				var tw=lt.create_tween().set_loops()
				for z in 5:tw.tween_property(lt,"light_energy",lt.light_energy*randf_range(.6,1.3),.08)
			"vortex":   # gorgo: spirale azzurra che gira dentro l'esagono, scintille risucchiate al centro
				var disc=MeshInstance3D.new();var pm=PlaneMesh.new();pm.size=Vector2(1.0,1.0);disc.mesh=pm;disc.position.y=.1
				var dm=StandardMaterial3D.new();dm.albedo_texture=_fx_texture("spiral");dm.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;dm.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
				dm.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;dm.cull_mode=BaseMaterial3D.CULL_DISABLED;disc.material_override=dm;root.add_child(disc)
				var disc2=disc.duplicate();disc2.scale=Vector3(.6,1,.6);disc2.position.y=.16;root.add_child(disc2)
				var sp1=disc.create_tween().set_loops();sp1.tween_property(disc,"rotation:y",-TAU,1.6).from(0.0)
				var sp2=disc2.create_tween().set_loops();sp2.tween_property(disc2,"rotation:y",-TAU,.9).from(0.0)
				var v=_sprite_particles(40,true);v.lifetime=1.1;v.local_coords=true;v.explosiveness=0;(v.mesh as QuadMesh).size=Vector2(.06,.06)
				v.emission_shape=CPUParticles3D.EMISSION_SHAPE_RING;v.emission_ring_axis=Vector3.UP;v.emission_ring_radius=.45;v.emission_ring_inner_radius=.38;v.emission_ring_height=.02
				v.direction=Vector3.UP;v.spread=0;v.initial_velocity_min=.02;v.initial_velocity_max=.08;v.gravity=Vector3(0,.35,0)
				v.tangential_accel_min=-1.6;v.tangential_accel_max=-1.0;v.radial_accel_min=-2.2;v.radial_accel_max=-1.6
				v.color_ramp=_ramp([[0,Color(.7,.9,1,0)],[.2,Color(.7,.9,1,1)],[1,Color(.4,.6,1,0)]]);v.position.y=.12;root.add_child(v);v.emitting=true
			"abyss":   # crepaccio: una fenditura nera dai bordi viola incandescenti, vapori che salgono dal fondo
				var hole=MeshInstance3D.new();var pm=PlaneMesh.new();pm.size=Vector2(1.05,1.05);hole.mesh=pm;hole.position.y=.1;hole.rotation.y=randf()*TAU
				var hm=StandardMaterial3D.new();hm.albedo_texture=_fx_texture("crack");hm.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;hm.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;hole.material_override=hm;root.add_child(hole)
				var pulse=hole.create_tween().set_loops();pulse.tween_property(hm,"albedo_color",Color(1.3,1.1,1.4),.8);pulse.tween_property(hm,"albedo_color",Color(1,1,1),.8)
				var d=_sprite_particles(40,false);d.lifetime=1.8;d.emission_shape=CPUParticles3D.EMISSION_SHAPE_RING;d.emission_ring_axis=Vector3.UP;d.emission_ring_radius=.25;d.emission_ring_inner_radius=.0;d.emission_ring_height=.02
				d.direction=Vector3.UP;d.spread=10;d.initial_velocity_min=.1;d.initial_velocity_max=.3;d.gravity=Vector3(0,.15,0);d.radial_accel_min=-.3;d.radial_accel_max=-.1
				d.scale_amount_min=1.2;d.scale_amount_max=2.2;d.color_ramp=_ramp([[0,Color(.2,.05,.3,0)],[.3,Color(.18,.03,.25,.5)],[1,Color(.05,0,.08,0)]]);d.position.y=.12;root.add_child(d);d.emitting=true
				var glow=_sprite_particles(18,true);glow.lifetime=1.2;glow.emission_shape=CPUParticles3D.EMISSION_SHAPE_SPHERE;glow.emission_sphere_radius=.2;glow.direction=Vector3.UP;glow.spread=8
				glow.initial_velocity_min=.2;glow.initial_velocity_max=.5;glow.gravity=Vector3.ZERO;glow.color_ramp=_ramp([[0,Color(.7,.2,1,0)],[.4,Color(.6,.15,.9,.35)],[1,Color(.3,0,.5,0)]])
				glow.position.y=.05;root.add_child(glow);glow.emitting=true
# --- Suoni (opzione): armi, passi, urla, magie -----------------------------------
# I file sono in assets/audio (sintetizzati da tools/audio/synth.py): nome_1, nome_2, ...
var sound=true:
	set(v):
		sound=v
		if is_inside_tree():_crowd_update()
const SHIELDED=["gascor","anteos","skelos","sketos"]   # parate sullo scudo: colpo sordo invece del clangore
const ARMORED=["gascor","anteos","ut","ramok","nuchra"]   # tintinnio di maglia ai passi
var _turn_seen=0;var _log_last="";var _end_played=false;var _crowd: AudioStreamPlayer
# suoni non posizionali (interfaccia, dado, gong del turno, fine partita)
func ui_sfx(name: String,db:=-6.0) -> void:
	if not sound:return
	var list=_variants(name)
	if list.is_empty():return
	var p=AudioStreamPlayer.new();p.stream=list[randi()%list.size()];p.volume_db=db;add_child(p);p.play();p.finished.connect(p.queue_free)
func _crowd_update() -> void:
	var on=false   # folla di sottofondo tolta su richiesta
	if on and _crowd==null:
		var list=_variants("crowd")
		if list.is_empty():return
		var st=list[0].duplicate();if st is AudioStreamOggVorbis:st.loop=true
		_crowd=AudioStreamPlayer.new();_crowd.stream=st;_crowd.volume_db=-24.0;add_child(_crowd);_crowd.play()
	elif not on and _crowd!=null:_crowd.queue_free();_crowd=null
func _ui_events() -> void:
	# gong a ogni nuovo turno, dado quando il diario riporta un tiro, esclamazione a fine partita, folla di sottofondo
	var turn=int(game.state.get("turn",0))
	if turn>_turn_seen:
		if _turn_seen>0:ui_sfx("turn",-10.0)
		_turn_seen=turn
	var log: Array=game.state.get("log",[])
	var fresh=[]
	for k in range(log.size()-1,-1,-1):
		if str(log[k])==_log_last:break
		fresh.append(str(log[k]))
	if not log.is_empty():
		_log_last=str(log.back())
	if game.state.get("phase","")=="finished" and not _end_played:
		_end_played=true
		var humans=[]
		for f in game.state.fighters:
			if str(f.get("controller",""))=="human" and not int(f.team) in humans:humans.append(int(f.team))
		ui_sfx("victory" if humans.is_empty() or int(game.state.get("winner",-1)) in humans else "defeat",-4.0)
	_crowd_update()
var labels_on=true          # nomi e barre sopra le miniature (spenti: ritratti nell'interfaccia)
func set_labels(v: bool) -> void:
	labels_on=v
	for i in minis:minis[i].bar.visible=v and game.state.fighters[i].alive
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
	if c in ["skelos","sketos"]:return "bones"
	if c in FEMALE:return "f"
	return "md" if c in DEEP_VOICE else "m"
const DEEP_VOICE=["gandy","ut","nuchra","gascor","ramok"]   # maghi e guerrieri robusti: voce profonda
func _pitch(i: int) -> float:
	# ogni personaggio ha il suo timbro: piccolo scarto fisso di intonazione
	var c=str(game.state.fighters[i].character)
	return 1.0+float(posmod(c.hash(),9)-4)*.035
func _sound_track(t: Dictionary,info: Dictionary,length: float,mode: String) -> void:
	if not sound or not minis.has(t.i):return
	var pos: Vector3=info.root.global_position+Vector3(0,.6,0);var v=_voice(t.i);var mv=str(t.get("move",""))
	if t.get("strike",false) and mv!="shoot":
		if mv=="charge" and v in ["m","md","f"]:_sfx("charge_"+v,pos,.05,-3.0,_pitch(t.i))   # grido di carica
		elif v!="spirit" and v!="bones":_sfx("grunt_"+v,pos,.05,-4.0,_pitch(t.i))
		if mv=="kick":_sfx("kick",pos,length*.4,-2.0)
		else:_sfx("swing",pos,length*.3,-3.0)
	if mv in ["dodge","roll"]:_sfx("dodge",pos,.1,-4.0)
	if t.get("pushed",false):_sfx("stumble",pos,0.0,-9.0)   # sbilanciato: arretra strascicando
	# il clangore della parata lo fa _parry_fx al momento dell impatto
	if mv=="load":_sfx("bow_draw",pos,.1,-6.0)
	if mv=="shoot":_sfx("bow_release",pos,length*.55,-2.0)
	if mv in ["concentrate","meditate"]:_sfx("concentrate",pos,.15,-2.0,1.0 if _voice(t.i)!="f" else 1.6)   # "Hooommmm"
	if mv=="transform":
		for tv in t.get("targets",[]):
			if minis.has(int(tv)):_sfx("frog",minis[int(tv)].root.global_position,length*.6,0.0)   # cra cra
	if SPELL_FX.has(mv):
		_sfx("cast",pos,.1,-6.0)
		var kind={"firestaff":"fire","fireball":"fire","wall":"fire","livingfire":"fire","lightning":"lightning","shock":"lightning",
			"heal":"heal","shield":"heal","vortex":"wind","float":"wind"}.get(mv,"dark")
		var special={"teleport":"teleport","dematerialize":"teleport","abyss":"crack","control":"mind_control","plague":"plague"}
		if special.has(mv):_sfx(special[mv],pos,length*.45,-3.0)
		else:_sfx("spell_"+kind,pos,length*.45,-3.0)
	var hit=int(t.get("hit",0))
	if hit>0:
		_sfx("hit",pos,t.get("delay",0.0)*0.0,-1.0)
		var dying=bool(t.get("dead",false))
		if dying and str(game.state.fighters[t.i].character)=="golem":return
		_sfx(("death_" if dying else "pain_")+v,pos,.08,-1.0 if dying else -3.0,_pitch(t.i))
	if mv=="down" and t.get("stay",false):_sfx("fall",pos,.35,-2.0)
	if mode=="passi" or (mode=="lineare" and v!="spirit"):   # passi sulla sabbia lungo il tragitto
		var fast=t.clip in ["Correre","Carica"];var gap=.27 if fast else .42
		var n=mini(int(length/gap),24);var who=str(game.state.fighters[t.i].character)
		if who=="golem":gap=.6;n=mini(int(length/gap),12)
		for k in n:
			_sfx("golem_step" if who=="golem" else "step",info.root.global_position,k*gap+.05,(-6.0 if who=="golem" else (-14.0 if not fast else -11.0)),.85 if who=="golem" else 1.0)
			if who in ARMORED and k%2==0:_sfx("armor",info.root.global_position,k*gap+.1,-16.0)
	elif mode=="lineare" and v=="spirit" and str(t.get("from",""))!=str(t.get("to","")):_sfx("spirit_move",info.root.global_position,.05,-6.0)
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
# Colpo parato: scintille e lampo tra le armi, clangore, scritta e un piccolo arretramento del difensore
func _parry_fx(defender: Dictionary,attacker: Dictionary,word: String) -> void:
	await get_tree().create_timer(.33).timeout
	if not is_instance_valid(defender.root) or not is_instance_valid(attacker.root):return
	var a: Vector3=attacker.root.global_position;var d: Vector3=defender.root.global_position
	var hit=d.lerp(a,.35)+Vector3(0,.75,0)
	if word!="SCHIVATA!":
		_one_shot(_sparks(70,3.5,Color(1,.9,.6)),hit,1.2)
		var flash=MeshInstance3D.new();var sm=SphereMesh.new();sm.radius=.08;sm.height=.16;flash.mesh=sm;var fm=_fx_mat(Color(1,.95,.8),5.0);fm.blend_mode=BaseMaterial3D.BLEND_MODE_ADD;flash.material_override=fm
		viewport.add_child(flash);flash.global_position=hit
		var ft=create_tween();ft.tween_property(flash,"scale",Vector3.ONE*4,.15);ft.parallel().tween_property(fm,"albedo_color:a",0.0,.2);ft.tween_callback(flash.queue_free)
		_flicker_light(hit,Color(1,.9,.7),3.0,2.5,.25)
		var dc=""
		for k in minis:
			if minis[k]==defender:dc=str(game.state.fighters[k].character)
		_sfx("shield_block" if dc in SHIELDED else "clash",hit,0.0,0.0)
	var l=Label3D.new();l.text=word;l.font_size=64;l.outline_size=14;l.modulate=Color("9fd6ff") if word!="MANCATO" else Color("d0d0d0");l.billboard=BaseMaterial3D.BILLBOARD_ENABLED;l.no_depth_test=true
	viewport.add_child(l);l.global_position=d+Vector3(0,1.45,0)
	var t=create_tween();t.tween_property(l,"global_position:y",l.global_position.y+.5,1.0);t.parallel().tween_property(l,"modulate:a",0.0,1.0).set_delay(.4);t.tween_callback(l.queue_free)
	var fig: Node3D=defender.pivot;var back=(d-a);back.y=0
	if back.length()>.01 and word!="MANCATO":   # il difensore cede un passo all'impatto e torna
		back=back.normalized()*.12;var p0=fig.position
		var kt=create_tween();kt.tween_property(fig,"global_position",fig.global_position+back,.08);kt.tween_property(fig,"position",p0,.25)
# colpo di lancia a due esagoni: una striscia dorata sul terreno dal lanciere al bersaglio e la scritta
func _reach_fx(from: Vector3,to: Vector3,delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	var d=to-from;d.y=0
	if d.length()<.1:return
	var strip=MeshInstance3D.new();var pm=PlaneMesh.new();pm.size=Vector2(.32,d.length());strip.mesh=pm
	var mat=_fx_mat(Color(1,.82,.3),3.0);mat.blend_mode=BaseMaterial3D.BLEND_MODE_ADD;strip.material_override=mat
	viewport.add_child(strip);strip.global_position=from+d*.5+Vector3(0,.06,0);strip.rotation.y=atan2(d.x,d.z)
	_ring(to,Color(1,.82,.3),.55,.6)
	var l=Label3D.new();l.text="PORTATA 2";l.font_size=56;l.outline_size=12;l.modulate=Color(1,.85,.35);l.billboard=BaseMaterial3D.BILLBOARD_ENABLED;l.no_depth_test=true
	viewport.add_child(l);l.global_position=from+d*.5+Vector3(0,1.3,0)
	var tw=create_tween();tw.tween_property(mat,"albedo_color:a",0.0,1.4).set_delay(.4);tw.parallel().tween_property(l,"modulate:a",0.0,1.0).set_delay(.8)
	tw.tween_callback(func():strip.queue_free();l.queue_free())
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
		minis[i].root.position=cell_pos(initial[i].cell);minis[i].pivot.rotation.y=facing_yaw(int(initial[i].facing));minis[i].root.visible=true;minis[i].pivot.visible=true;minis[i].pivot.scale=Vector3.ONE
		if minis[i].ap:minis[i].ap.play("In guardia",0.0)
		var q=game.state.fighters[i];_set_status(i,int(q.max_hp),int(q.max_hp),true,0);_set_rim(i,initial[i].current,int(initial[i].facing))
	for i in minis:
		if not initial.has(i):minis[i].root.visible=false   # evocati (golem): compaiono quando entrano in scena
		for m in minis[i].get("bones",[]):
			if is_instance_valid(m):m.queue_free()
		minis[i].erase("bones")
		if minis[i].get("model")!=null and not minis[i].has("frog_node"):minis[i].model.visible=true
		minis[i].erase("buried");minis[i].erase("dying")
	clear_blood();clear_arrows();_show_effects([]);_apply_states({})
	for key in pickup_nodes:
		if is_instance_valid(pickup_nodes[key]):pickup_nodes[key].queue_free()
	pickup_nodes={};_show_pickups(initial_pickups)
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
	var moves={};var acts=[];var labels={};var sn=0
	for step in group:
		sn+=1
		for t in step:
			if t.has("labels"):labels=t.labels;continue
			if not minis.has(t.i):continue
			if t.from.distance_to(t.to)>.05 and not t.get("after",false) and not t.get("pushed",false):
				if moves.has(t.i):moves[t.i].to=t.to;moves[t.i].yaw=t.yaw;moves[t.i].facing=t.get("facing",-1)   # più spostamenti nello stesso turno: un solo tragitto
				else:moves[t.i]=t.duplicate();moves[t.i].delay=0.0
			else:t["_step"]=sn;acts.append(t)
	var span=0.0
	for i in moves:span=maxf(span,_plan(moves[i],minis[i]).length)
	var longest=0.0
	for i in moves:longest=maxf(longest,_run_track(moves[i],minis[i],true,span))
	if longest>0:await get_tree().create_timer(longest).timeout
	longest=0.0
	var impacts={}   # per ogni passo: istante del colpo, così parate e reazioni partono insieme al colpo
	for t in acts:
		if t.get("strike",false):
			longest=maxf(longest,t.delay+_run_track(t,minis[t.i],true));t["_done"]=true
			impacts[t._step]=maxf(impacts.get(t._step,-1.0),float(t.get("impact_at",-1.0)))
	for t in acts:
		if t.get("_done",false):continue
		var imp=float(impacts.get(t._step,-1.0))
		if imp>=0.0 and t.has("parried"):t.delay=maxf(.05,imp-.35)
		elif imp>=0.0 and t.get("after_strike",false):t.delay=maxf(t.delay,imp)
		longest=maxf(longest,t.delay+_run_track(t,minis[t.i],true))
	if longest>0:await get_tree().create_timer(longest).timeout
	for step in group:
		for t in step:
			if t.has("effects"):_show_effects(t.effects)
			if t.has("pickups"):_show_pickups(t.pickups)
			if t.has("states"):_apply_states(t.states)
	for i in labels:
		if minis.has(i):_set_status(i,labels[i][0],labels[i][1],labels[i][2],labels[i][3] if labels[i].size()>3 else -1)
	for t in moves.values()+acts:
		var info=minis.get(t.i)
		if info and info.ap and not t.get("stay",false) and not t.clip in ["A terra","Morte"]:_end_pose(t.i)

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
# due dita (iPad, telefoni): pizzico = zoom, rotazione delle dita = gira la mappa
var _touches={}
func _pinch(event: InputEvent) -> bool:
	if event is InputEventMagnifyGesture:   # trackpad e Safari
		var f=event.factor;zoom=clampf(zoom*f,.6,3.0);_place_camera();accept_event();return true
	if event is InputEventScreenTouch:
		if event.pressed:_touches[event.index]=event.position
		else:_touches.erase(event.index)
		if _touches.size()>=2:_dragging=true   # niente clic al rilascio dopo un pizzico
		return false
	if event is InputEventScreenDrag and _touches.has(event.index):
		if _touches.size()<2:_touches[event.index]=event.position;return false
		var keys=_touches.keys();var other=keys[1] if keys[0]==event.index else keys[0]
		var a0: Vector2=_touches[event.index];var b: Vector2=_touches[other];var a1: Vector2=event.position
		var d0=a0.distance_to(b);var d1=a1.distance_to(b)
		if d0>8.0 and d1>8.0:
			var f=d1/d0;zoom=clampf(zoom*f,.6,3.0);_place_camera()
			var da=(a1-b).angle()-(a0-b).angle()
			if absf(da)<.5:follow=false;yaw-=da;_place_camera()
		_touches[event.index]=a1;_dragging=true;accept_event();return true
	return false
func _gui_input(event: InputEvent) -> void:
	if game==null:return
	if _pinch(event):return
	if _touches.size()>=2 and (event is InputEventMouseMotion or event is InputEventMouseButton):return   # il mouse emulato dal tocco tace mentre si pizzica
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
