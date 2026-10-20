# Sfida a coppie speculari tra BloodAI e la versione di riferimento (tests/ai_baseline.gd).
# LINEUP=0..4 GAMES=200 godot --headless -s tests/ai_duel.gd
extends SceneTree
const OldAI=preload("res://tests/ai_baseline.gd")
func _init() -> void:
	var v=OS.get_environment("AIV").split(",")
	if OS.get_environment("AIB")!="":BloodAI.BACK_W=float(OS.get_environment("AIB"))
	if v.size()==4:BloodAI.EXPOSE_ADJ=float(v[0]);BloodAI.EXPOSE_NEAR=float(v[1]);BloodAI.TROUBLE_RETREAT=float(v[2]);BloodAI.CHARGE_W=float(v[3])
	var lineups=[["gascor","anteos","ut","shannon"],["nuchra","ramok","zenyo","shaara"],["kylvia","zak","gascor","anteos"],["gandy","thorn","sanguinaria","ziggy"],["gascor","sanguinaria","anteos","gandy","kylvia","zak"]]
	var only=OS.get_environment("LINEUP");var n=int(OS.get_environment("GAMES")) if OS.get_environment("GAMES")!="" else 120
	var per={};var new_wins=0;var old_wins=0;var draws=0;var freq={}
	for g in n:
		var seed_n=g+1+int(OS.get_environment("SEED0")) if OS.get_environment("SEED0")!="" else g+1
		var li=seed_n%lineups.size() if only=="" else int(only)
		var chars=lineups[li];var new_team=g%2   # partite a coppie: stesso seme, IA scambiate di squadra
		seed_n=g/2+1+int(OS.get_environment("SEED0")) if OS.get_environment("SEED0")!="" else g/2+1
		var r=BloodRules.new();var roster=[]
		for i in chars.size():roster.append({"character":chars[i],"team":i%2,"controller":"ai"})
		r.new_game(roster,"libero",seed_n,8)
		var steps=0
		while r.state.phase!="finished" and r.state.turn<40 and steps<12000:
			steps+=1
			match r.state.phase:
				"deploy":
					var i=int(r.state.active);var team=int(r.state.fighters[i].team);r.deploy(r.entry_cells(team)[0],0 if team==0 else 3)
				"planning":
					for i in r.needs_plan():
						var nw=int(r.state.fighters[i].team)==new_team
						var mv=BloodAI.choose_move(r,i) if nw else OldAI.choose_move(r,i)
						if OS.get_environment("FREQ")!="":
							var tag=("N " if nw else "O ")+str(r.state.fighters[i].character)+":"+mv;freq[tag]=freq.get(tag,0)+1
						r.plan(i,mv)
					r.reveal()
				"draw":r.draw_next()
				"acting":
					var a=int(r.state.active)
					var c=BloodAI.command(r,a) if int(r.state.fighters[a].team)==new_team else OldAI.command(r,a)
					if not r.act(c):r.act({"pass":true,"facing":int(r.state.fighters[a].facing)})
				"opportunity":r.opportunity(BloodAI.opportunity(r,int(r.state.pending.reactors[0])))
				"reaction":r.react(BloodAI.reaction(r,int(r.state.pending.reactors[0])))
				"stumble":r.choose_stumble(r.state.pending.path.back())
				"upkeep":r.advance_effect(int(r.state.fighters[r.state.active].facing))
		var key=str(li);if not per.has(key):per[key]=[0,0]
		if r.state.phase=="finished" and int(r.state.winner)==new_team:new_wins+=1;per[key][0]+=1
		elif r.state.phase=="finished" and int(r.state.winner)>=0:old_wins+=1;per[key][1]+=1
		else:draws+=1
	print("PER FORMAZIONE ",per)
	print("NUOVA IA vince %d, vecchia %d, altre %d su %d" % [new_wins,old_wins,draws,n])
	if OS.get_environment("FREQ")!="":
		var ks=freq.keys();ks.sort()
		for k in ks:print(k," ",freq[k])
	quit()
