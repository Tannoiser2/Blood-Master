class_name BloodForge
extends RefCounted
## La forgia degli eroi: da pochi tratti (fisico, carattere, arma, scudo, armatura) costruisce un
## personaggio completo di Blood Master, con le sue pedine, e ne calcola il valore in punti.
##
## Le pedine seguono la stessa logica dei personaggi ufficiali: ogni corpo ha uno "scarto" di difesa D
## (la difesa di Avanzare) e un attacco di base A (quello di In guardia); le pedine sono scarti fissi
## da questi due numeri. Esempio: Gascor ha D=+2 e A=5, Zenyo D=-2 e A=6, Ut D=+4 e A=8.

# ------------------------------------------------------------------ scelte possibili
const CARATTERISTICHE = [["FOR","Forza","Colpi più forti; con la Costituzione fa la stazza"],["DES","Destrezza","Difesa, sprint, equilibrio nelle corse, schivate e capriole"],
	["COS","Costituzione","Ferite e recupero della fatica; con la Forza fa la stazza"],["INT","Intelligenza","Punti magia e quante magie puoi imparare (Intelligenza − 1)"]]
const CARATTERI = {"equilibrato":"Equilibrato","aggressivo":"Aggressivo","prudente":"Prudente","astuto":"Astuto"}
const ARMI = {"spada":"Spada","ascia":"Ascia a due mani","lancia":"Lancia","bastone":"Bastone (arti marziali)",
	"pugnale":"Pugnale","due_armi":"Due armi","arco":"Arco (e pugnale)"}
const SCUDI = {"nessuno":"Nessuno","piccolo":"Scudo piccolo","grande":"Scudo grande"}
const ARMATURE = {"nessuna":"Nessuna","leggera":"Leggera (cuoio)","media":"Media (maglia)","pesante":"Pesante (piastre)"}
const ARMOR_RANGE = {"nessuna":[],"leggera":[2,3],"media":[1,4],"pesante":[3,6]}
const NO_SHIELD = ["ascia","bastone","due_armi","arco"]   # armi a due mani: niente scudo
# a chi somiglia (disegni delle pedine) secondo l'arma
const LOOK = {"spada":"gascor","ascia":"ut","lancia":"shannon","bastone":"zenyo","pugnale":"kylvia","due_armi":"anteos","arco":"kylvia"}
const ASPETTI = {"uomo":"Uomo"}   # per ora solo corpi maschili
# corpi nuovi della forgia (uomini), uno per armatura: hanno sia le clip a una mano sia quelle a due mani
const FORGE_BODIES={"nessuna":"f_barbaro","leggera":"f_nomade","media":"f_predone","pesante":"f_cavaliere"}
const BODY_NAMES={"f_barbaro":"il barbaro delle steppe","f_nomade":"il nomade del deserto","f_predone":"il predone del nord","f_cavaliere":"il cavaliere nero"}
const BASE_IDS=["advance","run","rise","unbalanced","down","dodge","roll","again","parry_r","parry_l"]   # sempre presenti
# incantesimi dei quattro maghi che l'eroe può imparare
const SPELL_FROM={"gandy":["firestaff","shield","vortex","sleep","fireball"],"thorn":["pustules","fear","age","summon","plague"],
	"sanguinaria":["wall","teleport","transform","livingfire","abyss"],"ziggy":["shock","heal","drain","control","lightning"]}
static func body_for(t: Dictionary) -> String:
	if str(t.arma)=="arco":return "zak"   # le clip di tiro esistono solo sui corpi degli arcieri
	return FORGE_BODIES.get(str(t.armatura),"f_nomade")
## come vestire il corpo: arma in mano, cosa nell'altra mano (scudo, seconda arma), scala dalla stazza
static func dress_for(t: Dictionary,size: int,_catalog_sizes: Dictionary={}) -> Dictionary:
	var body=body_for(t);var arma=str(t.arma)
	var off=""
	if arma=="due_armi":off="spada"
	elif str(t.scudo)!="nessuno" and not arma in NO_SHIELD:off="scudo_"+str(t.scudo)
	var bsize={"f_barbaro":5,"f_nomade":3,"f_predone":4,"f_cavaliere":5,"zak":2}.get(body,4)
	return {"body":body,"weapon":"spada" if arma=="due_armi" else arma,"off":off,"scale":clampf(1.0+.07*(size-bsize),.8,1.25)}

