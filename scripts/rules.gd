class_name BloodRules
extends RefCounted

const DIRS = [Vector2i(0,-1),Vector2i(1,-1),Vector2i(1,0),Vector2i(0,1),Vector2i(-1,1),Vector2i(-1,0)]
const VERSION = 1
var catalog: Dictionary
var arena: Dictionary
var cells: Dictionary = {}
var state: Dictionary = {}
var rng = RandomNumberGenerator.new()
var forced_dice: Array = []

func _init() -> void:
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters.json"))
	for character in catalog.values():
		for m in character.moves.values():
			for field in ["red","blue","green"]:
				if m.has(field):m[field]=m[field].map(func(v):return int(v))
	arena = JSON.parse_string(FileAccess.get_file_as_string("res://data/arena.json"))
	for c in arena.cells:
		cells[key(int(c.q),int(c.r))] = c

static func key(q: int,r: int) -> String: return "%d,%d" % [q,r]
static func coord(k: String) -> Vector2i: return Vector2i(int(k.get_slice(",",0)),int(k.get_slice(",",1)))
static func neighbor(k: String,d: int) -> String:
	var p = coord(k)+DIRS[posmod(d,6)]
	return key(p.x,p.y)
static func distance(a: String,b: String) -> int:
	var v = coord(a)-coord(b)
	return maxi(absi(v.x),maxi(absi(v.y),absi(v.x+v.y)))
static func direction(a: String,b: String) -> int:
	var best = 99999
	var result = 0
	for d in 6:
		var score = distance(neighbor(a,d),b)
		if score < best: best=score;result=d
	return result

func die() -> int:
	if not forced_dice.is_empty(): return int(forced_dice.pop_front())
	return rng.randi_range(1,6)
func note(s: String) -> void:
	state.log.append(s)
	if state.log.size()>100: state.log.pop_front()
func definition(p: Dictionary) -> Dictionary: return catalog[p.character]
func move(p: Dictionary,id: String="") -> Dictionary:
	return definition(p).moves.get(p.current if id=="" else id,{})
func living(p: Dictionary) -> bool: return p.alive and not p.get("frog",false)
func at(k: String,except: int=-1) -> int:
	for i in state.fighters.size():
		var p=state.fighters[i]
		if i!=except and p.alive and p.cell==k and not p.get("pieces",false): return i
	return -1
func hazard(k: String,kind: String="") -> Dictionary:
	for e in state.effects:
		if e.cell==k and (kind=="" or e.kind==kind): return e
	return {}
func blocked(k: String,except: int=-1) -> bool:
	return not cells.has(k) or at(k,except)!=-1 or not hazard(k,"vortex").is_empty()
func snapshot() -> Dictionary:
	var out=state.duplicate(true)
	out.rng_state=str(rng.state)
	return out
func restore(s: Dictionary) -> void:
	state=_restore_numbers(s)
	rng.state=int(state.get("rng_state","1"))

# JSON represents all numbers as floats; array membership in Godot is typed.
# Restore integer rule values, including abyss dice and campaign player indices.
static func _restore_numbers(value):
	if value is Dictionary:
		var out={}
		for k in value:out[k]=_restore_numbers(value[k])
		return out
	if value is Array:return value.map(func(v):return _restore_numbers(v))
	if value is float and value==floor(value):return int(value)
	return value

func new_game(roster: Array,scenario: String="frontale",seed_n: int=1,magic: int=-1) -> void:
	rng.seed=seed_n
	state={"version":VERSION,"turn":0,"phase":"deploy","fighters":[],"plans":{},"bag":[],"active":-1,"effects":[],"log":[],"pending":{},"scenario":scenario,"war":scenario!="frontale","peace_left":4,"winner":-2,"seed":seed_n,"revision":0,"magic_start":magic,"round":1,"campaign":{},"interrupt_stack":[],"spin":{}}
	for i in roster.size():
		var cfg=roster[i];var d=catalog[cfg.character]
		var p={"character":cfg.character,"name":cfg.get("name",d.name),"team":int(cfg.get("team",i%2)),"controller":cfg.get("controller","ai"),"seat":int(cfg.get("seat",i)),"cell":"","facing":0,"hp":int(d.hp),"max_hp":int(d.hp),"fatigue":0,"permanent":0,"magic":(5+die() if magic<0 else magic) if d.mage else 0,"current":"float" if d.kind=="ziggy" else "guard","previous":"","done":false,"alive":true,"lost":[],"unbalanced":false,"down":false,"frog":false,"pieces":false,"guarding":false,"loaded":false,"bow":false,"meditated":false,"burning":false,"plague":-1,"controller_by":-1,"sprint_mod":0,"owner":-1}
		if d.kind=="ziggy":p.hp=die()*3;p.max_hp=p.hp
		if d.kind=="skeleton":p.current="guard"
		state.fighters.append(p)
	note("Blood Master · schieramento nell’arena")
	state.active=0

func entry_cells(team: int) -> Array:
	var out=[]
	for k in cells:
		var c=cells[k]
		if c.entry and ((c.y<1000 and team==1) or (c.y>1700 and team==0)):out.append(k)
	return out
func deploy(k: String,facing: int) -> bool:
	if state.phase!="deploy" or not cells.has(k):return false
	var p=state.fighters[state.active]
	if not k in entry_cells(p.team):return false
	# Original scenario permits sharing an entry hex with an ally.
	var occupant=at(k)
	if occupant!=-1 and state.fighters[occupant].team!=p.team:return false
	p.cell=k;p.facing=posmod(facing,6)
	state.active+=1
	if state.active>=state.fighters.size():begin_turn()
	return true
