extends VBoxContainer
## Schermata "La forgia degli eroi": a sinistra i tratti, al centro le pedine (modificabili una per una),
## a destra il valore in punti rispetto al budget, il collaudo con duelli simulati e gli eroi salvati.

class HexSides extends Control:
	## esagono coi lati cliccabili: il lato in alto è il fronte, poi in senso orario
	signal changed(sides: Array)
	var sides: Array=[]
	var color:=Color.RED
	func _init() -> void:
		custom_minimum_size=Vector2(46,40);mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
		tooltip_text="Clic su un lato per accenderlo o spegnerlo (in alto il fronte)"
	func _corner(k: int) -> Vector2:
		var c=size*.5;var r=minf(size.x*.5,size.y/1.732)-3.0;var a=deg_to_rad(60.0*k)
		return c+Vector2(cos(a)*r,sin(a)*r)
	func _draw() -> void:
		var pts=PackedVector2Array()
		for k in 6:pts.append(_corner(k))
		draw_colored_polygon(pts,Color(0,0,0,.35))
		for s in 6:   # lato s fra i vertici a 240+60s e 300+60s gradi
			var a=_corner((4+s)%6);var b=_corner((5+s)%6)
			draw_line(a,b,color if s in sides else Color(1,1,1,.22),4.0 if s in sides else 1.5,true)
		draw_circle(size*.5+Vector2(0,-size.y*.16),2.5,Color(1,1,1,.7))   # puntino del fronte
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index==MOUSE_BUTTON_LEFT:
			var v: Vector2=ev.position-size*.5
			var deg=fposmod(rad_to_deg(atan2(v.y,v.x))-270.0,360.0)
			var s=posmod(roundi(deg/60.0),6)
			if s in sides:sides.erase(s)
			else:sides.append(s)
			sides.sort();queue_redraw();changed.emit(sides.duplicate())

var ui   # la schermata principale (main.gd): caratteri, colori, pulsanti
var traits: Dictionary
var edits: Dictionary={"hp":0,"moves":{}}
var def: Dictionary
var base_points:=0.0
var value_box: VBoxContainer
var moves_box: VBoxContainer
var traits_box: VBoxContainer
var test_label: Label
var testing:=false
var on_close: Callable

func setup(main_ui,hero_id: String="") -> void:
	ui=main_ui
	traits=BloodForge.default_traits()
	if hero_id!="" and ui.game.catalog.has(hero_id) and ui.game.catalog[hero_id].has("traits"):
		traits=ui.game.catalog[hero_id].traits.duplicate(true);traits.id=hero_id
		edits=ui.game.catalog[hero_id].get("edits",{"hp":0,"moves":{}}).duplicate(true)
	size_flags_vertical=Control.SIZE_EXPAND_FILL;size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var head=HBoxContainer.new();add_child(head)
	head.add_child(ui.button("‹ Indietro",func():on_close.call()))
	head.add_child(ui.label("LA FORGIA DEGLI EROI",22,ui.GOLD))
	var sub=ui.label("Scegli corpo, carattere e armi: le pedine nascono da qui. Poi ritoccale una per una restando nel budget.",13,ui.MUTED);head.add_child(sub)
	var cols=HBoxContainer.new();cols.size_flags_vertical=Control.SIZE_EXPAND_FILL;cols.add_theme_constant_override("separation",10);add_child(cols)
	traits_box=_scroll_panel(cols,300)
	moves_box=_scroll_panel(cols,0);moves_box.get_parent().get_parent().get_parent().get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL
	value_box=_scroll_panel(cols,270)
	_rebuild(true)

func _scroll_panel(parent: Node,width: float) -> VBoxContainer:
	var v=ui.panel_content(parent,10)
	var panel=v.get_parent().get_parent()
	if width>0:panel.custom_minimum_size.x=width
	var sc=ScrollContainer.new();sc.size_flags_vertical=Control.SIZE_EXPAND_FILL;sc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc);var inner=VBoxContainer.new();inner.size_flags_horizontal=Control.SIZE_EXPAND_FILL;inner.add_theme_constant_override("separation",6);sc.add_child(inner)
	return inner

