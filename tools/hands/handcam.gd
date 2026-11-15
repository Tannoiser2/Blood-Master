extends SceneTree
# Primi piani delle due mani di ogni modello, da due lati: per controllare i pugni fatti da tools/hands/fist.py
# xvfb-run godot --rendering-driver opengl3 --path . -s tools/hands/handcam.gd   ONLY=gascor,ut  OUT=res://tmp/handcam
func _init():call_deferred("run")
func run():
	root.size=Vector2i(int(OS.get_environment("PX")) if OS.get_environment("PX")!="" else 360,(int(OS.get_environment("PX")) if OS.get_environment("PX")!="" else 360)*2/3)
	var out=OS.get_environment("OUT") if OS.get_environment("OUT")!="" else "res://tmp/handcam";DirAccess.make_dir_recursive_absolute(out)
	var world=Node3D.new();root.add_child(world)
	var env=WorldEnvironment.new();var e=Environment.new();e.background_mode=Environment.BG_COLOR;e.background_color=Color(.2,.22,.25);e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color(.6,.6,.62);e.ambient_light_energy=.6;env.environment=e;world.add_child(env)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.light_energy=1.3;world.add_child(sun)
	var cam=Camera3D.new();cam.fov=28;cam.near=.02;world.add_child(cam);cam.current=true
	var b3=load("res://scripts/board3d.gd").new()
	for cid in OS.get_environment("ONLY").split(",",false):
		var m: Node3D=load(b3.MODELS[cid]).instantiate();world.add_child(m)
		var ap: AnimationPlayer=m.find_children("*","AnimationPlayer",true,false)[0]
		var sk: Skeleton3D=m.find_children("*","Skeleton3D",true,false)[0]
		ap.play(OS.get_environment("CLIP") if OS.get_environment("CLIP")!="" else "In guardia");ap.seek(float(OS.get_environment("AT")),true);ap.pause()
		await process_frame;await process_frame
		for side in ["Right","Left"]:
			var hand: Vector3=(sk.global_transform*sk.get_bone_global_pose(sk.find_bone(side+"Hand"))).origin
			var fore: Vector3=(sk.global_transform*sk.get_bone_global_pose(sk.find_bone(side+"ForeArm"))).origin
			var at=hand+(hand-fore).normalized()*.08
			var k=0
			for off in [Vector3(.35,.25,.75),Vector3(-.75,.2,-.3),Vector3(.1,-.5,.7)]:
				cam.position=at+off.normalized()*float(OS.get_environment("D") if OS.get_environment("D")!="" else ".85");cam.look_at(at)
				await process_frame;await process_frame
				root.get_texture().get_image().save_png("%s/%s__%s_%d.png"%[out,cid,side,k]);k+=1
		m.queue_free();await process_frame
	quit()
