extends SceneTree
# Distribuzione delle mosse scelte dall'IA, spostamenti, attacchi e durata delle partite
func _init() -> void:
	var stats={};var total=0;var moved=0;var turns=0;var hits=0;var finished=0;var atk=0;var done_atk={};var guard_hits=0;var mv_total=0;var mv_still=0;var mv_still_closer=0
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
					var am=r.move(r.state.fighters[a]);var cmd=BloodAI.command(r,a)
					if am.id in ["advance","run"]:
						var tg=r.targets(a).filter(func(c):return c!=r.state.fighters[a].cell)
						if not tg.is_empty():
							var en=BloodAI._enemies(r,a);var near=99;var bestc=99
							for j in en:near=mini(near,r.walk_distance(r.state.fighters[a].cell,r.state.fighters[j].cell))
							for c in tg:
								for j in en:bestc=mini(bestc,r.walk_distance(c,r.state.fighters[j].cell))
							mv_total+=1
							if str(cmd.get("target",""))==str(r.state.fighters[a].cell) or cmd.get("pass",false):
								mv_still+=1
								if bestc<near and near>1:
									mv_still_closer+=1
									if mv_still_closer<=12:
										var pf=r.state.fighters[a];var here_s=BloodAI._move_score(r,a,pf.cell,am);var row=[]
										for c in tg:row.append("%s:%.1f"%[c,BloodAI._move_score(r,a,c,am)])
										print("FERMO ",pf.character," ",am.id," vicino ",near," cella ",pf.cell," fronte ",pf.facing," ferite ",pf.hp,"/",pf.max_hp," resta %.1f "%here_s,row," arciere ",pf.get("bow",false))
					r.act(cmd)
					if am.get("attack")!=null and am.id!="guard":atk+=1;done_atk[am.id]=done_atk.get(am.id,0)+1
					if str(r.state.fighters[a].cell)!=before:moved+=1
				"opportunity":guard_hits+=1;r.opportunity(BloodAI.opportunity(r,int(r.state.pending.reactors[0])))
				"reaction":
					var rj=int(r.state.pending.reactors[0]);var planned=r.move(r.state.fighters[rj]);var ch=BloodAI.reaction(r,rj)
					var tag="reazioni_"+("para" if ch!="pass" else "passa")+("_aveva_attacco" if planned.get("attack")!=null and planned.id!="guard" else ("_aveva_guardia" if planned.id=="guard" else "_altro"))
					stats["_"+tag]=stats.get("_"+tag,0)+1
					r.react(ch)
				"stumble":r.choose_stumble(r.state.pending.path.back())
				"upkeep":r.advance_effect(int(r.state.fighters[r.state.active].facing))
		turns+=int(r.state.turn);finished+=1 if r.state.phase=="finished" else 0
		for p in r.state.fighters:hits+=int(p.max_hp)-int(p.hp)
	var ks=stats.keys();ks.sort_custom(func(a,b):return stats[a]>stats[b])
	var line=""
	var rr=[]
	for k in ks:
		if k.begins_with("_"):rr.append("%s %d"%[k.substr(1),stats[k]])
	print("REAZIONI ",", ".join(rr))
	for k in ks.filter(func(x):return not x.begins_with("_")).slice(0,10):line+="%s %d%%  "%[k,roundi(100.0*stats[k]/total)]
	print("MOVIMENTI ",mv_total," fermi ",mv_still," fermi pur potendo avvicinarsi ",mv_still_closer)
	print("ESEGUITI ",done_atk," guard-colpi ",guard_hits);print(line);print("attacchi/turno %.2f spostamenti/turno %.2f"%[float(atk)/turns,float(moved)/turns]," spostamenti ",moved," ferite inflitte ",hits," turni ",turns," partite finite ",finished,"/40")
	quit()