# ------------------------------------------------------------------ tratti
func _chips(parent: Node,title: String,options: Array,current,cb: Callable,disabled:=false,tip:="") -> void:
	parent.add_child(ui.label(title,12,ui.GOLD))
	var flow=HFlowContainer.new();flow.add_theme_constant_override("h_separation",4);flow.add_theme_constant_override("v_separation",4);parent.add_child(flow)
	for o in options:
		var b=ui._bar_check(str(o[1]),str(o[0])==str(current),func(_v):cb.call(o[0]),tip)
		b.disabled=disabled;flow.add_child(b)
func _set_trait(k: String,v) -> void:
	traits[k]=v;edits={"hp":0,"moves":{}}   # nuovi tratti: si riparte dalle pedine generate
	_rebuild(true)
func _traits_panel() -> void:
	ui.clear(traits_box)
	traits_box.add_child(ui.label("NOME E TITOLO",12,ui.GOLD))
	var nm=LineEdit.new();nm.text=str(traits.name);nm.placeholder_text="Nome";nm.text_changed.connect(func(t):traits.name=t);traits_box.add_child(nm)
	var tt=LineEdit.new();tt.text=str(traits.title);tt.placeholder_text="Titolo (es. Il prode)";tt.text_changed.connect(func(t):traits.title=t);traits_box.add_child(tt)
	var lv=[]
	for n in 3:lv.append([n+1,BloodForge.LIVELLI[n]])
	var st=[]
	for n in 5:st.append([n+1,BloodForge.STAZZE[n]])
	_chips(traits_box,"STAZZA · colpi più forti e sbilanciamenti, ma bersaglio più facile",st,traits.stazza,func(v):_set_trait("stazza",v))
	_chips(traits_box,"FORZA · attacchi",lv,traits.forza,func(v):_set_trait("forza",v))
	_chips(traits_box,"AGILITÀ · difesa, sprint, schivate",lv,traits.agilita,func(v):_set_trait("agilita",v))
	_chips(traits_box,"RESISTENZA · ferite e recupero",lv,traits.resistenza,func(v):_set_trait("resistenza",v))
	var car=[]
	for k in BloodForge.CARATTERI:car.append([k,BloodForge.CARATTERI[k]])
	_chips(traits_box,"CARATTERE",car,traits.carattere,func(v):_set_trait("carattere",v),false,"Aggressivo: colpi +1, parate peggiori · Prudente: colpi −1, parate e guardia migliori · Astuto: sbilancia di più, si sposta di lato")
	var ar=[]
	for k in BloodForge.ARMI:ar.append([k,BloodForge.ARMI[k]])
	_chips(traits_box,"ARMA · decide quali pedine ha",ar,traits.arma,func(v):_set_trait("arma",v))
	var sc=[]
	for k in BloodForge.SCUDI:sc.append([k,BloodForge.SCUDI[k]])
	_chips(traits_box,"SCUDO"+(" · non con un'arma a due mani" if traits.arma in BloodForge.NO_SHIELD else ""),sc,"nessuno" if traits.arma in BloodForge.NO_SHIELD else traits.scudo,func(v):_set_trait("scudo",v),traits.arma in BloodForge.NO_SHIELD,"Piccolo: parate −1 · Grande: parate −2 e un lato blu in più, colpi −1, sprint −1")
	var am=[]
	for k in BloodForge.ARMATURE:am.append([k,BloodForge.ARMATURE[k]])
	_chips(traits_box,"ARMATURA · assorbe ferite, ma appesantisce",am,traits.armatura,func(v):_set_trait("armatura",v))
	_chips(traits_box,"SCHIERAMENTO",[[-1,"Con chiunque"],[0,"Ordine della Lama"],[1,"Ordine dell'Ombra"]],int(traits.get("team",-1)),func(v):_set_trait("team",v))

# ------------------------------------------------------------------ pedine
func _rebuild(full: bool) -> void:
	var base=BloodForge.build(traits)
	base_points=BloodForge.points(base)
	def=BloodForge.apply_edits(base,edits)
	if full:_traits_panel()
	_moves_panel();_value_panel()
func _edit(id: String,field: String,delta: int) -> void:
	var me: Dictionary=edits.get("moves",{});var e: Dictionary=me.get(id,{})
	e[field]=int(e.get(field,0))+delta
	if int(e[field])==0:e.erase(field)
	if e.is_empty():me.erase(id)
	else:me[id]=e
	edits.moves=me;_rebuild(false)
