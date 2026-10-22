extends SceneTree
# Schermate del tema: iniziale, preparazione, partita
func _init() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(1440,900)
	var scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene)
	await create_timer(1).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/f_splash.png")
	scene.roster=[{"character":"gascor","team":0,"controller":"human","seat":0},{"character":"gandy","team":0,"controller":"ai","seat":1},{"character":"anteos","team":1,"controller":"ai","seat":2},{"character":"ziggy","team":1,"controller":"ai","seat":3}]
	scene.set_meta("roster_default",true);scene._show_menu()
	await create_timer(.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/f_menu.png")
	scene.minis_3d=false;scene._start_local()
	await create_timer(4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/f_game.png")
	quit()
