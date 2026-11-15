extends VBoxContainer
## "La forgia degli eroi" come una scheda del personaggio: a sinistra nome, ritratto, caratteristiche,
## carattere ed equipaggiamento; a destra le pedine a nido d'ape (grandi, con i valori già calcolati e
## un + e un − su ogni valore, lati cliccabili); in basso, compatta, la fascia del valore e del budget.

class TokenHex extends Control:
	## una pedina: esagono coi lati colorati cliccabili (in alto il fronte, poi in senso orario)
	signal side_clicked(s: int)
	signal picked
	var m: Dictionary
	var selected:=false
	var tex: Texture2D
	var on:=true
	var R:=96.0
	const COL={"red":Color("e05a4a"),"green":Color("6cc46a"),"blue":Color("5aa0e8")}
	func _init(radius: float) -> void:
		R=radius;custom_minimum_size=Vector2(2*R,1.732*R);size=custom_minimum_size;mouse_filter=Control.MOUSE_FILTER_STOP
	func _corner(k: int,shrink:=0.0) -> Vector2:
		var a=deg_to_rad(60.0*k);return size*.5+Vector2(cos(a),sin(a))*(R-2.0-shrink)
	func _draw() -> void:
		var pts=PackedVector2Array()
		for k in 6:pts.append(_corner(k))
		draw_colored_polygon(pts,Color(.09,.06,.04,.92) if on else Color(.09,.06,.04,.55))
		if selected:
			var ring=PackedVector2Array()
			for k in 7:ring.append(_corner(k%6,9))
			draw_polyline(ring,Color("e6bf6c"),2.0,true)
		for s in 6:   # lato s fra i vertici a 240+60s e 300+60s gradi; più colori = strisce affiancate
			var n=0
			for c in ["red","green","blue"]:
				if s in m.get(c,[]):
					draw_line(_corner((4+s)%6,2+n*5),_corner((5+s)%6,2+n*5),COL[c] if on else COL[c].darkened(.5),4.0,true);n+=1
			if n==0:draw_line(_corner((4+s)%6,3),_corner((5+s)%6,3),Color(1,1,1,.14),1.5,true)
		draw_circle(size*.5+Vector2(0,-R*.72),3.0,Color(1,1,1,.7))   # puntino del fronte
	var content: Control
	func set_content(c: Control) -> void:
		content=c;add_child(c);c.minimum_size_changed.connect(_center)
	func _ready() -> void:_center.call_deferred()
	func _center() -> void:   # i valori al centro dell'esagono (misurati quando il tema è già applicato)
		if content==null:return
		var ms=content.get_combined_minimum_size();content.size=ms;content.position=(size-ms)*.5+Vector2(0,3)
	func _gui_input(ev: InputEvent) -> void:
		if not on:return
		if ev is InputEventMouseButton and ev.pressed and ev.button_index==MOUSE_BUTTON_LEFT:
			var v: Vector2=ev.position-size*.5
			if v.length()<R*.66:picked.emit();return   # al centro: si sceglie la pedina (anteprima 3D della mossa)
			side_clicked.emit(posmod(roundi(fposmod(rad_to_deg(atan2(v.y,v.x))-270.0,360.0)/60.0),6))

var ui   # la schermata principale (main.gd): caratteri, colori, pulsanti
var traits: Dictionary
var edits: Dictionary={"hp":0,"moves":{}}
var def: Dictionary
var all_def: Dictionary
var base_points:=0.0
var sheet: VBoxContainer
var comb: VBoxContainer
var band: HBoxContainer
var test_label: Label
var testing:=false
var brush:="red"
var on_close: Callable
var base_id:=""                 # personaggio del gioco aperto nella forgia: si guardano le sue pedine e se ne salva una variante
var var_info:={}                # nome, titolo e id della variante
const HIDDEN=["again","unbalanced","down","rise"]   # pedine di stato: non si modificano

func setup(main_ui,hero_id: String="") -> void:
	ui=main_ui
	traits=BloodForge.default_traits()
	_load_hero(hero_id)
	size_flags_vertical=Control.SIZE_EXPAND_FILL;size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",8)
	var head=HBoxContainer.new();add_child(head)
	head.add_child(ui.button("Indietro",func():on_close.call()))
	head.add_child(ui.label("LA FORGIA DEGLI EROI",22,ui.GOLD))
	head.add_child(ui.spacer())
	# i personaggi del gioco: si aprono per vedere ogni pedina con i suoi valori e il valore totale, e per farne una variante
	var pick=OptionButton.new();pick.add_theme_font_size_override("font_size",13);pick.add_item("Apri un personaggio del gioco")
	var officials=ui.game.catalog.keys().filter(func(k):return not BloodForge.is_custom(ui.game.catalog[k]) and not str(ui.game.catalog[k].kind) in ["golem","skeleton"])
	for id in officials:pick.add_item("%s · %s"%[str(ui.game.catalog[id].name),str(ui.game.catalog[id].title)])
	pick.item_selected.connect(func(n):
		if n>0:_load_hero(officials[n-1]);_rebuild(true))
	pick.tooltip_text="Mostra le pedine di un personaggio del gioco con tutti i valori; ritoccale e salva una variante";head.add_child(pick)
	head.add_child(ui._bar_button("Nuovo eroe",func():_load_hero("");traits=BloodForge.default_traits();_rebuild(true),"Ricomincia da un eroe nuovo, costruito dalle caratteristiche"))
	var cols=HBoxContainer.new();cols.size_flags_vertical=Control.SIZE_EXPAND_FILL;cols.add_theme_constant_override("separation",10);add_child(cols)
	var lv=ui.panel_content(cols,10);lv.get_parent().get_parent().custom_minimum_size.x=340
	_make_preview(lv)
	var lsc=ScrollContainer.new();lsc.size_flags_vertical=Control.SIZE_EXPAND_FILL;lsc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;lv.add_child(lsc)
	sheet=VBoxContainer.new();sheet.size_flags_horizontal=Control.SIZE_EXPAND_FILL;sheet.add_theme_constant_override("separation",6);lsc.add_child(sheet)
	comb=_scroll_panel(cols,0);comb.get_parent().get_parent().get_parent().get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var bp=ui.panel_content(self,8);band=HBoxContainer.new();band.add_theme_constant_override("separation",14);bp.add_child(band)
	_rebuild(true)