const NAMES = {"guard":"In guardia","advance":"Avanzare","run":"Correre","rise":"Rialzarsi","roll":"Rotolare",
	"unbalanced":"Sbilanciato","down":"A terra","parry_r":"Parata destra","parry_l":"Parata sinistra","dodge":"Schivare",
	"charge":"Carica","right":"Colpo a destra","left":"Colpo a sinistra","thrust":"Affondo","again":"Ancora",
	"cleave":"Fendente","sweep":"Spazzata","kick":"Calcio","spin":"Rotazione","meditate":"Meditare",
	"shoot":"Tirare","load":"Incoccare","weapon":"Impugnare l'arma","concentrate":"Concentrarsi",
	"double":"Doppio colpo","parry_counter":"Contrattacco","feint":"Finta","bash":"Colpo di scudo","trip":"Sgambetto"}
# pedine in più, spente finché non le accendi: doppio colpo (due armi), contrattacco (para e poi colpisce),
# finta (non si può parare e i lati blu non contano), colpo di scudo, sgambetto, rotazione (colpisce tutto intorno)
const EXTRA_IDS=["double","parry_counter","feint","bash","trip","spin"]

static func default_traits() -> Dictionary:
	return {"name":"Nuovo eroe","title":"Il forgiato","FOR":3,"DES":3,"COS":3,"INT":1,
		"carattere":"equilibrato","arma":"spada","scudo":"nessuno","armatura":"leggera","team":-1,"aspetto":"uomo","spells":[],"off":[],"on":[]}
## eroi salvati con la prima forgia (stazza, forza, agilità, resistenza da 1 a 3): stessi valori nella scala nuova
static func migrate(t: Dictionary) -> Dictionary:
	var o=t.duplicate(true)
	if not o.has("FOR"):
		o.FOR=clampi(int(o.get("forza",2))*2-1,1,5);o.DES=clampi(int(o.get("agilita",2))*2-1,1,5);o.COS=clampi(int(o.get("resistenza",2))*2-1,1,5);o.INT=1
	if not o.has("spells"):o.spells=[]
	if not o.has("off"):o.off=[]
	if not o.has("on"):o.on=[]
	o.aspetto="uomo"
	return o
static func stat(t: Dictionary,k: String) -> int:return clampi(int(t.get(k,3)),1,5)
## stazza da Forza + Costituzione: 2 (minuta) .. 6 (enorme), come i personaggi ufficiali
static func size_of(t: Dictionary) -> int:return clampi(int(round((stat(t,"FOR")+stat(t,"COS"))/2.0))+1,2,6)

static func _tok(id: String,attack,defense: int,red: Array=[],green: Array=[],blue: Array=[],fatigue: int=0,imbalance=null,secondary=null,rest: bool=false) -> Dictionary:
	return {"id":id,"name":NAMES.get(id,id),"attack":attack,"defense":defense,"red":red,"green":green,"blue":blue,
		"fatigue":fatigue,"rest":rest,"imbalance":imbalance,"secondary":defense if secondary==null else secondary}