func _stepper(parent: Node,label_text: String,value: String,id: String,field: String,tip: String) -> void:
	var box=HBoxContainer.new();box.add_theme_constant_override("separation",2);box.tooltip_text=tip;parent.add_child(box)
	box.add_child(ui.label(label_text,12,ui.MUTED))
	var minus=ui._bar_button("−",func():_edit(id,field,-1),tip);box.add_child(minus)
	var v=ui.label(value,15,ui.INK);v.custom_minimum_size.x=34;v.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;box.add_child(v)
	var plus=ui._bar_button("+",func():_edit(id,field,1),tip);box.add_child(plus)
func _moves_panel() -> void:
	ui.clear(moves_box)
	var top=HBoxContainer.new();moves_box.add_child(top)
	top.add_child(ui.label("LE PEDINE · %d"%def.moves.size(),13,ui.GOLD));top.add_child(ui.spacer())
	var hpbox=HBoxContainer.new();top.add_child(hpbox)
	hpbox.add_child(ui.label("Ferite %d"%int(def.hp),15,ui.INK))
	hpbox.add_child(ui._bar_button("−",func():edits.hp=int(edits.get("hp",0))-1;_rebuild(false),"Una ferita in meno"))
	hpbox.add_child(ui._bar_button("+",func():edits.hp=int(edits.get("hp",0))+1;_rebuild(false),"Una ferita in più"))
	top.add_child(ui.label("· Stazza %d · Sprint %d · Armatura %s"%[int(def.size),int(def.sprint),("%d-%d"%[def.armor[0],def.armor[1]]) if not def.armor.is_empty() else "nessuna"],13,ui.MUTED))
	var hint=ui.label("Difesa: più bassa è meglio (si somma al colpo avversario). Pallini neri = fatica: il colpo è più forte ma stanca. Il valore accanto a ogni pedina è quanto i tuoi ritocchi su di lei spostano i punti.",12,ui.MUTED)
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;moves_box.add_child(hint)
	var skip=["again","unbalanced","down","rise"]
	for id in def.moves:
		if id in skip:continue
		var m=def.moves[id]
		var row=PanelContainer.new();var sb=ui.box(Color(0,0,0,.25),6);row.add_theme_stylebox_override("panel",sb);moves_box.add_child(row)
		var h=HBoxContainer.new();h.add_theme_constant_override("separation",8);row.add_child(h)
		var t=TextureRect.new();t.texture=load(Art.token(m.texture)) if ResourceLoader.exists(Art.token(m.texture)) else null
		t.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;t.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;t.custom_minimum_size=Vector2(46,40)
		var who=VBoxContainer.new();who.add_theme_constant_override("separation",0);who.custom_minimum_size.x=96;h.add_child(who)
		who.add_child(t);var nm=ui.label(m.name,12,ui.INK);nm.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;nm.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;who.add_child(nm)
		var kind=BloodForge.side_kind(m)
		if kind!="":
			var hx=HexSides.new();hx.sides=m[kind].duplicate();hx.color={"red":Color("e05a4a"),"green":Color("6cc46a"),"blue":Color("5aa0e8")}[kind]
			hx.tooltip_text={"red":"Lati rossi: da dove colpisce","green":"Lati verdi: dove può muoversi","blue":"Lati blu: da dove para"}[kind]+" · clic per cambiarli"
			hx.changed.connect(func(s):
				var me: Dictionary=edits.get("moves",{});var e: Dictionary=me.get(id,{});e.sides=s;me[id]=e;edits.moves=me;_rebuild(false))
			h.add_child(hx)
		else:
			var gap=Control.new();gap.custom_minimum_size.x=46;h.add_child(gap)
		var grid=HFlowContainer.new();grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_theme_constant_override("h_separation",12);h.add_child(grid)
		if m.attack!=null and id!="shoot":_stepper(grid,"Att",str(m.attack),id,"attack","Valore d'attacco del colpo")
		_stepper(grid,"Dif",str(m.defense)+("/%d"%int(m.secondary) if not m.blue.is_empty() else ""),id,"defense","Difesa della pedina"+(" (sui lati blu / sugli altri)" if not m.blue.is_empty() else ""))
		if m.attack!=null and id!="shoot":
			_stepper(grid,"Fat","●".repeat(int(m.fatigue)) if int(m.fatigue)>0 else "—",id,"fatigue","Pallini neri: ogni punto di fatica toglie 1 all'attacco e alla difesa finché non si riposa")
			_stepper(grid,"Sbil",str(m.imbalance) if m.imbalance!=null else "—",id,"imbalance","Modificatore sulla tabella di sbilanciamento (con la stazza)")
		# quanto valgono i ritocchi fatti a questa pedina
		var e=edits.get("moves",{}).get(id,{})
		if not e.is_empty():
			var no=edits.duplicate(true);no.moves.erase(id)
			var dv=BloodForge.points(def)-BloodForge.points(BloodForge.apply_edits(BloodForge.build(traits),no))
			h.add_child(ui.label("%+.1f"%dv,14,Color("e8a070") if dv>0 else Color("8fd08a")))

