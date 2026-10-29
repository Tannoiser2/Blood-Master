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
# aspettare in guardia: nelle partite simulate solo una guardia su dieci arriva davvero a colpire,
# perché nessuno si infila davanti a chi è in guardia. Vale poco: meglio muoversi e aggirare
static var GUARD_WAIT=float(OS.get_environment("BM_GW")) if OS.get_environment("BM_GW")!="" else 2.0
static var GUARD_GAIN=float(OS.get_environment("BM_GG")) if OS.get_environment("BM_GG")!="" else .3

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
	if _guessing and not b.get("shield",false) and not b.done:
		# in pianificazione la pedina del nemico è segreta: non quella del turno prima, ma la media di quelle che può scegliere
		var sum=0.0;var pos=0.0;var n=0
		for id in game.definition(b).moves:
			if id in b.lost or id in ["unbalanced","down","pieces","again"]:continue
			if (id in ["rise","roll"])!=bool(b.down):continue
			var mm=game.definition(b).moves[id];var dd=int(mm.get("defense",0))
			if not mm.get("blue",[]).is_empty() and not side in mm.blue:dd=int(mm.get("secondary",dd))
			sum+=float(dd);pos+=float(POSITIONAL[side] if not side in mm.get("red",[]) else 0);n+=1
		if n>0:dv=roundi(sum/n);positional=roundi(pos/n)
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
		var b=game.state.fighters[j];var d=float(game.walk_distance(p.cell,b.cell))   # a piedi, aggirando la scenografia
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
	if game.pickup(k)!="" and p.character!="golem":   # zona di ristoro: vale quanto le ferite e la fatica da recuperare
		s+=minf(float(p.max_hp-p.hp),3.5)*2.2+float(p.fatigue)*1.5+(trouble*6.0)
	var archer=game.definition(p).moves.has("shoot") and bool(p.get("bow",false))
	var mage=bool(game.definition(p).get("mage",false))
	if trouble>TROUBLE_RETREAT or archer or (mage and MAGES_KEEP_DISTANCE):
		# ritirata strategica (o tiratori e maghi che tengono le distanze): via dai nemici, dietro gli amici
		s+=-_threat_at(game,i,k)*2.0+_cover_at(game,i,k)*1.5
		if (archer or mage) and focus!=-1:
			var d=BloodRules.distance(k,game.state.fighters[focus].cell)
			s+=3.0 if d in [2,3,4] else (-2.0 if d<=1 else -float(d-4))
	elif focus!=-1:
		var b=game.state.fighters[focus];var d=game.walk_distance(k,b.cell)   # a piedi: niente stalli dietro colonne e massi
		s+=-float(d)*2.0
		if d==1:   # arrivare sul fianco o alle spalle del bersaglio
			var side=posmod(BloodRules.direction(b.cell,k)-int(b.facing),6)
			s+=float(POSITIONAL[side])*2.5   # aggirare: fianchi (+3) e spalle (+5) sono dove si fanno le ferite
		s-=maxf(0.0,_threat_at(game,i,k)-4.0)*.6           # non infilarsi in mezzo a troppi nemici
	if focus!=-1 and k!=p.cell:
		var face=BloodRules.direction(k,game.state.fighters[focus].cell)
		s-=_back_risk(game,i,k,face)*BACK_W
	if not game.hazard(k).is_empty():s-=25.0
	if game.hr("zoc") and k!=p.cell:   # ZOC: sganciarsi da chi può ancora colpire costa un colpo
		for j in _enemies(game,i):
			var e=game.state.fighters[j]
			if e.done or e.down or e.unbalanced or BloodRules.distance(e.cell,p.cell)!=1 or BloodRules.distance(e.cell,k)==1:continue
			var em=game.move(e)
			if em.get("attack")==null or em.get("spell",false) or e.get("bow",false):continue
			if posmod(BloodRules.direction(e.cell,p.cell)-int(e.facing),6) in em.red:s-=4.0+float(em.attack)*.5
	if m.id in ["run","charge"] and k!=p.cell:
		# sprint: più esagoni, più rischio di cadere (e un turno perso per rialzarsi)
		var sp: Array=game.definition(p).get("sprints",[]);var steps=BloodRules.distance(p.cell,k)
		if steps>0 and steps<=sp.size():s-=float(sp[steps-1][2])/6.0*7.0+float(sp[steps-1][1])*.5
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
		"lightning":   # potentissimo: colpisce tutti quelli sulla linea
			s=8.0*(1.0 if enemy else 0.0)
			var here=p.cell
			for step in mini(7,BloodRules.distance(p.cell,k)):
				here=BloodRules.neighbor(here,BloodRules.direction(here,k));var o=game.at(here)
				if o!=-1:s+=(9.0 if game.state.fighters[o].team!=_team(game,i) else -10.0)
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
static var _dbg_scores={}
static var _guessing=false   # vero mentre si sceglie la pedina segreta: le pedine dei nemici non si conoscono
static func choose_move(game: BloodRules,i: int,difficulty: int=1) -> String:
	_guessing=true
	var r=_choose_move(game,i,difficulty)
	_guessing=false
	return r
