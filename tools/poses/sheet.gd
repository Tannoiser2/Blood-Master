extends SceneTree
# Foglio delle pose: per ogni personaggio la posa di guardia (quella che resta in campo), di fronte e di tre quarti.
# xvfb-run godot --rendering-method gl_compatibility --path . -s tools/poses/sheet.gd   (OUT=cartella, CLIPS="In guardia,In guardia arco", AT=0.3)
func _init():call_deferred("run")
func _find(n: Node,cls: String) -> Node:
	if n.is_class(cls):return n
	for c in n.get_children():
		var f=_find(c,cls)
		if f:return f
	return null
func run():
	root.size=Vector2i(560,640)
	var only=OS.get_environment("ONLY").split(",",false);var zoom=float(OS.get_environment("ZOOM")) if OS.get_environment("ZOOM")!="" else 1.0
	var out=OS.get_environment("OUT");DirAccess.make_dir_recursive_absolute(out)
	var clips=(OS.get_environment("CLIPS") if OS.get_environment("CLIPS")!="" else "In guardia,In guardia arco").split(",")
	var at=float(OS.get_environment("AT")) if OS.get_environment("AT")!="" else .3
	var world=Node3D.new();root.add_child(world)
	var env=WorldEnvironment.new();var e=Environment.new();e.background_mode=Environment.BG_COLOR;e.background_color=Color(.16,.18,.2);e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color(.6,.6,.65);e.ambient_light_energy=.7;env.environment=e;world.add_child(env)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-35,0);sun.light_energy=1.3;world.add_child(sun)
	var cam=Camera3D.new();cam.fov=30;world.add_child(cam);cam.current=true
	var models: Dictionary=load("res://scripts/board3d.gd").MODELS
	for cid in models:
		if cid=="ziggy" or not ResourceLoader.exists(models[cid]):continue
		if not only.is_empty() and not cid in only:continue
		var path: String=models[cid]
		if OS.get_environment("OLD")!="":path=OS.get_environment("OLD")+"/"+cid+"_old.glb"   # confronto con il modello di prima
		var m: Node3D
		if path.begins_with("res://"):m=load(path).instantiate()
		else:
			var gs=GLTFState.new();var gd=GLTFDocument.new()
			if gd.append_from_file(path,gs)!=OK:continue
			m=gd.generate_scene(gs)
		world.add_child(m)
		var ap: AnimationPlayer=_find(m,"AnimationPlayer")
		if ap==null:m.queue_free();continue
		var tall=2.4 if cid=="golem" else 1.9
		for clip in clips:
			if not ap.has_animation(clip):continue
			var bow=clip.ends_with("arco")
			for nm in ["Arco","FrecciaIncoccata"]:
				var g=m.find_child(nm,true,false)
				if g:g.visible=bow and nm=="Arco"
			for nm in ["Spada","ArcoSchiena"]:
				var g=m.find_child(nm,true,false)
				if g:g.visible=not bow
			var r1=m.find_child("Arma",true,false);var r2=m.find_child("ArmaAzione",true,false)
			if r1 and r2:r1.visible=true;r2.visible=false
			ap.play(clip);ap.pause();ap.seek(ap.get_animation(clip).length*at,true)
			var views=[["fronte",Vector3(0,1.3,4.6)],["tre_quarti",Vector3(-3.0,1.4,3.6)],["lato",Vector3(4.6,1.2,.2)]]
			if OS.get_environment("VIEWS")=="all":views+=[["dietro",Vector3(0,1.3,-4.6)],["alto",Vector3(0.01,6.0,0.4)],["lato_sx",Vector3(-4.6,1.2,.2)]]
			for v in views:
				cam.position=Vector3(0,tall*.55,0)+(v[1]-Vector3(0,1.3,0))*(tall/1.9)/zoom;cam.look_at(Vector3(0,tall*.55,0))
				await process_frame;await process_frame
				root.get_texture().get_image().save_png("%s/%s__%s__%s.png"%[out,cid,clip.replace(" ","_"),v[0]])
		m.queue_free();await process_frame
	print("FATTO")
	quit()