## apre un eroe forgiato, una variante salvata o un personaggio del gioco (vuoto: eroe nuovo)
func _load_hero(hero_id: String) -> void:
	base_id="";var_info={};edits={"hp":0,"moves":{}};selected_id="guard"
	if hero_id=="" or not ui.game.catalog.has(hero_id):return
	var c: Dictionary=ui.game.catalog[hero_id]
	if c.has("traits"):
		traits=BloodForge.migrate(c.traits);traits.id=hero_id
		edits=c.get("edits",{"hp":0,"moves":{}}).duplicate(true)
	elif c.has("variant_of"):
		base_id=str(c.variant_of);var_info={"id":hero_id,"name":str(c.name),"title":str(c.title)}
		edits=c.get("edits",{"hp":0,"moves":{}}).duplicate(true)
	elif not str(c.kind) in ["golem","skeleton"]:
		base_id=hero_id;var_info={"id":"","name":str(c.name)+" II","title":str(c.title)}
	if not edits.has("moves"):edits["moves"]={}
	if not edits.has("hp"):edits["hp"]=0
func _scroll_panel(parent: Node,width: float) -> VBoxContainer:
	var v=ui.panel_content(parent,10)
	var panel=v.get_parent().get_parent()
	if width>0:panel.custom_minimum_size.x=width
	var sc=ScrollContainer.new();sc.size_flags_vertical=Control.SIZE_EXPAND_FILL;sc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc);var inner=VBoxContainer.new();inner.size_flags_horizontal=Control.SIZE_EXPAND_FILL;inner.add_theme_constant_override("separation",6);sc.add_child(inner)
	return inner

# ------------------------------------------------------------------ scheda
func _chips(parent: Node,title: String,options: Array,current,cb: Callable,tip:="",disabled: Array=[]) -> void:
	if title!="":parent.add_child(ui.label(title,12,ui.GOLD))
	var flow=HFlowContainer.new();flow.add_theme_constant_override("h_separation",4);flow.add_theme_constant_override("v_separation",4);parent.add_child(flow)
	for o in options:
		var b=ui._bar_check(str(o[1]),str(o[0])==str(current),func(_v):cb.call(o[0]),tip)
		b.disabled=o[0] in disabled;flow.add_child(b)
func _set_trait(k: String,v,reset_edits:=false) -> void:
	traits[k]=v
	if reset_edits:edits={"hp":0,"moves":{}}   # arma nuova: le pedine ripartono da quelle calcolate
	_rebuild(true)
func _sheet_base() -> void:
	# personaggio del gioco: nome della variante, i suoi numeri e, in chiaro, tutte le pedine con ogni valore
	var b: Dictionary=BloodForge.official(base_id)
	var top=HBoxContainer.new();sheet.add_child(top)
	var names=VBoxContainer.new();names.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(names)
	names.add_child(ui.label("NOME DELLA VARIANTE",11,ui.GOLD))
	var nm=LineEdit.new();nm.text=str(var_info.get("name",""));nm.text_changed.connect(func(t):var_info.name=t);names.add_child(nm)
	names.add_child(ui.label("TITOLO",11,ui.GOLD))
	var tt=LineEdit.new();tt.text=str(var_info.get("title",""));tt.text_changed.connect(func(t):var_info.title=t);names.add_child(tt)
	var fp="res://assets/ui/faces/%s.webp"%base_id
	var fr=PanelContainer.new();var fs=ui.box(Color(0,0,0,.4),4);fs.set_border_width_all(2);fs.border_color=ui.GOLD.darkened(.2);fr.add_theme_stylebox_override("panel",fs);top.add_child(fr)
	var face=TextureRect.new();face.texture=load(fp) if ResourceLoader.exists(fp) else null;face.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;face.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;face.custom_minimum_size=Vector2(92,92);fr.add_child(face)
	sheet.add_child(ui.wrap_label("%s · %s è un personaggio del gioco. Qui a destra ci sono tutte le sue pedine con ogni valore; ritocca quello che vuoi e salva una variante: l'originale non cambia mai."%[str(b.name),str(b.title)],13,ui.MUTED,280))
	var orig=BloodForge.points(b);var now=BloodForge.points(def)
	sheet.add_child(ui.label("VALORE TOTALE",12,ui.GOLD))
	sheet.add_child(ui.wrap_label("%s originale: %d punti%s  ·  100 è la media dei guerrieri del gioco"%[str(b.name),roundi(orig),("  ·  questa variante: %d punti (%+d)"%[roundi(now),roundi(now)-roundi(orig)]) if absf(now-orig)>.5 else ""],13,ui.INK,280))
	sheet.add_child(ui.label("IL PERSONAGGIO",12,ui.GOLD))
	sheet.add_child(ui.wrap_label("Stazza %d · Ferite %d · Sprint %d · Armatura %s%s"%[int(def.size),int(def.hp),int(def.sprint),("%d-%d"%[def.armor[0],def.armor[1]]) if not def.armor.is_empty() else "nessuna",(" · Mago, magia iniziale 5 + un dado") if bool(def.get("mage",false)) else ""],13,ui.INK,280))
	# tutte le pedine in tabella: attacco, difesa (lati blu / altri lati), fatica, sbilanciamento, riposo, lati
	sheet.add_child(ui.label("TUTTE LE PEDINE · %d"%def.moves.size(),12,ui.GOLD))
	var g=GridContainer.new();g.columns=5;g.add_theme_constant_override("h_separation",8);g.add_theme_constant_override("v_separation",1);sheet.add_child(g)
	for h in ["Pedina","Att.","Dif.","Fat.","Sbil."]:g.add_child(ui.label(h,11,ui.MUTED))
	var side_txt=func(l: Array):return ",".join(l.map(func(x):return ["fronte","fronte-destra","dietro-destra","dietro","dietro-sinistra","fronte-sinistra"][int(x)]))
	for id in def.moves:
		var m: Dictionary=def.moves[id]
		var changed=edits.get("moves",{}).has(id)
		var nl=ui.label(str(m.name),12,ui.GOLD if changed else ui.INK);nl.clip_text=true;nl.custom_minimum_size.x=124
		var tip=[]
		if not m.red.is_empty():tip.append("Colpisce: "+side_txt.call(m.red))
		if not m.green.is_empty():tip.append("Si muove: "+side_txt.call(m.green))
		if not m.blue.is_empty():tip.append("Para: "+side_txt.call(m.blue))
		if bool(m.get("rest",false)):tip.append("Recupera fatica a fine turno")
		if m.get("spell",false):tip.append("Magia: valore %d, costo %d"%[int(m.get("value",0)),int(m.get("cost",0))])
		nl.tooltip_text="\n".join(tip);nl.mouse_filter=Control.MOUSE_FILTER_PASS;g.add_child(nl)
		g.add_child(ui.label(str(int(m.attack)) if m.attack!=null else "/",12,ui.INK))
		g.add_child(ui.label(("%d/%d"%[int(m.defense),int(m.secondary)]) if not m.blue.is_empty() else str(int(m.defense)),12,ui.INK))
		g.add_child(ui.label(str(int(m.fatigue)),12,ui.INK))
		g.add_child(ui.label(("+%d"%int(m.imbalance)) if m.get("imbalance")!=null else "no",12,ui.INK))
