class_name BloodForge
extends RefCounted
## La forgia degli eroi: da pochi tratti (fisico, carattere, arma, scudo, armatura) costruisce un
## personaggio completo di Blood Master, con le sue pedine, e ne calcola il valore in punti.
##
## Le pedine seguono la stessa logica dei personaggi ufficiali: ogni corpo ha uno "scarto" di difesa D
## (la difesa di Avanzare) e un attacco di base A (quello di In guardia); le pedine sono scarti fissi
## da questi due numeri. Esempio: Gascor ha D=+2 e A=5, Zenyo D=-2 e A=6, Ut D=+4 e A=8.

# ------------------------------------------------------------------ scelte possibili
const STAZZE = ["Minuta","Snella","Media","Robusta","Enorme"]          # stazza 2..6
const LIVELLI = ["Scarsa","Normale","Grande"]                           # forza, agilità, resistenza 1..3
const CARATTERI = {"equilibrato":"Equilibrato","aggressivo":"Aggressivo","prudente":"Prudente","astuto":"Astuto"}
const ARMI = {"spada":"Spada","ascia":"Ascia a due mani","lancia":"Lancia","bastone":"Bastone (arti marziali)",
	"pugnale":"Pugnale","due_armi":"Due armi","arco":"Arco (e pugnale)"}
const SCUDI = {"nessuno":"Nessuno","piccolo":"Scudo piccolo","grande":"Scudo grande"}
const ARMATURE = {"nessuna":"Nessuna","leggera":"Leggera (cuoio)","media":"Media (maglia)","pesante":"Pesante (piastre)"}
const ARMOR_RANGE = {"nessuna":[],"leggera":[2,3],"media":[1,4],"pesante":[3,6]}
const NO_SHIELD = ["ascia","bastone","due_armi","arco"]   # armi a due mani: niente scudo
# a chi somiglia (modello 3D, disegni delle pedine) secondo l'arma
const LOOK = {"spada":"gascor","ascia":"ut","lancia":"shannon","bastone":"zenyo","pugnale":"kylvia","due_armi":"anteos","arco":"kylvia"}   # disegni delle pedine
const ASPETTI = {"uomo":"Uomo","donna":"Donna"}
# corpo 3D: armi a una mano (le clip impugnano con la destra, la sinistra libera o con lo scudo) o a due mani,
# poi armatura e aspetto. L'arma vera viene montata in mano dopo (vedi board3d._dress).
const ONE_HAND = ["spada","pugnale","due_armi"]
static func body_for(t: Dictionary) -> String:
	var arma=str(t.arma);var arm=str(t.armatura);var donna=str(t.get("aspetto","uomo"))=="donna";var big=int(t.stazza)>=4
	if arma=="arco":return "kylvia" if donna else "zak"
	if arma=="due_armi":return "kylvia" if donna else "zak"   # la sinistra libera (niente posa da scudo)
	if arma in ONE_HAND:
		if donna or arm in ["nessuna","leggera"]:return "kylvia" if donna else "zak"
		return "anteos" if arm=="media" else "gascor"
	if arm=="nessuna":return "shaara" if donna else ("nuchra" if big else "zenyo")
	if arm=="leggera" or donna:return "shannon"
	return "ramok" if arm=="media" else "ut"
## come vestire il corpo: arma in mano, cosa nell'altra mano (scudo, seconda arma), scala dalla stazza
static func dress_for(t: Dictionary,size: int,catalog_sizes: Dictionary={}) -> Dictionary:
	var body=body_for(t);var arma=str(t.arma)
	var off=""
	if arma=="due_armi":off="spada"
	elif str(t.scudo)!="nessuno" and not arma in NO_SHIELD:off="scudo_"+str(t.scudo)
	var bsize={"zenyo":3,"shaara":3,"gascor":4,"anteos":4,"ut":6,"nuchra":6,"shannon":4,"ramok":4,"kylvia":2,"zak":2}.get(body,4)
	return {"body":body,"weapon":"spada" if arma=="due_armi" else arma,"off":off,"scale":clampf(1.0+.07*(size-bsize),.8,1.25)}

