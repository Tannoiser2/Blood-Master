extends Control

const BG=Color("100b08")
const PANEL=Color("211812")
const GOLD=Color("e6bf6c")
const INK=Color("f0e4c8")
const MUTED=Color("b8a27c")
const DARK_INK=Color("2a1a0e")   # testo scuro su oro e pergamena
const UI="res://assets/ui/fantasy/"
# tema fantasy in stile Reborn: Cinzel Decorative per i titoli, Cinzel per intestazioni e pulsanti, Alegreya per il testo
var font_body: Font;var font_head: Font;var font_title: Font
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
var replay_btn: Button;var new_btn: Button   # a fine scontro, nella barra in alto (il riquadro coprirebbe la mappa)
var move_grid: GridContainer
var roster: Array=[]
var mode="solo"
var scenario="frontale"
var selected_move=""
var selected_cell=""
var selected_facing=0
var last_error=""
var selected_path: Array=[]
var focus_index=-1
var selected_extra=0
var selected_step=""          # passo di un esagono prima o dopo l'azione (pedine con lati verdi degli eroi della forgia)
var selected_step_after=false
var handicap_picks: Array=[]
var auction_amount=1
var speed=.65
var busy=false
var step_pause=false   # "Pausa a ogni mossa": si va avanti cliccando la faccetta di chi ha agito
var waiting_click=false
var last_actor=-1
const READ_TIME=1.8      # secondi per leggere pedina e risultato prima della prossima estrazione
const SHOW_TIME=1.1      # secondi in cui si vede chi agisce e con quale pedina, prima che agisca
var auto_draw=true
var board_grid=false
var blood_on=false
var sound_on=true
var labels_on=true
var house={"fall":true,"push":true,"reach":true,"arrows":true,"zoc":true,"scenery":true,"golem":true,"restore":true}   # regole modificate, una per una
const HOUSE_INFO=[["fall","Cadute col dado","La pedina «a terra» fa cadere solo con 1-2 sul dado; con 6 ci si rimette in guardia."],
	["push","Arretramento sicuro","Chi viene sbilanciato arretra sempre di almeno un esagono: scontri più mobili."],
	["reach","Armi lunghe","Lance, alabarde, tridente e il bastone di Zenyo: affondo e carica colpiscono anche il secondo esagono davanti."],
	["arrows","Frecce contate","Ogni arciere ha 5 + un dado di frecce; finite quelle si torna alla spada."],
	["zoc","Zone di controllo","Entrando accanto a un nemico ci si ferma; chi si sgancia da un nemico che non ha ancora agito subisce un suo colpo."],
	["scenery","Scenografia","Colonne, massi, alberi, pozze e macerie a caso nell'arena: invalicabili; colonne, massi e alberi coprono dai tiri."],
	["golem","Golem più resistente","Il Golem non viene sbilanciato e non va in polvere: crolla solo a 40 ferite o se il mago che l'ha evocato è fuori combattimento; non serve rigiocare Evocazione per tenerlo in campo."],
	["restore","Zone di ristoro","Pozioni ed esagoni di mana luccicanti sparsi nell'arena: chi ci entra recupera un dado di ferite e tutta la fatica. La pozione sparisce, il mana si riaccende altrove a fine turno."]]
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
	_load_heroes()
	_build_theme()
	if OS.get_environment("BM_SMOKE")=="1":
		roster=[{"character":"gascor","team":0,"controller":"human","seat":0},{"character":"anteos","team":1,"controller":"ai","seat":1}]
		_start_local();return
	_show_splash()
func _load_heroes() -> void:
	# eroi della forgia salvati su questo dispositivo: entrano nel catalogo come gli altri
	var saved=BloodForge.load_saved()
	for id in saved:
		BloodRules.extra_defs[id]=saved[id];game.add_definition(saved[id])
func _forged(id: String) -> bool:
	# eroi della forgia e varianti dei personaggi del gioco
	return game.catalog.has(id) and BloodForge.is_custom(game.catalog[id])
func face_path(id: String) -> String:
	var look=str(game.catalog[id].get("look",id)) if game.catalog.has(id) else id
	return "res://assets/ui/faces/%s.webp"%look
func _show_forge(hero_id:="") -> void:
	showing_game=false;clear(page)
	var f=preload("res://scripts/forge_ui.gd").new();page.add_child(f)
	f.on_close=func():_show_menu()
	f.setup(self,hero_id)
# carattere di riserva per quello che scrivono i giocatori (nomi); l'interfaccia non usa simboli: frecce e croci sono disegnate
var font_symbols: Font=load("res://assets/fonts/NotoSansSymbols2-sub.ttf")
func _with_symbols(path: String) -> FontFile:
	var base: FontFile=load(path)
	if not font_symbols in base.fallbacks:base.fallbacks=base.fallbacks+[font_symbols]
	return base
func _font(path: String,weight: int) -> Font:
	var f=FontVariation.new();f.base_font=_with_symbols(path);f.variation_opentype={TextServerManager.get_primary_interface().name_to_tag("wght"):weight};return f
# --- Stile: cornici e pulsanti disegnati (niente immagini: nitidi a ogni risoluzione, uguali ovunque) ---
const EDGE=Color("5c4a33")
func flat(bg: Color,border: Color,radius:=7,bw:=1,ml:=14,mt:=8) -> StyleBoxFlat:
	var b=StyleBoxFlat.new();b.bg_color=bg;b.border_color=border;b.set_border_width_all(bw);b.set_corner_radius_all(radius)
	b.content_margin_left=ml;b.content_margin_right=ml;b.content_margin_top=mt;b.content_margin_bottom=mt;b.anti_aliasing=true;return b
func tex_box(file: String,_margin: int,cl:=14,ct:=9) -> StyleBoxFlat:
	# i nomi delle vecchie cornici a immagine restano come chiavi dello stile disegnato
	match file:
		"btn.png":return flat(Color("2b211a"),EDGE,7,1,cl,ct)
		"btn_hover.png":return flat(Color("3b2d21"),GOLD.darkened(.15),7,1,cl,ct)
		"btn_pressed.png":return flat(Color("1c1510"),GOLD.darkened(.3),7,1,cl,ct)
		"btn_gold.png":return flat(Color("d9b25f"),Color("f3d995"),7,1,cl,ct)
		"btn_gold_hover.png":return flat(Color("ecc875"),Color("fff0c0"),7,1,cl,ct)
		"btn_on.png":return flat(Color("c9a24e"),Color("f0d590"),7,1,cl,ct)
		"panel_light.png":return flat(Color("2e241c"),GOLD.darkened(.3),8,1,cl,ct)
	var p=flat(Color(.105,.082,.066,.94),EDGE,10,1,cl,ct);p.shadow_color=Color(0,0,0,.35);p.shadow_size=6;return p
func _build_theme() -> void:
	font_body=_font("res://assets/fonts/Alegreya.ttf",500);font_head=_font("res://assets/fonts/Cinzel.ttf",700);font_title=_with_symbols("res://assets/fonts/CinzelDecorative-Bold.ttf")
	var t=Theme.new();t.default_font_size=17;t.default_font=font_body
	t.set_color("font_color","Label",INK);t.set_color("font_color","Button",INK)
	t.set_color("font_color","RichTextLabel",INK)
	for typ in ["Button","OptionButton"]:
		t.set_font("font",typ,font_head)
		t.set_stylebox("normal",typ,tex_box("btn.png",0,16,9));t.set_stylebox("hover",typ,tex_box("btn_hover.png",0,16,9))
		t.set_stylebox("pressed",typ,tex_box("btn_pressed.png",0,16,9));t.set_stylebox("disabled",typ,flat(Color("1d1713"),Color("3a3027"),7,1,16,9))
		t.set_stylebox("focus",typ,StyleBoxEmpty.new())
		t.set_color("font_hover_color",typ,GOLD.lightened(.3));t.set_color("font_pressed_color",typ,GOLD)
		t.set_color("font_disabled_color",typ,Color("7d6a52"))
	for st in ["normal","hover","pressed","hover_pressed","focus","disabled"]:t.set_stylebox(st,"CheckBox",StyleBoxEmpty.new())
	t.set_font("font","CheckBox",font_body);t.set_color("font_color","CheckBox",INK);t.set_color("font_hover_color","CheckBox",GOLD.lightened(.3));t.set_color("font_pressed_color","CheckBox",INK)
	t.set_stylebox("normal","LineEdit",flat(Color("120c08"),EDGE,5,1,8,6));t.set_stylebox("focus","LineEdit",flat(Color("120c08"),GOLD.darkened(.2),5,1,8,6))
	t.set_stylebox("panel","PanelContainer",tex_box("panel.png",0,12,12))
	t.set_stylebox("panel","TooltipPanel",tex_box("panel_light.png",0,12,10))
	t.set_stylebox("panel","PopupMenu",tex_box("panel_light.png",0,8,8))
	t.set_color("font_color","TooltipLabel",INK);t.set_font("font","TooltipLabel",font_body)
	t.set_constant("separation","VBoxContainer",10);t.set_constant("separation","HBoxContainer",10)
	t.set_color("font_color","OptionButton",INK)
	t.set_stylebox("background","ProgressBar",box(Color("140d09"),4))
	t.set_stylebox("fill","ProgressBar",box(Color("c9a24e"),4))
	theme=t
	var bg=ColorRect.new();bg.color=BG;bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);bg.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(bg)
	var bgt=TextureRect.new();bgt.texture=load("res://assets/arena/arena.webp");bgt.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;bgt.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bgt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);bgt.mouse_filter=Control.MOUSE_FILTER_IGNORE;bgt.modulate=Color(.2,.17,.15);add_child(bgt)   # l'arena in penombra dietro ogni schermata
	var margin=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,16)
	add_child(margin);page=VBoxContainer.new();margin.add_child(page)
