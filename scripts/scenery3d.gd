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
	return n

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