const NAMES = {"guard":"In guardia","advance":"Avanzare","run":"Correre","rise":"Rialzarsi","roll":"Rotolare",
	"unbalanced":"Sbilanciato","down":"A terra","parry_r":"Parata destra","parry_l":"Parata sinistra","dodge":"Schivare",
	"charge":"Carica","right":"Colpo a destra","left":"Colpo a sinistra","thrust":"Affondo","again":"Ancora",
	"cleave":"Fendente","sweep":"Spazzata","kick":"Calcio","spin":"Rotazione","meditate":"Meditare",
	"shoot":"Tirare","load":"Incoccare","weapon":"Impugnare l'arma"}

static func default_traits() -> Dictionary:
	return {"name":"Nuovo eroe","title":"Il forgiato","stazza":3,"forza":2,"agilita":2,"resistenza":2,
		"carattere":"equilibrato","arma":"spada","scudo":"nessuno","armatura":"leggera","team":-1,"aspetto":"uomo"}

static func _tok(id: String,attack,defense: int,red: Array=[],green: Array=[],blue: Array=[],fatigue: int=0,imbalance=null,secondary=null,rest: bool=false) -> Dictionary:
	return {"id":id,"name":NAMES.get(id,id),"attack":attack,"defense":defense,"red":red,"green":green,"blue":blue,
		"fatigue":fatigue,"rest":rest,"imbalance":imbalance,"secondary":defense if secondary==null else secondary}

