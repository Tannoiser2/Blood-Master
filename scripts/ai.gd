class_name BloodAI
extends RefCounted

# L'IA legge solo ciò che è pubblico: posizioni, orientamenti, pedine rivelate, ferite e fatica.
# Non guarda mai i piani segreti, il sacchetto o il generatore di numeri casuali.
#
# Idee guida:
#  - colpire dove fa più male: stima le ferite attese (attacco, difesa della pedina avversaria,
#    lato colpito) e preferisce chi è ferito, sbilanciato, a terra o girato di spalle;
#  - aiutare gli amici: punta i nemici che stanno addosso a un alleato in difficoltà;
#  - ritirarsi quando si è malconci: allontanarsi dai nemici e mettersi dietro un alleato in forma;
#  - magie ad area messe dove servono (sui nemici, tra i nemici e gli amici feriti), mai sugli amici.

const POSITIONAL=[0,1,3,5,3,1]
static var EXPOSE_ADJ=2.0
static var EXPOSE_NEAR=.8
static var TROUBLE_RETREAT=.65
static var MAGES_KEEP_DISTANCE=false
static var WEAPON_RANGE=2
static var CHARGE_W=.6

# ------------------------------------------------------------------ valutazioni di base
static func _enemies(game: BloodRules,i: int) -> Array:
	var p=game.state.fighters[i];var out=[]
	for j in game.state.fighters.size():
		var b=game.state.fighters[j]
		if j!=i and game.living(b) and not b.get("pieces",false) and b.team!=p.team and b.cell!="":out.append(j)
	return out
static func _allies(game: BloodRules,i: int) -> Array:
	var p=game.state.fighters[i];var out=[]
	for j in game.state.fighters.size():
		var b=game.state.fighters[j]
		if j!=i and game.living(b) and not b.get("pieces",false) and b.team==p.team and b.cell!="":out.append(j)
	return out
static func _health(p: Dictionary) -> float:
	return clampf(float(p.hp)/maxf(1.0,float(p.max_hp)),0,1)
static func _trouble(game: BloodRules,i: int) -> float:
	# 0 = in forma, 1 = messo malissimo: poche ferite rimaste, tanta fatica, nemici addosso
	var p=game.state.fighters[i];var t=(1.0-_health(p))*.75+clampf((float(p.fatigue)+float(p.permanent))/12.0,0,1)*.35
	var adj=0
	for j in _enemies(game,i):
		if BloodRules.distance(p.cell,game.state.fighters[j].cell)==1:adj+=1
	if adj>=2:t+=.25
	if p.unbalanced or p.down:t+=.2
	return clampf(t,0,1)
static func _expected_wounds(game: BloodRules,i: int,j: int,m: Dictionary,from: String) -> float:
	# ferite attese colpendo j dalla cella "from" con la mossa m (stessa formula della tabella)
	var a=game.state.fighters[i];var b=game.state.fighters[j]
	if m.get("attack")==null:return 0.0
	var defense=game.move(b)
	var side=posmod(BloodRules.direction(b.cell,from)-int(b.facing),6)
	var dv=int(defense.get("defense",0))
	if b.get("shield",false):dv=-15
	if not defense.get("blue",[]).is_empty() and not side in defense.blue:dv=int(defense.get("secondary",dv))
	var positional=POSITIONAL[side] if not side in defense.get("red",[]) else 0
	var attack=float(m.attack)
	if m.id=="shoot":attack=15.0-float(BloodRules.distance(from,b.cell))
	attack+=float(a.get("sprint_mod",0))-float(a.fatigue)-float(a.permanent)
	var base=attack+float(dv)+float(b.get("sprint_mod",0))+float(b.fatigue)+float(b.permanent)+float(positional)
	var w=0.0
	for d in range(1,7):w+=maxf(0.0,base+float(d)-10.0)
	w/=6.0
	if b.down:w+=2.0
	if b.unbalanced:w+=1.0
	return w
