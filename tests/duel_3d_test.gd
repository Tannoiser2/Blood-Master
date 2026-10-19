extends SceneTree
# Gioca alcuni round del duello 3D con scelte casuali e verifica che regole e animazioni girino.
func _init():call_deferred("run")
func run():
	var scene=load("res://scenes/duel_3d.tscn").instantiate();root.add_child(scene)
	await process_frame
	for f in scene.F:
		for clip in scene.CLIP.values():assert(f.ap.has_animation(clip),"Manca la clip "+clip)
	var start=[scene.F[0].hp,scene.F[1].hp]
	for r in 6:
		if scene.F[0].hp<=0 or scene.F[1].hp<=0:break
		scene.F[0].choice=scene._ai_choice(scene.F[0],scene.F[1])
		scene._round()
		while scene.busy:await create_timer(.1).timeout
	print("FERITE ",start," -> ",[scene.F[0].hp,scene.F[1].hp])
	print(scene.log_box.get_parsed_text())
	assert(scene.F[0].hp<start[0] or scene.F[1].hp<start[1],"Nessun colpo andato a segno in 6 round")
	print("DUEL 3D TEST PASSED")
	quit()
