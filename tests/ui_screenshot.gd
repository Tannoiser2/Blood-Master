extends SceneTree
func _init() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(int(OS.get_environment("W")) if OS.get_environment("W")!="" else 1440,900)
	var scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene)
	await create_timer(1).timeout
	var ids=OS.get_environment("IDS").split(",")
	scene.roster=[]
	for k in ids.size():scene.roster.append({"character":ids[k],"team":k%2,"controller":"human" if k==0 else "ai","seat":0})
	scene.minis_3d=true;scene.speed=.05
	scene._start_local()
	var t=0.0
	while t<90.0 and scene.game.state.phase!="acting" or (scene.game.state.phase=="acting" and int(scene.game.state.active)!=0 and t<90.0):
		if scene.game.state.phase=="planning":
			for i in scene.game.needs_plan():
				if i==0:scene._submit({"type":"plan","fighter":0,"move":BloodAI.choose_move(scene.game,0)})
		if scene.game.state.phase=="deploy" and int(scene.game.state.active)==0:
			var c=scene.game.entry_cells(0)[0];scene._submit({"type":"deploy","target":c,"facing":0})
		await create_timer(.5).timeout;t+=.5
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/shot.png")
	print("FASE ",scene.game.state.phase," attivo ",scene.game.state.active," turno ",scene.game.state.turn)
	quit()
