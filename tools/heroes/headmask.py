"""Maschera della testa nella texture del corpo (per non ricolorare pelle e capelli).
Uso: python tools/heroes/headmask.py <modello.glb> <maschera.png>   (modulo bpy)"""
import bpy, sys
from PIL import Image, ImageDraw
src,out=sys.argv[-2],sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
body=max((o for o in bpy.data.objects if o.type=='MESH'),key=lambda o:len(o.data.vertices))
me=body.data;mw=body.matrix_world
co=[mw@v.co for v in me.vertices];zs=[c.z for c in co];zmin,zmax=min(zs),max(zs);H=zmax-zmin
cx=sum(c.x for c in co)/len(co);cy=sum(c.y for c in co)/len(co)
uv=me.uv_layers.active.data
N=2048;im=Image.new('L',(N,N),0);d=ImageDraw.Draw(im)
cnt=0
for p in me.polygons:
    vs=[co[i] for i in p.vertices]
    if min(v.z for v in vs)>zmin+H*.86 and max(abs(v.x-cx) for v in vs)<H*.08 and max(abs(v.y-cy) for v in vs)<H*.08:
        pts=[(uv[li].uv.x*N,(1-uv[li].uv.y)*N) for li in p.loop_indices];d.polygon(pts,fill=255);cnt+=1
im.save(out);print('FACCE TESTA',cnt)