func _sheet() -> void:
	ui.clear(sheet)
	if base_id!="":_sheet_base();return
	var top=HBoxContainer.new();sheet.add_child(top)
	var names=VBoxContainer.new();names.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(names)
	names.add_child(ui.label("NOME",11,ui.GOLD))
	var nm=LineEdit.new();nm.text=str(traits.name);nm.placeholder_text="Nome";nm.text_changed.connect(func(t):traits.name=t);names.add_child(nm)
	names.add_child(ui.label("TITOLO",11,ui.GOLD))
	var tt=LineEdit.new();tt.text=str(traits.title);tt.placeholder_text="Il prode";tt.text_changed.connect(func(t):traits.title=t);names.add_child(tt)
	var body=BloodForge.body_for(traits)
	var pp="res://assets/ui/portraits/%s.webp"%body
	if not ResourceLoader.exists(pp):pp="res://assets/ui/faces/%s.webp"%body
	var fr=PanelContainer.new();var fs=ui.box(Color(0,0,0,.4),4);fs.set_border_width_all(2);fs.border_color=ui.GOLD.darkened(.2);fr.add_theme_stylebox_override("panel",fs);top.add_child(fr)
	var face=TextureRect.new();face.texture=load(pp) if ResourceLoader.exists(pp) else null;face.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;face.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.custom_minimum_size=Vector2(92,92);face.tooltip_text="La miniatura: "+str(BloodForge.BODY_NAMES.get(body,"il corpo di "+str(ui.game.catalog[body].name) if ui.game.catalog.has(body) else body));fr.add_child(face)
	sheet.add_child(ui.label("CARATTERISTICHE",12,ui.GOLD))
	var g=GridContainer.new();g.columns=2;g.add_theme_constant_override("h_separation",8);g.add_theme_constant_override("v_separation",3);sheet.add_child(g)
	for c in BloodForge.CARATTERISTICHE:
		var l=ui.label(c[1],15,ui.INK);l.tooltip_text=c[2];l.custom_minimum_size.x=104;g.add_child(l)
		var row=HBoxContainer.new();row.add_theme_constant_override("separation",3);g.add_child(row)
		for v in range(1,6):
			var key=c[0]
			var b=ui._bar_check(str(v),BloodForge.stat(traits,key)==v,func(_x):_set_trait(key,v),c[2]);b.custom_minimum_size.x=34;row.add_child(b)
	var spells_max=maxi(0,BloodForge.stat(traits,"INT")-1)
	var info=ui.label("Stazza %d · Ferite %d · Sprint %d · Armatura %s · Magie %d"%[int(def.size),int(def.hp),int(def.sprint),("%d-%d"%[def.armor[0],def.armor[1]]) if not def.armor.is_empty() else "—",spells_max],12,ui.MUTED)
	info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;sheet.add_child(info)
	var car=[]
	for k in BloodForge.CARATTERI:car.append([k,BloodForge.CARATTERI[k]])
	_chips(sheet,"CARATTERE",car,traits.carattere,func(v):_set_trait("carattere",v,true),"Aggressivo: colpi +1, parate peggiori · Prudente: colpi −1, parate e guardia migliori · Astuto: sbilancia di più, si sposta di lato")
	sheet.add_child(ui.label("EQUIPAGGIAMENTO",12,ui.GOLD))
	var ar=[]
	for k in BloodForge.ARMI:ar.append([k,BloodForge.ARMI[k]])
	_chips(sheet,"",ar,traits.arma,func(v):_set_trait("arma",v,true))
	var sc=[]
	for k in BloodForge.SCUDI:sc.append([k,BloodForge.SCUDI[k]])
	var two=traits.arma in BloodForge.NO_SHIELD
	_chips(sheet,"Scudo"+(" · non con un'arma a due mani" if two else ""),sc,"nessuno" if two else traits.scudo,func(v):_set_trait("scudo",v,true),"Piccolo: parate −1 · Grande: parate −2 e un lato blu in più, colpi −1, sprint −1",["piccolo","grande"] if two else [])
	var am=[]
	for k in BloodForge.ARMATURE:am.append([k,BloodForge.ARMATURE[k]])
	_chips(sheet,"Armatura · assorbe ferite, ma appesantisce",am,traits.armatura,func(v):_set_trait("armatura",v,true))
	_chips(sheet,"ASPETTO",[["uomo","Uomo"],["donna","Donna (in arrivo)"]],"uomo",func(_v):pass,"Per ora i corpi nuovi sono solo maschili",["donna"])
	_chips(sheet,"SCHIERAMENTO",[[-1,"Con chiunque"],[0,"Ordine della Lama"],[1,"Ordine dell'Ombra"]],int(traits.get("team",-1)),func(v):_set_trait("team",v))
	# magie dei quattro maghi
	var chosen: Array=traits.get("spells",[])
	sheet.add_child(ui.label("MAGIE · %d di %d (Intelligenza − 1)"%[mini(chosen.size(),spells_max),spells_max],12,ui.GOLD))
	if spells_max==0:
		var h=ui.label("Alza l'Intelligenza a 2 o più per imparare incantesimi.",12,ui.MUTED);h.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;sheet.add_child(h)
	else:
		var cat=BloodForge._catalog()
		for mage in BloodForge.SPELL_FROM:
			var opts=[];var off=[]
			for sid in BloodForge.SPELL_FROM[mage]:
				opts.append([sid,"%s · %d mana · +%d"%[cat[mage].moves[sid].name,int(cat[mage].moves[sid].get("cost",1)),int(BloodForge.SPELL_POINTS.get(sid,10))]])
				if not sid in chosen and chosen.size()>=spells_max:off.append(sid)
			sheet.add_child(ui.label(str(cat[mage].name),11,ui.MUTED))
			var flow=HFlowContainer.new();flow.add_theme_constant_override("h_separation",4);flow.add_theme_constant_override("v_separation",4);sheet.add_child(flow)
			for o in opts:
				var sid=o[0]
				var b=ui._bar_check(o[1],sid in chosen,func(v):_toggle_spell(sid,v),"Costo in punti magia e quanti punti di valore aggiunge all'eroe (misurato con le partite simulate)");b.disabled=sid in off;flow.add_child(b)
