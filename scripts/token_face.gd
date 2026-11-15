class_name TokenFace
extends Control
## Pedina disegnata con i suoi valori veri, nello stile delle originali: attacco in alto a sinistra, difesa in alto
## a destra (parata: "lati blu / altri lati"), sbilanciamento in rosso, pallini neri di fatica, pallino bianco di
## riposo, lati colorati (rosso colpisce, verde si muove, blu para) con il fronte in alto.
## Serve per gli eroi della forgia e per le varianti dei personaggi: i loro valori non sono quelli stampati sulle
## pedine a cui somigliano, e le pedine in più (doppio colpo, finta, contrattacco...) non hanno un disegno.

signal pressed
const COL={"red":Color("d8392b"),"green":Color("2f9e4f"),"blue":Color("2f74c8")}
const PAPER=Color("f2ead6")
const INK=Color("2a1a0e")
var m: Dictionary
var font: Font
var font_name: Font
var dim:=false
var clickable:=false

func _init(move: Dictionary,width: float,numbers: Font,names: Font) -> void:
	m=move;font=numbers;font_name=names
	custom_minimum_size=Vector2(width,width*.8625);size=custom_minimum_size
func _corner(k: int,shrink:=0.0) -> Vector2:
	var r=minf(size.x*.5,size.y/1.732)-shrink
	var a=deg_to_rad(60.0*k);return size*.5+Vector2(cos(a),sin(a))*r
func _gui_input(ev: InputEvent) -> void:
	if clickable and ev is InputEventMouseButton and ev.pressed and ev.button_index==MOUSE_BUTTON_LEFT:pressed.emit()
func _draw() -> void:
	var r=minf(size.x*.5,size.y/1.732)
	var pts=PackedVector2Array()
	for k in 6:pts.append(_corner(k,1.0))
	draw_colored_polygon(pts,PAPER.darkened(.35) if dim else PAPER)
	var ring=PackedVector2Array()
	for k in 7:ring.append(_corner(k%6,1.0))
	draw_polyline(ring,Color(.25,.18,.1),maxf(1.0,r*.03),true)
	# lati colorati: il lato s sta fra i vertici (4+s) e (5+s); più colori = strisce una dentro l'altra
	var th=maxf(3.0,r*.13)
	for s in 6:
		var n=0
		for c in ["red","green","blue"]:
			if s in m.get(c,[]):
				draw_line(_corner((4+s)%6,th*(.5+n)),_corner((5+s)%6,th*(.5+n)),COL[c],th,true);n+=1
	if font==null:return
	var fs=int(r*.32);var small=int(r*.2);var c=size*.5
	var blue: bool=not m.get("blue",[]).is_empty()
	var atk="/" if m.get("attack")==null else str(int(m.attack))
	var dfs=("%d/%d"%[int(m.defense),int(m.secondary)]) if blue else str(int(m.defense))
	var top=c.y-r*.3
	draw_string(font,Vector2(c.x-r*.5,top),atk,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,INK)
	var dw=font.get_string_size(dfs,HORIZONTAL_ALIGNMENT_LEFT,-1,fs if not blue else int(fs*.8)).x
	draw_string(font,Vector2(c.x+r*.5-dw,top),dfs,HORIZONTAL_ALIGNMENT_LEFT,-1,fs if not blue else int(fs*.8),INK)
	if m.get("imbalance")!=null:
		draw_string(font,Vector2(c.x-r*.7,c.y+r*.04),"+%d"%int(m.imbalance),HORIZONTAL_ALIGNMENT_LEFT,-1,int(fs*.72),COL.red)
	if int(m.get("riposte",0))>0:
		var t="poi %d"%int(m.riposte);var w=font.get_string_size(t,HORIZONTAL_ALIGNMENT_LEFT,-1,int(fs*.62)).x
		draw_string(font,Vector2(c.x+r*.72-w,c.y+r*.04),t,HORIZONTAL_ALIGNMENT_LEFT,-1,int(fs*.62),COL.red)
	if m.get("spell",false):
		var t="magia %d · costo %d"%[int(m.get("value",0)),int(m.get("cost",0))]
		var w=font.get_string_size(t,HORIZONTAL_ALIGNMENT_LEFT,-1,small).x
		draw_string(font,Vector2(c.x-w*.5,c.y+r*.24),t,HORIZONTAL_ALIGNMENT_LEFT,-1,small,COL.blue.darkened(.2))
	# segni particolari, a parole: colpisce due volte, tutti i nemici, non parabile
	var tags=[]
	if m.get("double",false):tags.append("due colpi")
	if m.get("multi",false):tags.append("tutti")
	if m.get("feint",false):tags.append("non si para")
	if not tags.is_empty():
		var t=" · ".join(tags);var w=font.get_string_size(t,HORIZONTAL_ALIGNMENT_LEFT,-1,small).x
		draw_string(font,Vector2(c.x-w*.5,c.y+r*.24),t,HORIZONTAL_ALIGNMENT_LEFT,-1,small,INK.lightened(.25))
	# nome in basso, rimpicciolito finché non sta nell'esagono
	var nm=str(m.get("name",""));var nf=font_name if font_name!=null else font;var ns=int(r*.24)
	while ns>7 and nf.get_string_size(nm,HORIZONTAL_ALIGNMENT_LEFT,-1,ns).x>r*1.25:ns-=1
	var nw=nf.get_string_size(nm,HORIZONTAL_ALIGNMENT_LEFT,-1,ns).x
	draw_string(nf,Vector2(c.x-nw*.5,c.y+r*.56),nm,HORIZONTAL_ALIGNMENT_LEFT,-1,ns,INK)
	# pallini: neri di fatica, bianco di riposo (disegnati, non caratteri)
	var dot=maxf(2.5,r*.075);var x=c.x+r*.6;var y=c.y+r*.04-r*.0
	for k in int(m.get("fatigue",0)):draw_circle(Vector2(x-k*dot*2.6,y),dot,INK)
	if bool(m.get("rest",false)):
		draw_circle(Vector2(x,y),dot,Color.WHITE);draw_arc(Vector2(x,y),dot,0,TAU,20,INK,maxf(1.0,r*.02),true)
