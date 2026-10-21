"""Catalog manually transcribed from original scans, with source rectangles for audit."""
from pathlib import Path
from PIL import Image,ImageDraw
import json,math
P=Path('assets/tokens')
for f in P.glob('*.webp'): f.unlink()
characters={};moves={};sources={}
NAMES={'guard':'In guardia','advance':'Avanzare','run':'Correre','rise':'Rialzarsi','roll':'Rotolare','unbalanced':'Sbilanciato','down':'A terra','parry_r':'Parata destra','parry_l':'Parata sinistra','dodge':'Schivata','charge':'Carica','right':'Taglio destro','left':'Taglio sinistro','thrust':'Affondo','again':'Ancora','cleave':'Fendente','kick':'Calcio','sweep':'Spazzata','meditate':'Meditazione','load':'Incoccare','shoot':'Tirare','weapon':'Cambio arma','spin':'Roteare','concentrate':'Concentrazione','float':'Fluttuare','dematerialize':'Smaterializzazione','shock':'Shock','heal':'Rigenerazione','drain':'Risucchio','control':'Controllo mentale','lightning':'Fulmine magico','pustules':'Pustole venefiche','fear':'Paura','age':'Invecchiamento','summon':'Evocazione','plague':'Peste','firestaff':'Bastone di fuoco','shield':'Scudo di energia','vortex':'Gorgo magico','sleep':'Sonno','fireball':'Palla di fuoco','wall':'Muro infernale','teleport':'Teletrasporto','transform':'Trasformazione','livingfire':'Fuoco vivente','abyss':'Abisso infernale','pieces':'In pezzi','punch':'Pugno'}
# Clockwise directions, 0 = forward/up.
F=[5,0,1];ALL=list(range(6));BACK=[2,3,4]
def tile(source,c,r,name,custom=None,rotate=0):
 im=Image.open('tmp/source/'+source+'.png')
 if custom: x,y,w,h=custom
 else:
  dx=29 if source in ['blu-2','rossi-5'] else (12 if source.startswith('backfire') else 0)
  x=464+400*c+dx;y=68+425*r+(212 if c%2 else 0);w=430;h=373
 box=(x,y,x+w,y+h);t=im.crop(box).convert('RGBA')
 a=Image.new('L',t.size,0);ImageDraw.Draw(a).polygon([(w*.25,2),(w*.75,2),(w-2,h*.5),(w*.75,h-2),(w*.25,h-2),(2,h*.5)],fill=255)
 t.putalpha(a)
 if rotate:t=t.rotate(rotate,expand=True)
 t.thumbnail((400,350));t.save(P/(name+'.webp'),quality=93)
 sources[name]={'page':source,'rect':list(box),'rotation':rotate}
 return 'res://assets/tokens/'+name+'.webp'
def add(ch,id,source,c,r,atk,defense,red=[],green=[],blue=[],fatigue=0,rest=False,imbalance=None,secondary=None,custom=None,rotate=0,**kw):
 m={'id':id,'name':NAMES.get(id,id),'attack':atk,'defense':defense,'red':red,'green':green,'blue':blue,'fatigue':fatigue,'rest':rest,'imbalance':imbalance,'secondary':defense if secondary is None else secondary,'texture':tile(source,c,r,ch+'_'+id,custom,rotate)};m.update(kw)
 moves.setdefault(ch,{})[id]=m
 return m
sprints={
 'monk':[[1,0,0,1],[2,1,1,1],[3,1,1,2],[5,1,3,2],[6,2,4,3]],
 'sword':[[0,1,0,1],[1,1,1,2],[2,2,2,3]],
 'spear':[[1,0,0,2],[2,1,1,3],[3,1,2,5]],
 'archer':[[0,0,0,0],[0,1,1,0],[1,1,2,1],[1,2,3,2]],
 'heavy':[[2,1,1,3],[5,1,2,6]],
 'gandy':[[0,0,0,0],[1,1,1,1],[1,2,2,1]],
 'thorn':[[0,1,1,0],[1,2,2,1]],
 'sanguinaria':[[1,0,0,1],[1,0,0,2],[2,1,1,3],[3,1,2,4]],
 'skeleton':[[0,0,0,1],[1,0,1,1],[2,0,1,2],[2,0,2,2]]}
def char(id,name,title,kind,team,size,hp,sprint,armor,recovery,card):
 characters[id]={'id':id,'name':name,'title':title,'kind':kind,'team':team,'size':size,'hp':hp,'sprint':sprint,'armor':armor,'recovery':recovery,'sprints':sprints.get(kind,[]),'card':'res://assets/cards/'+id+'.webp','mage':kind in ['gandy','thorn','sanguinaria','ziggy'],'source_card':card}
