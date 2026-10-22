class_name ArenaBoard
extends Control
signal cell_clicked(cell: String)
signal fighter_clicked(index: int)
var game: BloodRules
var highlights: Array=[]
var selected=""
var focus_fighter=-1
var preview_facing=-1
var show_grid=false
var zoom=1.0
var pan=Vector2.ZERO
var textures={}
var arena_texture=preload("res://assets/arena/arena.webp")
var hovered=""
var origin=Vector2.ZERO
var scale_factor=1.0
var rot=0.0                # rotazione della mappa (radianti), attorno al centro della vista
var view=Transform2D()     # trasformazione della vista: rotazione attorno al centro
var _press=Vector2.ZERO
var _dragging=false
var blood: Array=[]        # macchie di sangue: [cella, scarto in px della mappa, raggio, tonalità]
const GOLD=Color("e0ba77")
const TEAL=Color("69cec1")
const RED=Color("e68078")
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	clip_contents=true
	custom_minimum_size=Vector2(460,350)
	resized.connect(queue_redraw)
func texture(path: String) -> Texture2D:
	if path=="":return null
	if not textures.has(path):textures[path]=load(path)
	return textures[path]
func fit() -> void:zoom=1;pan=Vector2.ZERO;rot=0.0;queue_redraw()
func rotate_view(step: float) -> void:rot+=step;queue_redraw()
func world(k: String) -> Vector2:
	var c=game.cells[k];return Vector2(float(c.x),float(c.y))
