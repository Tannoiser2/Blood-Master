extends Control

const BG=Color("0b1215")
const PANEL=Color("152024")
const GOLD=Color("dfbd7f")
const INK=Color("e9e5da")
const MUTED=Color("9eafad")
var game=BloodRules.new()
var board: ArenaBoard
var board3d: ArenaBoard3D
var minis_3d=false
var page: VBoxContainer
var status: Label
var sidebar: VBoxContainer
var roster_box: VBoxContainer
var log_box: RichTextLabel
var turn_label: Label
var move_grid: GridContainer
var roster: Array=[]
var mode="solo"
var scenario="frontale"
var selected_move=""
var selected_cell=""
var selected_facing=0
var selected_path: Array=[]
var focus_index=-1
var selected_extra=0
var handicap_picks: Array=[]
var auction_amount=1
var speed=.65
var busy=false
var auto_draw=true
var board_grid=false
var blood_on=false
var sound_on=true
var labels_on=true
var house_rules=true
var clear_plates=false
var _last_hp={}
var showing_game=false
var manual_window: Window
var manual_page=2
var network: Node
var room_code=""
var net_seat=-1
var net_host=false
var remote_ready: Array=[]
var title_font: Font
var inspect_dialog: Window
var message=""
var menu_options: Array=[]
var preview_overlay: Control

func _ready() -> void:
	_build_theme()
	if OS.get_environment("BM_SMOKE")=="1":
		roster=[{"character":"gascor","team":0,"controller":"human","seat":0},{"character":"anteos","team":1,"controller":"ai","seat":1}]
		_start_local();return
	_show_menu()
func _build_theme() -> void:
	var t=Theme.new();t.default_font_size=17
	t.set_color("font_color","Label",INK);t.set_color("font_color","Button",INK)
	t.set_color("font_color","RichTextLabel",INK)
	for typ in ["Button","OptionButton"]:
		for state in ["normal","hover","pressed","disabled","focus"]:
			var b=box(Color("233234") if state=="normal" else (Color("40534c") if state in ["hover","focus"] else Color("172125")),8)
			b.content_margin_left=15;b.content_margin_right=15;b.content_margin_top=10;b.content_margin_bottom=10
			if state=="focus":b.set_border_width_all(2);b.border_color=GOLD
			t.set_stylebox(state,typ,b)
		t.set_color("font_disabled_color",typ,Color("65736e"))
	t.set_stylebox("normal","LineEdit",box(Color("0c171a"),6))
	t.set_stylebox("panel","PanelContainer",box(PANEL,12))
	t.set_constant("separation","VBoxContainer",10);t.set_constant("separation","HBoxContainer",10)
	t.set_color("font_color","OptionButton",INK)
	t.set_stylebox("background","ProgressBar",box(Color("0a1518"),4))
	t.set_stylebox("fill","ProgressBar",box(Color("65bfb0"),4))
	theme=t
	var bg=ColorRect.new();bg.color=BG;bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);bg.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(bg)
	var margin=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,20)
	add_child(margin);page=VBoxContainer.new();margin.add_child(page)
func box(color: Color,radius: int=8) -> StyleBoxFlat:
	var b=StyleBoxFlat.new();b.bg_color=color;b.set_corner_radius_all(radius);return b
func label(text: String,font_size: int=17,color: Color=INK) -> Label:
	var l=Label.new();l.text=text;l.add_theme_font_size_override("font_size",font_size);l.add_theme_color_override("font_color",color);return l
func button(text: String,callback: Callable,primary: bool=false) -> Button:
	var b=Button.new();b.text=text;b.pressed.connect(callback);b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	if primary:
		var s=box(GOLD);s.content_margin_left=20;s.content_margin_right=20;s.content_margin_top=13;s.content_margin_bottom=13
		b.add_theme_stylebox_override("normal",s);b.add_theme_color_override("font_color",Color("151b19"))
	return b
func clear(node: Node) -> void:
	for c in node.get_children():node.remove_child(c);c.queue_free()
func spacer() -> Control:
	var s=Control.new();s.size_flags_horizontal=Control.SIZE_EXPAND_FILL;return s
func panel_content(parent: Node,pad: int=16) -> VBoxContainer:
	var p=PanelContainer.new();parent.add_child(p);var margin=MarginContainer.new();p.add_child(margin)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,pad)
	var v=VBoxContainer.new();margin.add_child(v);return v
func _header(subtitle: String) -> void:
	var row=HBoxContainer.new();page.add_child(row)
	var title=VBoxContainer.new();row.add_child(title)
	title.add_child(label("BLOOD MASTER",29,GOLD));title.add_child(label(subtitle,13,MUTED))
	row.add_child(spacer())
	if showing_game:
		turn_label=label("",17,GOLD);row.add_child(turn_label)
		row.add_child(button("Salva",_save_game))
	row.add_child(button("Regolamento",_open_manual))
	row.add_child(button("Crediti",_credits))
	if showing_game:row.add_child(button("Menu",_confirm_menu))
# --- Menu: preparazione dello scontro -------------------------------------------
# A sinistra la scheda del personaggio scelto con tutte le sue tessere a nido d'ape;
# al centro le schede disponibili; ai lati le due squadre. Un clic su una scheda la
# manda nella sua squadra: i Blu (Ordine della Lama) solo a sinistra, i Rossi (Ordine
# dell'Ombra) solo a destra. Maghi e scheletri sono fuori dagli Ordini: la metà della
# scheda su cui clicchi decide la squadra.
const TEAM_COLOR=[Color("69cec1"),Color("e68078")]
const TEAM_NAME=["BLU · ORDINE DELLA LAMA","ROSSI · ORDINE DELL’OMBRA"]
var art="classica"          # grafica delle schede: "classica" o "reborn"
var detail_id=""            # personaggio mostrato nel pannello di sinistra
func _load_settings() -> void:
	if not FileAccess.file_exists("user://settings.json"):return
	var d=JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
	if d is Dictionary:art=str(d.get("art","classica"));blood_on=bool(d.get("blood",false));sound_on=bool(d.get("sound",true));labels_on=bool(d.get("labels",true));house_rules=bool(d.get("house",true));clear_plates=bool(d.get("clear_plates",false))
func _save_settings() -> void:
	var f=FileAccess.open("user://settings.json",FileAccess.WRITE)
	if f:f.store_string(JSON.stringify({"art":art,"blood":blood_on,"sound":sound_on,"labels":labels_on,"house":house_rules,"clear_plates":clear_plates}))
func card_path(id: String) -> String:
	var r="res://assets/reborn/cards/%s.webp"%id
	if art=="reborn" and ResourceLoader.exists(r):return r
	return game.catalog[id].card
func mini_path(id: String) -> String:
	var r="res://assets/reborn/minis/%s.webp"%id
	return r if art=="reborn" and ResourceLoader.exists(r) else ""
func _free_agent(id: String) -> bool:
	return int(game.catalog[id].team)<0                       # maghi e scheletri
func _selectable() -> Array:
	return game.catalog.keys().filter(func(k):return game.catalog[k].kind!="golem")   # il Golem si evoca in partita
func _locked(id: String) -> bool:
	# negli scontri a squadre ogni combattente sta nel suo Ordine; nello scontro libero no
	return scenario!="libero" and not _free_agent(id)
func _card_widget(id: String,width: float,on_click: Callable,halves:=false) -> TextureRect:
	var t=TextureRect.new();t.texture=load(card_path(id));t.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;t.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex: Texture2D=t.texture;t.custom_minimum_size=Vector2(width,width*tex.get_height()/tex.get_width())
	t.mouse_filter=Control.MOUSE_FILTER_STOP;t.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	t.tooltip_text=game.catalog[id].name+" · "+game.catalog[id].title
	if halves:   # la metà sotto il mouse si colora della squadra in cui andrà la scheda
		var tint=ColorRect.new();tint.mouse_filter=Control.MOUSE_FILTER_IGNORE;tint.visible=false;t.add_child(tint)
		var locked=_locked(id);var own=int(game.catalog[id].team)
		t.gui_input.connect(func(ev):
			if ev is InputEventMouseMotion:
				var side=own if locked else (0 if ev.position.x<t.size.x*.5 else 1)
				var c=TEAM_COLOR[side];c.a=.28;tint.color=c;tint.visible=true
				tint.position=Vector2(0 if locked or side==0 else t.size.x*.5,0);tint.size=Vector2(t.size.x if locked else t.size.x*.5,t.size.y))
		t.mouse_exited.connect(func():tint.visible=false)
	t.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index==MOUSE_BUTTON_LEFT:on_click.call(ev.position.x/maxf(t.size.x,1.0)))
	return t
