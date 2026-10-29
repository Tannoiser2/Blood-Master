extends VBoxContainer
## "La forgia degli eroi" come una scheda del personaggio: a sinistra nome, ritratto, caratteristiche,
## carattere ed equipaggiamento; a destra le pedine a nido d'ape (grandi, con i valori già calcolati e
## un + e un − su ogni valore, lati cliccabili); in basso, compatta, la fascia del valore e del budget.

class TokenHex extends Control:
	## una pedina: esagono coi lati colorati cliccabili (in alto il fronte, poi in senso orario)
	signal side_clicked(s: int)
	var m: Dictionary
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
		if tex:
			var w=R*1.25;draw_texture_rect(tex,Rect2(size*.5-Vector2(w,w*.86)*.5,Vector2(w,w*.86)),false,Color(1,1,1,.16 if on else .08))
		for s in 6:   # lato s fra i vertici a 240+60s e 300+60s gradi; più colori = strisce affiancate
			var n=0
			for c in ["red","green","blue"]:
				if s in m.get(c,[]):
					draw_line(_corner((4+s)%6,3+n*6),_corner((5+s)%6,3+n*6),COL[c] if on else COL[c].darkened(.5),5.0,true);n+=1
			if n==0:draw_line(_corner((4+s)%6,3),_corner((5+s)%6,3),Color(1,1,1,.14),1.5,true)
		draw_circle(size*.5+Vector2(0,-R*.72),3.0,Color(1,1,1,.7))   # puntino del fronte
	func _gui_input(ev: InputEvent) -> void:
		if not on:return
		if ev is InputEventMouseButton and ev.pressed and ev.button_index==MOUSE_BUTTON_LEFT:
			var v: Vector2=ev.position-size*.5
			if v.length()<R*.62:return   # al centro ci sono i valori
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
const HIDDEN=["again","unbalanced","down","rise"]   # pedine di stato: non si modificano

func setup(main_ui,hero_id: String="") -> void:
	ui=main_ui
	traits=BloodForge.default_traits()
	if hero_id!="" and ui.game.catalog.has(hero_id) and ui.game.catalog[hero_id].has("traits"):
		traits=BloodForge.migrate(ui.game.catalog[hero_id].traits);traits.id=hero_id
		edits=ui.game.catalog[hero_id].get("edits",{"hp":0,"moves":{}}).duplicate(true)
	size_flags_vertical=Control.SIZE_EXPAND_FILL;size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",8)
	var head=HBoxContainer.new();add_child(head)
	head.add_child(ui.button("‹ Indietro",func():on_close.call()))
	head.add_child(ui.label("LA FORGIA DEGLI EROI",22,ui.GOLD))
	var sub=ui.label("Le caratteristiche calcolano le pedine; poi ritocca ogni valore e ogni lato, restando nel budget.",13,ui.MUTED);head.add_child(sub)
	var cols=HBoxContainer.new();cols.size_flags_vertical=Control.SIZE_EXPAND_FILL;cols.add_theme_constant_override("separation",10);add_child(cols)
	sheet=_scroll_panel(cols,340)
	comb=_scroll_panel(cols,0);comb.get_parent().get_parent().get_parent().get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var bp=ui.panel_content(self,8);band=HBoxContainer.new();band.add_theme_constant_override("separation",14);bp.add_child(band)
	_rebuild(true)

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
func _sheet() -> void:
	ui.clear(sheet)
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
	face.custom_minimum_size=Vector2(118,118);face.tooltip_text="La miniatura: "+str(BloodForge.BODY_NAMES.get(body,"il corpo di "+str(ui.game.catalog[body].name) if ui.game.catalog.has(body) else body));fr.add_child(face)
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
	var base=BloodForge.build(traits)
	base_points=BloodForge.points(base)
	def=BloodForge.apply_edits(base,edits)
	all_def=BloodForge.apply_edits(BloodForge.build_all(traits),edits)
	if full:_sheet()
	_comb();_band()
func _edit(id: String,field: String,value,absolute:=false) -> void:
	var me: Dictionary=edits.get("moves",{});var e: Dictionary=me.get(id,{})
	if absolute:e[field]=value
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
	var off: Array=traits.get("off",[]).duplicate()
	if id in off:off.erase(id)
	else:off.append(id)
	traits.off=off;_rebuild(false)
func _mini(text: String,cb: Callable,tip:="") -> Button:
	var b=Button.new();b.text=text;b.tooltip_text=tip;b.focus_mode=Control.FOCUS_NONE;b.custom_minimum_size=Vector2(18,18)
	b.add_theme_font_size_override("font_size",12);b.pressed.connect(cb);b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	var st=ui.box(Color(.35,.25,.14,.9),3);var sh=ui.box(Color(.55,.4,.2,.95),3)
	for k in ["normal","focus"]:st.content_margin_left=3;st.content_margin_right=3;st.content_margin_top=0;st.content_margin_bottom=0;b.add_theme_stylebox_override(k,st)
	for k in ["hover","pressed"]:sh.content_margin_left=3;sh.content_margin_right=3;sh.content_margin_top=0;sh.content_margin_bottom=0;b.add_theme_stylebox_override(k,sh)
	for k in ["font_color","font_hover_color","font_pressed_color"]:b.add_theme_color_override(k,ui.INK)
	return b
