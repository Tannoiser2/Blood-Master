extends SceneTree
func _init():call_deferred("run")
func run():
	var scene=load("res://scenes/gascor_preview.tscn").instantiate();root.add_child(scene)
	await process_frame
	await process_frame
	scene.spin=false;scene.angle=0.22
	var ap=scene.animation_player
	assert(ap!=null,"Missing AnimationPlayer")
	print("ANIMATIONS ",ap.get_animation_list())
	for name in ["Riposo","Camminata","Affondo","Parata Sx"]:
		assert(ap.has_animation(name),"Missing animation "+name)
		ap.play(name);ap.seek(0.75,true);ap.pause()
		await create_timer(.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://assets/models/gascor/test-"+name+".png")
	print("GASCOR ANIMATION TEST PASSED")
	quit()
