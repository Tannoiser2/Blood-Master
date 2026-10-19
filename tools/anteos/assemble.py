"""Assembla Anteos per Godot a partire dagli scaricamenti Meshy.

Pipeline (vedi docs): concept in posa A senza armi -> image-to-3d -> remesh 50k ->
rig automatico Meshy -> animazioni di libreria Meshy. Spada e scudo sono modelli
separati, ridotti e agganciati alle ossa delle mani: restano rigidi per costruzione.

Uso:  blender -b -P tools/anteos/assemble.py -- [cartella_meshy]
      (oppure python con il modulo bpy)
La cartella di default è source_art/anteos/meshy e deve contenere:
  anteos_rigged.glb, anim_*.glb, sword.glb, shield.glb
"""
import bpy, sys, math
import numpy as np
from mathutils import Vector, Matrix
from pathlib import Path

root = Path(__file__).resolve().parents[2]
SRC = Path(sys.argv[sys.argv.index('--') + 1]) if '--' in sys.argv else root / 'source_art/anteos/meshy'
OUT = root / 'assets/models/anteos'
OUT.mkdir(parents=True, exist_ok=True)

CLIPS = [  # nome della clip = nome della pedina; (file Meshy, azione di libreria)
    ('Riposo', 'anim_riposo.glb'),                  # Idle (0)
    ('Camminata', 'anim_walking.glb'),              # Walking (incluso nel rig)
    ('In guardia', 'anim_guard.glb'),               # Combat Idle (89)
    ('Avanzare', 'anim_camminata_guardia.glb'),     # Walk Fight Forward (21)
    ('Correre', 'anim_running.glb'),                # Running (incluso nel rig)
    ('Carica', 'anim_charge.glb'),                  # Standard Forward Charge (510)
    ('Affondo', 'anim_affondo.glb'),                # Thrust Slash (240)
    ('Fendente', 'anim_cleave.glb'),                # Attack (4)
    ('Taglio Sx', 'anim_left.glb'),                 # Left Slash (97)
    ('Taglio Dx', 'anim_right.glb'),                # Right-hand Sword Slash (219)
    ('Parata Sx', 'anim_parata_block.glb'),         # Block1 (138) - scudo
    ('Parata Dx', 'anim_parata_spada.glb'),         # Sword Parry (147) - spada
    ('Schivata', 'anim_dodge.glb'),                 # Stand Dodge (156)
    ('Rotolare', 'anim_roll.glb'),                  # Roll Dodge (158)
    ('Calcio', 'anim_kick.glb'),                    # Simple Kick (103)
    ('A terra', 'anim_down.glb'),                   # Falling Down (366)
    ('Rialzarsi', 'anim_rise.glb'),                 # Stand Up 2 (345)
    ('Sbilanciato', 'anim_unbalanced.glb'),         # Hit Reaction (178)
]


def imported(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    return [o for o in bpy.data.objects if o not in before]


bpy.ops.wm.read_factory_settings(use_empty=True)
objs = imported(SRC / 'anteos_rigged.glb')
arm = next(o for o in objs if o.type == 'ARMATURE')
body = next(o for o in objs if o.type == 'MESH' and o.find_armature() == arm)
for o in objs:  # Meshy aggiunge una sfera di servizio non skinnata
    if o.type == 'MESH' and o is not body:
        bpy.data.objects.remove(o)
arm.name = 'Anteos_Rig'; body.name = 'Anteos'
if arm.animation_data and arm.animation_data.action:
    bpy.data.actions.remove(arm.animation_data.action)
arm.animation_data_create()

# --- Clip: prendo l'azione da ogni file e butto il resto --------------------
for name, fname in CLIPS:
    objs = imported(SRC / fname)
    src = next(o for o in objs if o.type == 'ARMATURE')
    act = src.animation_data.action
    act.name = name; act.use_fake_user = True
    for o in objs:
        bpy.data.objects.remove(o)
    print('CLIP', name, tuple(round(f, 1) for f in act.frame_range), flush=True)
for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.armatures):
    for d in list(block):
        if d.users == 0:
            block.remove(d)

