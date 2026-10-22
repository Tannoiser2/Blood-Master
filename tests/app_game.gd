extends SceneTree
# Partita vera dentro l'app (come la giochi tu), tutta IA: quali mosse vengono rivelate turno per turno
func _init():call_deferred("run")
func run():
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	main.roster=[]
	for id in ["gascor","zenyo","ut","kylvia","thorn","gandy"]:main.roster.append({"character":id,"team":0,"controller":"ai","seat":main.roster.size()})
	for id in ["anteos","shaara","zak","nuchra","ramok","sanguinaria"]:main.roster.append({"character":id,"team":1,"controller":"ai","seat":main.roster.size()})
	main.minis_3d=false;main.speed=.02;main.step_pause=false
	for k in OS.get_environment("OFF").split(",",false):main.house[k]=false
	main._start_local()
	var seen=0;var t=0.0;var reveals={};var allnotes=[]
	while t<240.0 and main.game.state.phase!="finished" and int(main.game.state.turn)<16:
		await create_timer(.25).timeout;t+=.25
	for n in main.game.state.log:allnotes.append(n)
	for n in allnotes:
		if " rivela: " in n:var mv=n.split(" rivela: ")[1].trim_suffix(".");reveals[mv]=reveals.get(mv,0)+1
	print("TURNO ",main.game.state.turn," fase ",main.game.state.phase," tempo ",t)
	print("RIVELATE ",reveals)
	for n in allnotes.slice(-40):print("  ",n)
	quit()
