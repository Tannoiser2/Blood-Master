"""Ricolora la veste di un personaggio direttamente nel .glb (texture del corpo).

Uso: python3 tools/heroes/recolor.py zenyo

Zenyo: le vesti chiare (bianco/grigio/verde acqua) diventano blu-turchese come nelle
carte originali; pelle, legno, capelli e cuoio restano com'erano.
"""
import io, json, struct, sys
from pathlib import Path
import numpy as np
from PIL import Image

root = Path(__file__).resolve().parents[2]


def rgb_to_hsv(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx = a.max(-1); mn = a.min(-1); d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rm = m & (mx == r); gm = m & (mx == g) & ~rm; bm = m & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6; h[gm] = (b - r)[gm] / d[gm] + 2; h[bm] = (r - g)[bm] / d[bm] + 4
    h = h / 6; s = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0)
    return h, s, mx


def hsv_to_rgb(h, s, v):
    i = np.floor(h * 6).astype(int) % 6; f = h * 6 - np.floor(h * 6)
    p = v * (1 - s); q = v * (1 - f * s); t = v * (1 - (1 - f) * s)
    out = np.zeros(h.shape + (3,))
    for k, (a, b, c) in enumerate([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]):
        m = i == k; out[m, 0] = a[m]; out[m, 1] = b[m]; out[m, 2] = c[m]
    return out


def zenyo(img):
    a = np.asarray(img.convert('RGB')).astype(float) / 255
    h, s, v = rgb_to_hsv(a)
    hue = h * 360
    skin_wood = (hue > 4) & (hue < 60) & (s > .1)                               # pelle (anche la testa rasata), legno, cuoio
    white = (s < .2) & (v > .38) & ~skin_wood                                   # sottoveste chiara -> azzurro chiaro
    teal = (hue > 140) & (hue < 230) & (v > .15) & ~white & ~skin_wood          # veste verde acqua -> blu
    mp = Path(__file__).with_name('zenyo_headmask.png')
    if mp.exists():   # testa e collo (dalla geometria, tools/heroes/headmask.py): restano com'erano
        head = np.asarray(Image.open(mp).convert('L').resize(img.size)) > 40
        white &= ~head; teal &= ~head
    nh = np.where(white | teal, 205 / 360, h)
    ns = np.where(white, np.clip(.22 + (1 - v) * .4, 0, .6), np.where(teal, np.clip(.55 + s * .3, 0, .85), s))
    nv = np.where(white, v * .93, np.where(teal, v * .78, v))
    out = hsv_to_rgb(nh % 1, ns, nv)
    return Image.fromarray((out * 255).astype(np.uint8)), (white | teal).mean()


def patch_glb(path, fn):
    data = path.read_bytes()
    n = struct.unpack('<I', data[12:16])[0]; js = json.loads(data[20:20 + n])
    off = 20 + n; bl = struct.unpack('<I', data[off:off + 4])[0]; bin_ = bytearray(data[off + 8:off + 8 + bl])
    body = None   # l'immagine del colore di base del materiale del corpo (la più grande usata come baseColor)
    for m in js.get('materials', []):
        t = m.get('pbrMetallicRoughness', {}).get('baseColorTexture')
        if t is not None:
            img = js['textures'][t['index']]['source']
            bv = js['bufferViews'][js['images'][img]['bufferView']]
            if body is None or bv['byteLength'] > js['bufferViews'][js['images'][body]['bufferView']]['byteLength']:
                body = img
    views = js['bufferViews']; target = js['images'][body]['bufferView']
    chunks = []
    for i, bv in enumerate(views):
        raw = bytes(bin_[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']])
        if i == target:
            im = Image.open(io.BytesIO(raw)); new, frac = fn(im)
            buf = io.BytesIO(); new.save(buf, 'JPEG' if js['images'][body].get('mimeType') == 'image/jpeg' else 'PNG', quality=90)
            raw = buf.getvalue(); print('ricolorata immagine', body, 'quota veste %.0f%%' % (frac * 100))
            new.save(path.with_name(path.stem + '_texture_0.jpg'), 'JPEG', quality=90)   # copia estratta usata da Godot
        chunks.append(raw)
    out = bytearray(); 
    for bv, raw in zip(views, chunks):
        while len(out) % 4: out.append(0)
        bv['byteOffset'] = len(out); bv['byteLength'] = len(raw); out += raw
    while len(out) % 4: out.append(0)
    js['buffers'][0]['byteLength'] = len(out)
    jb = json.dumps(js, separators=(',', ':')).encode()
    while len(jb) % 4: jb += b' '
    total = 12 + 8 + len(jb) + 8 + len(out)
    path.write_bytes(struct.pack('<III', 0x46546C67, 2, total) + struct.pack('<II', len(jb), 0x4E4F534A) + jb
                     + struct.pack('<II', len(out), 0x004E4942) + bytes(out))


if __name__ == '__main__':
    cid = sys.argv[1]
    patch_glb(root / f'assets/models/{cid}/{cid}.glb', {'zenyo': zenyo}[cid])