func _add_to_team(id: String,team: int) -> void:
	if roster.size()>=16:message="Al massimo sedici personaggi nello scontro.";_show_menu();return
	if _locked(id):team=int(game.catalog[id].team)                          # lucchetto: resta nel suo Ordine
	var human=roster.any(func(r):return r.controller=="human")
	roster.append({"character":id,"team":team,"controller":"ai" if mode=="solo" and human else "human","seat":roster.size()})
	message="";_show_menu()
func _remove_from_team(i: int) -> void:
	roster.remove_at(i)
	for k in roster.size():roster[k].seat=k
	_show_menu()
func _set_scenario(n: int) -> void:
	scenario=["frontale","libero","bloodmaster"][n]
	for r in roster:
		if _locked(r.character):r.team=int(game.catalog[r.character].team)    # chi era nella squadra sbagliata torna nel suo Ordine
	_show_menu()
func _show_menu() -> void:
	showing_game=false;clear(page);menu_options=[]
	if not has_meta("settings_loaded"):_load_settings();set_meta("settings_loaded",true)
	_header("EDIZIONE DELUXE · VERSIONE IN SVILUPPO")
	if roster.is_empty() and not has_meta("roster_default"):
		set_meta("roster_default",true)
		roster=[{"character":"gascor","team":0,"controller":"human","seat":0},{"character":"anteos","team":1,"controller":"ai","seat":1}]
	var top=HBoxContainer.new();page.add_child(top)
	for option in [["solo","Contro IA"],["local","Stesso schermo"],["online","Online"]]:
		var b=button(option[1],func():mode=option[0];_show_menu())
		if mode==option[0]:b.add_theme_color_override("font_color",GOLD)
		top.add_child(b)
	top.add_child(spacer())
	top.add_child(label("SCENARIO",13,GOLD))
	var scene_choice=OptionButton.new();scene_choice.add_item("Scontro frontale · squadre e pace/guerra");scene_choice.add_item("Scontro libero · squadre a scelta");scene_choice.add_item("Blood Master · asta e 3 round")
	scene_choice.select(["frontale","libero","bloodmaster"].find(scenario));scene_choice.item_selected.connect(_set_scenario);top.add_child(scene_choice)
	top.add_child(spacer());top.add_child(label("Regole",14,MUTED))
	for option in [[false,"Originali"],[true,"Modificate"]]:
		var rb=button(option[1],func():house_rules=option[0];_save_settings();_show_menu())
		rb.tooltip_text="Modificate: la pedina \"a terra\" fa cadere solo con 1-2 sul dado (con 6 ci si rimette in guardia) e chi viene sbilanciato arretra sempre di almeno un esagono." if option[0] else "Il regolamento originale di Blood Master."
		if house_rules==option[0]:rb.add_theme_color_override("font_color",GOLD)
		top.add_child(rb)
	top.add_child(spacer());top.add_child(label("Grafica",14,MUTED))
	for option in [["classica","Classica"],["reborn","Reborn"]]:
		var b=button(option[1],func():art=option[0];_save_settings();_show_menu())
		if art==option[0]:b.add_theme_color_override("font_color",GOLD)
		top.add_child(b)
	var cols=HBoxContainer.new();cols.size_flags_vertical=Control.SIZE_EXPAND_FILL;cols.add_theme_constant_override("separation",14);page.add_child(cols)
	_team_column(cols,0)
	var pool=panel_content(cols,12);pool.get_parent().get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var hint="Clic sulla metà sinistra della scheda: Blu · sulla metà destra: Rossi" if scenario=="libero" else "Clic su una scheda: va nel suo Ordine · maghi e scheletri: metà sinistra Blu, metà destra Rossi"
	var h=label(hint,13,MUTED);h.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;pool.add_child(h)
	var scroll=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;pool.add_child(scroll)
	var inner=VBoxContainer.new();inner.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(inner)
	var taken=roster.map(func(r):return r.character)
	for group in [["COMBATTENTI",false],["MAGHI E SCHELETRI",true]]:
		var t=label(group[0],13,GOLD);t.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;inner.add_child(t)
		var center=CenterContainer.new();inner.add_child(center)
		var grid=GridContainer.new();grid.columns=3;grid.add_theme_constant_override("h_separation",12);grid.add_theme_constant_override("v_separation",8);center.add_child(grid)
		for id in _selectable():
			if _free_agent(id)!=group[1] or id in taken:continue
			grid.add_child(_pool_card(id))
	_team_column(cols,1)
	var bottom=HBoxContainer.new();page.add_child(bottom)
	if mode=="online":
		var online=VBoxContainer.new();online.size_flags_horizontal=Control.SIZE_EXPAND_FILL;bottom.add_child(online);_online_menu(online)
	else:
		bottom.add_child(button("Entra nell’arena",_start_local,true))
	if FileAccess.file_exists("user://battle.json"):bottom.add_child(button("Riprendi la partita salvata",_load_game))
	status=label(message,14,GOLD);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.size_flags_horizontal=Control.SIZE_EXPAND_FILL;bottom.add_child(status)
func _pool_card(id: String) -> Control:
	var v=VBoxContainer.new();v.add_theme_constant_override("separation",2)
	var locked=_locked(id);var own=int(game.catalog[id].team)
	v.add_child(_card_widget(id,262,func(x):_add_to_team(id,own if locked else (0 if x<.5 else 1)),true))
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",4);v.add_child(row)
	if locked:
		row.add_child(label("◀ solo Blu" if own==0 else "",12,TEAM_COLOR[0]))
	else:
		row.add_child(label("◀ Blu",12,TEAM_COLOR[0]))
	row.add_child(spacer())
	var info=Button.new();info.text="Mosse";info.tooltip_text="Scheda e tessere";info.add_theme_font_size_override("font_size",12)
	for st in ["normal","hover","pressed","focus"]:
		var sb=box(Color("233234") if st!="hover" else Color("40534c"),6);sb.content_margin_left=8;sb.content_margin_right=8;sb.content_margin_top=2;sb.content_margin_bottom=2;info.add_theme_stylebox_override(st,sb)
	info.pressed.connect(func():_show_detail(id));row.add_child(info)
	row.add_child(spacer())
	if locked:
		row.add_child(label("solo Rossi ▶" if own==1 else "",12,TEAM_COLOR[1]))
	else:
		row.add_child(label("Rossi ▶",12,TEAM_COLOR[1]))
	return v
func _team_column(parent: Node,team: int) -> void:
	var v=panel_content(parent,12);v.get_parent().get_parent().custom_minimum_size.x=250
	var members=[]
	for i in roster.size():
		if int(roster[i].team)==team:members.append(i)
	v.add_child(label(TEAM_NAME[team],13,TEAM_COLOR[team]))
	v.add_child(label("%d personaggi"%members.size() if members.size()!=1 else "1 personaggio",12,MUTED))
	var scroll=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;v.add_child(scroll)
	var list=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(list)
	if members.is_empty():
		var l=label("Clicca una scheda al centro per aggiungere un personaggio.",13,MUTED);l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;l.custom_minimum_size.x=210;list.add_child(l)
	for i in members:
		var id: String=roster[i].character
		list.add_child(_card_widget(id,218,func(_x):_show_detail(id)))
		var row=HBoxContainer.new();row.add_theme_constant_override("separation",6);list.add_child(row)
		var who=Button.new();who.text="Persona" if roster[i].controller=="human" else "IA";who.tooltip_text="Chi muove questo personaggio"
		who.pressed.connect(func():roster[i].controller="ai" if roster[i].controller=="human" else "human";_show_menu());row.add_child(who)
		row.add_child(spacer())
		var out=Button.new();out.text="✕";out.tooltip_text="Rimetti al centro";out.pressed.connect(func():_remove_from_team(i));row.add_child(out)
