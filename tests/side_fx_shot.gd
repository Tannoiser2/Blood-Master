extends SceneTree
# Gesti laterali: taglio e parata a destra e a sinistra, con l'arco di luce (Gascor: scudo al braccio sinistro)
func _init():call_deferred("run")
func run():
	root.size=Vector2i(1440,900)
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	main.roster=[{"character":"gascor","team":0,"controller":"human","seat":0},{"character":"anteos","team":1,"controller":"human","seat":1}]
	main.minis_3d=true;main.house["scenery"]=false;main.house["restore"]=false;main._start_local()
	main.game.deploy("3,8",0);main.game.deploy("3,-2",3)
	main.game.state.fighters[0].cell="4,3";main.game.state.fighters[0].facing=0;main.game.state.fighters[1].cell="1,0"
	main._refresh();await create_timer(2.0).timeout
	var b=main.board3d;b.follow=false;b.target=b.cell_pos("4,3");b.yaw=b.facing_yaw(0)+PI;b.pitch=.5;b.dist=4.0;b._place_camera()
	var n=0
	for clip in ["Taglio Dx","Taglio Sx","Parata Sx","Parata Dx"]:
		var ap=b.minis[0].ap;ap.play(clip)
		var at=ap.get_animation(clip).length*(.42 if clip.begins_with("Taglio") else .35)
		await create_timer(at).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/side_%d.png"%n);n+=1
		await create_timer(1.5).timeout
	quit()
