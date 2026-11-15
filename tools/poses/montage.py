"""Unisce i fotogrammi di tools/poses/strip.gd in un foglio per clip: riga in alto vista dall'alto, riga sotto di fronte.
uso: python3 tools/poses/montage.py tmp/strip [scala]"""
import sys, glob, os, collections
from PIL import Image, ImageDraw
d = sys.argv[1]; scale = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
groups = collections.defaultdict(lambda: collections.defaultdict(list))
for f in sorted(glob.glob(os.path.join(d, "*__*_??.png"))):
    base = os.path.basename(f)[:-4]
    cid, clip, rest = base.split("__")
    view = rest.rsplit("_", 1)[0]
    groups[(cid, clip)][view].append(f)
for (cid, clip), views in groups.items():
    rows = []
    for view in ("alto", "fronte"):
        ims = [Image.open(p).convert("RGB") for p in views.get(view, [])]
        if not ims: continue
        w, h = ims[0].size
        row = Image.new("RGB", (w * len(ims), h))
        for i, im in enumerate(ims): row.paste(im, (i * w, 0))
        rows.append(row)
    W = max(r.size[0] for r in rows); H = sum(r.size[1] for r in rows)
    sheet = Image.new("RGB", (W, H + 22), (20, 20, 20))
    y = 22
    for r in rows: sheet.paste(r, (0, y)); y += r.size[1]
    ImageDraw.Draw(sheet).text((6, 4), f"{cid} - {clip} (sopra: dall'alto, fronte in basso; sotto: di fronte)", fill=(255, 255, 255))
    if scale != 1.0: sheet = sheet.resize((int(sheet.size[0] * scale), int(sheet.size[1] * scale)))
    sheet.save(os.path.join(d, f"_{cid}__{clip}.png"))
    print("foglio", cid, clip)
