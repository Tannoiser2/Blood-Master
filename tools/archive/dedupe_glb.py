#!/usr/bin/env python3
"""Copia source_art in versione ridotta senza perdite: le texture incorporate nei GLB
(ripetute identiche in ogni clip di Meshy) vengono salvate una sola volta in textures/<hash>.<ext>
e i GLB le richiamano come immagini esterne (uri relativo). Blender e Godot le leggono così.
Uso: dedupe_glb.py <source_art> <destinazione>"""
import sys, os, json, struct, hashlib, shutil
src, dst = sys.argv[1], sys.argv[2]
tex = os.path.join(dst, 'textures'); os.makedirs(tex, exist_ok=True)
EXT = {'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp'}
def pad(b, c=b'\0'): return b + c * ((4 - len(b) % 4) % 4)
def dedupe(path, out):
    b = open(path, 'rb').read()
    jl = struct.unpack('<I', b[12:16])[0]; j = json.loads(b[20:20+jl])
    off = 20 + jl; binb = b''
    if off < len(b): bl = struct.unpack('<I', b[off:off+4])[0]; binb = b[off+8:off+8+bl]
    views = j.get('bufferViews', []); drop = set()
    for im in j.get('images', []):
        if 'bufferView' not in im: continue
        v = views[im['bufferView']]; o = v.get('byteOffset', 0); data = binb[o:o+v['byteLength']]
        h = hashlib.sha1(data).hexdigest()[:16]; name = h + '.' + EXT.get(im.get('mimeType', ''), 'bin')
        p = os.path.join(tex, name)
        if not os.path.exists(p): open(p, 'wb').write(data)
        drop.add(im.pop('bufferView')); im.pop('mimeType', None)
        im['uri'] = os.path.relpath(p, os.path.dirname(out)).replace(os.sep, '/')
    remap = {}; nb = bytearray(); nv = []
    for k, v in enumerate(views):
        if k in drop: continue
        o = v.get('byteOffset', 0); data = binb[o:o+v['byteLength']]
        while len(nb) % 16: nb.append(0)
        v = dict(v); v['byteOffset'] = len(nb); nb += data; remap[k] = len(nv); nv.append(v)
    j['bufferViews'] = nv
    for a in j.get('accessors', []):
        if 'bufferView' in a: a['bufferView'] = remap[a['bufferView']]
        sp = a.get('sparse')
        if sp:
            sp['indices']['bufferView'] = remap[sp['indices']['bufferView']]; sp['values']['bufferView'] = remap[sp['values']['bufferView']]
    if j.get('buffers'): j['buffers'][0]['byteLength'] = len(nb)
    jb = pad(json.dumps(j, separators=(',', ':')).encode(), b' '); nb = pad(bytes(nb))
    body = struct.pack('<I', len(jb)) + b'JSON' + jb + (struct.pack('<I', len(nb)) + b'BIN\0' + nb if nb else b'')
    open(out, 'wb').write(b'glTF' + struct.pack('<II', 2, 12 + len(body)) + body)
for root, dirs, files in os.walk(src):
    for f in files:
        if f.endswith('.blend1'): continue
        s = os.path.join(root, f); d = os.path.join(dst, os.path.relpath(s, src)); os.makedirs(os.path.dirname(d), exist_ok=True)
        if f.lower().endswith('.glb'): dedupe(s, d)
        else: shutil.copy2(s, d)