for id,name,title,kind,team,size,hp,sp,arm,rec,card in [
 ('zenyo','Zenyo',"L’illuminato",'monk',0,3,20,5,[],[1,3,3,4,99,99],['blu',0,0]),
 ('gascor','Gascor','Il prode','sword',0,4,24,3,[1,4],[1,1,2,3,3,99],['blu',1,0]),
 ('ut','Ut','Il vendicatore','heavy',0,6,38,2,[3,6],[1,1,1,2,2,4],['blu',0,1]),
 ('shannon','Shannon','Il cupo','spear',0,4,18,3,[2,3],[1,2,2,3,3,99],['blu',1,1]),
 ('kylvia','Kylvia','La temeraria','archer',0,2,14,4,[1,2],[1,2,2,2,4,99],['blu',1,2]),
 ('anteos','Anteos','Lo spietato','sword',1,4,24,3,[1,4],[1,1,2,3,3,99],['rossi',0,0]),
 ('shaara','Shaara','La tempestosa','monk',1,3,20,5,[],[1,3,3,4,99,99],['rossi',1,0]),
 ('zak','Zak','Il fulmineo','archer',1,2,14,4,[1,2],[1,2,2,2,4,99],['rossi',0,1]),
 ('nuchra','Nuchra','La folle','heavy',1,6,38,2,[3,6],[1,1,1,2,2,4],['rossi',1,1]),
 ('ramok','Ramok','Il malefico','spear',1,4,18,3,[2,3],[1,2,2,3,3,99],['rossi',1,2]),
 ('gandy','Gandy','Il pacifico','gandy',-1,3,16,3,[1,1],[1,1,2,3,3,99],['backfire',1]),
 ('thorn','Thorn','Il putrido','thorn',-1,4,18,2,[1,2],[1,1,2,2,3,4],['backfire',0]),
 ('sanguinaria','Sanguinaria',"L’inesorabile",'sanguinaria',-1,3,20,3,[],[1,2,2,3,99,99],['backfire',3]),
 ('ziggy','Ziggynowskij','Il fluttuante','ziggy',-1,0,0,6,[],[0]*6,['backfire',2]),
 ('skelos','Skelos','Scheletro animato','skeleton',-1,4,1,3,[],[99]*6,['backfire',5]),
 ('sketos','Sketos','Scheletro animato','skeleton',-1,4,1,3,[],[99]*6,['backfire',4]),
 ('golem','Golem','Mostro di roccia','golem',-1,8,40,1,[],[0]*6,['backfire',6])]:char(id,name,title,kind,team,size,hp,sp,arm,rec,card)
