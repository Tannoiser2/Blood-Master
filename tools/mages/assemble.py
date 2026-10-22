"""Assembla un mago (Gandy, Thorn, Sanguinaria, Ziggynowskij) con rig e animazioni proprie.

Ziggynowskij è uno spirito fluttuante, non un umanoide: niente rig, solo il vortice
(ziggy_swirl.glb) ripulito e scalato; in Godot board3d.gd lo anima in modo procedurale.

Uso:  python tools/mages/assemble.py <id>      (modulo bpy)   id: gandy | thorn | sanguinaria | ziggy

Ingressi (source_art/<id>/meshy): <id>_rigged.glb e anim_*.glb generate dal catalogo
Meshy sul rig del mago stesso (incantesimi compresi). Gandy impugna il bastone
(staff.glb), Sanguinaria il tridente (trident.glb), calibrati come la spada di Anteos.
"""
import bpy, sys, math
import numpy as np
from mathutils import Vector, Matrix
from pathlib import Path

root = Path(__file__).resolve().parents[2]
CID = sys.argv[-1]
BASE = [('Riposo', 'riposo'), ('Camminata', 'walking'), ('Correre', 'running'), ('In guardia', 'guardia'),
        ('Avanzare', 'avanzare'), ('Carica', 'carica'), ('Schivata', 'schivata'), ('A terra', 'a_terra'),
        ('Rialzarsi', 'rialzarsi'), ('Sbilanciato', 'sbilanciato'), ('Concentrarsi', 'concentrarsi'), ('Morte', 'morte')]
CFG = {
    'gandy': dict(name='Gandy', prop='staff.glb', length=1.75, grip=.42, clips=[
        ('Fendente', 'fendente'), ('Taglio Sx', 'taglio_sx'), ('Parata Dx', 'parata_dx'), ('Bastone di fuoco', 'bastone_fuoco'),
        ('Scudo', 'scudo'), ('Vortice', 'vortice'), ('Sonno', 'sonno'), ('Palla di fuoco', 'palla_fuoco')]),
    'thorn': dict(name='Thorn', prop=None, clips=[
        ('Calcio', 'calcio'), ('Pugno', 'pugno'), ('Pustole', 'pustole'), ('Paura', 'paura'), ('Vecchiaia', 'vecchiaia'),
        ('Evocare', 'evocare'), ('Peste', 'peste')]),
    'sanguinaria': dict(name='Sanguinaria', prop='trident.glb', length=1.85, grip=.20, clips=[
        ('Affondo', 'affondo'), ('Parata Dx', 'parata_dx'), ('Parata Sx', 'parata_sx'), ('Muro', 'muro'),
        ('Teletrasporto', 'teletrasporto'), ('Trasformazione', 'trasformazione'), ('Fuoco vivo', 'fuoco_vivo'), ('Abisso', 'abisso')]),
    'ziggy': dict(name='Ziggynowskij', prop=None, clips=[
        ('Scossa', 'scossa'), ('Cura', 'cura'), ('Drenare', 'drenare'), ('Controllo', 'controllo'), ('Fulmine', 'fulmine'),
        ('Smaterializzare', 'smaterializzare'), ('Fluttuare', 'fluttuare')]),
    'golem': dict(name='Golem', prop=None, clips=[('Schianto', 'schianto')]),
    'skelos': dict(name='Skelos', prop='../../skelos/meshy/spear.glb', length=2.0, grip=.15, shield=True, clips=[
        ('Fendente', 'fendente'), ('Taglio Dx', 'taglio_dx'), ('Taglio Sx', 'taglio_sx'), ('Parata Dx', 'parata_dx'), ('Parata Sx', 'parata_sx')]),
    'sketos': dict(name='Sketos', prop='../../skelos/meshy/spear.glb', length=2.0, grip=.15, shield=True, clips=[
        ('Fendente', 'fendente'), ('Taglio Dx', 'taglio_dx'), ('Taglio Sx', 'taglio_sx'), ('Parata Dx', 'parata_dx'), ('Parata Sx', 'parata_sx')]),
}[CID]
SRC = root / f'source_art/{CID}/meshy'
OUT = root / f'assets/models/{CID}'
OUT.mkdir(parents=True, exist_ok=True)


