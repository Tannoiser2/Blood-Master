extends SceneTree
# Partita vera nell'app, tutta IA: il diario completo, riga per riga
func _init():call_deferred("run")
func run():
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	main.roster=[]
	var a=OS.get_environment("A").split(",") if OS.get_environment("A")!="" else ["gascor","ut","kylvia","gandy"]
	var b=OS.get_environment("B").split(",") if OS.get_environment("B")!="" else ["anteos","nuchra","zak","sanguinaria"]
	for id in a:main.roster.append({"character":id,"team":0,"controller":"ai","seat":main.roster.size()})
	for id in b:main.roster.append({"character":id,"team":1,"controller":"ai","seat":main.roster.size()})
	main.minis_3d=false;main.speed=.02;main.step_pause=false
	main._start_local()
	var seen=0;var t=0.0;var out=[]
	while t<300.0 and main.game.state.phase!="finished" and int(main.game.state.turn)<=int(OS.get_environment("TURNS") if OS.get_environment("TURNS")!="" else "8"):
		await create_timer(.2).timeout;t+=.2
		var n=int(main.game.state.get("log_n",0));var lg=main.game.state.log
		if n>seen:
			for line in lg.slice(maxi(0,lg.size()-(n-seen))):out.append(line)
			seen=n
	for line in out:print(line)
	print("FINE turno ",main.game.state.turn," fase ",main.game.state.phase)
	quit()