# Warrior sheets: column-major positions retain exact source order.
for ch,src,kind in [('zenyo','blu-2','monk'),('shaara','rossi-3','monk'),('gascor','blu-3','sword'),('anteos','rossi-4','sword'),('shannon','blu-5','spear'),('ramok','rossi-5','spear'),('kylvia','blu-4','archer'),('nuchra','rossi-2','heavy')]:
 A=lambda id,c,r,a,d,**kw:add(ch,id,src,c,r,a,d,**kw)
 vals={'monk':[6,-3,-2,-1,1,2,3,-4,8,-1,-6,-3],'sword':[5,1,2,3,5,6,7,0,8,3,-2,1],'spear':[5,-1,0,1,3,4,5,-2,12,1,-4,-1],'archer':[4,-1,0,1,3,4,5,-2,6,1,-4,-1],'heavy':[8,3,4,5,7,8,9,2,10,5,0,3]}[kind]
 ga,gd,ad,rd,rid,ub,down,dd,ca,cd,pd,ps=vals
 A('guard',0,0,ga,gd,red=F,rest=True)
 A('advance',0,1,None,ad,green=F)
 A('run',0,2,None,rd,green=F,fatigue=int(kind=='heavy'))
 A('rise',4 if kind=='sword' else 0,3,None,rid)
 if kind not in ['spear','heavy','archer']:A('roll',1,0,None,0 if kind=='monk' else 4,green=[1,2,4,5])
 if kind=='archer':A('load',1,0,None,1,green=ALL,rest=True)
 if kind=='spear':A('kick',1,0,4,3,red=[0],imbalance=2)
 if kind=='heavy':A('spin',1,0,10,3,red=ALL,fatigue=2,imbalance=3)
 A('unbalanced',1,1,None,ub);A('down',1,2,None,down,rest=True)
 if kind!='archer':
  A('parry_r',2,0,None,pd,blue=[0,1],secondary=ps,rest=True)
  A('parry_l',2,1,None,pd,blue=[5,0],secondary=ps,rest=True)
 else:
  A('shoot',2,0,15,1,red=F)
  A('weapon',2,1,None,3,rest=True)
 A('dodge',2,2,None,dd,green=BACK if kind=='heavy' else [1,2,3,4,5])
 A('charge',2,3,ca,cd,red=[0],green=F,imbalance=1 if kind=='heavy' else 0,fatigue=int(kind=='heavy'))
 if kind!='spear':
  ra,df={'monk':(7,-2),'sword':(7,2),'archer':(5,0),'heavy':(9,4)}[kind]
  A('right',3,0,ra,df,red=[0,1],imbalance=0 if kind=='heavy' else None)
  A('left',3,1,ra,df,red=[5,0],imbalance=0 if kind=='heavy' else None)
 if kind=='heavy':A('kick',3,2,8,6,red=[0],imbalance=2)
 else:
  ta,td,tb={'monk':(9,-3,2),'sword':(9,1,2),'archer':(7,-1,None),'spear':(10,-1,1)}[kind]
  A('thrust',3,2,ta,td,red=[0],fatigue=int(kind!='spear'),imbalance=tb)
 if kind!='archer':A('again',4,0,None,0)
 if kind in ['monk','sword','heavy']:A('cleave',4,1,{'monk':11,'sword':12,'heavy':14}[kind],{'monk':-1,'sword':3,'heavy':5}[kind],red=[0],fatigue=1,imbalance=None if kind=='monk' else (0 if kind=='sword' else 1))
 if kind=='monk':
  A('sweep',4,2,6,-2,red=F,fatigue=1,imbalance=4)
  A('meditate',4,3,None,0,rest=ch=='shaara')
 if kind=='sword':A('kick',4,2,5,4,red=[0,1],imbalance=1)
 if kind=='archer':
  A('kick',4,1,4,2,red=[0,1],imbalance=1)
  A('roll',4,2,None,2,green=[1,2,4,5])
 if kind=='spear':A('sweep',4,3,6,-1,red=F,imbalance=3)
# Kylvia extra pieces share Shannon's sheet.
for id,c,r,d,blue in [('again',3,1,0,[]),('parry_r',4,1,-4,[0,1]),('parry_l',4,2,-4,[5,0])]:add('kylvia',id,'blu-5',c,r,None,d,blue=blue,secondary=-1,rest=id!='again')
# Hand-placed sheets. Coordinates expressed in the 1888 px inspection image then scaled.
def custom(ch,id,src,box,a,d,**kw):
 return add(ch,id,src,0,0,a,d,custom=[round(v*2523/1888) for v in box],**kw)
# Ut's available physical pieces, including the single printed parry.
for id,box,a,d,kw in [
 ('run',[864,120,318,276],None,5,{'green':F,'fatigue':1}),('down',[864,389,318,276],None,9,{'rest':True}),('guard',[860,658,320,276],8,3,{'red':F,'rest':True}),
 ('again',[1100,-10,320,276],None,0,{}),('unbalanced',[1100,259,320,276],None,8,{}),('cleave',[1100,527,320,276],14,5,{'red':[0],'fatigue':1,'imbalance':1}),
 ('advance',[1332,124,320,276],None,4,{'green':F}),('kick',[1332,394,320,276],8,6,{'red':[0],'imbalance':2}),('spin',[1332,660,320,276],10,3,{'red':ALL,'fatigue':2,'imbalance':3}),
 ('parry_l',[1564,-8,320,276],None,0,{'blue':[5,0],'secondary':3,'rest':True}),('left',[1564,260,320,276],9,4,{'red':[5,0],'imbalance':0}),('rise',[1564,528,320,276],None,7,{})]:custom('ut',id,'blu-6',box,a,d,**kw)
