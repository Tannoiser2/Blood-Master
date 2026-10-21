extends SceneTree
var failures=0
var dup={}
func _init() -> void:
	for seed_n in range(1,61):
		var r=BloodRules.new()
		var roster=[]
		var all=["gascor","anteos","zenyo","shaara","gandy","sanguinaria","thorn","ziggy","kylvia","zak","ut","shannon","nuchra","ramok","skelos","sketos"];var chars=[]
		for q in 6:chars.append(all[(seed_n*7+q*5)%all.size()])
		for i in chars.size():roster.append({"character":chars[i],"team":i%2,"controller":"ai"})
		r.new_game(roster,"libero",seed_n,8)
		var steps=0
		while r.state.phase!="finished" and r.state.turn<100 and steps<10000:
			steps+=1
			var ok=true
			match r.state.phase:
				"deploy":
					var i=int(r.state.active);var team=int(r.state.fighters[i].team);ok=r.deploy(r.entry_cells(team)[0],0 if team==0 else 3)
				"planning":
					for i in r.needs_plan():ok=r.plan(i,BloodAI.choose_move(r,i)) and ok
					ok=r.reveal() and ok
				"draw":r.draw_next()
				"acting":ok=r.act(BloodAI.command(r,int(r.state.active)))
				"opportunity":ok=r.opportunity(BloodAI.opportunity(r,int(r.state.pending.reactors[0])))
				"reaction":ok=r.react(BloodAI.reaction(r,int(r.state.pending.reactors[0])))
				"stumble":ok=r.choose_stumble(r.state.pending.path.back())
				"upkeep":ok=r.advance_effect(int(r.state.fighters[r.state.active].facing))
			if not ok:
				print(r.state.fighters[r.state.active] if r.state.active>=0 else r.state.pending);print(BloodAI.command(r,r.state.active) if r.state.active>=0 else "");push_error("Rejected AI action seed %d step %d phase %s"%[seed_n,steps,r.state.phase]);failures+=1;break
			var occ={}
			for q in r.state.fighters.size():
				var f=r.state.fighters[q]
				if f.cell=="" or not f.alive:continue
				if occ.has(f.cell):
					var key="%s+%s %s %s"%[r.state.fighters[occ[f.cell]].character,f.character,r.state.phase,str(r.state.fighters[occ[f.cell]].current)+"/"+str(f.current)]
					if not dup.has(key):dup[key]=0;print("STESSO ESAGONO seed ",seed_n," turno ",r.state.turn," ",key," ",f.cell, " pieces ",r.state.fighters[occ[f.cell]].pieces,f.pieces)
					dup[key]+=1
				occ[f.cell]=q
			for p in r.state.fighters:
				if p.cell!="" and not r.cells.has(p.cell):push_error("Off-board piece");failures+=1
				if p.magic<0 or p.fatigue<0:push_error("Negative resource");failures+=1
		print("Seed %d: %s, turn %d, %d decisions"%[seed_n,r.state.phase,r.state.turn,steps])
		if steps>=10000:failures+=1
	print("SIMULATION FAILURES: ",failures)
	quit(1 if failures else 0)
