extends SceneTree
# Duelli fra varianti (personaggi modificati, da un file JSON) e il cast ufficiale.
# VARS=file.json  V0/V1 = quali varianti (indici)  SEEDS = partite per avversario
const FOES=["zenyo","gascor","ut","shannon","kylvia","gandy","thorn","sanguinaria","ziggy"]
func _init() -> void:
	var defs: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("VARS")))
	BloodRules.extra_defs=defs
	var ids=defs.keys();ids.sort()
	var v0=int(OS.get_environment("V0"));var v1=mini(int(OS.get_environment("V1")),ids.size())
	var seeds=int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS")!="" else 16
	for vi in range(v0,v1):
		var vid=ids[vi]
		for foe in FOES:
			for s in seeds:
				var ro=[vid,foe] if s%2==0 else [foe,vid]
				var r=BloodRules.new();var roster=[]
				for n in 2:roster.append({"character":ro[n],"team":n,"controller":"ai"})
				r.new_game(roster,"libero",s*977+vi*31+foe.hash()%997,-1)
				var steps=0
				while r.state.phase!="finished" and r.state.turn<30 and steps<8000:
					steps+=1
					match r.state.phase:
						"deploy":
							var i=int(r.state.active);var team=int(r.state.fighters[i].team);var en=r.entry_cells(team);r.deploy(en[i%en.size()],0 if team==0 else 3)
						"planning":
							for i in r.needs_plan():r.plan(i,BloodAI.choose_move(r,i))
							r.reveal()
						"draw":r.draw_next()
						"acting":r.act(BloodAI.command(r,int(r.state.active)))
						"opportunity":r.opportunity(BloodAI.opportunity(r,int(r.state.pending.reactors[0])))
						"reaction":r.react(BloodAI.reaction(r,int(r.state.pending.reactors[0])))
						"stumble":r.choose_stumble(r.state.pending.path.back())
						"upkeep":r.advance_effect(BloodAI.effect_facing(r))
						_:break
				var w=int(r.state.winner) if r.state.phase=="finished" else -1
				var share=[0.0,0.0]
				for p in r.state.fighters:
					if int(p.get("owner",-1))>=0:continue
					if p.alive:share[int(p.team)]+=float(p.hp)/float(p.max_hp) if int(p.max_hp)>0 else 1.0
				print("RIS %s|%s|%d|%d|%.2f|%.2f"%[ro[0],ro[1],w,int(r.state.turn),share[0],share[1]])
	quit()
