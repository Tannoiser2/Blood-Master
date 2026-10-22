class_name Scenery3D
extends RefCounted
# Elementi di scena dell'arena (regola modificata) costruiti al volo, senza file esterni:
# colonne scanalate, massi, alberi, pozze d'acqua e macerie, con texture procedurali.

static func build(kind: String,seed_n: int) -> Node3D:
	var n=Node3D.new()
	match kind:
		"column":_column(n,seed_n)
		"boulder":_boulder(n,seed_n)
		"tree":_tree(n,seed_n)
		"water":_water(n,seed_n)
		"rubble":_rubble(n,seed_n)
		"potion":_potion(n,seed_n)
		"mana":_mana(n,seed_n)
	return n

# --- zone di ristoro (regola modificata) --------------------------------------------------------
static func _glow_shader(col: Color,alpha: float,ring: bool) -> ShaderMaterial:
	var sh=Shader.new();sh.code="""
shader_type spatial;
render_mode blend_add,unshaded,cull_disabled,depth_draw_never;
uniform vec4 col;
uniform float alpha;
uniform bool ring;
void fragment(){
	float pulse=.65+.35*sin(TIME*2.6);
	float a=alpha*pulse;
	if(ring){
		float r=length(UV-vec2(.5))*2.0;
		float waves=.5+.5*sin(r*18.0-TIME*4.0);
		a*=clamp(1.15-r,0.0,1.0)*(.45+.55*waves);
	}
	ALBEDO=col.rgb;ALPHA=clamp(a,0.0,1.0);
}"""
	var m=ShaderMaterial.new();m.shader=sh;m.set_shader_parameter("col",col);m.set_shader_parameter("alpha",alpha);m.set_shader_parameter("ring",ring)
	return m
static func _sparks(n: Node3D,col: Color,amount: int,spread: float,height: float) -> void:
	var p=CPUParticles3D.new();p.amount=amount;p.lifetime=1.6;p.emission_shape=CPUParticles3D.EMISSION_SHAPE_SPHERE;p.emission_sphere_radius=spread
	p.direction=Vector3.UP;p.spread=12;p.initial_velocity_min=height*.25;p.initial_velocity_max=height*.55;p.gravity=Vector3.ZERO;p.scale_amount_min=.5;p.scale_amount_max=1.2
	var q=QuadMesh.new();q.size=Vector2(.03,.03);var m=StandardMaterial3D.new();m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;m.albedo_color=col;m.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;m.blend_mode=BaseMaterial3D.BLEND_MODE_ADD;q.material=m;p.mesh=q
	var g=Gradient.new();g.set_color(0,Color(col,1));g.set_color(1,Color(col,0));p.color_ramp=g
	p.position.y=.08;n.add_child(p)
static func _potion(n: Node3D,seed_n: int) -> void:
	# boccetta di vetro col liquido rosso che brilla, su un cuscinetto di sassi
	var stone=_mat(Color(.5,.45,.4),Color(.33,.3,.27),.1,seed_n,.9)
	for k in 5:
		var a=k*TAU/5.0;_mesh(n,_rock(.05,seed_n+k,.6,.5),stone,Vector3(cos(a)*.13,0,sin(a)*.13))
	var bottle=Node3D.new();bottle.name="Bottiglia";bottle.position.y=.03;bottle.scale=Vector3.ONE*2.0;n.add_child(bottle)
	var liquid=StandardMaterial3D.new();liquid.albedo_color=Color(.85,.08,.12);liquid.emission_enabled=true;liquid.emission=Color(1,.15,.2);liquid.emission_energy_multiplier=3.5
	var body=SphereMesh.new();body.radius=.075;body.height=.15;_mesh(bottle,body,liquid,Vector3(0,.09,0))
	var glass=StandardMaterial3D.new();glass.albedo_color=Color(.8,.9,1,.28);glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;glass.roughness=.05;glass.metallic=.2
	var shell=SphereMesh.new();shell.radius=.085;shell.height=.17;_mesh(bottle,shell,glass,Vector3(0,.09,0))
	var neck=CylinderMesh.new();neck.top_radius=.022;neck.bottom_radius=.03;neck.height=.08;_mesh(bottle,neck,glass,Vector3(0,.2,0))
	var cork=CylinderMesh.new();cork.top_radius=.026;cork.bottom_radius=.022;cork.height=.035
	var cm=StandardMaterial3D.new();cm.albedo_color=Color(.55,.38,.22);cm.roughness=.9;_mesh(bottle,cork,cm,Vector3(0,.25,0))
	var halo=QuadMesh.new();halo.size=Vector2(.9,.9);var hm=_glow_shader(Color(1,.2,.25),.9,true)
	_mesh(n,halo,hm,Vector3(0,.012,0),Vector3(-PI/2,0,0))
	var l=OmniLight3D.new();l.light_color=Color(1,.3,.3);l.light_energy=2.2;l.omni_range=1.2;l.position.y=.35;n.add_child(l)
	_sparks(n,Color(1,.45,.45),16,.12,.6)
