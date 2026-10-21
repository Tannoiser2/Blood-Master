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
static var BACK_W=.8

# ------------------------------------------------------------------ valutazioni di base
static func _team(game: BloodRules,i: int) -> int:
	# chi è sotto controllo mentale agisce per la squadra del mago che lo controlla
	var p=game.state.fighters[i];var c=int(p.get("controller_by",-1))
	return int(game.state.fighters[c].team) if c>=0 else int(p.team)
static func _enemies(game: BloodRules,i: int) -> Array:
	var team=_team(game,i);var out=[]
	for j in game.state.fighters.size():
		var b=game.state.fighters[j]
		if j!=i and game.living(b) and not b.get("pieces",false) and int(b.team)!=team and b.cell!="":out.append(j)
	return out
static func _allies(game: BloodRules,i: int) -> Array:
	var team=_team(game,i);var out=[]
	for j in game.state.fighters.size():
		var b=game.state.fighters[j]
		if j!=i and game.living(b) and not b.get("pieces",false) and int(b.team)==team and b.cell!="":out.append(j)
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
static func _back_risk(game: BloodRules,i: int,k: String,facing: int) -> float:
	# quanto rischio di essere colpito sul fianco o alle spalle stando in k girato verso "facing"
	var r=0.0
	for j in _enemies(game,i):
		var e=game.state.fighters[j]
		if BloodRules.distance(k,e.cell)!=1:continue
		var side=posmod(BloodRules.direction(k,e.cell)-facing,6)
		r+=float(POSITIONAL[side])*(.5+_health(e))
	return r
static func _best_facing(game: BloodRules,i: int,k: String,fallback: int) -> int:
	# verso dove guardare in k: il nemico adiacente più pericoloso, altrimenti il bersaglio
	var best=-1.0;var f=fallback
	for j in _enemies(game,i):
		var e=game.state.fighters[j]
		if BloodRules.distance(k,e.cell)==1:
			var w=_health(e)+(float(game.move(e).get("attack",0) if game.move(e).get("attack")!=null else 0)/10.0)
			if w>best:best=w;f=BloodRules.direction(k,e.cell)
	return f
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
	if focus!=-1 and k!=p.cell:
		var face=BloodRules.direction(k,game.state.fighters[focus].cell)
		s-=_back_risk(game,i,k,face)*BACK_W
	if not game.hazard(k).is_empty():s-=25.0
	if m.id=="charge":
		var front=game.at(BloodRules.neighbor(k,int(p.facing)))
		if front!=-1 and game.state.fighters[front].team!=_team(game,i):
			s+=12.0+_expected_wounds(game,i,front,m,k)*2.0
		else:s-=15.0
	return s