func _show_detail(id: String) -> void:
	# finestra sopra il menu con scheda e tessere; si chiude cliccando fuori o su Chiudi
	detail_id=id
	var layer=Control.new();layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(layer)
	var dim=ColorRect.new();dim.color=Color(0,0,0,.6);dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layer.add_child(dim)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:layer.queue_free())
	var center=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);center.mouse_filter=Control.MOUSE_FILTER_IGNORE;layer.add_child(center)
	var v=panel_content(center,18);v.get_parent().get_parent().custom_minimum_size.x=460
	_detail_panel(v)
	v.add_child(button("Chiudi",layer.queue_free))
func _detail_panel(v: VBoxContainer) -> void:
	var d=game.catalog[detail_id]
	var head=HBoxContainer.new();v.add_child(head)
	var names=VBoxContainer.new();names.size_flags_horizontal=Control.SIZE_EXPAND_FILL;head.add_child(names)
	names.add_child(label(d.name,28,GOLD));names.add_child(label(d.title,15,MUTED))
	var team=int(d.team)
	names.add_child(label(["Ordine della Lama · Blu","Ordine dell’Ombra · Rossi"][team] if team>=0 else ("Mago · gioca con chiunque" if d.mage else "Scheletro · gioca con chiunque"),13,TEAM_COLOR[team] if team>=0 else INK))
	var mp=mini_path(detail_id)
	if mp!="":
		var m=TextureRect.new();m.texture=load(mp);m.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;m.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;m.custom_minimum_size=Vector2(140,140);head.add_child(m)
	var card=TextureRect.new();card.texture=load(card_path(detail_id));card.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;card.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.custom_minimum_size=Vector2(400,400.0*card.texture.get_height()/card.texture.get_width());v.add_child(card)
	v.add_child(label("LE SUE TESSERE · %d"%d.moves.size(),13,GOLD))
	var info=label("Passa sopra una tessera (o toccala) per leggerne i valori.",13,MUTED);info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;info.custom_minimum_size=Vector2(400,52)
	v.add_child(_honeycomb(d,info));v.add_child(info)
func _honeycomb(d: Dictionary,info: Label) -> Control:
	# tessere esagonali coi lati piatti in alto e in basso: colonne sfalsate di mezza altezza
	var w=92.0;var h=w*.8625;var cols=5;var n=d.moves.size();var gap=3.0
	var rows=ceili(float(n)/cols)
	var c=Control.new();c.custom_minimum_size=Vector2(w+(cols-1)*(w*.75+gap),rows*(h+gap)+h*.5)
	var k=0
	for id in d.moves:
		var m=d.moves[id];var col=k%cols;var row=k/cols
		var t=TextureRect.new();t.texture=load(m.texture);t.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;t.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size=Vector2(w,h);t.size=Vector2(w,h);t.position=Vector2(col*(w*.75+gap),row*(h+gap)+((h+gap)*.5 if col%2==1 else 0.0))
		t.tooltip_text=_move_tip(m);t.mouse_filter=Control.MOUSE_FILTER_STOP
		var tip=_move_tip(m).replace("\n"," · ")
		t.mouse_entered.connect(func():info.text=tip)
		t.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed:info.text=tip)
		c.add_child(t);k+=1
	return c
func _start_local() -> void:
	var seen=[];var teams=[]
	for r in roster:
		if r.character in seen:message="Ogni personaggio può essere scelto una sola volta.";_show_menu();return
		seen.append(r.character)
		if not r.team in teams:teams.append(r.team)
	if teams.size()<2:message="Assegna almeno un personaggio a ciascun Ordine.";_show_menu();return
	room_code="";net_host=false
	game.house_rules=house_rules
	if scenario=="bloodmaster":
		if roster.size()<3:message="Lo scenario Blood Master richiede almeno tre giocatori.";_show_menu();return
		game.start_campaign(roster,int(Time.get_unix_time_from_system()))
	else:game.new_game(roster,scenario,int(Time.get_unix_time_from_system()))
	_build_game();_refresh();_drive()
# --- Schermata di gioco ---------------------------------------------------------
# Mappa a tutto schermo; sopra una barra con tutti i comandi; diario a destra e scelte in
# sovraimpressione: il nido d'ape delle tessere in basso a sinistra (sparisce dopo la
# scelta) e i tasti dell'azione corrente in basso al centro, solo quando servono.
var stage: Control
var picker: Control
var action_panel: PanelContainer
var journal_panel: PanelContainer
var hint_label: Label
func _bar_button(text: String,cb: Callable,tip:="") -> Button:
	var b=button(text,cb);b.add_theme_font_size_override("font_size",14);b.tooltip_text=tip
	for st in ["normal","hover","pressed","focus"]:
		var sb=b.get_theme_stylebox(st).duplicate() if b.has_theme_stylebox(st) else box(Color("233234"),8)
		if sb is StyleBoxFlat:sb.content_margin_left=10;sb.content_margin_right=10;sb.content_margin_top=6;sb.content_margin_bottom=6
		b.add_theme_stylebox_override(st,sb)
	return b
func _bar_check(text: String,on: bool,cb: Callable,tip:="") -> Button:
	# pulsante attivo/non attivo (niente interruttore): acceso è dorato
	var c=_bar_button(text,func():pass,tip);c.toggle_mode=true;c.button_pressed=on;c.toggled.connect(cb)
	var lit=box(GOLD,8);lit.content_margin_left=10;lit.content_margin_right=10;lit.content_margin_top=6;lit.content_margin_bottom=6
	c.add_theme_stylebox_override("pressed",lit);c.add_theme_color_override("font_pressed_color",Color("151b19"))
	c.add_theme_color_override("font_hover_pressed_color",Color("151b19"));c.add_theme_stylebox_override("hover_pressed",lit)
	return c
func _overlay_panel(alpha:=.86) -> PanelContainer:
	var p=PanelContainer.new();var sb=box(Color(PANEL.r,PANEL.g,PANEL.b,alpha),12);sb.content_margin_left=14;sb.content_margin_right=14;sb.content_margin_top=10;sb.content_margin_bottom=10
	p.add_theme_stylebox_override("panel",sb);return p
