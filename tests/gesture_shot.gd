extends SceneTree
# Duello di prova in 3D per controllare a occhio colpi, parate e passi: A attacca (o si sposta), B risponde.
# xvfb-run godot --rendering-driver opengl3 --path . -s tests/gesture_shot.gd
#   A=gascor B=anteos MA=right MB=parry_r  (pedine)  SIDE=0 (lato di A su cui sta B)  STEP=2 (A si sposta su quel lato invece di colpire)
#   DICE=1,1,1 (dadi forzati)  N=14 DT=.14 (fotogrammi)  OUT=res://tmp/duel  REPLAY=1 (riprende il replay invece della partita)
func _init():call_deferred("run")
func env(k: String,d: String) -> String:return OS.get_environment(k) if OS.get_environment(k)!="" else d
func run():
	root.size=Vector2i(900,700)
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	var a_id=env("A","gascor");var b_id=env("B","anteos")
	if env("FORGE","")!="":   # FORGE=due_armi: A è un eroe della forgia con quell'arma (e tutte le pedine in più accese)
		var t=BloodForge.default_traits();t.arma=env("FORGE","");t.scudo=env("SCUDO","nessuno");t.id="forged_prova";t.name="Prova";t.on=BloodForge.EXTRA_IDS.duplicate()
		var d=BloodForge.build(t);BloodRules.extra_defs[d.id]=d;main.game.add_definition(d);a_id=d.id
	main.roster=[{"character":a_id,"team":0,"controller":"human","seat":0},{"character":b_id,"team":1,"controller":"human","seat":1}]
	main.minis_3d=true;main.scenario="libero"
	for k in main.house:main.house[k]=false
	main._start_local()
	var g=main.game
	g.deploy(g.entry_cells(0)[0],0);g.deploy(g.entry_cells(1)[0],3)
	var ca="4,3";var side=int(env("SIDE","0"));var cb=BloodRules.neighbor(ca,side)
	g.state.fighters[0].cell=ca;g.state.fighters[0].facing=0
	g.state.fighters[1].cell=cb;g.state.fighters[1].facing=posmod(int(env("FB",str(side+3))),6)
	main._refresh();await create_timer(1.5).timeout
	var b=main.board3d;b.follow=false;b.target=(b.cell_pos(ca)+b.cell_pos(cb))*.5;b.yaw=b.facing_yaw(0)+PI+float(env("YAW","0.5"));b.pitch=float(env("PITCH","0.95"));b.dist=float(env("DIST","4.6"));b._place_camera()
	b.labels_on=false;b.set_labels(false)
	g.plan(0,env("MA","right"));g.plan(1,env("MB","parry_r"));g.reveal()
	var dice=[]
	for d in env("DICE","1,1,1,1").split(","):dice.append(int(d))
	g.forced_dice=dice
	var n=int(env("N","14"));var dt=float(env("DT",".14"));var out=env("OUT","res://tmp/duel");DirAccess.make_dir_recursive_absolute(out)
	var guard=0;var shot=false
	while guard<40 and not shot:
		guard+=1
		match str(g.state.phase):
			"draw":g.draw_next()
			"reaction":g.react(env("RB",env("MB","parry_r")) if env("RB",env("MB","parry_r")) in g.reaction_options(int(g.state.pending.reactors[0])) else "pass")
			"acting":
				var i=int(g.state.active)
				if i==0:
					var ok=false
					if env("STEP","")!="":
						var dest=BloodRules.neighbor(ca,int(env("STEP","")))
						ok=g.act({"target":dest,"facing":int(env("FA","0"))})
					else:ok=g.act({"target":cb,"facing":0})
					print("A agisce: ",ok," fase ",g.state.phase)
					if g.state.phase=="reaction":g.react(env("RB",env("MB","parry_r")) if env("RB",env("MB","parry_r")) in g.reaction_options(int(g.state.pending.reactors[0])) else "pass")
					shot=true
				else:g.act({"pass":true,"facing":int(g.state.fighters[i].facing)})
			_:break
	main._refresh()
	if env("REPLAY","")!="":
		while b.busy():await create_timer(.2).timeout
		b.replay();await create_timer(.75).timeout
	for f in n:
		await create_timer(dt).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/f_%02d.png"%[out,f])
	for l in g.state.log.slice(maxi(0,g.state.log.size()-4)):print("  ",l)
	quit()
