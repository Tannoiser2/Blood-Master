extends Node3D

var pivot: Node3D
var camera: Camera3D
var angle=0.0
var spin=false
var pitch=0.13
var distance=4.5
var dragging=false
var animation_player: AnimationPlayer
var info: Label

func _ready():
	RenderingServer.set_default_clear_color(Color("101c22"))
	var env=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("101c22")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("b7d1df");env.environment.ambient_light_energy=0.65
	env.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC;add_child(env)
	for cfg in [[Vector3(-3,5,4),Color("fff0d0"),2.0],[Vector3(4,3,1),Color("a8dce8"),1.2],[Vector3(1,4,-3),Color("ffcc7a"),1.8]]:
		var light=DirectionalLight3D.new();add_child(light);light.position=cfg[0];light.look_at(Vector3(0,1,0));light.light_color=cfg[1];light.light_energy=cfg[2]
	pivot=Node3D.new();add_child(pivot)
	var model=load("res://assets/models/gascor/gascor-animated.glb").instantiate();pivot.add_child(model)
	animation_player=_find_animation(model)
	var ground=MeshInstance3D.new();ground.name="Pavimento"
	var plane=PlaneMesh.new();plane.size=Vector2(8,8);ground.mesh=plane;ground.position.y=-0.025
	var material=StandardMaterial3D.new();material.albedo_color=Color("14262c");material.roughness=0.9;material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;ground.material_override=material;add_child(ground)
	camera=Camera3D.new();camera.fov=37;add_child(camera)
	var layer=CanvasLayer.new();add_child(layer)
	var title=Label.new();title.text="GASCOR  /  IL PRODE";title.position=Vector2(28,24);title.add_theme_font_size_override("font_size",28);layer.add_child(title)
	info=Label.new();info.text="Prova 3D · trascina per ruotare · rotella per avvicinare";info.position=Vector2(28,65);layer.add_child(info)
	var row=HBoxContainer.new();row.position=Vector2(28,105);row.add_theme_constant_override("separation",10);layer.add_child(row)
	var back=Button.new();back.text="Torna al gioco";back.pressed.connect(func():get_tree().change_scene_to_file("res://scenes/main.tscn"));row.add_child(back)
	var toggle=Button.new();toggle.text="Rotazione automatica";toggle.toggle_mode=true;toggle.button_pressed=false;toggle.toggled.connect(func(on):spin=on);row.add_child(toggle)
	if animation_player:
		for action in animation_player.get_animation_list():
			if action=="RESET":continue
			animation_player.get_animation(action).loop_mode=Animation.LOOP_LINEAR if action in ["Riposo","Camminata"] else Animation.LOOP_NONE
			var b=Button.new();b.text=action;b.pressed.connect(func():animation_player.play(action,0.18));row.add_child(b)
		animation_player.animation_finished.connect(func(_name):animation_player.play("Riposo",0.18))
		if animation_player.has_animation("Riposo"):animation_player.play("Riposo")
	var card=TextureRect.new();card.texture=load("res://assets/modern/gascor/gascor-concept-v1.png");card.position=Vector2(1060,210);card.custom_minimum_size=Vector2(300,450);card.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;card.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;layer.add_child(card)
	var label=Label.new();label.text="Illustrazione di riferimento";label.position=Vector2(1080,675);layer.add_child(label)

func _find_animation(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:return n
	for c in n.get_children():
		var found=_find_animation(c)
		if found:return found
	return null

func _process(delta):
	if spin and not dragging:angle+=delta*0.25
	camera.position=Vector3(sin(angle)*distance,1.15+sin(pitch)*distance,cos(angle)*distance)
	camera.look_at(Vector3(0,1.08,0))

func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT:dragging=event.pressed
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_UP:distance=maxf(2.6,distance-0.25)
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_DOWN:distance=minf(7,distance+0.25)
	if event is InputEventMouseMotion and dragging:
		angle-=event.relative.x*0.008;pitch=clampf(pitch+event.relative.y*0.004,-0.1,0.65)