func _build_game() -> void:
	showing_game=true;clear(page)
	var bar=_overlay_panel(1.0);page.add_child(bar)
	var row=HFlowContainer.new();row.add_theme_constant_override("h_separation",6);row.add_theme_constant_override("v_separation",6);bar.add_child(row)
	turn_label=label("",15,GOLD);row.add_child(turn_label)
	status=label("",13,MUTED);status.custom_minimum_size.x=160;status.size_flags_horizontal=Control.SIZE_EXPAND_FILL;status.clip_text=true;status.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;row.add_child(status)
	row.add_child(_bar_check("Miniature 3D",minis_3d,func(v):minis_3d=v;board.visible=not v;board3d.visible=v;_refresh()))
	row.add_child(_bar_check("Griglia",board_grid,func(v):board_grid=v;board.show_grid=v;board.queue_redraw();_refresh()))
	row.add_child(_bar_check("Estrazione automatica",auto_draw,func(v):auto_draw=v;_drive()))
	row.add_child(_bar_check("Sangue",blood_on,func(v):blood_on=v;board3d.blood=v;_save_settings()))
	row.add_child(_bar_check("Suoni",sound_on,func(v):sound_on=v;board3d.sound=v;_save_settings()))
	row.add_child(_bar_check("Basette trasparenti",clear_plates,func(v):clear_plates=v;board3d.set_clear_plates(v);_save_settings()))
	row.add_child(_bar_check("Nomi e barre",labels_on,func(v):labels_on=v;board3d.set_labels(v);_save_settings(),"Nomi, ferite e fatica sopra le miniature"))
	row.add_child(_bar_button("Salva",_save_game));row.add_child(_bar_button("Regolamento",_open_manual))
	row.add_child(_bar_button("Crediti",_credits));row.add_child(_bar_button("Menu",_confirm_menu))
	stage=Control.new();stage.size_flags_vertical=Control.SIZE_EXPAND_FILL;stage.clip_contents=true;page.add_child(stage)
	board=ArenaBoard.new();board.game=game;board.show_grid=board_grid;board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);board.cell_clicked.connect(_cell_clicked);stage.add_child(board)
	_last_hp={}
	board3d=ArenaBoard3D.new();board3d.game=game;board3d.blood=blood_on;board3d.sound=sound_on;board3d.labels_on=labels_on;board3d.clear_plates=clear_plates;board3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);board3d.cell_clicked.connect(_cell_clicked);board3d.visible=minis_3d;stage.add_child(board3d)
	board.visible=not minis_3d
	# sovraimpressioni: colonna sinistra (nido d'ape), centro (azioni), destra (diario).
	# Contenitori trasparenti al mouse, così la mappa resta trascinabile ovunque.
	var over=MarginContainer.new();over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);over.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for side in ["left","right","top","bottom"]:over.add_theme_constant_override("margin_"+side,12)
	stage.add_child(over)
	var stack=VBoxContainer.new();stack.mouse_filter=Control.MOUSE_FILTER_IGNORE;stack.add_theme_constant_override("separation",10);over.add_child(stack)
	portraits=HBoxContainer.new();portraits.mouse_filter=Control.MOUSE_FILTER_IGNORE;portraits.alignment=BoxContainer.ALIGNMENT_CENTER;portraits.add_theme_constant_override("separation",8);stack.add_child(portraits)   # faccette in alto, una sola fila
	stage.resized.connect(_refresh_portraits)
	var cols=HBoxContainer.new();cols.mouse_filter=Control.MOUSE_FILTER_IGNORE;cols.add_theme_constant_override("separation",12);cols.size_flags_vertical=Control.SIZE_EXPAND_FILL;stack.add_child(cols)
	var left=VBoxContainer.new();left.mouse_filter=Control.MOUSE_FILTER_IGNORE;left.alignment=BoxContainer.ALIGNMENT_END;cols.add_child(left)
	picker=_overlay_panel(.88);left.add_child(picker)
	var mid=VBoxContainer.new();mid.mouse_filter=Control.MOUSE_FILTER_IGNORE;mid.alignment=BoxContainer.ALIGNMENT_END;mid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;cols.add_child(mid)
	var midrow=HBoxContainer.new();midrow.mouse_filter=Control.MOUSE_FILTER_IGNORE;midrow.alignment=BoxContainer.ALIGNMENT_CENTER;mid.add_child(midrow)
	action_panel=_overlay_panel(.9);midrow.add_child(action_panel)
	sidebar=VBoxContainer.new();sidebar.add_theme_constant_override("separation",8);action_panel.add_child(sidebar)
	hint_label=label("Trascina: sposta · tasto destro: ruota · rotellina: zoom · clic su un personaggio: scheda",12,MUTED)
	hint_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;hint_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var right=VBoxContainer.new();right.mouse_filter=Control.MOUSE_FILTER_IGNORE;right.custom_minimum_size.x=300;cols.add_child(right)
	journal_panel=_overlay_panel(.72);right.add_child(journal_panel)
	var jv=VBoxContainer.new();journal_panel.add_child(jv)
	var jh=HBoxContainer.new();jv.add_child(jh);jh.add_child(label("DIARIO",13,GOLD));jh.add_child(spacer())
	log_box=RichTextLabel.new();log_box.bbcode_enabled=true;log_box.scroll_following=true;log_box.custom_minimum_size=Vector2(270,240);log_box.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;log_box.add_theme_font_size_override("normal_font_size",14);jv.add_child(log_box)
	jh.add_child(_bar_button("−",func():log_box.visible=not log_box.visible,"Riduci o apri il diario"))
	var fill=Control.new();fill.mouse_filter=Control.MOUSE_FILTER_IGNORE;fill.size_flags_vertical=Control.SIZE_EXPAND_FILL;right.add_child(fill)
	right.add_child(hint_label)
	_refresh_portraits()
var portraits: HBoxContainer
func _refresh_portraits() -> void:
	# faccette sempre visibili su una sola fila: ritratto, barre (o solo numeri se sono tanti),
	# punti magia, ultima mossa e formula coi dadi. La larghezza si adatta al numero di personaggi.
	if portraits==null:return
	clear(portraits);portraits.visible=not game.state.is_empty() and game.state.phase!="deploy"
	if not portraits.visible:return
	var notes=_fighter_notes()
	var shown=[]
	for i in game.state.fighters.size():
		var p=game.state.fighters[i]
		if p.cell=="" and p.alive:continue
		if not p.alive and int(p.get("owner",-1))>=0:continue   # golem evocati e caduti: spariscono
		shown.append(i)
	if shown.is_empty():return
	var avail=maxf(400.0,(stage.size.x if stage else 1280.0)-24.0)
	var w=clampf((avail-8.0*(shown.size()-1))/shown.size()-10.0,58.0,150.0)   # larghezza interna del riquadro
	var compact=w<104.0
	var font=11 if w>=90.0 else 10
	for i in shown:
		var p=game.state.fighters[i]
		var team_col=Color("69cec1") if int(p.team)==0 else Color("e68078")
		var card=PanelContainer.new();var sb=box(Color(PANEL.r,PANEL.g,PANEL.b,.88),8);sb.border_color=team_col;sb.set_border_width_all(2)
		sb.content_margin_left=4;sb.content_margin_right=4;sb.content_margin_top=4;sb.content_margin_bottom=4;card.add_theme_stylebox_override("panel",sb)
		card.mouse_filter=Control.MOUSE_FILTER_IGNORE;card.modulate=Color(1,1,1,1) if p.alive else Color(.55,.55,.55,.7);card.custom_minimum_size.x=w+8;portraits.add_child(card)
		var v=VBoxContainer.new();v.add_theme_constant_override("separation",2);v.mouse_filter=Control.MOUSE_FILTER_IGNORE;card.add_child(v)
		var path="res://assets/reborn/minis/%s.webp"%p.character
		if not ResourceLoader.exists(path):path=card_path(p.character) if game.catalog.has(p.character) else ""
		var img=TextureRect.new();img.custom_minimum_size=Vector2(w,minf(w*.62,64.0));img.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;img.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.mouse_filter=Control.MOUSE_FILTER_IGNORE;img.clip_contents=true
		if path!="":img.texture=load(path)
		v.add_child(img)
		var nm=label(p.name.split(" ")[0]+("" if p.alive else " †"),font+1,team_col);nm.custom_minimum_size.x=w;nm.clip_text=true;v.add_child(nm)
		var hp=maxi(0,int(p.hp));var fat=int(p.fatigue)+int(p.permanent)
		var mage=bool(game.definition(p).get("mage",false))
		if compact:   # tanti personaggi: solo numeri, ferite/fatica (e magia)
			var t=label("%d/%d · %d%s"%[hp,int(p.max_hp),fat," · %dm"%int(p.magic) if mage else ""],font,MUTED);t.tooltip_text="ferite / massimo · fatica"+(" · punti magia" if mage else "");t.mouse_filter=Control.MOUSE_FILTER_PASS;v.add_child(t)
		else:
			v.add_child(_meter(float(hp)/maxf(1,float(p.max_hp)),Color("5fd068"),"%d ferite"%hp,w))
			v.add_child(_meter(clampf(float(fat)/10.0,0,1),Color("b48cff"),"%d fatica"%fat,w))
			v.add_child(label("%d ferite · %d fatica"%[hp,fat],font,MUTED))
			if mage:v.add_child(label("%d punti magia"%int(p.magic),font,Color("8fb8ff")))
		var n=notes.get(i,{})
		var mv=label(str(n.get("move","")),font+1,GOLD);mv.custom_minimum_size.x=w;mv.clip_text=true;v.add_child(mv)
		if not n.get("lines",[]).is_empty():
			var rt=RichTextLabel.new();rt.bbcode_enabled=true;rt.fit_content=false;rt.scroll_active=false;rt.custom_minimum_size=Vector2(w,(font+4)*3)
			rt.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;rt.clip_contents=true   # al massimo tre righe: la fila resta bassa
			rt.add_theme_font_size_override("normal_font_size",font);rt.mouse_filter=Control.MOUSE_FILTER_IGNORE
			rt.text=_log_bbcode(n.lines.slice(maxi(0,n.lines.size()-1))).replace("width=18 height=18","width=%d height=%d"%[font+3,font+3]);v.add_child(rt)