func _toggle_spell(sid: String,v: bool) -> void:
	var c: Array=traits.get("spells",[]).duplicate()
	if v and not sid in c:c.append(sid)
	if not v:c.erase(sid)
	traits.spells=c;_rebuild(true)

# ------------------------------------------------------------------ pedine a nido d'ape
func _rebuild(full: bool) -> void:
	if base_id!="":   # variante di un personaggio del gioco
		def=BloodForge.build_variant(base_id,var_info,edits)
		var keep=edits.duplicate(true)
		for id in keep.moves:keep.moves[id].erase("off")
		all_def=BloodForge.build_variant(base_id,var_info,keep)   # con anche le pedine tolte (si possono rimettere)
		base_points=BloodForge.points(BloodForge.official(base_id))
		if full or true:_sheet()
		_comb();_band();_update_preview();return
	var base=BloodForge.build(traits)
	base_points=BloodForge.points(base)
	def=BloodForge.apply_edits(base,edits)
	all_def=BloodForge.apply_edits(BloodForge.build_all(traits),edits)
	if full:_sheet()
	_comb();_band();_update_preview()
func _edit(id: String,field: String,value,absolute:=false) -> void:
	var me: Dictionary=edits.get("moves",{});var e: Dictionary=me.get(id,{})
	if absolute:
		e[field]=value
		if field=="off" and not bool(value):e.erase(field)
	else:
		e[field]=int(e.get(field,0))+int(value)
		if int(e[field])==0:e.erase(field)
	if e.is_empty():me.erase(id)
	else:me[id]=e
	edits.moves=me;_rebuild(false)
func _side(id: String,s: int) -> void:
	var m=all_def.moves[id];var list: Array=m.get(brush,[]).duplicate()
	if s in list:list.erase(s)
	else:list.append(s)
	list.sort();_edit(id,brush,list,true)
func _toggle_token(id: String) -> void:
	if base_id!="":   # personaggio del gioco: la pedina si toglie (o si rimette) nella variante
		_edit(id,"off",not bool(edits.get("moves",{}).get(id,{}).get("off",false)),true);return
	if id in BloodForge.EXTRA_IDS and not all_def.moves[id].get("native",false):   # pedine in più: spente finché non le accendi
		var on_list: Array=traits.get("on",[]).duplicate()
		if id in on_list:on_list.erase(id)
		else:on_list.append(id)
		traits.on=on_list
	else:
		var off: Array=traits.get("off",[]).duplicate()
		if id in off:off.erase(id)
		else:off.append(id)
		traits.off=off
	_rebuild(false)
func _mini(text: String,cb: Callable,tip:="") -> Button:
	var b=_tiny(text,cb,tip);b.custom_minimum_size=Vector2(20,20);b.add_theme_font_size_override("font_size",13);return b
func _tiny(text: String,cb: Callable,tip:="",disabled:=false) -> Button:
	var b=Button.new();b.text=text;b.tooltip_text=tip;b.focus_mode=Control.FOCUS_NONE;b.custom_minimum_size=Vector2(13,13);b.disabled=disabled
	b.add_theme_font_size_override("font_size",10);b.pressed.connect(cb);b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	for k in ["normal","focus","hover","pressed","disabled"]:
		var st=ui.box(Color(.42,.3,.16,.85) if k!="hover" else Color(.62,.45,.22,.95),2);st.content_margin_left=2;st.content_margin_right=2;st.content_margin_top=0;st.content_margin_bottom=0
		if k=="disabled":st.bg_color=Color(.2,.16,.12,.5)
		b.add_theme_stylebox_override(k,st)
	for k in ["font_color","font_hover_color","font_pressed_color"]:b.add_theme_color_override(k,ui.INK)
	b.add_theme_color_override("font_disabled_color",Color(.5,.45,.4))
	return b
