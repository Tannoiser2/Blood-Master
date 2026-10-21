"""Assembla un arciere (Kylvia, Zak) con animazioni proprie dal catalogo Meshy.

Uso:  python tools/archers/assemble.py <id>      (modulo bpy)   id: kylvia | zak

Ingressi (source_art/<id>/meshy): <id>_rigged.glb e anim_*.glb generate sul rig
dell'arciere stesso (niente mosse prese da altri personaggi); spada corta in
source_art/archers/sword.glb. L'arco, la sua copia a tracolla e la freccia incoccata
sono modellati qui. In Godot board3d.gd mostra arco o spada secondo la modalità.
"""
import bpy, sys, math
import numpy as np
from mathutils import Vector, Matrix
from pathlib import Path

root = Path(__file__).resolve().parents[2]
CID = sys.argv[-1]
CFG = {'kylvia': dict(name='Kylvia', bow=1.10), 'zak': dict(name='Zak', bow=1.18)}[CID]
SRC = root / f'source_art/{CID}/meshy'
OUT = root / f'assets/models/{CID}'
OUT.mkdir(parents=True, exist_ok=True)
CLIPS = [('Riposo', 'riposo'), ('Camminata', 'walking'), ('Correre', 'running'), ('In guardia', 'guardia'),
         ('Avanzare', 'avanzare'), ('Carica', 'carica'), ('Affondo', 'affondo'), ('Taglio Dx', 'taglio_dx'),
         ('Taglio Sx', 'taglio_sx'), ('Parata Dx', 'parata_dx'), ('Parata Sx', 'parata_sx'), ('Schivata', 'schivata'),
         ('Rotolare', 'rotolare'), ('Calcio', 'calcio'), ('A terra', 'a_terra'), ('Morte', 'morte'), ('Rialzarsi', 'rialzarsi'),
         ('Sbilanciato', 'sbilanciato'), ('Incoccare', 'incoccare'), ('Tirare', 'tirare'),
         ('In guardia arco', 'guardia_arco'), ('Avanzare arco', 'avanzare_arco'), ('Correre arco', 'correre_arco'),
         ('Sbilanciato arco', 'sbilanciato_arco')]


def imported(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    return [o for o in bpy.data.objects if o not in before]


def set_action(o, a):
    o.animation_data.action = a
    try:
        o.animation_data.action_slot = a.slots[0]
    except Exception:
        pass


def rest(o):
    if o.animation_data:
        o.animation_data.action = None
    for p in o.pose.bones:
        p.matrix_basis = Matrix()
    bpy.context.view_layer.update()


bpy.ops.wm.read_factory_settings(use_empty=True)
objs = imported(SRC / f'{CID}_rigged.glb')
arm = next(o for o in objs if o.type == 'ARMATURE')
body = next(o for o in objs if o.type == 'MESH' and o.find_armature() == arm)
for o in objs:
    if o.type == 'MESH' and o is not body:
        bpy.data.objects.remove(o)
arm.name = CFG['name'] + '_Rig'; body.name = CFG['name']
if arm.animation_data and arm.animation_data.action:
    bpy.data.actions.remove(arm.animation_data.action)
arm.animation_data_create()

# --- clip: ognuna generata sul rig dell'arciere ----------------------------------
for name, fname in CLIPS:
    f = SRC / f'anim_{fname}.glb'
    if not f.exists():
        print('MANCA', fname, flush=True); continue
    o2 = imported(f)
    src = next(o for o in o2 if o.type == 'ARMATURE')
    act = src.animation_data.action; act.name = name; act.use_fake_user = True
    for o in o2:
        bpy.data.objects.remove(o)
    print('CLIP', name, flush=True)
for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.armatures):
    for d in list(block):
        if d.users == 0:
            block.remove(d)
rest(arm)
AW = arm.matrix_world


def bone_world(o, n):
    return o.matrix_world @ o.pose.bones[n].matrix


def hw(n):
    return AW @ arm.pose.bones[n].head


def pca(o):
    co = np.array([v.co[:] for v in o.data.vertices]); c = co.mean(0)
    return co, c, np.linalg.svd(co - c, full_matrices=False)[2]