# --- Icone disegnate: frecce, croce, più e meno. Nessun carattere speciale: i simboli che un carattere tipografico
# non contiene diventano quadratini, soprattutto sul web dove non c'è un carattere di sistema di riserva.
func _draw_icon(c: Control,kind: String,col: Color) -> void:
	var o=c.size*.5;var r=minf(c.size.x,c.size.y)*.22;var w=maxf(2.0,r*.3)
	match kind:
		"left":c.draw_colored_polygon(PackedVector2Array([o+Vector2(-r,0),o+Vector2(r*.8,-r),o+Vector2(r*.8,r)]),col)
		"right":c.draw_colored_polygon(PackedVector2Array([o+Vector2(r,0),o+Vector2(-r*.8,-r),o+Vector2(-r*.8,r)]),col)
		"cross":c.draw_line(o+Vector2(-r,-r),o+Vector2(r,r),col,w,true);c.draw_line(o+Vector2(-r,r),o+Vector2(r,-r),col,w,true)
		"plus":c.draw_line(o+Vector2(-r,0),o+Vector2(r,0),col,w,true);c.draw_line(o+Vector2(0,-r),o+Vector2(0,r),col,w,true)
		"minus":c.draw_line(o+Vector2(-r,0),o+Vector2(r,0),col,w,true)
		"check":c.draw_polyline(PackedVector2Array([o+Vector2(-r,0),o+Vector2(-r*.25,r*.75),o+Vector2(r,-r*.8)]),col,w,true)
func icon_button(kind: String,cb: Callable,tip:="",px:=30.0) -> Button:
	var b=_bar_button("",cb,tip);b.custom_minimum_size=Vector2(px,px)
	b.draw.connect(func():_draw_icon(b,kind,GOLD.lightened(.3) if b.is_hovered() else INK))
	return b
func wrap_label(text: String,font_size: int,color: Color,min_w: float) -> Label:
	# testo che va a capo: sempre con una larghezza minima, altrimenti in un contenitore stretto si schiaccia in colonna (una lettera per riga)
	var l=label(text,font_size,color);l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;l.custom_minimum_size.x=min_w;l.size_flags_horizontal=Control.SIZE_EXPAND_FILL;return l
## riga con interruttore disegnato, titolo e spiegazione sempre visibile (anche col tocco: niente testo che compare solo passando sopra)
func toggle_card(title: String,text: String,on: bool,cb: Callable,min_w:=220.0) -> PanelContainer:
	var p=PanelContainer.new();p.add_theme_stylebox_override("panel",flat(Color(.24,.18,.09,.95) if on else Color(.16,.12,.09,.9),GOLD.darkened(.1) if on else EDGE,8,1,12,9))
	p.size_flags_horizontal=Control.SIZE_EXPAND_FILL;p.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND;p.custom_minimum_size.x=min_w
	var h=HBoxContainer.new();h.add_theme_constant_override("separation",12);h.mouse_filter=Control.MOUSE_FILTER_IGNORE;p.add_child(h)
	var sw=Control.new();sw.custom_minimum_size=Vector2(46,26);sw.size_flags_vertical=Control.SIZE_SHRINK_CENTER;sw.mouse_filter=Control.MOUSE_FILTER_IGNORE;h.add_child(sw)
	sw.draw.connect(func():
		sw.draw_style_box(flat(GOLD if on else Color("3a3027"),GOLD.lightened(.2) if on else EDGE,11,1,0,0),Rect2(Vector2(0,2),Vector2(46,22)))
		sw.draw_circle(Vector2(35 if on else 11,13),8,DARK_INK if on else MUTED))
	var v=VBoxContainer.new();v.add_theme_constant_override("separation",2);v.size_flags_horizontal=Control.SIZE_EXPAND_FILL;v.mouse_filter=Control.MOUSE_FILTER_IGNORE;h.add_child(v)
	var tl=label(title,15,GOLD if on else INK);tl.add_theme_font_override("font",font_head);tl.mouse_filter=Control.MOUSE_FILTER_IGNORE;tl.clip_text=true;tl.custom_minimum_size.x=min_w-90;tl.size_flags_horizontal=Control.SIZE_EXPAND_FILL;v.add_child(tl)
	if text!="":
		var d=wrap_label(text,13,MUTED,min_w-90);d.mouse_filter=Control.MOUSE_FILTER_IGNORE;v.add_child(d)
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index==MOUSE_BUTTON_LEFT:cb.call(not on))
	return p
func _rule() -> ColorRect:
	var r=ColorRect.new();r.color=Color(EDGE,.8);r.custom_minimum_size.y=1;return r
## pedina: il disegno originale, oppure disegnata con i suoi valori (eroi della forgia, varianti, pedine senza disegno)
func token_widget(m: Dictionary,w: float) -> Control:
	var path=Art.token(str(m.get("texture","")))
	if m.get("drawn",false) or not ResourceLoader.exists(path):return TokenFace.new(m,w,font_head,font_body)
	var t=TextureRect.new();t.texture=load(path);t.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;t.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size=Vector2(w,w*.8625);t.size=t.custom_minimum_size;return t
func box(color: Color,radius: int=8) -> StyleBoxFlat:
	var b=StyleBoxFlat.new();b.bg_color=color;b.set_corner_radius_all(radius);return b
func label(text: String,font_size: int=17,color: Color=INK) -> Label:
	var l=Label.new();l.text=text;l.add_theme_font_size_override("font_size",font_size);l.add_theme_color_override("font_color",color)
	if font_head and (color==GOLD or font_size>=20):l.add_theme_font_override("font",font_head)   # intestazioni e titoli in Cinzel
	return l
func button(text: String,callback: Callable,primary: bool=false) -> Button:
	var b=Button.new();b.text=text;b.pressed.connect(func():if board3d!=null and is_instance_valid(board3d):board3d.ui_sfx("click",-14.0));b.pressed.connect(callback);b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	if primary:
		b.add_theme_stylebox_override("normal",tex_box("btn_gold.png",10,22,13));b.add_theme_stylebox_override("hover",tex_box("btn_gold_hover.png",10,22,13))
		b.add_theme_stylebox_override("pressed",tex_box("btn_on.png",10,22,13))
		for c in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:b.add_theme_color_override(c,DARK_INK)
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
var art="classica":         # grafica delle schede e delle pedine: "classica" o "reborn"
	set(v):art=v;Art.reborn=(v=="reborn")
var detail_id=""            # personaggio mostrato nel pannello di sinistra
func _load_settings() -> void:
	if not FileAccess.file_exists("user://settings.json"):return
	var d=JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
	if not d is Dictionary:return
	art=str(d.get("art","classica"));blood_on=bool(d.get("blood",false));sound_on=bool(d.get("sound",true));labels_on=bool(d.get("labels",true))
	step_pause=bool(d.get("pause",false));clear_plates=bool(d.get("clear_plates",false))
	minis_3d=bool(d.get("minis_3d",false));auto_draw=bool(d.get("auto_draw",true));board_grid=bool(d.get("grid",false))
	var hs=d.get("house_rules",null)
	if hs is Dictionary:
		for k in house:house[k]=bool(hs.get(k,house[k]))
	elif d.has("house"):   # vecchie impostazioni: un solo interruttore per tutte le regole modificate
		for k in house:house[k]=bool(d.house) and (k!="scenery" or bool(d.get("scenery",true)))
func _save_settings() -> void:
	var f=FileAccess.open("user://settings.json",FileAccess.WRITE)
	if f:f.store_string(JSON.stringify({"art":art,"blood":blood_on,"sound":sound_on,"labels":labels_on,"house_rules":house,"clear_plates":clear_plates,"pause":step_pause,"minis_3d":minis_3d,"auto_draw":auto_draw,"grid":board_grid}))
func card_path(id: String) -> String:
	var r="res://assets/reborn/cards/%s.webp"%str(game.catalog[id].get("look",id))
	if art=="reborn" and ResourceLoader.exists(r):return r
	return game.catalog[id].card
func mini_path(id: String) -> String:
	var r="res://assets/reborn/minis/%s.webp"%str(game.catalog[id].get("look",id))
	return r if art=="reborn" and ResourceLoader.exists(r) else ""
func _free_agent(id: String) -> bool:
	return int(game.catalog[id].team)<0                       # maghi e scheletri
func _selectable() -> Array:
	return game.catalog.keys().filter(func(k):return not game.catalog[k].kind in ["golem","skeleton"])   # il Golem si evoca in partita; niente scheletri
func _locked(id: String) -> bool:
	# negli scontri a squadre ogni combattente sta nel suo Ordine; nello scontro libero no
	return scenario!="libero" and not _free_agent(id)
