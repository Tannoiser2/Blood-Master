"""Controlla che ogni carattere scritto nell'interfaccia esista nei caratteri tipografici del gioco.
Un simbolo che il carattere non contiene diventa un quadratino (sul web non c'è un carattere di sistema di riserva):
frecce, croci, spunte e pallini vanno DISEGNATI (main.gd: _draw_icon), non scritti.
uso: python3 tools/check_glyphs.py   (esce con 1 se trova caratteri mancanti)"""
import glob, json, re, sys
from fontTools.ttLib import TTFont
FONTS = ["assets/fonts/Alegreya.ttf", "assets/fonts/Cinzel.ttf", "assets/fonts/CinzelDecorative-Bold.ttf"]
cmaps = {f: set(TTFont(f).getBestCmap().keys()) for f in FONTS}
bad = {}
def check(text, where):
    for ch in text:
        if ord(ch) < 128 or ch in "\n\t": continue
        missing = [f.split("/")[-1] for f, cm in cmaps.items() if ord(ch) not in cm]
        # il titolo decorativo si usa solo per "BLOOD MASTER": conta solo se manca nei due caratteri del testo
        missing = [m for m in missing if not m.startswith("CinzelDecorative")]
        if missing: bad.setdefault(ch, set()).add(where)
for path in sorted(glob.glob("scripts/*.gd")):
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        code = line.split("#", 1)[0] if not re.search(r'"[^"]*#[^"]*"', line) else line
        for s in re.findall(r'"((?:[^"\\]|\\.)*)"', code): check(s, f"{path}:{n}")
cat = json.load(open("data/characters.json", encoding="utf-8"))
for cid, d in cat.items():
    check(d["name"] + d["title"], f"characters.json:{cid}")
    for m in d["moves"].values(): check(m["name"], f"characters.json:{cid}/{m['id']}")
if bad:
    for ch, where in sorted(bad.items()):
        print(f"MANCA {ch!r} (U+{ord(ch):04X}) in {len(where)} punti, es. {sorted(where)[:3]}")
    sys.exit(1)
print("OK: tutti i caratteri dell'interfaccia esistono in Alegreya e Cinzel")
