extends SceneTree
var failures=0
func _init() -> void:
	for seed_n in range(1,21):
		var r=BloodRules.new()
		var roster=[]
		var chars=["gascor","anteos","zenyo","shaara"] if seed_n<=10 else ["gandy","sanguinaria","thorn","ziggy"]
		for i in chars.size():roster.append({"character":chars[i],"team":i%2,"controller":"ai"})
		r.new_game(roster,"libero",seed_n,8)
		var steps=0
		while r.state.phase!="finished" and r.state.turn<100 and steps<10000:
			steps+=1
			var ok=true
			match r.state.phase:
				"deploy":
					var i=int(r.state.active);var team=int(r.state.fighters[i].team);ok=r.deploy(r.entry_cells(team)[i%2],0 if team==0 else 3)
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
			for p in r.state.fighters:
				if p.cell!="" and not r.cells.has(p.cell):push_error("Off-board piece");failures+=1
				if p.magic<0 or p.fatigue<0:push_error("Negative resource");failures+=1
		print("Seed %d: %s, turn %d, %d decisions"%[seed_n,r.state.phase,r.state.turn,steps])
		if steps>=10000:failures+=1
	print("SIMULATION FAILURES: ",failures)
	quit(1 if failures else 0)
