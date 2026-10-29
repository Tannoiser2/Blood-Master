extends SceneTree
func _init() -> void:
	var r=BloodRules.new()
	for id in ["zenyo","gascor","ut","shannon","kylvia","anteos","shaara","zak","nuchra","ramok"]:print("%-10s %d"%[id,roundi(BloodForge.points(r.catalog[id]))])
	for arma in BloodForge.ARMI:
		var t=BloodForge.default_traits();t.arma=arma
		print("forgia %-9s %d"%[arma,roundi(BloodForge.points(BloodForge.build(t)))])
	quit()