# --- spada corta nella mano destra, come la spada di Anteos ------------------------
with bpy.data.libraries.load(str(root / 'source_art/anteos/anteos.blend'), link=False) as (sd, dd):
    dd.objects = [n for n in sd.objects if n in ('Anteos_Rig', 'Spada')]
for o in dd.objects:
    bpy.context.scene.collection.objects.link(o)
a_rig = bpy.data.objects['Anteos_Rig']; a_sword = bpy.data.objects['Spada']
rest(a_rig)
REL = bone_world(a_rig, 'RightHand').inverted() @ a_sword.matrix_world
co, c, ax = pca(a_sword)
tip = max((Vector(p) for p in co), key=lambda v: v.length)
bA = tip.normalized(); sA = Vector(ax[1]); sA = (sA - bA * sA.dot(bA)).normalized()
BA = Matrix((bA, sA, bA.cross(sA))).transposed()
sw = next(x for x in imported(root / 'source_art/archers/sword.glb') if x.type == 'MESH')
sw.data.transform(sw.matrix_world); sw.matrix_world = Matrix()
mod = sw.modifiers.new('r', 'DECIMATE'); mod.ratio = min(1, 5000 / len(sw.data.polygons))
bpy.context.view_layer.objects.active = sw; bpy.ops.object.modifier_apply(modifier=mod.name)
co, c, ax = pca(sw); u = ax[0]; t = (co - c) @ u
radial = np.linalg.norm((co - c) - np.outer(t, u), axis=1); L0 = t.max() - t.min()
edges = np.linspace(t.min(), t.max() - L0 * .04, 50)
prof = [radial[(t > a) & (t < a + L0 * .04)].max(initial=0) for a in edges]
guard = edges[int(np.argmax(prof))] + L0 * .02
if t.max() - guard < guard - t.min():
    u = -u; t = -t; guard = -guard
s = .72 / L0; grip_c = guard - (guard - t.min()) * .45
for v, p in zip(sw.data.vertices, co):
    v.co = (Vector(p) - Vector(c) - Vector(u) * grip_c) * s
bG = Vector(u); sG = Vector(ax[1]); sG = (sG - bG * sG.dot(bG)).normalized()
BG = Matrix((bG, sG, bG.cross(sG))).transposed()
rot = REL.to_3x3().normalized() @ BA @ BG.transposed()
sw.parent = arm; sw.parent_type = 'BONE'; sw.parent_bone = 'RightHand'; bpy.context.view_layer.update()
sw.matrix_world = bone_world(arm, 'RightHand') @ Matrix.Translation(REL.translation) @ rot.to_4x4() @ Matrix.Scale(REL.to_scale()[0], 4)
for o in (a_rig, a_sword):
    bpy.data.objects.remove(o)
sw.name = 'Spada'


# --- arco: flettenti curvi e corda; X = verso il bersaglio, Y = asse dei flettenti ---
def mat(name, col, metal=0.0, rough=.6):
    m = bpy.data.materials.new(name); m.use_nodes = True; b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*col, 1); b.inputs['Metallic'].default_value = metal
    b.inputs['Roughness'].default_value = rough; return m


WOOD = mat('Legno arco', (.28, .15, .07)); STRING = mat('Corda', (.85, .82, .72)); STEEL = mat('Punta', (.75, .76, .78), 1, .3)
FEATHER = mat('Penne', (.9, .88, .8))
H = CFG['bow'] / 2


def limb_x(y):
    a = abs(y) / H
    return -.13 * a * a + (.22 * (a - .78) ** 2 if a > .78 else 0)    # i flettenti piegano verso l'arciere, le punte all'infuori


def tube(points, radius, material, name):
    cu = bpy.data.curves.new(name, 'CURVE'); cu.dimensions = '3D'; cu.bevel_depth = radius; cu.bevel_resolution = 2
    sp = cu.splines.new('POLY'); sp.points.add(len(points) - 1)
    for p, q in zip(sp.points, points):
        p.co = (*q, 1)
    o = bpy.data.objects.new(name, cu); bpy.context.scene.collection.objects.link(o); cu.materials.append(material)
    bpy.context.view_layer.objects.active = o; o.select_set(True); bpy.ops.object.convert(target='MESH'); o.select_set(False)
    return o