# ------------------------------------------------------------------ dai tratti al personaggio
static func build(t: Dictionary) -> Dictionary:
	var size: int=clampi(int(t.stazza),1,5)+1               # 2..6 come i personaggi ufficiali
	var str_: int=clampi(int(t.forza),1,3);var agi: int=clampi(int(t.agilita),1,3);var res: int=clampi(int(t.resistenza),1,3)
	var arma: String=t.arma;var scudo: String="nessuno" if arma in NO_SHIELD else str(t.scudo);var arm: String=t.armatura
	# scarto di difesa: un corpo grosso è un bersaglio facile, l'agilità lo rende sfuggente,
	# un'armatura pesante rallenta (ma assorbe ferite col suo dado)
	var D: int=int((size-4)*.5)+{"nessuna":0,"leggera":0,"media":2,"pesante":3}[arm]-(agi-2)*2
	# attacco di base: stazza e forza
	var A: int=size+str_-1
	var mv={}
	var add=func(m):mv[m.id]=m
	# pedine comuni a tutti
	add.call(_tok("advance",null,D,[],[5,0,1]))
	add.call(_tok("run",null,D+1,[],[5,0,1],[],1 if arm=="pesante" or size>=6 else 0))
	add.call(_tok("rise",null,D+3))
	add.call(_tok("unbalanced",null,D+4))
	add.call(_tok("down",null,D+5,[],[],[],0,null,null,true))
	add.call(_tok("dodge",null,D-2,[],[2,3,4] if size>=5 or arm=="pesante" else [1,2,3,4,5]))
	if agi>=2 and size<=4 and arm!="pesante":add.call(_tok("roll",null,D+2,[],[1,2,4,5]))
	add.call(_tok("again",null,0))
	# parate (non con l'arco in mano; due armi: parata larga ma meno solida)
	var pd=D-4;var ps=D-1;var br=[0,1];var bl=[5,0]
	if arma=="due_armi":pd=D-3;br=[5,0,1];bl=[5,0,1]
	if arma=="pugnale":pd=D-3
	if scudo=="piccolo":pd-=1;ps-=1
	if scudo=="grande":pd-=2;ps-=1;br=[0,1,2];bl=[4,5,0]
	add.call(_tok("parry_r",null,pd,[],[],br,0,null,ps,true))
	add.call(_tok("parry_l",null,pd,[],[],bl,0,null,ps,true))
	# pedine d'attacco secondo l'arma: [id, scarto d'attacco, scarto di difesa, rossi, fatica, sbilanciamento]
	var W={
		"spada":[["guard",0,-1,[5,0,1],0,null],["charge",3,1,[0],0,0],["right",2,0,[0,1],0,null],["left",2,0,[5,0],0,null],["thrust",4,-1,[0],1,2],["cleave",7,1,[0],1,0],["kick",0,2,[0,1],0,1]],
		"ascia":[["guard",0,-1,[5,0,1],0,null],["charge",2,1,[0],1,1],["right",1,0,[0,1],0,0],["left",1,0,[5,0],0,0],["spin",2,-1,[0,1,2,3,4,5],2,3],["cleave",6,1,[0],1,1],["kick",0,2,[0],0,2]],
		"lancia":[["guard",0,-1,[5,0,1],0,null],["charge",7,1,[0],0,0],["thrust",5,-1,[0],0,1],["sweep",1,-1,[5,0,1],0,3],["kick",-1,3,[0],0,2]],
		"bastone":[["guard",2,-1,[5,0,1],0,null],["charge",4,1,[0],0,0],["right",3,0,[0,1],0,null],["left",3,0,[5,0],0,null],["thrust",5,-1,[0],1,2],["cleave",7,1,[0],1,null],["sweep",2,0,[5,0,1],1,4]],
		"pugnale":[["guard",-1,-1,[5,0,1],0,null],["charge",1,1,[0],0,0],["right",1,0,[0,1],0,null],["left",1,0,[5,0],0,null],["thrust",3,-1,[0],0,null],["kick",0,2,[0,1],0,1]],
		"due_armi":[["guard",0,-1,[5,0,1],0,null],["charge",2,1,[0],0,0],["right",2,0,[0,1],0,null],["left",2,0,[5,0],0,null],["thrust",3,-1,[0],1,null],["spin",1,0,[0,1,2,3,4,5],1,1],["cleave",5,1,[5,0,1],1,null]],
		"arco":[["guard",1,-1,[5,0,1],0,null],["charge",3,1,[0],0,0],["right",2,0,[0,1],0,null],["left",2,0,[5,0],0,null],["thrust",4,-1,[0],1,null],["kick",1,2,[0,1],0,1]],
	}[arma]
	var car: String=t.carattere
	for w in W:
		var atk: int=A+int(w[1]);var imb=w[5]
		if scudo=="grande" and w[0]!="guard":atk-=1                 # lo scudo grande pesa sui colpi
		if car=="aggressivo":atk+=1
		if car=="prudente" and w[0]!="guard":atk-=1
		if car=="astuto" and imb!=null:imb=int(imb)+1                # colpi che sbilanciano
		if car=="astuto" and w[0]=="cleave":atk-=2
		var dd: int=D+int(w[2])
		if (scudo!="nessuno") and w[0]=="guard":dd-=1
		add.call(_tok(w[0],atk,dd,w[3],[0,5,1] if w[0]=="charge" else [],[],int(w[4]),imb,null,w[0]=="guard"))
	if mv.has("charge"):mv.charge.green=[5,0,1]
	if arma=="bastone":add.call(_tok("meditate",null,D+2,[],[],[],0,null,null,true))
	if arma=="arco":
		add.call(_tok("shoot",15,D+1,[5,0,1]))
		add.call(_tok("load",null,D+1,[],[0,1,2,3,4,5],[],0,null,null,true))
		add.call(_tok("weapon",null,D+3,[],[],[],0,null,null,true))
	# carattere sulle difese
	for id in ["parry_r","parry_l","dodge"]:
		if car=="aggressivo":mv[id].defense+=1;mv[id].secondary+=1
		if car=="prudente":mv[id].defense-=1;mv[id].secondary-=1
	if car=="prudente":mv.guard.defense-=1;mv.guard.secondary-=1
	if car=="astuto":mv.advance.green=[4,5,0,1,2]
	# punti ferita, sprint, equilibrio, recupero
	var hp: int=6*size+4*(res-2)+2
	var sprint: int=clampi(2+agi-(1 if size>=5 else 0)-(1 if arm=="pesante" else 0)-(1 if scudo=="grande" else 0),1,6)
	var sprints=[]
	for k in range(1,sprint+1):
		# [bonus d'attacco della carica, fatica, caduta con dado <=, sbilanciamento della carica]
		sprints.append([int(floor(k*(size+agi)/5.0)),(k+2-agi)/2,maxi(0,k-agi+1),roundi(k*size*size/20.0)])
	var rec=[[1,2,2,2,4,99],[1,1,2,3,3,99],[1,3,3,4,99,99]][res-1]
	if arm=="pesante":rec=[1,1,1,2,2,4]
	var tex_from: String=LOOK[arma]
	for m in mv.values():m.texture="res://assets/tokens/%s_%s.webp"%[tex_from,m.id]
	var id=str(t.get("id","")) if str(t.get("id",""))!="" else "forged_%d"%(abs(str(t.name).hash())%100000)
	return {"id":id,"name":str(t.name),"title":str(t.title),"kind":"forged","team":int(t.get("team",-1)),"size":size,"hp":hp,
		"sprint":sprint,"armor":ARMOR_RANGE[arm],"recovery":rec,"sprints":sprints,"card":"res://assets/cards/%s.webp"%body_for(t),
		"mage":false,"look":body_for(t),"dress":dress_for(t,size),"reach":arma in ["lancia","bastone"],"traits":t.duplicate(),"moves":mv}

