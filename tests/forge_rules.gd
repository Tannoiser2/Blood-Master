extends SceneTree
# Regole di costruzione delle pedine: il cast ufficiale e ogni eroe che la forgia può costruire le rispettano;
# ogni pedina ha un disegno (nessun posto vuoto nel nido d'ape); le varianti dei personaggi del gioco partono
# identiche all'originale, cambiano solo dove si ritocca e sopravvivono a salvataggio e ricarica.
var fails=0;var checks=0
func ok(cond: bool,what: String) -> void:
	checks+=1
	if not cond:fails+=1;print("FALLITO: ",what)
func _init() -> void:
	var rules=BloodRules.new()
	for id in rules.catalog:
		var pr=BloodForge.validate(BloodForge.official(id))
		ok(pr.is_empty(),"%s: %s"%[id,str(pr)])
	var n=0
	for arma in BloodForge.ARMI:
		for scudo in BloodForge.SCUDI:
			for arm in BloodForge.ARMATURE:
				for car in BloodForge.CARATTERI:
					var t=BloodForge.default_traits();t.arma=arma;t.scudo=scudo;t.armatura=arm;t.carattere=car;t.on=BloodForge.EXTRA_IDS.duplicate()
					t.FOR=1+n%5;t.DES=1+(n/5)%5;t.COS=1+(n/3)%5;n+=1
					var d=BloodForge.build(t)
					var pr=BloodForge.validate(d)
					ok(pr.is_empty(),"%s/%s/%s/%s: %s"%[arma,scudo,arm,car,str(pr)])
					for m in d.moves.values():
						ok(ResourceLoader.exists(str(m.texture)),"%s: la pedina %s non ha disegno (%s)"%[arma,m.id,m.texture])
					ok(BloodForge.points(d)>0.0,"valore in punti di %s/%s/%s/%s FOR %d DES %d COS %d: %.1f"%[arma,scudo,arm,car,t.FOR,t.DES,t.COS,BloodForge.points(d)])
	# un eroe oltre i 100 punti resta un eroe valido (si salva lo stesso)
	var strong=BloodForge.default_traits();strong.FOR=5;strong.DES=5;strong.COS=5;strong.arma="ascia";strong.armatura="pesante"
	var sd=BloodForge.build(strong)
	ok(BloodForge.points(sd)>BloodForge.BUDGET and BloodForge.validate(sd).is_empty(),"eroe oltre il budget: %d punti"%roundi(BloodForge.points(sd)))
	# varianti
	for id in rules.catalog:
		if str(rules.catalog[id].kind) in ["golem","skeleton"]:continue
		var base=BloodForge.official(id)
		var v=BloodForge.build_variant(id,{"id":"var_"+id,"name":"Prova"},{"hp":0,"moves":{}})
		ok(v.moves.size()==base.moves.size() and int(v.hp)==int(base.hp) and str(v.kind)==str(base.kind) and str(v.look)==id,"variante senza ritocchi di "+id)
		for mid in base.moves:
			var a=base.moves[mid];var b=v.moves[mid]
			ok(str(a.attack)==str(b.attack) and int(a.defense)==int(b.defense) and int(a.secondary)==int(b.secondary) and a.red==b.red and a.green==b.green and a.blue==b.blue,"%s/%s uguale all'originale"%[id,mid])
		ok(absf(BloodForge.points(v)-BloodForge.points(base))<.01,"stesso valore dell'originale per "+id)
	var e={"hp":2,"moves":{"thrust":{"attack":2},"parry_r":{"defense":-1},"kick":{"off":true}}}
	var g2=BloodForge.build_variant("gascor",{"id":"var_gascor_prova","name":"Gascor il Rosso"},e)
	var g0=BloodForge.official("gascor")
	ok(int(g2.moves.thrust.attack)==int(g0.moves.thrust.attack)+2 and int(g2.moves.parry_r.defense)==int(g0.moves.parry_r.defense)-1 and not g2.moves.has("kick") and int(g2.hp)==int(g0.hp)+2,"ritocchi della variante")
	ok(int(g2.moves.cleave.attack)==int(g0.moves.cleave.attack) and bool(g2.moves.thrust.get("drawn",false)) and not bool(g2.moves.cleave.get("drawn",false)),"il resto resta com'era")
	ok(BloodForge.validate(g2).is_empty(),"variante valida")
	var sh=BloodForge.build_variant("shannon",{"id":"var_shannon_prova"},{"hp":0,"moves":{}})
	ok(bool(sh.get("reach",false)),"l'arma lunga resta lunga nella variante")
	# la variante gioca: entra nel catalogo e si schiera
	rules.add_definition(g2)
	rules.new_game([{"character":"var_gascor_prova","team":0,"controller":"ai"},{"character":"anteos","team":1,"controller":"ai"}],"libero",3,-1)
	ok(rules.state.fighters[0].name=="Gascor il Rosso" and int(rules.state.fighters[0].hp)==int(g0.hp)+2 and rules.state.get("custom_defs",{}).has("var_gascor_prova"),"variante in partita, salvata con la partita")
	print("PASS: %d checks"%checks if fails==0 else "FAIL: %d di %d"%[fails,checks])
	quit(1 if fails>0 else 0)