static func _target_value(game: BloodRules,i: int,j: int,wounds: float) -> float:
	# quanto vale colpire j: le ferite attese pesano di più su chi è già malridotto (si può eliminare)
	var b=game.state.fighters[j];var v=wounds*2.0
	if wounds>=float(b.hp):v+=14.0                       # probabile eliminazione
	v+=(1.0-_health(b))*4.0
	# aiutare gli amici: il nemico che sta addosso a un alleato in difficoltà vale di più
	for k in _allies(game,i):
		var al=game.state.fighters[k]
		if BloodRules.distance(al.cell,b.cell)==1:v+=_trouble(game,k)*6.0
	if game.definition(b).get("mage",false):v+=2.0       # i maghi sono pericolosi
	return v
static func _threat_at(game: BloodRules,i: int,k: String) -> float:
	# pericolo in una cella: nemici vicini, più se sono in grado di colpire
	var t=0.0
	for j in _enemies(game,i):
		var b=game.state.fighters[j];var d=BloodRules.distance(k,b.cell)
		if d==1:t+=3.0*_health(b)+1.0
		elif d==2:t+=1.0*_health(b)
	return t
static func _cover_at(game: BloodRules,i: int,k: String) -> float:
	# riparo: alleati in forma vicini, meglio se stanno tra me e i nemici
	var c=0.0
	for a in _allies(game,i):
		var al=game.state.fighters[a];var d=BloodRules.distance(k,al.cell)
		if d<=2:c+=_health(al)*(2.0 if d==1 else 1.0)
		for j in _enemies(game,i):
			var e=game.state.fighters[j]
			if BloodRules.distance(e.cell,al.cell)<BloodRules.distance(e.cell,k):c+=.4*_health(al)
	return c
static func _focus(game: BloodRules,i: int) -> int:
	# il nemico da puntare: vicino, ferito, esposto, o addosso a un amico in difficoltà
	var p=game.state.fighters[i];var best=-INF;var out=-1
	for j in _enemies(game,i):
		var b=game.state.fighters[j];var d=float(BloodRules.distance(p.cell,b.cell))
		var v=-d*1.6+(1.0-_health(b))*6.0+(3.0 if b.unbalanced or b.down else 0.0)
		for k in _allies(game,i):
			var al=game.state.fighters[k]
			if BloodRules.distance(al.cell,b.cell)==1:v+=_trouble(game,k)*7.0
		if v>best:best=v;out=j
	return out
static func _move_score(game: BloodRules,i: int,k: String,m: Dictionary) -> float:
	# valore di una cella di arrivo
	var p=game.state.fighters[i];var trouble=_trouble(game,i);var s=0.0
	var focus=_focus(game,i)
	var archer=game.definition(p).moves.has("shoot") and bool(p.get("bow",false))
	var mage=bool(game.definition(p).get("mage",false))
	if trouble>TROUBLE_RETREAT or archer or (mage and MAGES_KEEP_DISTANCE):
		# ritirata strategica (o tiratori e maghi che tengono le distanze): via dai nemici, dietro gli amici
		s+=-_threat_at(game,i,k)*2.0+_cover_at(game,i,k)*1.5
		if (archer or mage) and focus!=-1:
			var d=BloodRules.distance(k,game.state.fighters[focus].cell)
			s+=3.0 if d in [2,3,4] else (-2.0 if d<=1 else -float(d-4))
	elif focus!=-1:
		var b=game.state.fighters[focus];var d=BloodRules.distance(k,b.cell)
		s+=-float(d)*2.0
		if d==1:   # arrivare sul fianco o alle spalle del bersaglio
			var side=posmod(BloodRules.direction(b.cell,k)-int(b.facing),6)
			s+=float(POSITIONAL[side])*1.2
		s-=maxf(0.0,_threat_at(game,i,k)-4.0)*.6           # non infilarsi in mezzo a troppi nemici
	if not game.hazard(k).is_empty():s-=25.0
	if m.id=="charge":
		var front=game.at(BloodRules.neighbor(k,int(p.facing)))
		if front!=-1 and game.state.fighters[front].team!=p.team:
			s+=12.0+_expected_wounds(game,i,front,m,k)*2.0
		else:s-=15.0
	return s