# ------------------------------------------------------------------ valore in punti
# Tutto si misura in ferite attese (stesso calcolo della partita: dado che esplode sul 6, posizionale,
# lati blu della parata, armatura). Le caratteristiche del personaggio sono poi pesate con i
# coefficienti tarati su migliaia di partite simulate (tools/balance/fit.py): 100 punti = la media del cast.
const POS=[0,1,3,5,3,1]
const SIDE_W={0:.45,1:.15,5:.15,2:.09,4:.09,3:.07}
const OFFICIAL=["zenyo","gascor","ut","shannon","kylvia","anteos","shaara","zak","nuchra","ramok"]
# coefficienti (forza in scala logit per unità di caratteristica), tarati con le simulazioni
# tarati su circa 20.000 duelli e 1.200 partite a squadre fra cast ufficiale, 60 varianti e 40 eroi forgiati
# (correlazione 0,90 con la forza osservata; su eroi esclusi dalla taratura 0,86-0,94)
static var COEF={"off":1.013,"hp":0.9122,"sub":-0.5209,"sprint":0.0,"size":0.1363,"fat":-0.756,"imb":0.3,"natk":0.0,"green":0.0,"shoot":1.2267,"best":-0.3212,"zero":-4.1831}
# imb: nelle simulazioni lo sbilanciamento pesa quasi zero; gli si dà comunque un piccolo prezzo, perché non sia gratis
static var _die: Dictionary={}
static var _ref_def: Array=[]
static var _ref_atk: Array=[]
static var _off_cache: Dictionary={}
static var _sub_cache: Dictionary={}
static var _base_logit:=INF
static func _dist() -> Dictionary:
	if _die.is_empty():
		for d in range(1,6):_die[d]=1.0/6.0
		for e in range(1,7):_die[6+e]=1.0/36.0
	return _die
static func _wounds(total: int) -> int:
	if total>20:return mini(16,10+int(ceil((total-20)/2.0)))
	return clampi(total-10,0,10)
static func _armor_cut(n: float,armor: Array) -> float:
	if armor.is_empty() or n<=0:return n
	var out=0.0
	for d in range(1,7):out+=(maxf(0.0,n-d) if d>=int(armor[0]) and d<=int(armor[1]) else n)/6.0
	return out
