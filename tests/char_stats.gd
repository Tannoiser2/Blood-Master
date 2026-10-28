extends SceneTree
# Mosse scelte da un personaggio (CHAR=nuchra) in molte partite, e quanto combatte davvero
func _init() -> void:
	var who=OS.get_environment("CHAR") if OS.get_environment("CHAR")!="" else "nuchra"
	var dbg_n=0
	var stats={};var total=0;var moved=0;var acts=0;var atk=0;var adj_turns=0;var far_guard=0
	var foes=["gascor","anteos","zenyo","shaara","kylvia","zak","ut","shannon","ramok"]
	for seed_n in range(1,41):
		var r=BloodRules.new()
		var roster=[{"character":who,"team":0,"controller":"ai"},{"character":foes[seed_n%9],"team":1,"controller":"ai"}]
		if seed_n%2==0:roster+=[{"character":foes[(seed_n+3)%9],"team":0,"controller":"ai"},{"character":foes[(seed_n+5)%9],"team":1,"controller":"ai"}]
		r.new_game(roster,"libero",seed_n,8)
		var steps=0
		while r.state.phase!="finished" and r.state.turn<40 and steps<6000:
			steps+=1
			match r.state.phase:
				"deploy":
					var i=int(r.state.active);var team=int(r.state.fighters[i].team);var en=r.entry_cells(team);r.deploy(en[i%en.size()],0 if team==0 else 3)
				"planning":
					for i in r.needs_plan():
						BloodAI._dbg_scores={}
						var mv=BloodAI.choose_move(r,i)
						if r.state.fighters[i].character==who and dbg_n<10 and OS.get_environment("BM_AIDBG")!="":
							var nn=99
							for j in BloodAI._enemies(r,i):nn=mini(nn,r.walk_distance(r.state.fighters[i].cell,r.state.fighters[j].cell))
							if nn==1:dbg_n+=1;print("SCELTA ",mv," ",BloodAI._dbg_scores," fronte ",r.state.fighters[i].facing," nemici-lati ",BloodAI._enemies(r,i).filter(func(j):return BloodRules.distance(r.state.fighters[i].cell,r.state.fighters[j].cell)==1).map(func(j):return posmod(BloodRules.direction(r.state.fighters[i].cell,r.state.fighters[j].cell)-int(r.state.fighters[i].facing),6)))
						if r.state.fighters[i].character==who:
							stats[mv]=stats.get(mv,0)+1;total+=1
							var near=99
							for j in BloodAI._enemies(r,i):near=mini(near,r.walk_distance(r.state.fighters[i].cell,r.state.fighters[j].cell))
							var key="%s@%d"%[mv,mini(near,4)];stats["_"+key]=stats.get("_"+key,0)+1
							if near==1:adj_turns+=1
							elif mv=="guard" and near>2:far_guard+=1
						r.plan(i,mv)
					r.reveal()
				"draw":r.draw_next()
				"acting":
					var a=int(r.state.active);var before=str(r.state.fighters[a].cell);var m=r.move(r.state.fighters[a])
					var cm=BloodAI.command(r,a)
					if r.state.fighters[a].character==who and m.id=="guard":
						var k2="guardia_"+("attacca" if cm.has("target") else ("aspetta" if cm.get("wait",false) else "passa"));stats["_"+k2]=stats.get("_"+k2,0)+1
					r.act(cm)
					if r.state.fighters[a].character==who:
						acts+=1
						if str(r.state.fighters[a].cell)!=before:moved+=1
						if m.get("attack")!=null and m.id!="guard":atk+=1
				"opportunity":r.opportunity(BloodAI.opportunity(r,int(r.state.pending.reactors[0])))
				"reaction":r.react(BloodAI.reaction(r,int(r.state.pending.reactors[0])))
				"stumble":r.choose_stumble(r.state.pending.path.back())
				"upkeep":r.advance_effect(int(r.state.fighters[r.state.active].facing))
	var ks=stats.keys();ks.sort_custom(func(a,b):return stats[a]>stats[b])
	var line=""
	for k in ks:
		if not k.begins_with("_"):line+="%s %d%%  "%[k,roundi(100.0*stats[k]/total)]
	var det=[]
	for k in ks:
		if k.begins_with("_"):det.append("%s %d"%[k.substr(1),stats[k]])
	print("per distanza: ",", ".join(det.slice(0,16)))
	print(who,": ",line)
	print("azioni ",acts," spostamenti ",moved," attacchi ",atk," turni accanto a un nemico ",adj_turns,"/",total," guardia lontano dai nemici ",far_guard)
	quit()
