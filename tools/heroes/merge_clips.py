"""Unisce i tre montaggi di un corpo della forgia in un solo modello per Godot.

Uso:  python tools/heroes/merge_clips.py <id>      (modulo bpy)   id: f_barbaro | f_nomade | f_predone | f_cavaliere

source_art/<id>/build/1h.glb (clip di spada a una mano), lancia.glb e pesante.glb (stesse clip
con le mani sull'asta, generate da tools/heroes/assemble.py con BM_VARIANT): la mesh e lo scheletro
vengono dal primo, le clip degli altri due entrano con il suffisso " lancia" e " 2h".
La mappa 3D sceglie il gruppo di clip secondo l'arma montata (board3d._clip_for).
"""
import bpy, sys, re
from pathlib import Path
root = Path(__file__).resolve().parents[2]
CID = sys.argv[-1]
B = root / f'source_art/{CID}/build'
bpy.ops.wm.read_factory_settings(use_empty=True)

def imported(path):
    before = set(bpy.data.objects); acts = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=str(path))
    return [o for o in bpy.data.objects if o not in before], [a for a in bpy.data.actions if a not in acts]

objs, base_acts = imported(B / '1h.glb')
arm = next(o for o in objs if o.type == 'ARMATURE')
for a in base_acts:
    a.name = a.name.split('|')[-1] if '|' in a.name else a.name
    a.use_fake_user = True
for fname, suffix in (('lancia.glb', ' lancia'), ('pesante.glb', ' 2h')):
    o2, acts = imported(B / fname)
    for a in acts:
        a.name = re.sub(r'\.\d{3}$', '', a.name.split('|')[-1]) + suffix
        a.use_fake_user = True
    for o in o2:
        bpy.data.objects.remove(o)
# ogni clip legata allo scheletro rimasto
for a in bpy.data.actions:
    arm.animation_data_create(); arm.animation_data.action = a
    try:
        arm.animation_data.action_slot = a.slots[0]
    except Exception:
        pass
    bpy.context.scene.frame_set(0)
arm.animation_data.action = None
OUT = root / f'assets/models/{CID}'; OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='DESELECT')
for o in objs:
    if o.type in ('ARMATURE', 'MESH'):
        o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.context.scene.render.fps = 24
bpy.ops.export_scene.gltf(filepath=str(OUT / f'{CID}.glb'), export_format='GLB', use_selection=True,
                          export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True,
                          export_image_format='JPEG', export_image_quality=88)
print('READY', CID, len(bpy.data.actions), sorted(a.name for a in bpy.data.actions)[:6], flush=True)