## interruttore a parola: dorato se acceso, spento grigio
func _flag(text: String,on: bool,cb: Callable,tip: String,disabled:=false) -> Button:
	var b=_tiny(text,cb,tip,disabled)
	var st=ui.box(Color(.78,.6,.28,.95) if on else Color(.18,.13,.09,.8),2);st.content_margin_left=3;st.content_margin_right=3;st.content_margin_top=0;st.content_margin_bottom=0
	for k in ["normal","focus","pressed"]:b.add_theme_stylebox_override(k,st)
	for k in ["font_color","font_pressed_color"]:b.add_theme_color_override(k,ui.DARK_INK if on else Color(.62,.55,.45))
	return b
## un valore: numero grande in mezzo, − e + piccoli ai lati, etichetta minuscola sopra
func _cell(parent: Node,label: String,value: String,minus: Callable,plus: Callable,tip: String) -> void:
	var c=VBoxContainer.new();c.add_theme_constant_override("separation",-2);c.tooltip_text=tip;c.mouse_filter=Control.MOUSE_FILTER_PASS;parent.add_child(c)
	var l=ui.label(label,9,ui.MUTED);l.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;c.add_child(l)
	var r=HBoxContainer.new();r.add_theme_constant_override("separation",1);r.alignment=BoxContainer.ALIGNMENT_CENTER;c.add_child(r)
	r.add_child(_tiny("-",minus,tip))
	var v=ui.label(value,17,ui.INK);v.custom_minimum_size.x=24;v.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;r.add_child(v)
	r.add_child(_tiny("+",plus,tip))
func _line(parent: Node) -> HBoxContainer:
	var h=HBoxContainer.new();h.alignment=BoxContainer.ALIGNMENT_CENTER;h.add_theme_constant_override("separation",5);parent.add_child(h);return h
func _hex_for(id: String,R: float) -> Control:
	var m: Dictionary=all_def.moves[id];var opt=not id in BloodForge.BASE_IDS;var on=BloodForge.is_on(traits,id) or bool(m.get("native",false)) and not id in traits.get("off",[])
	if base_id!="":on=def.moves.has(id);opt=not id in ["advance","guard"]
	var hx=TokenHex.new(R);hx.m=m;hx.on=on
	hx.side_clicked.connect(func(s):_side(id,s))
	hx.selected=id==selected_id;hx.picked.connect(func():_pick(id))
	var v=VBoxContainer.new();v.add_theme_constant_override("separation",1);v.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hx.set_content(v)
	var title=_line(v)
	var nm=ui.label(str(m.name),11,ui.GOLD if on else ui.MUTED);nm.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.add_child(nm)
	if opt:   # spunta disegnata se la pedina c'è, più se è spenta
		var tg=_tiny("",func():_toggle_token(id),"Pedina attiva: tocca per toglierla" if on else "Pedina spenta: tocca per aggiungerla");tg.custom_minimum_size=Vector2(17,17)
		tg.draw.connect(func():ui._draw_icon(tg,"check" if on else "plus",ui.INK));title.add_child(tg)
	if on:
		var blue=not m.blue.is_empty()
		var l1=_line(v)
		if m.get("spell",false):
			var sl=ui.label("magia %d · costo %d"%[int(m.get("value",0)),int(m.get("cost",0))],10,Color("8fb8ff"));sl.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;v.add_child(sl)
		if m.attack!=null and id!="shoot":_cell(l1,"ATTACCO",str(m.attack),func():_edit(id,"attack",-1),func():_edit(id,"attack",1),"Valore d'attacco (ogni lato rosso in più lo abbassa di 1)")
		_cell(l1,"DIFESA BLU" if blue else "DIFESA",str(m.defense),func():_edit(id,"defense",-1),func():_edit(id,"defense",1),"Difesa: più bassa è meglio"+(" (sui lati blu; ogni lato blu in più la peggiora di 1)" if blue else ""))
		if blue:_cell(l1 if m.attack==null or id=="shoot" else _line(v),"ALTRI LATI",str(m.secondary),func():_edit(id,"secondary",-1),func():_edit(id,"secondary",1),"Difesa sugli altri lati")
		if int(m.get("riposte",0))>0:_cell(_line(v),"CONTRATTACCO",str(m.riposte),func():_edit(id,"riposte",-1),func():_edit(id,"riposte",1),"Dopo aver parato colpisce l'attaccante con questo valore")
		if m.attack!=null:
			var l2=_line(v)
			_cell(l2,"FATICA",str(int(m.fatigue)),func():_edit(id,"fatigue",-1),func():_edit(id,"fatigue",1),"Pallini neri: il colpo stanca, ogni punto di fatica toglie 1 all'attacco e alla difesa finché non si riposa")
			var iv=int(m.imbalance) if m.imbalance!=null else -1
			_cell(l2,"SBILANCIA",str(iv) if iv>=0 else "no",func():_edit(id,"imb",maxi(-1,iv-1),true),func():_edit(id,"imb",mini(6,iv+1),true),"Sbilanciamento: modificatore sulla tabella (con la stazza)")
		var l3=_line(v)
		var rest=bool(m.get("rest",false));var tired=int(m.fatigue)>0
		l3.add_child(_flag("riposo",rest,func():_edit(id,"rest",not rest,true),"Pallino bianco (riposo): a fine turno con questa pedina si recupera fatica" if not tired else "Con il pallino nero (fatica) il riposo non è possibile",tired))
		if m.attack!=null and id!="shoot":
			var multi=bool(m.get("multi",false))
			l3.add_child(_flag("multi",multi,func():_edit(id,"multi",not multi,true),"Multi attacco: colpisce tutti i nemici sui lati rossi, uno dopo l'altro (−2 a ogni colpo in più)"))
		var e=edits.get("moves",{}).get(id,{})
		if not e.is_empty():
			var no=edits.duplicate(true);no.moves.erase(id)
			var dv=BloodForge.points(def)-BloodForge.points(BloodForge.apply_edits(BloodForge.build(traits),no))
			var dl=ui.label("%+.1f"%dv,10,Color("e8a070") if dv>0 else Color("8fd08a"));dl.tooltip_text="Quanto spostano i punti i tuoi ritocchi su questa pedina";l3.add_child(dl)
	return hx