func begin_turn() -> void:
	state.turn+=1;state.phase="planning";state.active=-1;state.plans={};state.bag=[];state.pending={}
	if not state.war:
		if rng.randi_range(0,int(state.peace_left))==0:state.war=true;note("GUERRA · ora è possibile attaccare.")
		else:state.peace_left-=1;note("PACE · questo turno non si attacca.")
	for p in state.fighters:
		p.done=false;p.guarding=false
		if p.get("skip_next",false):p.done=true;p.skip_next=false
		if p.alive and p.frog:_frog_turn(p)
	note("Turno %d · scegliete le mosse in segreto." % state.turn)
	_check_end()

func legal_moves(i: int) -> Array:
	if i<0 or i>=state.fighters.size():return []
	var p=state.fighters[i];var out=[]
	if not living(p) or p.done or p.pieces or not hazard(p.cell,"vortex").is_empty():return out
	var prev=move(p)
	for id in definition(p).moves:
		var m=move(p,id)
		if id in ["unbalanced","down","pieces"] or id in p.lost:continue
		if p.down and not id in ["rise","roll"]:continue
		if not p.down and id in ["rise","roll"]:continue
		if id=="again":
			if p.current in ["again","unbalanced","down","pieces"] or p.current in p.lost:continue
			m=prev
		if m.get("spell",false) and (p.down or p.magic<m.cost):continue
		if m.fatigue>0 and m.attack!=null and (p.unbalanced or (prev.get("attack")!=null and prev.get("fatigue",0)>0)):continue
		if id=="shoot" and not p.loaded:continue
		if p.bow and m.attack!=null and id!="shoot":continue
		if p.bow and not m.blue.is_empty():continue
		if not state.war and (m.attack!=null or m.get("spell",false) and m.target=="enemy"):continue
		out.append(id)
	return out
func plan(i: int,id: String) -> bool:
	if state.phase!="planning" or state.plans.has(str(i)) or not id in legal_moves(i):return false
	state.plans[str(i)]=id
	return true
func needs_plan() -> Array:
	var out=[]
	for i in state.fighters.size():
		if not state.plans.has(str(i)) and not legal_moves(i).is_empty():out.append(i)
	return out
func reveal() -> bool:
	if state.phase!="planning" or not needs_plan().is_empty():return false
	for k in state.plans:
		state.bag.append({"fighter":int(k),"move":state.plans[k]})
		if state.fighters[int(k)].unbalanced:state.bag.append({"fighter":int(k),"move":"fall"})
	for j in range(state.bag.size()-1,0,-1):
		var z=rng.randi_range(0,j);var t=state.bag[j];state.bag[j]=state.bag[z];state.bag[z]=t
	state.plans={};state.phase="draw";state.active=-1
	return true
func draw_next() -> void:
	if state.phase!="draw":return
	while not state.bag.is_empty():
		var b=state.bag.pop_front();var p=state.fighters[b.fighter]
		if not living(p) or p.done or p.pieces:continue
		if b.move=="fall":_knock(int(b.fighter),true);p.done=true;note(p.name+" cade a terra prima di agire.");continue
		var id=b.move
		if id=="again":id=p.current
		if not definition(p).moves.has(id) or id in p.lost:p.done=true;continue
		if b.move!="again":
			p.shield=false
			state.effects=state.effects.filter(func(e):return int(e.owner)!=int(b.fighter) or not e.kind in ["vortex","livingfire"])
		p.previous=p.current;p.current=id;p.sprint_mod=0;p.unbalanced=false;p.pending_sprint_fatigue=0
		if b.move=="again" and id=="concentrate":continue
		state.active=b.fighter;state.phase="acting";state.pending={}
		note(p.name+" rivela: "+move(p).name+".")
		var opportunities=[]
		for j in state.fighters.size():
			var other=state.fighters[j]
			if j!=int(b.fighter) and living(other) and not other.done and not other.down and (other.guarding or other.current=="concentrate"):opportunities.append(j)
		if not opportunities.is_empty():
			state.pending={"kind":"opportunity","resume":int(b.fighter),"reactors":opportunities};state.phase="opportunity"
		return
	finish_turn()

func reachable(i: int,max_steps: int,dirs: Array=[]) -> Dictionary:
	var p=state.fighters[i];var paths={p.cell:[]};var queue=[p.cell]
	while not queue.is_empty():
		var here=queue.pop_front();var path=paths[here]
		if path.size()>=max_steps:continue
		for d in (DIRS.size() if dirs.is_empty() else 0):
			var next=neighbor(here,d)
			if paths.has(next) or blocked(next,i):continue
			paths[next]=path+[next];queue.append(next)
		for d in dirs:
			var next=neighbor(here,int(d)+int(p.facing))
			if paths.has(next) or blocked(next,i):continue
			paths[next]=path+[next];queue.append(next)
	return paths
func in_view(p: Dictionary,k: String) -> bool:
	if definition(p).kind=="ziggy" or k==p.cell:return true
	var delta=coord(k)-coord(p.cell)
	var vec=Vector2(1.5*delta.x,sqrt(3.0)*(delta.y+delta.x*.5))
	var forward=Vector2.UP.rotated(int(p.facing)*PI/3)
	return absf(forward.angle_to(vec))<=PI/3+.001