static func _mana(n: Node3D,seed_n: int) -> void:
	# esagono di mana: lastra di luce azzurra che pulsa, cristalli e scintille che salgono
	var plate=CylinderMesh.new();plate.top_radius=.48;plate.bottom_radius=.48;plate.height=.005;plate.radial_segments=6
	_mesh(n,plate,_glow_shader(Color(.2,.65,1),1.0,true),Vector3(0,.015,0),Vector3(0,PI/6,0))
	var beam=CylinderMesh.new();beam.top_radius=.3;beam.bottom_radius=.42;beam.height=.9;beam.radial_segments=6;beam.cap_top=false;beam.cap_bottom=false
	var bm=_glow_shader(Color(.3,.7,1),.22,false);_mesh(n,beam,bm,Vector3(0,.45,0),Vector3(0,PI/6,0))   # colonna di luce
	var rim=TorusMesh.new();rim.inner_radius=.44;rim.outer_radius=.47;rim.rings=6;rim.ring_segments=4
	var rm=StandardMaterial3D.new();rm.albedo_color=Color(.3,.75,1);rm.emission_enabled=true;rm.emission=Color(.35,.8,1);rm.emission_energy_multiplier=2.5
	_mesh(n,rim,rm,Vector3(0,.02,0),Vector3(0,PI/6,0))
	var cm=StandardMaterial3D.new();cm.albedo_color=Color(.55,.85,1,.75);cm.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;cm.emission_enabled=true;cm.emission=Color(.3,.7,1);cm.emission_energy_multiplier=1.6;cm.roughness=.1
	for k in 3:   # cristalli
		var c=CylinderMesh.new();c.top_radius=0;c.bottom_radius=.05;c.height=.26+.07*k;c.radial_segments=6
		var a=k*TAU/3.0+float(seed_n%7)
		_mesh(n,c,cm,Vector3(cos(a)*.3,c.height*.5,sin(a)*.3),Vector3(.15*cos(a),0,.15*sin(a)))
	var l=OmniLight3D.new();l.light_color=Color(.4,.75,1);l.light_energy=1.4;l.omni_range=1.1;l.position.y=.25;n.add_child(l)
	_sparks(n,Color(.5,.85,1),18,.35,.6)

static func _noise_tex(c1: Color,c2: Color,freq: float,seed_n: int,normal:=false) -> NoiseTexture2D:
	var t=NoiseTexture2D.new();var f=FastNoiseLite.new();f.seed=seed_n;f.frequency=freq;f.fractal_octaves=4;t.noise=f;t.seamless=true;t.width=256;t.height=256
	if normal:t.as_normal_map=true;t.bump_strength=6.0
	else:
		var g=Gradient.new();g.set_color(0,c1);g.set_color(1,c2);t.color_ramp=g
	return t
static func _mat(c1: Color,c2: Color,freq: float,seed_n: int,rough:=.85,scale:=1.0) -> StandardMaterial3D:
	# colore di base (la media dei due) moltiplicato per una macchiatura chiara/scura di rumore
	var m=StandardMaterial3D.new();var c=c1.lerp(c2,.5);m.albedo_color=Color(c.r*.58,c.g*.58,c.b*.58);   # l'arena è molto illuminata: tinte più scure
	m.albedo_texture=_noise_tex(Color(1.15,1.15,1.15),Color(.7,.7,.7),freq,seed_n);m.roughness=rough
	m.normal_enabled=true;m.normal_texture=_noise_tex(c1,c2,freq*2.0,seed_n+7,true);m.normal_scale=.6
	m.uv1_triplanar=true;m.uv1_scale=Vector3.ONE*scale
	return m
