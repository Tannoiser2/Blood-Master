"""Assembla un personaggio Meshy con arma a due mani e gli trasferisce le mosse di Anteos.

Uso:  python tools/heroes/assemble.py <id>      (modulo bpy)   id: ut | shannon | nuchra | ramok

Ingressi (source_art/<id>/meshy): <id>_rigged.glb (rig automatico Meshy) e weapon.glb.
Le 18 clip arrivano da source_art/anteos/anteos.blend con lo stesso retarget di Gascor
(orientamento assoluto osso per osso, bacino scalato sulla statura). L'arma è agganciata
alla mano destra come la spada di Anteos; la mano sinistra afferra l'asta con un IK a due
ossa che viene poi cotto nelle clip, così in Godot non servono vincoli.
"""
import bpy, sys, math
import numpy as np
from mathutils import Vector, Matrix
from pathlib import Path

root = Path(__file__).resolve().parents[2]
CID = sys.argv[-1]
# length: lunghezza dell'arma (m); grip: posizione della mano destra misurata dal fondo,
# in frazione della lunghezza; shaft: tratto dell'asta (m, negativo = verso il fondo) dove
# può stare la mano sinistra; heavy: fendente con la clip a due mani del martello;
# kind: 'sword' trova la guardia, 'pole' trova la testa dalla larghezza degli estremi.
CFG = {
    'ut':      dict(name='Ut', kind='sword', length=1.50, grip=.235, shaft=(-.20, -.12), heavy=True),
    'shannon': dict(name='Shannon', kind='pole', length=2.05, grip=.50, shaft=(-.85, -.25), heavy=False),
    'nuchra':  dict(name='Nuchra', kind='pole', length=1.30, grip=.40, shaft=(-.48, -.18), heavy=True),
    'ramok':   dict(name='Ramok', kind='pole', length=2.05, grip=.50, shaft=(-.85, -.25), heavy=True),
}[CID]
SRC = root / f'source_art/{CID}/meshy'
ANTEOS = root / 'source_art/anteos/anteos.blend'
OUT = root / f'assets/models/{CID}'
OUT.mkdir(parents=True, exist_ok=True)