func targets(i: int,id: String="") -> Array:
	var p=state.fighters[i];var m=move(p,id);var out=[]
	if m.is_empty():return out
	if not state.get("spin",{}).is_empty() and int(state.spin.actor)==i:return state.spin.remaining
	if m.get("spell",false):
		if p.magic<int(m.cost):return []
		for k in cells:
			var dist=distance(p.cell,k)
			if dist>int(m.range) or not in_view(p,k):continue
			var occupant=at(k)
			if m.target=="self" and k!=p.cell:continue
			if m.target=="empty" and blocked(k,i):continue
			if m.id=="teleport" and dist>p.magic:continue
			if m.id=="livingfire" and (dist!=1 or not posmod(direction(p.cell,k)-int(p.facing),6) in FACING_FRONT):continue
			if m.target=="enemy" and (occupant==-1 or state.fighters[occupant].team==p.team):continue
			out.append(k)
		return out
	if m.id in ["run","charge","float"]:return reachable(i,int(definition(p).sprint)).keys()
	if m.id in ["advance","dodge","load","concentrate","roll","rise"]:
		var dirs=m.green
		if m.id in ["concentrate","load","rise","roll"]:dirs=[]
		return reachable(i,2 if m.id=="roll" else 1,dirs).keys()
	if m.attack!=null:
		for j in state.fighters.size():
			var t=state.fighters[j]
			if not living(t) or t.team==p.team or t.pieces or not hazard(t.cell,"vortex").is_empty():continue
			if m.id=="shoot":
				if in_view(p,t.cell):out.append(t.cell)
			elif distance(p.cell,t.cell)==1 and posmod(direction(p.cell,t.cell)-int(p.facing),6) in m.red:out.append(t.cell)
		return out
	return [p.cell]
const FACING_FRONT=[5,0,1]
func reaction_options(i: int,spell_value: int=0) -> Array:
	var p=state.fighters[i];var out=["pass"]
	if not living(p) or p.done or p.down or p.unbalanced:return out
	if spell_value>0:
		if p.current=="concentrate" and p.magic>=spell_value:out.append("counter")
		return out
	if p.bow or (move(p).get("attack")!=null and move(p).get("fatigue",0)>0):return out
	for id in definition(p).moves:
		if id in p.lost:continue
		if id.begins_with("parry") or id=="dematerialize":out.append(id)
	return out

func act(command: Dictionary) -> bool:
	if state.phase!="acting":return false
	var i=int(state.active);var p=state.fighters[i];var m=move(p)
	var k=str(command.get("target",p.cell));var facing=posmod(int(command.get("facing",p.facing)),6)
	var rotation=mini(posmod(facing-int(p.facing),6),posmod(int(p.facing)-facing,6))
	var max_rotation=1
	if m.id in ["rise","meditate","teleport","float"] or (m.id=="guard" and command.get("wait",false)):max_rotation=3
	if m.id.begins_with("parry") or m.id in ["dematerialize","weapon","roll"]:max_rotation=0
	if rotation>max_rotation:return false
	if command.get("wait",false) and m.id=="guard":
		p.facing=facing;p.guarding=true;state.phase="draw";state.active=-1;note(p.name+" resta in guardia, pronto a intervenire.");return true
	if command.get("pass",false):
		_finish_action(i,m,false,facing);return true
	if not k in targets(i):return false
	if m.get("spell",false):
		var extra=maxi(0,int(command.get("extra",0)));var cost=int(m.cost)
		if m.id=="teleport":cost=distance(p.cell,k)
		elif m.id in ["fireball","lightning","control"]:cost+=extra
		elif m.id=="abyss" and extra>0:cost=10
		if p.magic<cost:return false
		p.magic-=cost
		state.pending={"kind":"spell","actor":i,"target":k,"facing":facing,"extra":extra,"move":m.id,"reactors":[]}
		for j in state.fighters.size():
			if state.fighters[j].team!=p.team and "counter" in reaction_options(j,int(m.value)):state.pending.reactors.append(j)
		if not state.pending.reactors.is_empty():state.phase="reaction"
		else:_cast_pending()
		return true
	var paths={}
	if m.id in ["advance","dodge","run","charge","float","load","concentrate","roll","rise"]:
		var max_step=1
		if m.id in ["run","charge","float"]:max_step=int(definition(p).sprint)
		if m.id=="roll":max_step=2
		paths=reachable(i,max_step,[] if m.id in ["run","charge","float","load","concentrate","roll","rise"] else m.green)
		var path: Array=command.get("path",paths.get(k,[]))
		if path.size()>max_step:return false
		var here=p.cell
		for step in path:
			if distance(here,step)!=1 or blocked(step,i):return false
			here=step
		if here!=k:return false
		var steps=path.size();var stumble=false
		if steps>0 and m.id in ["run","charge"]:
			var sp=definition(p).sprints
			if steps>sp.size():return false
			var sprint=sp[steps-1];p.sprint_mod=int(sprint[0]);p.pending_sprint_fatigue=int(sprint[1])
			var sd=die();stumble=sd<=int(sprint[2])
			if int(sprint[2])>0:note("%s, equilibrio nello sprint: dado %d, cade con %d o meno." % [p.name,sd,int(sprint[2])])
			state.pending["charge_imbalance"]=int(sprint[3])
		if m.id=="float":_hurt(i,maxi(0,steps-die()),false)
		if stumble:
			# The player can choose a cell along the declared route on a failed balance roll.
			state.pending={"kind":"stumble","actor":i,"path":path,"facing":facing,"move":m.id}
			state.phase="stumble";note(p.name+" perde l’equilibrio durante lo sprint.");return true
		for step in path:
			p.cell=step;_cross_effects(i)
			if not p.alive:break
		if m.id=="rise":
			p.down=false;p.unbalanced=steps>0
			if steps>0:p.current="unbalanced"
		if m.id=="load":p.loaded=true;p.bow=true
		if m.id=="charge" and p.alive:
			var target=at(neighbor(p.cell,int(p.facing)),i)
			if target!=-1 and state.fighters[target].team!=p.team:
				_attack_request(i,target,facing,int(state.pending.get("charge_imbalance",0)));return true
			_knock(i,false);note(p.name+": carica senza contatto, sbilanciato.")
		_finish_action(i,m,false,facing);return true
	if m.attack!=null and at(k,i)!=-1:
		_attack_request(i,at(k,i),facing);return true
	if m.id=="meditate":p.meditated=true
	if m.id=="weapon":p.bow=false;p.loaded=false
	_finish_action(i,m,false,facing)
	return true

