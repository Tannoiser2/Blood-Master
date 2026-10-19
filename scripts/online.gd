class_name BloodOnline
extends Node
signal updated
signal lobby_updated(room: Dictionary)
signal failed(message: String)
var net: BloodNet
var game: BloodRules
var code=""
var seat=-1
var host=false
var frame=0
var commits: Dictionary={}
var secrets: Dictionary={}
var revealed: Dictionary={}
var local_lock: Dictionary={}
var ready_seats: Array=[]
var room_data: Dictionary={}
var seats: Dictionary={}
var in_lobby=true
var active=false
var polling=false
var poll_clock=0.0
var heartbeat_clock=0.0
var seen_frame=-1
var processing=false
var apply_command: Callable
var last_submit_frame=-1

func _ready() -> void:
	net=BloodNet.new();add_child(net)
func create(player: String,roster: Array,scenario: String) -> bool:
	var human=[]
	for i in roster.size():
		if roster[i].controller=="human":human.append(i)
	if human.size()<2:failed.emit("Per una partita online scegli almeno due posti Persona.");return false
	code=await net.create_room(player,human)
	if code=="":failed.emit(net.last_error);return false
	seat=human[0];host=true
	var cfg={"kind":"blood-master","version":BloodRules.VERSION,"roster":roster,"scenario":scenario,"frame":0}
	var r=await net.db_put("rooms/%s/game"%code,cfg)
	if r.code!=200:failed.emit(net.last_error);return false
	net.remember_room(code,seat);active=true;in_lobby=true;return true
func join(player: String,room_code: String) -> bool:
	if room_code.length()!=4 or not room_code.is_valid_identifier():failed.emit("Inserisci le quattro lettere della stanza.");return false
	code=room_code;seat=await net.join_room(code,player)
	if seat<0:failed.emit(net.last_error if net.last_error!="" else "Stanza non disponibile o senza posti liberi.");return false
	host=net.last_room.get("host","")==net.uid;room_data=net.last_room
	net.remember_room(code,seat);active=true;in_lobby=room_data.get("status","")=="lobby"
	if host and not in_lobby:
		if not _restore_host():failed.emit("Il salvataggio dell’organizzatore non è disponibile su questo dispositivo.");active=false;return false
	return true
func start() -> bool:
	if not host:return false
	var room=await net.room(code);var cfg=room.get("game",{})
	seats=BloodNet._as_dict(room.get("seats",{}));var roster=cfg.roster.duplicate(true)
	for i in roster.size():
		roster[i].seat=i
		if roster[i].controller=="human":
			if not seats.has(str(i)):failed.emit("Manca ancora un giocatore. Attendi che tutti i posti Persona siano occupati.");return false
			roster[i].name=seats[str(i)].name+" · "+game.catalog[roster[i].character].name
	if cfg.scenario=="bloodmaster":game.start_campaign(roster,int(Time.get_unix_time_from_system()))
	else:game.new_game(roster,cfg.scenario,int(Time.get_unix_time_from_system()))
	in_lobby=false;frame=1
	var ok=await net.start_room(code,_packet())
	if ok:_save_host();updated.emit()
	return ok
func _process(delta: float) -> void:
	if not active:return
	poll_clock+=delta;heartbeat_clock+=delta
	if poll_clock>=1.25 and not polling:
		poll_clock=0;_poll()
func _poll() -> void:
	polling=true
	if heartbeat_clock>=20:
		heartbeat_clock=0;await net.heartbeat(code,seat)
	var room=await net.room(code)
	if room.is_empty():polling=false;failed.emit("Connessione sospesa. Riprovo automaticamente; tieni aperta la pagina.");return
	room_data=room;seats=BloodNet._as_dict(room.get("seats",{}))
	if room.get("status","")=="lobby":lobby_updated.emit(room);polling=false;return
	in_lobby=false
	var packet=room.get("game",{})
	if not packet is Dictionary or packet.get("kind","")!="blood-master":polling=false;return
	if int(packet.get("version",-1))!=BloodRules.VERSION:failed.emit("Versioni del gioco diverse: ricarica la pagina prima di entrare.");active=false;polling=false;return
	if not host and packet.get("state_json") is String:
		frame=int(packet.frame);ready_seats=packet.get("ready",[])
		if seen_frame!=frame or game.state.get("ready",[])!=ready_seats:
			seen_frame=frame;game.restore(JSON.parse_string(packet.state_json));game.state.ready=ready_seats;updated.emit()
		if packet.get("reveal",false):await _reveal_local()
	if host:await host_tick()
	polling=false