func _card_widget(id: String,width: float,on_click: Callable,halves:=false) -> TextureRect:
	var t=TextureRect.new();t.texture=load(card_path(id));t.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;t.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex: Texture2D=t.texture;t.custom_minimum_size=Vector2(width,width*tex.get_height()/tex.get_width())
	t.mouse_filter=Control.MOUSE_FILTER_STOP;t.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	t.tooltip_text=game.catalog[id].name+" · "+game.catalog[id].title
	if _forged(id):   # la carta è quella del personaggio a cui somiglia: sopra il nome dell'eroe
		t.modulate=Color(.85,.8,.75)
		var tag=PanelContainer.new();tag.add_theme_stylebox_override("panel",box(Color(0,0,0,.72),4));tag.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var tl=label(str(game.catalog[id].name).to_upper(),maxi(11,int(width*.08)),GOLD);tl.mouse_filter=Control.MOUSE_FILTER_IGNORE;tag.add_child(tl)
		tag.custom_minimum_size=Vector2(width*.5,t.custom_minimum_size.y*.26)   # copre il nome stampato sulla carta
		t.add_child(tag);tag.position=Vector2(0,0)
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
# --- Menu iniziale unico -----------------------------------------------------------
# Una sola schermata: a sinistra il titolo, le sezioni (Scontro, Regole della casa, Opzioni), la forgia, il
# regolamento e il tasto per entrare nell'arena; a destra la sezione scelta. Niente più copertina separata.
var menu_section="scontro"
const MODES=[["solo","Contro l'IA","Tu guidi i tuoi personaggi, il computer tutti gli altri."],["local","Stesso schermo","Più giocatori sullo stesso dispositivo, a turno."],["online","Online","Stanza privata con codice: ognuno gioca dal suo dispositivo."]]
const SCENARIOS=[["frontale","Scontro frontale","Lama contro Ombra, ognuno nel suo Ordine. Si comincia in pace, poi è guerra."],["libero","Scontro libero","Squadre a scelta: ogni personaggio può stare con chiunque e si attacca da subito."],["bloodmaster","Blood Master","Asta dei personaggi e tre round: da almeno tre giocatori."]]
func _show_splash() -> void:_show_menu()
func _nav(title: String,sub: String,selected: bool,cb: Callable,width: float) -> PanelContainer:
	var p=PanelContainer.new();var sb=flat(Color(.26,.19,.1,.95) if selected else Color(.15,.115,.09,.85),GOLD if selected else EDGE,7,1,12,7)
	if selected:sb.border_width_left=5
	p.add_theme_stylebox_override("panel",sb);p.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND;p.custom_minimum_size.x=width
	var v=VBoxContainer.new();v.add_theme_constant_override("separation",0);v.mouse_filter=Control.MOUSE_FILTER_IGNORE;p.add_child(v)
	var t=label(title,15,GOLD if selected else INK);t.add_theme_font_override("font",font_head);t.clip_text=true;t.custom_minimum_size.x=width-30;t.mouse_filter=Control.MOUSE_FILTER_IGNORE;v.add_child(t)
	if sub!="":
		var s=label(sub,11,MUTED);s.clip_text=true;s.custom_minimum_size.x=width-30;s.mouse_filter=Control.MOUSE_FILTER_IGNORE;v.add_child(s)
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index==MOUSE_BUTTON_LEFT:cb.call())
	p.mouse_entered.connect(func():if not selected:sb.bg_color=Color(.22,.17,.12,.95))
	p.mouse_exited.connect(func():if not selected:sb.bg_color=Color(.15,.115,.09,.85))
	return p
func _show_menu() -> void:
	showing_game=false;clear(page);_close_overlays();menu_options=[]
	if not has_meta("settings_loaded"):_load_settings();set_meta("settings_loaded",true)
	roster=roster.filter(func(r):return _selectable().has(r.character))   # niente scheletri nelle squadre salvate
	for k in roster.size():roster[k].seat=k
	if roster.is_empty() and not has_meta("roster_default"):
		set_meta("roster_default",true)
		roster=[{"character":"gascor","team":0,"controller":"human","seat":0},{"character":"anteos","team":1,"controller":"ai","seat":1}]
	var vp=get_viewport().get_visible_rect().size
	var narrow=vp.x<1180.0
	var rail_w=214.0 if narrow else 256.0
	var root=HBoxContainer.new();root.size_flags_vertical=Control.SIZE_EXPAND_FILL;root.size_flags_horizontal=Control.SIZE_EXPAND_FILL;root.add_theme_constant_override("separation",12);page.add_child(root)
	# --- colonna di sinistra
	var rail=panel_content(root,14);rail.get_parent().get_parent().custom_minimum_size.x=rail_w;rail.add_theme_constant_override("separation",7)
	var inner=rail_w-28.0
	var t=label("BLOOD\nMASTER",30 if narrow else 38,GOLD);t.add_theme_font_override("font",font_title);t.add_theme_constant_override("line_spacing",-10 if narrow else -14);rail.add_child(t)
	var sub=label("Gladiatori e maghi nell'arena",12,MUTED);sub.clip_text=true;sub.custom_minimum_size.x=inner;rail.add_child(sub)
	rail.add_child(_rule())
	var on_rules=0
	for k in house:
		if bool(house[k]):on_rules+=1
	var lama=roster.filter(func(r):return int(r.team)==0).size()
	for s in [["scontro","Scontro","Lama %d · Ombra %d"%[lama,roster.size()-lama]],["regole","Regole della casa","%d su %d attive"%[on_rules,house.size()]],["opzioni","Opzioni","Grafica, suoni e ritmo"]]:
		rail.add_child(_nav(s[1],s[2],menu_section==s[0],func():menu_section=s[0];message="";_show_menu(),inner))
	rail.add_child(_rule())
	rail.add_child(_nav("La forgia degli eroi","Eroi nuovi e varianti",false,func():_show_forge(),inner))
	rail.add_child(_nav("Regolamento","Le dodici pagine originali",false,_open_manual,inner))
	rail.add_child(_nav("Crediti","",false,_credits,inner))
	var gap=Control.new();gap.size_flags_vertical=Control.SIZE_EXPAND_FILL;rail.add_child(gap)
	status=wrap_label(message,13,Color("ffb07a"),inner);rail.add_child(status)
	if FileAccess.file_exists("user://battle.json"):
		var rb=button("Riprendi la partita",_load_game);rb.add_theme_font_size_override("font_size",14);rb.tooltip_text="La partita locale salvata su questo dispositivo";rail.add_child(rb)
	if mode=="online":
		var online=VBoxContainer.new();rail.add_child(online);_online_menu(online)
	else:
		var go=button("Entra nell'arena",_start_local,true);go.add_theme_font_size_override("font_size",17 if narrow else 19);go.custom_minimum_size.y=52;rail.add_child(go)
	# --- sezione scelta: scorre in verticale se lo schermo è basso
	var body=panel_content(root,14);body.get_parent().get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var sc=ScrollContainer.new();sc.size_flags_vertical=Control.SIZE_EXPAND_FILL;sc.size_flags_horizontal=Control.SIZE_EXPAND_FILL;sc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;body.add_child(sc)
	var content=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;content.add_theme_constant_override("separation",10);sc.add_child(content)
	var cw=vp.x-32.0-rail_w-12.0-28.0-14.0;var ch=vp.y-32.0-28.0
	match menu_section:
		"regole":_menu_house(content,cw)
		"opzioni":_menu_options(content,cw)
		_:_menu_battle(content,cw,ch)
func _set_scenario(key: String) -> void:
	scenario=key
	for r in roster:
		if _locked(r.character):r.team=int(game.catalog[r.character].team)    # chi era nella squadra sbagliata torna nel suo Ordine
	_show_menu()
func _menu_battle(v: VBoxContainer,w: float,h: float) -> void:
	# in alto modalità e scenario; al centro le carte dei personaggi; in basso le due squadre
	var wide=w>=860.0
	var top: BoxContainer=HBoxContainer.new() if wide else VBoxContainer.new()
	top.add_theme_constant_override("separation",18 if wide else 8);v.add_child(top)
	for grp in [["MODALITÀ",MODES,mode,func(k):mode=k;_show_menu()],["SCENARIO",SCENARIOS,scenario,_set_scenario]]:
		var gv=VBoxContainer.new();gv.add_theme_constant_override("separation",4);gv.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(gv)
		gv.add_child(label(grp[0],12,GOLD))
		var row=HBoxContainer.new();row.add_theme_constant_override("separation",6);gv.add_child(row)
		var desc=""
		for o in grp[1]:
			var b=_bar_check(o[1],grp[2]==o[0],func(_x):grp[3].call(o[0]),o[2]);b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;b.custom_minimum_size.y=36;b.clip_text=true;row.add_child(b)
			if grp[2]==o[0]:desc=o[2]
		gv.add_child(wrap_label(desc,13,MUTED,220))
	v.add_child(_rule())
	var hint="Freccia a sinistra: Ordine della Lama · freccia a destra: Ordine dell'Ombra · i maghi con chiunque"+(", i combattenti nel loro Ordine" if scenario=="frontale" else ", in questo scenario anche i combattenti")+" · tocca una carta per la scheda e le pedine"
	v.add_child(wrap_label(hint,12,MUTED,300))
	# carte: ogni Ordine su due colonne (4 + 3), i maghi insieme nell'ultima riga
	var ratio=2.05
	var forged=_selectable().filter(func(x):return _forged(x))
	var free_h=h-(150.0 if wide else 250.0)-150.0-(70.0 if not forged.is_empty() else 34.0)
	var cw=clampf(minf((w-40.0-3*8.0-16.0)/4.0,(free_h-3*8.0)/4.0*ratio),118.0,420.0)
	var two=HBoxContainer.new();two.alignment=BoxContainer.ALIGNMENT_CENTER;two.add_theme_constant_override("separation",40);v.add_child(two)
	var order=_pool_order()
	for half in 2:
		var g=GridContainer.new();g.columns=2;g.add_theme_constant_override("h_separation",8);g.add_theme_constant_override("v_separation",8);two.add_child(g)
		var ids: Array=order.slice(half*7,half*7+7)
		var fighters=ids.filter(func(x):return not _free_agent(x));var mages=ids.filter(func(x):return _free_agent(x))
		for id in fighters:g.add_child(_pool_card(id,cw))
		if fighters.size()%2==1:   # casella vuota: i maghi stanno tutti insieme nell'ultima riga
			var gap=Control.new();gap.custom_minimum_size=Vector2(cw,1);g.add_child(gap)
		for id in mages:g.add_child(_pool_card(id,cw))
	# eroi della forgia e varianti: una fila sotto
	var forge_row=HFlowContainer.new();forge_row.alignment=FlowContainer.ALIGNMENT_CENTER;forge_row.add_theme_constant_override("h_separation",8);forge_row.add_theme_constant_override("v_separation",6);v.add_child(forge_row)
	if mode!="online":
		for id in forged:forge_row.add_child(_pool_card(id,cw*.72))
	elif not forged.is_empty():forge_row.add_child(label("Eroi forgiati e varianti: non ancora nelle partite online",12,MUTED))
	var fb=_bar_button("Forgia un eroe o una variante",func():_show_forge(),"Crea un personaggio da tratti, armi e armatura, o ritocca un personaggio del gioco");fb.size_flags_vertical=Control.SIZE_SHRINK_CENTER;forge_row.add_child(fb)
	v.add_child(_rule())
	for team in 2:_team_strip(v,team,w)
