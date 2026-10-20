extends SceneTree
# Partita vera IA contro IA con le miniature 3D: verifica eventi, animazioni e replay.
func _init():call_deferred("run")
func run():
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	# BM_ROSTER="ut:0,shannon:0,nuchra:1,ramok:1" per provare altri personaggi
	var spec=OS.get_environment("BM_ROSTER")
	if spec=="":spec="gascor:0,anteos:1"
	main.roster=[]
	for part in spec.split(","):
		var kv=part.split(":");main.roster.append({"character":kv[0],"team":int(kv[1]),"controller":"ai","seat":main.roster.size()})
	main.minis_3d=true;main.speed=.05
	main._start_local()
	var t=0.0
	while t<400.0 and main.game.state.phase!="finished":
		await create_timer(.5).timeout;t+=.5
	var b=main.board3d
	print("FASE ",main.game.state.phase," TURNO ",main.game.state.turn," PASSI ANIMATI ",b.history.size()," MINIATURE ",b.minis.size())
	var clips={}
	for step in b.history:
		for tr in step:
			if tr.has("clip"):clips[tr.clip]=clips.get(tr.clip,0)+1
	print("CLIP USATE ",clips)
	for i in b.minis:print(main.game.state.fighters[i].name," modello 3D: ",b.minis[i].model!=null," cella ",main.game.state.fighters[i].cell)
	assert(b.history.size()>3,"Troppo pochi passi animati")
	assert(b.minis.size()>=main.roster.size(),"Miniature mancanti")   # più i golem evocati
	for i in b.minis:
		if b.MODELS.has(main.game.state.fighters[i].character):assert(b.minis[i].model!=null,"Modello 3D mancante")
	b.replay()
	await create_timer(3.0).timeout
	assert(b.replaying,"Il replay non è partito")
	print("BOARD 3D TEST PASSED")
	quit()