static func _choose_move(game: BloodRules,i: int,difficulty: int=1) -> String:
	var p=game.state.fighters[i];var legal=game.legal_moves(i)
	if legal.is_empty():return ""
	var trouble=_trouble(game,i)
	var adjacent=0;var nearest=99
	for j in _enemies(game,i):
		var d=game.walk_distance(p.cell,game.state.fighters[j].cell);nearest=mini(nearest,d)   # a piedi: una colonna in mezzo allontana
		if d==1:adjacent+=1
	var within2=0
	for j in _enemies(game,i):
		if game.walk_distance(p.cell,game.state.fighters[j].cell)<=2:within2+=1
	var exposure=float(adjacent)*EXPOSE_ADJ+float(within2-adjacent)*EXPOSE_NEAR
	# chi ha tante ferite (Nuchra 38, Ut 38) può esporsi: la difesa della pedina pesa meno; un arciere da 14 resta prudente
	exposure*=clampf(22.0/maxf(float(p.max_hp),1.0),.5,1.2)
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
				if m.id=="summon" and game.own_golem(i)>=0 and game.hr("golem"):score=-5.0   # resta in campo da solo
				elif m.id=="summon" and game.own_golem(i)>=0:   # senza Evocazione il Golem si sbriciola: conviene se sta combattendo
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
			var sp=_step_plan(game,i,m) if not m.get("green",[]).is_empty() else [0.0,"",false]
			if targets.is_empty() and str(sp[1])!="" and not bool(sp[2]):score=float(sp[0])*.9-float(m.fatigue)*2.5   # un passo e poi il colpo
			elif targets.is_empty():score=-20.0
			else:
				var top=-INF;var vals=[]
				for k in targets:
					var j=game.at(k,i)
					if j==-1:continue
					var tv=_target_value(game,i,j,_expected_wounds(game,i,j,m,p.cell));vals.append(tv);top=maxf(top,tv)
				if m.get("double",false):top*=1.7          # doppio colpo: la seconda arma colpisce ancora
				if m.get("feint",false):top+=2.0           # finta: niente parata
				if (m.id=="spin" or m.get("multi",false)) and vals.size()>1:   # la rotazione colpisce tutti gli adiacenti (con -2 per ogni colpo successivo)
					vals.sort();vals.reverse();top=0.0
					for n in vals.size():top+=maxf(0.0,vals[n]-float(n)*4.0)
				score=top-float(m.fatigue)*2.5+(float(m.imbalance)*.8 if m.get("imbalance")!=null else 0.0)
				score-=float(adjacent-1)*1.5*(1.0-float(m.get("defense",0))/6.0)   # attaccare in mezzo a tanti nemici espone
				if str(sp[1])!="":score+=maxf(0.0,float(sp[0]))*.5   # il passo (prima o dopo) migliora il colpo o la posizione
		elif id in ["advance","run","float","charge","dodge","roll","rise","concentrate","load","teleport"] and not targets.is_empty():
			var top=-INF
			for k in targets:top=maxf(top,_move_score(game,i,k,m))
			score=(top-here)*.8+2.0
			if id=="charge":score=top*CHARGE_W-(8.0 if adjacent>0 else 0.0)   # già in mischia: meglio colpire da fermi
			if id=="concentrate":
				score=(14.0 if p.magic<3 else 4.0)+(top-here)*.3-float(adjacent)*4.0
				for sk in game.state.fighters:   # uno scheletro in pezzi da rigenerare (amico o nemico): ne vale la pena
					if sk.alive and sk.get("pieces",false) and int(p.magic)>=2:score+=22.0;break
			if id=="load":
				score=(14.0 if not p.get("loaded",false) else -5.0)+(top-here)*.3-float(adjacent)*6.0
				# già incoccata ma nessuno nel campo visivo: rimirare (un passo e un lato) tiene la freccia invece di perderla
				if p.get("loaded",false) and game.targets(i,"shoot").is_empty() and _best_aim(game,i)[0]>0.0:score=12.0-float(adjacent)*6.0
			if id=="rise":score=25.0
			if id in ["run","charge"]:score-=float(p.fatigue)*.6
			if id=="dodge" or id=="roll":score+=trouble*6.0*float(adjacent)
		if m.get("rest",false):score+=minf(10.0,float(p.fatigue)*2.0)*(1.0 if adjacent==0 else .3)
		var waiting=id=="guard" and targets.is_empty()   # in guardia senza nessuno davanti: si aspetta che qualcuno arrivi
		if id=="guard":score=maxf(score,(GUARD_WAIT if nearest<=2 else -1.0)+(2.0 if adjacent>0 else 0.0))
		if id.begins_with("parry"):score=float(adjacent)*3.5+trouble*4.0-6.0+(float(adjacent)*2.0 if int(m.get("riposte",0))>0 else 0.0)   # il contrattacco vale di più in mischia
		if id=="shoot":   # tiro: 15 meno la distanza, fortissimo anche a bruciapelo; la freccia incoccata non va sprecata
			if targets.is_empty():score=-20.0
			else:
				var top=0.0
				for k in targets:
					var o=game.at(k,i)
					if o!=-1:top=maxf(top,_target_value(game,i,o,_expected_wounds(game,i,o,m,p.cell)))
				score=top+18.0+(6.0 if adjacent==0 else 0.0)
		if id=="weapon":score=18.0 if p.get("bow",false) and (nearest<=WEAPON_RANGE or int(p.get("arrows",-1))==0) else -10.0   # senza frecce si riprende la spada
		if id=="meditate":score=(8.0 if adjacent==0 and nearest<=3 else (1.0 if adjacent==0 else -6.0))+trouble*4.0   # medita se poi potrà colpire
		# esposizione: la difesa della pedina scelta conta quando i nemici ci attaccano (valore alto = più ferite subite)
		if id=="again":   # "Ancora" mantiene in gioco gorgo e fuoco vivente: valgono quanto i nemici che hanno intorno
			for e in game.state.effects:
				if int(e.owner)==i and str(e.kind) in ["vortex","livingfire"]:
					var ev=3.0
					for j in _enemies(game,i):
						var d=BloodRules.distance(str(e.cell),game.state.fighters[j].cell)
						if d<=5:ev+=5.0/float(maxi(1,d))
					score+=ev
		if m.id=="dematerialize":   # intoccabile per un turno ma non fa nulla: solo per sfuggire a una mischia pericolosa, mai di fila
			score=(3.0+trouble*10.0+float(adjacent)*2.0 if adjacent>0 else -6.0)-(8.0 if p.previous=="dematerialize" or p.current=="dematerialize" else 0.0)
		if not m.id in ["run","charge","float","teleport","dematerialize"]:score-=float(m.get("defense",0))*exposure
		if id=="guard" and within2>0:   # in guardia si colpisce per primi chi si avvicina
			var gbest=0.0
			for j in _enemies(game,i):
				if game.walk_distance(p.cell,game.state.fighters[j].cell)<=2:gbest=maxf(gbest,_target_value(game,i,j,_expected_wounds(game,i,j,m,p.cell)))
			score=maxf(score,gbest*(GUARD_GAIN if waiting else .7)+3.0)
		if id=="guard" and adjacent>0:
			var now_risk=_back_risk(game,i,p.cell,int(p.facing));var turned=_back_risk(game,i,p.cell,_best_facing(game,i,p.cell,int(p.facing)))
			score+=(now_risk-turned)*BACK_W*.8
		if difficulty==0:score+=sin(float(i*61+game.state.turn*13+id.hash()%97))*6
		if OS.get_environment("BM_AIDBG")==str(p.character):_dbg_scores[id]=snappedf(score,.1)
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
		if m.id in ["advance","run"] and m.get("attack")==null:
			# la pedina di movimento non va sprecata: a parità di valore ci si sposta, verso il nemico più vicino a piedi
			var near=99
			for j in _enemies(game,i):near=mini(near,game.walk_distance(k,game.state.fighters[j].cell))
			score-=float(near)*.05+(.6 if k==p.cell else 0.0)
			if p.character=="golem":score=-float(near)*3.0   # il Golem va dritto addosso al nemico più vicino
		if score>best:best=score;selected=k
	if m.id=="load":   # arciere: si mette dove e come potrà tirare al turno dopo
		var aim=_best_aim(game,i)
		if aim[0]>0.0:return {"target":aim[1],"facing":aim[2]}
	var focus=_focus(game,i)
	if focus!=-1:
		var look=game.state.fighters[focus].cell
		var desired=BloodRules.direction(p.cell if m.get("attack")!=null else selected,look)
		if m.id=="guard" and targets.is_empty():desired=_best_facing(game,i,p.cell,desired)
		if m.id in ["rise","meditate","teleport","float"] or (m.id=="guard" and targets.is_empty()):facing=desired
		elif desired!=facing:facing=posmod(facing+(1 if posmod(desired-facing,6)<=3 else -1),6)
	# chi è attaccato di lato o alle spalle si gira verso la minaccia: tra i fronti consentiti, quello che
	# lascia meno scoperti fianchi e schiena; a parità resta il fronte verso il bersaglio
	if not m.id in ["dematerialize","weapon","roll","charge"] and not m.id.begins_with("parry"):
		var endc=selected if m.id in ["advance","run","float","dodge","roll","rise","concentrate","load","teleport"] else p.cell
		var rot=game.max_rotation(i,m.id=="guard" and targets.is_empty())
		var keep=_back_risk(game,i,endc,facing);var bf=facing
		for d in range(-rot,rot+1):
			var f=posmod(int(p.facing)+d,6);var r=_back_risk(game,i,endc,f)
			if r<keep-2.0:keep=r;bf=f
		facing=bf
	if m.id in ["dematerialize","weapon","roll","charge"]:facing=int(p.facing)   # la carica non ruota: colpisce davanti
	if m.id.begins_with("parry"):facing=_parry_facing(game,i,m)   # gira il lato blu verso chi minaccia
	var plan=_step_plan(game,i,m) if not m.id=="guard" else [0.0,"",false]
	if str(plan[1])!="":
		if m.get("attack")==null:return {"pass":true,"facing":facing,"step":plan[1]}
		if bool(plan[2]) and not targets.is_empty():return {"target":selected,"facing":facing,"step":plan[1],"step_after":true}
		if not bool(plan[2]):
			var tgt=_attack_from(game,i,m,str(plan[1]))
			if str(tgt[1])!="":return {"target":tgt[1],"facing":int(p.facing),"step":plan[1]}
	if targets.is_empty():
		if m.id=="guard":return {"wait":true,"facing":facing}
		return {"pass":true,"facing":int(p.facing)}
	var extra=0   # punti magia in più: il controllo riesce col dado <= punti giocati, palla di fuoco e fulmine colpiscono più forte
	if m.id=="control":extra=clampi(int(p.magic)-int(m.cost),0,3)
	elif m.id in ["fireball","lightning"]:extra=clampi(int(p.magic)-int(m.cost)-3,0,3)
	return {"target":selected,"facing":facing,"extra":extra}