# ------------------------------------------------------------------ valore, collaudo, salvataggio
func _value_panel() -> void:
	ui.clear(value_box)
	var f=BloodForge.features(def);var pts=BloodForge.points(def)
	value_box.add_child(ui.label("VALORE",13,ui.GOLD))
	var big=ui.label("%d"%roundi(pts),52,ui.GOLD if pts<=BloodForge.BUDGET+.5 else Color("e86a5a"));value_box.add_child(big)
	value_box.add_child(ui.label("budget %d (media dei personaggi ufficiali)"%int(BloodForge.BUDGET),12,ui.MUTED))
	var bar=ProgressBar.new();bar.min_value=0;bar.max_value=160;bar.value=pts;bar.show_percentage=false;bar.custom_minimum_size.y=14;value_box.add_child(bar)
	var over=pts-BloodForge.BUDGET
	var msg=ui.label(("Dentro il budget: restano %d punti."%roundi(-over)) if over<=.5 else ("Oltre il budget di %d punti: togli qualcosa."%roundi(over)),14,Color("8fd08a") if over<=.5 else Color("e86a5a"))
	msg.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;value_box.add_child(msg)
	if absf(pts-base_points)>.5:value_box.add_child(ui.label("Pedine generate: %d · ritocchi: %+d"%[roundi(base_points),roundi(pts-base_points)],12,ui.MUTED))
	var lines=[["Ferite per colpo inflitto","%.1f"%f.off,"Media delle sue 4 pedine d'attacco migliori contro un difensore medio"],
		["Ferite per colpo subito","%.1f"%f.sub,"Media sulle sue pedine contro un attaccante medio (armatura compresa)"],
		["Ferite che regge","%d"%int(f.hp),""],["Sprint","%d"%int(f.sprint),""],["Pedine d'attacco","%d"%int(f.natk),""]]
	var g=GridContainer.new();g.columns=2;g.add_theme_constant_override("h_separation",10);value_box.add_child(g)
	for l in lines:
		var a=ui.label(l[0],13,ui.MUTED);a.tooltip_text=l[2];g.add_child(a);g.add_child(ui.label(l[1],14,ui.INK))
	value_box.add_child(ui.label("CONFRONTO",12,ui.GOLD))
	var cmp=GridContainer.new();cmp.columns=2;value_box.add_child(cmp)
	for id in ["ut","shannon","kylvia","gascor","zenyo"]:
		cmp.add_child(ui.label(ui.game.catalog[id].name,12,ui.MUTED));cmp.add_child(ui.label("%d"%roundi(BloodForge.points(ui.game.catalog[id])),12,ui.INK))
	value_box.add_child(ui.button("Adatta al budget",_fit_budget))
	var tb=ui.button("Collaudo · 36 duelli simulati",_run_test);tb.disabled=testing;value_box.add_child(tb)
	test_label=ui.label("",13,ui.INK);test_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;value_box.add_child(test_label)
	var save=ui.button("Salva l'eroe",_save,true);save.disabled=over>.5;save.tooltip_text="Si può salvare solo dentro il budget" if over>.5 else "";value_box.add_child(save)
	value_box.add_child(ui.label("EROI SALVATI",12,ui.GOLD))
	for id in BloodForge.load_saved():
		var r=HBoxContainer.new();value_box.add_child(r)
		var n=ui.label(str(ui.game.catalog[id].name) if ui.game.catalog.has(id) else id,13,ui.INK);n.size_flags_horizontal=Control.SIZE_EXPAND_FILL;n.clip_text=true;r.add_child(n)
		r.add_child(ui._bar_button("Modifica",func():_open(id)))
		r.add_child(ui._bar_button("✕",func():BloodForge.delete_hero(id);ui.game.catalog.erase(id);BloodRules.extra_defs.erase(id);_value_panel(),"Elimina"))
