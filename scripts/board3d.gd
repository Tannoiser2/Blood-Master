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
	"nuchra":"res://assets/models/nuchra/nuchra.glb","ramok":"res://assets/models/ramok/ramok.glb"}
const CLIP={"guard":"In guardia","advance":"Avanzare","run":"Correre","charge":"Carica","cleave":"Fendente",
	"left":"Taglio Sx","right":"Taglio Dx","thrust":"Affondo","kick":"Calcio","parry_l":"Parata Sx","parry_r":"Parata Dx",
	"dodge":"Schivata","roll":"Rotolare","unbalanced":"Sbilanciato","down":"A terra","rise":"Rialzarsi","again":"In guardia",
	"spin":"Taglio Dx","sweep":"Taglio Sx"}   # rotazione e spazzata: le clip di taglio più vicine
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
	var info={"root":root,"pivot":pivot,"sides":sides,"model":null,"ap":null,"token":null}
	var path=MODELS.get(p.character,"")
	if path!="":
		var model=load(path).instantiate();model.scale=Vector3.ONE*.58;pivot.add_child(model);info.model=model  # ~1,1 m: proporzionata a un esagono da 1,2 m
		info.ap=_find_animation(model)
		if info.ap:_extract_root_motion(info)
		for n in ["In guardia","Riposo","Avanzare","Correre","Carica"]:
			if info.ap and info.ap.has_animation(n):info.ap.get_animation(n).loop_mode=Animation.LOOP_LINEAR
		if info.ap:info.ap.play("In guardia")
	else:
		# personaggio senza modello 3D: pedina in piedi con il disegno della mossa corrente
		var s=Sprite3D.new();s.pixel_size=.0019;s.position.y=.47;s.billboard=BaseMaterial3D.BILLBOARD_FIXED_Y;s.shaded=false;pivot.add_child(s);info.token=s
	# barra di stato sopra la testa: nome e ferite (sempre rivolta alla camera)
	var bar=Node3D.new();bar.position.y=1.32+.16*(i%2);root.add_child(bar);info.bar=bar
	var label=Label3D.new();label.text=p.name;label.font_size=26;label.outline_size=8;label.modulate=team;label.position.y=.085;label.no_depth_test=true;label.render_priority=3;bar.add_child(label);info.label=label
	var back=MeshInstance3D.new();var bq=QuadMesh.new();bq.size=Vector2(.64,.075);back.mesh=bq
	var bk=StandardMaterial3D.new();bk.albedo_color=Color(0,0,0,.75);bk.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;bk.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;bk.no_depth_test=true;bk.render_priority=1;back.material_override=bk;bar.add_child(back)
	var fill=MeshInstance3D.new();var fq=QuadMesh.new();fq.size=Vector2(.6,.05);fill.mesh=fq;fill.position.z=.001
	var fm=StandardMaterial3D.new();fm.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;fm.no_depth_test=true;fm.render_priority=2;fill.material_override=fm;bar.add_child(fill);info.fill=fill;info.fill_mat=fm
	minis[i]=info;return info

func _set_status(i: int,hp: int,max_hp: int,alive: bool) -> void:
	var info=minis[i];var p=game.state.fighters[i]
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
			info.root.position=cell_pos(p.cell);info.pivot.rotation.y=facing_yaw(int(p.facing));_token(i)
			initial[i]=now;prev[i]=now;continue
		var was=prev[i]
		if now.done and not was.done and now.alive:actors.append(i)
		elif now.cell!=was.cell or now.facing!=was.facing:actors.append(i)
		if now.hp<was.hp or (now.unbalanced and not was.unbalanced) or (now.down and not was.down) or (was.alive and not now.alive):victims.append(i)
		elif was.down and not now.down and not i in actors:actors.append(i)
	for i in actors:
		var p=game.state.fighters[i];var was=prev[i];var id=p.current
		if i in victims and game.move(p).get("attack")==null and not id in MOVING:continue
		var track={"i":i,"clip":CLIP.get(id,"In guardia"),"from":cell_pos(was.cell),"to":cell_pos(p.cell),"yaw":facing_yaw(int(p.facing)),"facing":int(p.facing),"delay":0.0,"move":id,"strike":game.move(p).get("attack")!=null}
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
		var clip="A terra" if (p.down or not p.alive) else "Sbilanciato"
		step.append({"i":i,"clip":clip,"from":cell_pos(prev[i].cell),"to":cell_pos(p.cell),"yaw":facing_yaw(int(p.facing)),"facing":int(p.facing),"delay":strike_delay,"move":"down" if clip=="A terra" else "unbalanced","strike":false,"hit":prev[i].hp-int(p.hp),"stay":p.down or not p.alive})
	for i in game.state.fighters.size():
		if game.state.fighters[i].cell!="":prev[i]=_view(game.state.fighters[i])
	if not step.is_empty():
		var labels={}   # etichette dopo questo passo, per il replay
		for i in minis:
			var q=game.state.fighters[i];labels[i]=[int(q.hp),int(q.max_hp),q.alive]
		step.append({"labels":labels})
		if is_visible_in_tree():
			queue.append(step)
			if not playing:_play_queue()
		else:history.append(step)   # mappa 3D nascosta: registro per il replay, senza animare
	_draw_overlay()
	_refresh_tokens()

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
			if p.cell!="":info.root.position=cell_pos(p.cell)
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
	var longest=0.0
	for t in step:
		if t.has("labels"):continue
		var info=minis.get(t.i)
		if info==null:continue
		var dur=_run_track(t,info,fluid)
		longest=maxf(longest,t.delay+dur)
	await get_tree().create_timer(longest).timeout
	for t in step:
		if t.has("labels"):
			if fluid:
				for i in t.labels:
					if minis.has(i):_set_status(i,t.labels[i][0],t.labels[i][1],t.labels[i][2])
			continue
		var info=minis.get(t.i)
		if info and info.ap and not t.get("stay",false) and t.clip!="A terra":info.ap.play("In guardia",.25)