func _fighter_notes() -> Dictionary:
	# dal diario: per ogni personaggio la mossa rivelata per ultima e i tiri di dado che ne sono seguiti
	var names=[]
	for i in game.state.fighters.size():names.append([str(game.state.fighters[i].name),i])
	names.sort_custom(func(a,b):return a[0].length()>b[0].length())   # prima i nomi lunghi ("Golem di Thorn")
	var out={};var last_attacker=-1
	for raw in game.state.log:
		var line=str(raw)
		if line.begins_with("Sbilanciamento:") and last_attacker>=0:
			out[last_attacker].lines.append(line.trim_suffix(".").replace("Sbilanciamento: ","sbil. "));continue
		var who=-1;var rest=""
		for nm in names:
			if line.begins_with(nm[0]+" ") or line.begins_with(nm[0]+","):who=nm[1];rest=line.substr(nm[0].length()).strip_edges();break
		if who<0:continue
		if not out.has(who):out[who]={"move":"","lines":[]}
		if rest.begins_with("rivela: "):out[who]={"move":rest.substr(8).trim_suffix("."),"lines":[]};continue
		if rest.begins_with("lancia "):out[who].move=rest.substr(7).trim_suffix(".");continue
		if rest.begins_with("attacca "):
			last_attacker=who
			out[who].lines.append("su "+rest.substr(8).trim_suffix(".").replace("; "," · "));continue
		if "dado" in rest:out[who].lines.append(rest.trim_prefix(",").trim_prefix(":").strip_edges().trim_suffix("."))
	return out
func _meter(f: float,col: Color,tip: String,w:=96.0) -> Control:
	var back=ColorRect.new();back.color=Color("131d20");back.custom_minimum_size=Vector2(w,6);back.tooltip_text=tip;back.mouse_filter=Control.MOUSE_FILTER_PASS
	var fill=ColorRect.new();fill.color=col if f>.5 or col!=Color("5fd068") else (Color("f0c040") if f>.25 else Color("d9534f"));fill.size=Vector2(w*clampf(f,0,1),6);fill.mouse_filter=Control.MOUSE_FILTER_IGNORE;back.add_child(fill)
	return back
var _dice_re: RegEx
func _log_bbcode(lines: Array) -> String:
	# "dado 5" nel diario diventa l'immagine del dado con quella faccia
	if _dice_re==null:_dice_re=RegEx.new();_dice_re.compile("dado ([1-6])")
	var out=[]
	for line in lines:
		var t=str(line).replace("[","[lb]")
		t=_dice_re.sub(t,"[img width=18 height=18]res://assets/ui/dice_$1.png[/img]",true)
		out.append(t)
	return "\n".join(out)
func _layout_overlays() -> void:
	# i pulsanti consecutivi stanno sulla stessa riga; il pannello sparisce se è vuoto
	var kids=sidebar.get_children();var row: HBoxContainer=null
	for c in kids:
		if c is Button and not c is CheckButton:
			if row==null:
				row=HBoxContainer.new();row.alignment=BoxContainer.ALIGNMENT_CENTER;row.add_theme_constant_override("separation",8)
				sidebar.add_child(row);sidebar.move_child(row,c.get_index())
			sidebar.remove_child(c);row.add_child(c)
		elif c is Label and c.autowrap_mode!=TextServer.AUTOWRAP_OFF:
			c.custom_minimum_size.x=520;row=null
		else:row=null
	action_panel.visible=sidebar.get_child_count()>0
	picker.visible=picker.get_child_count()>0
func _refresh() -> void:
	if not showing_game:return
	clear(sidebar);clear(picker)
	turn_label.text=("STANZA "+room_code+" · " if room_code!="" else "")+"TURNO %d" % game.state.turn
	_refresh_portraits()
	log_box.text=_log_bbcode(game.state.log.slice(maxi(0,game.state.log.size()-40)))
	board.highlights=[];board.preview_facing=-1;board.focus_fighter=-1;board.selected=selected_cell
	status.text=""
	match game.state.phase:
		"handicap":_handicap_panel()
		"auction":_auction_panel()
		"round_result","campaign_finished":_campaign_result_panel()
		"deploy":_deployment_panel()
		"planning":_planning_panel()
		"acting":_action_panel()
		"opportunity":_opportunity_panel()
		"reaction":_reaction_panel()
		"stumble":_stumble_panel()
		"draw":_draw_panel()
		"upkeep":_upkeep_panel()
		"finished":_finish_panel()
		"net_reveal":sidebar.add_child(label("Tutti hanno scelto. Apertura delle mosse…",19,GOLD))
	_layout_overlays()
	# sangue sulla mappa 2D: macchie proporzionate alle ferite appena subite
	for i in game.state.fighters.size():
		var q=game.state.fighters[i];var was=int(_last_hp.get(i,q.hp))
		if blood_on and int(q.hp)<was and q.cell!="":
			for k in mini(2+was-int(q.hp),14):board.blood.append([q.cell,Vector2(randf_range(-55,55),randf_range(-55,55)),randf_range(9,20)+(was-int(q.hp))*.8,randf()])
		_last_hp[i]=int(q.hp)
	board.queue_redraw()
	if board3d:board3d.copy_from(board)
func _human(i: int) -> bool:
	if i<0:return false
	var p=game.state.fighters[i]
	if p.get("controller_by",-1)>=0:p=game.state.fighters[p.controller_by]
	return p.controller=="human" and (room_code=="" or int(p.seat)==net_seat)
func _heading(i: int,text: String) -> void:
	var p=game.state.fighters[i]
	var h=HBoxContainer.new();h.alignment=BoxContainer.ALIGNMENT_CENTER;sidebar.add_child(h)
	h.add_child(label(text.to_upper()+" ·",13,GOLD));h.add_child(label(p.name,21,Color("79cfbf") if int(p.team)==0 else Color("ed9992")))
	board.focus_fighter=i
func _deployment_panel() -> void:
	var i=int(game.state.active);var p=game.state.fighters[i];_heading(i,"Schieramento")
	board.highlights=game.entry_cells(int(p.team));board.preview_facing=selected_facing
	_wrap("Scegli un esagono di partenza evidenziato: ognuno può ospitare un solo personaggio.")
	if _human(i):
		_facing_controls()
		var b=button("Schiera il personaggio",func():_submit({"type":"deploy","target":selected_cell,"facing":selected_facing}),true);b.disabled=not selected_cell in board.highlights;sidebar.add_child(b)
	else:_wrap("In attesa dello schieramento…")
func _planning_panel() -> void:
	var i=-1
	for j in game.needs_plan():
		if _human(j) and not str(j) in remote_ready:i=j;break
	if i==-1:
		sidebar.add_child(label("MOSSE SEGRETE · la tua scelta è al sicuro, aspettiamo gli altri personaggi.",14,GOLD))
		return
	focus_index=i;board.focus_fighter=i
	var p=game.state.fighters[i]
	var v=VBoxContainer.new();v.add_theme_constant_override("separation",6);picker.add_child(v)
	var h=HBoxContainer.new();v.add_child(h)
	h.add_child(label("SCEGLI IN SEGRETO ·",13,GOLD));h.add_child(label(p.name,21,Color("79cfbf") if int(p.team)==0 else Color("ed9992")))
	var info=label("Tocca una tessera per sceglierla. Spostamento e bersaglio li decidi quando verrà estratta.",13,MUTED)
	info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;info.custom_minimum_size=Vector2(380,40)
	v.add_child(_move_honeycomb(game.legal_moves(i),p,info,func(id):_submit({"type":"plan","fighter":i,"move":id})));v.add_child(info)
