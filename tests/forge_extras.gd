extends SceneTree
# Pedine in più (doppio colpo, contrattacco, finta, sgambetto, rotazione, multi attacco): partite senza errori
func _init() -> void:
	var notes={"contrattacca":0,"colpisce di nuovo":0,"rifiutati":0}
	for arma in ["spada","due_armi","ascia"]:
		var t=BloodForge.default_traits();t.arma=arma;t.id="forged_x_"+arma;t.name="X "+arma
		t.on=["double","parry_counter","feint","trip","spin","bash"]
		var d=BloodForge.apply_edits(BloodForge.build(t),{"hp":0,"moves":{"cleave":{"multi":true,"red":[5,0,1]}} if arma!="ascia" else {}})
		BloodRules.extra_defs[d.id]=d
		var used={}
		for seed_n in 12:
			var r=BloodRules.new()
			r.new_game([{"character":d.id,"team":0,"controller":"ai"},{"character":"gascor","team":1,"controller":"ai"},{"character":"shannon","team":1,"controller":"ai"}],"libero",seed_n,-1)
			var n=0
			while r.state.phase!="finished" and r.state.turn<30 and n<6000:
				n+=1
				match r.state.phase:
					"deploy":
						var i=int(r.state.active);var team=int(r.state.fighters[i].team);var en=r.entry_cells(team);r.deploy(en[i%en.size()],0 if team==0 else 3)
					"planning":
						for i in r.needs_plan():
							var mv=BloodAI.choose_move(r,i);r.plan(i,mv)
							if i==0:used[mv]=used.get(mv,0)+1
						r.reveal()
					"draw":r.draw_next()
					"acting":
						var a=int(r.state.active)
						if not r.act(BloodAI.command(r,a)):notes.rifiutati+=1;r.act({"pass":true,"facing":int(r.state.fighters[a].facing)})
					"opportunity":r.opportunity(BloodAI.opportunity(r,int(r.state.pending.reactors[0])))
					"reaction":r.react(BloodAI.reaction(r,int(r.state.pending.reactors[0])))
					"stumble":r.choose_stumble(r.state.pending.path.back())
					"upkeep":r.advance_effect(BloodAI.effect_facing(r))
					_:break
			for line in r.state.log:
				for k in ["contrattacca","colpisce di nuovo"]:
					if k in str(line):notes[k]+=1
		print(arma," punti %d"%roundi(BloodForge.points(d))," mosse ",used)
	print("NOTE ",notes)
	quit()
