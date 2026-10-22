extends SceneTree
# Distribuzione delle mosse scelte dall'IA, spostamenti, attacchi e durata delle partite
func _init() -> void:
	var stats={};var total=0;var moved=0;var turns=0;var hits=0;var finished=0;var atk=0;var done_atk={};var guard_hits=0
	for seed_n in range(1,(31 if OS.get_environment("BIG")=="1" else 41)):
		var r=BloodRules.new()
		var war=["gascor","anteos","zenyo","shaara","kylvia","zak","ut","shannon","nuchra","ramok"]
		var roster=[]
		var big=OS.get_environment("BIG")=="1"
		if big:
			for id in ["gascor","zenyo","ut","kylvia","shannon","thorn","gandy"]:roster.append({"character":id,"team":0,"controller":"ai"})
			for id in ["anteos","shaara","zak","nuchra","ramok","sanguinaria","ziggy"]:roster.append({"character":id,"team":1,"controller":"ai"})
		else:
			for i in 4:roster.append({"character":war[(seed_n*3+i*5)%10],"team":i%2,"controller":"ai"})
			roster.append({"character":["gandy","thorn","sanguinaria","ziggy"][seed_n%4],"team":seed_n%2,"controller":"ai"})
		if "house" in r:
			for k in OS.get_environment("OFF").split(",",false):r.house[k]=false
		r.new_game(roster,"frontale",seed_n,8)
		var steps=0
		while r.state.phase!="finished" and r.state.turn<40 and steps<10000:
			steps+=1
			match r.state.phase:
				"deploy":
					var i=int(r.state.active);var team=int(r.state.fighters[i].team);var en=r.entry_cells(team);r.deploy(en[i%en.size()],0 if team==0 else 3)
				"planning":
					for i in r.needs_plan():
						var mv=BloodAI.choose_move(r,i);stats[mv]=stats.get(mv,0)+1;total+=1;r.plan(i,mv)
					r.reveal()
				"draw":r.draw_next()
				"acting":
					var a=int(r.state.active);var before=str(r.state.fighters[a].cell)
					var am=r.move(r.state.fighters[a]);r.act(BloodAI.command(r,a))
					if am.get("attack")!=null and am.id!="guard":atk+=1;done_atk[am.id]=done_atk.get(am.id,0)+1
					if str(r.state.fighters[a].cell)!=before:moved+=1
				"opportunity":guard_hits+=1;r.opportunity(BloodAI.opportunity(r,int(r.state.pending.reactors[0])))
				"reaction":r.react(BloodAI.reaction(r,int(r.state.pending.reactors[0])))
				"stumble":r.choose_stumble(r.state.pending.path.back())
				"upkeep":r.advance_effect(int(r.state.fighters[r.state.active].facing))
		turns+=int(r.state.turn);finished+=1 if r.state.phase=="finished" else 0
		for p in r.state.fighters:hits+=int(p.max_hp)-int(p.hp)
	var ks=stats.keys();ks.sort_custom(func(a,b):return stats[a]>stats[b])
	var line=""
	for k in ks.slice(0,10):line+="%s %d%%  "%[k,roundi(100.0*stats[k]/total)]
	print("ESEGUITI ",done_atk," guard-colpi ",guard_hits);print(line);print("attacchi/turno %.2f spostamenti/turno %.2f"%[float(atk)/turns,float(moved)/turns]," spostamenti ",moved," ferite inflitte ",hits," turni ",turns," partite finite ",finished,"/40")
	quit()