# --- passo prima o dopo l'azione (pedine d'attacco o di parata con lati verdi, eroi della forgia) ---
static func _step_options(game: BloodRules,i: int,m: Dictionary) -> Array:
	var p=game.state.fighters[i];var out=[]
	if m.is_empty() or m.id in BloodRules.MOVE_IDS or m.get("green",[]).is_empty() or p.down or m.get("spell",false):return out
	for g in m.green:
		var k=BloodRules.neighbor(p.cell,int(p.facing)+int(g))
		if game.cells.has(k) and not game.blocked(k,i):out.append(k)
	return out
static func _attack_from(game: BloodRules,i: int,m: Dictionary,c: String) -> Array:
	# [valore del colpo migliore, cella del bersaglio] stando in c
	var p=game.state.fighters[i];var keep=str(p.cell);p.cell=c
	var best=[0.0,""]
	for k in game.targets(i,m.id):
		var j=game.at(k,i)
		if j==-1 or int(game.state.fighters[j].team)==_team(game,i):continue
		var v=_target_value(game,i,j,_expected_wounds(game,i,j,m,c))
		if v>best[0]:best=[v,k]
	p.cell=keep
	return best
static func _step_plan(game: BloodRules,i: int,m: Dictionary) -> Array:
	# [guadagno, cella, dopo?]: passo che porta a un colpo migliore (prima) o via da una posizione cattiva (dopo)
	var opts=_step_options(game,i,m)
	if opts.is_empty():return [0.0,"",false]
	var p=game.state.fighters[i];var atk=m.get("attack")!=null
	var here_atk=_attack_from(game,i,m,p.cell)[0] if atk else 0.0
	var here=_move_score(game,i,p.cell,{"id":"stay"})
	var best=[0.0,"",false]
	for c in opts:
		var ms=_move_score(game,i,c,{"id":"stay"})-here
		var before=(_attack_from(game,i,m,c)[0]-here_atk+ms*.3) if atk else ms*.6
		if before>best[0]+.5:best=[before,c,false]
		if atk and here_atk>0.0 and ms*.5>best[0]+.5:best=[ms*.5,c,true]
	return best
