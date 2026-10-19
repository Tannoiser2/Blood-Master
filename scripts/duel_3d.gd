extends Node3D
# Duello 3D di prova: Gascor contro Anteos con le animazioni delle pedine.
# Usa i valori delle mosse (data/characters.json) e le tabelle del regolamento
# (BloodRules.combat_table / balance_table) in forma semplificata: duello frontale,
# niente esagoni né movimento sulla mappa; ordine d'azione tirato a sorte ogni round.

const CLIP={"guard":"In guardia","advance":"Avanzare","run":"Correre","charge":"Carica","cleave":"Fendente",
	"left":"Taglio Sx","right":"Taglio Dx","thrust":"Affondo","kick":"Calcio","parry_l":"Parata Sx","parry_r":"Parata Dx",
	"dodge":"Schivata","roll":"Rotolare","unbalanced":"Sbilanciato","down":"A terra","rise":"Rialzarsi"}
const CHOOSABLE=["guard","advance","run","charge","cleave","left","right","thrust","kick","parry_l","parry_r","dodge","roll"]
const FIGHTERS=[
	{"id":"gascor","model":"res://assets/models/gascor/gascor.glb","x":-1.05,"color":Color("79cfbf")},
	{"id":"anteos","model":"res://assets/models/anteos/anteos.glb","x":1.05,"color":Color("ed9992")}]

var catalog:Dictionary
var F:Array=[]
var rng=RandomNumberGenerator.new()
var busy=false
var camera:Camera3D
var angle=0.0
var pitch=0.18
var distance=5.2
var dragging=false
var log_box:RichTextLabel
var fight_button:Button
var ai_toggle:CheckBox

func _ready():
	rng.randomize()
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://data/characters.json"))
	_build_world()
	var layer=CanvasLayer.new();add_child(layer)
	var title=Label.new();title.text="DUELLO 3D  ·  GASCOR contro ANTEOS";title.position=Vector2(28,18);title.add_theme_font_size_override("font_size",26);layer.add_child(title)
	var sub=Label.new();sub.text="Scegli una pedina per ciascuno e premi Combatti · regole semplificate (duello frontale)";sub.position=Vector2(28,56);sub.modulate=Color(1,1,1,.75);layer.add_child(sub)
	for i in 2:_build_fighter(i,layer)
	var bottom=HBoxContainer.new();bottom.position=Vector2(28,640);bottom.add_theme_constant_override("separation",12);layer.add_child(bottom)
	fight_button=Button.new();fight_button.text="  Combatti!  ";fight_button.add_theme_font_size_override("font_size",22);fight_button.pressed.connect(_round);bottom.add_child(fight_button)
	var reset=Button.new();reset.text="Nuovo duello";reset.pressed.connect(_reset);bottom.add_child(reset)
	ai_toggle=CheckBox.new();ai_toggle.text="Anteos sceglie da solo";ai_toggle.button_pressed=true;ai_toggle.toggled.connect(func(_on):_refresh());bottom.add_child(ai_toggle)
	var back=Button.new();back.text="Torna al gioco";back.pressed.connect(func():get_tree().change_scene_to_file("res://scenes/main.tscn"));bottom.add_child(back)
	log_box=RichTextLabel.new();log_box.position=Vector2(330,470);log_box.size=Vector2(620,160);log_box.scroll_following=true;log_box.bbcode_enabled=true
	var bg=StyleBoxFlat.new();bg.bg_color=Color(0,0,0,.45);bg.set_corner_radius_all(6);bg.content_margin_left=10;bg.content_margin_top=6;log_box.add_theme_stylebox_override("normal",bg);layer.add_child(log_box)
	_reset()