static func _rock(radius: float,seed_n: int,squash: float,rough:=.35,smooth:=false) -> ArrayMesh:
	# sfera deformata col rumore: un sasso irregolare con la base piatta
	var sm=SphereMesh.new();sm.radius=radius;sm.height=radius*2;sm.radial_segments=20;sm.rings=12
	var arr=sm.get_mesh_arrays();var verts: PackedVector3Array=arr[Mesh.ARRAY_VERTEX];var idx: PackedInt32Array=arr[Mesh.ARRAY_INDEX]
	var nz=FastNoiseLite.new();nz.seed=seed_n;nz.frequency=1.6
	var out=PackedVector3Array()
	for v in verts:
		var d=v.normalized();var f=1.0+nz.get_noise_3dv(d*2.0)*rough
		var w=d*radius*f;w.y*=squash
		if w.y<-radius*.15:w.y=-radius*.15
		out.append(w+Vector3(0,radius*.15,0))
	var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if smooth:
		for v in out:st.add_vertex(v)
		for i in idx:st.add_index(i)
	else:
		for i in idx:st.add_vertex(out[i])
	st.generate_normals();return st.commit()
static func _mesh(parent: Node3D,mesh: Mesh,mat: Material,pos:=Vector3.ZERO,rot:=Vector3.ZERO,scl:=Vector3.ONE) -> MeshInstance3D:
	var mi=MeshInstance3D.new();mi.mesh=mesh;mi.material_override=mat;mi.position=pos;mi.rotation=rot;mi.scale=scl;parent.add_child(mi);return mi

static func _column(n: Node3D,seed_n: int) -> void:
	# colonna di marmo scanalata su un basamento; a volte spezzata, col capitello caduto accanto
	var marble=_mat(Color(.86,.83,.76),Color(.68,.64,.57),.035,seed_n,.7,1.5)
	var broken=seed_n%3==0
	var h=.95 if broken else 1.75
	var base=BoxMesh.new();base.size=Vector3(.62,.14,.62);_mesh(n,base,marble,Vector3(0,.07,0))
	var plinth=CylinderMesh.new();plinth.top_radius=.25;plinth.bottom_radius=.29;plinth.height=.1;plinth.radial_segments=24;_mesh(n,plinth,marble,Vector3(0,.19,0))
	var shaft=CylinderMesh.new();shaft.top_radius=.19;shaft.bottom_radius=.215;shaft.height=h;shaft.radial_segments=20;shaft.rings=4
	var arr=shaft.get_mesh_arrays();var verts: PackedVector3Array=arr[Mesh.ARRAY_VERTEX]
	for k in verts.size():   # scanalature: solchi verticali lungo il fusto
		var v=verts[k];var a=atan2(v.z,v.x);var r=Vector2(v.x,v.z).length()
		if r>.05:var rr=r*(1.0-.06*maxf(0.0,cos(a*10.0)));verts[k]=Vector3(cos(a)*rr,v.y,sin(a)*rr)
	arr[Mesh.ARRAY_VERTEX]=verts;var am=ArrayMesh.new();am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arr)
	_mesh(n,am,marble,Vector3(0,.24+h*.5,0))
	if broken:   # moncone frastagliato in cima e capitello a terra
		_mesh(n,_rock(.2,seed_n,.6,.5),marble,Vector3(0,.24+h-.02,0))
		var cap=BoxMesh.new();cap.size=Vector3(.48,.16,.48);_mesh(n,cap,marble,Vector3(.32,.1,.22),Vector3(.25,.6,.4))
	else:
		var echinus=CylinderMesh.new();echinus.top_radius=.27;echinus.bottom_radius=.19;echinus.height=.1;echinus.radial_segments=24;_mesh(n,echinus,marble,Vector3(0,.24+h+.05,0))
		var abacus=BoxMesh.new();abacus.size=Vector3(.6,.1,.6);_mesh(n,abacus,marble,Vector3(0,.24+h+.15,0))

static func _boulder(n: Node3D,seed_n: int) -> void:
	var stone=_mat(Color(.52,.49,.45),Color(.32,.3,.28),.06,seed_n,.9,2.0)
	_mesh(n,_rock(.42,seed_n,.85,.4),stone,Vector3(0,0,0),Vector3(0,seed_n*.7,0))
	_mesh(n,_rock(.18,seed_n+3,.8,.45),stone,Vector3(.38,0,.2))
	_mesh(n,_rock(.12,seed_n+5,.7,.5),stone,Vector3(-.3,0,.32))
	var moss=_mat(Color(.33,.42,.2),Color(.22,.3,.14),.1,seed_n+9,.95)
	_mesh(n,_rock(.3,seed_n+11,.25,.3),moss,Vector3(-.05,.36,0),Vector3.ZERO,Vector3(1,1,1))   # muschio in cima