func screen(p: Vector2) -> Vector2:return origin+Vector2(p.y,1956-p.x)*scale_factor
func _draw() -> void:
	draw_style_box(_background(),Rect2(Vector2.ZERO,size))
	if game==null:return
	scale_factor=minf((size.x-24)/2736.0,(size.y-24)/1956.0)*zoom
	origin=(size-Vector2(2736,1956)*scale_factor)*.5+pan
	view=Transform2D(0,size*.5)*Transform2D(rot,Vector2.ZERO)*Transform2D(0,-size*.5)
	draw_set_transform_matrix(view*Transform2D(-PI/2,Vector2.ONE*scale_factor,0,origin+Vector2(0,1956*scale_factor)))
	draw_texture(arena_texture,Vector2.ZERO)
	draw_set_transform_matrix(view)
	for k in game.cells:
		var center=screen(world(k));var poly=hexagon(center,121*scale_factor)
		if show_grid:draw_polyline(poly,Color(1,.97,.85,.6),2.0,true)
		if game.cells[k].entry and game.state.get("phase","")=="deploy":draw_colored_polygon(poly,Color(0.1,.8,.7,.2))
		if k in highlights:
			draw_colored_polygon(poly,Color(.8,.65,.3,.23));draw_polyline(poly,GOLD,2.0,true)
		if k==selected:draw_polyline(poly,Color("fff0bf"),4.0,true)
		elif k==hovered:draw_polyline(poly,Color(1,1,1,.7),1.5,true)
	if game.state.is_empty():return
	for b in blood:   # il sangue resta sull'esagono
		if game.cells.has(b[0]):draw_circle(screen(world(b[0])+b[1]),b[2]*scale_factor,Color(.38+b[3]*.12,0,.02,.82))
	for o in game.state.get("obstacles",[]):   # elementi di scena: un simbolo colorato sull'esagono
		if not game.cells.has(o.cell):continue
		var c=screen(world(o.cell));var r=60*scale_factor
		match str(o.kind):
			"column":draw_circle(c,r*.55,Color(.82,.78,.7));draw_arc(c,r*.55,0,TAU,24,Color(.45,.4,.35),3.0*scale_factor);draw_circle(c,r*.3,Color(.7,.66,.58))
			"boulder":draw_colored_polygon(PackedVector2Array([c+Vector2(-r*.7,r*.3),c+Vector2(-r*.4,-r*.5),c+Vector2(r*.3,-r*.6),c+Vector2(r*.75,0),c+Vector2(r*.4,r*.55),c+Vector2(-r*.3,r*.6)]),Color(.45,.42,.4))
			"tree":draw_circle(c,r*.75,Color(.2,.45,.18));draw_circle(c+Vector2(-r*.2,-r*.2),r*.4,Color(.3,.58,.25))
			"water":draw_circle(c,r*.85,Color(.2,.45,.75,.85));draw_arc(c,r*.5,0,TAU,24,Color(.7,.85,1,.7),2.0*scale_factor)
			"rubble":
				for q in 6:draw_circle(c+Vector2.from_angle(q*1.05)*r*.45,r*.22,Color(.5,.44,.38))
	for o in game.state.get("pickups",[]):   # zone di ristoro: pozione rossa, esagono di mana azzurro
		if not game.cells.has(str(o.cell)):continue
		var c=screen(world(str(o.cell)));var r=60*scale_factor
		if str(o.kind)=="potion":
			draw_circle(c,r*.75,Color(1,.3,.3,.18));draw_circle(c+Vector2(0,r*.12),r*.32,Color(.85,.1,.15));draw_rect(Rect2(c+Vector2(-r*.1,-r*.5),Vector2(r*.2,r*.3)),Color(.8,.9,1,.8))
		else:
			draw_colored_polygon(hexagon(c,r*.9),Color(.3,.7,1,.35));draw_polyline(hexagon(c,r*.9),Color(.5,.85,1),2.5*scale_factor,true)
	for e in game.state.effects:
		var path="res://assets/tokens/effect_"+("fire" if e.kind=="livingfire" else e.kind)+".webp"
		var tex=texture(path)
		if tex:draw_texture_rect(tex,Rect2(screen(world(e.cell))-Vector2.ONE*100*scale_factor,Vector2.ONE*200*scale_factor),false)
	for i in game.state.fighters.size():
		var p=game.state.fighters[i]
		if p.cell=="" or not game.cells.has(p.cell) or not p.alive:continue
		var center=screen(world(p.cell))
		# Entry stacking is legal; offset the visual markers without changing cells.
		var count=0
		for j in i:
			if game.state.fighters[j].cell==p.cell:count+=1
		center+=Vector2(count*8,-count*8)
		var m=game.move(p);var path=m.get("texture","")
		if p.frog:path="res://assets/tokens/effect_frog.webp"
		var tex=texture(path);var radius=109*scale_factor
		var color=TEAL if p.team==0 else RED
		draw_circle(center+Vector2(2,4),radius,Color(0,0,0,.5))
		draw_arc(center,radius+3,0,TAU,40,color,3,true)
		if i==focus_fighter:draw_arc(center,radius+7,0,TAU,40,GOLD,3,true)
		var facing=int(p.facing)
		if i==focus_fighter and preview_facing>=0:facing=preview_facing
		draw_set_transform_matrix(view*Transform2D(-PI/2+facing*PI/3,center))
		if tex:draw_texture_rect(tex,Rect2(Vector2(-radius,-radius*.866),Vector2(radius*2,radius*1.732)),false,Color(1,1,1,.72 if p.done else 1))
		draw_set_transform_matrix(view)
		var forward=Vector2.UP.rotated(-PI/2+facing*PI/3)
		draw_circle(center+forward*(radius+9),3,color)
		# barretta delle ferite sempre orizzontale sullo schermo, sotto la pedina
		draw_set_transform(Vector2.ZERO)
		var sc=view*center
		var bar=Rect2(sc+Vector2(-radius,radius+9),Vector2(radius*2,5))
		draw_rect(bar,Color("1a110b"));bar.size.x*=clampf(float(p.hp)/maxf(1,p.max_hp),0,1);draw_rect(bar,color)
		var tired=Rect2(sc+Vector2(-radius,radius+16),Vector2(radius*2,4))   # fatica, piena a 10 punti
		draw_rect(tired,Color("1a110b"));tired.size.x*=clampf(float(int(p.fatigue)+int(p.permanent))/10.0,0,1);draw_rect(tired,Color("b48cff"))
		draw_set_transform_matrix(view)
		if p.burning:draw_circle(center+Vector2(radius,-radius),5,Color("f5a34b"))
		if p.fatigue>0:draw_circle(center+Vector2(-radius,-radius),4,Color("a38bdd"))
		if p.unbalanced:draw_arc(center,radius+10,0,TAU,30,Color("f5a34b"),2,true)