func _build_world():
	RenderingServer.set_default_clear_color(Color("101c22"))
	var env=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("101c22")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("b7d1df");env.environment.ambient_light_energy=.6
	env.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC;add_child(env)
	for cfg in [[Vector3(-3,5,4),Color("fff0d0"),2.0],[Vector3(4,3,2),Color("a8dce8"),1.1],[Vector3(1,4,-3),Color("ffcc7a"),1.6]]:
		var light=DirectionalLight3D.new();add_child(light);light.position=cfg[0];light.look_at(Vector3(0,1,0));light.light_color=cfg[1];light.light_energy=cfg[2];light.shadow_enabled=cfg[2]>1.9
	var ground=MeshInstance3D.new();var disk=CylinderMesh.new();disk.top_radius=4.2;disk.bottom_radius=4.2;disk.height=.05;ground.mesh=disk;ground.position.y=-.026
	var mat=StandardMaterial3D.new();mat.albedo_color=Color("2a3a3f");mat.roughness=.95;ground.material_override=mat;add_child(ground)
	var ring=MeshInstance3D.new();var tor=TorusMesh.new();tor.inner_radius=4.1;tor.outer_radius=4.25;ring.mesh=tor;var rm=StandardMaterial3D.new();rm.albedo_color=Color("b08a3a");rm.metallic=.6;ring.material_override=rm;add_child(ring)
	camera=Camera3D.new();camera.fov=38;add_child(camera)

func _build_fighter(i:int,layer:CanvasLayer):
	var cfg=FIGHTERS[i];var d=catalog[cfg.id]
	var root=Node3D.new();add_child(root)
	var model=load(cfg.model).instantiate();root.add_child(model)
	root.rotation.y=PI/2 if i==0 else -PI/2  # si guardano: il modello Meshy guarda verso +Z
	var ap=_find_animation(model)
	for n in ["In guardia","Riposo","Avanzare","Correre","Carica"]:
		if ap.has_animation(n):ap.get_animation(n).loop_mode=Animation.LOOP_LINEAR
	var panel=VBoxContainer.new();panel.position=Vector2(28 if i==0 else 1000,92);panel.custom_minimum_size=Vector2(252,0);layer.add_child(panel)
	var who=Label.new();who.text=d.name.to_upper()+"  ·  "+d.title;who.add_theme_color_override("font_color",cfg.color);who.add_theme_font_size_override("font_size",19);panel.add_child(who)
	var hp=ProgressBar.new();hp.max_value=int(d.hp);hp.custom_minimum_size=Vector2(252,18);hp.show_percentage=false;panel.add_child(hp)
	var info=Label.new();panel.add_child(info)
	var grid=GridContainer.new();grid.columns=4;grid.add_theme_constant_override("h_separation",4);grid.add_theme_constant_override("v_separation",4);panel.add_child(grid)
	var group=ButtonGroup.new();var buttons={}
	for id in CHOOSABLE+["rise"]:
		var m=d.moves[id];var b=Button.new();b.toggle_mode=true;b.button_group=group;b.icon=load(m.texture);b.expand_icon=true;b.custom_minimum_size=Vector2(60,60)
		b.tooltip_text="%s\nattacco %s · difesa %s%s" % [m.name,str(m.attack) if m.attack!=null else "–",str(m.defense),"\nfatica +1" if int(m.fatigue)>0 else ""]
		b.toggled.connect(func(on):
			if on:
				F[i].choice=id
				_refresh())
		grid.add_child(b);buttons[id]=b
	var choice_label=Label.new();panel.add_child(choice_label)
	F.append({"cfg":cfg,"def":d,"root":root,"ap":ap,"hp_bar":hp,"info":info,"buttons":buttons,"choice_label":choice_label})

func _find_animation(n:Node)->AnimationPlayer:
	if n is AnimationPlayer:return n
	for c in n.get_children():
		var f=_find_animation(c)
		if f:return f
	return null

func _reset():
	if busy:return
	for f in F:
		f.hp=int(f.def.hp);f.fatigue=0;f.state="ok";f.choice="guard";f.prev="";f.root.position=Vector3(f.cfg.x,0,0)
		f.ap.play("In guardia",.2)
	for f in F:f.buttons["guard"].button_pressed=true
	log_box.clear();_log("[b]Nuovo duello.[/b] Gascor e Anteos entrano nell’arena.")
	_refresh()