func _open(id: String) -> void:
	traits=ui.game.catalog[id].traits.duplicate(true);traits.id=id
	edits=ui.game.catalog[id].get("edits",{"hp":0,"moves":{}}).duplicate(true);_rebuild(true)
func _fit_budget() -> void:
	# porta il valore al budget cambiando le ferite (la cosa più neutra da ritoccare)
	for n in 60:
		var pts=BloodForge.points(def)
		if pts>BloodForge.BUDGET+.5:edits.hp=int(edits.get("hp",0))-1
		elif pts<BloodForge.BUDGET-4.0:edits.hp=int(edits.get("hp",0))+1
		else:break
		def=BloodForge.apply_edits(BloodForge.build(traits),edits)
		if int(def.hp)<=4:break
	_rebuild(false)
func _save() -> void:
	if str(traits.get("id",""))=="":traits.id="forged_%d"%(Time.get_ticks_usec()%10000000)
	def=BloodForge.apply_edits(BloodForge.build(traits),edits)
	BloodForge.save_hero(def);BloodRules.extra_defs[def.id]=def;ui.game.add_definition(def)
	_value_panel();test_label.text="Salvato: %s è nella scelta dei personaggi (fra gli eroi forgiati)."%def.name

const FOES=["zenyo","gascor","ut","shannon","kylvia","gandy","thorn","sanguinaria","ziggy"]
func _run_test() -> void:
	if testing:return
	testing=true;_value_panel()
	var probe=def.duplicate(true);probe.id="forged_collaudo";probe.name=def.name
	BloodRules.extra_defs[probe.id]=probe
	var wins=0.0;var games=0;var by={}
	for foe in FOES:
		for s in 4:
			var ro=[probe.id,foe] if s%2==0 else [foe,probe.id]
			var r=BloodRules.new();var roster=[]
			for n in 2:roster.append({"character":ro[n],"team":n,"controller":"ai"})
			r.new_game(roster,"libero",int(Time.get_ticks_usec()%100000)+s,-1)
			var steps=0
			while r.state.phase!="finished" and r.state.turn<30 and steps<6000:
				steps+=1
				match r.state.phase:
					"deploy":
						var i=int(r.state.active);var team=int(r.state.fighters[i].team);var en=r.entry_cells(team);r.deploy(en[i%en.size()],0 if team==0 else 3)
					"planning":
						for i in r.needs_plan():r.plan(i,BloodAI.choose_move(r,i))
						r.reveal()
					"draw":r.draw_next()
					"acting":r.act(BloodAI.command(r,int(r.state.active)))
					"opportunity":r.opportunity(BloodAI.opportunity(r,int(r.state.pending.reactors[0])))
					"reaction":r.react(BloodAI.reaction(r,int(r.state.pending.reactors[0])))
					"stumble":r.choose_stumble(r.state.pending.path.back())
					"upkeep":r.advance_effect(BloodAI.effect_facing(r))
					_:break
				if steps%40==0:await get_tree().process_frame
			var me=0 if s%2==0 else 1;var res=0.5
			if r.state.phase=="finished":res=1.0 if int(r.state.winner)==me else (0.0 if int(r.state.winner)>=0 else .5)
			else:
				var share=[0.0,0.0]
				for p in r.state.fighters:
					if p.alive and int(p.get("owner",-1))<0:share[int(p.team)]+=float(p.hp)/maxf(1.0,float(p.max_hp))
				res=1.0 if share[me]>share[1-me]+.1 else (0.0 if share[1-me]>share[me]+.1 else .5)
			wins+=res;games+=1;by[foe]=float(by.get(foe,0.0))+res
			if is_instance_valid(test_label):test_label.text="Collaudo… %d/36 · vittorie %d%%"%[games,roundi(100*wins/games)]
			await get_tree().process_frame
	BloodRules.extra_defs.erase(probe.id)
	testing=false
	if not is_inside_tree():return
	_value_panel()
	var parts=[]
	for foe in FOES:parts.append("%s %d%%"%[ui.game.catalog[foe].name,roundi(100*by[foe]/4.0)])
	var verdict="in linea con il cast" if wins/games>=.4 and wins/games<=.6 else ("troppo forte" if wins/games>.6 else "un po' debole")
	test_label.text="Collaudo: vince il %d%% dei duelli (%s; i personaggi ufficiali vanno dal 34%% al 74%%).\n%s"%[roundi(100*wins/games),verdict,", ".join(parts)]
