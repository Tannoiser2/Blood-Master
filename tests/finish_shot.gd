extends SceneTree
# Fine scontro: risultato e tasti nella barra in alto, mappa libera
func _init():call_deferred("run")
func run():
	root.size=Vector2i(1440,900)
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	main.roster=[{"character":"gascor","team":0,"controller":"human","seat":0},{"character":"anteos","team":1,"controller":"human","seat":1}]
	main.minis_3d=true;main._start_local()
	main.game.deploy("3,8",0);main.game.deploy("3,-2",3)
	main.game.state.fighters[1].alive=false;main.game.state.phase="finished";main.game.state.winner=0
	main._refresh();await create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/finish.png")
	print("pannello visibile: ",main.action_panel.visible," replay: ",main.replay_btn.visible)
	quit()
