# Texture del tema fantasy (stile Reborn): pannelli con doppia cornice d'oro e fregi agli angoli,
# pulsanti di cuoio scuro bordati d'oro, pulsante principale dorato, sfondo scuro con vignettatura.
import random, math
from PIL import Image, ImageDraw, ImageFilter
OUT="assets/ui/fantasy/"
random.seed(7)
GOLD=(214,170,90);GOLD_D=(140,100,45);GOLD_L=(245,215,140)
def noise(img,amount,blur=0):
    w,h=img.size;n=Image.effect_noise((w,h),amount).convert("L")
    if blur:n=n.filter(ImageFilter.GaussianBlur(blur))
    px=img.load();q=n.load()
    for y in range(h):
        for x in range(w):
            r,g,b,a=px[x,y];d=(q[x,y]-128)*.12
            px[x,y]=(max(0,min(255,int(r+d))),max(0,min(255,int(g+d*.9))),max(0,min(255,int(b+d*.8))),a)
    return img
def vgrad(w,h,top,bot):
    img=Image.new("RGBA",(w,h));d=ImageDraw.Draw(img)
    for y in range(h):
        t=y/(h-1);d.line([(0,y),(w,y)],fill=tuple(int(top[i]+(bot[i]-top[i])*t) for i in range(3))+(255,))
    return img
def corner(d,x,y,sx,sy,s):
    # fregio d'angolo: rombo e due riccioli
    d.polygon([(x+sx*s*.55,y+sy*s*.1),(x+sx*s*.85,y+sy*s*.4),(x+sx*s*.55,y+sy*s*.7),(x+sx*s*.25,y+sy*s*.4)],fill=GOLD,outline=GOLD_D)
    d.polygon([(x+sx*s*.55,y+sy*s*.28),(x+sx*s*.67,y+sy*s*.4),(x+sx*s*.55,y+sy*s*.52),(x+sx*s*.43,y+sy*s*.4)],fill=GOLD_L)
def panel(name,base_top,base_bot,size=128,m=22):
    img=vgrad(size,size,base_top,base_bot);noise(img,40,1)
    d=ImageDraw.Draw(img)
    d.rectangle([0,0,size-1,size-1],outline=(20,12,8),width=2)
    d.rectangle([3,3,size-4,size-4],outline=GOLD_D,width=1)
    d.rectangle([4,4,size-5,size-5],outline=GOLD,width=2)
    d.rectangle([8,8,size-9,size-9],outline=GOLD_D,width=1)
    for (x,y,sx,sy) in [(0,0,1,1),(size,0,-1,1),(0,size,1,-1),(size,size,-1,-1)]:corner(d,x,y,sx,sy,m)
    img.putpixel((0,0),(0,0,0,0));img.putpixel((size-1,0),(0,0,0,0));img.putpixel((0,size-1),(0,0,0,0));img.putpixel((size-1,size-1),(0,0,0,0))
    img.save(OUT+name)
def button(name,top,bot,border,inner,w=96,h=48):
    img=vgrad(w,h,top,bot);noise(img,30,0.6)
    d=ImageDraw.Draw(img)
    d.rectangle([0,0,w-1,h-1],outline=(15,10,6),width=1)
    d.rectangle([1,1,w-2,h-2],outline=border,width=2)
    d.line([(4,4),(w-5,4)],fill=inner,width=1)   # riflesso in alto
    for (x,y) in [(2,2),(w-3,2),(2,h-3),(w-3,h-3)]:   # borchie agli angoli (dentro i margini: non si stirano)
        d.ellipse([x-1,y-1,x+1,y+1],fill=border)
    img.save(OUT+name)
panel("panel.png",(40,28,20),(24,16,11))
panel("panel_light.png",(62,44,30),(40,28,19))
button("btn.png",(74,34,26),(42,18,14),GOLD_D,(120,70,50))
button("btn_hover.png",(110,48,34),(64,26,18),GOLD,(170,100,70))
button("btn_pressed.png",(38,16,12),(60,26,20),GOLD,(80,40,30))
button("btn_gold.png",(250,222,150),(196,150,70),(110,70,25),(255,245,200))
button("btn_gold_hover.png",(255,236,175),(220,172,90),(90,55,15),(255,250,220))
button("btn_on.png",(214,170,90),(160,115,50),(250,225,150),(255,240,190))
# sfondo: cuoio scurissimo, vignettatura e una trama di rombi appena percepibile
W,H=1600,1000
bg=vgrad(W,H,(28,19,14),(14,9,7));noise(bg,60,2)
d=ImageDraw.Draw(bg,"RGBA")
for y in range(-60,H+60,60):
    for x in range(-60,W+60,60):
        o=30 if (y//60)%2 else 0
        pass
v=Image.new("L",(W,H),0);vd=ImageDraw.Draw(v)
for k in range(60):
    t=k/60;vd.ellipse([-W*.25+t*W*.3,-H*.25+t*H*.3,W*1.25-t*W*.3,H*1.25-t*H*.3],fill=int(255*t**1.6))
v=v.filter(ImageFilter.GaussianBlur(60))
black=Image.new("RGBA",(W,H),(0,0,0,255));bg=Image.composite(bg,black,v)
bg.convert("RGB").save(OUT+"bg.webp",quality=88)
print("ok")
