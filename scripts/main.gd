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
func _show_menu() -> void:
	showing_game=false;clear(page);menu_options=[]
	_header("EDIZIONE DELUXE · VERSIONE IN SVILUPPO")
	var content=HBoxContainer.new();content.size_flags_vertical=Control.SIZE_EXPAND_FILL;content.add_theme_constant_override("separation",24);page.add_child(content)
	var hero=VBoxContainer.new();hero.size_flags_horizontal=Control.SIZE_EXPAND_FILL;hero.size_flags_stretch_ratio=1.15;content.add_child(hero)
	hero.add_child(label("Entra nell’arena.",42))
	var trials=HBoxContainer.new();trials.add_theme_constant_override("separation",10);hero.add_child(trials)
	trials.add_child(button("Gascor 3D",func():get_tree().change_scene_to_file("res://scenes/gascor_preview.tscn")))
	trials.add_child(button("Anteos 3D",func():get_tree().change_scene_to_file("res://scenes/anteos_preview.tscn")))
	trials.add_child(button("Altri 3D",func():get_tree().change_scene_to_file("res://scenes/ut_preview.tscn")))
	trials.add_child(button("Duello 3D",func():get_tree().change_scene_to_file("res://scenes/duel_3d.tscn")))
	var intro=label("Scegli la tua mossa. Attendi l’estrazione.\nColpisci quando l’avversario abbassa la guardia.",19,MUTED);hero.add_child(intro)
	var arena_view=TextureRect.new();arena_view.texture=load("res://assets/arena/arena.webp");arena_view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;arena_view.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;arena_view.size_flags_vertical=Control.SIZE_EXPAND_FILL;arena_view.custom_minimum_size=Vector2(350,350);hero.add_child(arena_view)
	hero.add_child(label("Stefano Ancillai & Marco Ramadori\nIllustrazioni originali di Luigi Filipponi",14,MUTED))
	var right=VBoxContainer.new();right.custom_minimum_size.x=560;right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;content.add_child(right)
	var modes=HBoxContainer.new();right.add_child(modes)
	for option in [["solo","Contro IA"],["local","Stesso schermo"],["online","Online"]]:
		var b=button(option[1],func():mode=option[0];_show_menu());b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if mode==option[0]:b.add_theme_color_override("font_color",GOLD)
		modes.add_child(b)
	var config=panel_content(right)
	config.add_child(label("PREPARA LO SCONTRO",13,GOLD))
	var scene_choice=OptionButton.new();scene_choice.add_item("Scontro frontale · squadre e pace/guerra");scene_choice.add_item("Scontro libero · squadre a scelta");scene_choice.add_item("Blood Master · asta e 3 round")
	scene_choice.select(["frontale","libero","bloodmaster"].find(scenario));scene_choice.item_selected.connect(func(n):scenario=["frontale","libero","bloodmaster"][n]);config.add_child(scene_choice)
	config.add_child(label("Giocatori e personaggi",18))
	var scroll=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.custom_minimum_size.y=300;config.add_child(scroll)
	roster_box=VBoxContainer.new();roster_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(roster_box)
	if roster.is_empty():roster=[{"character":"gascor","team":0,"controller":"human","seat":0},{"character":"anteos","team":1,"controller":"ai","seat":1}]
	for i in roster.size():_roster_row(i)
	var controls=HBoxContainer.new();config.add_child(controls)
	controls.add_child(button("+ Giocatore",func():
		if roster.size()<10:
			var candidates=game.catalog.keys().filter(func(k):return k!="golem" and not roster.any(func(r):return r.character==k))
			roster.append({"character":candidates[0],"team":roster.size()%2,"controller":"ai" if mode=="solo" else "human","seat":roster.size()});_show_menu()))
	controls.add_child(button("− Giocatore",func():
		if roster.size()>2:roster.pop_back();_show_menu()))
	var tip=label("Le mosse restano segrete fino all’estrazione.\nMaghi e scheletri possono combattere in entrambi gli Ordini.",14,MUTED);config.add_child(tip)
	if mode=="online":_online_menu(config)
	else:config.add_child(button("Entra nell’arena",_start_local,true))
	if FileAccess.file_exists("user://battle.json"):right.add_child(button("Riprendi la partita salvata",_load_game))
	status=label(message,14,GOLD);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;right.add_child(status)
