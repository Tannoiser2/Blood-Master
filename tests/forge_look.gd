extends SceneTree
# Miniature degli eroi della forgia in fila (posa di guardia): corpo, arma, scudo, seconda arma, statura
func _init():call_deferred("run")
func _find(n: Node,cls: String) -> Node:
	if n.is_class(cls):return n
	for c in n.get_children():
		var f=_find(c,cls)
		if f:return f
	return null
func run():
	var sets=[["Spada e scudo",{"arma":"spada","scudo":"grande","armatura":"pesante","stazza":3}],["Due spade",{"arma":"due_armi","armatura":"media","stazza":3}],
		["Pugnale",{"arma":"pugnale","armatura":"leggera","stazza":2,"aspetto":"donna"}],["Ascia enorme",{"arma":"ascia","armatura":"nessuna","stazza":5}],
		["Lancia e scudo",{"arma":"lancia","scudo":"piccolo","armatura":"media","stazza":3}],["Bastone (donna)",{"arma":"bastone","armatura":"nessuna","stazza":2,"aspetto":"donna"}],
		["Ascia pesante",{"arma":"ascia","armatura":"pesante","stazza":4}],["Spada minuta",{"arma":"spada","armatura":"leggera","stazza":1,"aspetto":"donna","scudo":"piccolo"}]]
	if OS.get_environment("SIZES")!="":   # la stessa lancia con le cinque stazze
		sets=[]
		for k in 5:sets.append([BloodForge.STAZZE[k],{"arma":"lancia","armatura":"leggera","stazza":k+1}])
	if OS.get_environment("SET")!="":sets=sets.slice(int(OS.get_environment("SET")),int(OS.get_environment("SET"))+1)
	root.size=Vector2i(maxi(520,260*sets.size()),640)
	var world=Node3D.new();root.add_child(world)
	var env=WorldEnvironment.new();var e=Environment.new();e.background_mode=Environment.BG_COLOR;e.background_color=Color(.16,.18,.2);e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color(.6,.6,.65);e.ambient_light_energy=.7;env.environment=e;world.add_child(env)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-30,0);sun.light_energy=1.3;world.add_child(sun)
	var b3=load("res://scripts/board3d.gd").new()
	var yaw=float(OS.get_environment("YAW")) if OS.get_environment("YAW")!="" else 25.0
	for k in sets.size():
		var t=BloodForge.default_traits()
		for key in sets[k][1]:t[key]=sets[k][1][key]
		var d=BloodForge.build(t)
		var m: Node3D=load(b3.MODELS[d.look]).instantiate();world.add_child(m)
		b3._dress(m,d.dress)
		m.position=Vector3((k-(sets.size()-1)/2.0)*1.0,0,0);m.rotation_degrees.y=yaw
		var ap: AnimationPlayer=_find(m,"AnimationPlayer")
		if ap and ap.has_animation(OS.get_environment("CLIP") if OS.get_environment("CLIP")!="" else "In guardia"):
			ap.play(OS.get_environment("CLIP") if OS.get_environment("CLIP")!="" else "In guardia");ap.seek(.3,true);ap.pause()
		var l=Label3D.new();l.text=sets[k][0]+"\n"+d.look;l.font_size=40;l.pixel_size=.004;l.position=m.position+Vector3(0,-.12,.3);world.add_child(l)
	var cam=Camera3D.new();cam.fov=30;world.add_child(cam);cam.current=true
	cam.position=Vector3(0,.8,4.4 if sets.size()>4 else 2.6);cam.look_at(Vector3(0,.45,0))
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/forge_look%s.png"%OS.get_environment("TAG"))
	quit()
