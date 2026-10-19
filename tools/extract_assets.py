"""Extract printed components from scans; retain original artwork and source coordinates."""
from pathlib import Path
import json, math
import cv2,numpy as np
from PIL import Image,ImageDraw
import pymupdf
root=Path('.')
manifest=[]
for f in sorted(Path('tmp/source').glob('*.png')):
 if f.stem.endswith('-1'):continue
 im=cv2.imread(str(f));gray=cv2.cvtColor(im,cv2.COLOR_BGR2GRAY)
 mask=cv2.threshold(gray,175,255,cv2.THRESH_BINARY_INV)[1]
 mask=cv2.morphologyEx(mask,cv2.MORPH_CLOSE,np.ones((7,7),np.uint8))
 contours,_=cv2.findContours(mask,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
 found=[]
 for c in contours:
  x,y,w,h=cv2.boundingRect(c);area=cv2.contourArea(c)
  if 270<w<550 and 270<h<470 and area>w*h*.55:
   found.append((x,y,w,h))
 found.sort(key=lambda b:(round(b[0]/150),b[1]))
 print(f.stem,len(found),found)
 for n,(x,y,w,h) in enumerate(found):
  pad=5;x=max(0,x-pad);y=max(0,y-pad);w+=2*pad;h+=2*pad
  tile=Image.fromarray(cv2.cvtColor(im[y:y+h,x:x+w],cv2.COLOR_BGR2RGB)).convert('RGBA')
  # Exact hexagonal clipping removes scanner paper outside the printed piece.
  alpha=Image.new('L',tile.size,0);d=ImageDraw.Draw(alpha);d.polygon([(w*.25,3),(w*.75,3),(w-3,h*.5),(w*.75,h-3),(w*.25,h-3),(3,h*.5)],fill=255)
  tile.putalpha(alpha);tile.thumbnail((400,350))
  name=f'{f.stem}-{n:02d}';tile.save('assets/tokens/'+name+'.webp',quality=92)
  manifest.append({'id':name,'source':f.stem,'rect':[x,y,w,h]})
 Path('tmp/source/'+f.stem+'.json').write_text(json.dumps(found))
Path('data/token_sources.json').write_text(json.dumps(manifest,indent=2))
# Readable source rule pages in the in-game reference book.
doc=pymupdf.open('Blood Master - Regole.pdf')
for i,p in enumerate(doc):
 pix=p.get_pixmap(matrix=pymupdf.Matrix(2,2));im=Image.frombytes('RGB',[pix.width,pix.height],pix.samples)
 im.save(f'assets/rules/page-{i+1:02d}.webp',quality=88)
# Arena: upper-left 3, upper-right 4, lower-left 1, lower-right 2.
# Keep each original quadrant independently addressable for alignment adjustments.
for i in range(1,5):
 im=Image.open(f'tmp/pdfs/arena-{i}.jpg').crop((0,0,978,1368))
 im.save(f'assets/arena/part-{i}.webp',quality=94)
