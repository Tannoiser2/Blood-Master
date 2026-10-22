extends SceneTree
# Rialzarsi con passi e rotolare da a terra: nessuna traccia di caduta/sbilanciamento in più.
func _init():call_deferred("run")
func run():
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	main.roster=[{"character":"gascor","team":0,"controller":"human","seat":0},{"character":"anteos","team":1,"controller":"human","seat":1}]
	main.minis_3d=true;main.speed=.05;main.house["scenery"]=false
	main._start_local()
	await create_timer(1.0).timeout
	var g=main.game;var b=main.board3d
	for mv in ["rise","rise","roll"]:
		while b.busy():await create_timer(.2).timeout
		var p=g.state.fighters[0]
		p.down=true;p.unbalanced=false;p.current="down";p.done=false
		b.sync();await create_timer(.5).timeout
		while b.busy():await create_timer(.2).timeout
		var hn=b.history.size()
		p.current=mv;g.state.phase="acting";g.state.active=0
		var cells=g.reachable(0,1 if mv=="rise" else 2,[]).keys().filter(func(c):return c!=p.cell)
		var ln=g.state.log.size() if g.state.has("log") else 0
		var ok=g.act({"target":cells[0]})
		if g.state.has("log"):print("  LOG ",g.state.log.slice(ln))
		print("  da ",p.get("path",[])," celle ",cells)
		print("hist ",hn," -> ",b.history.size()," queue ",b.queue.size());print(mv," act ",ok," down ",p.down," unbalanced ",p.unbalanced," current ",p.current)
		b.sync()
		await create_timer(.3).timeout
		while b.busy():await create_timer(.2).timeout
		for st in b.history.slice(hn):
			print("  passo")
			for tr in st:
				if tr.get("i",-1)==0:print("  traccia ",tr.clip," move ",tr.move," stay ",tr.get("stay",false)," lying ",tr.get("lying",false))
		print("  posa finale ",b.minis[0].ap.assigned_animation)
	await create_timer(2.0).timeout
	for st in b.history:
		print("PASSO")
		for tr in st:
			if tr.has("clip"):print("  ",tr.i," ",tr.clip," move ",tr.move," stay ",tr.get("stay",false)," path ",tr.has("path"))
	quit()