# posa di riposo per posizionare le armi
arm.animation_data.action = None
for p in arm.pose.bones:
    p.matrix_basis = Matrix()
bpy.context.view_layer.update()


def bone_world(name):
    b = arm.data.bones[name]
    m = arm.matrix_world
    return m @ b.head_local, (m.to_3x3() @ (b.tail_local - b.head_local)).normalized()


def load_weapon(path, faces):
    o = next(x for x in imported(path) if x.type == 'MESH')
    o.data.transform(o.matrix_world); o.matrix_world = Matrix()
    mod = o.modifiers.new('riduzione', 'DECIMATE'); mod.ratio = min(1, faces / len(o.data.polygons))
    bpy.context.view_layer.objects.active = o; bpy.ops.object.modifier_apply(modifier=mod.name)
    co = np.array([v.co[:] for v in o.data.vertices]); c = co.mean(0)
    return o, co, c, np.linalg.svd(co - c, full_matrices=False)[2]


def place(o, frame, center, bone):
    """frame: colonne = assi locali del modello nel mondo; center: dove va l'origine."""
    M = Matrix.Translation(center) @ Matrix(frame).to_4x4()
    o.parent = arm; o.parent_type = 'BONE'; o.parent_bone = bone
    bpy.context.view_layer.update(); o.matrix_world = M


# --- Spada: asse principale; lama dal lato con la punta, impugnatura accorciata --
sword, co, c, ax = load_weapon(SRC / 'sword.glb', 6000)
u = ax[0]; t = (co - c) @ u
w = np.array([np.linalg.norm(((co - c) - np.outer(t, u))[(t > a) & (t < a + .12)], axis=1).max(initial=0)
              for a in np.linspace(t.min(), t.max() - .12, 20)])
guard_t = np.linspace(t.min(), t.max() - .12, 20)[w.argmax()] + .06   # la guardia è la parte più larga
if abs(t.min() - guard_t) > abs(t.max() - guard_t):  # orienta l'asse: lama verso t negativi
    u = -u; t = -t; guard_t = -guard_t
# La spada Meshy ha la guardia a metà lama: sotto la guardia la lama continua fino a
# un'impugnatura rossa corta (t≈0.60-0.88 lungo l'asse, poi il pomolo). Comprimo quel
# tratto di lama a un ricasso di 4 cm, allungo la lama sopra la guardia e lascio
# intatti impugnatura e pomolo. Valori misurati sul profilo di questo modello.
GRIP_LO, GRIP_HI = .60, .88
blade_end = guard_t - .08; ric_lo = guard_t + .10
nt = t.copy()
m = t < blade_end; nt[m] = blade_end + (t[m] - blade_end) * 1.25                     # lama più lunga
m = (t >= ric_lo) & (t < GRIP_LO); nt[m] = ric_lo + (t[m] - ric_lo) * .04 / (GRIP_LO - ric_lo)
m = t >= GRIP_LO; nt[m] = ric_lo + .04 + (t[m] - GRIP_LO)                              # impugnatura e pomolo
co2 = co + np.outer(nt - t, u)
L = nt.max() - nt.min(); s = 0.95 / L                                                  # spada lunga 95 cm
grip_c = ric_lo + .04 + (GRIP_HI - GRIP_LO) / 2                                        # centro dell'impugnatura
for v, p in zip(sword.data.vertices, co2):
    v.co = (Vector(p) - Vector(c) - Vector(u) * grip_c) * s   # origine = centro dell'impugnatura