func _move_honeycomb(ids: Array,p: Dictionary,info: Label,on_pick: Callable) -> Control:
	# tessere esagonali coi lati piatti in alto e in basso, a colonne sfalsate
	var w=92.0;var h=w*.8625;var cols=5;var gap=3.0
	var rows=ceili(float(ids.size())/cols)
	var c=Control.new();c.custom_minimum_size=Vector2(w+(cols-1)*(w*.75+gap),rows*(h+gap)+h*.5)
	var k=0
	for id in ids:
		var m=game.move(p,id);var col=k%cols;var row=k/cols
		var t=TextureButton.new();t.texture_normal=load(m.texture);t.ignore_texture_size=true;t.stretch_mode=TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size=Vector2(w,h);t.size=Vector2(w,h);t.position=Vector2(col*(w*.75+gap),row*(h+gap)+((h+gap)*.5 if col%2==1 else 0.0))
		t.tooltip_text=_move_tip(m);t.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
		var tip=_move_tip(m).replace("\n"," · ")
		t.mouse_entered.connect(func():info.text=tip)
		t.pressed.connect(func():on_pick.call(id))
		c.add_child(t);k+=1
	return c
func _action_panel() -> void:
	var i=int(game.state.active);var p=game.state.fighters[i];var m=game.move(p)
	# una riga compatta: tessera estratta, chi la gioca, valori e cosa fare
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",12);sidebar.add_child(row)
	var t=TextureRect.new();t.texture=load(m.texture);t.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;t.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;t.custom_minimum_size=Vector2(86,74);row.add_child(t)
	var col=VBoxContainer.new();col.add_theme_constant_override("separation",2);row.add_child(col)
	var h=HBoxContainer.new();col.add_child(h)
	h.add_child(label(p.name,20,Color("79cfbf") if int(p.team)==0 else Color("ed9992")));h.add_child(label("· "+m.name,20,GOLD))
	col.add_child(label(_move_tip(m).split("\n",true,1)[1] if "\n" in _move_tip(m) else "",13,MUTED))
	board.highlights=game.targets(i);board.preview_facing=selected_facing;board.focus_fighter=i
	if not _human(i):col.add_child(label("Il personaggio sta decidendo la sua azione…",13,MUTED));return
	col.add_child(label("Tocca una casella evidenziata, scegli l’orientamento e conferma.",13,MUTED))
	if selected_cell!="":sidebar.add_child(label("Destinazione / bersaglio: "+selected_cell,15,GOLD))
	_facing_controls()
	if m.get("spell",false) and m.id in ["fireball","lightning","control","abyss"]:
		var sp=SpinBox.new();sp.min_value=0;sp.max_value=maxi(0,p.magic-int(m.cost));sp.value=selected_extra;sp.prefix="Magia extra: ";sp.value_changed.connect(func(v):selected_extra=int(v));sidebar.add_child(sp)
	if m.id=="concentrate":
		for j in game.state.fighters.size():
			if game.state.fighters[j].pieces:sidebar.add_child(button("Rigenera "+game.state.fighters[j].name,func():_submit({"type":"regenerate","fighter":j})))
	var command={"type":"act","target":selected_cell if selected_cell!="" else p.cell,"facing":selected_facing,"extra":selected_extra}
	var b=button("Esegui la mossa",func():_submit(command),true);b.disabled=not command.target in board.highlights;sidebar.add_child(b)
	if m.id=="guard":sidebar.add_child(button("Resta in guardia · attacca più tardi",func():_submit({"type":"act","wait":true,"facing":selected_facing})))
	sidebar.add_child(button("Non eseguire l’azione",func():_submit({"type":"act","pass":true,"facing":int(p.facing)})))
func _reaction_panel() -> void:
	var pending=game.state.pending;var i=int(pending.reactors[0]);_heading(i,"Puoi reagire")
	var attacker=game.state.fighters[pending.actor]
	_wrap(attacker.name+" annuncia "+game.move(attacker).name+". La reazione avviene prima della risoluzione.")
	if not _human(i):_wrap("In attesa della reazione…");return
	var v=int(game.move(attacker).get("value",0)) if pending.kind=="spell" else 0
	for id in game.reaction_options(i,v):
		var name="Non reagire" if id=="pass" else ("Disperdi magia · costo %d"%v if id=="counter" else game.move(game.state.fighters[i],id).name)
		sidebar.add_child(button(name,func():_submit({"type":"react","move":id}),id!="pass"))
	if v>0:_wrap("Puoi disperdere solo prima di aver agito. Se il dado supera il valore dell’incantesimo, lo annulli e consumi la mossa. Se fallisci, potrai ancora agire.")
func _stumble_panel() -> void:
	var i=int(game.state.pending.actor);_heading(i,"Equilibrio perso")
	board.highlights=game.state.pending.path
	_wrap("Scegli dove fermarti lungo il percorso dichiarato: il personaggio resta sbilanciato.")
	if _human(i):
		var b=button("Fermati qui",func():_submit({"type":"stumble","target":selected_cell}),true);b.disabled=not selected_cell in board.highlights;sidebar.add_child(b)
func _draw_panel() -> void:
	# niente pannello: con l'estrazione automatica non serve nulla, altrimenti un piccolo tasto
	if not auto_draw and (room_code=="" or net_host):
		var b=_bar_button("Estrai ▸",func():_submit({"type":"draw"}),"Estrai la prossima pedina dal contenitore");sidebar.add_child(b)
	for i in game.state.fighters.size():
		var p=game.state.fighters[i]
		if p.guarding and _human(i):
			sidebar.add_child(button(p.name+" · intervieni dalla guardia",func():
				_submit({"type":"guard_prepare","fighter":i})))
func _upkeep_panel() -> void:
	var i=int(game.state.active);_heading(i,"Effetti di fine turno")
	var e=game.state.effects[game.state.upkeep[0]]
	_wrap("Scegli la direzione del "+("gorgo magico" if e.kind=="vortex" else "fuoco vivente")+". Si muoverà di tanti esagoni quanto il tiro del dado.")
	board.selected=e.cell
	if _human(i):_facing_controls();sidebar.add_child(button("Muovi l’effetto",func():_submit({"type":"effect","facing":selected_facing}),true))
func _finish_panel() -> void:
	sidebar.add_child(label("LO SCONTRO È FINITO",13,GOLD))
	var winner=int(game.state.winner)
	sidebar.add_child(label("Lama Lucente" if winner==0 else ("Ombra Oscura" if winner==1 else "Pace nell’arena"),27,GOLD))
	_wrap("La battaglia si conclude. Puoi consultare le schede e la cronaca prima di preparare un nuovo scontro.")
	sidebar.add_child(button("Replay 3D dello scontro",func():
		minis_3d=true;board.visible=false;board3d.visible=true;board3d.replay()))
	sidebar.add_child(button("Nuovo scontro",_show_menu,true))
func _facing_controls() -> void:
	var row=HBoxContainer.new();sidebar.add_child(row)
	row.add_child(button("↶",func():selected_facing=posmod(selected_facing-1,6);_refresh()))
	row.add_child(label("Orientamento %d / 6"%(selected_facing+1),15))
	row.add_child(button("↷",func():selected_facing=posmod(selected_facing+1,6);_refresh()))
func _wrap(text: String) -> void:
	var l=label(text,15,MUTED);l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;l.custom_minimum_size.x=320;sidebar.add_child(l)
func _tile(path: String,width: int) -> void:
	var t=TextureRect.new();t.texture=load(path);t.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;t.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;t.custom_minimum_size=Vector2(width,width*.866);sidebar.add_child(t)