static func _spell_cell(game: BloodRules,i: int,m: Dictionary,k: String) -> float:
	# valore di un incantesimo lanciato sulla cella k
	var p=game.state.fighters[i];var occ=game.at(k);var s=0.0
	var enemy=occ!=-1 and game.state.fighters[occ].team!=_team(game,i)
	var friend=occ!=-1 and not enemy
	match m.id:
		"fireball":
			for j in game.state.fighters.size():
				var t=game.state.fighters[j]
				if game.living(t) and BloodRules.distance(k,t.cell)<=1:s+=(6.0 if t.team!=_team(game,i) else -9.0)
		"lightning":
			s=4.0*(1.0 if enemy else 0.0)
			var here=p.cell
			for step in mini(7,BloodRules.distance(p.cell,k)):
				here=BloodRules.neighbor(here,BloodRules.direction(here,k));var o=game.at(here)
				if o!=-1:s+=(5.0 if game.state.fighters[o].team!=_team(game,i) else -8.0)
		"abyss":
			s=12.0 if enemy else -20.0 if friend else 0.0
			s+=_blocks_enemy(game,i,k)*3.0
		"wall":
			if friend:return -20.0
			s=(6.0 if enemy else 0.0)+minf(_blocks_enemy(game,i,k),2.5)*3.0
		"vortex":   # il gorgo poi si sposta di 1-6 esagoni a ogni fine turno travolgendo chi incontra
			s=3.0+minf(_blocks_enemy(game,i,k),2.0)*2.0
			for j in _enemies(game,i):
				var d=BloodRules.distance(k,game.state.fighters[j].cell)
				if d<=5:s+=4.0/float(maxi(1,d))
			for j in _allies(game,i):
				if BloodRules.distance(k,game.state.fighters[j].cell)<=1:s-=4.0
		"livingfire":   # il fuoco vivente si muove ogni turno: vale per i nemici che ha intorno
			s=7.0
			for j in _enemies(game,i):
				var d=BloodRules.distance(k,game.state.fighters[j].cell)
				if d<=5:s+=6.0/float(maxi(1,d))
			for j in _allies(game,i):
				if BloodRules.distance(k,game.state.fighters[j].cell)<=1:s-=4.0
		"summon":   # il Golem compare vicino ai nemici, meglio se a contatto
			var nd=99
			for j in _enemies(game,i):nd=mini(nd,BloodRules.distance(k,game.state.fighters[j].cell))
			s=14.0-float(nd)*2.5+_blocks_enemy(game,i,k)*2.0
		"teleport":   # via di fuga quando si è in difficoltà e circondati
			var adj=0
			for j in _enemies(game,i):
				if BloodRules.distance(p.cell,game.state.fighters[j].cell)==1:adj+=1
			if _trouble(game,i)>.35 and adj>0:s=8.0+_trouble(game,i)*10.0+float(adj)*3.0-_threat_at(game,i,k)*2.0+_cover_at(game,i,k)-float(BloodRules.distance(p.cell,k))*.3
			else:s=-10.0
		_:
			if enemy:
				var b=game.state.fighters[occ];s=8.0+(1.0-_health(b))*4.0
				if m.id in ["transform","age"]:s=(14.0 if m.id=="transform" else 7.0)+_health(b)*7.0   # meglio sul nemico più in forma
				if m.id=="plague":s=12.0+_health(b)*6.0
				if m.id=="sleep":   # 3 dadi meno la stazza diventano fatica; a 9 o più crolla a terra
					var size=float(game.definition(b).get("size",5));s=6.0+maxf(0.0,10.5-size)*1.2+float(b.fatigue)*.6+_health(b)*3.0
				if m.id=="control":   # riesce se il dado è <= punti giocati (fino a 4): rende se il controllato ha amici accanto da colpire
					var chance=float(mini(4,int(p.magic)))/6.0;var mates=0
					for t in game.state.fighters.size():
						var q=game.state.fighters[t]
						if t!=occ and game.living(q) and int(q.team)==int(b.team) and BloodRules.distance(q.cell,b.cell)==1:mates+=1
					s=chance*(12.0+float(mates)*8.0+_health(b)*4.0)
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
	if p.character=="golem" and legal.has("guard") and legal.has("advance"):   # il Golem può solo avanzare o colpire
		if not game.targets(i,"guard").is_empty() or adjacent>0:return "guard"
		for k in game.targets(i,"advance"):
			for j in _enemies(game,i):
				if BloodRules.distance(k,game.state.fighters[j].cell)<nearest:return "advance"
		return "guard"
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
				score=top+2.0-float(m.cost)*.5   # la magia costa: le più care devono valere di più
				if m.id=="heal":score=16.0*(1.0-_health(p))-2.0
				if m.id=="summon" and game.own_golem(i)>=0:   # senza Evocazione il Golem si sbriciola: conviene se sta combattendo
					var g=game.state.fighters[game.own_golem(i)];var gd=99
					for j in _enemies(game,i):gd=mini(gd,BloodRules.distance(g.cell,game.state.fighters[j].cell))
					score=22.0+(8.0 if gd==1 else (5.0 if gd<=2 else 1.0))+_health(g)*4.0-trouble*6.0   # 40 ferite gratis: tenerlo vale quasi sempre
				if m.id=="shield":score=1.0+float(adjacent)*3.0+trouble*5.0
				if m.id in ["pustules","shock"]:
					var hit=0.0
					for j in game.state.fighters.size():
						var t=game.state.fighters[j]
						if game.living(t) and j!=i and BloodRules.distance(p.cell,t.cell)<=(2 if m.id=="pustules" else 1):hit+=(5.0 if int(t.team)!=_team(game,i) else -7.0)
					score=hit
				if m.id=="fear":   # gli avversari che lo vedono entro 5 perdono la mossa, quelli accanto vanno sbilanciati
					var hit=0.0
					for j in _enemies(game,i):
						var t=game.state.fighters[j];var d=BloodRules.distance(p.cell,t.cell)
						if d<=5 and game.in_view(t,p.cell):hit+=4.0
						if d==1:hit+=3.0
					score=hit-2.0
		elif m.get("attack")!=null and m.id!="charge":
			if targets.is_empty():score=-20.0
			else:
				var top=-INF;var vals=[]
				for k in targets:
					var j=game.at(k,i)
					if j==-1:continue
					var tv=_target_value(game,i,j,_expected_wounds(game,i,j,m,p.cell));vals.append(tv);top=maxf(top,tv)
				if m.id=="spin" and vals.size()>1:   # la rotazione colpisce tutti gli adiacenti (con -2 per ogni colpo successivo)
					vals.sort();vals.reverse();top=0.0
					for n in vals.size():top+=maxf(0.0,vals[n]-float(n)*4.0)
				score=top-float(m.fatigue)*2.5+(float(m.imbalance)*.8 if m.get("imbalance")!=null else 0.0)
				score-=float(adjacent-1)*1.5*(1.0-float(m.get("defense",0))/6.0)   # attaccare in mezzo a tanti nemici espone
		elif id in ["advance","run","float","charge","dodge","roll","rise","concentrate","load","teleport"] and not targets.is_empty():
			var top=-INF
			for k in targets:top=maxf(top,_move_score(game,i,k,m))
			score=(top-here)*.8+2.0
			if id=="charge":score=top*CHARGE_W-(8.0 if adjacent>0 else 0.0)   # già in mischia: meglio colpire da fermi
			if id=="concentrate":
				score=(14.0 if p.magic<3 else 4.0)+(top-here)*.3-float(adjacent)*4.0
				for sk in game.state.fighters:   # uno scheletro in pezzi da rigenerare (amico o nemico): ne vale la pena
					if sk.alive and sk.get("pieces",false) and int(p.magic)>=2:score+=22.0;break
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
		if id=="again":   # "Ancora" mantiene in gioco gorgo e fuoco vivente: valgono quanto i nemici che hanno intorno
			for e in game.state.effects:
				if int(e.owner)==i and str(e.kind) in ["vortex","livingfire"]:
					var ev=3.0
					for j in _enemies(game,i):
						var d=BloodRules.distance(str(e.cell),game.state.fighters[j].cell)
						if d<=5:ev+=5.0/float(maxi(1,d))
					score+=ev
		if not id in ["run","charge","float","teleport","dematerialize"]:score-=float(m.get("defense",0))*exposure
		if id=="guard" and within2>0:   # in guardia si colpisce per primi chi si avvicina
			var gbest=0.0
			for j in _enemies(game,i):
				if BloodRules.distance(p.cell,game.state.fighters[j].cell)<=2:gbest=maxf(gbest,_target_value(game,i,j,_expected_wounds(game,i,j,m,p.cell)))
			score=maxf(score,gbest*.7+3.0)
		if id=="guard" and adjacent>0:
			var now_risk=_back_risk(game,i,p.cell,int(p.facing));var turned=_back_risk(game,i,p.cell,_best_facing(game,i,p.cell,int(p.facing)))
			score+=(now_risk-turned)*BACK_W*.8
		if difficulty==0:score+=sin(float(i*61+game.state.turn*13+id.hash()%97))*6
		if score>best:best=score;selected=id
	return selected