# ------------------------------------------------------------------ dai tratti al personaggio
## tutte le pedine possibili (anche quelle spente): base, d'arma e magie scelte
static func build_all(t0: Dictionary) -> Dictionary:
	var t=migrate(t0)
	var size: int=size_of(t)
	var F: int=stat(t,"FOR");var DX: int=stat(t,"DES");var C: int=stat(t,"COS");var I: int=stat(t,"INT")
	var agi: int=(DX+1)/2   # 1..3 per le tabelle di sprint ed equilibrio
	var arma: String=t.arma;var scudo: String="nessuno" if arma in NO_SHIELD else str(t.scudo);var arm: String=t.armatura
	# scarto di difesa: un corpo grosso è un bersaglio facile, la destrezza lo rende sfuggente,
	# un'armatura pesante rallenta (ma assorbe ferite col suo dado)
	var D: int=int((size-4)*.5)+{"nessuna":0,"leggera":0,"media":2,"pesante":3}[arm]-(DX-3)
	# attacco di base: stazza e forza
	var A: int=size+int(F*.6)
	var mv={}
	var add=func(m):mv[m.id]=m
	# pedine comuni a tutti
	add.call(_tok("advance",null,D,[],[5,0,1]))
	add.call(_tok("run",null,D+1,[],[5,0,1],[],1 if arm=="pesante" or size>=6 else 0))
	add.call(_tok("rise",null,D+3))
	add.call(_tok("unbalanced",null,D+4))
	add.call(_tok("down",null,D+5,[],[],[],0,null,null,true))
	add.call(_tok("dodge",null,D-2,[],[2,3,4] if size>=5 or arm=="pesante" else [1,2,3,4,5]))
	if DX>=3 and size<=4 and arm!="pesante":add.call(_tok("roll",null,D+2,[],[1,2,4,5]))
	add.call(_tok("again",null,0))
	# parate (due armi: parata larga ma meno solida)
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
	# pedine in più (spente finché non si accendono)
	var native_spin=mv.has("spin")
	if arma!="arco":
		if not native_spin:add.call(_tok("spin",A+1,D-1,[0,1,2,3,4,5],[],[],2,2));mv.spin.multi=true
		add.call(_tok("parry_counter",null,pd+1,[],[],[0],0,null,ps,false));mv.parry_counter.riposte=A+1
		add.call(_tok("feint",A-1,D,[0],[],[],0,null));mv.feint.feint=true
		add.call(_tok("trip",A-3,D+1,[0,1],[],[],0,5))
	if arma=="due_armi":add.call(_tok("double",A+1,D,[0],[],[],1,null));mv.double.double=true
	if scudo!="nessuno":add.call(_tok("bash",A-1,D-1,[0],[],[],0,4))
	if native_spin:mv.spin.multi=true;mv.spin.native=true
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
	var tex_from: String=LOOK[arma]
	for m in mv.values():m.texture="res://assets/tokens/%s_%s.webp"%[tex_from,m.id]
	# magie scelte (Intelligenza − 1 al massimo): stesse pedine dei maghi, difesa riportata sul corpo dell'eroe
	var spells: Array=t.get("spells",[]).slice(0,maxi(0,I-1))
	if not spells.is_empty():
		var cat=_catalog()
		add.call(_tok("concentrate",null,D+5,[],[0,1,2,3,4,5],[],0,null,null,true))
		mv.concentrate.texture="res://assets/tokens/gandy_concentrate.webp"
		for sid in spells:
			for mage in SPELL_FROM:
				if sid in SPELL_FROM[mage]:
					var m=cat[mage].moves[sid].duplicate(true)
					var base_d=int(cat[mage].moves.advance.defense) if cat[mage].moves.has("advance") else 0
					m.defense=D+int(m.defense)-base_d;m.secondary=D+int(m.secondary)-base_d;m.name=str(m.name)
					mv[sid]=m
	# punti ferita, sprint, equilibrio, recupero
	var hp: int=6*size+2*(C-3)+2
	var sprint: int=clampi(2+agi-(1 if size>=5 else 0)-(1 if arm=="pesante" else 0)-(1 if scudo=="grande" else 0),1,6)
	var sprints=[]
	for k in range(1,sprint+1):
		# [bonus d'attacco della carica, fatica, caduta con dado <=, sbilanciamento della carica]
		sprints.append([int(floor(k*(size+agi)/5.0)),(k+2-agi)/2,maxi(0,k-agi+1),roundi(k*size*size/20.0)])
	var rec=[[1,2,2,2,4,99],[1,2,2,2,4,99],[1,1,2,3,3,99],[1,3,3,4,99,99],[1,3,3,4,99,99]][C-1]
	if arm=="pesante":rec=[1,1,1,2,2,4]
	var id=str(t.get("id","")) if str(t.get("id",""))!="" else "forged_%d"%(abs(str(t.name).hash())%100000)
	return {"id":id,"name":str(t.name),"title":str(t.title),"kind":"forged","team":int(t.get("team",-1)),"size":size,"hp":hp,
		"sprint":sprint,"armor":ARMOR_RANGE[arm],"recovery":rec,"sprints":sprints,"card":"res://assets/cards/%s.webp"%tex_from,
		"mage":not spells.is_empty(),"magic_base":I+1,"look":body_for(t),"dress":dress_for(t,size),"reach":arma in ["lancia","bastone"],"traits":t,"moves":mv}
## il personaggio giocabile: senza le pedine spente
static func build(t0: Dictionary) -> Dictionary:
	var d=build_all(t0)
	for id in d.traits.get("off",[]):
		if not id in BASE_IDS:d.moves.erase(id)
	for id in EXTRA_IDS:
		if d.moves.has(id) and not id in d.traits.get("on",[]) and not d.moves[id].get("native",false):d.moves.erase(id)
	return d