func _team_strip(parent: Node,team: int,w: float) -> void:
	# la squadra in una riga: volto, nome, chi lo muove (Persona o IA) e la croce per toglierlo
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",8);parent.add_child(row)
	var tag=label(["LAMA","OMBRA"][team],13,TEAM_COLOR[team]);tag.custom_minimum_size.x=62;tag.size_flags_vertical=Control.SIZE_SHRINK_CENTER;row.add_child(tag)
	var flow=HFlowContainer.new();flow.size_flags_horizontal=Control.SIZE_EXPAND_FILL;flow.add_theme_constant_override("h_separation",6);flow.add_theme_constant_override("v_separation",6);row.add_child(flow)
	var any=false
	for i in roster.size():
		if int(roster[i].team)!=team:continue
		any=true
		var id: String=roster[i].character
		var chip=PanelContainer.new();chip.add_theme_stylebox_override("panel",flat(Color(TEAM_COLOR[team],.14),Color(TEAM_COLOR[team],.8),7,1,6,4));flow.add_child(chip)
		var h=HBoxContainer.new();h.add_theme_constant_override("separation",6);chip.add_child(h)
		var f=TextureRect.new();var fp=face_path(id)
		if ResourceLoader.exists(fp):f.texture=load(fp)
		f.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;f.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;f.custom_minimum_size=Vector2(32,32);h.add_child(f)
		var nm=label(str(game.catalog[id].name),14,INK);nm.clip_text=true;nm.custom_minimum_size.x=84;nm.size_flags_vertical=Control.SIZE_SHRINK_CENTER;h.add_child(nm)
		h.add_child(_bar_button("Persona" if roster[i].controller=="human" else "IA",func():roster[i].controller="ai" if roster[i].controller=="human" else "human";_show_menu(),"Chi muove questo personaggio: tocca per cambiare"))
		h.add_child(icon_button("cross",func():_remove_from_team(i),"Togli dalla squadra"))
	if not any:
		var e=label("nessuno: scegli una carta con la freccia",13,Color(TEAM_COLOR[team],.7));e.clip_text=true;e.custom_minimum_size=Vector2(minf(300.0,w-90.0),40);e.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;flow.add_child(e)
func _menu_house(v: VBoxContainer,w: float) -> void:
	var head=HFlowContainer.new();head.add_theme_constant_override("h_separation",10);head.add_theme_constant_override("v_separation",6);v.add_child(head)
	var title=label("REGOLE DELLA CASA",22,GOLD);title.custom_minimum_size.x=280;head.add_child(title)
	head.add_child(_bar_button("Attiva tutte",func():
		for k in house:house[k]=true
		_save_settings();_show_menu(),"Tutte le regole modificate"))
	head.add_child(_bar_button("Solo il regolamento originale",func():
		for k in house:house[k]=false
		_save_settings();_show_menu(),"Spegne tutte le regole modificate"))
	v.add_child(wrap_label("Ogni regola si accende e si spegne da sola e vale dal prossimo scontro. Con tutte spente si gioca con il regolamento originale di Blood Master.",14,MUTED,300))
	var g=GridContainer.new();g.columns=2 if w>=780.0 else 1;g.add_theme_constant_override("h_separation",10);g.add_theme_constant_override("v_separation",10);g.size_flags_horizontal=Control.SIZE_EXPAND_FILL;v.add_child(g)
	for info in HOUSE_INFO:
		g.add_child(toggle_card(info[1],info[2],bool(house[info[0]]),func(val):house[info[0]]=val;_save_settings();_show_menu(),260))
	var box_p=PanelContainer.new();box_p.add_theme_stylebox_override("panel",flat(Color(.13,.1,.08,.9),EDGE,8,1,14,10));v.add_child(box_p)
	var bv=VBoxContainer.new();bv.add_theme_constant_override("separation",4);box_p.add_child(bv)
	bv.add_child(label("CHIARIMENTI DELL'AUTORE · sempre validi",13,GOLD))
	for line in ["Punti magia iniziali: 5 più un dado per ogni mago.","Shannon: i valori aggiuntivi stampati sulle sue pedine sono errori di stampa e non contano.","Disperdi magia si usa solo prima di avere agito: se riesce consuma la mossa, se fallisce no; il costo in punti magia si paga in tutti e due i casi."]:
		bv.add_child(wrap_label(line,13,INK,280))
func _menu_options(v: VBoxContainer,w: float) -> void:
	v.add_child(label("OPZIONI",22,GOLD))
	v.add_child(label("GRAFICA DELLE SCHEDE E DELLE PEDINE",12,GOLD))
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",6);v.add_child(row)
	for o in [["classica","Classica","Le scansioni del gioco originale."],["reborn","Reborn","Schede e pedine ridisegnate."]]:
		var b=_bar_check(o[1],art==o[0],func(_x):art=o[0];_save_settings();_show_menu(),o[2]);b.custom_minimum_size=Vector2(150,36);row.add_child(b)
	v.add_child(wrap_label("Classica: le scansioni del gioco originale. Reborn: schede e pedine ridisegnate, con gli stessi valori.",13,MUTED,280))
	var groups=[["IN PARTITA",[
		["Miniature 3D","Lo scontro con le miniature animate invece delle pedine sulla mappa. Si cambia anche durante la partita.",minis_3d,func(x):minis_3d=x],
		["Nomi e barre","Nome, ferite e fatica sopra ogni miniatura.",labels_on,func(x):labels_on=x],
		["Griglia","Il contorno degli esagoni sulla mappa.",board_grid,func(x):board_grid=x],
		["Basette trasparenti","Sotto le miniature restano solo i lati colorati della pedina giocata.",clear_plates,func(x):clear_plates=x],
		["Sangue","Schizzi e macchie proporzionati alle ferite.",blood_on,func(x):blood_on=x],
		["Suoni","Colpi, passi, voci e pubblico.",sound_on,func(x):sound_on=x]]],
		["RITMO",[
		["Estrazione automatica","Le pedine escono dal sacchetto da sole, una dopo l'altra.",auto_draw,func(x):auto_draw=x],
		["Pausa a ogni mossa","Dopo ogni mossa il gioco si ferma: si riparte toccando il volto di chi ha agito.",step_pause,func(x):step_pause=x]]]]
	for grp in groups:
		v.add_child(label(grp[0],12,GOLD))
		var g=GridContainer.new();g.columns=2 if w>=780.0 else 1;g.add_theme_constant_override("h_separation",10);g.add_theme_constant_override("v_separation",8);g.size_flags_horizontal=Control.SIZE_EXPAND_FILL;v.add_child(g)
		for o in grp[1]:
			g.add_child(toggle_card(o[0],o[1],bool(o[2]),func(val):o[3].call(val);_save_settings();_show_menu(),260))
func _pool_order() -> Array:
	# prima fila: Ordine della Lama e due maghi; seconda: Ordine dell'Ombra e gli altri due maghi
	var lama=[];var ombra=[];var mages=[]
	for id in _selectable():
		if _forged(id):continue   # gli eroi della forgia hanno una fila tutta loro
		var t=int(game.catalog[id].team)
		if t==0:lama.append(id)
		elif t==1:ombra.append(id)
		else:mages.append(id)
	var half=ceili(mages.size()/2.0)
	return lama+mages.slice(0,half)+ombra+mages.slice(half)
func _pool_card(id: String,width: float) -> Control:
	# carta piccola con due frecce larghe ai lati: ◀ Lama, ▶ Ombra; già scelta = bordo e etichetta della squadra
	var picked=-1
	for i in roster.size():
		if roster[i].character==id:picked=i
	var box_c=PanelContainer.new()
	var sb=box(Color(0,0,0,0),6);sb.set_border_width_all(3);sb.border_color=TEAM_COLOR[int(roster[picked].team)] if picked>=0 else Color(0,0,0,0)
	box_c.add_theme_stylebox_override("panel",sb)
	var card=_card_widget(id,width,func(_x):_show_detail(id))
	if picked>=0:card.modulate=Color(1,1,1,.5)
	box_c.add_child(card)
	var own=int(game.catalog[id].team);var locked=_locked(id)
	var ch=card.custom_minimum_size;var aw=clampf(width*.13,24.0,46.0);var ah=clampf(ch.y*.5,26.0,60.0)
	for team in 2:
		if locked and team!=own:continue                      # combattente legato al suo Ordine
		if picked>=0 and int(roster[picked].team)==team:continue   # è già lì
		var ar=Button.new();ar.draw.connect(func():_draw_icon(ar,"left" if team==0 else "right",DARK_INK))   # freccia disegnata
		ar.tooltip_text=("Nell'Ordine della Lama" if team==0 else "Nell'Ordine dell'Ombra")+(" (sposta)" if picked>=0 else "")
		var st=box(TEAM_COLOR[team].darkened(.15),8);st.set_border_width_all(2);st.border_color=Color(1,1,1,.55)
		var sth=box(TEAM_COLOR[team].lightened(.15),8);sth.set_border_width_all(2);sth.border_color=Color.WHITE
		ar.add_theme_stylebox_override("normal",st);ar.add_theme_stylebox_override("hover",sth);ar.add_theme_stylebox_override("pressed",sth)
		ar.add_theme_color_override("font_color",DARK_INK);ar.add_theme_color_override("font_hover_color",DARK_INK)
		ar.custom_minimum_size=Vector2(aw,ah);ar.size=Vector2(aw,ah);ar.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
		ar.position=Vector2(0.0 if team==0 else ch.x-aw,(ch.y-ah)*.5)
		ar.pressed.connect(func():
			if picked>=0:roster[picked].team=team;message="";_show_menu()
			else:_add_to_team(id,team))
		card.add_child(ar)
	if picked>=0:
		var tag=label(("LAMA" if int(roster[picked].team)==0 else "OMBRA"),11,DARK_INK)
		var tp=PanelContainer.new();tp.add_theme_stylebox_override("panel",box(TEAM_COLOR[int(roster[picked].team)],4));tp.add_child(tag);card.add_child(tp);tp.position=Vector2(4,4)
		var x=icon_button("cross",func():_remove_from_team(picked),"Togli dalla squadra",26.0);card.add_child(x);x.position=Vector2(ch.x-32,3)
	return box_c
