extends SceneTree
# Come appare la freccia a terra da chi colpisce a chi è colpito
func _init():call_deferred("run")
func run():
	root.size=Vector2i(1440,900)
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	main.roster=[{"character":"gascor","team":0,"controller":"human","seat":0},{"character":"anteos","team":1,"controller":"human","seat":1}]
	main.minis_3d=true;main.house["scenery"]=false;main._start_local()
	main.game.deploy("3,8",0);main.game.deploy("3,-2",3)
	main.game.state.fighters[0].cell="4,2";main.game.state.fighters[1].cell="4,0"
	main._refresh();await create_timer(2.0).timeout
	var b=main.board3d
	b._attack_marker(b.minis[0].root.global_position,b.minis[1].root.global_position,Color(1,.25,.2),0.0,3.0)
	await create_timer(.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/marker.png")
	quit()