static func _spell_cell(game: BloodRules,i: int,m: Dictionary,k: String) -> float:
	# valore di un incantesimo lanciato sulla cella k
	var p=game.state.fighters[i];var occ=game.at(k);var s=0.0
	var enemy=occ!=-1 and game.state.fighters[occ].team!=p.team
	var friend=occ!=-1 and not enemy
	match m.id:
		"fireball":
			for j in game.state.fighters.size():
				var t=game.state.fighters[j]
				if game.living(t) and BloodRules.distance(k,t.cell)<=1:s+=(6.0 if t.team!=p.team else -9.0)
		"lightning":
			s=4.0*(1.0 if enemy else 0.0)
			var here=p.cell
			for step in mini(7,BloodRules.distance(p.cell,k)):
				here=BloodRules.neighbor(here,BloodRules.direction(here,k));var o=game.at(here)
				if o!=-1:s+=(5.0 if game.state.fighters[o].team!=p.team else -8.0)
		"abyss":
			s=12.0 if enemy else -20.0 if friend else 0.0
			s+=_blocks_enemy(game,i,k)*3.0
		"vortex","wall":
			if friend:return -20.0
			s=(6.0 if enemy else 0.0)+_blocks_enemy(game,i,k)*4.0
		"livingfire":s=6.0 if enemy else 2.0
		"summon":s=_blocks_enemy(game,i,k)*3.0+4.0
		"teleport":
			s=-_threat_at(game,i,k)*2.0+_cover_at(game,i,k) if _trouble(game,i)>.4 else -float(BloodRules.distance(k,game.state.fighters[_focus(game,i)].cell)) if _focus(game,i)!=-1 else 0.0
		_:
			if enemy:
				var b=game.state.fighters[occ];s=8.0+(1.0-_health(b))*4.0
				if m.id in ["control","transform","sleep","age"]:s=6.0+_health(b)*6.0   # meglio sul nemico più in forma
				if m.id=="drain":s+=(1.0-_health(p))*6.0
			elif friend:s=-20.0
	return s
static func _blocks_enemy(game: BloodRules,i: int,k: String) -> float:
	# quanto la cella k sbarra la strada ai nemici verso un alleato in difficoltà (o verso di me)
	var v=0.0;var p=game.state.fighters[i]
	var protect=[i]+_allies(game,i)
	for j in _enemies(game,i):
		var e=game.state.fighters[j]
		for a in protect:
			var al=game.state.fighters[a];var w=.5+_trouble(game,a)
			var de=BloodRules.distance(e.cell,al.cell)
			if de<=4 and BloodRules.distance(e.cell,k)+BloodRules.distance(k,al.cell)<=de+1:v+=w
	return v