func _roster_row(i: int) -> void:
	var row=HBoxContainer.new();roster_box.add_child(row)
	row.add_child(label(str(i+1),16,GOLD))
	var select=OptionButton.new();select.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var keys=game.catalog.keys().filter(func(k):return k!="golem")
	for k in keys:select.add_item(game.catalog[k].name+" · "+game.catalog[k].title)
	select.select(keys.find(roster[i].character));select.item_selected.connect(func(n):roster[i].character=keys[n]);row.add_child(select)
	var team=OptionButton.new();team.add_item("Lama");team.add_item("Ombra");team.select(int(roster[i].team));team.item_selected.connect(func(n):roster[i].team=n);row.add_child(team)
	var ctrl=OptionButton.new();ctrl.add_item("Persona");ctrl.add_item("IA");ctrl.select(1 if roster[i].controller=="ai" else 0);ctrl.item_selected.connect(func(n):roster[i].controller="ai" if n else "human");row.add_child(ctrl)
func _start_local() -> void:
	var seen=[];var teams=[]
	for r in roster:
		if r.character in seen:message="Ogni personaggio può essere scelto una sola volta.";_show_menu();return
		seen.append(r.character)
		if not r.team in teams:teams.append(r.team)
	if teams.size()<2:message="Assegna almeno un personaggio a ciascun Ordine.";_show_menu();return
	room_code="";net_host=false
	if scenario=="bloodmaster":
		if roster.size()<3:message="Lo scenario Blood Master richiede almeno tre giocatori.";_show_menu();return
		game.start_campaign(roster,int(Time.get_unix_time_from_system()))
	else:game.new_game(roster,scenario,int(Time.get_unix_time_from_system()))
	_build_game();_refresh();_drive()
func _build_game() -> void:
	showing_game=true;clear(page);_header("DELUXE · MOSSE SEGRETE, COMBATTIMENTO TATTICO")
	var body=HBoxContainer.new();body.size_flags_vertical=Control.SIZE_EXPAND_FILL;page.add_child(body)
	var left=VBoxContainer.new();left.custom_minimum_size.x=210;body.add_child(left)
	left.add_child(label("NELL’ARENA",13,GOLD))
	var scroll=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;left.add_child(scroll)
	roster_box=VBoxContainer.new();roster_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(roster_box)
	var middle=VBoxContainer.new();middle.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_child(middle)
	board=ArenaBoard.new();board.game=game;board.size_flags_vertical=Control.SIZE_EXPAND_FILL;board.cell_clicked.connect(_cell_clicked);middle.add_child(board)
	board3d=ArenaBoard3D.new();board3d.game=game;board3d.size_flags_vertical=Control.SIZE_EXPAND_FILL;board3d.cell_clicked.connect(_cell_clicked);board3d.visible=minis_3d;middle.add_child(board3d)
	board.visible=not minis_3d
	var toolbar=HBoxContainer.new();middle.add_child(toolbar)
	toolbar.add_child(button("Inquadra",func():board.fit();board3d.fit()))
	var minis=CheckButton.new();minis.text="Miniature 3D";minis.button_pressed=minis_3d;minis.toggled.connect(func(v):minis_3d=v;board.visible=not v;board3d.visible=v;_refresh());toolbar.add_child(minis)
	var grid=CheckButton.new();grid.text="Griglia";grid.toggled.connect(func(v):board.show_grid=v;board.queue_redraw());toolbar.add_child(grid)
	var auto=CheckButton.new();auto.text="Estrazione automatica";auto.button_pressed=auto_draw;auto.toggled.connect(func(v):auto_draw=v;_drive());toolbar.add_child(auto)
	toolbar.add_child(spacer());toolbar.add_child(button("−",func():board.zoom=maxf(.8,board.zoom-.15);board.queue_redraw();board3d.zoom=maxf(.6,board3d.zoom/1.15);board3d.fit_zoom()));toolbar.add_child(button("+",func():board.zoom=minf(3.5,board.zoom+.15);board.queue_redraw();board3d.zoom=minf(3.0,board3d.zoom*1.15);board3d.fit_zoom()))
	var right_scroll=ScrollContainer.new();right_scroll.custom_minimum_size.x=355;body.add_child(right_scroll)
	sidebar=VBoxContainer.new();sidebar.custom_minimum_size.x=335;sidebar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;right_scroll.add_child(sidebar)
	var journal=PanelContainer.new();journal.custom_minimum_size.y=100;page.add_child(journal)
	log_box=RichTextLabel.new();log_box.bbcode_enabled=true;log_box.scroll_following=true;log_box.custom_minimum_size=Vector2(0,100);log_box.add_theme_font_size_override("normal_font_size",14);journal.add_child(log_box)
	status=label("",14,MUTED);page.add_child(status)
