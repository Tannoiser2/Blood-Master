extends SceneTree
# Registra ogni animazione di ogni personaggio in fotogrammi PNG (poi tools/gif/make_gifs.py fa le GIF).
# xvfb-run godot --rendering-method gl_compatibility --path . -s tools/gif/record.gd   (OUT=cartella, ONLY=gascor,ut)
const FPS=12.0
const BOW_CLIPS=["Incoccare","Tirare","In guardia arco","Avanzare arco","Correre arco","Sbilanciato arco"]
const REST_GRIP=["Riposo","In guardia","Camminata","Correre","Avanzare","Carica","Schivata","Sbilanciato","A terra","Rialzarsi","Morte"]
func _init():call_deferred("run")
func _find(n: Node,cls: String) -> Node:
	if n.is_class(cls):return n
	for c in n.get_children():
		var f=_find(c,cls)
		if f:return f
	return null
func run():
	root.size=Vector2i(360,360)
	var out=OS.get_environment("OUT");var only=OS.get_environment("ONLY").split(",",false)
	var world=Node3D.new();root.add_child(world)
	var env=WorldEnvironment.new();var e=Environment.new();e.background_mode=Environment.BG_COLOR;e.background_color=Color(.16,.18,.2);e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color(.6,.6,.65);e.ambient_light_energy=.6;env.environment=e;world.add_child(env)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-35,0);sun.light_energy=1.3;sun.shadow_enabled=true;world.add_child(sun)
	var ground=MeshInstance3D.new();var pm=PlaneMesh.new();pm.size=Vector2(12,12);ground.mesh=pm;var gm=StandardMaterial3D.new();gm.albedo_color=Color(.5,.42,.33);ground.material_override=gm;world.add_child(ground)
	var cam=Camera3D.new();cam.fov=32;world.add_child(cam);cam.current=true
	var board=load("res://scripts/board3d.gd")
	var models: Dictionary=board.MODELS
	for cid in models:
		if not only.is_empty() and not cid in only:continue
		if not ResourceLoader.exists(models[cid]):continue
		var m: Node3D=load(models[cid]).instantiate();world.add_child(m)
		var ap: AnimationPlayer=_find(m,"AnimationPlayer");var sk: Skeleton3D=_find(m,"Skeleton3D")
		if cid=="ziggy":await _ziggy(m,cam,out);m.queue_free();await process_frame;print("FATTO ",cid);continue
		if ap==null:m.queue_free();continue
		var hips=sk.find_bone("Hips") if sk else -1
		var tall=2.4 if cid=="golem" else 1.9
		DirAccess.make_dir_recursive_absolute(out+"/"+cid)
		for clip in ap.get_animation_list():
			if clip=="RESET":continue
			var a: Animation=ap.get_animation(clip);var length=minf(a.length,5.0)
			# armi giuste per la clip: arco o spada per gli arcieri, bastone dritto o in azione per i maghi
			var bow=clip in BOW_CLIPS
			for nm in ["Arco","FrecciaIncoccata"]:
				var g=m.find_child(nm,true,false)
				if g:g.visible=bow
			for nm in ["Spada","ArcoSchiena"]:
				var g=m.find_child(nm,true,false)
				if g:g.visible=not bow
			var r1=m.find_child("Arma",true,false);var r2=m.find_child("ArmaAzione",true,false)
			if r1 and r2:r1.visible=clip in REST_GRIP;r2.visible=not r1.visible
			ap.play(clip);ap.pause()
			var frames=int(ceil(length*FPS))+1
			for f in frames:
				ap.seek(minf(float(f)/FPS,length),true)
				var c=Vector3.ZERO
				if hips>=0:c=sk.global_transform*sk.get_bone_global_pose(hips).origin;c.y=0
				cam.position=c+Vector3(-2.6,1.6,4.2)*(tall/1.9);cam.look_at(c+Vector3(0,tall*.45,0))
				await process_frame;await process_frame
				root.get_texture().get_image().save_png("%s/%s/%s__%03d.png"%[out,cid,clip,f])
		m.queue_free();await process_frame
		print("FATTO ",cid)
	quit()

# Ziggynowskij non ha scheletro: le sue "animazioni" sono quelle procedurali di board3d (_spirit_move e fluttuazione)
func _ziggy(m: Node3D,cam: Camera3D,out: String) -> void:
	DirAccess.make_dir_recursive_absolute(out+"/ziggy")
	var piv=Node3D.new();m.get_parent().add_child(piv);m.reparent(piv,false)
	cam.position=Vector3(-2.6,1.6,4.2);cam.look_at(Vector3(0,.9,0))
	var clips={"Fluttuare":3.8,"Incantesimo":1.4,"Colpito":1.2,"Volo":1.4,"Morte":1.6}
	for clip in clips:
		var frames=int(ceil(clips[clip]*FPS))+1
		for f in frames:
			var t=float(f)/FPS
			var bob=.14+.10*(.5-.5*cos(t*PI/1.3));var sway=.22*sin(t*TAU/3.8)
			m.position.y=bob;m.rotation.y=sway;piv.scale=Vector3.ONE;piv.rotation=Vector3.ZERO;piv.visible=true
			match clip:
				"Incantesimo":   # vortice veloce e gonfiarsi
					var k=clampf(t/.25,0,1);var back=clampf((t-.7)/.3,0,1)
					piv.scale=Vector3.ONE.lerp(Vector3(1.18,1.1,1.18),sin(k*PI/2)*(1.0-back))
					piv.rotation.y=TAU*(1.0-pow(1.0-clampf(t/.7,0,1),3))
				"Colpito":       # si contrae e trema
					var sc=Vector3(.85,.92,.85) if t<.5 else Vector3(.85,.92,.85).lerp(Vector3.ONE,clampf((t-.5)/.2,0,1))
					piv.scale=Vector3.ONE.lerp(Vector3(.85,.92,.85),clampf(t/.12,0,1)) if t<.12 else sc
					if t>=.12 and t<.36:piv.rotation.z=.12 if int((t-.12)/.06)%2==0 else -.12
				"Volo":          # si allunga nella direzione del volo
					var a=clampf(t/.3,0,1);var b=clampf((t-.7)/.3,0,1)
					piv.scale=Vector3.ONE.lerp(Vector3(.92,1.12,.92),a*(1.0-b));piv.position.x=-1.2+2.4*clampf(t/1.0,0,1)
				"Morte":         # si dissolve girando su se stesso
					var d=clampf(t/1.2,0,1);piv.rotation.y=TAU*2*d
					piv.scale=Vector3.ONE.lerp(Vector3(.01,1.6,.01),pow(2,10*(d-1)) if d>0 else 0.0);piv.visible=t<1.2
			if clip!="Volo":piv.position.x=0
			await process_frame;await process_frame
			root.get_texture().get_image().save_png("%s/ziggy/%s__%03d.png"%[out,clip,f])