func _show_detail(id: String) -> void:
	# finestra sopra il menu con scheda e tessere; si chiude cliccando fuori o su Chiudi
	detail_id=id
	var layer=Control.new();layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layer.set_meta("overlay",true);add_child(layer)
	var dim=ColorRect.new();dim.color=Color(0,0,0,.6);dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layer.add_child(dim)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:layer.queue_free())
	var center=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);center.mouse_filter=Control.MOUSE_FILTER_IGNORE;layer.add_child(center)
	var v=panel_content(center,18);v.get_parent().get_parent().custom_minimum_size.x=460
	_detail_panel(v)
	v.add_child(button("Chiudi",layer.queue_free))
func _close_overlays() -> void:
	# chiude la finestra della scheda (livello sopra il menu)
	for c in get_children():
		if c is Control and c.get_meta("overlay",false):c.queue_free()
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
	var did=detail_id
	if not d.kind in ["golem","skeleton"]:
		v.add_child(label("Valore %d punti · 100 è la media dei guerrieri del gioco"%roundi(BloodForge.points(d)),13,MUTED))
		v.add_child(button("Modifica nella forgia" if _forged(did) else "Apri nella forgia: valori di ogni pedina e varianti",func():_close_overlays();_show_forge(did)))
func _honeycomb(d: Dictionary,info: Label) -> Control:
	# tessere esagonali coi lati piatti in alto e in basso: colonne sfalsate di mezza altezza
	var w=92.0;var h=w*.8625;var cols=5;var n=d.moves.size();var gap=3.0
	var rows=ceili(float(n)/cols)
	var c=Control.new();c.custom_minimum_size=Vector2(w+(cols-1)*(w*.75+gap),rows*(h+gap)+h*.5)
	var k=0
	for id in d.moves:
		var m=d.moves[id];var col=k%cols;var row=k/cols
		var t=token_widget(m,w)
		t.position=Vector2(col*(w*.75+gap),row*(h+gap)+((h+gap)*.5 if col%2==1 else 0.0))
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
	game.house=house.duplicate()
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
var journal_open=false
var news_panel: PanelContainer;var news_now: RichTextLabel;var news_prev: RichTextLabel
var _news_seen=-1
var hint_label: Label
func _bar_button(text: String,cb: Callable,tip:="") -> Button:
	var b=button(text,cb);b.add_theme_font_size_override("font_size",13);b.tooltip_text=tip
	for st in ["normal","hover","pressed","focus"]:
		b.add_theme_stylebox_override(st,tex_box({"normal":"btn.png","hover":"btn_hover.png","pressed":"btn_pressed.png","focus":"btn_hover.png"}[st],8,11,6))
	return b
func _bar_check(text: String,on: bool,cb: Callable,tip:="") -> Button:
	# pulsante attivo/non attivo (niente interruttore): acceso è dorato
	var c=_bar_button(text,func():pass,tip);c.toggle_mode=true;c.button_pressed=on;c.toggled.connect(cb)
	var lit=tex_box("btn_on.png",8,11,6)
	c.add_theme_stylebox_override("pressed",lit);c.add_theme_color_override("font_pressed_color",DARK_INK)
	c.add_theme_color_override("font_hover_pressed_color",DARK_INK);c.add_theme_stylebox_override("hover_pressed",lit)
	return c
func _overlay_panel(alpha:=.86) -> PanelContainer:
	var p=PanelContainer.new();var sb=box(Color(PANEL.r,PANEL.g,PANEL.b,alpha),6);sb.content_margin_left=14;sb.content_margin_right=14;sb.content_margin_top=10;sb.content_margin_bottom=10
	sb.set_border_width_all(2);sb.border_color=Color(GOLD.darkened(.35),alpha)   # cornice d'oro brunito
	p.add_theme_stylebox_override("panel",sb);return p
func _build_game() -> void:
	showing_game=true;clear(page)
	var bar=_overlay_panel(1.0);page.add_child(bar)
	var row=HFlowContainer.new();row.add_theme_constant_override("h_separation",6);row.add_theme_constant_override("v_separation",6);bar.add_child(row)
	# barra in alto: turno e messaggi a sinistra, pochi tasti a destra; il resto sta nel riquadro Opzioni
	turn_label=label("",15,GOLD);row.add_child(turn_label)
	status=label("",13,MUTED);status.custom_minimum_size.x=160;status.size_flags_horizontal=Control.SIZE_EXPAND_FILL;status.clip_text=true;status.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;row.add_child(status)
	replay_btn=_bar_button("Replay 3D",func():
		minis_3d=true;board.visible=false;board3d.visible=true;board3d.replay(),"Rivedi tutto lo scontro con le miniature 3D")
	replay_btn.add_theme_stylebox_override("normal",tex_box("btn_on.png",8,11,6));replay_btn.add_theme_color_override("font_color",DARK_INK)
	new_btn=_bar_button("Nuovo scontro",_show_menu,"Torna al menu per preparare un altro scontro")
	new_btn.add_theme_stylebox_override("normal",tex_box("btn_on.png",8,11,6));new_btn.add_theme_color_override("font_color",DARK_INK)
	row.add_child(replay_btn);row.add_child(new_btn);replay_btn.visible=false;new_btn.visible=false
	row.add_child(_bar_check("Miniature 3D",minis_3d,func(v):minis_3d=v;board.visible=not v;board3d.visible=v;_save_settings();_refresh(),"Miniature animate al posto delle pedine sulla mappa"))
	row.add_child(_bar_check("Diario",journal_open,func(v):journal_open=v;journal_panel.visible=v,"Apri o chiudi il diario completo dello scontro"))
	row.add_child(_bar_check("Opzioni",false,func(v):
		if is_instance_valid(options_panel):options_panel.visible=v,"Griglia, ritmo, sangue, suoni, nomi e basette"))
	row.add_child(_bar_button("Salva",_save_game));row.add_child(_bar_button("Regolamento",_open_manual))
	row.add_child(_bar_button("Menu",_confirm_menu))
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
	stage.resized.connect(_refresh_portraits)
	var cols=HBoxContainer.new();cols.mouse_filter=Control.MOUSE_FILTER_IGNORE;cols.add_theme_constant_override("separation",12);cols.size_flags_vertical=Control.SIZE_EXPAND_FILL;stack.add_child(cols)
	# faccette in colonna sui bordi: blu a sinistra, rossi a destra, così non coprono l'arena
	team_cols=[]
	for side in 2:
		var tc=VBoxContainer.new();tc.mouse_filter=Control.MOUSE_FILTER_IGNORE;tc.add_theme_constant_override("separation",6);tc.custom_minimum_size.x=CARD_W
		team_cols.append(tc)
	# le colonne stanno fisse sui bordi dell'arena, fuori dal flusso: il centro non può spingerle fuori schermo
	for side in 2:
		var dock=MarginContainer.new();dock.mouse_filter=Control.MOUSE_FILTER_IGNORE
		dock.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE if side==0 else Control.PRESET_RIGHT_WIDE)
		dock.offset_left=12.0 if side==0 else -CARD_W-12.0;dock.offset_right=CARD_W+12.0 if side==0 else -12.0
		dock.offset_top=12.0;dock.offset_bottom=-12.0;stage.add_child(dock);dock.add_child(team_cols[side])
		if side==1:dock.grow_horizontal=Control.GROW_DIRECTION_BEGIN   # se serve più spazio cresce verso l'arena, non fuori schermo
	var lgap=Control.new();lgap.custom_minimum_size.x=CARD_W;lgap.mouse_filter=Control.MOUSE_FILTER_IGNORE;cols.add_child(lgap)
	var left=VBoxContainer.new();left.mouse_filter=Control.MOUSE_FILTER_IGNORE;left.alignment=BoxContainer.ALIGNMENT_END;cols.add_child(left)
	picker=_overlay_panel(.88);left.add_child(picker)
	var mid=VBoxContainer.new();mid.mouse_filter=Control.MOUSE_FILTER_IGNORE;mid.alignment=BoxContainer.ALIGNMENT_END;mid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;cols.add_child(mid)
	var midrow=HBoxContainer.new();midrow.mouse_filter=Control.MOUSE_FILTER_IGNORE;midrow.alignment=BoxContainer.ALIGNMENT_CENTER;mid.add_child(midrow)
	action_panel=_overlay_panel(.9);midrow.add_child(action_panel);panel_home=midrow
	sidebar=VBoxContainer.new();sidebar.add_theme_constant_override("separation",8);action_panel.add_child(sidebar)
	hint_label=label("Trascina: sposta · tasto destro: ruota · rotellina: zoom · clic su un personaggio: scheda",12,MUTED)
	hint_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;hint_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var right=VBoxContainer.new();right.mouse_filter=Control.MOUSE_FILTER_IGNORE;right.custom_minimum_size.x=240;cols.add_child(right)
	var rgap=Control.new();rgap.custom_minimum_size.x=CARD_W;rgap.mouse_filter=Control.MOUSE_FILTER_IGNORE;cols.add_child(rgap)
	journal_panel=_overlay_panel(.86);right.add_child(journal_panel);journal_panel.visible=journal_open
	var jv=VBoxContainer.new();journal_panel.add_child(jv)
	var jh=HBoxContainer.new();jv.add_child(jh);jh.add_child(label("DIARIO",13,GOLD));jh.add_child(spacer())
	log_box=RichTextLabel.new();log_box.bbcode_enabled=true;log_box.scroll_following=true;log_box.custom_minimum_size=Vector2(210,240);log_box.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;log_box.add_theme_font_size_override("normal_font_size",14);jv.add_child(log_box)
	jh.add_child(icon_button("minus",func():log_box.visible=not log_box.visible,"Riduci o apri il diario",26.0))
	var fill=Control.new();fill.mouse_filter=Control.MOUSE_FILTER_IGNORE;fill.size_flags_vertical=Control.SIZE_EXPAND_FILL;right.add_child(fill)
	right.add_child(hint_label)
	# CRONACA: in alto al centro, quello che è appena successo (formule e dadi); l'azione prima resta sotto, attenuata
	news_panel=_overlay_panel(.88);news_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;stage.add_child(news_panel)
	news_panel.set_anchors_preset(Control.PRESET_CENTER_TOP);news_panel.custom_minimum_size.x=560;news_panel.visible=false
	var nv=VBoxContainer.new();nv.add_theme_constant_override("separation",4);nv.mouse_filter=Control.MOUSE_FILTER_IGNORE;news_panel.add_child(nv)
	for k in 2:
		var rt=RichTextLabel.new();rt.bbcode_enabled=true;rt.fit_content=true;rt.scroll_active=false;rt.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		rt.custom_minimum_size.x=530;rt.mouse_filter=Control.MOUSE_FILTER_IGNORE
		rt.add_theme_font_size_override("normal_font_size",16 if k==0 else 13);rt.add_theme_font_size_override("bold_font_size",16 if k==0 else 13)
		if k==1:rt.modulate=Color(1,1,1,.62)
		nv.add_child(rt)
		if k==0:news_now=rt
		else:news_prev=rt
	_news_seen=-1
	# riquadro delle opzioni: sotto la barra, a destra; si apre e si chiude dal tasto Opzioni
	options_panel=_overlay_panel(.97);options_panel.visible=false;stage.add_child(options_panel)
	options_panel.anchor_left=1.0;options_panel.anchor_right=1.0;options_panel.offset_left=-352.0;options_panel.offset_right=-10.0;options_panel.offset_top=8.0
	options_panel.grow_horizontal=Control.GROW_DIRECTION_BEGIN
	_fill_game_options()
	_refresh_portraits()