func _available(f)->Array:
	if f.state!="ok":return ["rise"]
	var out=[]
	for id in CHOOSABLE:
		var m=f.def.moves[id]
		if int(m.fatigue)>0 and m.attack!=null and f.prev!="" and int(f.def.moves[f.prev].fatigue)>0 and f.def.moves[f.prev].attack!=null:continue
		out.append(id)
	return out

func _refresh():
	for i in 2:
		var f=F[i];var avail=_available(f)
		if not f.choice in avail:f.choice=avail[0];f.buttons[f.choice].button_pressed=true
		for id in f.buttons:
			f.buttons[id].disabled=busy or not id in avail or (i==1 and ai_toggle.button_pressed)
			f.buttons[id].visible=id!="rise" or f.state!="ok"
		f.hp_bar.value=f.hp
		f.info.text="Ferite %d/%d · fatica %d%s" % [f.hp,int(f.def.hp),f.fatigue,{"ok":"","unbalanced":" · SBILANCIATO","down":" · A TERRA"}[f.state]]
		f.choice_label.text="Pedina: "+("(segreta)" if i==1 and ai_toggle.button_pressed else f.def.moves[f.choice].name)
	fight_button.disabled=busy or F[0].hp<=0 or F[1].hp<=0

func _log(s:String):log_box.append_text(s+"\n")
func die()->int:return rng.randi_range(1,6)

func _ai_choice(f,o)->String:
	var avail=_available(f)
	if avail.size()==1:return avail[0]
	var weights={"cleave":3,"thrust":3,"left":3,"right":3,"kick":2,"charge":2,"parry_l":2,"parry_r":2,"dodge":1,"guard":1,"roll":1,"advance":1,"run":1}
	if o.state!="ok":weights.cleave=7;weights.thrust=6
	var total=0
	for id in avail:total+=weights.get(id,1)
	var r=rng.randi_range(1,total)
	for id in avail:
		r-=weights.get(id,1)
		if r<=0:return id
	return avail[0]

func _round():
	if busy:return
	busy=true
	if ai_toggle.button_pressed:F[1].choice=_ai_choice(F[1],F[0])
	_refresh()
	var order=[0,1];if rng.randi()%2==1:order=[1,0]
	_log("[b]Round[/b] · %s: %s · %s: %s · agisce per primo %s." % [F[0].def.name,F[0].def.moves[F[0].choice].name,F[1].def.name,F[1].def.moves[F[1].choice].name,F[order[0]].def.name])
	var start_state=[F[0].state,F[1].state]
	var acted=[false,false]
	for i in order:
		var f=F[i];var o=F[1-i]
		if f.hp<=0 or o.hp<=0:break
		if f.state!=start_state[i] and f.choice!="rise":
			_log(f.def.name+" è stato sbilanciato e perde la sua azione.");continue
		var m=f.def.moves[f.choice]
		if f.choice=="rise":
			f.state="ok";await _play(f,"rise");f.ap.play("In guardia",.3);_log(f.def.name+" si rialza.");acted[i]=true;continue
		if m.attack==null:
			if not acted[i]:await _play(f,f.choice);f.ap.play("In guardia",.3)
			acted[i]=true;continue
		# attacco: il difensore mostra la sua pedina (se non l'ha già giocata e non è a terra)
		var defense_id=o.choice if o.state=="ok" else o.state
		if o.state=="ok" and not acted[1-i] and o.def.moves[o.choice].attack==null:
			_play(o,o.choice);acted[1-i]=true
		var clip=f.ap.get_animation(CLIP[f.choice]);f.ap.play(CLIP[f.choice],.15)
		await get_tree().create_timer(clip.length*.45).timeout
		await _resolve(f,o,m,o.def.moves[defense_id])
		var rest=clip.length*.55
		await get_tree().create_timer(rest).timeout
		if f.hp>0:f.ap.play("In guardia",.3)
		acted[i]=true
	for f in F:
		f.prev=f.choice
		if f.def.moves[f.choice].rest and f.fatigue>0:f.fatigue-=1
		if f.hp<=0:_log("[b]%s è fuori combattimento![/b] Vince %s." % [f.def.name,F[1-F.find(f)].def.name])
	busy=false;_refresh()

