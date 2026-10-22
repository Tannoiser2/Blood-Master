extends SceneTree
# Sequenza dei passi animati in una partita 3D: reazioni dopo l'impatto, colpi in fila
func _init():call_deferred("run")
func run():
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	main.roster=[]
	for id in ["kylvia","gascor","gandy"]:main.roster.append({"character":id,"team":0,"controller":"ai","seat":main.roster.size()})
	for id in ["zak","anteos","sanguinaria"]:main.roster.append({"character":id,"team":1,"controller":"ai","seat":main.roster.size()})
	main.minis_3d=true;main.speed=.05;main.step_pause=false
	main._start_local()
	var t=0.0
	while t<500.0 and main.game.state.phase!="finished" and int(main.game.state.turn)<9:
		await create_timer(.5).timeout;t+=.5
	print("FINE turno ",main.game.state.turn)
	quit()