var options_panel: PanelContainer
func _fill_game_options() -> void:
	clear(options_panel)
	var v=VBoxContainer.new();v.add_theme_constant_override("separation",6);options_panel.add_child(v)
	v.add_child(label("OPZIONI",13,GOLD))
	for o in [["Griglia","","grid",board_grid],["Estrazione automatica","Le pedine escono da sole","auto",auto_draw],["Pausa a ogni mossa","Si riparte toccando il volto acceso","pause",step_pause],
		["Nomi e barre","Sopra le miniature","labels",labels_on],["Basette trasparenti","","plates",clear_plates],["Sangue","","blood",blood_on],["Suoni","","sound",sound_on]]:
		v.add_child(toggle_card(o[0],o[1],bool(o[3]),func(val):_set_game_option(o[2],val),300))
	v.add_child(_bar_button("Crediti",_credits))
func _set_game_option(key: String,x: bool) -> void:
	match key:
		"grid":board_grid=x;board.show_grid=x;board.queue_redraw();_refresh()
		"auto":auto_draw=x;_drive()
		"pause":
			step_pause=x
			if not x and waiting_click:waiting_click=false
		"labels":labels_on=x;board3d.set_labels(x)
		"plates":clear_plates=x;board3d.set_clear_plates(x)
		"blood":blood_on=x;board3d.blood=x
		"sound":sound_on=x;board3d.sound=x
	_save_settings();_fill_game_options()
var team_cols: Array=[]
var panel_home: Control
var cards: Dictionary={}
const CARD_W=196.0
func _refresh_portraits() -> void:
	# faccette in colonna: volto, nome e barre (ferite, fatica, magia); sotto, la pedina giocata e la formula col dado.
	# Chi sta agendo ha il riquadro acceso e la pedina grande.
	if team_cols.is_empty():return
	cards={}
	if action_panel!=null and is_instance_valid(action_panel) and action_panel.get_parent() in team_cols:action_panel.reparent(panel_home,false)   # non va buttato con le faccette
	for tc in team_cols:clear(tc);tc.visible=not game.state.is_empty() and game.state.phase!="deploy"
	if game.state.is_empty() or game.state.phase=="deploy":return
	var notes=_fighter_notes()
	var shown=[[],[]]
	for i in game.state.fighters.size():
		var p=game.state.fighters[i]
		if p.cell=="" and p.alive:continue
		if not p.alive and int(p.get("owner",-1))>=0:continue   # golem evocati e caduti: spariscono
		shown[posmod(int(p.team),2)].append(i)
	var avail=maxf(300.0,(stage.size.y if stage else 800.0)-30.0)
	var active=int(game.state.get("active",-1))
	if game.state.phase in ["opportunity","reaction"] and not game.state.get("pending",{}).get("reactors",[]).is_empty():active=int(game.state.pending.reactors[0])
	var acting_phase=game.state.phase in ["acting","opportunity","reaction","stumble","upkeep"]
	for side in 2:
		var n=maxi(1,shown[side].size())
		var po=_panel_owner();var room=avail
		if po>=0 and po in shown[side] and _human(po):room-=240.0   # il riquadro delle azioni sta in questa colonna
		var budget=(room-6.0*(n-1))/n
		var compact=budget<112.0;var tiny=budget<76.0
		for i in shown[side]:
			var p=game.state.fighters[i];var team_col=Color("69cec1") if int(p.team)==0 else Color("e68078")
			var on=(acting_phase and i==active) or (game.state.phase=="draw" and i==last_actor)
			var card=PanelContainer.new();var sb=box(Color(.32,.25,.08,.97) if on else Color(PANEL.r,PANEL.g,PANEL.b,.9),8)
			sb.border_color=GOLD if on else team_col;sb.set_border_width_all(4 if on else 2)
			if on:sb.shadow_color=Color(GOLD.r,GOLD.g,GOLD.b,.6);sb.shadow_size=10
			sb.content_margin_left=5;sb.content_margin_right=5;sb.content_margin_top=4;sb.content_margin_bottom=4;card.add_theme_stylebox_override("panel",sb)
			card.mouse_filter=Control.MOUSE_FILTER_IGNORE;card.modulate=Color(1,1,1,1) if p.alive else Color(.55,.55,.55,.7);card.custom_minimum_size.x=CARD_W
			if on and waiting_click:   # pausa: si prosegue cliccando questa faccetta
				card.mouse_filter=Control.MOUSE_FILTER_STOP;card.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND;card.tooltip_text="Clicca per continuare"
				card.gui_input.connect(func(ev):if ev is InputEventMouseButton and ev.pressed:waiting_click=false;_refresh_portraits())
			team_cols[side].add_child(card);cards[i]=card
			var v=VBoxContainer.new();v.add_theme_constant_override("separation",3);v.mouse_filter=Control.MOUSE_FILTER_IGNORE;card.add_child(v)
			var head=HBoxContainer.new();head.add_theme_constant_override("separation",6);head.mouse_filter=Control.MOUSE_FILTER_IGNORE;v.add_child(head)
			if on and waiting_click:
				var go=label("Clicca qui per continuare",11,DARK_INK);go.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
				var gp=PanelContainer.new();gp.add_theme_stylebox_override("panel",box(GOLD,6));gp.mouse_filter=Control.MOUSE_FILTER_IGNORE;go.mouse_filter=Control.MOUSE_FILTER_IGNORE;gp.add_child(go);v.add_child(gp)
			var fs=28.0 if tiny else 44.0
			var face=TextureRect.new();face.custom_minimum_size=Vector2(fs,fs);face.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;face.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;face.mouse_filter=Control.MOUSE_FILTER_IGNORE
			var fp=face_path(p.character)
			if not ResourceLoader.exists(fp):fp="res://assets/reborn/minis/%s.webp"%p.character
			if ResourceLoader.exists(fp):face.texture=load(fp)
			head.add_child(face)
			var info=VBoxContainer.new();info.add_theme_constant_override("separation",2);info.size_flags_horizontal=Control.SIZE_EXPAND_FILL;info.mouse_filter=Control.MOUSE_FILTER_IGNORE;head.add_child(info)
			var nm=label(p.name.split(" ")[0]+("" if p.alive else " (caduto)"),13,GOLD if on else team_col);nm.clip_text=true;nm.custom_minimum_size.x=CARD_W-fs-22;info.add_child(nm)
			var hp=maxi(0,int(p.hp));var fat=int(p.fatigue)+int(p.permanent);var mage=bool(game.definition(p).get("mage",false))
			var bw=CARD_W-fs-24
			if not tiny:
				info.add_child(_meter(float(hp)/maxf(1,float(p.max_hp)),Color("5fd068"),"%d ferite"%hp,bw))
				info.add_child(_meter(clampf(float(fat)/10.0,0,1),Color("b48cff"),"%d fatica"%fat,bw))
				if mage:info.add_child(_meter(clampf(float(p.magic)/15.0,0,1),Color("6fa8ff"),"%d punti magia"%int(p.magic),bw))
			var arrows=int(p.get("arrows",-1))
			var nums=label("%d ferite · %d fatica%s%s"%[hp,fat," · %d magia"%int(p.magic) if mage else ""," · %d frecce"%arrows if arrows>=0 else ""],10,MUTED);nums.clip_text=true;nums.custom_minimum_size.x=bw;info.add_child(nums)
			# la pedina giocata (piccola) e la formula col dado; grande e in evidenza mentre agisce
			var nt=notes.get(i,{});var mv_def=game.move(p) if p.alive else {}
			if mv_def.is_empty() or (str(nt.get("move",""))=="" and not on) or (tiny and not on):continue
			var row=HBoxContainer.new();row.add_theme_constant_override("separation",5);row.mouse_filter=Control.MOUSE_FILTER_IGNORE;v.add_child(row)
			var ts=(58.0 if on else (22.0 if compact else 30.0))
			var tk=token_widget(mv_def,ts/.8625)
			tk.tooltip_text=_move_tip(mv_def);tk.mouse_filter=Control.MOUSE_FILTER_PASS;row.add_child(tk)
			var lines=nt.get("lines",[])
			if compact and not on:
				var ml=label(str(mv_def.name),10,GOLD);ml.clip_text=true;ml.custom_minimum_size.x=CARD_W-ts-20;row.add_child(ml);continue
			var rt=RichTextLabel.new();rt.bbcode_enabled=true;rt.scroll_active=false;rt.fit_content=true;rt.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			rt.custom_minimum_size=Vector2(CARD_W-ts-20,0);rt.size_flags_horizontal=Control.SIZE_EXPAND_FILL;rt.mouse_filter=Control.MOUSE_FILTER_IGNORE
			var fsz=12 if on else 10;rt.add_theme_font_size_override("normal_font_size",fsz);rt.add_theme_font_size_override("bold_font_size",fsz)
			var txt="[b][color=#%s]%s[/color][/b]"%[GOLD.to_html(false),str(mv_def.name)]
			if not lines.is_empty():txt+="\n"+_log_bbcode(lines.slice(lines.size()-1)).replace("width=18 height=18","width=%d height=%d"%[fsz+3,fsz+3])
			rt.text=txt;row.add_child(rt)
	call_deferred("_place_panel")
