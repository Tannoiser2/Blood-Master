extends SceneTree
var checks=0
var failures=0
func check(ok: bool,why: String) -> void:
	checks+=1
	if not ok:push_error(why);failures+=1
func _init() -> void:
	var r=BloodRules.new()
	check(r.catalog.size()==17,"Catalog completeness")
	check(BloodRules.combat_table(10).wounds==0,"10 misses")
	check(BloodRules.combat_table(21).wounds==11,"21 wounds")
	check(not BloodRules.combat_table(25).unbalance,"25 does not unbalance")
	check(BloodRules.combat_table(31).wounds==16,"31 max wounds")
	check(BloodRules.balance_table(7,1)==0,"Balance zero is still unbalanced")
	check(BloodRules.balance_table(7,2)==-1,"Balance no effect")
	check(BloodRules.balance_table(17,10)==0,"Balance upper limit")
	r.new_game([{"character":"gandy","team":0},{"character":"thorn","team":1}],"libero",42)
	check(r.state.fighters[0].magic>=6 and r.state.fighters[0].magic<=11,"Initial magic is 5 + d6")
	r.state.fighters[0].magic=6
	r.state.fighters[0].cell="4,0";r.state.fighters[1].cell="4,-1"
	r.state.phase="acting";r.state.active=1;r.state.fighters[1].current="age"
	r.state.fighters[1].facing=3;r.state.fighters[0].current="concentrate"
	r.state.pending={"kind":"spell","actor":1,"target":"4,0","facing":3,"extra":0,"move":"age","reactors":[0]};r.state.phase="reaction"
	r.forced_dice=[2]
	check(r.react("counter"),"Counter accepted")
	check(not r.state.fighters[0].done,"Failed dispel does not consume action")
	check(r.state.fighters[0].magic==3,"Failed dispel still costs value")
	# Reset to isolate the successful dispel from transformation.
	r.state.fighters[0].frog=false;r.state.fighters[0].magic=6;r.state.fighters[0].done=false
	r.state.fighters[1].done=false;r.state.phase="reaction"
	r.state.pending={"kind":"spell","actor":1,"target":"4,0","facing":3,"extra":0,"move":"age","reactors":[0]}
	r.forced_dice=[6]
	check(r.react("counter"),"Successful counter accepted")
	check(r.state.fighters[0].done,"Successful dispel consumes action")
	check(r.state.fighters[0].permanent>0,"Successful counter adds no further ageing")
	check(not "counter" in r.reaction_options(0,3),"Used action cannot counter")
	r.new_game([{ "character":"gascor","team":0},{"character":"anteos","team":1}],"libero",42)
	r.state.fighters[0].cell="3,2";r.state.fighters[1].cell="3,1"
	check("3,1" in r.targets(0,"guard"),"Printed directional arrows permit frontal attacks")
	r.state.effects=[{"kind":"abyss","numbers":[1,2],"owner":0,"cell":"4,2"}]
	r.restore(JSON.parse_string(JSON.stringify(r.snapshot())))
	check(1 in r.state.effects[0].numbers,"Saved abyss dice retain integer membership")
	var net=BloodOnline.new()
	check(net._hash({"fighter":1,"move":"guard","salt":"sample"})==net._hash({"fighter":1.0,"move":"guard","salt":"sample"}),"Firebase numeric roundtrip preserves commitment")
	net.free()
	for roll in range(1,7):
		r.forced_dice=[roll]
		r.new_game([{ "character":"gandy","team":0}],"libero",42)
		check(r.state.fighters[0].magic==5+roll,"Initial magic uses each die result")
	print("PASS: %d checks" % checks)
	quit(1 if failures else 0)