func _comb() -> void:
	ui.clear(comb)
	var top=HBoxContainer.new();top.add_theme_constant_override("separation",6);comb.add_child(top)
	top.add_child(ui.label("LE PEDINE",13,ui.GOLD))
	top.add_child(ui.label("· pennello per i lati:",12,ui.MUTED))
	for b in [["red","Rosso · colpisce"],["green","Verde · si muove"],["blue","Blu · para"]]:
		var key=b[0]
		var btn=ui._bar_check(b[1],brush==key,func(_v):brush=key;_comb(),"Clic su un lato di una pedina per accendere o spegnere questo colore");top.add_child(btn)
		btn.add_theme_color_override("font_color",TokenHex.COL[key].lightened(.25))
	var hint=ui.label("In alto il fronte. Rosso: da dove colpisce (ogni lato in più: attacco −1) · Verde: dove si muove (su un colpo o una parata è un passo prima o dopo l'azione) · Blu: da dove para (ogni lato in più: difesa +1). Prima le pedine base, poi quelle dell'arma, quelle in più (spente: + per accenderle) e le magie.",12,ui.MUTED)
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;comb.add_child(hint)
	var ids=all_def.moves.keys().filter(func(k):return not k in HIDDEN)
	var order=func(k):return (0 if k in BloodForge.BASE_IDS else (2 if k in BloodForge.EXTRA_IDS and not all_def.moves[k].get("native",false) else (3 if all_def.moves[k].get("spell",false) else 1)))
	var sorted_ids=[]
	for g in 4:sorted_ids+=ids.filter(func(k):return order.call(k)==g)   # base, arma, in più, magie (ordine stabile)
	ids=sorted_ids
	comb.add_child(_honeycomb(ids,86.0))
func _honeycomb(ids: Array,R: float) -> Control:
	# griglia ordinata, un esagono accanto all'altro senza incastri: a nido d'ape i valori di una pedina finivano
	# sopra gli angoli delle vicine (riquadri sovrapposti)
	var avail=maxf(460.0,get_viewport().get_visible_rect().size.x-440.0)
	var w=2*R;var h=1.732*R;var gap=8.0
	var cols=maxi(2,int((avail+gap)/(w+gap)))
	var rows=ceili(float(ids.size())/cols)
	var c=Control.new();c.custom_minimum_size=Vector2(mini(cols,ids.size())*(w+gap)-gap,rows*(h+gap))
	for k in ids.size():
		var col=k%cols;var row=k/cols
		var hx=_hex_for(ids[k],R);hx.position=Vector2(col*(w+gap),row*(h+gap));c.add_child(hx)
	return c

# ------------------------------------------------------------------ fascia del valore, collaudo, salvataggio
func _band() -> void:
	ui.clear(band)
	var pts=BloodForge.points(def);var over=pts-BloodForge.BUDGET
	var vb=VBoxContainer.new();vb.add_theme_constant_override("separation",0);band.add_child(vb)
	vb.add_child(ui.label("VALORE",11,ui.GOLD))
	vb.add_child(ui.label("%d / %d"%[roundi(pts),int(BloodForge.BUDGET)],30,ui.GOLD if over<=.5 else Color("e86a5a")))
	var mid=VBoxContainer.new();mid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;mid.add_theme_constant_override("separation",2);band.add_child(mid)
	var bar=ProgressBar.new();bar.min_value=0;bar.max_value=160;bar.value=pts;bar.show_percentage=false;bar.custom_minimum_size.y=10;mid.add_child(bar)
	var f=BloodForge.features(def)
	var msg=("Dentro il budget: restano %d punti."%roundi(-over)) if over<=.5 else ("Oltre il budget di %d punti: più forte della media. Si può salvare lo stesso."%roundi(over))
	if base_id!="":msg="Originale %d punti, ora %d."%[roundi(base_points),roundi(pts)]
	var problems: Array=BloodForge.validate(def)
	var l=ui.label(msg+"  ·  colpo %.1f ferite · subisce %.1f a colpo · %d ferite · budget = media dei personaggi ufficiali, 10 punti ≈ 5 vittorie su 100"%[f.off,f.sub,int(f.hp)],12,Color("8fd08a") if over<=.5 else Color("e86a5a"))
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;l.custom_minimum_size.x=240;mid.add_child(l)
	if not problems.is_empty():   # regole di costruzione delle pedine non rispettate: finché restano non si salva
		mid.add_child(ui.wrap_label("Pedine da sistemare prima di salvare: "+" · ".join(problems.slice(0,4))+(" · e altre %d"%(problems.size()-4) if problems.size()>4 else ""),12,Color("ff8a70"),240))
	test_label=ui.label("",12,ui.INK);test_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;test_label.custom_minimum_size.x=240;mid.add_child(test_label)
	var hp=HBoxContainer.new();hp.add_theme_constant_override("separation",3);hp.size_flags_vertical=Control.SIZE_SHRINK_CENTER;band.add_child(hp)
	hp.add_child(ui.label("Ferite",12,ui.MUTED))
	hp.add_child(_mini("-",func():edits.hp=int(edits.get("hp",0))-1;_rebuild(false),"Una ferita in meno"))
	hp.add_child(ui.label(str(int(def.hp)),15,ui.INK))
	hp.add_child(_mini("+",func():edits.hp=int(edits.get("hp",0))+1;_rebuild(false),"Una ferita in più"))
	var fb=ui._bar_button("Adatta al budget",_fit_budget,"Porta il valore a 100 cambiando le ferite");fb.size_flags_vertical=Control.SIZE_SHRINK_CENTER;band.add_child(fb)
	var tb=ui._bar_button("Collaudo",_run_test,"36 duelli simulati contro il cast ufficiale");tb.disabled=testing;tb.size_flags_vertical=Control.SIZE_SHRINK_CENTER;band.add_child(tb)
	var save=ui.button("Salva la variante" if base_id!="" else "Salva l'eroe",_save,true);save.disabled=not problems.is_empty()
	save.tooltip_text="Prima sistema le pedine segnalate" if not problems.is_empty() else ("Oltre i %d punti: si salva lo stesso, come eroe fuori budget"%int(BloodForge.BUDGET) if over>.5 else "");save.size_flags_vertical=Control.SIZE_SHRINK_CENTER;band.add_child(save)
	var saved=BloodForge.load_saved()
	if not saved.is_empty():
		var ob=OptionButton.new();ob.add_item("Eroi e varianti salvati");ob.add_theme_font_size_override("font_size",13)
		var ids=saved.keys()
		for id in ids:ob.add_item(str(saved[id].name))
		ob.item_selected.connect(func(n):if n>0:_open(ids[n-1]));ob.size_flags_vertical=Control.SIZE_SHRINK_CENTER;band.add_child(ob)
		var cur=str(var_info.get("id","")) if base_id!="" else str(traits.get("id",""))
		if cur!="" and saved.has(cur):
			var del=ui._bar_button("Elimina",func():BloodForge.delete_hero(cur);ui.game.catalog.erase(cur);BloodRules.extra_defs.erase(cur);traits.erase("id");var_info["id"]="";_rebuild(false),"Elimina questo salvataggio");del.size_flags_vertical=Control.SIZE_SHRINK_CENTER;band.add_child(del)