func _panel_owner() -> int:
	# il personaggio a cui si riferisce il riquadro delle azioni (se c'è)
	match str(game.state.get("phase","")):
		"acting","upkeep":return int(game.state.active)
		"opportunity","reaction":return int(game.state.pending.reactors[0]) if not game.state.pending.get("reactors",[]).is_empty() else -1
		"stumble":return int(game.state.pending.actor)
	return -1
func _place_panel() -> void:
	# il riquadro delle azioni compare nella colonna, subito sotto la faccetta del personaggio che deve decidere
	if action_panel==null or not is_instance_valid(action_panel):return
	var o=_panel_owner()
	if o>=0 and cards.has(o) and is_instance_valid(cards[o]):
		var card: Control=cards[o];var col: Control=card.get_parent()
		if action_panel.get_parent()!=col:action_panel.reparent(col,false)
		col.move_child(action_panel,card.get_index()+1)
		action_panel.custom_minimum_size.x=CARD_W
	elif action_panel.get_parent()!=panel_home:
		action_panel.custom_minimum_size.x=0
		action_panel.reparent(panel_home,false)
func _fighter_notes() -> Dictionary:
	# dal diario: per ogni personaggio la mossa rivelata per ultima e i tiri di dado che ne sono seguiti
	var names=[]
	for i in game.state.fighters.size():names.append([str(game.state.fighters[i].name),i])
	names.sort_custom(func(a,b):return a[0].length()>b[0].length())   # prima i nomi lunghi ("Golem di Thorn")
	var out={};var last_attacker=-1
	for raw in game.state.log:
		var line=str(raw)
		if line.begins_with("Turno "):out={};last_attacker=-1;continue   # nuovo turno: le pedine giocate si azzerano
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
	var back=ColorRect.new();back.color=Color("1a110b");back.custom_minimum_size=Vector2(w,6);back.tooltip_text=tip;back.mouse_filter=Control.MOUSE_FILTER_PASS
	var fill=ColorRect.new();fill.color=col if f>.5 or col!=Color("5fd068") else (Color("f0c040") if f>.25 else Color("d9534f"));fill.size=Vector2(w*clampf(f,0,1),6);fill.mouse_filter=Control.MOUSE_FILTER_IGNORE;back.add_child(fill)
	return back
var _dice_re: RegEx
# cronaca in alto: le righe nuove dall'ultimo aggiornamento formano un blocco; il blocco prima scende sotto
func _update_news() -> void:
	if news_panel==null or not is_instance_valid(news_panel):return
	var total=int(game.state.get("log_n",game.state.log.size()));var lg: Array=game.state.log
	if _news_seen<0:_news_seen=total   # all'inizio (o dopo un caricamento) niente arretrati
	var fresh=mini(total-_news_seen,lg.size())
	if fresh<=0:return
	_news_seen=total
	var lines=lg.slice(lg.size()-fresh)
	if lines.size()>6:lines=lines.slice(lines.size()-6)   # al massimo sei righe: le più recenti
	if news_now.text!="":news_prev.text=news_now.text;news_prev.visible=true
	news_now.text="[b]"+_log_bbcode(lines.slice(0,1))+"[/b]"+("\n"+_log_bbcode(lines.slice(1)) if lines.size()>1 else "")
	news_panel.visible=true
	news_panel.reset_size();news_panel.position.x=(stage.size.x-news_panel.size.x)*.5;news_panel.position.y=6
func _log_bbcode(lines: Array) -> String:
	# "dado 5" nel diario diventa l'immagine del dado con quella faccia
	if _dice_re==null:_dice_re=RegEx.new();_dice_re.compile("dado ([1-6])")
	var out=[]
	for line in lines:
		var t=str(line).replace("[","[lb]")
		t=_dice_re.sub(t,"[img width=18 height=18]res://assets/ui/dice_$1.png[/img]",true)
		out.append(t)
	return "\n".join(out)
var panel_narrow=false
func _layout_overlays() -> void:
	# i pulsanti consecutivi stanno sulla stessa riga; il pannello sparisce se è vuoto.
	# Sotto una faccetta (colonna stretta) i pulsanti restano uno sotto l'altro e i testi vanno a capo.
	var kids=sidebar.get_children();var row: HBoxContainer=null
	for c in kids:
		if panel_narrow:
			if c is Button:
				c.size_flags_horizontal=Control.SIZE_EXPAND_FILL;c.clip_text=true;c.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
				c.add_theme_font_size_override("font_size",14);c.custom_minimum_size.x=0;c.tooltip_text=c.text
				for st in ["normal","hover","pressed","disabled"]:   # meno margine laterale: il pulsante sta nella colonna
					var sb=c.get_theme_stylebox(st)
					if sb is StyleBoxFlat:sb=sb.duplicate();sb.content_margin_left=8;sb.content_margin_right=8;c.add_theme_stylebox_override(st,sb)
			elif c is HBoxContainer:   # intestazioni (fase · nome): vanno a capo invece di allargare la colonna
				for h in c.get_children():
					if h is Label:h.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;h.custom_minimum_size.x=0;h.size_flags_horizontal=Control.SIZE_EXPAND_FILL
				c.custom_minimum_size.x=0
			elif c is Label and c.autowrap_mode!=TextServer.AUTOWRAP_OFF:c.custom_minimum_size.x=CARD_W-30
			elif c is Label:c.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;c.custom_minimum_size.x=CARD_W-30
			continue
		if c is Button and not c is CheckButton:
			if row==null:
				row=HBoxContainer.new();row.alignment=BoxContainer.ALIGNMENT_CENTER;row.add_theme_constant_override("separation",8)
				sidebar.add_child(row);sidebar.move_child(row,c.get_index())
			sidebar.remove_child(c);row.add_child(c)
		elif c is Label and c.autowrap_mode!=TextServer.AUTOWRAP_OFF:
			c.custom_minimum_size.x=420;row=null
		else:row=null
	action_panel.visible=sidebar.get_child_count()>0
	picker.visible=picker.get_child_count()>0
func _refresh() -> void:
	if not showing_game:return
	clear(sidebar);clear(picker)
	turn_label.text=("STANZA "+room_code+" · " if room_code!="" else "")+"TURNO %d" % game.state.turn
	var over=str(game.state.get("phase",""))=="finished"
	if replay_btn:replay_btn.visible=over;new_btn.visible=over
	if over:
		var w=int(game.state.winner)
		turn_label.text="FINE · "+("vince la Lama Lucente" if w==0 else ("vince l’Ombra Oscura" if w==1 else "pace nell’arena"))
	_refresh_portraits()
	panel_narrow=_panel_owner()>=0 and cards.has(_panel_owner()) and _human(_panel_owner())
	log_box.text=_log_bbcode(game.state.log.slice(maxi(0,game.state.log.size()-40)))
	_update_news()
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
	var owner=_panel_owner()
	if owner>=0 and not _human(owner):clear(sidebar)   # decide l'IA: basta la faccetta accesa, niente riquadro di passaggio
	_layout_overlays()
	call_deferred("_place_panel")
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
		var t=token_widget(m,w);t.mouse_filter=Control.MOUSE_FILTER_STOP
		t.position=Vector2(col*(w*.75+gap),row*(h+gap)+((h+gap)*.5 if col%2==1 else 0.0))
		var full=_move_tip(m)+_reach_tip(p,id)
		t.tooltip_text=full;t.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
		var tip=full.replace("\n"," · ")
		t.mouse_entered.connect(func():info.text=tip)
		t.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index==MOUSE_BUTTON_LEFT:on_pick.call(id))
		c.add_child(t);k+=1
	return c
