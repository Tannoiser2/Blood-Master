extends SceneTree
# Schivata all'indietro: il corpo resta rivolto in avanti e la camminata va a ritroso
func _init():call_deferred("run")
func run():
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	main.roster=[{"character":"gascor","team":0,"controller":"human","seat":0},{"character":"anteos","team":1,"controller":"human","seat":1}]
	main.minis_3d=true;main.house["scenery"]=false;main.house["restore"]=false;main.house["zoc"]=false;main._start_local()
	main.game.deploy("3,8",0);main.game.deploy("3,-2",3)
	var g=main.game;var b=main.board3d
	for k in ["rise"]:pass
	g.state.fighters[0].cell="4,3";g.state.fighters[0].facing=0;g.state.fighters[1].cell="1,0"
	main._refresh();b.sync();await create_timer(2.0).timeout
	var p=g.state.fighters[0];var back=BloodRules.neighbor("4,3",3)
	# una mossa di camminata verso l'esagono dietro (come la camminata prima di un'azione sul posto)
	var t={"i":0,"clip":"Camminata","from":b.cell_pos("4,3"),"to":b.cell_pos(back),"yaw":b.facing_yaw(0),"facing":0,"delay":0.0,"move":"advance","strike":false}
	var info=b.minis[0];var y0=info.pivot.rotation.y
	var dur=b._run_track(t,info,false)
	var neg=0;var maxturn=0.0
	for k in 12:
		await create_timer(dur/12.0).timeout
		if info.ap.speed_scale<0:neg+=1
		maxturn=maxf(maxturn,absf(angle_difference(y0,info.pivot.rotation.y)))
	print("campioni all'indietro ",neg,"/12  rotazione massima ",snappedf(rad_to_deg(maxturn),1)," gradi")
	assert(neg>=6 and rad_to_deg(maxturn)<20,"non cammina all'indietro")
	print("BACK STEP OK")
	quit()