func _refresh() -> void:
	if not showing_game:return
	clear(roster_box);clear(sidebar)
	turn_label.text=("STANZA "+room_code+" · " if room_code!="" else "")+"TURNO %d" % game.state.turn
	for i in game.state.fighters.size():
		var p=game.state.fighters[i];var d=game.definition(p)
		var b=button(p.name+ ("  †" if not p.alive else ""),func():_inspect(i))
		b.alignment=HORIZONTAL_ALIGNMENT_LEFT;b.add_theme_font_size_override("font_size",16)
		b.add_theme_color_override("font_color",Color("79cfbf") if p.team==0 else Color("ed9992"));roster_box.add_child(b)
		var info=label("%d / %d vita  ·  %d fatica%s" % [p.hp,p.max_hp,p.fatigue+p.permanent,"  ·  %d magia"%p.magic if d.mage else ""],12,MUTED);roster_box.add_child(info)
		var hp=ProgressBar.new();hp.max_value=maxi(1,int(p.max_hp));hp.value=p.hp;hp.show_percentage=false;hp.custom_minimum_size.y=5;roster_box.add_child(hp)
		var phase=game.move(p).get("name","")
		if game.state.phase=="planning" and (game.state.plans.has(str(i)) or str(i) in remote_ready):phase="Mossa scelta · segreta"
		if p.pieces:phase="In pezzi"
		if p.frog:phase="Trasformato in ranocchio"
		roster_box.add_child(label(phase+ (" · ha agito" if p.done else ""),12,MUTED))
	log_box.text="\n".join(game.state.log.slice(maxi(0,game.state.log.size()-20)))
	board.highlights=[];board.preview_facing=-1;board.focus_fighter=-1;board.selected=selected_cell
	status.text="Rotellina: zoom · Trascina con il tasto destro: sposta l’arena · Tocca un nome per vedere la scheda."
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
		"net_reveal":sidebar.add_child(label("Tutti hanno scelto.\nApertura delle mosse…",21,GOLD))
	board.queue_redraw()
	if board3d:board3d.copy_from(board)
func _human(i: int) -> bool:
	if i<0:return false
	var p=game.state.fighters[i]
	if p.get("controller_by",-1)>=0:p=game.state.fighters[p.controller_by]
	return p.controller=="human" and (room_code=="" or int(p.seat)==net_seat)
func _heading(i: int,text: String) -> void:
	var p=game.state.fighters[i]
	sidebar.add_child(label(text.to_upper(),13,GOLD))
	sidebar.add_child(label(p.name,27))
	board.focus_fighter=i
func _deployment_panel() -> void:
	var i=int(game.state.active);var p=game.state.fighters[i];_heading(i,"Schieramento")
	board.highlights=game.entry_cells(int(p.team));board.preview_facing=selected_facing
	_wrap("Scegli uno degli ingressi evidenziati. Puoi condividere la zona di ingresso con un alleato.")
	if _human(i):
		_facing_controls()
		var b=button("Schiera il personaggio",func():_submit({"type":"deploy","target":selected_cell,"facing":selected_facing}),true);b.disabled=not selected_cell in board.highlights;sidebar.add_child(b)
	else:_wrap("In attesa dello schieramento…")