func _packet() -> Dictionary:
	var s=game.public_state()
	if not commits.is_empty():s.ready=commits.keys()
	var opening=not commits.is_empty() and _all_committed() and game.state.phase=="planning"
	if opening:s.phase="net_reveal"
	return {"kind":"blood-master","version":BloodRules.VERSION,"frame":frame,"state_json":JSON.stringify(s),"ready":commits.keys(),"reveal":opening}
func _publish() -> bool:
	_save_host()
	var r=await net.db_put("rooms/%s/game"%code,_packet())
	if r.code!=200:failed.emit("Salvataggio online non riuscito: "+net.last_error);return false
	ready_seats=commits.keys();updated.emit();return true
func submit(c: Dictionary) -> void:
	if in_lobby or not active:return
	if not host and last_submit_frame==frame:return
	if c.type=="plan":
		var salt=Crypto.new().generate_random_bytes(24).hex_encode()
		var fighter=int(c.fighter);var payload={"fighter":fighter,"move":c.move,"salt":salt}
		local_lock[str(game.state.turn)]=payload
		_save_local()
		c={"type":"commit","fighter":fighter,"hash":_hash(payload)}
	if host:
		while processing:await get_tree().process_frame
		processing=true
		await _receive(seat,c)
		processing=false
	else:
		if last_submit_frame==frame:return
		var ok=await net.post_choice(code,frame,seat,c)
		if ok:last_submit_frame=frame
		else:failed.emit("Invio non riuscito. "+net.last_error)
func _hash(p: Dictionary) -> String:
	return (str(int(p.fighter))+"|"+str(p.move)+"|"+str(p.salt)).sha256_text()
func _all_committed() -> bool:
	for i in game.needs_plan():
		if not commits.has(str(i)):return false
	return true
func _reveal_local() -> void:
	var turn=str(game.state.turn)
	if not local_lock.has(turn):_load_local()
	if not local_lock.has(turn):failed.emit("La scelta segreta non è disponibile: torna nella scheda originale della partita.");return
	if last_submit_frame==frame:return
	var payload=local_lock[turn].duplicate();payload.type="reveal_plan"
	var ok=await net.post_choice(code,frame,seat,payload)
	if ok:last_submit_frame=frame
func _owns(sender: int,i: int) -> bool:
	if i<0 or i>=game.state.fighters.size():return false
	var p=game.state.fighters[i]
	if p.get("controller_by",-1)>=0:p=game.state.fighters[p.controller_by]
	return int(p.seat)==sender
func _receive(sender: int,c: Dictionary) -> bool:
	if c.get("type","")=="commit":
		var i=int(c.get("fighter",-1))
		if game.state.phase!="planning" or not _owns(sender,i) or commits.has(str(i)) or not str(c.get("hash","")).length()==64:return false
		commits[str(i)]=str(c.hash)
		if sender==seat:
			var lock=local_lock.get(str(game.state.turn),{})
			if not lock.is_empty():secrets[str(i)]=lock
		if _all_committed():frame+=1
		await _publish();return true
	if c.get("type","")=="reveal_plan":
		var i=int(c.get("fighter",-1))
		if not _owns(sender,i) or not _all_committed() or revealed.has(str(i)):return false
		if commits.get(str(i),"")!=_hash(c) or not c.move in game.legal_moves(i):return false
		revealed[str(i)]=true;game.plan(i,c.move)
		await _publish();return true
	var acting=int(game.state.active)
	if game.state.phase in ["reaction","opportunity"]:acting=int(game.state.pending.reactors[0])
	if game.state.phase=="stumble":acting=int(game.state.pending.actor)
	if c.get("type","")=="guard_prepare":acting=int(c.get("fighter",-1))
	if c.get("type","")=="next_round":
		if sender!=seat or not host:return false
		if apply_command.call(c):frame+=1;await _publish();return true
	if c.get("type","")=="draw":
		if sender!=seat or not host or game.state.phase!="draw":return false
	elif not _owns(sender,acting):return false
	if apply_command.call(c):frame+=1;await _publish();return true
	return false