static func _tree(n: Node3D,seed_n: int) -> void:
	# un ulivo/pino nodoso: tronco storto e chioma a ciuffi
	var bark=_mat(Color(.36,.26,.18),Color(.2,.14,.1),.12,seed_n,.95,3.0)
	var leaves=_mat(Color(.24,.42,.2),Color(.12,.26,.12),.09,seed_n+1,.9,2.0)
	var trunk=CylinderMesh.new();trunk.top_radius=.06;trunk.bottom_radius=.13;trunk.height=1.2;trunk.radial_segments=10
	_mesh(n,trunk,bark,Vector3(0,.6,0),Vector3(.08,0,.06))
	var branch=CylinderMesh.new();branch.top_radius=.03;branch.bottom_radius=.06;branch.height=.55;branch.radial_segments=8
	_mesh(n,branch,bark,Vector3(.15,1.05,0),Vector3(0,0,-.8))
	var rng=RandomNumberGenerator.new();rng.seed=seed_n
	for k in 5:
		var a=k*TAU/5.0+rng.randf()*.5;var r=.18+rng.randf()*.15
		_mesh(n,_rock(.32+rng.randf()*.1,seed_n+20+k,.75,.35,true),leaves,Vector3(cos(a)*r,1.25+rng.randf()*.3,sin(a)*r))
	_mesh(n,_rock(.36,seed_n+30,.8,.3,true),leaves,Vector3(0,1.55,0))
	var root=_mat(Color(.3,.24,.16),Color(.2,.16,.1),.2,seed_n+4,.95)
	_mesh(n,_rock(.22,seed_n+40,.25,.4),root,Vector3(0,0,0))

static func _water(n: Node3D,seed_n: int) -> void:
	# pozza: acqua che ondeggia dentro un bordo di sassi
	var sh=Shader.new();sh.code="""
shader_type spatial;
render_mode blend_mix,cull_back;
uniform vec3 deep=vec3(.05,.22,.35);
uniform vec3 shallow=vec3(.2,.5,.6);
void vertex(){ VERTEX.y+=sin(TIME*1.6+VERTEX.x*9.0)*.006+cos(TIME*1.3+VERTEX.z*8.0)*.006; }
void fragment(){
	vec2 p=UV*8.0;
	float w=sin(p.x*3.0+TIME*1.7)*.5+sin(p.y*2.6-TIME*1.3)*.5;
	NORMAL_MAP=normalize(vec3(.5+.12*cos(p.x*3.0+TIME*1.7),.5+.12*cos(p.y*2.6-TIME*1.3),1.0));
	float r=length(UV-vec2(.5))*2.0;
	ALBEDO=mix(deep,shallow,clamp(r*r+.15*w,0.0,1.0));
	ROUGHNESS=.08;SPECULAR=.7;METALLIC=.1;ALPHA=.88;
}"""
	var wm=ShaderMaterial.new();wm.shader=sh
	var pool=CylinderMesh.new();pool.top_radius=.5;pool.bottom_radius=.5;pool.height=.03;pool.radial_segments=6
	_mesh(n,pool,wm,Vector3(0,.05,0),Vector3(0,PI/6,0))
	var stone=_mat(Color(.55,.5,.44),Color(.36,.33,.3),.08,seed_n,.9)
	for k in 12:
		var a=k*TAU/12.0;_mesh(n,_rock(.07+.02*((k*7+seed_n)%3),seed_n+k,.7,.45),stone,Vector3(cos(a)*.5,0,sin(a)*.5))
	var reed=_mat(Color(.35,.45,.2),Color(.25,.35,.15),.2,seed_n+2,.9)
	for k in 4:   # qualche canna
		var c=CylinderMesh.new();c.top_radius=.004;c.bottom_radius=.012;c.height=.35+.1*(k%2);c.radial_segments=5
		_mesh(n,c,reed,Vector3(-.35+k*.05,.18,.28-k*.04),Vector3(.15*(k-1.5),0,.1))

static func _rubble(n: Node3D,seed_n: int) -> void:
	# macerie: sassi e un tronco di colonna rovesciato, terreno impraticabile
	var stone=_mat(Color(.6,.56,.5),Color(.38,.35,.31),.06,seed_n,.9)
	var marble=_mat(Color(.85,.82,.75),Color(.66,.62,.56),.035,seed_n+1,.7)
	var rng=RandomNumberGenerator.new();rng.seed=seed_n
	for k in 9:
		var a=rng.randf()*TAU;var r=rng.randf()*.4
		_mesh(n,_rock(.07+rng.randf()*.11,seed_n+k,.6,.5),stone,Vector3(cos(a)*r,0,sin(a)*r))
	var drum=CylinderMesh.new();drum.top_radius=.18;drum.bottom_radius=.18;drum.height=.55;drum.radial_segments=16
	_mesh(n,drum,marble,Vector3(.05,.18,-.05),Vector3(0,rng.randf()*PI,PI/2))
