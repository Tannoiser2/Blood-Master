extends SceneTree
# Eroi forgiati di prova (tratti diversi) salvati in JSON per il collaudo con tests/balance_variants.gd
func _init() -> void:
	var sets=[["spada",3,2,2,2,"equilibrato","piccolo","media"],["ascia",5,3,1,3,"aggressivo","nessuno","pesante"],["lancia",3,2,2,1,"prudente","nessuno","leggera"],
		["bastone",2,2,3,2,"astuto","nessuno","nessuna"],["pugnale",2,1,3,2,"aggressivo","piccolo","leggera"],["due_armi",3,3,2,2,"aggressivo","nessuno","media"],
		["arco",1,2,2,1,"prudente","nessuno","leggera"],["spada",4,3,1,3,"prudente","grande","pesante"],["lancia",4,2,1,2,"aggressivo","grande","media"],["ascia",3,2,2,2,"equilibrato","nessuno","leggera"],
		["bastone",3,3,2,3,"aggressivo","nessuno","nessuna"],["arco",2,1,3,2,"astuto","nessuno","nessuna"]]
	var out={};var n=0
	for s in sets:
		var t=BloodForge.default_traits()
		t.arma=s[0];t.stazza=s[1];t.forza=s[2];t.agilita=s[3];t.resistenza=s[4];t.carattere=s[5];t.scudo=s[6];t.armatura=s[7]
		t.id="v_forged%02d_%s"%[n,s[0]];t.name=t.id;n+=1
		var d=BloodForge.build(t);out[d.id]=d
		print("PUNTI %s %.1f"%[d.id,BloodForge.points(d)])
	var f=FileAccess.open(OS.get_environment("OUT"),FileAccess.WRITE);f.store_string(JSON.stringify(out))
	quit()
