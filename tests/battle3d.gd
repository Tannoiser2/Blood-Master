extends SceneTree
# Scontro completo fra IA in 3D (scenario libero: si attacca subito) e poi il replay: nessun errore, tempi dei colpi
# e delle parate (BM_TIMING=1 li stampa). IDS=gascor,ut,anteos,shannon  FORGE=due_armi aggiunge un eroe a due armi
func _init():call_deferred("run")
func run():
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	var ids=(OS.get_environment("IDS") if OS.get_environment("IDS")!="" else "gascor,ut,anteos,shannon").split(",")
	if OS.get_environment("FORGE")!="":
		var t=BloodForge.default_traits();t.arma=OS.get_environment("FORGE");t.id="forged_prova";t.name="Prova";t.on=BloodForge.EXTRA_IDS.duplicate()
		var d=BloodForge.build(t);BloodRules.extra_defs[d.id]=d;main.game.add_definition(d);ids.append(d.id)
	main.roster=[]
	for k in ids.size():main.roster.append({"character":ids[k],"team":k%2,"controller":"ai","seat":k})
	main.minis_3d=true;main.scenario="libero";main.step_pause=false
	for k in main.house:main.house[k]=k in ["zoc","reach","push"]
	Engine.time_scale=float(OS.get_environment("SPEED")) if OS.get_environment("SPEED")!="" else 6.0
	main._start_local()
	var t0=Time.get_ticks_msec();var max_turn=int(OS.get_environment("TURNS")) if OS.get_environment("TURNS")!="" else 10
	while main.game.state.phase!="finished" and int(main.game.state.turn)<=max_turn and Time.get_ticks_msec()-t0<240000:
		await create_timer(1.0).timeout
	print("FINE turno ",main.game.state.turn," fase ",main.game.state.phase," passi ",main.board3d.history.size())
	while main.board3d.busy():await create_timer(.5).timeout
	if OS.get_environment("REPLAY")!="":
		print("REPLAY");Engine.time_scale=8.0
		main.board3d.replay()
		await create_timer(1.0).timeout
		Engine.time_scale=8.0   # il replay rallenta da sé: qui lo si accelera per la prova
		var t1=Time.get_ticks_msec()
		while main.board3d.replaying and Time.get_ticks_msec()-t1<200000:await create_timer(1.0).timeout
		print("REPLAY FINITO ",not main.board3d.replaying)
	quit()