def imported(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    return [o for o in bpy.data.objects if o not in before]


def rest(o):
    if o.animation_data:
        o.animation_data.action = None
    for p in o.pose.bones:
        p.matrix_basis = Matrix()
    bpy.context.view_layer.update()


bpy.ops.wm.read_factory_settings(use_empty=True)
if CID == 'ziggy':
    parts = [o for o in imported(SRC / 'ziggy_swirl.glb') if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    z = parts[0]; z.data.transform(z.matrix_world); z.matrix_world = Matrix(); z.name = 'Ziggynowskij'
    mod = z.modifiers.new('r', 'DECIMATE'); mod.ratio = min(1, 40000 / len(z.data.polygons))
    bpy.ops.object.modifier_apply(modifier=mod.name)
    co = np.array([v.co[:] for v in z.data.vertices]); lo, hi = co.min(0), co.max(0)
    s = 1.7 / (hi[2] - lo[2]); c = (lo + hi) / 2
    for v in z.data.vertices:
        v.co = (Vector(v.co) - Vector((c[0], c[1], lo[2]))) * s
    for img in bpy.data.images:
        if img.size[0] > 2048:
            img.scale(2048, 2048 * img.size[1] // img.size[0])
        img.pack()
    for m in z.data.materials:      # un filo di luce propria: è energia
        b = m.node_tree.nodes.get('Principled BSDF') if m and m.use_nodes else None
        if b:
            tex = next((n for n in m.node_tree.nodes if n.type == 'TEX_IMAGE'), None)
            if tex:
                m.node_tree.links.new(tex.outputs['Color'], b.inputs['Emission Color'])
            b.inputs['Emission Strength'].default_value = .35
    bpy.ops.object.select_all(action='DESELECT'); z.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUT / 'ziggy.glb'), export_format='GLB', use_selection=True,
                              export_image_format='JPEG', export_image_quality=88)
    print('READY ziggy', len(z.data.polygons), flush=True)
    sys.exit(0)
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

for name, fname in BASE + CFG['clips']:
    f = SRC / f'anim_{fname}.glb'
    if not f.exists():
        print('MANCA', fname, flush=True); continue
    o2 = imported(f)
    src = next(o for o in o2 if o.type == 'ARMATURE')
    act = src.animation_data.action; act.name = name; act.use_fake_user = True
    for o in o2:
        bpy.data.objects.remove(o)
for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.armatures):
    for d in list(block):
        if d.users == 0:
            block.remove(d)
rest(arm)


def bone_world(o, n):
    return o.matrix_world @ o.pose.bones[n].matrix


def pca(o):
    co = np.array([v.co[:] for v in o.data.vertices]); c = co.mean(0)
    return co, c, np.linalg.svd(co - c, full_matrices=False)[2]