func _run_track(t: Dictionary,info: Dictionary,fluid: bool) -> float:
	var ap=info.ap;var root=info.root;var pivot=info.pivot
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
		elif not m.is_empty() and m.net.length()>.15:
			mode="profilo"                                                  # la clip avanza da sola
		else:
			mode="lineare"
	var loops=1
	if mode=="profilo":
		loops=maxi(1,roundi(dist/m.net.length()));length=anim.length*loops
	var tw=create_tween()
	if t.delay>0:tw.tween_interval(t.delay)
	if turn>0:tw.tween_property(pivot,"rotation:y",pivot.rotation.y+angle_difference(pivot.rotation.y,t.yaw),turn)
	tw.tween_callback(func():
		_set_rim(t.i,t.move,t.get("facing",-1))
		if anim:
			if mode=="passi" or mode=="profilo":anim.loop_mode=Animation.LOOP_LINEAR
			ap.play(t.clip,.12 if fluid else .18)
		if t.get("hit",0)>0:_float(root.position,"-%d" % t.hit))
	if mode=="fermo":
		tw.tween_interval(length)
	else:
		root.position=t.from
		var from: Vector3=t.from;var to: Vector3=t.to
		if mode=="profilo":
			var clip_len=anim.length
			tw.tween_method(func(x: float):
				var k=floorf(x/clip_len);var p=(k+_progress(m,x-k*clip_len))/loops
				root.position=from.lerp(to,minf(p,1.0)),0.0,length,length)
		else:
			tw.tween_property(root,"position",to,length)
		if mode=="profilo" and anim and not t.clip in ["Carica"]:
			tw.tween_callback(func():anim.loop_mode=Animation.LOOP_NONE)
	return turn+length

func _float(at: Vector3,text: String) -> void:
	var l=Label3D.new();l.text=text;l.font_size=72;l.outline_size=14;l.modulate=Color("ff7b6b");l.billboard=BaseMaterial3D.BILLBOARD_ENABLED;l.no_depth_test=true
	viewport.add_child(l);l.position=at+Vector3(0,1.35,0)
	var t=create_tween();t.tween_property(l,"position:y",l.position.y+.7,1.2);t.parallel().tween_property(l,"modulate:a",0.0,1.2);t.tween_callback(l.queue_free)

func replay() -> void:
	# Riproduce tutto lo scontro dall'inizio, un passo dopo l'altro senza pause fra i turni.
	if replaying or history.is_empty():return
	replaying=true
	while playing:await get_tree().create_timer(.1).timeout   # aspetto che finisca la mossa in corso
	playing=true
	var final={}
	for i in minis:final[i]={"pos":minis[i].root.position,"yaw":minis[i].pivot.rotation.y}
	for i in initial:
		if not minis.has(i):continue
		minis[i].root.position=cell_pos(initial[i].cell);minis[i].pivot.rotation.y=facing_yaw(int(initial[i].facing));minis[i].root.visible=true
		if minis[i].ap:minis[i].ap.play("In guardia",0.0)
		var q=game.state.fighters[i];_set_status(i,int(q.max_hp),int(q.max_hp),true);_set_rim(i,initial[i].current,int(initial[i].facing))
	await get_tree().create_timer(.6).timeout
	for step in history:
		await _play_step(step,true)
	replaying=false;playing=false;_refresh_tokens()

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
