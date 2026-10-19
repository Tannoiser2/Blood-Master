from PIL import Image,ImageDraw
import numpy as np,json
canvas=Image.new('RGB',(1956,2736))
for n,xy in [(3,(0,0)),(4,(978,0)),(1,(0,1368)),(2,(978,1368))]:canvas.paste(Image.open(f'assets/arena/part-{n}.webp'),xy)
canvas.save('assets/arena/arena.webp',quality=94)
# The grid is calibrated independently in the two vertical scan halves; the
# logical coordinates remain continuous across the scan seam.
cells=[]
for q in range(9):
 for r in range(-6,14):
  x=242+184*q;y=425+213*(r+q/2)
  if not(100<x<1856 and 90<y<2640):continue
  # Lower scans have a small scanner offset; interpolate to the common grid.
  py=y if y<1368 else y-18
  patch=np.array(canvas.crop((int(x-35),int(py-35),int(x+35),int(py+35)))).astype(float)
  orange=((patch[:,:,0]>140)&(patch[:,:,0]>patch[:,:,1]*1.14)&(patch[:,:,1]>65)&(patch[:,:,2]<patch[:,:,1]*.9)).mean()
  if orange>.60:cells.append({'q':q,'r':r,'x':x,'y':py,'entry':False})
# Tiled entry hexes at the four shoulders of the arena. Calibrated to the
# adjoining printed hexes; other cobblestones remain outside the arena.
for q,r in [(3,-2),(5,-3),(1,3),(7,0),(1,5),(7,2),(3,8),(5,7)]:
 if not any(c['q']==q and c['r']==r for c in cells):
  y=425+213*(r+q/2);cells.append({'q':q,'r':r,'x':242+184*q,'y':y if y<1368 else y-18,'entry':True})
Path=None
open('data/arena.json','w').write(json.dumps({'width':1956,'height':2736,'radius':121,'cells':cells},indent=2))
d=ImageDraw.Draw(canvas)
for c in cells:
 x,y=c['x'],c['y'];d.ellipse((x-12,y-12,x+12,y+12),fill='cyan' if c['entry'] else 'white');d.text((x-22,y+16),f"{c['q']},{c['r']}",fill='black')
canvas.thumbnail((1000,1400));canvas.save('tmp/arena-grid.jpg')
print(len(cells),'playable hexes')
