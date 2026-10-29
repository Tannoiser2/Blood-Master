extends SceneTree
# Eroi con magie diverse per tarare il prezzo degli incantesimi (OUT=file.json)
func _init() -> void:
	var sets={"v_sp_nessuna":[1,[]],"v_sp_fulmine":[2,["lightning"]],"v_sp_palla":[2,["fireball"]],"v_sp_difesa":[3,["shield","heal"]],
		"v_sp_paura":[3,["fear","pustules"]],"v_sp_quattro":[5,["fireball","lightning","fear","wall"]],"v_sp_sonno":[2,["sleep"]],"v_sp_gorgo":[2,["vortex"]],
		"v_sp_controllo":[2,["control"]],"v_sp_golem":[2,["summon"]],"v_sp_abisso":[2,["abyss"]],"v_sp_bastone":[2,["firestaff"]]}
	var out={}
	for id in sets:
		var t=BloodForge.default_traits();t.id=id;t.name=id;t.INT=sets[id][0];t.spells=sets[id][1]
		var d=BloodForge.build(t);out[id]=d
		print("PUNTI %s %.1f"%[id,BloodForge.points(d)])
	var f=FileAccess.open(OS.get_environment("OUT"),FileAccess.WRITE);f.store_string(JSON.stringify(out))
	quit()
