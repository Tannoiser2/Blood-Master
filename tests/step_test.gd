extends SceneTree
# Regola del passo: pedina d'attacco con lati verdi, un passo prima o dopo il colpo; duelli dell'IA senza errori
func _init() -> void:
	var t=BloodForge.default_traits();t.id="forged_passo";t.name="Passo"
	var d=BloodForge.build(t)
	d.moves.thrust.green=[2,4];d.moves.parry_r.green=[3]   # affondo con passo indietro di lato, parata con passo indietro
	BloodRules.extra_defs[d.id]=d
	var ok=0;var steps_before=0;var steps_after=0
	for seed_n in 30:
		var r=BloodRules.new()
		r.new_game([{"character":d.id,"team":0,"controller":"ai"},{"character":"gascor","team":1,"controller":"ai"}],"libero",seed_n,-1)
		var n=0
		while r.state.phase!="finished" and r.state.turn<30 and n<6000:
			n+=1
			match r.state.phase:
				"deploy":
					var i=int(r.state.active);var team=int(r.state.fighters[i].team);var en=r.entry_cells(team);r.deploy(en[i%en.size()],0 if team==0 else 3)
				"planning":
					for i in r.needs_plan():r.plan(i,BloodAI.choose_move(r,i))
					r.reveal()
				"draw":r.draw_next()
				"acting":
					var a=int(r.state.active);var cmd=BloodAI.command(r,a)
					if cmd.has("step"):
						if cmd.get("step_after",false):steps_after+=1
						else:steps_before+=1
					if not r.act(cmd):print("COMANDO RIFIUTATO ",cmd," mossa ",r.state.fighters[a].current);r.act({"pass":true,"facing":int(r.state.fighters[a].facing)})
				"opportunity":r.opportunity(BloodAI.opportunity(r,int(r.state.pending.reactors[0])))
				"reaction":r.react(BloodAI.reaction(r,int(r.state.pending.reactors[0])))
				"stumble":r.choose_stumble(r.state.pending.path.back())
				"upkeep":r.advance_effect(BloodAI.effect_facing(r))
				_:break
		if r.state.phase=="finished":ok+=1
	print("STEP partite finite %d/30 · passi prima %d · passi dopo %d"%[ok,steps_before,steps_after])
	quit()