side = Vector(ax[1])
wrist, hdir = bone_world('RightHand')
fwd = Vector((0, -1, 0)); fwd = (fwd - hdir * fwd.dot(hdir)).normalized()          # lama in avanti
frame = np.column_stack([np.array(fwd), np.array(hdir.cross(fwd)), np.array(hdir)])
# base del modello: (lama, laterale, spessore) -> mondo
R = Matrix(frame) @ Matrix(np.column_stack([-np.array(u), np.array(side), np.cross(-np.array(u), np.array(side))])).transposed()
palm = Vector((1, 0, 0)); palm = (palm - hdir * palm.dot(hdir)).normalized()     # il palmo destro guarda il corpo
place(sword, R, wrist + hdir * .08 + palm * .025, 'RightHand')
# Ritocco calibrato sulle clip: nel punto di massima estensione dell'affondo la lama
# formava 48° con l'avambraccio. La ruoto di 28° verso l'avambraccio nel sistema della
# mano (vale per tutte le clip): affondo più dritto, lama a riposo leggermente più bassa.
HM = (arm.matrix_world @ arm.data.bones['RightHand'].matrix_local).to_3x3().normalized()
blade_w = (sword.matrix_world.to_3x3() @ max((v.co for v in sword.data.vertices), key=lambda c: c.length)).normalized()
fore_l = Vector((-0.0809, 0.7392, 0.6687)); blade_l = HM.inverted() @ blade_w
axis_w = HM @ blade_l.cross(fore_l).normalized()
from mathutils import Quaternion
Rw = Quaternion(axis_w, math.radians(28)).to_matrix().to_4x4()
ctr = sword.matrix_world.translation.copy()
sword.matrix_world = Matrix.Translation(ctr) @ Rw @ Matrix.Translation(-ctr) @ sword.matrix_world
sword.name = 'Spada'

# --- Scudo: tondo da 70 cm, faccia (umbone) verso l'esterno dell'avambraccio ----
shield, co, c, ax = load_weapon(SRC / 'shield.glb', 9000)
n = ax[2]; d = (co - c) @ n; rad = np.linalg.norm((co - c) - np.outer(d, n), axis=1)
if d[rad < .15].max() < -d[rad < .15].min():
    n = -n  # n punta verso la faccia con l'umbone
s = .70 / (2 * rad.max())
for v in shield.data.vertices:
    v.co = (v.co - Vector(c)) * s
fa_head, fa_dir = bone_world('LeftForeArm'); hand_head, _ = bone_world('LeftHand')
mid = fa_head.lerp(hand_head, .55)
out = Vector((1, 0, .25)); out = (out - fa_dir * out.dot(fa_dir)).normalized()     # dorso dell'avambraccio
a1 = Vector(ax[0]); a1 = (a1 - Vector(n) * a1.dot(Vector(n))).normalized(); a2 = Vector(n).cross(a1)
R = Matrix(np.column_stack([np.array(fa_dir), np.array(out.cross(fa_dir)), np.array(out)])) @ \
    Matrix(np.column_stack([np.array(a1), np.array(a2), np.array(n)])).transposed()
place(shield, R, mid + out * .075, 'LeftForeArm')
shield.name = 'Scudo'

# --- Texture più leggere per il web --------------------------------------------
for img in bpy.data.images:
    lim = 2048 if any(img in [n.image for n in m.node_tree.nodes if n.type == 'TEX_IMAGE']
                      for m in body.data.materials if m and m.use_nodes) else 1024
    if img.size[0] > lim:
        img.scale(lim, lim * img.size[1] // img.size[0])
    img.pack()

bpy.context.scene.render.fps = 24  # stessa frequenza usata in importazione: tempi originali
bpy.ops.object.select_all(action='DESELECT')
for o in (arm, body, sword, shield):
    o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=str(OUT / 'anteos.glb'), export_format='GLB', use_selection=True,
                          export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True,
                          export_image_format='JPEG', export_image_quality=88)
(root / 'source_art/anteos').mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(root / 'source_art/anteos/anteos.blend'), compress=True)
print('ANTEOS_READY', [a.name for a in bpy.data.actions], flush=True)