func choose_stumble(k: String) -> bool:
	if state.phase!="stumble" or not k in state.pending.path:return false
	var i=int(state.pending.actor);var p=state.fighters[i];var m=move(p)
	p.cell=k;_knock(i,false);_finish_action(i,m,false,int(state.pending.facing));return true
func guard_attack(i: int,k: String,facing: int) -> bool:
	if state.phase!="draw" or not state.fighters[i].guarding:return false
	var p=state.fighters[i];var old=p.facing;p.facing=posmod(facing,6)
	if not k in targets(i):p.facing=old;return false
	p.guarding=false;state.active=i;_attack_request(i,at(k,i),p.facing);return true
func _attack_request(i: int,j: int,facing: int,charge_imbalance: int=0) -> void:
	state.pending={"kind":"attack","actor":i,"victim":j,"facing":facing,"charge_imbalance":charge_imbalance,"reactors":[j]}
	if reaction_options(j).size()>1:state.phase="reaction"
	else:_attack_pending()
func react(id: String) -> bool:
	if state.phase!="reaction":return false
	var pending=state.pending;var j=int(pending.reactors[0]);var p=state.fighters[j]
	var v=int(move(state.fighters[pending.actor]).get("value",0)) if pending.kind=="spell" else 0
	if not id in reaction_options(j,v):return false
	if id=="counter":
		p.magic-=v
		var rolled=die();note("%s disperde magia: dado %d, serve più di %d." % [p.name,rolled,v])
		if rolled>v:
			p.done=true;p.guarding=false
			var actor=state.fighters[pending.actor]
			_finish_action(int(pending.actor),move(actor),false,int(pending.facing));return true
		# Author clarification: failure spends magic but leaves the move available.
	elif id!="pass":
		p.current=id;p.done=true;p.guarding=false
		if id=="dematerialize":_hurt(j,1,false)
		note(p.name+" reagisce con "+move(p).name+".")
	pending.reactors.pop_front()
	if pending.reactors.is_empty():
		if pending.kind=="spell":_cast_pending()
		else:_attack_pending()
	return true
func _attack_pending() -> void:
	var pending=state.pending.duplicate(true);var i=int(pending.actor);var p=state.fighters[i];var m=move(p)
	var penalty=int(state.get("spin",{}).get("penalty",0))
	var effect=_combat(i,int(pending.victim),m,false,-penalty,int(pending.get("charge_imbalance",0)))
	if m.id=="spin":
		var remaining=targets(i).duplicate();remaining.erase(state.fighters[int(pending.victim)].cell)
		remaining=remaining.filter(func(k):return at(k,i)!=-1 and living(state.fighters[at(k,i)]))
		if not remaining.is_empty():
			state.spin={"actor":i,"remaining":remaining,"penalty":penalty+2,"effect":effect or state.get("spin",{}).get("effect",false)}
			state.phase="acting";state.pending={};return
		effect=effect or state.get("spin",{}).get("effect",false)
	if m.id=="shoot":
		p.loaded=false
		state.shots=int(state.get("shots",0))+1                 # per la mappa 3D: la freccia vola verso il bersaglio
		state.last_shot={"actor":i,"victim":int(pending.victim)}
	_finish_action(i,m,effect,int(pending.facing))

static func combat_table(total: int) -> Dictionary:
	var wounds=clampi(total-10,0,10)
	if total>20:wounds=mini(16,10+int(ceil((total-20)/2.0)))
	return {"wounds":wounds,"unbalance":total>=21 and not total in [25,26]}
static func balance_table(value: int,size: int) -> int:
	# Exact printed table, row 7- and 17+ are clamped.
	var rows=[ [0,-1,-1,-1,-1,-1,-1,-1,-1,-1], [0,0,-1,-1,-1,-1,-1,-1,-1,-1], [0,0,0,-1,-1,-1,-1,-1,-1,-1], [1,0,0,0,-1,-1,-1,-1,-1,-1], [1,1,0,0,0,-1,-1,-1,-1,-1], [1,1,1,0,0,0,-1,-1,-1,-1], [2,1,1,1,0,0,0,-1,-1,-1], [2,2,1,1,1,0,0,0,-1,-1], [2,2,2,1,1,1,0,0,0,-1], [3,2,2,2,1,1,1,0,0,0], [3,3,2,2,2,1,1,1,0,0] ]
	return rows[clampi(value,7,17)-7][clampi(size,1,10)-1]
