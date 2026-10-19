"""Assembla il nuovo Gascor (pipeline Meshy) e gli trasferisce le mosse di Anteos.

Ingressi (source_art/gascor/meshy): gascor_rigged.glb (rig automatico Meshy),
sword.glb e shield.glb (ricavati dall'illustrazione di Gascor).
Le 18 clip vengono prese da source_art/anteos/anteos.blend (generato da
tools/anteos/assemble.py) con un retarget: per ogni fotogramma ogni osso di Gascor
assume lo stesso orientamento assoluto dell'osso omonimo di Anteos (i due rig Meshy
hanno le stesse 24 ossa ma pose di riposo diverse); il bacino è scalato sulla statura.
Le armi sono agganciate alle mani nella stessa posizione relativa usata per Anteos.

Uso:  python tools/gascor/assemble_meshy.py   (modulo bpy) oppure blender -b -P ...
"""
import bpy, math
import numpy as np
from mathutils import Vector, Matrix, Quaternion
from pathlib import Path

root = Path(__file__).resolve().parents[2]
SRC = root / 'source_art/gascor/meshy'
ANTEOS = root / 'source_art/anteos/anteos.blend'
OUT = root / 'assets/models/gascor'


def imported(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    return [o for o in bpy.data.objects if o not in before]


bpy.ops.wm.read_factory_settings(use_empty=True)
objs = imported(SRC / 'gascor_rigged.glb')
arm = next(o for o in objs if o.type == 'ARMATURE')
body = next(o for o in objs if o.type == 'MESH' and o.find_armature() == arm)
for o in objs:
    if o.type == 'MESH' and o is not body:
        bpy.data.objects.remove(o)
arm.name = 'Gascor_Rig'; body.name = 'Gascor'
if arm.animation_data and arm.animation_data.action:
    bpy.data.actions.remove(arm.animation_data.action)
arm.animation_data_create()

# --- Anteos come sorgente: rig con le clip, spada e scudo già calibrati ---------
with bpy.data.libraries.load(str(ANTEOS), link=False) as (src_data, dst):
    dst.objects = [n for n in src_data.objects if n in ('Anteos_Rig', 'Spada', 'Scudo')]
    dst.actions = list(src_data.actions)
for o in dst.objects:
    bpy.context.scene.collection.objects.link(o)
src = bpy.data.objects['Anteos_Rig']; a_sword = bpy.data.objects['Spada']; a_shield = bpy.data.objects['Scudo']
src.animation_data_create()
clips = list(dst.actions)


def rest(o):
    if o.animation_data:
        o.animation_data.action = None
    for p in o.pose.bones:
        p.matrix_basis = Matrix()


def set_action(o, a):
    o.animation_data.action = a
    try:
        o.animation_data.action_slot = a.slots[0]
    except Exception:
        pass


rest(src); rest(arm); bpy.context.view_layer.update()


def bone_frame(o, name):  # spazio mondo, a riposo
    return o.matrix_world @ o.data.bones[name].matrix_local


# relazioni arma/osso di Anteos (in posa le ossa dei due rig coincidono come orientamento)
REL_SWORD = bone_frame(src, 'RightHand').inverted() @ a_sword.matrix_world
REL_SHIELD = bone_frame(src, 'LeftForeArm').inverted() @ a_shield.matrix_world


def pca(o):
    co = np.array([v.co[:] for v in o.data.vertices]); c = co.mean(0)
    return co, c, np.linalg.svd(co - c, full_matrices=False)[2]


# assi della spada di Anteos nel suo spazio oggetto (origine = centro impugnatura)
co, c, ax = pca(a_sword)
tip = max((Vector(p) for p in co), key=lambda v: v.length)
bA = tip.normalized(); sA = Vector(ax[1]); sA = (sA - bA * sA.dot(bA)).normalized()
BA = Matrix((bA, sA, bA.cross(sA))).transposed()
# assi dello scudo di Anteos: normale verso la faccia esterna (umbone)
co, c, ax = pca(a_shield)
nA = Vector(ax[2]); d = (co - c) @ np.array(nA); rad = np.linalg.norm((co - c) - np.outer(d, np.array(nA)), axis=1)
if d[rad < rad.max() * .15].max() < -d[rad < rad.max() * .15].min():
    nA = -nA
# direzione "su" per lo scudo, nel sistema dell'avambraccio: la misuro nella Parata Sx
set_action(src, bpy.data.actions['Parata Sx'])
bpy.context.scene.frame_set(int(bpy.data.actions['Parata Sx'].frame_range[1] / 2))
FA = (src.matrix_world @ src.pose.bones['LeftForeArm'].matrix).to_3x3().normalized()
n_f = (REL_SHIELD.to_3x3().normalized() @ nA).normalized()
up_f = FA.inverted() @ Vector((0, 0, 1)); up_f = (up_f - n_f * up_f.dot(n_f)).normalized()
rest(src); bpy.context.view_layer.update()

# --- Retarget delle clip ------------------------------------------------------
order = []
def walk(b):
    order.append(b)
    for ch in b.children:
        walk(ch)
for b in arm.data.bones:
    if b.parent is None:
        walk(b)
hips = order[0].name
ratio = arm.data.bones[hips].head_local.z / src.data.bones[hips].head_local.z
print('RETARGET ratio bacino', round(ratio, 3), flush=True)
for p in arm.pose.bones:
    p.rotation_mode = 'QUATERNION'
for act in clips:
    set_action(src, act)
    new = bpy.data.actions.new(act.name); new.use_fake_user = True
    set_action(arm, new)
    last = {}
    for f in range(int(act.frame_range[0]), int(act.frame_range[1]) + 1):
        bpy.context.scene.frame_set(f)
        S = {b.name: src.pose.bones[b.name].matrix.copy() for b in order}
        pm = {}
        for b in order:
            pb = arm.pose.bones[b.name]; R = S[b.name].to_quaternion()
            if b.parent is None:
                pos = S[b.name].translation * ratio
                M = Matrix.Translation(pos) @ R.to_matrix().to_4x4()
                basis = b.matrix_local.inverted() @ M
            else:
                P = pm[b.parent.name] @ (b.parent.matrix_local.inverted() @ b.matrix_local)
                q = P.to_quaternion().inverted() @ R
                basis = q.to_matrix().to_4x4(); M = P @ basis
            pm[b.name] = M
            pb.matrix_basis = basis
            q = pb.rotation_quaternion.copy()
            if b.name in last and last[b.name].dot(q) < 0:
                q.negate(); pb.rotation_quaternion = q
            last[b.name] = q.copy()
            pb.keyframe_insert('rotation_quaternion', frame=f)
            if b.parent is None:
                pb.keyframe_insert('location', frame=f)
    print('CLIP', act.name, flush=True)
for a in clips:
    a.name = a.name + '__anteos'
for a in bpy.data.actions:
    if a.name.endswith('.001'):
        a.name = a.name[:-4]
for o in (src, a_sword, a_shield):
    bpy.data.objects.remove(o)
for a in [a for a in bpy.data.actions if a.name.endswith('__anteos')]:
    bpy.data.actions.remove(a)
rest(arm); bpy.context.view_layer.update()


def load_weapon(path, faces):
    o = next(x for x in imported(path) if x.type == 'MESH')
    o.data.transform(o.matrix_world); o.matrix_world = Matrix()
    mod = o.modifiers.new('riduzione', 'DECIMATE'); mod.ratio = min(1, faces / len(o.data.polygons))
    bpy.context.view_layer.objects.active = o; bpy.ops.object.modifier_apply(modifier=mod.name)
    return o


def attach(o, bone, rel):
    o.parent = arm; o.parent_type = 'BONE'; o.parent_bone = bone
    bpy.context.view_layer.update(); o.matrix_world = bone_frame(arm, bone) @ rel


# --- Spada di Gascor: lama dal lato lungo, origine al centro dell'impugnatura ---
sword = load_weapon(SRC / 'sword.glb', 6000)
co, c, ax = pca(sword); u = ax[0]; t = (co - c) @ u
prof = [(a, np.linalg.norm(((co - c) - np.outer(t, u))[(t > a) & (t < a + .05)], axis=1).max(initial=0))
        for a in np.linspace(t.min(), t.max() - .05, 40)]
guard = max(prof, key=lambda x: x[1])[0] + .025                   # la guardia è la parte più larga
if t.max() - guard > guard - t.min():                              # la lama è il tratto più lungo
    u = -u; t = -t; guard = -guard
grip_c = guard + (t.max() - guard) * .42
s = 1.05 / (t.max() - t.min())                                     # spada lunga 105 cm
for v, p in zip(sword.data.vertices, co):
    v.co = (Vector(p) - Vector(c) - Vector(u) * grip_c) * s
bG = Vector(-u); sG = Vector(ax[1]); sG = (sG - bG * sG.dot(bG)).normalized()
BG = Matrix((bG, sG, bG.cross(sG))).transposed()
rot = REL_SWORD.to_3x3().normalized() @ BA @ BG.transposed()
attach(sword, 'RightHand', Matrix.Translation(REL_SWORD.translation) @ rot.to_4x4() @ Matrix.Scale(REL_SWORD.to_scale()[0], 4))  # il rig Meshy ha scala 0.01
sword.name = 'Spada'

# --- Scudo a goccia: alto 95 cm, punta in basso, faccia verso l'esterno -------
shield = load_weapon(SRC / 'shield.glb', 9000)
co, c, ax = pca(shield); a1 = Vector(ax[0]); n = Vector(ax[2])
t = (co - c) @ np.array(a1)
w_top = np.ptp(((co - c) @ ax[1])[t > t.max() * .7]); w_bot = np.ptp(((co - c) @ ax[1])[t < t.min() * .7])
if w_top < w_bot:                                                  # in alto lo scudo è più largo
    a1 = -a1
d = (co - c) @ np.array(n); rad = np.linalg.norm((co - c) - np.outer(d, np.array(n)), axis=1)
if d[rad < rad.max() * .2].mean() < d[rad > rad.max() * .8].mean():  # faccia convessa = davanti
    n = -n
s = .95 / np.ptp(t)
for v, p in zip(shield.data.vertices, co):
    v.co = (Vector(p) - Vector(c)) * s
BS = Matrix((n, a1, n.cross(a1))).transposed()                     # (normale, su, laterale) del modello
BF = Matrix((n_f, up_f, n_f.cross(up_f))).transposed()             # gli stessi assi nell'avambraccio
attach(shield, 'LeftForeArm', Matrix.Translation(REL_SHIELD.translation) @ (BF @ BS.transposed()).to_4x4() @ Matrix.Scale(REL_SHIELD.to_scale()[0], 4))
shield.name = 'Scudo'

for img in bpy.data.images:
    used_by_body = any(img in [nd.image for nd in m.node_tree.nodes if nd.type == 'TEX_IMAGE']
                       for m in body.data.materials if m and m.use_nodes)
    lim = 2048 if used_by_body else 1024
    if img.size[0] > lim:
        img.scale(lim, lim * img.size[1] // img.size[0])
    img.pack()

bpy.context.scene.render.fps = 24
bpy.ops.object.select_all(action='DESELECT')
for o in (arm, body, sword, shield):
    o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=str(OUT / 'gascor.glb'), export_format='GLB', use_selection=True,
                          export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True,
                          export_image_format='JPEG', export_image_quality=88)
bpy.ops.wm.save_as_mainfile(filepath=str(root / 'source_art/gascor/gascor-meshy.blend'), compress=True)
print('GASCOR_READY', sorted(a.name for a in bpy.data.actions), flush=True)