# ------------------------------------------------------------------ esecuzione della mossa
static func command(game: BloodRules,i: int) -> Dictionary:
	var p=game.state.fighters[i];var m=game.move(p);var targets=game.targets(i)
	# un mago che si concentra rigenera uno scheletro in pezzi, se ha abbastanza magia da rischiare il tiro
	if m.id=="concentrate" and int(p.magic)>=2:
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
		if m.id=="guard" and targets.is_empty():desired=_best_facing(game,i,p.cell,desired)
		if m.id in ["rise","meditate","teleport","float"] or (m.id=="guard" and targets.is_empty()):facing=desired
		elif desired!=facing:facing=posmod(facing+(1 if posmod(desired-facing,6)<=3 else -1),6)
	if m.id.begins_with("parry") or m.id in ["dematerialize","weapon","roll"]:facing=int(p.facing)
	if targets.is_empty():
		if m.id=="guard":return {"wait":true,"facing":facing}
		return {"pass":true,"facing":int(p.facing)}
	var extra=0   # punti magia in più: il controllo riesce col dado <= punti giocati, palla di fuoco e fulmine colpiscono più forte
	if m.id=="control":extra=clampi(int(p.magic)-int(m.cost),0,3)
	elif m.id in ["fireball","lightning"]:extra=clampi(int(p.magic)-int(m.cost)-3,0,3)
	return {"target":selected,"facing":facing,"extra":extra}

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

# ------------------------------------------------------------------ gorgo e fuoco vivente
# A fine turno il mago sposta il suo effetto (gorgo o fuoco vivente) di 1-6 esagoni nella direzione scelta:
# si sceglie quella che in media travolge più nemici e meno amici, altrimenti verso il nemico più vicino.
static func effect_facing(game: BloodRules) -> int:
	var e=game.state.effects[game.state.upkeep[0]];var owner=int(e.owner);var team=_team(game,owner)
	var best=-INF;var choice=int(game.state.fighters[owner].facing)
	for f in 6:
		var score=0.0;var cell=str(e.cell);var path=[]
		for step in 6:
			var nxt=BloodRules.neighbor(cell,f)
			if not game.cells.has(nxt):break
			cell=nxt;path.append(cell)
		if path.is_empty():continue
		for roll in range(1,7):   # media sui sei risultati del dado
			var v=0.0
			for k in mini(roll,path.size()):
				var o=game.at(path[k])
				if o==-1:continue
				var enemy=int(game.state.fighters[o].team)!=team
				v+=(3.0 if enemy else -4.0)
			var end=path[mini(roll,path.size())-1]
			for j in _enemies(game,owner):   # dove si ferma conta: il turno dopo minaccia chi gli sta accanto
				var d=BloodRules.distance(end,game.state.fighters[j].cell)
				if d<=2:v+=1.0/float(d+1)
			score+=v/6.0
		var near=99
		for j in _enemies(game,owner):near=mini(near,BloodRules.distance(path.back(),game.state.fighters[j].cell))
		score-=float(near)*.05
		if score>best:best=score;choice=f
	return choice