def make_bow(name):
    ys = np.linspace(-H, H, 41)
    limb = tube([(limb_x(y), y, 0) for y in ys], .014, WOOD, name)
    grip = tube([(.0, -.07, 0), (.0, .07, 0)], .02, WOOD, name + '_presa')
    tipx = limb_x(H)
    string = tube([(tipx - .01, -H + .01, 0), (tipx - .01, H - .01, 0)], .0025, STRING, name + '_corda')
    bpy.ops.object.select_all(action='DESELECT')
    for o in (grip, string):
        o.select_set(True)
    limb.select_set(True); bpy.context.view_layer.objects.active = limb; bpy.ops.object.join(); limb.select_set(False)
    limb.name = name; return limb


def make_arrow(name):
    shaft = tube([(-.62, 0, 0), (.08, 0, 0)], .0045, WOOD, name)
    bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=.011, depth=.05, location=(.105, 0, 0), rotation=(0, math.pi / 2, 0))
    tipo = bpy.context.object; tipo.data.materials.append(STEEL)
    parts = [tipo]
    for k in range(3):
        bpy.ops.mesh.primitive_plane_add(size=1, location=(-.56, 0, 0)); f = bpy.context.object
        f.scale = (.06, .015, 1); f.rotation_euler = (k * 2 * math.pi / 3, 0, 0); f.data.materials.append(FEATHER)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        f.location = (-.56, math.cos(k * 2 * math.pi / 3) * .012, math.sin(k * 2 * math.pi / 3) * .012); parts.append(f)
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts + [shaft]:
        o.select_set(True)
    bpy.context.view_layer.objects.active = shaft; bpy.ops.object.join(); shaft.name = name
    bpy.ops.object.select_all(action='DESELECT'); return shaft


bow = make_bow('Arco')
nock = make_arrow('FrecciaIncoccata')

# mano che regge l'arco: nella clip di tiro è il braccio teso (la mano più lontana dal petto)
tir = bpy.data.actions.get('Tirare')
set_action(arm, tir)
f0, f1 = tir.frame_range
f_aim = int(f0 + (f1 - f0) * .45)
score = {'LeftHand': 0.0, 'RightHand': 0.0}
for k in range(9):
    bpy.context.scene.frame_set(int(f0 + (f1 - f0) * (.3 + .05 * k)))
    ch = (hw('LeftArm') + hw('RightArm')) / 2
    for hn in score:
        score[hn] += (hw(hn) - ch).length
HAND = max(score, key=score.get); DRAW = 'LeftHand' if HAND == 'RightHand' else 'RightHand'
print('PUNTEGGI', {k: round(v, 2) for k, v in score.items()}, flush=True)
print('MANO ARCO', HAND, flush=True)
up = Vector((0, 0, 1))


def aim_dir():
    d = hw(HAND) - hw(DRAW); d.z = 0; return d.normalized()


# le clip di Meshy mirano di lato: le ruoto sul posto perché il tiro parta in avanti (-Y in Blender)
bpy.context.scene.frame_set(f_aim)
d = aim_dir(); ang = math.atan2(d.x, -d.y)          # angolo da d a (0,-1)
print('ROTAZIONE MIRA', round(math.degrees(ang), 1), flush=True)
root_b = next(b for b in arm.pose.bones if b.parent is None)
ax_arm = (arm.matrix_world.inverted().to_3x3() @ up).normalized()
Rarm = Matrix.Rotation(-ang, 4, ax_arm)
for an in ('Incoccare', 'Tirare', 'In guardia arco'):
    act = bpy.data.actions.get(an)
    if not act:
        continue
    set_action(arm, act); a0, a1 = int(act.frame_range[0]), int(act.frame_range[1])
    mats = []
    for f in range(a0, a1 + 1):
        bpy.context.scene.frame_set(f); mats.append(Rarm @ root_b.matrix.copy())
    for f, m in zip(range(a0, a1 + 1), mats):
        bpy.context.scene.frame_set(f); root_b.matrix = m; bpy.context.view_layer.update()
        root_b.keyframe_insert('location', frame=f); root_b.keyframe_insert(
            'rotation_quaternion' if root_b.rotation_mode == 'QUATERNION' else 'rotation_euler', frame=f)