func _open(id: String) -> void:
	var saved=BloodForge.load_saved()
	if not saved.has(id):return
	if not ui.game.catalog.has(id):BloodRules.extra_defs[id]=saved[id];ui.game.add_definition(saved[id])
	_load_hero(id);_rebuild(true)
func _fit_budget() -> void:
	# porta il valore al budget cambiando le ferite (la cosa più neutra da ritoccare)
	for n in 80:
		var pts=BloodForge.points(def)
		if pts>BloodForge.BUDGET+.5:edits.hp=int(edits.get("hp",0))-1
		elif pts<BloodForge.BUDGET-3.0:edits.hp=int(edits.get("hp",0))+1
		else:break
		def=BloodForge.build_variant(base_id,var_info,edits) if base_id!="" else BloodForge.apply_edits(BloodForge.build(traits),edits)
		if int(def.hp)<=4:break
	_rebuild(false)
func _save() -> void:
	if base_id!="":
		if str(var_info.get("id",""))=="":var_info["id"]="var_%s_%d"%[base_id,Time.get_ticks_usec()%10000000]
		if str(var_info.get("name","")).strip_edges()=="":var_info["name"]=str(BloodForge.official(base_id).name)+" II"
		def=BloodForge.build_variant(base_id,var_info,edits)
		BloodForge.save_hero(def);BloodRules.extra_defs[def.id]=def;ui.game.add_definition(def)
		_band();test_label.text="Salvata: %s è nella scelta dei personaggi, fra gli eroi forgiati. L'originale resta com'era."%def.name;return
	if str(traits.get("id",""))=="":traits.id="forged_%d"%(Time.get_ticks_usec()%10000000)
	def=BloodForge.apply_edits(BloodForge.build(traits),edits)
	BloodForge.save_hero(def);BloodRules.extra_defs[def.id]=def;ui.game.add_definition(def)
	_band();test_label.text="Salvato: %s è nella scelta dei personaggi (fra gli eroi forgiati)."%def.name

const FOES=["zenyo","gascor","ut","shannon","kylvia","gandy","thorn","sanguinaria","ziggy"]
func _run_test() -> void:
	if testing:return
	testing=true;_band()
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
					"acting":
						var a=int(r.state.active)
						if not r.act(BloodAI.command(r,a)):r.act({"pass":true,"facing":int(r.state.fighters[a].facing)})
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
	_band()
	var parts=[]
	for foe in FOES:parts.append("%s %d%%"%[ui.game.catalog[foe].name,roundi(100*by[foe]/4.0)])
	var verdict="in linea con il cast" if wins/games>=.4 and wins/games<=.6 else ("troppo forte" if wins/games>.6 else "un po' debole")
	test_label.text="Collaudo: vince il %d%% dei duelli (%s; gli ufficiali vanno dal 34%% al 74%%) · %s"%[roundi(100*wins/games),verdict,", ".join(parts)]

