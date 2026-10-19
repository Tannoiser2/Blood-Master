class_name BloodAI
extends RefCounted

# AI reads public positions and printed characteristics only. It never examines
# plans, the shuffled extraction bag or the random generator state.
static func choose_move(game: BloodRules,i: int,difficulty: int=1) -> String:
	var p=game.state.fighters[i];var legal=game.legal_moves(i)
	if legal.is_empty():return ""
	var best=-INF;var selected=str(legal[0]);var nearest=99
	for b in game.state.fighters:
		if game.living(b) and b.team!=p.team:nearest=mini(nearest,BloodRules.distance(p.cell,b.cell))
	for id in legal:
		var m=game.move(p,id);var score=0.0
		if id=="again":m=game.move(p)
		var targets=game.targets(i,m.id)
		if m.attack!=null:
			score=-15.0 if targets.is_empty() else float(m.attack)*1.3-float(m.defense)*.7-float(m.fatigue)*3
			if m.get("imbalance")!=null:score+=float(m.imbalance)*.7
		if m.rest:score+=minf(12.0,float(p.fatigue)*2.5)
		if id=="guard":score+=2 if nearest<=2 else -2
		if id in ["advance","run","float","charge"]:
			score=7.0 if nearest>1 else -4.0
			if id in ["run","float"] and nearest>3:score+=3
			if id=="charge" and nearest in [2,3]:score+=5
		if id=="concentrate":score=16.0 if p.magic<3 else (6.0 if nearest>2 else -5.0)
		if id=="load":score=13.0 if nearest>2 else -4.0
		if id=="shoot" and not targets.is_empty():score=18.0
		if id=="weapon" and p.bow and nearest<=2:score=20.0
		if id in ["rise","roll"]:score=20.0 if id=="rise" else 1.0
		if m.get("spell",false):
			score=-20.0 if targets.is_empty() else 10.0+float(m.value)
			if id=="heal":score=18.0 if p.hp<9 else -3.0
			if id=="shield":score=9 if nearest<=2 else -3
			if id in ["pustules","shock","fear"] and nearest>int(m.range):score=-10
		if id.begins_with("parry"):score-=8
		if difficulty==0:score+=sin(float(i*61+game.state.turn*13+id.hash()%97))*6
		if score>best:best=score;selected=id
	return selected

static func command(game: BloodRules,i: int) -> Dictionary:
	var p=game.state.fighters[i];var m=game.move(p);var targets=game.targets(i)
	var best=-INF;var selected=p.cell;var facing=int(p.facing)
	var enemy=-1;var near=999
	for j in game.state.fighters.size():
		var b=game.state.fighters[j]
		if game.living(b) and b.team!=p.team:
			var dist=BloodRules.distance(p.cell,b.cell)
			if dist<near:near=dist;enemy=j
	for k in targets:
		var score=0.0;var occupant=game.at(k,i)
		if occupant!=-1 and game.state.fighters[occupant].team!=p.team:
			var b=game.state.fighters[occupant]
			score=20.0-float(b.hp)*.2+float(game.move(b).get("defense",0))
		elif enemy!=-1:
			var dist=BloodRules.distance(k,game.state.fighters[enemy].cell)
			score=-float(dist)
			if p.fatigue>=4 and m.rest:score=float(dist)*.3
			if m.id=="teleport":score=float(dist) if p.hp<6 else -float(dist)
		if not game.hazard(k).is_empty():score-=15
		if m.id=="charge":
			var front=game.at(BloodRules.neighbor(k,int(p.facing)))
			if front!=-1 and game.state.fighters[front].team!=p.team:score+=25
			else:score-=12
		if score>best:best=score;selected=k
	if enemy!=-1:
		var desired=BloodRules.direction(p.cell if m.attack!=null else selected,game.state.fighters[enemy].cell)
		if m.id in ["rise","meditate","teleport","float"] or (m.id=="guard" and targets.is_empty()):facing=desired
		elif desired!=facing:facing=posmod(facing+(1 if posmod(desired-facing,6)<=3 else -1),6)
	if m.id.begins_with("parry") or m.id in ["dematerialize","weapon","roll"]:facing=int(p.facing)
	if targets.is_empty():
		if m.id=="guard":return {"wait":true,"facing":facing}
		return {"pass":true,"facing":int(p.facing)}
	return {"target":selected,"facing":facing,"extra":0}
static func reaction(game: BloodRules,i: int) -> String:
	var s=game.state.pending;var v=int(game.move(game.state.fighters[s.actor]).get("value",0)) if s.kind=="spell" else 0
	var opts=game.reaction_options(i,v)
	if "counter" in opts:return "counter"
	var best="pass";var value=999
	var p=game.state.fighters[i];var attacker=game.state.fighters[s.actor]
	var side=posmod(BloodRules.direction(p.cell,attacker.cell)-int(p.facing),6)
	for id in opts:
		if id=="pass":continue
		var m=game.move(p,id);var defense=int(m.defense) if side in m.blue else int(m.secondary)
		if defense<value:value=defense;best=id
	return best

static func opportunity(game: BloodRules,i: int) -> String:
	var p=game.state.fighters[i]
	if p.guarding and not game.targets(i).is_empty():return "guard"
	if p.current=="concentrate":
		var choice=choose_move(game,i)
		if game.move(p,choice).get("spell",false) and not game.targets(i,choice).is_empty():return choice
	return "pass"
