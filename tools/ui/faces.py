"""Ritaglia il volto di ogni miniatura (assets/reborn/minis) in assets/ui/faces/<id>.webp per le faccette."""
from PIL import Image
import os, sys
# centro del volto (x, y) e lato del riquadro, su immagini 640x640
FACES = {'anteos': (318, 122, 180), 'gandy': (272, 172, 190), 'gascor': (308, 80, 180), 'golem': (320, 120, 240),
         'kylvia': (292, 120, 170), 'nuchra': (335, 150, 190), 'ramok': (325, 105, 170), 'sanguinaria': (300, 120, 180),
         'shaara': (320, 80, 180), 'shannon': (280, 100, 180), 'skelos': (352, 112, 170), 'sketos': (330, 112, 170),
         'thorn': (322, 140, 190), 'ut': (320, 100, 190), 'zak': (292, 126, 160), 'zenyo': (280, 100, 180), 'ziggy': (300, 70, 200)}
root = sys.argv[1] if len(sys.argv) > 1 else '.'
out = os.path.join(root, 'assets/ui/faces'); os.makedirs(out, exist_ok=True)
for cid, (x, y, s) in FACES.items():
    im = Image.open(os.path.join(root, 'assets/reborn/minis', cid + '.webp')).convert('RGB')
    box = (max(0, x - s // 2), max(0, y - s // 2)); box = box + (box[0] + s, box[1] + s)
    im.crop(box).resize((128, 128), Image.LANCZOS).save(os.path.join(out, cid + '.webp'), quality=88)
