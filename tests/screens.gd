extends SceneTree
func _init() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(1440,960)
	var scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene)
	await create_timer(1).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/menu.png")
	scene.roster=[{"character":"gascor","team":0,"controller":"human","seat":0},{"character":"anteos","team":1,"controller":"human","seat":1}]
	scene._start_local()
	scene.game.deploy("3,8",0);scene.game.deploy("3,-2",3)
	scene.game.state.fighters[0].cell="4,1";scene.game.state.fighters[1].cell="4,0"
	scene._reset_selection();scene._refresh()
	await create_timer(.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/game.png")
	quit()