# Zak's sheet.
for id,box,a,d,kw in [
 ('unbalanced',[400,131,320,276],None,4,{}),('parry_l',[400,403,320,276],None,-4,{'blue':[5,0],'secondary':-1,'rest':True}),('guard',[400,672,320,276],4,-1,{'red':F,'rest':True}),
 ('shoot',[635,-8,320,276],15,1,{'red':F}),('down',[635,262,320,276],None,5,{'rest':True}),('weapon',[635,532,320,276],None,3,{'rest':True}),
 ('advance',[870,127,320,276],None,0,{'green':F}),('left',[870,396,320,276],5,0,{'red':[5,0]}),('charge',[870,667,320,276],6,1,{'red':[0],'green':F,'imbalance':0}),
 ('again',[1103,-8,320,276],None,0,{}),('load',[1103,260,320,276],None,1,{'green':ALL,'rest':True}),('rise',[1103,531,320,276],None,3,{}),
 ('kick',[1338,129,320,276],4,2,{'red':[0,1],'imbalance':1}),('parry_r',[1338,395,320,276],None,-4,{'blue':[0,1],'secondary':-1,'rest':True}),('roll',[1360,665,320,276],None,2,{'green':[1,2,4,5],'rotate':180}),
 ('thrust',[1574,-8,314,276],7,-1,{'red':[0],'fatigue':1}),('right',[1574,260,314,276],5,0,{'red':[0,1]}),('run',[1574,525,314,276],None,1,{'green':F})]:custom('zak',id,'rossi-6',box,a,d,**kw)
# Mages and animated skeletons.
for ch,src in [('thorn','backfire-2'),('sanguinaria','backfire-3'),('gandy','backfire-5')]:
 A=lambda id,c,r,a,d,**kw:add(ch,id,src,c,r,a,d,**kw)
 sg=ch=='sanguinaria';ga=ch=='gandy'
 A('advance',0,0,None,0 if sg else 3,green=F)
 A('down',0,1,None,5 if sg else 8,rest=True);A('unbalanced',0,2,None,4 if sg else 7)
 A('run',0,3,None,1 if sg else 4,green=F)
 A('guard',1,0,5 if sg else (3 if ga else 2),-1 if sg else 2,red=F,rest=True)
 A('dodge',1,1,None,-2 if sg else 1,green=[1,2,3,4,5] if sg else BACK)
 A('charge',1,2,9 if sg else 4,1 if sg else 4,red=[0],green=F)
 A('rise',2,0,None,3 if sg else 6)
 if sg:
  A('thrust',2,1,8,1,red=F,fatigue=1,imbalance=1)
  A('parry_r',2,2,None,-4,blue=[0,1],secondary=-2,rest=True)
  A('parry_l',2,3,None,-4,blue=[5,0],secondary=-2,rest=True)
  A('concentrate',3,0,None,7,green=ALL)
 else:
  A('concentrate',2,1,None,8,green=ALL,rest=ga)
  A('cleave' if ga else 'kick',2,2,6 if ga else 4,3 if ga else 5,red=[0,1],fatigue=1,imbalance=1 if ga else 0)
  if ga:A('parry_r',2,3,None,-1,blue=F,secondary=3,rest=True)
  else:A('punch',2,3,5,4,red=F,fatigue=1)
 if ga:A('sweep',3,0,4,4,red=F,imbalance=3)
# Spell metadata: value, cost, range, target, source coordinates, defensive value.
spellrows={
 'gandy':[('firestaff',1,1,1,'enemy',3,1,-3),('shield',2,2,0,'self',3,2,-15),('vortex',3,3,3,'empty',4,0,7),('sleep',4,4,3,'enemy',4,1,5),('fireball',5,5,7,'cell',4,2,0)],
 'thorn':[('pustules',1,1,2,'self',3,0,0),('fear',2,2,5,'self',3,1,-2),('age',3,3,4,'enemy',3,2,5),('summon',4,4,2,'empty',4,0,7),('plague',5,5,5,'enemy',4,1,5)],
 'sanguinaria':[('wall',1,1,3,'empty',3,1,-1),('teleport',2,1,99,'empty',3,2,-8),('transform',3,3,1,'enemy',4,0,5),('livingfire',4,4,1,'empty',4,1,2),('abyss',5,5,3,'cell',4,2,3)],
 'ziggy':[('shock',1,1,1,'self',1,0,-5),('heal',2,2,0,'self',1,1,-3),('drain',3,3,2,'enemy',1,2,-6),('control',4,1,4,'enemy',2,0,0),('lightning',5,5,7,'cell',2,1,-2)]}
for ch,rows in spellrows.items():
 src={'gandy':'backfire-5','thorn':'backfire-2','sanguinaria':'backfire-3','ziggy':'backfire-4'}[ch]
 for id,v,cost,ran,target,c,r,d in rows:add(ch,id,src,c,r,13 if id=='firestaff' else None,d,red=F if id=='firestaff' else [],spell=True,value=v,cost=cost,range=ran,target=target)
 if ch!='gandy':add(ch,'again',src,4 if ch!='ziggy' else 2,2 if ch in ['thorn','ziggy'] else 3,None,0)