func hexagon(center: Vector2,radius: float) -> PackedVector2Array:
	var poly=PackedVector2Array()
	for i in 7:poly.append(center+Vector2(cos(i*PI/3-PI/2),sin(i*PI/3-PI/2))*radius)
	return poly
func _background() -> StyleBoxFlat:
	var s=StyleBoxFlat.new();s.bg_color=Color("140e0a");s.set_corner_radius_all(8);s.set_border_width_all(2);s.border_color=Color("8a6a35");return s
# due dita (iPad, telefoni): pizzico = zoom, rotazione delle dita = gira la mappa
var _touches={}
func _pinch(event: InputEvent) -> bool:
	if event is InputEventMagnifyGesture:   # trackpad e Safari
		var f=event.factor;zoom=clampf(zoom*f,.8,3.5);queue_redraw();accept_event();return true
	if event is InputEventScreenTouch:
		if event.pressed:_touches[event.index]=event.position
		else:_touches.erase(event.index)
		if _touches.size()>=2:_dragging=true   # niente clic al rilascio dopo un pizzico
		return false
	if event is InputEventScreenDrag and _touches.has(event.index):
		if _touches.size()<2:_touches[event.index]=event.position;return false
		var keys=_touches.keys();var other=keys[1] if keys[0]==event.index else keys[0]
		var a0: Vector2=_touches[event.index];var b: Vector2=_touches[other];var a1: Vector2=event.position
		var d0=a0.distance_to(b);var d1=a1.distance_to(b)
		if d0>8.0 and d1>8.0:
			var f=d1/d0;zoom=clampf(zoom*f,.8,3.5);queue_redraw()
			var da=(a1-b).angle()-(a0-b).angle()
			if absf(da)<.5:rot+=da
		_touches[event.index]=a1;_dragging=true;accept_event();return true
	return false
func _gui_input(event: InputEvent) -> void:
	if game==null:return
	if _pinch(event):return
	if _touches.size()>=2 and (event is InputEventMouseMotion or event is InputEventMouseButton):return   # il mouse emulato dal tocco tace mentre si pizzica
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			zoom=clampf(zoom*(1.12 if event.button_index==MOUSE_BUTTON_WHEEL_UP else .89),.8,3.5);queue_redraw();accept_event()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:_press=event.position;_dragging=false
			elif not _dragging and hovered!="":cell_clicked.emit(hovered)   # clic = rilascio senza trascinamento
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			rot+=event.relative.x*.006                                       # tasto destro: ruota la mappa
		elif event.button_mask & (MOUSE_BUTTON_MASK_LEFT|MOUSE_BUTTON_MASK_MIDDLE):
			if event.position.distance_to(_press)>6 or _dragging or event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
				_dragging=true;pan+=event.relative.rotated(-rot)                 # trascina: sposta la mappa
		var local=view.affine_inverse()*event.position
		var best=100000.0;var cell=""
		for k in game.cells:
			var dist=screen(world(k)).distance_to(local)
			if dist<best:best=dist;cell=k
		hovered=cell if best<110*scale_factor else ""
		tooltip_text=""
		if hovered!="" and not game.state.is_empty():
			var j=game.at(hovered)
			if j!=-1:
				var p=game.state.fighters[j];tooltip_text="%s · %s\n%d ferite rimaste · %d fatica" % [p.name,game.move(p).get("name",""),p.hp,p.fatigue]
		queue_redraw()
