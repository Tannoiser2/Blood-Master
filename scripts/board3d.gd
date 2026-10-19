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
const MODELS={"gascor":"res://assets/models/gascor/gascor.glb","anteos":"res://assets/models/anteos/anteos.glb"}
const CLIP={"guard":"In guardia","advance":"Avanzare","run":"Correre","charge":"Carica","cleave":"Fendente",
	"left":"Taglio Sx","right":"Taglio Dx","thrust":"Affondo","kick":"Calcio","parry_l":"Parata Sx","parry_r":"Parata Dx",
	"dodge":"Schivata","roll":"Rotolare","unbalanced":"Sbilanciato","down":"A terra","rise":"Rialzarsi","again":"In guardia"}
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
	if not follow or minis.is_empty() or not is_visible_in_tree():return
	target=target.lerp(_action_center()+Vector3(0,.8,0),clampf(delta*2.0,0,1))
	dist=lerpf(dist,clampf(6.5+_action_spread()*1.6,6.5,16.0),clampf(delta*1.5,0,1))
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
	var base=MeshInstance3D.new();var cyl=CylinderMesh.new();cyl.top_radius=.42;cyl.bottom_radius=.45;cyl.height=.05;cyl.radial_segments=32;base.mesh=cyl;base.position.y=.025
	var bm=StandardMaterial3D.new();bm.albedo_color=Color("1d2628");bm.roughness=.7;base.material_override=bm;root.add_child(base)
	var ring=MeshInstance3D.new();var tor=TorusMesh.new();tor.inner_radius=.42;tor.outer_radius=.47;ring.mesh=tor;ring.position.y=.04
	var rm=StandardMaterial3D.new();rm.albedo_color=team;rm.emission_enabled=true;rm.emission=team*.4;ring.material_override=rm;root.add_child(ring)
	var notch=MeshInstance3D.new();var bx=BoxMesh.new();bx.size=Vector3(.12,.03,.14);notch.mesh=bx;notch.position=Vector3(0,.06,.47);notch.material_override=rm;root.add_child(notch)
	var info={"root":root,"model":null,"ap":null,"token":null}
	var path=MODELS.get(p.character,"")
	if path!="":
		var model=load(path).instantiate();model.scale=Vector3.ONE*1.15;root.add_child(model);info.model=model
		info.ap=_find_animation(model)
		if info.ap:_damp_root_motion(info.ap)
		for n in ["In guardia","Riposo","Avanzare","Correre","Carica"]:
			if info.ap and info.ap.has_animation(n):info.ap.get_animation(n).loop_mode=Animation.LOOP_LINEAR
		if info.ap:info.ap.play("In guardia")
	else:
		# personaggio senza modello 3D: pedina in piedi con il disegno della mossa corrente
		var s=Sprite3D.new();s.pixel_size=.0035;s.position.y=.85;s.billboard=BaseMaterial3D.BILLBOARD_FIXED_Y;s.shaded=false;root.add_child(s);info.token=s
	var label=Label3D.new();label.text=p.name;label.font_size=36;label.outline_size=10;label.modulate=team;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.position.y=2.45+.32*(i%2);label.no_depth_test=true;root.add_child(label);info.label=label
	minis[i]=info;return info