export = [arm, body]
if CFG['prop']:
    # calibrazione della presa dalla spada di Anteos: la "lama" diventa la parte alta dell'asta
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
    for o in (a_rig, a_sword):
        bpy.data.objects.remove(o)
    parts = [x for x in imported(SRC / CFG['prop']) if x.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    w = parts[0]; w.data.transform(w.matrix_world); w.matrix_world = Matrix()
    mod = w.modifiers.new('r', 'DECIMATE'); mod.ratio = min(1, 8000 / len(w.data.polygons))
    bpy.ops.object.modifier_apply(modifier=mod.name)
    co, c, ax = pca(w); u = ax[0]; t = (co - c) @ u
    radial = np.linalg.norm((co - c) - np.outer(t, u), axis=1); L0 = t.max() - t.min()
    top = radial[t > t.max() - L0 * .2].mean(); bot = radial[t < t.min() + L0 * .2].mean()
    if bot > top:                      # la testa (sfera o rebbi) è la parte più larga: va in alto
        u = -u; t = -t
    s = CFG['length'] / L0; grip_c = t.min() + (t.max() - t.min()) * CFG['grip']
    for v, p in zip(w.data.vertices, co):
        v.co = (Vector(p) - Vector(c) - Vector(u) * grip_c) * s
    bG = Vector(u); sG = Vector(ax[1]); sG = (sG - bG * sG.dot(bG)).normalized()
    BG = Matrix((bG, sG, bG.cross(sG))).transposed()
    rot = REL.to_3x3().normalized() @ BA @ BG.transposed()
    w.parent = arm; w.parent_type = 'BONE'; w.parent_bone = 'RightHand'; bpy.context.view_layer.update()
    w.matrix_world = bone_world(arm, 'RightHand') @ Matrix.Translation(REL.translation) @ rot.to_4x4() @ Matrix.Scale(REL.to_scale()[0], 4)
    # due impugnature: "ArmaAzione" come la spada (testa in avanti: incantesimi, colpi, parate)
    # e "Arma" raddrizzata per riposo, guardia e spostamenti; Godot mostra quella giusta per la clip
    w2 = w.copy(); w2.data = w.data; bpy.context.scene.collection.objects.link(w2)
    w2.parent = arm; w2.parent_type = 'BONE'; w2.parent_bone = 'RightHand'; w2.matrix_world = w.matrix_world.copy()
    w2.name = 'ArmaAzione'; export.append(w2)
    # a riposo il bastone (o il tridente) sta dritto con la testa in alto, come un bastone da viaggio:
    # ruoto l'impugnatura attorno al pugno finché, nella clip Riposo, l'asta punta verso l'alto
    act = bpy.data.actions['Riposo']; arm.animation_data.action = act
    try:
        arm.animation_data.action_slot = act.slots[0]
    except Exception:
        pass
    bpy.context.scene.frame_set(int(act.frame_range[0])); bpy.context.view_layer.update()
    M = w.matrix_world.copy(); d = (M.to_3x3() @ Vector(u)).normalized()
    up = Vector((0, 0, 1)); target = (up + d * .25).normalized()   # quasi verticale, appena inclinato come era
    Q = d.rotation_difference(target).to_matrix().to_4x4()
    newM = Matrix.Translation(M.translation) @ Q @ Matrix.Translation(-M.translation) @ M
    REL2 = bone_world(arm, 'RightHand').inverted() @ newM
    rest(arm); w.matrix_world = bone_world(arm, 'RightHand') @ REL2
    print('RADDRIZZATO', round(math.degrees(d.angle(target)), 1), flush=True)
    w.name = 'Arma'; export.append(w)

if CFG.get('shield'):
    # scudo tondo sull'avambraccio sinistro, nella stessa posizione dello scudo di Gascor
    with bpy.data.libraries.load(str(root / 'source_art/gascor/gascor-meshy.blend'), link=False) as (sd, dd):
        dd.objects = [n for n in sd.objects if n in ('Gascor_Rig', 'Scudo')]
    for o in dd.objects:
        bpy.context.scene.collection.objects.link(o)
    g_rig = bpy.data.objects['Gascor_Rig']; g_sh = bpy.data.objects['Scudo']; rest(g_rig)
    W = np.array([(g_sh.matrix_world @ v.co)[:] for v in g_sh.data.vertices]); cg = W.mean(0)
    axg = np.linalg.svd(W - cg, full_matrices=False)[2]; ng = axg[2]; tg = (W - cg) @ ng
    if tg.max() + tg.min() < 0:
        ng = -ng                                  # la normale verso il lato bombato (fuori)
    upg = np.array([0, 0, 1.0]); upg = upg - ng * upg.dot(ng); upg /= np.linalg.norm(upg)
    sizeg = np.ptp((W - cg) @ axg[0])
    G_bone = bone_world(g_rig, 'LeftForeArm').copy()
    for o in (g_rig, g_sh):
        bpy.data.objects.remove(o)
    parts = [x for x in imported(root / 'source_art/skelos/meshy/shield.glb') if x.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for q in parts:
        q.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    sh = parts[0]; sh.data.transform(sh.matrix_world); sh.matrix_world = Matrix()
    mod = sh.modifiers.new('r', 'DECIMATE'); mod.ratio = min(1, 6000 / len(sh.data.polygons)); bpy.ops.object.modifier_apply(modifier=mod.name)
    co = np.array([v.co[:] for v in sh.data.vertices]); cn = co.mean(0)
    axn = np.linalg.svd(co - cn, full_matrices=False)[2]; nn = axn[2]; tn = (co - cn) @ nn
    if tn.max() + tn.min() < 0:
        nn = -nn
    upn = np.array([0, 0, 1.0]); upn = upn - nn * upn.dot(nn)
    if np.linalg.norm(upn) < .1:
        upn = axn[0]
    upn /= np.linalg.norm(upn)
    Bn = np.array([upn, nn, np.cross(upn, nn)]); Bg = np.array([upg, ng, np.cross(upg, ng)])
    scale = .62 / np.ptp((co - cn) @ axn[0])          # 62 cm di diametro
    Wn = ((co - cn) @ Bn.T) @ Bg * scale + cg         # nella posa di Gascor
    Mrel = bone_world(arm, 'LeftForeArm') @ G_bone.inverted()
    for v, p in zip(sh.data.vertices, Wn):
        v.co = Mrel @ Vector(p)
    sh.parent = arm; sh.parent_type = 'BONE'; sh.parent_bone = 'LeftForeArm'; bpy.context.view_layer.update()
    sh.matrix_world = Matrix()
    sh.name = 'Scudo'; export.append(sh)

for img in bpy.data.images:
    used_by_body = any(img in [nd.image for nd in m.node_tree.nodes if nd.type == 'TEX_IMAGE']
                       for m in body.data.materials if m and m.use_nodes)
    lim = 2048 if used_by_body else 1024
    if img.size[0] > lim:
        img.scale(lim, lim * img.size[1] // img.size[0])
    img.pack()

bpy.context.scene.render.fps = 24
bpy.ops.object.select_all(action='DESELECT')
for o in export:
    o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=str(OUT / f'{CID}.glb'), export_format='GLB', use_selection=True,
                          export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True,
                          export_image_format='JPEG', export_image_quality=88)
bpy.ops.wm.save_as_mainfile(filepath=str(root / f'source_art/{CID}/{CID}.blend'), compress=True)
print('READY', CID, sorted(a.name for a in bpy.data.actions), flush=True)
