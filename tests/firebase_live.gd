extends SceneTree
var failures=0
func _init() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
	print(("PASS " if ok else "FAIL ")+text)
	if not ok:failures+=1
func run() -> void:
	OS.set_environment("BM_SESSION","user://test_host_%d.cfg"%Time.get_ticks_msec())
	var host=BloodNet.new();root.add_child(host)
	var code=await host.create_room("Collaudo Blood Master",[0,1])
	check(code!="","Create isolated test room")
	if code=="":print(host.last_error);quit(1);return
	OS.set_environment("BM_SESSION","user://test_guest_%d.cfg"%Time.get_ticks_msec())
	var guest=BloodNet.new();root.add_child(guest)
	var seat=await guest.join_room(code,"Collaudo ospite")
	check(seat==1,"Second identity joins seat 1")
	var ok=await host.start_room(code,{"kind":"blood-master","version":1,"state":{"turn":1},"frame":1})
	check(ok,"Host publishes game state")
	check(await guest.post_choice(code,1,1,{"type":"test","value":7}),"Guest submits own move")
	var moves=await host.choices(code,1)
	check(moves.get("1",{}).get("value",0)==7,"Host receives guest move")
	var foreign=await guest.db_put("rooms/%s/game"%code,{"kind":"intrusion"})
	check(foreign.code==401 or foreign.code==403,"Guest cannot overwrite host state")
	var duplicate=await guest.post_choice(code,1,1,{"type":"test","value":8})
	check(not duplicate,"Move cannot be overwritten")
	await host.close_room(code)
	var deleted=await host.room(code);check(deleted.is_empty(),"Test room removed")
	print("Firebase failures: ",failures)
	quit(1 if failures else 0)
