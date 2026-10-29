extends SceneTree
func _init() -> void:
	var r=BloodRules.new()
	for id in ["zenyo","gascor","ut","shannon","kylvia"]:print("%-10s %d"%[id,roundi(BloodForge.points(r.catalog[id]))])
	for arma in BloodForge.ARMI:
		var t=BloodForge.default_traits();t.arma=arma
		var d=BloodForge.build(t)
		print("forgia %-9s %d  pf %d stazza %d pedine %d"%[arma,roundi(BloodForge.points(d)),d.hp,d.size,d.moves.size()])
	var t=BloodForge.default_traits();t.INT=4;t.spells=["fireball","heal","shield"]
	var d=BloodForge.build(t);print("con 3 magie %d mago %s magie %s"%[roundi(BloodForge.points(d)),d.mage,d.moves.keys().filter(func(k):return d.moves[k].get("spell",false))])
	t.off=["kick","cleave"];print("senza calcio e fendente %d"%roundi(BloodForge.points(BloodForge.build(t))))
	var old={"name":"Vecchio","title":"x","stazza":3,"forza":2,"agilita":2,"resistenza":2,"carattere":"equilibrato","arma":"spada","scudo":"nessuno","armatura":"leggera"}
	print("vecchio eroe migrato %d"%roundi(BloodForge.points(BloodForge.build(old))))
	quit()