# parata: tra il fronte attuale e un lato in più a destra o a sinistra, quello che mette sotto i lati blu
# i nemici adiacenti più pericolosi e non lascia scoperti fianchi e spalle
static func _parry_facing(game: BloodRules,i: int,m: Dictionary) -> int:
	var p=game.state.fighters[i];var best=int(p.facing);var best_s=-INF
	for f in [int(p.facing),posmod(int(p.facing)+1,6),posmod(int(p.facing)-1,6)]:
		var s=(.2 if f==int(p.facing) else 0.0)
		for j in _enemies(game,i):
			var e=game.state.fighters[j]
			if BloodRules.distance(p.cell,e.cell)!=1 or e.down:continue
			var w=1.0+(float(game.move(e).get("attack",0)) if game.move(e).get("attack")!=null else 0.0)*.15
			var side=posmod(BloodRules.direction(p.cell,e.cell)-f,6)
			if side in m.blue:s+=3.0*w
			elif side in [2,3,4]:s-=2.0*w   # fianco o spalle verso un nemico
		if s>best_s:best_s=s;best=f
	return best
# miglior tiro possibile dopo Incoccare: [valore, cella, fronte] tra le celle raggiungibili e i fronti consentiti
static func _best_aim(game: BloodRules,i: int) -> Array:
	var p=game.state.fighters[i];var keep_c=str(p.cell);var keep_f=int(p.facing)
	var shoot=game.definition(p).moves.get("shoot",{})
	if shoot.is_empty():return [0.0,keep_c,keep_f]
	var best=[0.0,keep_c,keep_f];var rot=1   # Incoccare: un passo in qualunque direzione e un lato di rotazione
	var cells=game.targets(i,"load")
	if not keep_c in cells:cells.append(keep_c)
	for c in cells:
		for d in range(-rot,rot+1):
			var f=posmod(keep_f+d,6);p.cell=c;p.facing=f
			for j in _enemies(game,i):
				var e=game.state.fighters[j]
				if not game.living(e) or not game.in_view(p,e.cell) or not game.clear_shot(c,e.cell):continue
				var v=_target_value(game,i,j,_expected_wounds(game,i,j,shoot,c))-float(BloodRules.distance(c,keep_c))*.3
				if v>best[0]:best=[v,c,f]
	p.cell=keep_c;p.facing=keep_f
	return best
