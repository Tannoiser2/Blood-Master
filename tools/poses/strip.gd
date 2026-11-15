extends SceneTree
# Striscia di fotogrammi di una clip: N istanti, visti da dietro-alto (come in partita) e di fronte.
# xvfb-run godot --rendering-driver opengl3 --path . -s tools/poses/strip.gd
#   ONLY=gascor  CLIPS="Taglio Dx,Parata Sx"  N=6  OUT=tmp/strip  DRESS="spada,spada" (arma,altra mano: corpi della forgia)
#   KIND=shield costruisce i gesti di scripts/gestures.gd: le clip si chiamano "g/Colpo destro", ...
func _init():call_deferred("run")
func _find(n: Node,cls: String) -> Node:
	if n.is_class(cls):return n
	for c in n.get_children():
		var f=_find(c,cls)
		if f:return f
	return null
func run():
	var n=int(OS.get_environment("N")) if OS.get_environment("N")!="" else 6
	var cw=int(OS.get_environment("CW")) if OS.get_environment("CW")!="" else 300;var chh=cw*34/30
	var zoom=float(OS.get_environment("ZOOM")) if OS.get_environment("ZOOM")!="" else 1.0
	root.size=Vector2i(cw,chh)
	var out=OS.get_environment("OUT") if OS.get_environment("OUT")!="" else "res://tmp/strip";DirAccess.make_dir_recursive_absolute(out)
	var clips=OS.get_environment("CLIPS").split(",",false)
	var world=Node3D.new();root.add_child(world)
	var env=WorldEnvironment.new();var e=Environment.new();e.background_mode=Environment.BG_COLOR;e.background_color=Color(.2,.22,.25);e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color(.7,.7,.72);e.ambient_light_energy=.8;env.environment=e;world.add_child(env)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-35,0);sun.light_energy=1.2;world.add_child(sun)
	var cam=Camera3D.new();cam.fov=30;world.add_child(cam);cam.current=true
	# pavimento con la freccia del fronte (+Z) e i lati: rosso = destra del personaggio, blu = sinistra
	var mk=func(size: Vector3,pos: Vector3,col: Color):
		var mi=MeshInstance3D.new();var bm=BoxMesh.new();bm.size=size;mi.mesh=bm;mi.position=pos
		var mt=StandardMaterial3D.new();mt.albedo_color=col;mt.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mi.material_override=mt;world.add_child(mi)
	mk.call(Vector3(.05,.01,1.2),Vector3(0,0,.6),Color.WHITE)
	mk.call(Vector3(.9,.01,.05),Vector3(-.45,0,0),Color(1,.3,.3))   # destra del personaggio (x negativo guardando +Z)
	mk.call(Vector3(.9,.01,.05),Vector3(.45,0,0),Color(.3,.5,1))
	var b3=load("res://scripts/board3d.gd").new()
	var models: Dictionary=b3.MODELS
	for cid in OS.get_environment("ONLY").split(",",false):
		var m: Node3D=load(models[cid]).instantiate();world.add_child(m)
		var dr=OS.get_environment("DRESS").split(",")
		if dr.size()>=1 and dr[0]!="":b3._dress(m,{"body":cid,"weapon":dr[0],"off":dr[1] if dr.size()>1 else "","scale":1.0});m.scale=Vector3.ONE
		var ap: AnimationPlayer=_find(m,"AnimationPlayer")
		if OS.get_environment("KIND")!="":   # clip costruite (scripts/gestures.gd): KIND=one|shield|dual|two|none, SFX=" 2h"
			var gs=load("res://scripts/gestures.gd").new();var sfx=OS.get_environment("SFX")
			if gs.setup(m,ap,OS.get_environment("KIND"),"In guardia"+sfx):gs.build(ap,90.0,sfx);print(cid," tipo ",gs.kind," asse ",gs.axisR," ",gs.axisL)
			else:print("niente gesti per ",cid)
		if OS.get_environment("LIST")!="":print(cid," CLIPS ",ap.get_animation_list())
		for clip in clips:
			if not ap.has_animation(clip):print("manca ",cid," ",clip);continue
			var L=ap.get_animation(clip).length
			var k=0
			for v in [["alto",Vector3(0,4.6,-3.4)],["fronte",Vector3(1.6,1.5,5.0)]]:
				for f in n:
					ap.play(clip);ap.seek(L*(f+.5)/n,true);ap.pause()
					cam.position=Vector3(0,.85,0)+(v[1]-Vector3(0,.85,0))/zoom;cam.look_at(Vector3(0,.85,0))
					await process_frame;await process_frame
					root.get_texture().get_image().save_png("%s/%s__%s__%s_%02d.png"%[out,cid,clip.replace(" ","_").replace("/","-"),v[0],f])
					k+=1
			print("OK ",cid," ",clip," %.2fs"%L)
		m.queue_free();await process_frame
	quit()