func host_tick() -> void:
	if not host or in_lobby or processing or not active:return
	processing=true
	var incoming=await net.choices(code,frame)
	for k in incoming:
		var c=incoming[k]
		if c is Dictionary:
			var previous=frame
			await _receive(int(k),c)
			if frame!=previous:break
	var changed=false
	var s=game.state
	if s.phase=="planning":
		for i in game.needs_plan():
			var p=s.fighters[i]
			if p.controller=="ai" and not commits.has(str(i)):
				var payload={"fighter":i,"move":BloodAI.choose_move(game,i),"salt":Crypto.new().generate_random_bytes(24).hex_encode()}
				commits[str(i)]=_hash(payload);secrets[str(i)]=payload;changed=true
		if _all_committed():
			if changed:frame+=1
			for k in secrets:
				if not revealed.has(k) and commits.has(k):game.plan(int(k),secrets[k].move);revealed[k]=true;changed=true
			if game.needs_plan().is_empty():game.reveal();commits={};secrets={};revealed={};frame+=1;changed=true
	else:
		var i=int(s.active)
		if s.phase in ["reaction","opportunity"]:i=int(s.pending.reactors[0])
		if s.phase=="stumble":i=int(s.pending.actor)
		var ai=i>=0 and s.fighters[i].controller=="ai"
		if s.phase=="handicap" and ai:changed=game.handicap_choices(i,s.campaign.pool.slice(0,3))
		elif s.phase=="auction" and ai:
			var c=s.campaign;var price=mini(int(c.players[i].points),maxi(2,int(c.players[i].points)/3))
			changed=game.auction_bid(i,int(c.bid)+1 if c.bid<price else 0)
		elif s.phase=="deploy" and ai:
			var team=int(s.fighters[i].team);var entries=game.entry_cells(team);changed=game.deploy(entries[i%entries.size()],0 if team==0 else 3)
		elif s.phase=="acting" and ai:changed=game.act(BloodAI.command(game,i))
		elif s.phase=="opportunity" and ai:changed=game.opportunity(BloodAI.opportunity(game,i))
		elif s.phase=="reaction" and ai:changed=game.react(BloodAI.reaction(game,i))
		elif s.phase=="stumble" and ai:changed=game.choose_stumble(s.pending.path.back())
		elif s.phase=="upkeep" and ai:changed=game.advance_effect(int(s.fighters[i].facing))
		elif s.phase=="draw":
			if not s.fighters.any(func(p):return p.guarding and p.controller=="human"):game.draw_next();changed=true
		if changed:frame+=1
	if changed:await _publish()
	processing=false
func _save_host() -> void:
	var f=FileAccess.open("user://host_"+code+".json",FileAccess.WRITE)
	if f:f.store_string(JSON.stringify({"state":game.snapshot(),"frame":frame,"commits":commits,"secrets":secrets,"revealed":revealed}))
func _restore_host() -> bool:
	var path="user://host_"+code+".json"
	if not FileAccess.file_exists(path):return false
	var s=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not s is Dictionary:return false
	game.restore(s.state);frame=int(s.frame);commits=s.commits;secrets=s.secrets;revealed=s.revealed;return true
func _save_local() -> void:
	var data=JSON.stringify(local_lock)
	if OS.has_feature("web"):JavaScriptBridge.eval("sessionStorage.setItem('bm_plans_%s', %s)"%[code,JSON.stringify(data)])
	else:
		var f=FileAccess.open("user://plans_"+code+".json",FileAccess.WRITE)
		if f:f.store_string(data)
func _load_local() -> void:
	var text=""
	if OS.has_feature("web"):
		var v=JavaScriptBridge.eval("sessionStorage.getItem('bm_plans_%s') || '{}'"%code);text=str(v)
	elif FileAccess.file_exists("user://plans_"+code+".json"):text=FileAccess.get_file_as_string("user://plans_"+code+".json")
	var parsed=JSON.parse_string(text)
	if parsed is Dictionary:local_lock=parsed