## ferite attese di un attacco contro chi mostra questa pedina (lati da cui arriva il colpo pesati)
static func expected(attack: int,tok: Dictionary,armor: Array=[]) -> float:
	var out=0.0
	for side in SIDE_W:
		var dv=int(tok.defense)
		if not tok.blue.is_empty() and not side in tok.blue:dv=int(tok.secondary)
		var pos=0 if side in tok.red else POS[side]
		for d in _dist():out+=SIDE_W[side]*_dist()[d]*_armor_cut(_wounds(attack+dv+pos+d),armor)
	return out
static func _play(def: Dictionary) -> Array:
	var out=[]
	for k in def.moves:
		if k in ["unbalanced","down","again","pieces","rise","weapon"] or def.moves[k].get("spell",false):continue
		out.append(def.moves[k])
	return out
static func _refs() -> void:
	if not _ref_def.is_empty():return
	var cat=JSON.parse_string(FileAccess.get_file_as_string("res://data/characters.json"))
	for c in ["zenyo","gascor","ut","shannon","kylvia"]:
		for m in _play(cat[c]):
			for field in ["red","blue","green"]:m[field]=m[field].map(func(v):return int(v))
			_ref_def.append(m)
			if m.attack!=null and m.id!="shoot":_ref_atk.append(int(m.attack))
static func offense(a: int) -> float:
	# ferite attese di un colpo d'attacco "a" contro un difensore medio (tutte le pedine dei guerrieri)
	_refs()
	if not _off_cache.has(a):
		var e=0.0
		for t in _ref_def:e+=expected(a,t)
		_off_cache[a]=e/_ref_def.size()
	return _off_cache[a]
static func received(m: Dictionary,armor: Array) -> float:
	# ferite attese ricevute da un attaccante medio mentre si mostra la pedina m
	_refs()
	var k="%d|%d|%s|%s|%s"%[int(m.defense),int(m.secondary),str(m.blue),str(m.red),str(armor)]
	if not _sub_cache.has(k):
		var s=0.0
		for a in _ref_atk:s+=expected(a,m,armor)
		_sub_cache[k]=s/_ref_atk.size()
	return _sub_cache[k]
static func sum_hits(v: int) -> float:
	# probabilità che il dado di sbilanciamento (dado + stazza + modificatore) arrivi a 10 o più
	var h=0
	for d in range(1,7):
		if d+v>=10:h+=1
	return h/6.0
## caratteristiche misurabili del personaggio
static func features(def: Dictionary,_catalog: Dictionary={}) -> Dictionary:
	var offs=[];var fat=0.0;var imb=0.0
	for m in _play(def):
		if m.attack==null:continue
		offs.append(offense(11 if m.id=="shoot" else int(m.attack)))
		fat+=float(m.fatigue)
		if m.imbalance!=null:imb+=sum_hits(int(def.size)+int(m.imbalance))
	offs.sort();offs.reverse()
	var top=0.0;var n=mini(4,offs.size())
	for k in n:top+=offs[k]
	top/=maxf(1,n)
	var sub=0.0;var toks=_play(def);var green=0.0;var best=INF
	for m in toks:
		var rc=received(m,def.armor);sub+=rc;green+=m.green.size()
		if m.attack==null and m.id!="load":best=minf(best,rc)   # la difesa migliore (parata o schivata)
	sub/=maxf(1,toks.size())
	var na=float(offs.size())
	return {"off":top,"sub":sub,"hp":float(def.hp),"sprint":float(def.sprint),"size":float(def.size),
		"fat":fat/maxf(1.0,na),"imb":imb/maxf(1.0,na),"natk":na,"green":green/maxf(1.0,toks.size()),
		"shoot":1.0 if def.moves.has("shoot") else 0.0,"mage":1.0 if def.get("mage",false) else 0.0,
		"best":best if best<INF else sub}