const ATTACK_CLIPS=["Affondo","Fendente","Taglio Sx","Taglio Dx","Calcio","Carica"]
var _damped={}
func _damp_root_motion(ap: AnimationPlayer) -> void:
	# Negli attacchi il bacino avanza fino a ~1 m: sulla mappa la cella accanto è a 1,04 m,
	# quindi dimezzo lo spostamento orizzontale (X/Z) mantenendo quello verticale.
	for clip in ATTACK_CLIPS:
		if not ap.has_animation(clip):continue
		var anim=ap.get_animation(clip)
		if _damped.has(anim.get_instance_id()):continue
		_damped[anim.get_instance_id()]=true
		for t in anim.get_track_count():
			if anim.track_get_type(t)!=Animation.TYPE_POSITION_3D or not str(anim.track_get_path(t)).ends_with(":Hips"):continue
			var first: Vector3=anim.track_get_key_value(t,0)
			for k in anim.track_get_key_count(t):
				var v: Vector3=anim.track_get_key_value(t,k)
				anim.track_set_key_value(t,k,Vector3(first.x+(v.x-first.x)*.5,v.y,first.z+(v.z-first.z)*.5))
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
			info.root.position=cell_pos(p.cell);info.root.rotation.y=facing_yaw(int(p.facing));_token(i)
			initial[i]=now;prev[i]=now;continue
		var was=prev[i]
		if now.done and not was.done and now.alive:actors.append(i)
		elif now.cell!=was.cell or now.facing!=was.facing:actors.append(i)
		if now.hp<was.hp or (now.unbalanced and not was.unbalanced) or (now.down and not was.down) or (was.alive and not now.alive):victims.append(i)
		elif was.down and not now.down and not i in actors:actors.append(i)
	for i in actors:
		var p=game.state.fighters[i];var was=prev[i];var id=p.current
		if i in victims and game.move(p).get("attack")==null and not id in MOVING:continue
		var track={"i":i,"clip":CLIP.get(id,"In guardia"),"from":cell_pos(was.cell),"to":cell_pos(p.cell),"yaw":facing_yaw(int(p.facing)),"delay":0.0,"move":id,"strike":game.move(p).get("attack")!=null}
		step.append(track)
		# il difensore di fronte mostra la sua pedina difensiva mentre arriva il colpo
		if track.strike:
			var front=game.at(BloodRules.neighbor(p.cell,int(p.facing)),i)
			if front!=-1 and not front in victims and game.state.fighters[front].current in DEFENSIVE and minis.has(front):
				step.append({"i":front,"clip":CLIP[game.state.fighters[front].current],"from":cell_pos(game.state.fighters[front].cell),"to":cell_pos(game.state.fighters[front].cell),"yaw":facing_yaw(int(game.state.fighters[front].facing)),"delay":.1,"move":game.state.fighters[front].current,"strike":false})
	var strike_delay=0.0
	for t in step:
		if t.get("strike",false) and minis[t.i].ap:strike_delay=maxf(strike_delay,minis[t.i].ap.get_animation(t.clip).length*.45)
	for i in victims:
		var p=game.state.fighters[i]
		var clip="A terra" if (p.down or not p.alive) else "Sbilanciato"
		step.append({"i":i,"clip":clip,"from":cell_pos(prev[i].cell),"to":cell_pos(p.cell),"yaw":facing_yaw(int(p.facing)),"delay":strike_delay,"move":"down" if clip=="A terra" else "unbalanced","strike":false,"hit":prev[i].hp-int(p.hp),"stay":p.down or not p.alive})
	for i in game.state.fighters.size():
		if game.state.fighters[i].cell!="":prev[i]=_view(game.state.fighters[i])
	if not step.is_empty():
		var labels={}   # etichette dopo questo passo, per il replay
		for i in minis:
			var q=game.state.fighters[i];labels[i]=("%s  †" % q.name) if not q.alive else ("%s  %d/%d" % [q.name,maxi(0,int(q.hp)),int(q.max_hp)])
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
		info.label.text=("%s  †" % p.name) if not p.alive else ("%s  %d/%d" % [p.name,maxi(0,int(p.hp)),int(p.max_hp)])
		info.root.visible=p.cell!=""
		if not playing:
			if info.token:_token(i)
			if p.cell!="":info.root.position=cell_pos(p.cell)
			if info.ap and p.down and info.ap.current_animation!="A terra":info.ap.play("A terra",0.0);info.ap.seek(info.ap.get_animation("A terra").length-.05,true)
			var f=int(p.facing)
			if i==focus_fighter and preview_facing>=0:f=preview_facing
			info.root.rotation.y=lerp_angle(info.root.rotation.y,facing_yaw(f),1.0)

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
					if minis.has(i):minis[i].label.text=t.labels[i]
			continue
		var info=minis.get(t.i)
		if info and info.ap and not t.get("stay",false) and t.clip!="A terra":info.ap.play("In guardia",.25)

func _run_track(t: Dictionary,info: Dictionary,fluid: bool) -> float:
	var ap=info.ap;var root=info.root
	var length=1.2
	if ap and ap.has_animation(t.clip):length=ap.get_animation(t.clip).length
	if t.clip in ["In guardia","Avanzare","Correre","Carica"]:length=minf(length,1.6)
	length=minf(length,3.2)
	var turn=.22 if absf(angle_difference(root.rotation.y,t.yaw))>.05 else 0.0
	var tw=create_tween()
	if t.delay>0:tw.tween_interval(t.delay)
	if turn>0:tw.tween_property(root,"rotation:y",root.rotation.y+angle_difference(root.rotation.y,t.yaw),turn)
	tw.tween_callback(func():
		if ap and ap.has_animation(t.clip):ap.play(t.clip,.12 if fluid else .18)
		if t.get("hit",0)>0:_float(root.position,"-%d" % t.hit))
	if t.from.distance_to(t.to)>.05:
		root.position=t.from
		tw.tween_property(root,"position",t.to,maxf(.5,length*.85))
	else:
		tw.tween_interval(length)
	return turn+length