## un valore con il suo − e + (compatto: due per riga dentro l'esagono)
func _cell(parent: Node,label: String,value: String,minus: Callable,plus: Callable,tip: String) -> void:
	var r=HBoxContainer.new();r.add_theme_constant_override("separation",1);r.tooltip_text=tip;r.mouse_filter=Control.MOUSE_FILTER_PASS;parent.add_child(r)
	var l=ui.label(label,10,ui.MUTED);l.custom_minimum_size.x=20;l.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;r.add_child(l)
	r.add_child(_mini("−",minus,tip))
	var v=ui.label(value,13,ui.INK);v.custom_minimum_size.x=22;v.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;r.add_child(v)
	r.add_child(_mini("+",plus,tip))
func _line(parent: Node) -> HBoxContainer:
	var h=HBoxContainer.new();h.alignment=BoxContainer.ALIGNMENT_CENTER;h.add_theme_constant_override("separation",6);parent.add_child(h);return h
func _hex_for(id: String,R: float) -> Control:
	var m: Dictionary=all_def.moves[id];var opt=not id in BloodForge.BASE_IDS;var on=not id in traits.get("off",[])
	var hx=TokenHex.new(R);hx.m=m;hx.on=on
	var tp=Art.token(str(m.get("texture","")))
	if ResourceLoader.exists(tp):hx.tex=load(tp)
	hx.side_clicked.connect(func(s):_side(id,s))
	var v=VBoxContainer.new();v.add_theme_constant_override("separation",2);v.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hx.add_child(v)
	var title=_line(v)
	var nm=ui.label(str(m.name),13,ui.GOLD if on else ui.MUTED);nm.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.add_child(nm)
	if opt:title.add_child(_mini("✓" if on else "＋",func():_toggle_token(id),"Pedina attiva: clic per toglierla" if on else "Pedina spenta: clic per aggiungerla"))
	if on:
		var blue=not m.blue.is_empty()
		if m.get("spell",false):
			var sp=ui.label("magia · costo %d"%int(m.get("cost",1)),10,ui.MUTED);sp.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;v.add_child(sp)
		var l1=_line(v)
		if m.attack!=null and id!="shoot":_cell(l1,"Att",str(m.attack),func():_edit(id,"attack",-1),func():_edit(id,"attack",1),"Valore d'attacco")
		_cell(l1,"Blu" if blue else "Dif",str(m.defense),func():_edit(id,"defense",-1),func():_edit(id,"defense",1),"Difesa (più bassa è meglio)"+(" sui lati blu" if blue else ""))
		if blue:_cell(l1 if m.attack==null or id=="shoot" else _line(v),"Altri",str(m.secondary),func():_edit(id,"secondary",-1),func():_edit(id,"secondary",1),"Difesa sugli altri lati")
		if m.attack!=null:
			var l2=_line(v)
			_cell(l2,"Fat","●".repeat(int(m.fatigue)) if int(m.fatigue)>0 else "—",func():_edit(id,"fatigue",-1),func():_edit(id,"fatigue",1),"Pallini neri: il colpo stanca, ogni punto di fatica toglie 1 all'attacco e alla difesa finché non si riposa")
			var iv=int(m.imbalance) if m.imbalance!=null else -1
			_cell(l2,"Sbil",str(iv) if iv>=0 else "—",func():_edit(id,"imb",maxi(-1,iv-1),true),func():_edit(id,"imb",mini(6,iv+1),true),"Sbilanciamento: modificatore sulla tabella (con la stazza); — = non sbilancia")
		var l3=_line(v)
		var rest=bool(m.get("rest",false))
		l3.add_child(_mini("☾ riposo" if rest else "☾ no",func():_edit(id,"rest",not rest,true),"Riposo: a fine turno con questa pedina si recupera fatica"))
		var e=edits.get("moves",{}).get(id,{})
		if not e.is_empty():
			var no=edits.duplicate(true);no.moves.erase(id)
			var dv=BloodForge.points(def)-BloodForge.points(BloodForge.apply_edits(BloodForge.build(traits),no))
			var dl=ui.label("%+.1f"%dv,12,Color("e8a070") if dv>0 else Color("8fd08a"));dl.tooltip_text="Quanto spostano i punti i tuoi ritocchi su questa pedina";l3.add_child(dl)
	# centra il contenuto nell'esagono
	var ms=v.get_combined_minimum_size();v.size=ms;v.position=(hx.size-ms)*.5+Vector2(0,4)
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
	var hint=ui.label("In alto il fronte. Rosso: da dove colpisce · Verde: dove si muove (su un colpo o una parata è un passo prima o dopo l'azione) · Blu: da dove para. Le pedine con ✓ si possono togliere.",12,ui.MUTED)
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;comb.add_child(hint)
	var ids=all_def.moves.keys().filter(func(k):return not k in HIDDEN)
	var base_ids=ids.filter(func(k):return k in BloodForge.BASE_IDS)
	var weapon_ids=ids.filter(func(k):return not k in BloodForge.BASE_IDS and not all_def.moves[k].get("spell",false))
	var spell_ids=ids.filter(func(k):return all_def.moves[k].get("spell",false))
	var R=110.0
	for group in [["MOVIMENTO E DIFESA",base_ids],["ARMA",weapon_ids],["MAGIE",spell_ids]]:
		if group[1].is_empty():continue
		var gl=ui.label(group[0],12,ui.GOLD);comb.add_child(gl)
		comb.add_child(_honeycomb(group[1],R))