## forza in scala logit: log dell'offesa e della vita, meno log delle ferite subite, più il resto
static func logit(f: Dictionary) -> float:
	var z=float(COEF.zero)
	z+=float(COEF.off)*log(maxf(f.off,.05))+float(COEF.hp)*log(maxf(f.hp,1.0))+float(COEF.sub)*log(maxf(f.sub,.05))+float(COEF.best)*log(maxf(f.best,.05))
	for k in ["sprint","size","fat","imb","natk","green","shoot"]:z+=float(COEF[k])*float(f[k])
	return z
## valore in punti: 100 = la media dei guerrieri ufficiali; 10 punti ≈ 5 vittorie in più (o in meno) su 100
static func points(def: Dictionary) -> float:
	if _base_logit==INF:
		var cat=JSON.parse_string(FileAccess.get_file_as_string("res://data/characters.json"));var t=0.0
		for id in OFFICIAL:
			for m in cat[id].moves.values():
				for field in ["red","blue","green"]:m[field]=m[field].map(func(v):return int(v))
			t+=logit(features(cat[id]))
		_base_logit=t/OFFICIAL.size()
	return 100.0+50.0*(logit(features(def))-_base_logit)
const BUDGET=100.0

# ------------------------------------------------------------------ modifiche a mano e salvataggio
## edits: {"hp":delta, "moves":{id:{"attack":d,"defense":d,"fatigue":d,"imbalance":d,"sides":[...]}}}
static func apply_edits(def: Dictionary,edits: Dictionary) -> Dictionary:
	var d=def.duplicate(true)
	d.hp=maxi(4,int(d.hp)+int(edits.get("hp",0)))
	var me: Dictionary=edits.get("moves",{})
	for id in me:
		if not d.moves.has(id):continue
		var m=d.moves[id];var e=me[id]
		if m.attack!=null and e.has("attack"):m.attack=maxi(0,int(m.attack)+int(e.attack))
		if e.has("defense"):m.defense=int(m.defense)+int(e.defense);m.secondary=int(m.secondary)+int(e.defense)
		if e.has("fatigue"):m.fatigue=clampi(int(m.fatigue)+int(e.fatigue),0,3)
		if e.has("imbalance"):m.imbalance=clampi(int(m.imbalance if m.imbalance!=null else 0)+int(e.imbalance),0,6)
		if e.has("sides"):
			var kind=side_kind(m)
			if kind!="":m[kind]=e.sides.map(func(v):return int(v))
	d.edits=edits.duplicate(true)
	return d
## quale colore di lato si modifica su questa pedina: rosso (attacchi), verde (movimenti), blu (parate)
static func side_kind(m: Dictionary) -> String:
	if not m.blue.is_empty():return "blue"
	if m.attack!=null:return "red"
	if not m.green.is_empty():return "green"
	return ""
const SAVE="user://heroes.json"
static func load_saved() -> Dictionary:
	if not FileAccess.file_exists(SAVE):return {}
	var d=JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	if not d is Dictionary:return {}
	var out={}
	for id in d:
		var h=d[id]
		if h is Dictionary and h.has("traits"):out[id]=apply_edits(build(h.traits),h.get("edits",{}))
	return out
static func save_hero(def: Dictionary) -> void:
	var all={}
	if FileAccess.file_exists(SAVE):
		var d=JSON.parse_string(FileAccess.get_file_as_string(SAVE))
		if d is Dictionary:all=d
	all[def.id]={"traits":def.traits,"edits":def.get("edits",{})}
	var f=FileAccess.open(SAVE,FileAccess.WRITE)
	if f:f.store_string(JSON.stringify(all))
static func delete_hero(id: String) -> void:
	if not FileAccess.file_exists(SAVE):return
	var d=JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	if d is Dictionary:
		d.erase(id);var f=FileAccess.open(SAVE,FileAccess.WRITE)
		if f:f.store_string(JSON.stringify(d))
