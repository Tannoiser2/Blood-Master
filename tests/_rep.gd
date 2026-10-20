extends SceneTree
func _init():call_deferred("run")
func run():
	root.size=Vector2i(1440,960)
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	var spec=OS.get_environment("R").split(",")
	main.roster=[]
	for s in spec:var kv=s.split(":");main.roster.append({"character":kv[0],"team":int(kv[1]),"controller":"ai","seat":main.roster.size()})
	main.minis_3d=OS.get_environment("M")=="1";main.speed=.05;main.scenario=OS.get_environment("SC") if OS.get_environment("SC")!="" else "frontale"
	main._start_local()
	var b=main.board3d;var t=0
	while main.game.state.phase!="finished" and t<4000:await create_timer(.1).timeout;t+=1
	print("FINE turno ",main.game.state.turn," passi ",b.history.size())
	# pulsante vero del pannello finale
	var btn=null
	for c in main.sidebar.get_children():
		for d in ([c]+c.get_children()):
			if d is Button and d.text.begins_with("Replay"):btn=d
	var t0=Time.get_ticks_msec();btn.pressed.emit()
	await create_timer(.3).timeout
	while b.replaying:await create_timer(.1).timeout
	print("REPLAY %.1f s"%((Time.get_ticks_msec()-t0)/1000.0))
	quit()