def imported(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    return [o for o in bpy.data.objects if o not in before]


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

with bpy.data.libraries.load(str(ANTEOS), link=False) as (src_data, dst):
    dst.objects = [n for n in src_data.objects if n in ('Anteos_Rig', 'Spada')]
    dst.actions = list(src_data.actions)
for o in dst.objects:
    bpy.context.scene.collection.objects.link(o)
src = bpy.data.objects['Anteos_Rig']; a_sword = bpy.data.objects['Spada']
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


def bone_frame(o, name):
    return o.matrix_world @ o.data.bones[name].matrix_local


REL_SWORD = bone_frame(src, 'RightHand').inverted() @ a_sword.matrix_world


def pca(o):
    co = np.array([v.co[:] for v in o.data.vertices]); c = co.mean(0)
    return co, c, np.linalg.svd(co - c, full_matrices=False)[2]


co, c, ax = pca(a_sword)
tip = max((Vector(p) for p in co), key=lambda v: v.length)
bA = tip.normalized(); sA = Vector(ax[1]); sA = (sA - bA * sA.dot(bA)).normalized()
BA = Matrix((bA, sA, bA.cross(sA))).transposed()

# --- Retarget delle clip (come Gascor) ------------------------------------------
order = []
def walk(b):
    order.append(b)
    for ch in b.children:
        walk(ch)
for b in arm.data.bones:
    if b.parent is None:
        walk(b)
hips = order[0].name
for p in arm.pose.bones:
    p.rotation_mode = 'QUATERNION'


def retarget(srco, act, name):
    """Ogni osso del bersaglio prende l'orientamento assoluto dell'osso omonimo della sorgente."""
    ratio = arm.data.bones[hips].head_local.z / srco.data.bones[hips].head_local.z
    set_action(srco, act)
    new = bpy.data.actions.new(name); new.use_fake_user = True
    set_action(arm, new)
    last = {}
    for f in range(int(act.frame_range[0]), int(act.frame_range[1]) + 1):
        bpy.context.scene.frame_set(f)
        S = {b.name: srco.pose.bones[b.name].matrix.copy() for b in order}
        pm = {}
        for b in order:
            pb = arm.pose.bones[b.name]; R = S[b.name].to_quaternion()
            if b.parent is None:
                M = Matrix.Translation(S[b.name].translation * ratio) @ R.to_matrix().to_4x4()
                basis = b.matrix_local.inverted() @ M
            else:
                P = pm[b.parent.name] @ (b.parent.matrix_local.inverted() @ b.matrix_local)
                basis = (P.to_quaternion().inverted() @ R).to_matrix().to_4x4(); M = P @ basis
            pm[b.name] = M
            pb.matrix_basis = basis
            q = pb.rotation_quaternion.copy()
            if b.name in last and last[b.name].dot(q) < 0:
                q.negate(); pb.rotation_quaternion = q
            last[b.name] = q.copy()
            pb.keyframe_insert('rotation_quaternion', frame=f)
            if b.parent is None:
                pb.keyframe_insert('location', frame=f)
    set_action(arm, new)
    print('CLIP', name, flush=True)
    return new


for act in clips:
    act.name = act.name + '__anteos'
for act in clips:
    retarget(src, act, act.name[:-8])
for o in (src, a_sword):
    bpy.data.objects.remove(o)
for a in clips:
    bpy.data.actions.remove(a)

# clip a due mani dal catalogo Meshy, generate sul rig di Ut e trasferite a tutti
EXTRA = {'Parata Sx': 'anim_parata2h.glb', 'Parata Dx': 'anim_parata2h.glb'}  # Two-handed Parry (149)
if CFG['heavy']:
    EXTRA['Fendente'] = 'anim_martello.glb'                                    # Heavy Hammer Swing (128)
for name, fname in EXTRA.items():
    objs = imported(root / 'source_art/ut/meshy' / fname)
    sa = next(o for o in objs if o.type == 'ARMATURE'); act = sa.animation_data.action
    for pbn in sa.pose.bones:
        pbn.rotation_mode = 'QUATERNION'
    old = bpy.data.actions.get(name)
    if old:
        old.name = name + '__vecchia'
    retarget(sa, act, name)
    if old:
        bpy.data.actions.remove(old)
    bpy.data.actions.remove(act)
    for o in objs:
        bpy.data.objects.remove(o)
rest(arm); bpy.context.view_layer.update()

# --- Arma: asse lungo, testa riconosciuta, origine sulla presa della mano destra ---
w = next(x for x in imported(SRC / 'weapon.glb') if x.type == 'MESH')
w.data.transform(w.matrix_world); w.matrix_world = Matrix()
mod = w.modifiers.new('riduzione', 'DECIMATE'); mod.ratio = min(1, 9000 / len(w.data.polygons))
bpy.context.view_layer.objects.active = w; bpy.ops.object.modifier_apply(modifier=mod.name)
co, c, ax = pca(w); u = ax[0]; t = (co - c) @ u
radial = np.linalg.norm((co - c) - np.outer(t, u), axis=1)
L0 = t.max() - t.min()
if CFG['kind'] == 'sword':
    edges = np.linspace(t.min(), t.max() - L0 * .04, 50)
    prof = [radial[(t > a) & (t < a + L0 * .04)].max(initial=0) for a in edges]
    guard = edges[int(np.argmax(prof))] + L0 * .02
    head_pos = t.max() - guard > guard - t.min()     # la lama è il lato lungo
else:
    q = L0 * .3
    head_pos = radial[t > t.max() - q].max() > radial[t < t.min() + q].max()
if not head_pos:
    u = -u; t = -t
s = CFG['length'] / L0
grip_t = t.min() + L0 * CFG['grip']
for v, p in zip(w.data.vertices, co):
    v.co = (Vector(p) - Vector(c) - Vector(u) * grip_t) * s
# assi del modello: (verso la testa, larghezza, spessore) come la spada di Anteos
bG = Vector(u); sG = Vector(ax[1]); sG = (sG - bG * sG.dot(bG)).normalized()
BG = Matrix((bG, sG, bG.cross(sG))).transposed()
rot = REL_SWORD.to_3x3().normalized() @ BA @ BG.transposed()
w.parent = arm; w.parent_type = 'BONE'; w.parent_bone = 'RightHand'
bpy.context.view_layer.update()
w.matrix_world = bone_frame(arm, 'RightHand') @ Matrix.Translation(REL_SWORD.translation) @ rot.to_4x4() @ Matrix.Scale(REL_SWORD.to_scale()[0], 4)
w.name = 'Arma'
bpy.context.view_layer.update()

# --- Presa a due mani: arma raddrizzata e mano sinistra sull'asta -----------------
# Le ossa importate da Meshy hanno code lunghissime, quindi niente vincoli IK di Blender:
# lavoro sulle teste delle ossa (spalla, gomito, polso) e scrivo il risultato nelle clip.
# 1) fuori dagli attacchi l'arma non punta mai all'indietro (né verso terra, per aste e
#    asce, che in guardia puntano avanti e in alto): la correggo ruotando il polso
#    destro, al massimo di 120°;
# 2) la mano sinistra afferra l'asta nel punto più comodo per la spalla (entro il tratto
#    CFG['shaft'] dietro la mano destra) con un IK a due ossa: gomito in basso e in fuori;
# 3) il palmo sinistro si chiude attorno all'asta.
from mathutils import Quaternion
CALM = ('Riposo', 'Camminata', 'Avanzare', 'Correre', 'In guardia', 'Carica', 'Schivata', 'Rialzarsi', 'Sbilanciato')
AW = arm.matrix_world; AWi = AW.inverted(); UNIT = 1 / AW.to_scale()[0]   # metri -> unità armatura
UP = Vector((0, 0, 1))
U_W = Vector(u)                                   # verso la testa dell'arma, spazio dell'arma
def head(n):
    return arm.pose.bones[n].head.copy()          # spazio armatura
def turn(name, R, pivot):
    pb = arm.pose.bones[name]; M = pb.matrix.copy()
    T = Matrix.Translation(pivot) @ R.to_matrix().to_4x4() @ Matrix.Translation(-pivot)
    pb.matrix = T @ M; bpy.context.view_layer.update()
def weapon_dir():
    return (AWi.to_3x3() @ w.matrix_world.to_3x3() @ U_W).normalized()
def grip_origin():
    return AWi @ w.matrix_world.translation
def two_bone(target, pole_pref):
    S, E, W = head('LeftArm'), head('LeftForeArm'), head('LeftHand')
    a_, b_ = (E - S).length, (W - E).length
    d = target - S; dl = min(max(d.length, abs(a_ - b_) + 1e-3), (a_ + b_) * .999)
    dn = d.normalized()
    pole = pole_pref - dn * pole_pref.dot(dn)
    if pole.length < 1e-6:
        pole = (E - S) - dn * (E - S).dot(dn)
    pole.normalize()
    x = (a_ * a_ - b_ * b_ + dl * dl) / (2 * dl); h = math.sqrt(max(a_ * a_ - x * x, 0))
    E2 = S + dn * x + pole * h
    turn('LeftArm', (E - S).rotation_difference(E2 - S), S)
    E, W = head('LeftForeArm'), head('LeftHand')
    turn('LeftForeArm', (W - E).rotation_difference(S + dn * dl - E), E)
    return a_ + b_
BONES = ('RightHand', 'LeftArm', 'LeftForeArm', 'LeftHand')
for act in list(bpy.data.actions):
    set_action(arm, act)
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    frames = {}
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        left = head('LeftUpLeg') - head('RightUpLeg'); left.z = 0; left.normalize()
        fwd = left.cross(UP)
        # 1) arma raddrizzata
        D = weapon_dir()
        if act.name in CALM:
            Dt = D.copy()
            if D.dot(fwd) < 0:
                Dt -= fwd * 2 * D.dot(fwd)
            if CFG['kind'] == 'pole':
                # aste e asce in guardia: verso l'avversario e un po' in alto
                Dt = Dt.normalized() * .35 + fwd * .75 + UP * (.25 if CFG['length'] > 1.6 else .7)
            R = D.rotation_difference(Dt.normalized())
            if R.angle > math.radians(120):
                R = Quaternion(R.axis, math.radians(120))
            if R.angle > 1e-3:
                turn('RightHand', R, head('RightHand'))
            D = weapon_dir()
        # 2) punto della presa: quello a distanza più comoda dalla spalla sinistra
        S = head('LeftArm'); reach = (head('LeftForeArm') - S).length + (head('LeftHand') - head('LeftForeArm')).length
        g0 = grip_origin(); lo, hi = CFG['shaft']
        best = None
        for k in range(13):
            sm = lo + (hi - lo) * k / 12
            g = g0 + D * sm * UNIT
            score = abs((g - S).length - .82 * reach)
            if best is None or score < best[0]:
                best = (score, g)
        g = best[1]
        tgt = g - (g - S).normalized() * .07 * UNIT     # il polso sta un palmo prima dell'asta
        two_bone(tgt, -UP * 1.0 + left * .6 - fwd * .2)
        # 3) palmo attorno all'asta: la mano prosegue l'avambraccio ma perpendicolare all'asta
        E, Wr = head('LeftForeArm'), head('LeftHand')
        fa = (Wr - E).normalized(); hd = fa - D * fa.dot(D)
        if hd.length > 1e-4:
            pbh = arm.pose.bones['LeftHand']; hy = pbh.matrix.col[1].xyz.normalized()
            turn('LeftHand', hy.rotation_difference((hd.normalized() + fa * .3).normalized()), Wr)
        frames[f] = {n: arm.pose.bones[n].rotation_quaternion.copy() for n in BONES}
    last = {}
    for f, qs in sorted(frames.items()):
        for n, q in qs.items():
            if n in last and last[n].dot(q) < 0:
                q.negate()                                     # quaternioni continui
            last[n] = q
            pb = arm.pose.bones[n]; pb.rotation_quaternion = q
            pb.keyframe_insert('rotation_quaternion', frame=f)
    print('PRESA', act.name, flush=True)
for a in bpy.data.actions:
    a.use_fake_user = True
rest(arm); bpy.context.view_layer.update()

for img in bpy.data.images:
    used_by_body = any(img in [nd.image for nd in m.node_tree.nodes if nd.type == 'TEX_IMAGE']
                       for m in body.data.materials if m and m.use_nodes)
    lim = 2048 if used_by_body else 1024
    if img.size[0] > lim:
        img.scale(lim, lim * img.size[1] // img.size[0])
    img.pack()

bpy.context.scene.render.fps = 24
bpy.ops.object.select_all(action='DESELECT')
for o in (arm, body, w):
    o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=str(OUT / f'{CID}.glb'), export_format='GLB', use_selection=True,
                          export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True,
                          export_image_format='JPEG', export_image_quality=88)
bpy.ops.wm.save_as_mainfile(filepath=str(root / f'source_art/{CID}/{CID}.blend'), compress=True)
print('READY', CID, sorted(a.name for a in bpy.data.actions), flush=True)