# ------------------------------------------------------------------ scelta della mossa segreta
static func choose_move(game: BloodRules,i: int,difficulty: int=1) -> String:
	var p=game.state.fighters[i];var legal=game.legal_moves(i)
	if legal.is_empty():return ""
	var trouble=_trouble(game,i)
	var adjacent=0;var nearest=99
	for j in _enemies(game,i):
		var d=BloodRules.distance(p.cell,game.state.fighters[j].cell);nearest=mini(nearest,d)
		if d==1:adjacent+=1
	var within2=0
	for j in _enemies(game,i):
		if BloodRules.distance(p.cell,game.state.fighters[j].cell)<=2:within2+=1
	var exposure=float(adjacent)*EXPOSE_ADJ+float(within2-adjacent)*EXPOSE_NEAR
	var here=_move_score(game,i,p.cell,{"id":"stay"})
	var best=-INF;var selected=str(legal[0])
	for id in legal:
		var m=game.move(p,id);var score=-2.0
		if id=="again":m=game.move(p)
		var targets=game.targets(i,m.id)
		if m.get("spell",false):
			if targets.is_empty():score=-30.0
			else:
				var top=-INF
				for k in targets:top=maxf(top,_spell_cell(game,i,m,k))
				score=top+2.0
				if m.id=="heal":score=16.0*(1.0-_health(p))-2.0
				if m.id=="shield":score=4.0+float(adjacent)*5.0+trouble*6.0
				if m.id in ["pustules","shock","fear"]:
					var hit=0.0
					for j in game.state.fighters.size():
						var t=game.state.fighters[j]
						if game.living(t) and j!=i and BloodRules.distance(p.cell,t.cell)<=int(m.get("range",1)):hit+=(5.0 if t.team!=p.team else -7.0)
					score=hit
		elif m.get("attack")!=null and m.id!="charge":
			if targets.is_empty():score=-20.0
			else:
				var top=-INF
				for k in targets:
					var j=game.at(k,i)
					if j==-1:continue
					top=maxf(top,_target_value(game,i,j,_expected_wounds(game,i,j,m,p.cell)))
				score=top-float(m.fatigue)*2.5+(float(m.imbalance)*.8 if m.get("imbalance")!=null else 0.0)
				score-=float(adjacent-1)*1.5*(1.0-float(m.get("defense",0))/6.0)   # attaccare in mezzo a tanti nemici espone
		elif id in ["advance","run","float","charge","dodge","roll","rise","concentrate","load","teleport"] and not targets.is_empty():
			var top=-INF
			for k in targets:top=maxf(top,_move_score(game,i,k,m))
			score=(top-here)*.8+2.0
			if id=="charge":score=top*CHARGE_W-(8.0 if adjacent>0 else 0.0)   # già in mischia: meglio colpire da fermi
			if id=="concentrate":score=(14.0 if p.magic<3 else 4.0)+(top-here)*.3-float(adjacent)*4.0
			if id=="load":score=(14.0 if not p.get("loaded",false) else -5.0)+(top-here)*.3-float(adjacent)*6.0
			if id=="rise":score=25.0
			if id in ["run","charge"]:score-=float(p.fatigue)*.6
			if id=="dodge" or id=="roll":score+=trouble*6.0*float(adjacent)
		if m.get("rest",false):score+=minf(10.0,float(p.fatigue)*2.0)*(1.0 if adjacent==0 else .3)
		if id=="guard":score=maxf(score,(5.0 if nearest<=2 else -1.0)+(2.0 if adjacent>0 else 0.0))
		if id.begins_with("parry"):score=float(adjacent)*3.5+trouble*4.0-6.0
		if id=="shoot":score=-20.0 if targets.is_empty() else 10.0+(16.0 if adjacent==0 else 0.0)
		if id=="weapon":score=18.0 if p.get("bow",false) and nearest<=WEAPON_RANGE else -10.0
		if id=="meditate":score=(8.0 if adjacent==0 else -6.0)+trouble*4.0
		# esposizione: la difesa della pedina scelta conta quando i nemici ci attaccano (valore alto = più ferite subite)
		if not id in ["run","charge","float","teleport","dematerialize"]:score-=float(m.get("defense",0))*exposure
		if id=="guard" and within2>0:   # in guardia si colpisce per primi chi si avvicina
			var gbest=0.0
			for j in _enemies(game,i):
				if BloodRules.distance(p.cell,game.state.fighters[j].cell)<=2:gbest=maxf(gbest,_target_value(game,i,j,_expected_wounds(game,i,j,m,p.cell)))
			score=maxf(score,gbest*.7+3.0)
		if difficulty==0:score+=sin(float(i*61+game.state.turn*13+id.hash()%97))*6
		if score>best:best=score;selected=id
	return selected

# ------------------------------------------------------------------ esecuzione della mossa
static func command(game: BloodRules,i: int) -> Dictionary:
	var p=game.state.fighters[i];var m=game.move(p);var targets=game.targets(i)
	# un mago che si concentra rigenera uno scheletro in pezzi, se ha abbastanza magia da rischiare il tiro
	if m.id=="concentrate" and int(p.magic)>=4:
		for j in game.state.fighters.size():
			var sk=game.state.fighters[j]
			if sk.alive and sk.get("pieces",false):return {"type":"regenerate","fighter":j}
	var best=-INF;var selected=p.cell;var facing=int(p.facing)
	for k in targets:
		var score=0.0;var occupant=game.at(k,i)
		if m.get("spell",false):score=_spell_cell(game,i,m,k)
		elif m.get("attack")!=null and m.id!="charge" and occupant!=-1:
			score=_target_value(game,i,occupant,_expected_wounds(game,i,occupant,m,p.cell))
		else:score=_move_score(game,i,k,m)
		if score>best:best=score;selected=k
	var focus=_focus(game,i)
	if focus!=-1:
		var look=game.state.fighters[focus].cell
		var desired=BloodRules.direction(p.cell if m.get("attack")!=null else selected,look)
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