func _combat(i: int,j: int,m: Dictionary,magic: bool=false,bonus: int=0,charge_imbalance: int=0) -> bool:
	var a=state.fighters[i];var b=state.fighters[j]
	if not living(a) or not living(b):return false
	var defense=move(b)
	var side=posmod(direction(b.cell,a.cell)-int(b.facing),6)
	var dv=int(defense.get("defense",0))
	if b.get("shield",false):dv=-15
	if not defense.get("blue",[]).is_empty() and not side in defense.blue:dv=int(defense.secondary)
	var positional=[0,1,3,5,3,1][side] if not side in defense.get("red",[]) else 0
	var attack=int(m.get("attack",0))+bonus
	if a.meditated and not magic:attack=int(m.get("attack",0))*2+bonus;a.meditated=false
	if m.id=="shoot":attack=15-distance(a.cell,b.cell)
	if not magic:attack+=int(a.sprint_mod)-int(a.fatigue)-int(a.permanent)
	dv+=int(b.sprint_mod)+int(b.fatigue)+int(b.permanent)
	var d=die();var total=attack+dv+positional+d;var extra=0
	if d==6:
		extra=die();total+=extra
		var removable=[]
		for id in definition(b).moves:
			if not definition(b).moves[id].red.is_empty() and not id in b.lost:removable.append(id)
		if not removable.is_empty():
			var lost=removable[rng.randi_range(0,removable.size()-1)];b.lost.append(lost);note(b.name+" perde la mossa "+definition(b).moves[lost].name+" per un critico.")
		if extra==6:_kill(j);note("Doppio sei! "+b.name+" viene ucciso.");return true
	var result=combat_table(total)
	note("%s attacca %s: %d + %d + %d + dado %d%s = %d; %d ferite%s." % [a.name,b.name,attack,dv,positional,d," + dado %d" % extra if extra>0 else "",total,result.wounds," · sbilanciato (S)" if result.unbalance and result.wounds>0 else ""])
	_hurt(j,int(result.wounds),not magic)
	# Nello stesso attacco lo sbilanciamento conta una volta sola: la "S" della tabella e il tiro
	# sulla tabella di sbilanciamento non si sommano per mandare a terra (si cade solo se si era
	# già sbilanciati prima del colpo, o se arretrando si urta un ostacolo).
	var knocked=false
	if result.unbalance and b.alive and not b.pieces:_knock(j,false);knocked=true
	if m.get("imbalance")!=null and result.wounds>0 and b.alive and not b.pieces:
		var bd=die();var value=bd+int(definition(a).size)+int(m.imbalance)+charge_imbalance
		var push=balance_table(value,int(definition(b).size))
		note("Sbilanciamento: dado %d + stazza %d + modificatore %d%s = %d contro stazza %d: %s." % [bd,int(definition(a).size),int(m.imbalance)," + carica %d"%charge_imbalance if charge_imbalance else "",value,int(definition(b).size),"nessun effetto" if push<0 else ("sbilanciato" if push==0 else "sbilanciato, arretra di %d" % push)])
		if push>=0:
			if not knocked:_knock(j,false)
			var dir=direction(a.cell,b.cell)
			for step in push:
				var dest=neighbor(b.cell,dir);var other=at(dest,j)
				if blocked(dest,j):
					_knock(j,true)
					if other!=-1 and definition(state.fighters[other]).size<=definition(b).size:_knock(other,false)
					break
				b.cell=dest;_cross_effects(j)
	return result.wounds>0
func _hurt(i: int,n: int,armor: bool=true) -> void:
	var p=state.fighters[i]
	if n<=0 or not p.alive or p.frog:return
	if definition(p).kind=="skeleton":return
	if armor and not definition(p).armor.is_empty():
		var d=die();var arm=definition(p).armor
		if d>=arm[0] and d<=arm[1]:n=maxi(0,n-d);note(p.name+": armatura, dado %d: assorbe %d ferite." % [d,d])
	if n>0:p.hp-=n;p.meditated=false
	if p.hp<=0:_kill(i)
func _kill(i: int) -> void:
	var p=state.fighters[i];p.alive=false;p.done=true;p.guarding=false;note(p.name+" è fuori combattimento.")
	for other in state.fighters:
		if other.get("frog_owner",-1)==i:other.frog=false;other.frog_owner=-1
		if other.plague==i:other.plague=-1
	state.effects=state.effects.filter(func(e):return int(e.owner)!=i)
	if state.scenario=="bloodmaster" and rng.randi_range(0,maxi(1,state.campaign.get("players",[]).size()-2))==0:state.winner=-1;state.phase="finished";note("PACE · il round termina.");_score_campaign()
func _knock(i: int,ground: bool) -> void:
	var p=state.fighters[i]
	if definition(p).kind=="ziggy":return
	if definition(p).kind=="skeleton":p.pieces=true;p.current="pieces";p.done=true;note(p.name+" va in pezzi.");return
	if definition(p).kind=="golem":_kill(i);return
	if ground or p.unbalanced or p.down:p.down=true;p.unbalanced=false;p.current="down"
	else:p.unbalanced=true;p.current="unbalanced"
	p.done=true;p.guarding=false
func _finish_action(i: int,m: Dictionary,attack_effect: bool,facing: int) -> void:
	var p=state.fighters[i]
	p.fatigue+=int(m.fatigue)+int(p.get("pending_sprint_fatigue",0));p.pending_sprint_fatigue=0
	if m.id!="meditate":p.meditated=false
	if m.id!="load":p.loaded=false
	if m.attack==null or attack_effect or m.id=="charge":p.facing=facing
	p.done=true;p.guarding=false;p.controller_by=-1
	if not state.phase in ["finished","round_result","campaign_finished"]:state.phase="draw"
	state.active=-1;state.pending={};state.spin={};state.revision+=1
	if not state.get("interrupt_stack",[]).is_empty() and state.phase=="draw":
		var resume=state.interrupt_stack.pop_back()
		if living(state.fighters[resume]) and not state.fighters[resume].done:state.phase="acting";state.active=resume
	_check_end()
