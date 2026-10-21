"""Unisce i fotogrammi di tools/gif/record.gd in una GIF per animazione: GIF/<personaggio>/<clip>.gif"""
import sys, re
from pathlib import Path
from collections import defaultdict
from PIL import Image
src, dst = Path(sys.argv[1]), Path(sys.argv[2])
for cdir in sorted(p for p in src.iterdir() if p.is_dir()):
    clips = defaultdict(list)
    for f in sorted(cdir.glob('*.png')):
        m = re.match(r'(.+)__(\d+)\.png$', f.name)
        if m: clips[m.group(1)].append(f)
    (dst / cdir.name).mkdir(parents=True, exist_ok=True)
    for clip, fs in clips.items():
        ims = [Image.open(f).convert('RGB').quantize(colors=128, method=Image.Quantize.MEDIANCUT) for f in fs]
        ims[0].save(dst / cdir.name / f'{clip}.gif', save_all=True, append_images=ims[1:], duration=int(1000 / 12), loop=0, optimize=True)
    print(cdir.name, len(clips))
