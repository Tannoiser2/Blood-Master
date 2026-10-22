extends SceneTree
var failures=0
var stats={}
func _init() -> void:
	for seed_n in range(1,81):
		var r=BloodRules.new()
		var roster=[]
		var mages=["gandy","thorn","sanguinaria","ziggy"];var war=["gascor","anteos","zenyo","shaara","kylvia","zak","ut","shannon","nuchra","ramok"]
		var chars=[mages[seed_n%4],war[seed_n%10],mages[(seed_n/4)%4],war[(seed_n*3+1)%10],war[(seed_n*7+2)%10],war[(seed_n*5+3)%10]]
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
					for i in r.needs_plan():
						var mv=BloodAI.choose_move(r,i)
						if r.move(r.state.fighters[i],mv).get("spell",false):stats["plan_"+mv]=stats.get("plan_"+mv,0)+1
						if r.state.fighters[i].character=="ziggy":stats["Z_"+mv]=stats.get("Z_"+mv,0)+1
						ok=r.plan(i,mv) and ok
					ok=r.reveal() and ok
				"draw":r.draw_next()
				"acting":
					var a=int(r.state.active);var c=BloodAI.command(r,a);var mv=r.move(r.state.fighters[a])
					if mv.get("spell",false):stats["cast_"+mv.id]=stats.get("cast_"+mv.id,0)+1
					if r.state.fighters[a].previous==r.state.fighters[a].current and mv.get("spell",false):stats["again_"+mv.id]=stats.get("again_"+mv.id,0)+1
					if int(r.state.fighters[a].get("controller_by",-1))>=0:
						var tg=r.at(str(c.get("target","")),a)
						var k2="ctrl_"+("amico" if tg>=0 and int(r.state.fighters[tg].team)==int(r.state.fighters[a].team) else ("nemico" if tg>=0 else "nessuno"))+"_"+str(mv.id)
						stats[k2]=stats.get(k2,0)+1
					ok=r.act(c)
				"opportunity":ok=r.opportunity(BloodAI.opportunity(r,int(r.state.pending.reactors[0])))
				"reaction":ok=r.react(BloodAI.reaction(r,int(r.state.pending.reactors[0])))
				"stumble":ok=r.choose_stumble(r.state.pending.path.back())
				"upkeep":
					stats["upkeep_move"]=stats.get("upkeep_move",0)+1;ok=r.advance_effect(BloodAI.effect_facing(r))
			if not ok:
				print(r.state.fighters[r.state.active] if r.state.active>=0 else r.state.pending);print(BloodAI.command(r,r.state.active) if r.state.active>=0 else "");push_error("Rejected AI action seed %d step %d phase %s"%[seed_n,steps,r.state.phase]);failures+=1;break
			for p in r.state.fighters:
				if p.cell!="" and not r.cells.has(p.cell):push_error("Off-board piece");failures+=1
				if p.magic<0 or p.fatigue<0:push_error("Negative resource");failures+=1
		if false:print("Seed %d: %s, turn %d, %d decisions"%[seed_n,r.state.phase,r.state.turn,steps])
		if steps>=10000:failures+=1
	var ks=stats.keys();ks.sort()
	for k in ks:print(k," ",stats[k])
	print("FAIL ",failures)
	quit(1 if failures else 0)
