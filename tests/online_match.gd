extends SceneTree
var h: BloodOnline
var g: BloodOnline
var failures=0
func _init() -> void:call_deferred("run")
func apply_h(c: Dictionary) -> bool:
	match c.type:
		"deploy":return h.game.deploy(c.target,int(c.facing))
		"act":return h.game.act(c)
		"opportunity":return h.game.opportunity(c.move)
		"react":return h.game.react(c.move)
		"stumble":return h.game.choose_stumble(c.target)
		"effect":return h.game.advance_effect(int(c.facing))
		"draw":h.game.draw_next();return true
	return false
func run() -> void:
	h=BloodOnline.new();h.game=BloodRules.new();h.apply_command=apply_h;root.add_child(h);h.set_process(false)
	OS.set_environment("BM_SESSION","user://live_match_host_%d.cfg"%Time.get_ticks_msec())
	var roster=[{"character":"gascor","team":0,"controller":"human","seat":0},{"character":"anteos","team":1,"controller":"human","seat":1}]
	if not await h.create("Prova completa host",roster,"libero"):push_error("Host create");quit(1);return
	g=BloodOnline.new();g.game=BloodRules.new();root.add_child(g);g.set_process(false)
	OS.set_environment("BM_SESSION","user://live_match_guest_%d.cfg"%Time.get_ticks_msec())
	if not await g.join("Prova completa ospite",h.code):push_error("Guest join");await h.net.close_room(h.code);quit(1);return
	if not await h.start():push_error("Start");await h.net.close_room(h.code);quit(1);return
	h.game.rng.seed=42
	var steps=0
	while h.game.state.phase!="finished" and steps<250:
		steps+=1
		await g._poll()
		var s=h.game.state
		if s.phase=="planning":
			for i in h.game.needs_plan():
				if not h.commits.has(str(i)):
					var peer=h if i==0 else g
					await peer.submit({"type":"plan","fighter":i,"move":BloodAI.choose_move(peer.game,i)})
		elif s.phase=="draw":
			await h.submit({"type":"draw"})
		else:
			var i=int(s.active)
			if s.phase in ["reaction","opportunity"]:i=int(s.pending.reactors[0])
			if s.phase=="stumble":i=int(s.pending.actor)
			if i>=0:
				var peer=h if i==0 else g;var c={}
				match s.phase:
					"deploy":c={"type":"deploy","target":h.game.entry_cells(i)[0],"facing":0 if i==0 else 3}
					"acting":c=BloodAI.command(peer.game,i);c.type="act"
					"opportunity":c={"type":"opportunity","move":BloodAI.opportunity(peer.game,i)}
					"reaction":c={"type":"react","move":BloodAI.reaction(peer.game,i)}
					"stumble":c={"type":"stumble","target":s.pending.path.back()}
					"upkeep":c={"type":"effect","facing":int(s.fighters[i].facing)}
				if not c.is_empty():await peer.submit(c)
		await h.host_tick()
		if steps%10==0:
			print("Online decisions ",steps," turn ",h.game.state.turn," phase ",h.game.state.phase," frame ",h.frame)
	await g._poll()
	var same=JSON.stringify(JSON.parse_string(JSON.stringify(h.game.public_state().fighters)))==JSON.stringify(JSON.parse_string(JSON.stringify(g.game.state.fighters)))
	print("END phase=",h.game.state.phase," same fighters=",same," decisions=",steps)
	if not same or h.game.state.phase!="finished":failures+=1
	await h.net.close_room(h.code)
	print("CLEANUP completed; failures=",failures)
	quit(1 if failures else 0)
