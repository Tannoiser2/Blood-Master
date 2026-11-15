extends SceneTree
# Menu iniziale: una schermata per sezione. W e H dall'ambiente; SEC=scontro,regole,opzioni (tutte se manca)
func _init() -> void:call_deferred("run")
func run() -> void:
	var w=int(OS.get_environment("W")) if OS.get_environment("W")!="" else 1440
	var h=int(OS.get_environment("H")) if OS.get_environment("H")!="" else 900
	root.size=Vector2i(w,h)
	var scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene)
	await create_timer(1).timeout
	scene.roster=[{"character":"gascor","team":0,"controller":"human","seat":0},{"character":"gandy","team":0,"controller":"ai","seat":1},{"character":"anteos","team":1,"controller":"ai","seat":2},{"character":"ziggy","team":1,"controller":"ai","seat":3}]
	scene.set_meta("roster_default",true)
	DirAccess.make_dir_recursive_absolute("res://tmp")
	for sec in (OS.get_environment("SEC").split(",",false) if OS.get_environment("SEC")!="" else ["scontro","regole","opzioni"]):
		scene.menu_section=sec;scene._show_menu()
		await create_timer(.6).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/menu_%s_%d.png"%[sec,w])
	quit()