func _float(at: Vector3,text: String) -> void:
	var l=Label3D.new();l.text=text;l.font_size=110;l.outline_size=20;l.modulate=Color("ff7b6b");l.billboard=BaseMaterial3D.BILLBOARD_ENABLED;l.no_depth_test=true
	viewport.add_child(l);l.position=at+Vector3(0,2.3,0)
	var t=create_tween();t.tween_property(l,"position:y",l.position.y+.7,1.2);t.parallel().tween_property(l,"modulate:a",0.0,1.2);t.tween_callback(l.queue_free)

func replay() -> void:
	# Riproduce tutto lo scontro dall'inizio, un passo dopo l'altro senza pause fra i turni.
	if replaying or history.is_empty():return
	replaying=true
	while playing:await get_tree().create_timer(.1).timeout   # aspetto che finisca la mossa in corso
	playing=true
	var final={}
	for i in minis:final[i]={"pos":minis[i].root.position,"yaw":minis[i].root.rotation.y}
	for i in initial:
		if not minis.has(i):continue
		minis[i].root.position=cell_pos(initial[i].cell);minis[i].root.rotation.y=facing_yaw(int(initial[i].facing));minis[i].root.visible=true
		if minis[i].ap:minis[i].ap.play("In guardia",0.0)
		var q=game.state.fighters[i];minis[i].label.text="%s  %d/%d" % [q.name,int(q.max_hp),int(q.max_hp)]
	await get_tree().create_timer(.6).timeout
	for step in history:
		await _play_step(step,true)
	replaying=false;playing=false;_refresh_tokens()

# ---------------------------------------------------------------- celle evidenziate
func _draw_overlay() -> void:
	var im: ImmediateMesh=overlay.mesh;im.clear_surfaces()
	if game==null or game.state.is_empty():return
	var fills=[]
	if game.state.get("phase","")=="deploy":
		for k in game.cells:
			if game.cells[k].entry:fills.append([k,Color(.1,.8,.7,.22)])
	for k in highlights:fills.append([k,Color(.85,.68,.3,.3)])
	if not fills.is_empty():
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for f in fills:
			var c=cell_pos(f[0])+Vector3(0,.02,0)
			for s in 6:
				im.surface_set_color(f[1]);im.surface_add_vertex(c)
				im.surface_set_color(f[1]);im.surface_add_vertex(c+_corner(s))
				im.surface_set_color(f[1]);im.surface_add_vertex(c+_corner(s+1))
		im.surface_end()
	var lines=[]
	if show_grid:
		for k in game.cells:lines.append([k,Color(.05,.07,.06,.45)])
	for k in highlights:lines.append([k,Color("e0ba77")])
	if hovered!="":lines.append([hovered,Color(1,1,1,.8)])
	if selected!="":lines.append([selected,Color("fff0bf")])
	if not lines.is_empty():
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		for l in lines:
			var c=cell_pos(l[0])+Vector3(0,.03,0)
			for s in 6:
				im.surface_set_color(l[1]);im.surface_add_vertex(c+_corner(s))
				im.surface_set_color(l[1]);im.surface_add_vertex(c+_corner(s+1))
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

func _gui_input(event: InputEvent) -> void:
	if game==null:return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_UP:zoom=clampf(zoom*1.1,.6,3.0);_place_camera();accept_event()
		elif event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_DOWN:zoom=clampf(zoom/1.1,.6,3.0);_place_camera();accept_event()
		elif event.pressed and event.button_index==MOUSE_BUTTON_LEFT and hovered!="":cell_clicked.emit(hovered)
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			follow=false
			yaw-=event.relative.x*.008;pitch=clampf(pitch+event.relative.y*.005,.25,1.45);_place_camera()
		elif event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			follow=false
			var right=camera.global_transform.basis.x;var fwd=Vector3(-sin(yaw),0,-cos(yaw))
			target+=(-right*event.relative.x+fwd*event.relative.y)*.012*dist/(zoom*10);_place_camera()
		var cell=_cell_at(event.position)
		if cell!=hovered:hovered=cell;_draw_overlay()
		tooltip_text=""
		if hovered!="" and not game.state.is_empty():
			var j=game.at(hovered)
			if j!=-1:
				var p=game.state.fighters[j];tooltip_text="%s · %s\n%d ferite rimaste · %d fatica" % [p.name,game.move(p).get("name",""),p.hp,p.fatigue]
