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
    'nuchra':  dict(name='Nuchra', kind='pole', length=1.30, grip=.40, shaft=(-.48, -.18), heavy=True, sep=-.17, gshift=(0, .08, 0)),
    'zenyo':   dict(name='Zenyo', kind='pole', length=1.80, grip=.50, shaft=(-.85, -.25), heavy=False),
    'shaara':  dict(name='Shaara', weapon=False, heavy=False),
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
EXTRA = {'Parata Sx': 'anim_parata2h.glb', 'Parata Dx': 'anim_parata2h.glb'} if CFG.get('weapon', True) else {}  # Two-handed Parry (149)
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

WEAPON = CFG.get('weapon', True)       # Shaara combatte a mani nude
w = None
if WEAPON:
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

    # --- Presa a due mani guidata dall'arma ----------------------------------------
    # Le clip di Anteos sono di spada e scudo: la mano destra fa gesti da spada a una mano e
    # l'asta finiva dietro il corpo. Qui è l'arma a guidare: per ogni mossa la sua posizione
    # è definita rispetto al busto (guardia avanti all'anca, fendente dall'alto, tagli ad
    # arco, parata di traverso), con i colpi nello stesso istante in cui colpisce la clip
    # originale. Poi due IK a due ossa portano entrambe le mani sull'asta, gomiti in basso
    # e in fuori. Gambe, busto e testa restano quelli della clip.
    # Le ossa importate da Meshy hanno code lunghissime: lavoro sulle teste delle ossa.
    from mathutils import Quaternion
    AW = arm.matrix_world; AWi = AW.inverted(); UNIT = 1 / AW.to_scale()[0]
    def head(n):
        return arm.pose.bones[n].head.copy()          # spazio armatura
    def hw(n):
        return AW @ arm.pose.bones[n].head            # mondo
    def turn(name, R, pivot):
        pb = arm.pose.bones[name]; M = pb.matrix.copy()
        T = Matrix.Translation(pivot) @ R.to_matrix().to_4x4() @ Matrix.Translation(-pivot)
        pb.matrix = T @ M; bpy.context.view_layer.update()
    def two_bone(side, target, pole_pref):
        A, F, H = side + 'Arm', side + 'ForeArm', side + 'Hand'
        S, E, W = head(A), head(F), head(H)
        a_, b_ = (E - S).length, (W - E).length
        d = target - S; dl = min(max(d.length, abs(a_ - b_) + 1e-3), (a_ + b_) * .995)
        dn = d.normalized()
        pole = pole_pref - dn * pole_pref.dot(dn)
        if pole.length < 1e-6:
            pole = (E - S) - dn * (E - S).dot(dn)
        pole.normalize()
        x = (a_ * a_ - b_ * b_ + dl * dl) / (2 * dl); h = math.sqrt(max(a_ * a_ - x * x, 0))
        E2 = S + dn * x + pole * h
        turn(A, (E - S).rotation_difference(E2 - S), S)
        E, W = head(F), head(H)
        turn(F, (W - E).rotation_difference(S + dn * dl - E), E)

    rest(arm); bpy.context.view_layer.update()
    K_inv = ((AW @ arm.pose.bones['RightHand'].matrix).inverted() @ w.matrix_world).inverted()  # arma -> mano
    ARM_LEN = (hw('LeftForeArm') - hw('LeftArm')).length + (hw('LeftHand') - hw('LeftForeArm')).length
    KS = ARM_LEN / .55                                 # pose disegnate per un braccio di 55 cm
    LOC = Matrix((Vector(u), sG, Vector(u).cross(sG))).transposed()   # assi dell'arma nel suo spazio
    STYLE = 'lancia' if CFG['length'] > 1.6 else 'pesante'
    SEP = CFG.get('sep', {'lancia': .38, 'pesante': -.13 if CFG['kind'] == 'sword' else -.28}[STYLE])   # mano sinistra lungo l'asta
    F_, L_, U_ = 'f', 'l', 'u'
    # pose: (presa della mano destra (avanti, sinistra, su) dal centro delle spalle, direzione
    # della testa dell'arma, normale del piano in cui sta la lama)
    POSES = {
     'lancia': {
      'riposo':      ((0.00, -.20, -.45), (1, .25, .35), 'l'),
      'guardia':     ((0.00, -.20, -.42), (1, .20, .30), 'l'),
      'affondo_c':   ((-.12, -.22, -.38), (1, .15, .20), 'l'),
      'affondo':     ((0.30, -.10, -.30), (1, .05, .12), 'l'),
      'fendente_c':  ((0.05, -.15, -.05), (.40, .15, 1), 'l'),
      'fendente':    ((0.05, -.08, -.28), (1, .10, -.35), 'l'),
      'taglio_d':    ((0.15, 0.10, -.35), (.55, -.80, .10), 'u'),
      'taglio_m':    ((0.12, 0.00, -.30), (1, 0, .05), 'u'),
      'taglio_s':    ((0.05, -.15, -.30), (.50, .85, .05), 'u'),
      'parata':      ((0.25, -.25, 0.05), (.15, 1, .25), 'f'),
     },
     'pesante': {
      'riposo':      ((0.24, -.10, -.40), (.55, .05, .85), 'l'),     # guardia bassa, arma davanti
      'guardia':     ((0.28, -.08, -.32), (.80, .05, .80), 'l'),
      'affondo_c':   ((0.12, -.15, -.30), (1, .05, .15), 'l'),
      'affondo':     ((0.45, -.05, -.20), (1, 0, .05), 'l'),
      'fendente_c':  ((0.05, -.08, 0.28), (-.70, .05, .70), 'l'),
      'fendente':    ((0.45, -.03, -.30), (.80, 0, -.60), 'l'),
      'taglio_d':    ((0.15, -.25, -.15), (.20, -1, .20), 'u'),
      'taglio_m':    ((0.42, 0.00, -.25), (1, 0, 0), 'u'),
      'taglio_s':    ((0.20, 0.25, -.20), (.10, 1, .10), 'u'),
      'parata':      ((0.30, -.20, 0.15), (.10, 1, .35), 'f'),
     }}[STYLE]
    if CFG.get('gshift'):                              # presa spostata verso il centro (corporature larghe)
        POSES = {k: (tuple(a + b for a, b in zip(v[0], CFG['gshift'])),) + v[1:] for k, v in POSES.items()}
    # riposo e spostamenti: l'arma sta nella sola mano destra (lancia dritta al fianco, armi
    # pesanti in spalla) e il braccio sinistro resta quello naturale della clip
    ONE_HAND = ('Riposo', 'Camminata', 'Correre', 'Avanzare')
    POSES['mano'] = {'lancia': ((0.06, -.26, -.42), (.15, 0, 1), 'l'),
                     'pesante': ((0.10, -.22, -.12), (-.55, -.15, .82), 'l')}[STYLE]
    FIXED = {n: 'mano' for n in ONE_HAND}
    def schedule(name, ts):
        """Pose chiave (frazione della clip, posa); ts = istante del colpo nella clip originale."""
        seq = {'Affondo': [(ts - .2, 'affondo_c'), (ts, 'affondo'), (ts + .12, 'affondo')],
               'Fendente': [(ts - .22, 'fendente_c'), (ts, 'fendente'), (ts + .12, 'fendente')],
               'Taglio Sx': [(ts - .2, 'taglio_d'), (ts, 'taglio_m'), (ts + .14, 'taglio_s')],
               'Taglio Dx': [(ts - .2, 'taglio_s'), (ts, 'taglio_m'), (ts + .14, 'taglio_d')],
               'Parata Sx': [(.25, 'parata'), (.75, 'parata')],
               'Parata Dx': [(.25, 'parata'), (.75, 'parata')]}.get(name)
        if name in FIXED:
            return [(0, FIXED[name]), (1, FIXED[name])]
        if seq is None:
            return [(0, 'guardia'), (1, 'guardia')]
        keys = [(0, 'guardia')] + [(min(max(t, .05), .95), p) for t, p in seq] + [(1, 'guardia')]
        out = []
        for t, p in keys:                                  # tempi crescenti
            if out and t <= out[-1][0]:
                t = out[-1][0] + .01
            out.append((min(t, 1), p))
        return out
    def body_frame():
        c = (hw('LeftArm') + hw('RightArm')) / 2
        left = (hw('LeftArm') - hw('RightArm')).normalized()
        up = (hw('neck') - hw('Spine')); up = (up - left * up.dot(left)).normalized()
        return c, left.cross(up), left, up                 # centro, avanti, sinistra, su
    def pose_at(sched, x):
        for (t0, p0), (t1, p1) in zip(sched, sched[1:]):
            if x <= t1:
                k = 0 if t1 <= t0 else (x - t0) / (t1 - t0)
                return POSES[p0], POSES[p1], k * k * (3 - 2 * k)
        return POSES[sched[-1][1]], POSES[sched[-1][1]], 0
    def vec(t, F, Lf, Up):
        return F * t[0] + Lf * t[1] + Up * t[2]
    def strike_time(act):
        """Istante (frazione) in cui la mano destra della clip va più veloce rispetto al busto."""
        f0, f1 = int(act.frame_range[0]), int(act.frame_range[1]); prev = None; best = (0, .5)
        for f in range(f0, f1 + 1):
            bpy.context.scene.frame_set(f)
            c, F, Lf, Up = body_frame(); r = hw('RightHand') - c
            loc = Vector((r.dot(F), r.dot(Lf), r.dot(Up)))
            x = (f - f0) / max(f1 - f0, 1)
            if prev is not None and .15 < x < .85:
                v = (loc - prev).length
                if v > best[0]:
                    best = (v, x)
            prev = loc
        return best[1]
    BONES = ('RightArm', 'RightForeArm', 'RightHand', 'LeftArm', 'LeftForeArm', 'LeftHand')
    LEFT = ('LeftShoulder', 'LeftArm', 'LeftForeArm', 'LeftHand')
    # In Avanzare (camminata in guardia) il braccio sinistro della clip originale è alzato come per
    # reggere uno scudo: prendo l'oscillazione naturale della Camminata, alla stessa fase.
    walk = bpy.data.actions.get('Camminata'); adv = bpy.data.actions.get('Avanzare')
    if walk and adv:
        wl = walk.frame_range[1] - walk.frame_range[0]; al = adv.frame_range[1] - adv.frame_range[0]
        keep = {}
        set_action(arm, walk)
        for f in range(int(adv.frame_range[0]), int(adv.frame_range[1]) + 1):
            x = walk.frame_range[0] + ((f - adv.frame_range[0]) / max(al, 1)) * wl
            bpy.context.scene.frame_set(int(x), subframe=x - int(x))
            keep[f] = {nm: arm.pose.bones[nm].rotation_quaternion.copy() for nm in LEFT}
        set_action(arm, adv)
        for f, qs in keep.items():
            for nm, q in qs.items():
                pb = arm.pose.bones[nm]; pb.rotation_quaternion = q; pb.keyframe_insert('rotation_quaternion', frame=f)
    for act in list(bpy.data.actions):
        set_action(arm, act)
        one = act.name in ONE_HAND
        f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
        sched = schedule(act.name, strike_time(act))
        frames = {}
        for f in range(f0, f1 + 1):
            bpy.context.scene.frame_set(f)
            c, F, Lf, Up = body_frame()
            P0, P1, k = pose_at(sched, (f - f0) / max(f1 - f0, 1))
            g = c + vec(P0[0], F, Lf, Up).lerp(vec(P1[0], F, Lf, Up), k) * KS
            d0 = vec(P0[1], F, Lf, Up).normalized(); d1 = vec(P1[1], F, Lf, Up).normalized()
            d = d0.slerp(d1, k) if d0.dot(d1) > -.99 else (d0 if k < .5 else d1)
            nrm = {'l': Lf, 'u': Up, 'f': F}
            n = nrm[P0[2]].lerp(nrm[P1[2]], k)
            e = n.cross(d)
            if e.length < 1e-3:
                e = Up.cross(d)
            e.normalize()
            Wm = Matrix.Translation(g) @ (Matrix((d, e, d.cross(e))).transposed() @ LOC.transposed()).to_4x4()
            Hm = AWi @ Wm @ K_inv                               # mano destra voluta, spazio armatura
            two_bone('Right', Hm.translation, AWi.to_3x3() @ (-Up - Lf * .6 - F * .2))
            pb = arm.pose.bones['RightHand']; M = Hm.normalized(); M.translation = pb.head
            pb.matrix = M; bpy.context.view_layer.update()
            if one:
                frames[f] = {nm: arm.pose.bones[nm].rotation_quaternion.copy() for nm in BONES[:3]}
                continue
            gl = AWi @ (g + d * SEP)                            # presa sinistra
            S = head('LeftArm'); tgt = gl - (gl - S).normalized() * .07 * UNIT
            two_bone('Left', tgt, AWi.to_3x3() @ (-Up + Lf * .6 - F * .2))
            E, Wr = head('LeftForeArm'), head('LeftHand'); D = (AWi.to_3x3() @ d).normalized()
            fa = (Wr - E).normalized(); hd = fa - D * fa.dot(D)
            if hd.length > 1e-4:
                pbh = arm.pose.bones['LeftHand']; hy = pbh.matrix.col[1].xyz.normalized()
                turn('LeftHand', hy.rotation_difference((hd.normalized() + fa * .3).normalized()), Wr)
            frames[f] = {nm: arm.pose.bones[nm].rotation_quaternion.copy() for nm in BONES}
        last = {}
        for f, qs in sorted(frames.items()):
            for nm, q in qs.items():
                if nm in last and last[nm].dot(q) < 0:
                    q.negate()
                last[nm] = q
                pb = arm.pose.bones[nm]; pb.rotation_quaternion = q
                pb.keyframe_insert('rotation_quaternion', frame=f)
        print('PRESA', act.name, [p for _, p in sched], flush=True)
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
    if o:
        o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=str(OUT / f'{CID}.glb'), export_format='GLB', use_selection=True,
                          export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True,
                          export_image_format='JPEG', export_image_quality=88)
bpy.ops.wm.save_as_mainfile(filepath=str(root / f'source_art/{CID}/{CID}.blend'), compress=True)
print('READY', CID, sorted(a.name for a in bpy.data.actions), flush=True)