## la pedina è accesa?
static func is_on(t: Dictionary,id: String) -> bool:
	if id in BASE_IDS:return true
	if id in EXTRA_IDS:return id in t.get("on",[])
	return not id in t.get("off",[])
static var _cat: Dictionary={}
static func _catalog() -> Dictionary:
	if _cat.is_empty():_cat=JSON.parse_string(FileAccess.get_file_as_string("res://data/characters.json"))
	return _cat
## pedine che si possono spegnere (tutte tranne le base)
static func optional(def: Dictionary) -> Array:
	return def.moves.keys().filter(func(k):return not k in BASE_IDS)

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
static var COEF={"off":1.0226,"hp":0.8668,"sub":-0.2078,"sprint":0.0,"size":0.1524,"fat":-0.7704,"imb":0.3,"natk":0.0,"green":0.2,"shoot":1.1399,"best":-0.5233,"rest":0.714,
	"reach":1.0,"step":.03,"spells":0.0,"ntok":.02,"zero":-4.614}
# valore in punti di ogni magia per un eroe forgiato: misurato con 1.080 duelli contro il cast (bastone di fuoco,
# evocazione, fulmine, palla di fuoco, sonno, abisso, controllo, paura, gorgo, scudo e cura); le altre stimate
const SPELL_POINTS={"firestaff":60,"summon":50,"lightning":40,"fireball":35,"sleep":28,"abyss":28,"transform":25,
	"livingfire":15,"plague":15,"control":12,"drain":12,"age":10,"vortex":9,"fear":8,"teleport":8,"shock":8,"wall":5,"pustules":4,"shield":3,"heal":3}
# stime, non dai dati (nelle partite simulate non variavano abbastanza o non esistevano):
#  green .2 (lati verdi delle pedine di movimento), reach 1.0 (lati rossi), step .03 a lato (passo prima/dopo),
#  ntok .02 a pedina (una scelta in più),
#  imb .3 (sbilanciamento); le magie hanno un prezzo ciascuna (SPELL_POINTS)
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
		var o=offense(11 if m.id=="shoot" else int(m.attack))
		if m.get("multi",false):o*=1.0+.3*float(maxi(0,m.red.size()-1))/2.0   # più nemici nello stesso colpo (stima)
		if m.get("double",false):o*=1.7          # due colpi (il secondo a -2) (stima)
		if m.get("feint",false):o*=1.2           # niente parata, lati blu ignorati (stima)
		offs.append(o)
		fat+=float(m.fatigue)
		if m.imbalance!=null:imb+=sum_hits(int(def.size)+int(m.imbalance))
	for m in _play(def):   # contrattacco: metà di un colpo in più quando para
		if int(m.get("riposte",0))>0:offs.append(offense(int(m.riposte))*.5)
	offs.sort();offs.reverse()
	var top=0.0;var n=mini(4,offs.size())
	for k in n:top+=offs[k]
	top/=maxf(1,n)
	# ferite subite: media sulle 10 pedine più solide (una pedina in più non peggiora mai: basta non giocarla)
	var sub=0.0;var toks=_play(def);var green=0.0;var best=INF;var recs=[]
	for m in toks:
		var rc=received(m,def.armor);recs.append(rc);green+=m.green.size()
		if m.attack==null and m.id!="load":best=minf(best,rc)   # la difesa migliore (parata o schivata)
	recs.sort()
	var kk=mini(10,recs.size())
	for q in kk:sub+=recs[q]
	sub/=maxf(1,kk)
	var na=float(offs.size())
	# lati rossi: quanto delle direzioni da cui arrivano i nemici copre ogni pedina d'attacco
	var reach=0.0;var rest=0.0;var step=0.0;var spells=0.0
	for m in toks:
		if m.attack!=null:
			for sd in m.red:reach+=float(SIDE_W.get(int(sd),0.0))
		if m.get("rest",false):rest+=1.0
		if not m.id in BloodRules.MOVE_IDS:step+=m.green.size()   # passo prima o dopo l'azione
	for k in def.moves:
		if def.moves[k].get("spell",false):spells+=float(def.moves[k].get("cost",1))
	return {"reach":reach/maxf(1.0,na),"rest":minf(rest,6.0)/10.0,"ntok":float(toks.size()),"step":step,"spells":spells,"off":top,"sub":sub,"hp":float(def.hp),"sprint":float(def.sprint),"size":float(def.size),
		"fat":fat/maxf(1.0,na),"imb":imb/maxf(1.0,na),"natk":na,"green":green/10.0,
		"shoot":1.0 if def.moves.has("shoot") else 0.0,"mage":1.0 if def.get("mage",false) else 0.0,
		"best":best if best<INF else sub}