# ------------------------------------------------------------------ anteprima 3D: corpo, armatura, armi, statura e la mossa scelta
var pv_vp: SubViewport
var pv_root: Node3D
var pv_model: Node3D
var pv_ap: AnimationPlayer
var pv_key:=""
var pv_label: Label
var pv_b3
var selected_id:="guard"
var pv_info:={}
func _make_preview(parent: Node) -> void:
	pv_b3=load("res://scripts/board3d.gd").new()   # solo per vestire il corpo (armi, scudo) come in partita
	var svc=SubViewportContainer.new();svc.stretch=true;svc.custom_minimum_size=Vector2(318,250);parent.add_child(svc)
	pv_vp=SubViewport.new();pv_vp.own_world_3d=true;pv_vp.msaa_3d=Viewport.MSAA_2X;svc.add_child(pv_vp)
	var w=Node3D.new();pv_vp.add_child(w)
	var env=WorldEnvironment.new();var e=Environment.new();e.background_mode=Environment.BG_COLOR;e.background_color=Color(.1,.075,.055)
	e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color(.62,.58,.55);e.ambient_light_energy=.75;env.environment=e;w.add_child(env)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-42,-35,0);sun.light_energy=1.25;w.add_child(sun)
	var back=DirectionalLight3D.new();back.rotation_degrees=Vector3(-20,150,0);back.light_energy=.45;w.add_child(back)
	var plate=MeshInstance3D.new();var cyl=CylinderMesh.new();cyl.top_radius=.62;cyl.bottom_radius=.62;cyl.height=.03;cyl.radial_segments=6;plate.mesh=cyl
	var pm=StandardMaterial3D.new();pm.albedo_color=Color(.22,.16,.1);pm.roughness=.8;plate.material_override=pm;plate.rotation_degrees.y=30;w.add_child(plate)
	pv_root=Node3D.new();w.add_child(pv_root)
	var cam=Camera3D.new();cam.fov=30;w.add_child(cam);cam.position=Vector3(0,1.15,3.9);cam.look_at(Vector3(0,.66,0))
	cam.current=true
	svc.gui_input.connect(func(ev):   # trascina per girare il personaggio
		if ev is InputEventMouseMotion and (ev.button_mask&MOUSE_BUTTON_MASK_LEFT)!=0:pv_root.rotation.y+=ev.relative.x*.012
		if ev is InputEventScreenDrag:pv_root.rotation.y+=ev.relative.x*.012)
	pv_label=ui.label("",12,ui.MUTED);pv_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;parent.add_child(pv_label)
func _pick(id: String) -> void:
	selected_id=id;_comb();_update_preview()
func _update_preview() -> void:
	if pv_root==null:return
	var dr: Dictionary=def.get("dress",{});var body=str(def.get("look","f_nomade"))
	var key="%s|%s|%s|%.2f"%[body,dr.get("weapon",""),dr.get("off",""),float(dr.get("scale",1.0))]
	if key!=pv_key:
		pv_key=key
		if pv_model:pv_model.queue_free();pv_model=null;pv_ap=null
		var path=str(pv_b3.MODELS.get(body,""))
		if path!="" and ResourceLoader.exists(path):
			pv_model=load(path).instantiate();pv_root.add_child(pv_model)
			if dr.is_empty():pv_model.scale=Vector3.ONE*.58   # personaggio del gioco: armi e scudo sono già i suoi
			else:pv_b3._dress(pv_model,dr)
			pv_model.scale*=1.3   # più grande che sulla mappa: riempie l'anteprima
			var aps=pv_model.find_children("*","AnimationPlayer",true,false)
			if not aps.is_empty():
				pv_ap=aps[0]
				pv_info={"model":pv_model,"root":pv_root,"ap":pv_ap,"sfx":{"lancia":" lancia","bastone":" lancia","ascia":" 2h"}.get(str(dr.get("weapon","")),"")}
				pv_b3._extract_root_motion(pv_info)   # il bacino resta sopra la basetta, come in partita
				pv_b3.build_gestures(pv_info,def)       # gli stessi gesti della partita: colpi e parate dal lato giusto, seconda lama
				pv_ap.animation_finished.connect(func(n):   # la mossa si ripete, con una breve pausa
					if is_inside_tree():get_tree().create_timer(.6).timeout.connect(func():if is_instance_valid(pv_ap) and pv_ap.assigned_animation==n:pv_ap.play(n)))
	if pv_ap==null:pv_label.text="";return
	if not all_def.moves.has(selected_id) or (base_id=="" and not BloodForge.is_on(traits,selected_id) and not all_def.moves[selected_id].get("native",false)):selected_id="guard" if all_def.moves.has("guard") else str(all_def.moves.keys()[0])
	var bow=selected_id in ["shoot","load"]
	for n in ["Arco","FrecciaIncoccata"]:
		var g=pv_model.find_child(n,true,false)
		if g:g.visible=bow and (n!="FrecciaIncoccata" or selected_id=="shoot")
	var sw=pv_model.find_child("Spada",true,false)
	if sw and pv_model.find_child("Arco",true,false):sw.visible=not bow
	var clip=_preview_clip(selected_id,bow)
	pv_ap.play(clip,.15)
	var m=all_def.moves.get(selected_id,{})
	pv_label.text="%s · clic su una pedina per vederla · trascina per girarlo"%str(m.get("name",""))
func _preview_clip(id: String,bow: bool) -> String:
	var m=all_def.moves.get(id,{})
	var base=str(pv_b3.CLIP.get(id,"In guardia"))
	var cands=[base]+Array(pv_b3.CLIP_FALLBACK.get(base,[]))
	var own=str(pv_b3.OWN_CLIP.get(id,""))
	if own!="" and pv_ap.has_animation(own):return own   # mosse proprie del modello (Shaara)
	if m.get("spell",false) and not pv_ap.has_animation(base):cands=["Affondo"]   # i maghi hanno la clip di ogni incantesimo
	if id=="concentrate":cands=["Riposo","In guardia"]
	if bow:cands=[base+" arco",base]
	var gen=str(pv_b3.GEN_CLIP.get(id,""))
	if not bow and gen!="" and pv_ap.has_animation("g/"+gen):return "g/"+gen
	for c in cands:
		var nm=str(pv_b3._anim(pv_info,c))
		if pv_ap.has_animation(nm):return nm
	return str(pv_b3._anim(pv_info,"In guardia"))