static func reaction(game: BloodRules,i: int) -> String:
	# Reagire con una parata costa la mossa preparata: conviene solo se le ferite evitate valgono più di
	# quello che si perde (un attacco pronto, una guardia, un'azione utile). Se il colpo può uccidere, si para.
	var s=game.state.pending;var v=int(game.move(game.state.fighters[s.actor]).get("value",0)) if s.kind=="spell" else 0
	var opts=game.reaction_options(i,v)
	if "counter" in opts:return "counter"
	if opts.size()<=1:return "pass"
	var p=game.state.fighters[i];var a=int(s.actor);var attacker=game.state.fighters[a];var m_att=game.move(attacker)
	var keep_cur=str(p.current);var keep_face=int(p.facing)
	var now_w=_expected_wounds(game,a,i,m_att,attacker.cell)
	var best="pass";var best_w=now_w
	for id in opts:
		if id=="pass":continue
		p.current=id
		var blue: Array=game.move(p).get("blue",[])
		var side=posmod(BloodRules.direction(p.cell,attacker.cell)-keep_face,6)
		if id.begins_with("parry") and not side in blue:   # come nelle regole: si gira di un lato verso il lato blu
			for d in [1,-1]:
				if posmod(side-d,6) in blue:p.facing=posmod(keep_face+d,6);break
		var w=_expected_wounds(game,a,i,m_att,attacker.cell)+(1.0 if id=="dematerialize" else 0.0)
		p.facing=keep_face
		if w<best_w:best_w=w;best=id
	p.current=keep_cur
	if best=="pass":return "pass"
	if now_w>=float(p.hp) and best_w<float(p.hp):return best     # altrimenti muore: si para
	# quanto vale la mossa che si perderebbe
	var mine=game.move(p);var keep=1.5
	if mine.get("attack")!=null and mine.id!="guard":keep=4.0+(4.0 if not game.targets(i).is_empty() else 0.0)
	elif mine.id=="guard":keep=3.0+(3.0 if not game.targets(i).is_empty() else 0.0)
	elif mine.get("spell",false):keep=5.0
	elif mine.id in ["load","shoot"]:keep=5.0
	elif mine.id in ["rise","run","charge"]:keep=3.0
	return best if (now_w-best_w)*1.6>keep else "pass"

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