func _honeycomb(ids: Array,R: float) -> Control:
	# colonne sfalsate di mezza altezza (esagoni coi lati piatti in alto e in basso)
	var avail=maxf(600.0,get_viewport().get_visible_rect().size.x-420.0)
	var w=2*R;var h=1.732*R;var gap=6.0
	var cols=maxi(2,int((avail-w)/(w*.75+gap))+1)
	var rows=ceili(float(ids.size())/cols)
	var c=Control.new();c.custom_minimum_size=Vector2(w+(mini(cols,ids.size())-1)*(w*.75+gap),rows*(h+gap)+h*.5+4)
	for k in ids.size():
		var col=k%cols;var row=k/cols
		var hx=_hex_for(ids[k],R);hx.position=Vector2(col*(w*.75+gap),row*(h+gap)+((h+gap)*.5 if col%2==1 else 0.0));c.add_child(hx)
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
	var msg=("Dentro il budget: restano %d punti."%roundi(-over)) if over<=.5 else ("Oltre il budget di %d punti: togli qualcosa."%roundi(over))
	var l=ui.label(msg+"  ·  colpo %.1f ferite · subisce %.1f a colpo · %d ferite · budget = media dei personaggi ufficiali, 10 punti ≈ 5 vittorie su 100"%[f.off,f.sub,int(f.hp)],12,Color("8fd08a") if over<=.5 else Color("e86a5a"))
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;mid.add_child(l)
	test_label=ui.label("",12,ui.INK);test_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;mid.add_child(test_label)
	var hp=HBoxContainer.new();hp.add_theme_constant_override("separation",3);hp.size_flags_vertical=Control.SIZE_SHRINK_CENTER;band.add_child(hp)
	hp.add_child(ui.label("Ferite",12,ui.MUTED))
	hp.add_child(_mini("−",func():edits.hp=int(edits.get("hp",0))-1;_rebuild(false),"Una ferita in meno"))
	hp.add_child(ui.label(str(int(def.hp)),15,ui.INK))
	hp.add_child(_mini("+",func():edits.hp=int(edits.get("hp",0))+1;_rebuild(false),"Una ferita in più"))
	var fb=ui._bar_button("Adatta al budget",_fit_budget,"Porta il valore a 100 cambiando le ferite");fb.size_flags_vertical=Control.SIZE_SHRINK_CENTER;band.add_child(fb)
	var tb=ui._bar_button("Collaudo",_run_test,"36 duelli simulati contro il cast ufficiale");tb.disabled=testing;tb.size_flags_vertical=Control.SIZE_SHRINK_CENTER;band.add_child(tb)
	var save=ui.button("Salva l'eroe",_save,true);save.disabled=over>.5;save.tooltip_text="Si può salvare solo dentro il budget" if over>.5 else "";save.size_flags_vertical=Control.SIZE_SHRINK_CENTER;band.add_child(save)
	var saved=BloodForge.load_saved()
	if not saved.is_empty():
		var ob=OptionButton.new();ob.add_item("Eroi salvati…");ob.add_theme_font_size_override("font_size",13)
		var ids=saved.keys()
		for id in ids:ob.add_item(str(saved[id].name))
		ob.item_selected.connect(func(n):if n>0:_open(ids[n-1]));ob.size_flags_vertical=Control.SIZE_SHRINK_CENTER;band.add_child(ob)
		if str(traits.get("id",""))!="" and saved.has(str(traits.id)):
			var cur=str(traits.id)
			band.add_child(ui._bar_button("✕ Elimina",func():BloodForge.delete_hero(cur);ui.game.catalog.erase(cur);BloodRules.extra_defs.erase(cur);traits.erase("id");_rebuild(false),"Elimina questo eroe salvato"))
func _open(id: String) -> void:
	var saved=BloodForge.load_saved()
	if not saved.has(id):return
	traits=BloodForge.migrate(saved[id].traits);traits.id=id
	edits=saved[id].get("edits",{"hp":0,"moves":{}}).duplicate(true);_rebuild(true)
func _fit_budget() -> void:
	# porta il valore al budget cambiando le ferite (la cosa più neutra da ritoccare)
	for n in 80:
		var pts=BloodForge.points(def)
		if pts>BloodForge.BUDGET+.5:edits.hp=int(edits.get("hp",0))-1
		elif pts<BloodForge.BUDGET-3.0:edits.hp=int(edits.get("hp",0))+1
		else:break
		def=BloodForge.apply_edits(BloodForge.build(traits),edits)
		if int(def.hp)<=4:break
	_rebuild(false)
func _save() -> void:
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