func _move_tip(m: Dictionary) -> String:
	var text=m.name+"\n"
	text+=("Attacco %s · "%str(m.attack) if m.attack!=null else "")+"Difesa %s"%str(m.defense)
	if m.fatigue>0:text+=" · Fatica +%d"%m.fatigue
	if m.rest:text+=" · Recupero a fine turno"
	if m.get("imbalance")!=null:text+="\nSbilanciamento +%d"%m.imbalance
	if m.get("spell",false):text+="\nMagia: valore %d · costo %d"%[m.value,m.cost]
	return text
func _cell_clicked(k: String) -> void:
	if k in board.highlights:selected_cell=k;_refresh()
	else:
		var i=game.at(k)
		if i!=-1:_inspect(i)
func _reset_selection() -> void:
	selected_move="";selected_cell="";selected_path=[];selected_extra=0;handicap_picks=[]
	selected_facing=0
	if game.state.active>=0:
		selected_facing=int(game.state.fighters[game.state.active].facing)
		if game.state.phase=="deploy":selected_facing=0 if game.state.fighters[game.state.active].team==0 else 3
func _submit(command: Dictionary) -> void:
	if room_code!="" and network!=null:
		await network.submit(command);return
	if _apply(command):
		_reset_selection();_refresh();_autosave();_drive()
	else:status.text="Questa azione non è valida: controlla bersaglio e orientamento."
func _apply(c: Dictionary) -> bool:
	match c.type:
		"handicap":return game.handicap_choices(int(game.state.active),c.picks)
		"bid":return game.auction_bid(int(game.state.active),int(c.amount))
		"next_round":return game.next_campaign_round()
		"deploy":return game.deploy(c.target,int(c.facing))
		"plan":return game.plan(int(c.fighter),c.move)
		"reveal":return game.reveal()
		"draw":game.draw_next();return true
		"act":return game.act(c)
		"opportunity":return game.opportunity(c.move)
		"regenerate":return game.regenerate(int(c.fighter))
		"react":return game.react(c.move)
		"stumble":return game.choose_stumble(c.target)
		"effect":return game.advance_effect(int(c.facing))
		"guard_prepare":
			var i=int(c.fighter)
			if game.state.phase!="draw" or not game.state.fighters[i].guarding:return false
			game.state.active=i;game.state.phase="acting";game.state.fighters[i].guarding=false;return true
	return false
func _drive() -> void:
	if busy or not showing_game or (room_code!="" and not net_host):return
	busy=true
	await get_tree().create_timer(speed).timeout
	while board3d!=null and is_instance_valid(board3d) and board3d.is_visible_in_tree() and board3d.busy():
		await get_tree().create_timer(.1).timeout   # le miniature finiscono la mossa prima della prossima estrazione
	busy=false
	if not showing_game:return
	if room_code!="":
		if network!=null:await network.host_tick()
		return
	var s=game.state;var acted=false
	match s.phase:
		"handicap":
			var i=int(s.active)
			if s.fighters[i].controller=="ai":acted=game.handicap_choices(i,s.campaign.pool.slice(0,3))
		"auction":
			var i=int(s.active)
			if s.fighters[i].controller=="ai":
				var c=s.campaign;var limit=mini(int(c.players[i].points),maxi(2,int(c.players[i].points)/3))
				acted=game.auction_bid(i,int(c.bid)+1 if c.bid<limit else 0)
		"deploy":
			var i=int(s.active)
			if s.fighters[i].controller=="ai":
				var entries=game.entry_cells(s.fighters[i].team);var cell=entries[i%entries.size()]
				acted=game.deploy(cell,0 if s.fighters[i].team==0 else 3)
		"planning":
			for i in game.needs_plan():
				if s.fighters[i].controller=="ai":game.plan(i,BloodAI.choose_move(game,i));acted=true
			if game.needs_plan().is_empty():acted=game.reveal()
		"acting":
			var i=int(s.active);var p=s.fighters[i]
			if p.controller=="ai" or p.get("owner",-1)>=0:acted=game.act(BloodAI.command(game,i))
		"opportunity":
			var i=int(s.pending.reactors[0])
			if s.fighters[i].controller=="ai":acted=game.opportunity(BloodAI.opportunity(game,i))
		"reaction":
			var i=int(s.pending.reactors[0])
			if s.fighters[i].controller=="ai":acted=game.react(BloodAI.reaction(game,i))
		"stumble":
			var i=int(s.pending.actor)
			if s.fighters[i].controller=="ai":acted=game.choose_stumble(s.pending.path.back())
		"upkeep":
			if s.fighters[s.active].controller=="ai":acted=game.advance_effect(int(s.fighters[s.active].facing))
		"draw":
			var guarding=s.fighters.any(func(p):return p.guarding and p.controller=="human")
			if auto_draw and not guarding:game.draw_next();acted=true
	if acted:
		_reset_selection();_refresh();_autosave();_drive()
func _autosave() -> void:
	if room_code!="":return
	var f=FileAccess.open("user://battle.json",FileAccess.WRITE)
	if f:f.store_string(JSON.stringify(game.snapshot()))
	if board3d:   # anche il replay, così copre tutto lo scontro dopo un caricamento
		var r=FileAccess.open("user://battle_replay.json",FileAccess.WRITE)
		if r:r.store_string(JSON.stringify(board3d.export_replay()))
func _save_game() -> void:
	_autosave();status.text="Partita salvata su questo dispositivo."
func _load_game() -> void:
	var s=JSON.parse_string(FileAccess.get_file_as_string("user://battle.json"))
	if not s is Dictionary or int(s.get("version",0))!=BloodRules.VERSION:message="Il salvataggio non è compatibile.";_show_menu();return
	game.restore(s);room_code="";_build_game()
	if FileAccess.file_exists("user://battle_replay.json"):
		var r=JSON.parse_string(FileAccess.get_file_as_string("user://battle_replay.json"))
		if r is Dictionary:board3d.import_replay(r)
	_reset_selection();_refresh();_drive()
func _confirm_menu() -> void:
	var d=ConfirmationDialog.new();d.title="Tornare al menu?";d.dialog_text="La partita locale è salvata automaticamente. Potrai riprenderla da questo dispositivo.";d.confirmed.connect(_show_menu);d.canceled.connect(d.queue_free);d.confirmed.connect(d.queue_free);add_child(d);d.popup_centered()
func _inspect(i: int) -> void:
	var p=game.state.fighters[i];var d=game.definition(p)
	var win=Window.new();win.title=d.name+" · "+d.title;win.size=Vector2i(1050,650);win.transient=true;win.exclusive=true;add_child(win);win.close_requested.connect(win.queue_free)
	var v=VBoxContainer.new();v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);win.add_child(v)
	var card=TextureRect.new();card.texture=load(card_path(d.id));card.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;card.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;card.size_flags_vertical=Control.SIZE_EXPAND_FILL;v.add_child(card)
	v.add_child(label("%s · Stazza %d · Sprint %d · %d vita · %d fatica · %d magia"%[d.name,d.size,d.sprint,p.hp,p.fatigue+p.permanent,p.magic],18,GOLD))
	if not p.lost.is_empty():v.add_child(label("Mosse perdute: "+", ".join(p.lost),16))
	v.add_child(button("Chiudi",win.queue_free));win.popup_centered()
func _open_manual() -> void:
	if is_instance_valid(manual_window):manual_window.grab_focus();return
	manual_window=Window.new();manual_window.title="Blood Master · regolamento originale";manual_window.size=Vector2i(850,900);manual_window.transient=true;add_child(manual_window);manual_window.close_requested.connect(manual_window.queue_free);_manual_content();manual_window.popup_centered()