func _planning_panel() -> void:
	var i=-1
	for j in game.needs_plan():
		if _human(j) and not str(j) in remote_ready:i=j;break
	if i==-1:
		sidebar.add_child(label("MOSSE SEGRETE",13,GOLD));_wrap("La tua scelta è al sicuro. Aspettiamo gli altri personaggi.")
		return
	focus_index=i;_heading(i,"Scegli in segreto")
	_wrap("Scegli solo la mossa: deciderai spostamento e bersaglio quando verrà estratta.")
	var grid=GridContainer.new();grid.columns=3;grid.add_theme_constant_override("h_separation",6);grid.add_theme_constant_override("v_separation",8);sidebar.add_child(grid)
	for id in game.legal_moves(i):
		var m=game.move(game.state.fighters[i],id)
		var col=VBoxContainer.new();grid.add_child(col)
		var b=TextureButton.new();b.texture_normal=load(m.texture);b.ignore_texture_size=true;b.stretch_mode=TextureButton.STRETCH_KEEP_ASPECT_CENTERED;b.custom_minimum_size=Vector2(101,87);b.tooltip_text=_move_tip(m);b.pressed.connect(func():selected_move=id;_refresh());col.add_child(b)
		var text=label(m.name,12,GOLD if selected_move==id else INK);text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;text.custom_minimum_size.x=101;text.clip_text=true;col.add_child(text)
	if selected_move!="" and selected_move in game.legal_moves(i):
		var m=game.move(game.state.fighters[i],selected_move);_wrap(_move_tip(m))
		var move_id=selected_move
		sidebar.add_child(button("Conferma "+m.name,func():_submit({"type":"plan","fighter":i,"move":move_id}),true))
func _action_panel() -> void:
	var i=int(game.state.active);var p=game.state.fighters[i];var m=game.move(p);_heading(i,"Pedina estratta")
	sidebar.add_child(label(m.name,23,GOLD));_tile(m.texture,180)
	_wrap(_move_tip(m))
	board.highlights=game.targets(i);board.preview_facing=selected_facing
	if not _human(i):_wrap("Il personaggio sta decidendo la sua azione…");return
	_wrap("Tocca una casella evidenziata nell’arena. Scegli l’orientamento finale e conferma.")
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
	sidebar.add_child(label("IL CONTENITORE DELLE MOSSE",13,GOLD));sidebar.add_child(label("Chi agirà adesso?",25))
	_wrap("Le pedine vengono estratte casualmente. Una parata o uno sbilanciamento possono consumare la mossa prima che venga estratta.")
	if room_code=="" or net_host:sidebar.add_child(button("Estrai la prossima pedina",func():_submit({"type":"draw"}),true))
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
func _save_game() -> void:
	_autosave();status.text="Partita salvata su questo dispositivo."
func _load_game() -> void:
	var s=JSON.parse_string(FileAccess.get_file_as_string("user://battle.json"))
	if not s is Dictionary or int(s.get("version",0))!=BloodRules.VERSION:message="Il salvataggio non è compatibile.";_show_menu();return
	game.restore(s);room_code="";_build_game();_reset_selection();_refresh();_drive()
func _confirm_menu() -> void:
	var d=ConfirmationDialog.new();d.title="Tornare al menu?";d.dialog_text="La partita locale è salvata automaticamente. Potrai riprenderla da questo dispositivo.";d.confirmed.connect(_show_menu);d.canceled.connect(d.queue_free);d.confirmed.connect(d.queue_free);add_child(d);d.popup_centered()
func _inspect(i: int) -> void:
	var p=game.state.fighters[i];var d=game.definition(p)
	var win=Window.new();win.title=d.name+" · "+d.title;win.size=Vector2i(1050,650);win.transient=true;win.exclusive=true;add_child(win);win.close_requested.connect(win.queue_free)
	var v=VBoxContainer.new();v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);win.add_child(v)
	var card=TextureRect.new();card.texture=load(d.card);card.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;card.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;card.size_flags_vertical=Control.SIZE_EXPAND_FILL;v.add_child(card)
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
	var row=HBoxContainer.new();v.add_child(row);row.add_child(button("←",func():manual_page=posmod(manual_page-1,12);_manual_content()));row.add_child(label("Pagina %d / 12"%(manual_page+1)));row.add_child(button("→",func():manual_page=posmod(manual_page+1,12);_manual_content()));row.add_child(button("Chiudi",manual_window.queue_free))
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
	sidebar.add_child(label("ASTA · ROUND %d / 3"%c.round,13,GOLD));sidebar.add_child(label(d.name,28,GOLD));_tile(d.card,220)
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
