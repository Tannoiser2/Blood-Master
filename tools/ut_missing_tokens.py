"""Ut (scheda BLU, pagina fotografata) ha solo 12 pedine stampate: le 4 mancanti
(Parata destra, Schivata, Carica, Taglio destro) si ricostruiscono con i valori del gemello Nuchra
e con la figura di Ut presa dalle sue pedine (specchiata dove serve), testo e bordi ridisegnati.
Va lanciato dopo tools/build_catalog.py, che cancella e rigenera assets/tokens."""
from PIL import Image, ImageDraw, ImageFont, ImageOps
import math
T = 'assets/tokens/'
FONT = '/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf'
RED, GREEN, BLUE = (214, 48, 32), (20, 140, 60), (30, 110, 180)
def hexagon(w, h):
    return [(w * .25, 2), (w * .75, 2), (w - 2, h * .5), (w * .75, h - 2), (w * .25, h - 2), (2, h * .5)]
def edge(pts, k):   # 0 = alto, poi in senso orario
    order = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 0)]
    return pts[order[k][0]], pts[order[k][1]]
def token(name, src, mirror, label, atk, defense, sec=None, imbalance=None, red=(), green=(), blue=(), rest=False, fatigue=0):
    base = Image.open(T + 'ut_' + src + '.webp').convert('RGBA')
    if mirror: base = ImageOps.mirror(base)
    w, h = base.size; out = base.copy(); d = ImageDraw.Draw(out)
    pts = hexagon(w, h); paper = (246, 244, 236, 255)
    d.line(pts + [pts[0]], fill=paper, width=26)            # via i bordi colorati originali
    d.rectangle((0, 0, w, h * .25), fill=paper)              # via numeri e scritte stampati
    d.rectangle((0, h * .80, w, h), fill=paper)
    d.rectangle((0, 0, w * .30, h * .38), fill=paper)        # via lo sbilanciamento rosso (anche specchiato)
    d.rectangle((w * .70, 0, w, h * .38), fill=paper)
    m = Image.new('L', (w, h), 0); ImageDraw.Draw(m).polygon(pts, fill=255); out.putalpha(m)
    d = ImageDraw.Draw(out)
    for col, ks in ((RED, red), (GREEN, green), (BLUE, blue)):
        for k in ks:
            a, b = edge(pts, k); d.line([a, b], fill=col, width=11)
    big = ImageFont.truetype(FONT, 40); small = ImageFont.truetype(FONT, 26); lab = ImageFont.truetype(FONT, 30)
    d.text((w * .27, 18), '/' if atk is None else str(atk), fill=(30, 30, 30), font=big)
    dt = str(defense); d.text((w * .62, 18), dt, fill=(30, 30, 30), font=big)
    if sec is not None:
        tw = d.textlength(dt, font=big); d.text((w * .62 + tw, 34), '/' + str(sec), fill=(30, 30, 30), font=small)
    if imbalance is not None: d.text((w * .22, 66), '+%d' % imbalance, fill=RED, font=small)
    tw = d.textlength(label, font=lab); d.text(((w - tw) / 2, h - 58), label, fill=(30, 30, 30), font=lab)
    if rest: d.ellipse((w * .78, h - 54, w * .78 + 20, h - 34), outline=(30, 30, 30), width=3)
    for f in range(fatigue): d.ellipse((w * .78 + f * 22, h - 54, w * .78 + 20 + f * 22, h - 34), fill=(20, 20, 20))
    out.save(T + 'ut_' + name + '.webp', quality=93)
token('parry_r', 'parry_l', True, 'Parata Dx', None, 0, sec=3, blue=(0, 1), rest=True)
token('dodge', 'unbalanced', True, 'Schivata', None, 2, green=(2, 3, 4))
token('charge', 'run', False, 'Carica', 10, 5, imbalance=1, red=(0,), green=(5, 0, 1), fatigue=1)
token('right', 'left', True, 'Taglio Dx', 9, 4, imbalance=0, red=(0, 1))
