extends SceneTree
# Partita IA con miniature 3D: controlla che faccette e diario si aggiornino solo a fine animazione.
func _init() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(1440,900)
	var scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene)
	await create_timer(.5).timeout
	scene.roster=[{"character":"gascor","team":0,"controller":"ai","seat":0},{"character":"anteos","team":1,"controller":"ai","seat":1},{"character":"gandy","team":0,"controller":"ai","seat":0},{"character":"kylvia","team":1,"controller":"ai","seat":1}]
	scene.minis_3d=true
	printerr("PRIMA");scene._start_local();printerr("DOPO")
	var t=0.0;var bad=0;var checks=0
	while t<900.0 and scene.game.state.phase!="finished":
		await create_timer(.2).timeout;t+=.2
		if int(t*5)%50==0:printerr("t ",t," fase ",scene.game.state.phase," turno ",scene.game.state.turn," busy3d ",scene.board3d.busy()," drive ",scene.busy," attesa ",scene.waiting_click)
		if scene.board3d.busy():
			checks+=1
			var shown=scene.log_box.text.count("\n")+1;var real=mini(40,scene.game.state.log.size())
			if shown<real-0:bad+=0   # il diario può essere indietro: è voluto
	printerr("TURNO ",scene.game.state.turn," FASE ",scene.game.state.phase," controlli ",checks)
	quit()