set_action(arm, tir); bpy.context.scene.frame_set(f_aim)
xdir = aim_dir()
print('MIRA DOPO', tuple(round(v, 2) for v in xdir), flush=True)
Hw = bone_world(arm, HAND)
fa = (hw(HAND) - hw(HAND.replace('Hand', 'ForeArm'))).normalized()
grip_w = hw(HAND) + fa * .07 * 1.0
Rw = Matrix((xdir, up, xdir.cross(up))).transposed().to_4x4()
REL_BOW = Hw.inverted() @ (Matrix.Translation(grip_w) @ Rw)
# freccia incoccata: la cocca segue le dita della mano che tende, la punta passa sull'impugnatura
Dw = bone_world(arm, DRAW)
fd = (hw(DRAW) - hw(DRAW.replace('Hand', 'ForeArm'))).normalized()
nock_w = hw(DRAW) + fd * .05
dirw = (grip_w + up * .02 - nock_w).normalized()
side = dirw.cross(up).normalized(); upa = side.cross(dirw)
REL_N = Dw.inverted() @ Matrix.Translation(nock_w) @ Matrix((dirw, upa, side)).transposed().to_4x4() @ Matrix.Translation((.62, 0, 0))
prof = []
for f in range(int(f0), int(f1) + 1):
    bpy.context.scene.frame_set(f); prof.append((hw(HAND) - hw(DRAW)).length)
print('PROFILO MANI', [round(x, 2) for x in prof[::2]], flush=True)
rest(arm)
nock.parent = arm; nock.parent_type = 'BONE'; nock.parent_bone = DRAW; bpy.context.view_layer.update()
nock.matrix_world = bone_world(arm, DRAW) @ REL_N
bow.parent = arm; bow.parent_type = 'BONE'; bow.parent_bone = HAND; bpy.context.view_layer.update()
bow.matrix_world = bone_world(arm, HAND) @ REL_BOW

# copia a tracolla sulla schiena (visibile quando in mano c'è la spada)
back = make_bow('ArcoSchiena')
sp = 'Spine02' if 'Spine02' in arm.pose.bones else 'Spine'
left = (hw('LeftUpLeg') - hw('RightUpLeg')); left.z = 0; left.normalize(); fwd = left.cross(up)
pos = hw(sp) - fwd * .17 + up * .08
diag = (up * math.cos(math.radians(35)) + left * math.sin(math.radians(35))).normalized()
xb = -fwd; zb = xb.cross(diag)
back.parent = arm; back.parent_type = 'BONE'; back.parent_bone = sp; bpy.context.view_layer.update()
back.matrix_world = Matrix.Translation(pos) @ Matrix((xb, diag, zb)).transposed().to_4x4()

for img in bpy.data.images:
    used_by_body = any(img in [nd.image for nd in m.node_tree.nodes if nd.type == 'TEX_IMAGE']
                       for m in body.data.materials if m and m.use_nodes)
    lim = 2048 if used_by_body else 1024
    if img.size[0] > lim:
        img.scale(lim, lim * img.size[1] // img.size[0])
    img.pack()

bpy.context.scene.render.fps = 24
bpy.ops.object.select_all(action='DESELECT')
for o in (arm, body, sw, bow, back, nock):
    o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=str(OUT / f'{CID}.glb'), export_format='GLB', use_selection=True,
                          export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True,
                          export_image_format='JPEG', export_image_quality=88)
bpy.ops.wm.save_as_mainfile(filepath=str(root / f'source_art/{CID}/{CID}.blend'), compress=True)
print('READY', CID, sorted(a.name for a in bpy.data.actions), flush=True)
