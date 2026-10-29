extends SceneTree
# Equilibrio dei personaggi: duelli 1 contro 1 fra tutti gli archetipi (MODE=duel) oppure squadre
# miste casuali 3 contro 3 (MODE=team). Stampa una riga RIS per partita: chi c'era e chi ha vinto.
# S0/S1 = intervallo di semi, per dividere il lavoro in più processi.
const TYPES=["zenyo","gascor","ut","shannon","kylvia","gandy","thorn","sanguinaria","ziggy"]
func _init() -> void:
	var mode=OS.get_environment("MODE") if OS.get_environment("MODE")!="" else "duel"
	var s0=int(OS.get_environment("S0")) if OS.get_environment("S0")!="" else 0
	var s1=int(OS.get_environment("S1")) if OS.get_environment("S1")!="" else 40
	for seed_n in range(s0,s1):
		var rosters=[]
		if mode=="duel":
			for a in TYPES.size():
				for b in range(a+1,TYPES.size()):
					# lati alternati: metà delle partite ognuno parte dall'altra parte
					var x=TYPES[a] if seed_n%2==0 else TYPES[b];var y=TYPES[b] if seed_n%2==0 else TYPES[a]
					rosters.append([x,y])
		else:
			var rng=RandomNumberGenerator.new();rng.seed=seed_n*7919
			var pool=TYPES.duplicate();var t0=[];var t1=[]
			for n in 3:t0.append(pool[rng.randi_range(0,pool.size()-1)])
			for n in 3:t1.append(pool[rng.randi_range(0,pool.size()-1)])
			rosters.append(t0+t1)
		for ro in rosters:
			var r=BloodRules.new();var roster=[]
			var half=ro.size()/2
			for n in ro.size():roster.append({"character":ro[n],"team":0 if n<half else 1,"controller":"ai"})
			r.new_game(roster,"libero",seed_n*131+ro.hash()%1000,-1)
			var steps=0
			while not r.state.phase in ["finished"] and r.state.turn<30 and steps<8000:
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
			# a fine partita (o al limite dei turni): vince chi resta, altrimenti chi ha più ferite residue in proporzione
			var w=int(r.state.winner) if r.state.phase=="finished" else -1
			var share=[0.0,0.0]
			for p in r.state.fighters:
				if p.character in ["golem","skelos","sketos"] or int(p.get("owner",-1))>=0:continue
				var t=int(p.team) if int(p.get("controller_by",-1))<0 else int(p.team)
				if p.alive and int(p.max_hp)>0:share[t]+=float(p.hp)/float(p.max_hp)
				elif p.alive:share[t]+=1.0
			print("RIS %s|%s|%d|%d|%.2f|%.2f"%[",".join(ro.slice(0,half)),",".join(ro.slice(half)),w,int(r.state.turn),share[0],share[1]])
	quit()