func _check_end() -> void:
	if state.phase in ["deploy","finished","handicap","auction","round_result","campaign_finished"]:return
	var teams=[]
	for p in state.fighters:
		if living(p) and not p.pieces and not p.team in teams:teams.append(p.team)
	if teams.size()<=1:
		state.winner=teams[0] if teams.size()==1 else -1;state.phase="finished"
		note("Lo scontro è terminato.")
		if state.scenario=="bloodmaster":_score_campaign()

func _cast_pending() -> void:
	var s=state.pending.duplicate(true);var i=int(s.actor);var p=state.fighters[i];var m=move(p)
	var k=str(s.target);var j=at(k);var extra=int(s.get("extra",0))
	note(p.name+" lancia "+m.name+".")
	state.spells=int(state.get("spells",0))+1;state.last_spell={"actor":i,"target":k,"move":m.id}   # per gli effetti 3D
	match m.id:
		"firestaff":
			if j!=-1 and _combat(i,j,m,true):state.fighters[j].burning=true
		"shield":p.shield=true
		"vortex":_effect(i,k,"vortex",2)
		"sleep":
			if j!=-1:
				var s1=die();var s2=die();var s3=die();var n=maxi(0,s1+s2+s3-int(definition(state.fighters[j]).size));state.fighters[j].fatigue+=n
				note("Sonno su %s: dado %d + dado %d + dado %d - stazza %d = %d fatica." % [state.fighters[j].name,s1,s2,s3,int(definition(state.fighters[j]).size),n])
				if n>=9:_knock(j,true)
		"fireball":
			for t in state.fighters.size():
				if living(state.fighters[t]) and distance(k,state.fighters[t].cell)<=1:
					_magic_hit(i,t,15+extra);state.fighters[t].burning=true
		"wall":_effect(i,k,"wall",4)
		"teleport":p.cell=k;_cross_effects(i)
		"transform":
			if j!=-1:
				for t in state.fighters:
					if t.get("frog_owner",-1)==i:t.frog=false;t.frog_owner=-1
				state.fighters[j].frog=true;state.fighters[j].frog_owner=i;state.fighters[j].done=true
		"livingfire":_effect(i,k,"livingfire",6)
		"abyss":
			_effect(i,k,"abyss",5)
			var e=hazard(k,"abyss");e.numbers=[1,2,3,4] if extra>0 else [1,2]
			if j!=-1:_abyss(j,e)
		"shock":
			var hit=[i];var queue=[i]
			while not queue.is_empty():
				var u=queue.pop_front()
				for t in state.fighters.size():
					if not t in hit and living(state.fighters[t]) and distance(state.fighters[u].cell,state.fighters[t].cell)==1:hit.append(t);queue.append(t)
			for t in hit:
				if t!=i:_hurt(t,die(),false)
		"heal":
			var hd=die();p.hp+=hd;p.max_hp=maxi(p.hp,p.max_hp);note("%s si rigenera: dado %d, +%d ferite." % [p.name,hd,hd])
		"drain":
			if j!=-1:
				var n=die();note("%s drena %s: dado %d." % [p.name,state.fighters[j].name,n]);_hurt(j,n,false);p.hp+=n;p.max_hp=maxi(p.hp,p.max_hp)
		"control":
			if j!=-1 and die()<=mini(4,1+extra):state.fighters[j].controller_by=i
		"lightning":
			var hit=[];var here=p.cell
			for step in mini(7,distance(p.cell,k)):
				here=neighbor(here,direction(here,k));var occupant=at(here)
				if occupant!=-1 and not occupant in hit:hit.append(occupant)
			if j!=-1 and not j in hit:hit.append(j)
			var queue=hit.duplicate()
			while not queue.is_empty():
				var u=queue.pop_front()
				for t in state.fighters.size():
					if t!=i and not t in hit and living(state.fighters[t]) and distance(state.fighters[u].cell,state.fighters[t].cell)==1:hit.append(t);queue.append(t)
			for t in hit:_magic_hit(i,t,15+extra)
		"pustules":
			for t in state.fighters.size():
				if t==i or not living(state.fighters[t]):continue
				var dist=distance(p.cell,state.fighters[t].cell)
				if dist<=2:
					var wounded=_magic_hit(i,t,15 if dist==1 else 10)
					if wounded and balance_table(die()+2,int(definition(state.fighters[t]).size))>=0:_knock(t,false)
		"fear":
			for t in state.fighters.size():
				var b=state.fighters[t]
				if b.team!=p.team and living(b) and distance(p.cell,b.cell)<=5 and in_view(b,p.cell):b.done=true;b.guarding=false
				if b.team!=p.team and living(b) and distance(p.cell,b.cell)==1:_knock(t,false)
		"age":
			if j!=-1:state.fighters[j].permanent+=die()
		"summon":
			if not state.fighters.any(func(t):return t.character=="golem" and t.alive):
				var g=p.duplicate(true);g.character="golem";g.name="Golem di "+p.name;g.cell=k;g.current="advance";g.previous="";g.hp=40;g.max_hp=40;g.magic=0;g.fatigue=0;g.permanent=0;g.lost=[];g.owner=i;g.done=true;g.alive=true;state.fighters.append(g)
		"plague":
			if j!=-1:state.fighters[j].plague=i
	_finish_action(i,m,false,int(s.facing))
func _magic_hit(i: int,j: int,power: int) -> bool:
	var m={"id":"magic","attack":power,"imbalance":null}
	return _combat(i,j,m,true)
func _effect(i: int,k: String,kind: String,limit: int) -> void:
	var existing=state.effects.filter(func(e):return e.kind==kind)
	if existing.size()>=limit:return
	state.effects.append({"kind":kind,"cell":k,"owner":i,"facing":int(state.fighters[i].facing),"created":int(state.turn)})
