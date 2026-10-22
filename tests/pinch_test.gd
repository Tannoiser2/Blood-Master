extends SceneTree
# Zoom a pizzico con due dita su mappa 2D e 3D
func _init():call_deferred("run")
func touch(b,i,pos,pressed):
	var e=InputEventScreenTouch.new();e.index=i;e.position=pos;e.pressed=pressed;b._gui_input(e)
func drag(b,i,pos):
	var e=InputEventScreenDrag.new();e.index=i;e.position=pos;b._gui_input(e)
func run():
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	main.roster=[{"character":"gascor","team":0,"controller":"human","seat":0},{"character":"anteos","team":1,"controller":"human","seat":1}]
	main._start_local();await create_timer(1.0).timeout
	for b in [main.board,main.board3d]:
		var z0=b.zoom
		touch(b,0,Vector2(400,400),true);touch(b,1,Vector2(500,400),true)
		for k in 10:drag(b,1,Vector2(500+k*10,400))
		var z1=b.zoom
		for k in 10:drag(b,1,Vector2(590-k*15,400))
		touch(b,1,Vector2(450,400),false);touch(b,0,Vector2(400,400),false)
		print(b.name," zoom ",z0," -> ",snappedf(z1,.01)," -> ",snappedf(b.zoom,.01))
		assert(z1>z0 and b.zoom<z1,"pizzico non funziona")
	print("PINCH OK")
	quit()
