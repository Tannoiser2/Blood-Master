extends SceneTree
# Caratteristiche (BloodForge.features) dei personaggi ufficiali, delle varianti (VARS) e di alcuni forgiati
func _init() -> void:
	if OS.get_environment("VARS")!="":BloodRules.extra_defs=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("VARS")))
	var r=BloodRules.new()
	for id in r.catalog:
		if r.catalog[id].kind in ["golem","skeleton"]:continue
		print("FEAT ",JSON.stringify({"id":id,"f":BloodForge.features(r.catalog[id],r.catalog)}))
	if OS.get_environment("FORGE")!="":
		for arma in BloodForge.ARMI:
			var t=BloodForge.default_traits();t.arma=arma;t.name="prova_"+arma
			if arma=="ascia":t.stazza=5;t.forza=3;t.agilita=1;t.resistenza=3;t.armatura="pesante"
			if arma=="bastone":t.stazza=2;t.agilita=3;t.armatura="nessuna"
			if arma=="arco":t.stazza=1;t.resistenza=1
			if arma=="spada":t.armatura="media"
			var d=BloodForge.build(t)
			print("FORGE ",arma," hp ",d.hp," size ",d.size," sprint ",d.sprint," ",d.sprints," armor ",d.armor)
			for m in d.moves.values():print("   %-10s att %-4s def %-3s sec %-3s fat %s imb %s R%s G%s B%s"%[m.id,m.attack,m.defense,m.secondary,m.fatigue,m.imbalance,m.red,m.green,m.blue])
	quit()