func _cross_effects(i: int) -> void:
	var p=state.fighters[i]
	for e in state.effects.duplicate():
		if e.cell!=p.cell:continue
		if e.kind=="wall":_hurt(i,die(),false);p.burning=true
		if e.kind=="livingfire":_magic_hit(int(e.owner),i,15);p.burning=true
		if e.kind=="abyss":_abyss(i,e)
	for other in state.fighters:
		if other.alive and other.team==p.team and other.plague>=0 and distance(other.cell,p.cell)==1:p.plague=other.plague
func _abyss(i: int,e: Dictionary) -> void:
	var p=state.fighters[i]
	var ad=die();note("%s sull'abisso: dado %d." % [p.name,ad])
	if ad in e.get("numbers",[1,2]):_kill(i)
	else:
		_knock(i,false)
		for d in 6:
			var dest=neighbor(p.cell,d)
			if not blocked(dest,i):p.cell=dest;break
func _frog_turn(p: Dictionary) -> void:
	var d=die()
	if d<=2:note(p.name+" (ranocchio): CRAAA!")
	elif d<=4:
		var here=p.cell
		for step in 3:
			here=neighbor(here,int(p.facing));var j=at(here)
			if j!=-1:state.fighters[j].done=true;note("Lo sputacchio del ranocchio fa perdere la mossa a "+state.fighters[j].name+".");break
	else:
		for step in die():
			var next=neighbor(p.cell,int(p.facing));var j=at(next)
			if j!=-1:_knock(j,false);break
			if not cells.has(next):break
			p.cell=next
	p.done=true
func finish_turn() -> void:
	if state.phase in ["finished","round_result","campaign_finished"]:return
	# End-of-turn recovery is determined by the piece that remains on the board.
	for i in state.fighters.size():
		var p=state.fighters[i]
		if not p.alive:continue
		var m=move(p)
		if m.get("rest",false):
			var rd=die();var amount=int(definition(p).recovery[rd-1]);p.fatigue=maxi(0,int(p.fatigue)-amount)
			if amount>0 and int(p.fatigue)+amount>0:note("%s riposa: dado %d, recupera %d fatica." % [p.name,rd,mini(amount,99)])
		if p.current=="concentrate":
			var d=die();p.magic+=1 if d==1 else (3 if d==6 else 2)
		if p.burning:
			var d=die()
			if d>=5:p.burning=false;note(p.name+": il fuoco si spegne.")
			else:_hurt(i,2 if d==1 else 1,false)
		if p.plague>=0:_hurt(i,2,false)
		if p.character=="golem" and p.get("owner",-1)>=0:
			var owner=state.fighters[p.owner]
			if not owner.alive or owner.current!="summon":_kill(i)
	var remaining=[]
	for e in state.effects:
		if not state.fighters[e.owner].alive:continue
		if e.kind in ["wall","abyss"]:
			if die()>=5:continue
		remaining.append(e)
	state.effects=remaining
	if state.phase in ["finished","round_result","campaign_finished"]:return
	state.upkeep=[]
	for e in state.effects:
		if e.kind in ["vortex","livingfire"]:state.upkeep.append(state.effects.find(e))
	if not state.upkeep.is_empty():state.phase="upkeep";state.active=int(state.effects[state.upkeep[0]].owner)
	else:begin_turn()
	_check_end()
func advance_effect(facing: int) -> bool:
	if state.phase!="upkeep":return false
	var e=state.effects[state.upkeep.pop_front()];e.facing=posmod(facing,6)
	for step in die():
		var next=neighbor(e.cell,e.facing)
		if not cells.has(next):break
		e.cell=next
		var victim=at(next)
		if victim!=-1:
			if e.kind=="vortex":_knock(victim,true)
			else:_magic_hit(int(e.owner),victim,15);state.fighters[victim].burning=true
	if state.upkeep.is_empty():begin_turn()
	else:state.active=int(state.effects[state.upkeep[0]].owner)
	return true

func public_state() -> Dictionary:
	var out=snapshot()
	out.plans={}
	out.bag=[]
	out.erase("rng_state")
	if out.phase=="handicap":
		out.campaign.handicaps={}
		out.campaign.totals={}
	# During planning, publish only which seats have committed, not their moves.
	out.ready=state.plans.keys()
	return out

const VICTORY_POINTS={3:10,4:15,5:20,6:20,7:25,8:25,9:30,10:30,11:35,12:35,13:40,14:50}
func start_campaign(roster: Array,seed_n: int=1) -> void:
	new_game(roster,"libero",seed_n,0)
	var players=[]
	for i in roster.size():
		players.append({"name":roster[i].get("name","Giocatore %d"%(i+1)),"points":VICTORY_POINTS.get(roster.size(),10),"controller":roster[i].controller,"seat":roster[i].get("seat",i),"character":"","handicap":0})
	state.scenario="bloodmaster";state.campaign={"round":1,"players":players,"pool":[],"handicaps":{},"totals":{},"card":0,"bid":0,"bidder":-1,"passed":[],"scored":false}
	_campaign_round()
func _campaign_round() -> void:
	state.fighters.resize(state.campaign.players.size())
	var c=state.campaign;c.pool=[];c.handicaps={};c.totals={};c.card=0;c.bid=0;c.bidder=-1;c.passed=[];c.scored=false
	var available=[]
	for id in catalog:
		if not catalog[id].kind in ["skeleton","golem"]:available.append(id)
	for i in c.players.size():
		var n=rng.randi_range(0,available.size()-1);c.pool.append(available[n]);available.remove_at(n)
		c.players[i].character="";c.players[i].handicap=0
		state.fighters[i].cell="";state.fighters[i].alive=true;state.fighters[i].done=false
	for id in c.pool:c.totals[id]=0
	state.phase="handicap";state.active=0;state.effects=[];state.turn=0
	note("BLOOD MASTER · Round %d di 3 · assegnate gli handicap in segreto."%c.round)
