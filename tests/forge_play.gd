extends SceneTree
# Un duello per ogni arma della forgia contro Gascor: nessun errore, partita che finisce
func _init() -> void:
	for arma in BloodForge.ARMI:
		for scudo in ["nessuno","grande"]:
			var t=BloodForge.default_traits();t.arma=arma;t.scudo=scudo;t.id="forged_t_"+arma+scudo;t.name="Prova "+arma
			if OS.get_environment("SPELLS")!="":   # con magie: Intelligenza 5 e quattro incantesimi di maghi diversi
				t.INT=5;t.spells=["fireball","lightning","fear","wall"]
			var d=BloodForge.build(t);BloodRules.extra_defs[d.id]=d
			var r=BloodRules.new();r.house["arrows"]=true
			r.new_game([{"character":d.id,"team":0,"controller":"ai"},{"character":"gascor","team":1,"controller":"ai"}],"libero",7,-1)
			var steps=0;var used={}
			while r.state.phase!="finished" and r.state.turn<30 and steps<6000:
				steps+=1
				match r.state.phase:
					"deploy":
						var i=int(r.state.active);var team=int(r.state.fighters[i].team);var en=r.entry_cells(team);r.deploy(en[i%en.size()],0 if team==0 else 3)
					"planning":
						for i in r.needs_plan():
							var mv=BloodAI.choose_move(r,i);r.plan(i,mv)
							if i==0:used[mv]=used.get(mv,0)+1
						r.reveal()
					"draw":r.draw_next()
					"acting":r.act(BloodAI.command(r,int(r.state.active)))
					"opportunity":r.opportunity(BloodAI.opportunity(r,int(r.state.pending.reactors[0])))
					"reaction":r.react(BloodAI.reaction(r,int(r.state.pending.reactors[0])))
					"stumble":r.choose_stumble(r.state.pending.path.back())
					"upkeep":r.advance_effect(BloodAI.effect_facing(r))
					_:break
			# salvataggio e ripresa: la scheda viaggia con la partita
			var snap=JSON.parse_string(JSON.stringify(r.snapshot()))
			BloodRules.extra_defs.erase(d.id)
			var r2=BloodRules.new();r2.restore(snap)
			print("%-9s %-8s fase %s turno %d vince %d punti %d ripresa %s mosse %s"%[arma,scudo,r.state.phase,int(r.state.turn),int(r.state.winner),roundi(BloodForge.points(d)),str(r2.catalog.has(d.id)),used])
	quit()
