"""Rana della Trasformazione di Sanguinaria: source_art/frog/frog_raw.glb -> assets/models/frog/frog.glb"""
import bpy
import numpy as np
from mathutils import Vector, Matrix
from pathlib import Path
root = Path(__file__).resolve().parents[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(root / 'source_art/frog/frog_raw.glb'))
parts = [o for o in bpy.data.objects if o.type == 'MESH']
for o in parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
if len(parts) > 1:
    bpy.ops.object.join()
f = parts[0]; f.data.transform(f.matrix_world); f.matrix_world = Matrix(); f.name = 'Rana'
m = f.modifiers.new('r', 'DECIMATE'); m.ratio = min(1, 8000 / len(f.data.polygons)); bpy.ops.object.modifier_apply(modifier=m.name)
co = np.array([v.co[:] for v in f.data.vertices]); lo, hi = co.min(0), co.max(0); s = .5 / (hi[2] - lo[2]); c = (lo + hi) / 2
for v in f.data.vertices:
    v.co = (Vector(v.co) - Vector((c[0], c[1], lo[2]))) * s
for img in bpy.data.images:
    if img.size[0] > 1024:
        img.scale(1024, 1024 * img.size[1] // img.size[0])
    img.pack()
(root / 'assets/models/frog').mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(root / 'assets/models/frog/frog.glb'), export_format='GLB', use_selection=True, export_image_format='JPEG')
print('READY frog')
