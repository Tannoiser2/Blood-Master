extends SceneTree
# Gorgo e fuoco vivente: si spostano esagono per esagono (posizioni intermedie) e le vittime reagiscono all'arrivo
func _init():call_deferred("run")
func run():
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	main.roster=[{"character":"gandy","team":0,"controller":"human","seat":0},{"character":"anteos","team":1,"controller":"human","seat":1}]
	main.minis_3d=true;main.house["scenery"]=false;main.house["restore"]=false;main._start_local()
	main.game.deploy("3,8",0);main.game.deploy("3,-2",3)
	var g=main.game;var b=main.board3d
	g.state.fighters[0].cell="1,4";g.state.fighters[1].cell="4,1"
	g._effect(0,"4,4","vortex",2)
	main._refresh();await create_timer(1.5).timeout
	var e=g.state.effects[0];var node=b.effect_by_id[str(e.id)]
	print("gorgo in ",e.cell," nodo a ",node.position.distance_to(b.cell_pos("4,4"))<.05)
	# spostamento a mano verso Anteos: 4,4 -> 4,3 -> 4,2 -> 4,1
	e.path=["4,4","4,3","4,2","4,1"];e.cell="4,1";g._knock(1,true)
	b.sync()
	var samples=[]
	for k in 8:
		await create_timer(.2).timeout
		samples.append(snappedf(node.position.distance_to(b.cell_pos("4,1")),.01))
	print("distanza dalla meta nel tempo ",samples)
	var mid=samples.filter(func(x):return x>.1 and x<2.0).size()
	print("posizioni intermedie: ",mid)
	assert(mid>=2,"il gorgo non scivola")
	print("EFFECT MOVE OK")
	quit()