add('gandy','again','backfire-7',4,0,None,0)
for id,r,d in [('advance',0,2),('float',1,3),('concentrate',2,8),('dematerialize',3,-25)]:add('ziggy',id,'backfire-4',0,r,None,d,green=ALL if id in ['advance','float','concentrate'] else [],blue=ALL if id=='dematerialize' else [])
for ch,src in [('skelos','backfire-6'),('sketos','backfire-7')]:
 A=lambda id,c,r,a,d,**kw:add(ch,id,src,c,r,a,d,**kw)
 A('again',0,0,None,0);A('cleave',0,1,9 if ch=='skelos' else 11,4,red=[0],imbalance=0 if ch=='skelos' else 1)
 A('advance',0,2,None,3,green=F);A('guard',0,3,6,3,red=F)
 A('dodge',1,0,None,1,green=BACK);A('charge',1,1,6 if ch=='skelos' else 8,3 if ch=='skelos' else 5,red=[0],green=F)
 A('right',1,2,5 if ch=='skelos' else 6,3 if ch=='skelos' else 4,red=[0,1],imbalance=None if ch=='skelos' else 0)
 A('left',2,0,5 if ch=='skelos' else 6,3 if ch=='skelos' else 4,red=[5,0],imbalance=None if ch=='skelos' else 0)
 A('parry_r',2,1,None,-1,blue=[0,1],secondary=2);A('parry_l',2,2,None,-1,blue=[5,0],secondary=2);A('pieces',2,3,None,0)
add('golem','advance','backfire-4',4,2,None,0,green=F)
add('golem','guard','backfire-4',4,3,18,2,red=F)
# Cards: crop straight from the original scan.
for ch,st in characters.items():
 cd=st['source_card'];im=Image.open('tmp/source/'+cd[0]+'-1.png')
 if cd[0]!='backfire':
  x=505+1010*cd[1];y=495*cd[2];card=im.crop((x,y,min(x+1008,im.width),y+493))
 else:
  i=cd[1]
  if i<5:
   # Five vertical cards in the supplied sheet.
   x=102+(4-i)*486;card=im.crop((x,0,x+484,1017)).rotate(90,expand=True)
  else:
   x=1510 if i==5 else 490;card=im.crop((x,1015,min(x+1013,im.width),1505))
 card.thumbnail((1000,500));card.save('assets/cards/'+ch+'.webp',quality=94)
# Persistent effect pieces, counts are the physical stock.
for name,src,c,r in [('vortex','backfire-7',3,1),('fire','backfire-4',3,0),('wall','backfire-7',4,1),('abyss','backfire-6',4,0),('frog','backfire-6',3,2)]:tile(src,c,r,'effect_'+name)
for ch,st in characters.items():st['moves']=moves[ch]
# Nomi stampati sulle pedine quando differiscono da quelli generici della mossa.
for (c,k),n in {('shaara','right'):'Pugno destro',('shaara','left'):'Pugno sinistro',('shaara','thrust'):'Calcio volante',
                ('zenyo','right'):'Colpo destro',('zenyo','left'):'Colpo sinistro',('gandy','parry_r'):'Parata'}.items():moves[c][k]['name']=n
# Ut: la scheda fotografata ha solo 12 pedine; le 4 mancanti prendono i valori del gemello Nuchra
# (immagini ricostruite da tools/ut_missing_tokens.py, da lanciare dopo questo script).
for k in ['parry_r','dodge','charge','right']:
 m=json.loads(json.dumps(moves['nuchra'][k]));m['texture']='res://assets/tokens/ut_%s.webp'%k;moves['ut'][k]=m
moves['ut']={k:moves['ut'][k] for k in moves['nuchra'] if k in moves['ut']};characters['ut']['moves']=moves['ut']
Path('data/characters.json').write_text(json.dumps(characters,ensure_ascii=False,indent=2))
Path('data/token_sources.json').write_text(json.dumps(sources,ensure_ascii=False,indent=2))
# Original cover for the catalog, no generated illustration.
im=Image.open('assets/rules/page-01.webp');im.thumbnail((650,920));im.save('ludoteca/copertina.webp',quality=90)
print('Characters:',len(characters),'Moves:',sum(len(x) for x in moves.values()))