func _manual_content() -> void:
	clear(manual_window)
	var v=VBoxContainer.new();v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);manual_window.add_child(v)
	var scroll=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;v.add_child(scroll)
	var image=TextureRect.new();image.texture=load("res://assets/rules/page-%02d.webp"%(manual_page+1));image.custom_minimum_size=Vector2(810,1145);image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT;scroll.add_child(image)
	var row=HBoxContainer.new();v.add_child(row);row.add_child(button("‹ Indietro",func():manual_page=posmod(manual_page-1,12);_manual_content()));row.add_child(label("Pagina %d / 12"%(manual_page+1)));row.add_child(button("Avanti ›",func():manual_page=posmod(manual_page+1,12);_manual_content()));row.add_child(button("Chiudi",manual_window.queue_free))
	var l=label("Chiarimento dell’autore: Disperdi magia consuma la mossa solo se riesce.",14,GOLD);v.add_child(l)
func _credits() -> void:
	var w=AcceptDialog.new();w.title="Blood Master Deluxe";w.dialog_text="Ideazione e sviluppo: Stefano Ancillai e Marco Ramadori\nDisegni: Luigi Filipponi\nEdizione originale: Devil’s Den\n\nVersione digitale realizzata dalle scansioni dell’autore.\nMotore Godot 4.7 · Partite online con Firebase\n\nLe illustrazioni e il regolamento appartengono ai rispettivi autori.";add_child(w);w.confirmed.connect(w.queue_free);w.popup_centered()
func _online_menu(parent: VBoxContainer) -> void:
	parent.add_child(label("Multiplayer · stanza privata",18,GOLD))
	var name=LineEdit.new();name.placeholder_text="Il tuo nome";name.text="Giocatore";parent.add_child(name)
	var code=LineEdit.new();code.placeholder_text="Codice stanza (4 lettere)";code.max_length=4;parent.add_child(code)
	var row=HBoxContainer.new();parent.add_child(row)
	row.add_child(button("Crea stanza",func():_connect_online(true,name.text,""),true))
	row.add_child(button("Entra",func():_connect_online(false,name.text,code.text.to_upper()),true))
func _connect_online(want_host: bool,player_name: String,requested_code: String) -> void:
	if player_name.strip_edges()=="":status.text="Scrivi il tuo nome.";return
	status.text="Collegamento a Firebase…"
	if is_instance_valid(network):network.active=false;network.queue_free()
	network=BloodOnline.new();network.game=game;network.apply_command=_apply;add_child(network)
	network.failed.connect(func(text):if is_instance_valid(status):status.text=text)
	network.updated.connect(_network_update)
	network.lobby_updated.connect(_show_lobby)
	var ok=await network.create(player_name,roster,scenario) if want_host else await network.join(player_name,requested_code)
	if not ok:return
	room_code=network.code;net_seat=network.seat;net_host=network.host
	_show_lobby(await network.net.room(room_code))
func _show_lobby(room: Dictionary) -> void:
	if room.get("status","")!="lobby":return
	showing_game=false;clear(page);_header("PARTITA ONLINE · STANZA "+room_code)
	var area=panel_content(page,30)
	area.add_child(label("Invita gli altri nell’arena",32,GOLD))
	area.add_child(label("Codice stanza: "+room_code,40))
	area.add_child(label("Condividi il codice con gli altri giocatori.
Devono aprire Blood Master, scegliere Online e premere Entra.",18,MUTED))
	var cfg=room.get("game",{});var occupied=BloodNet._as_dict(room.get("seats",{}))
	for i in cfg.get("roster",[]).size():
		var p=cfg.roster[i];var who="IA" if p.controller=="ai" else (occupied[str(i)].name if occupied.has(str(i)) else "In attesa…")
		area.add_child(label("%s · %s"%[game.catalog[p.character].name,who],19))
	if net_host:area.add_child(button("Inizia la partita",func():await network.start(),true))
	area.add_child(button("Copia codice",func():DisplayServer.clipboard_set(room_code)))
	area.add_child(button("Torna al menu",func():network.active=false;room_code="";_show_menu()))
	status=label("I posti Persona devono essere occupati prima dell’avvio.",15,MUTED);area.add_child(status)
func _network_update() -> void:
	remote_ready=network.ready_seats
	if game.state.is_empty():return
	if not showing_game:_build_game()
	_reset_selection();_refresh()


func _handicap_panel() -> void:
	var c=game.state.campaign;var i=int(game.state.active)
	sidebar.add_child(label("BLOOD MASTER · ROUND %d / 3"%c.round,13,GOLD))
	sidebar.add_child(label(c.players[i].name,25))
	_wrap("Assegna in segreto 3, 2 e 1 punti handicap a tre personaggi diversi. I punti saranno sottratti al premio di sopravvivenza; per i maghi sono anche la magia iniziale.")
	for id in c.pool:
		var amount=3-handicap_picks.find(id) if id in handicap_picks else 0
		var b=button(game.catalog[id].name+(" · %d"%amount if amount else ""),func():
			if id in handicap_picks:handicap_picks.erase(id)
			elif handicap_picks.size()<3:handicap_picks.append(id)
			_refresh())
		b.disabled=not _human(i);sidebar.add_child(b)
	if _human(i):
		var picks=handicap_picks.duplicate();var b=button("Conferma gli handicap",func():_submit({"type":"handicap","picks":picks}),true);b.disabled=picks.size()!=3;sidebar.add_child(b)
func _auction_panel() -> void:
	var c=game.state.campaign;var i=int(game.state.active);var id=c.pool[c.card];var d=game.catalog[id]
	sidebar.add_child(label("ASTA · ROUND %d / 3"%c.round,13,GOLD));sidebar.add_child(label(d.name,28,GOLD));_tile(card_path(id),220)
	_wrap("Handicap: %d\nOfferta attuale: %d\nTocca a %s · %d punti disponibili"%[c.totals[id],c.bid,c.players[i].name,c.players[i].points])
	if _human(i):
		var spin=SpinBox.new();spin.min_value=int(c.bid)+1;spin.max_value=maxi(int(c.bid)+1,int(c.players[i].points));spin.value=int(c.bid)+1;spin.prefix="Offri ";sidebar.add_child(spin)
		var bid=button("Fai un’offerta",func():_submit({"type":"bid","amount":int(spin.value)}),true);bid.disabled=int(c.players[i].points)<=int(c.bid);sidebar.add_child(bid)
		sidebar.add_child(button("Passa",func():_submit({"type":"bid","amount":0})))
	_wrap("Ogni giocatore acquista un solo personaggio. Senza offerte, il personaggio viene assegnato casualmente a chi ne è ancora privo, al costo di 2 punti.")
func _campaign_result_panel() -> void:
	var c=game.state.campaign;var finished=game.state.phase=="campaign_finished"
	sidebar.add_child(label("IL NUOVO BLOOD MASTER" if finished else "FINE ROUND %d"%c.round,17,GOLD))
	var sorted_players=c.players.duplicate(true);sorted_players.sort_custom(func(a,b):return a.points>b.points)
	for p in sorted_players:sidebar.add_child(label("%s · %d punti"%[p.name,p.points],20))
	if finished:sidebar.add_child(button("Torna al menu",_show_menu,true))
	elif room_code=="" or net_host:sidebar.add_child(button("Classifica finale" if c.round==3 else "Prossimo round",func():_submit({"type":"next_round"}),true))

func _opportunity_panel() -> void:
	var i=int(game.state.pending.reactors[0]);var p=game.state.fighters[i]
	_heading(i,"Prima dell’azione avversaria")
	_wrap(game.state.fighters[game.state.pending.resume].name+" ha rivelato la propria mossa. Puoi intervenire ora oppure attendere.")
	if not _human(i):_wrap("In attesa della decisione…");return
	if p.guarding:sidebar.add_child(button("Attacca dalla guardia",func():_submit({"type":"opportunity","move":"guard"}),true))
	if p.current=="concentrate":
		for id in game.legal_moves(i):
			var m=game.move(p,id)
			if m.get("spell",false):sidebar.add_child(button(m.name,func():_submit({"type":"opportunity","move":id}),true))
	sidebar.add_child(button("Attendi",func():_submit({"type":"opportunity","move":"pass"})))