func handicap_choices(i: int,picks: Array) -> bool:
	if state.phase!="handicap" or i!=int(state.active) or picks.size()!=3:return false
	if picks[0]==picks[1] or picks[0]==picks[2] or picks[1]==picks[2]:return false
	var c=state.campaign
	for id in picks:
		if not id in c.pool:return false
	c.handicaps[str(i)]=picks.duplicate()
	for j in 3:c.totals[picks[j]]+=3-j
	state.active+=1
	if state.active>=c.players.size():
		state.phase="auction";state.active=0
		note("Handicap rivelati: "+str(c.totals))
	return true
func auction_bid(i: int,amount: int) -> bool:
	if state.phase!="auction" or i!=int(state.active):return false
	var c=state.campaign;var p=c.players[i]
	if p.character!="" or amount<0:return false
	if amount>0:
		if amount<=int(c.bid) or amount>int(p.points):return false
		c.bid=amount;c.bidder=i;c.passed=[];note("%s offre %d per %s."%[p.name,amount,catalog[c.pool[c.card]].name])
	else:
		if not i in c.passed:c.passed.append(i)
	var eligible=[]
	for j in c.players.size():
		if c.players[j].character=="" and not j in c.passed and j!=int(c.bidder):eligible.append(j)
	if eligible.is_empty():
		var winner=int(c.bidder);var cost=int(c.bid)
		if winner<0:
			var unassigned=[]
			for j in c.players.size():
				if c.players[j].character=="":unassigned.append(j)
			winner=unassigned[rng.randi_range(0,unassigned.size()-1)];cost=2
		c.players[winner].character=c.pool[c.card];c.players[winner].points-=cost;c.players[winner].handicap=c.totals[c.pool[c.card]]
		note("%s ottiene %s per %d punti."%[c.players[winner].name,catalog[c.pool[c.card]].name,cost])
		c.card+=1;c.bid=0;c.bidder=-1;c.passed=[]
		if c.card>=c.pool.size():_campaign_battle();return true
		for j in c.players.size():
			if c.players[j].character=="":state.active=j;break
	else:
		for offset in range(1,c.players.size()+1):
			var j=(i+offset)%c.players.size()
			if j in eligible:state.active=j;break
	return true
func _campaign_battle() -> void:
	var c=state.campaign.duplicate(true);var roster=[]
	for i in c.players.size():
		var p=c.players[i];var d=catalog[p.character];var team=int(d.team)
		if team<0:
			var pos=c.pool.find(p.character);var prev=c.pool[pos-1 if pos>0 else c.pool.size()-1]
			team=1-maxi(0,int(catalog[prev].team))
		roster.append({"character":p.character,"team":team,"controller":p.controller,"seat":p.seat,"name":p.name+" · "+d.name})
	var seed_n=rng.randi();new_game(roster,"libero",seed_n,0);state.campaign=c;state.scenario="bloodmaster"
	for i in state.fighters.size():
		if definition(state.fighters[i]).mage:state.fighters[i].magic=int(c.players[i].handicap)
	note("Round %d · i sopravvissuti guadagnano punti vittoria meno i propri handicap."%c.round)
func _score_campaign() -> void:
	var c=state.campaign
	if c.is_empty() or c.scored:return
	c.scored=true
	var prize=int(VICTORY_POINTS.get(c.players.size(),10))
	for i in c.players.size():
		var p=state.fighters[i]
		if living(p) and not p.pieces:c.players[i].points+=prize-int(c.players[i].handicap)
	state.phase="round_result"
func next_campaign_round() -> bool:
	if state.phase!="round_result":return false
	if int(state.campaign.round)>=3:state.phase="campaign_finished";return true
	state.campaign.round+=1;_campaign_round();return true

func opportunity(id: String) -> bool:
	if state.phase!="opportunity":return false
	var pending=state.pending;var i=int(pending.reactors[0]);var p=state.fighters[i]
	if id=="pass":
		pending.reactors.pop_front()
		if pending.reactors.is_empty():state.phase="acting";state.active=int(pending.resume);state.pending={}
		return true
	if id=="guard" and not p.guarding:return false
	if id!="guard":
		if p.current!="concentrate" or not id in legal_moves(i) or not move(p,id).get("spell",false):return false
	state.interrupt_stack.append(int(pending.resume));state.active=i;state.phase="acting";state.pending={}
	p.previous=p.current;p.current=id;p.guarding=false
	return true
func regenerate(i: int) -> bool:
	if state.phase!="acting":return false
	var actor=int(state.active);var p=state.fighters[actor]
	if p.current!="concentrate" or i<0 or i>=state.fighters.size():return false
	var target=state.fighters[i]
	if not target.pieces:return false
	var cost=die()
	if p.magic>=cost:
		p.magic-=cost;target.pieces=false;target.current="guard";target.team=p.team;target.controller=p.controller;target.seat=p.seat;target.owner=actor;target.done=true
		note("%s rigenera %s spendendo %d punti magia."%[p.name,target.name,cost])
	else:note("Rigenerazione: servono %d punti magia; %s non ne ha abbastanza."%[cost,p.name])
	_finish_action(actor,move(p),false,int(p.facing));return true
