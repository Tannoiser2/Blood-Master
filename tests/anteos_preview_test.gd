extends SceneTree
func _init():call_deferred("run")
func run():
	var scene=load("res://scenes/anteos_preview.tscn").instantiate();root.add_child(scene)
	await process_frame
	await process_frame
	var ap=scene.animation_player
	assert(ap!=null,"Missing AnimationPlayer")
	print("ANIMATIONS ",ap.get_animation_list())
	for name in ["Riposo","Camminata","Affondo","Parata"]:
		assert(ap.has_animation(name),"Missing animation "+name)
	print("ANTEOS PREVIEW TEST PASSED")
	quit()
