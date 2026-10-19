extends SceneTree
func _init():call_deferred("run")
func run():
	var scene=load("res://scenes/gascor_preview.tscn").instantiate();root.add_child(scene)
	await process_frame
	await process_frame
	assert(scene.pivot.get_child_count()==1,"Missing model")
	assert(scene.camera!=null,"Missing camera")
	print("GASCOR PREVIEW READY")
	if not DisplayServer.get_name()=="headless":
		scene.spin=false;scene.angle=0.35
		await create_timer(1).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://assets/models/gascor/gascor-godot-preview.png")
	quit()
