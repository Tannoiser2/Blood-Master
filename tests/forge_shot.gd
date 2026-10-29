extends SceneTree
# Schermata della forgia: W e H dall'ambiente; ARMA, EDIT=1 per qualche ritocco, MENU=1 per il menu con un eroe salvato
func _init() -> void:call_deferred("run")
func run() -> void:
	var w=int(OS.get_environment("W")) if OS.get_environment("W")!="" else 1440
	var h=int(OS.get_environment("H")) if OS.get_environment("H")!="" else 900
	root.size=Vector2i(w,h)
	var scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene)
	await create_timer(1).timeout
	scene._show_forge()
	var f=scene.page.get_child(0)
	if OS.get_environment("ARMA")!="":f._set_trait("arma",OS.get_environment("ARMA"),true)
	if OS.get_environment("EDIT")=="1":
		f._edit("cleave","fatigue",1);f._edit("cleave","attack",2);f._edit("thrust","defense",-1);f.brush="green";f._side("thrust",3)
		f._set_trait("INT",3);f._toggle_spell("fireball",true);f._toggle_spell("shield",true);f._toggle_token("kick")
	if OS.get_environment("SAVE")=="1":
		f.traits.name="Brunilde";f.traits.title="La forgiata";f._fit_budget();f._save()
	if OS.get_environment("TEST")=="1":
		f._run_test()
		while f.testing:await create_timer(.5).timeout
		print("COLLAUDO ",f.test_label.text)
	if OS.get_environment("MENU")=="1":
		scene.set_meta("roster_default",true);scene.mode="solo";scene._show_menu()
	await create_timer(.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/forge_%s.png"%OS.get_environment("TAG"))
	quit()