func _play(f,id:String):
	var a=f.ap.get_animation(CLIP[id]);f.ap.play(CLIP[id],.15)
	await get_tree().create_timer(minf(a.length,2.2) if a.loop_mode==Animation.LOOP_NONE else 1.4).timeout

func _resolve(a,b,m:Dictionary,dm:Dictionary):
	var dv=int(dm.defense)
	if not dm.get("blue",[]).is_empty() and not 0 in dm.blue:dv=int(dm.secondary)
	var attack=int(m.attack)-int(a.fatigue);dv+=int(b.fatigue)
	var d=die();var total=attack+dv+d;var extra=""
	if d==6:
		var e=die();total+=e;extra=" (6! +%d)" % e
	var res=BloodRules.combat_table(total);var wounds=int(res.wounds)
	var text="%s %s → %s (%s): %d + %d + dado %d%s = %d" % [a.def.name,m.name,b.def.name,dm.name,attack,dv,d,extra,total]
	if wounds>0 and not b.def.armor.is_empty():
		var ad=die()
		if ad>=int(b.def.armor[0]) and ad<=int(b.def.armor[1]):wounds=maxi(0,wounds-ad);text+=" · armatura assorbe %d" % ad
	a.fatigue+=int(m.fatigue)
	var knocked=false;var push=-1
	if res.unbalance:knocked=true
	if m.get("imbalance")!=null and wounds>0:
		var value=die()+int(a.def.size)+int(m.imbalance)
		push=BloodRules.balance_table(value,int(b.def.size))
		if push>=0:knocked=true
	b.hp=maxi(0,b.hp-wounds)
	_log(text+" · [b]%d ferite[/b]%s" % [wounds,"" if not knocked else (" · "+b.def.name+(" A TERRA" if b.state!="ok" else " SBILANCIATO"))])
	_float(b,"-%d" % wounds if wounds>0 else "parato!",Color("ff7b6b") if wounds>0 else Color("bfe8ff"))
	if b.hp<=0:b.state="down";b.ap.play("A terra",.1);return
	if knocked:
		b.state="down" if b.state!="ok" else "unbalanced"
		b.ap.play("A terra" if b.state=="down" else "Sbilanciato",.1)
		if push>0:
			var dir=signf(b.root.position.x-a.root.position.x)
			var target=clampf(b.root.position.x+dir*.45*push,-3.2,3.2)
			create_tween().tween_property(b.root,"position:x",target,.5)
	elif wounds>0:
		b.ap.play("Sbilanciato",.1)
		await get_tree().create_timer(.6).timeout
		if b.state=="ok":b.ap.play("In guardia",.3)

func _float(f,text:String,color:Color):
	var l=Label3D.new();l.text=text;l.font_size=96;l.modulate=color;l.billboard=BaseMaterial3D.BILLBOARD_ENABLED;l.outline_size=18
	add_child(l);l.position=f.root.position+Vector3(0,2.25,0)
	var t=create_tween();t.tween_property(l,"position:y",l.position.y+.6,1.2);t.parallel().tween_property(l,"modulate:a",0.0,1.2);t.tween_callback(l.queue_free)

func _process(delta):
	camera.position=Vector3(sin(angle)*distance,1.25+sin(pitch)*distance,cos(angle)*distance)
	camera.look_at(Vector3(0,1.0,0))

func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT:dragging=event.pressed
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_UP:distance=maxf(3.0,distance-.25)
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_DOWN:distance=minf(9,distance+.25)
	if event is InputEventMouseMotion and dragging:
		angle-=event.relative.x*.008;pitch=clampf(pitch+event.relative.y*.004,-.05,.75)