func _action_panel() -> void:
	var i=int(game.state.active);var p=game.state.fighters[i];var m=game.move(p)
	board.highlights=game.targets(i);board.preview_facing=selected_facing;board.focus_fighter=i
	if not _human(i):return   # la pedina estratta si vede sotto la faccetta del personaggio: niente riquadro
	# la pedina e i valori sono già nella faccetta accesa: qui solo cosa fare
	var col=VBoxContainer.new();col.add_theme_constant_override("separation",2);sidebar.add_child(col)
	col.add_child(label(_move_tip(m).split("\n",true,1)[1] if "\n" in _move_tip(m) else "",12,MUTED))
	board.highlights=game.targets(i);board.preview_facing=selected_facing;board.focus_fighter=i
	if not _human(i):col.add_child(label("Il personaggio sta decidendo la sua azione…",13,MUTED));return
	var tg=game.targets(i)
	# pedina d'attacco o di parata con lati verdi: un passo di un esagono, prima o dopo l'azione (prima lo sapeva fare solo l'IA)
	var steps: Array=game.step_cells(i);var sim_cell=str(p.cell)
	if selected_step!="" and not selected_step in steps:selected_step=""
	if not steps.is_empty():
		var ob=OptionButton.new();ob.add_theme_font_size_override("font_size",13);ob.add_item("Nessun passo");ob.fit_to_longest_item=false;ob.clip_text=true;ob.custom_minimum_size.x=170
		var names=["avanti","avanti a destra","indietro a destra","indietro","indietro a sinistra","avanti a sinistra"]
		var opts=[["",false]]
		for k in steps:
			var side=posmod(BloodRules.direction(str(p.cell),str(k))-int(p.facing),6)
			for after in [false,true]:
				opts.append([str(k),after]);ob.add_item("Passo %s, %s"%[names[side],"dopo l'azione" if after else "prima dell'azione"])
				if selected_step==str(k) and selected_step_after==after:ob.select(opts.size()-1)
		ob.item_selected.connect(func(n):selected_step=opts[n][0];selected_step_after=opts[n][1];selected_cell="";_refresh())
		ob.tooltip_text="Questa pedina ha lati verdi: puoi fare un passo di un esagono prima o dopo l'azione";sidebar.add_child(ob)
		if selected_step!="" and not selected_step_after:   # col passo prima, i bersagli si contano dall'esagono d'arrivo
			sim_cell=selected_step
			var old=p.cell;p.cell=sim_cell;tg=game.targets(i);p.cell=old
			board.highlights=tg
	var self_only=tg.size()==1 and str(tg[0])==sim_cell
	if tg.size()==1 and selected_cell=="":selected_cell=str(tg[0])   # un solo bersaglio possibile: già scelto
	var msg="Tocca una casella evidenziata, scegli l’orientamento e conferma."
	if _reach_tip(p,m.id)!="":msg+=" Con l’arma lunga puoi colpire anche il nemico a due esagoni davanti."
	if self_only:msg="Questa pedina non ha bersaglio: premi Esegui la mossa."
	elif tg.is_empty():msg="Nessun bersaglio raggiungibile: puoi solo rinunciare all’azione."
	elif tg.size()==1:msg="Un solo bersaglio possibile, già selezionato: premi Esegui la mossa."
	var hint=label(msg,12,GOLD if self_only or tg.size()==1 else MUTED);hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;col.add_child(hint)
	if last_error!="":var er=label(last_error,12,Color("ff8a80"));er.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;col.add_child(er)
	if selected_cell!="" and not self_only:sidebar.add_child(label("Destinazione / bersaglio: "+selected_cell,15,GOLD))
	_facing_controls(game.max_rotation(i),int(p.facing))
	if m.get("spell",false) and m.id in ["fireball","lightning","control","abyss"]:
		var sp=SpinBox.new();sp.min_value=0;sp.max_value=maxi(0,p.magic-int(m.cost));sp.value=selected_extra;sp.prefix="Magia extra: ";sp.value_changed.connect(func(v):selected_extra=int(v));sidebar.add_child(sp)
	if m.id=="concentrate":
		for j in game.state.fighters.size():
			if game.state.fighters[j].pieces:sidebar.add_child(button("Rigenera "+game.state.fighters[j].name,func():_submit({"type":"regenerate","fighter":j})))
	var command={"type":"act","target":selected_cell if selected_cell!="" else sim_cell,"facing":selected_facing,"extra":selected_extra}
	var b=button("Esegui la mossa",func():_submit(command),true);b.disabled=not command.target in board.highlights;sidebar.add_child(b)
	if selected_step!="":
		command["step"]=selected_step;command["step_after"]=selected_step_after
		if self_only and not selected_step_after:command.erase("target")   # nessun bersaglio: dopo il passo la mossa si esegue lì
	if m.id=="guard":sidebar.add_child(button("Resta in guardia",func():_submit({"type":"act","wait":true,"facing":selected_facing})))
	sidebar.add_child(button("Rinuncia all’azione",func():_submit({"type":"act","pass":true,"facing":int(p.facing)})))
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
		var b=_bar_button("Estrai la prossima pedina",func():_submit({"type":"draw"}),"Estrai la prossima pedina dal contenitore");sidebar.add_child(b)
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
	pass   # fine scontro: risultato, Replay 3D e Nuovo scontro stanno nella barra in alto; niente riquadro sopra la mappa
func _facing_controls(limit:=6,from:=-1) -> void:
	# limit: di quanti lati si può ruotare rispetto all'orientamento attuale (from); 0 = fisso
	if limit<=0:return
	var row=HBoxContainer.new();row.alignment=BoxContainer.ALIGNMENT_CENTER;sidebar.add_child(row)
	var turn=func(d):
		var nf=posmod(selected_facing+d,6)
		if from>=0 and limit<3 and mini(posmod(nf-from,6),posmod(from-nf,6))>limit:return   # oltre la rotazione consentita
		selected_facing=nf;_refresh()
	row.add_child(icon_button("left",func():turn.call(-1),"Ruota a sinistra",40.0))
	row.add_child(label(("Fronte %d/6" if panel_narrow else "Orientamento %d / 6")%(selected_facing+1),15))
	row.add_child(icon_button("right",func():turn.call(1),"Ruota a destra",40.0))
func _wrap(text: String) -> void:
	var l=label(text,15,MUTED);l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;l.custom_minimum_size.x=320;sidebar.add_child(l)
func _tile(path: String,width: int) -> void:
	var t=TextureRect.new();t.texture=load(path);t.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;t.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;t.custom_minimum_size=Vector2(width,width*.866);sidebar.add_child(t)
func _reach_tip(p: Dictionary,id: String) -> String:
	# regola modificata delle lance: affondo e carica arrivano al secondo esagono davanti
	if game.hr("reach") and (str(p.character) in BloodRules.SPEARS or bool(game.definition(p).get("reach",false))) and id in ["thrust","charge"]:
		return "\nArma lunga: colpisce anche il secondo esagono davanti (regola modificata)"
	return ""
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
	selected_move="";selected_cell="";selected_path=[];selected_extra=0;handicap_picks=[];selected_step="";selected_step_after=false
	selected_facing=0
	if game.state.active>=0:
		selected_facing=int(game.state.fighters[game.state.active].facing)
		if game.state.phase=="deploy":selected_facing=0 if game.state.fighters[game.state.active].team==0 else 3
func _submit(command: Dictionary) -> void:
	if room_code!="" and network!=null:
		await network.submit(command);return
	var before=int(game.state.get("active",-1));var ph=str(game.state.get("phase",""))
	if _apply(command):
		last_error=""
		if ph=="acting" and str(command.get("type",""))=="act":last_actor=before
		if str(command.get("type",""))=="draw":last_actor=-1
		await _show_result();_drive()
	else:
		status.text="Questa azione non è valida: controlla bersaglio e orientamento."
		last_error="Azione non valida: controlla bersaglio e orientamento.";_refresh()
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
	await _wait_animation()   # le miniature finiscono la mossa prima di tutto il resto
	var ph=str(game.state.get("phase",""))
	var pause=speed
	if ph=="acting" and not _human(int(game.state.active)):pause=maxf(speed,SHOW_TIME)   # si vede chi agisce e con che pedina
	if ph=="draw" and last_actor>=0:pause=maxf(speed,READ_TIME)   # il tempo di leggere il risultato
	await get_tree().create_timer(pause).timeout
	if ph=="draw" and last_actor>=0 and step_pause and room_code=="":   # resta così finché non si clicca la faccetta
		waiting_click=true;_refresh_portraits()
		while waiting_click and showing_game:await get_tree().create_timer(.1).timeout
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
			if p.controller=="ai" or p.get("owner",-1)>=0:
				acted=game.act(BloodAI.command(game,i))
				if acted:last_actor=i
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
			if s.fighters[s.active].controller=="ai":acted=game.advance_effect(BloodAI.effect_facing(game))
		"draw":
			var guarding=s.fighters.any(func(p):return p.guarding and p.controller=="human")
			if auto_draw and not guarding:game.draw_next();acted=true;last_actor=-1
	if acted:await _show_result();_drive()
func _wait_animation() -> void:
	while board3d!=null and is_instance_valid(board3d) and board3d.is_visible_in_tree() and board3d.busy():
		await get_tree().create_timer(.1).timeout
func _show_result() -> void:
	# prima le miniature eseguono l'azione, poi faccette e diario mostrano il risultato (niente spoiler)
	_reset_selection()
	if board3d!=null and is_instance_valid(board3d) and board3d.is_visible_in_tree():
		board3d.copy_from(board);await _wait_animation()
	_refresh();_autosave()
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
	var row=HBoxContainer.new();v.add_child(row);row.add_child(button("Pagina prima",func():manual_page=posmod(manual_page-1,12);_manual_content()));row.add_child(label("Pagina %d / 12"%(manual_page+1)));row.add_child(button("Pagina dopo",func():manual_page=posmod(manual_page+1,12);_manual_content()));row.add_child(button("Chiudi",manual_window.queue_free))
	var l=label("Chiarimento dell’autore: Disperdi magia consuma la mossa solo se riesce.",14,GOLD);v.add_child(l)
func _credits() -> void:
	var w=AcceptDialog.new();w.title="Blood Master Deluxe";w.dialog_text="Ideazione e sviluppo: Stefano Ancillai e Marco Ramadori\nDisegni: Luigi Filipponi\nEdizione originale: Devil’s Den\n\nVersione digitale realizzata dalle scansioni dell’autore.\nMotore Godot 4.7 · Partite online con Firebase\nEffetti sonori: registrazioni CC0 (OpenGameArt, Freesound e altri; elenco in docs/audio_fonti_licenze.csv)\nCaratteri: Cinzel, Cinzel Decorative (Natanael Gama) e Alegreya (Huerta Tipográfica), Noto Sans Symbols 2 (Google), SIL Open Font License\n\nLe illustrazioni e il regolamento appartengono ai rispettivi autori.";add_child(w);w.confirmed.connect(w.queue_free);w.popup_centered()
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