## forza in scala logit: log dell'offesa e della vita, meno log delle ferite subite, più il resto
static func logit(f: Dictionary) -> float:
	var z=float(COEF.zero)
	z+=float(COEF.off)*log(maxf(f.off,.05))+float(COEF.hp)*log(maxf(f.hp,1.0))+float(COEF.sub)*log(maxf(f.sub,.05))+float(COEF.best)*log(maxf(f.best,.05))
	for k in ["sprint","size","fat","imb","natk","green","shoot","reach","rest","step","spells","ntok"]:z+=float(COEF.get(k,0.0))*float(f.get(k,0.0))
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
	var sp=0.0
	for k in def.moves:
		if def.moves[k].get("spell",false):sp+=float(SPELL_POINTS.get(k,10))
	return 100.0+50.0*(logit(features(def))-_base_logit)+(sp if def.get("kind","")=="forged" else 0.0)
const BUDGET=100.0

# ------------------------------------------------------------------ modifiche a mano e salvataggio
## edits: {"hp":delta, "moves":{id:{"attack":d,"defense":d,"secondary":d,"fatigue":d,   (scarti)
##          "imb":n o -1 (nessuno), "rest":bool, "red":[...], "green":[...], "blue":[...]}}}  (valori assoluti)
static func apply_edits(def: Dictionary,edits: Dictionary) -> Dictionary:
	var d=def.duplicate(true)
	d.hp=maxi(4,int(d.hp)+int(edits.get("hp",0)))
	var me: Dictionary=edits.get("moves",{})
	for id in me:
		if not d.moves.has(id):continue
		var m=d.moves[id];var e=me[id];var had_blue=not m.blue.is_empty()
		if m.attack!=null and e.has("attack"):m.attack=maxi(0,int(m.attack)+int(e.attack))
		if e.has("defense"):
			m.defense=int(m.defense)+int(e.defense)
			if not had_blue:m.secondary=int(m.secondary)+int(e.defense)
		if e.has("fatigue"):m.fatigue=clampi(int(m.fatigue)+int(e.fatigue),0,3)
		if e.has("imbalance"):m.imbalance=clampi(int(m.imbalance if m.imbalance!=null else 0)+int(e.imbalance),0,6)   # prima forgia
		if e.has("imb"):m.imbalance=null if int(e.imb)<0 else clampi(int(e.imb),0,6)
		if e.has("rest"):m.rest=bool(e.rest)
		if e.has("sides"):   # prima forgia: un solo colore per pedina
			var kind=side_kind(m)
			if kind!="":m[kind]=e.sides.map(func(v):return int(v))
		for c in ["red","green","blue"]:
			if e.has(c):
				var nw=e[c].map(func(v):return int(v));var diff=nw.size()-m[c].size()
				# più lati rossi = colpo più largo ma più debole; più lati blu = parata più ampia ma meno solida
				if c=="red" and m.attack!=null and m.id!="shoot":m.attack=maxi(0,int(m.attack)-diff)
				if c=="blue" and had_blue:m.defense=int(m.defense)+diff
				m[c]=nw
		if e.has("multi") and m.attack!=null:m.multi=bool(e.multi)
		if e.has("riposte") and int(m.get("riposte",0))>0:m.riposte=maxi(1,int(m.riposte)+int(e.riposte))
		if e.has("secondary") and not m.blue.is_empty():m.secondary=int(m.secondary)+int(e.secondary)
		if m.blue.is_empty():m.secondary=m.defense   # senza lati blu la difesa è una sola
		if int(m.fatigue)>0:m.rest=false   # col pallino nero (fatica) niente pallino bianco (riposo)
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
		if h is Dictionary and h.has("traits"):
			var t=migrate(h.traits);t.id=id;out[id]=apply_edits(build(t),h.get("edits",{}))
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
