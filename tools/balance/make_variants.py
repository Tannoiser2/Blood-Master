#!/usr/bin/env python3
"""Varianti dei guerrieri ufficiali per tarare il calcolatore: ognuna cambia una sola cosa."""
import json, copy, os, sys
HERE=os.path.dirname(os.path.abspath(__file__))
D=json.load(open(os.path.join(HERE,'..','..','data','characters.json')))
out={}
def add(base,tag,fn):
    x=copy.deepcopy(D[base]);x['reach']=base in ('shannon','ramok','zenyo','shaara') and base!='shaara';fn(x);vid='v_%s_%s'%(base,tag);x['id']=vid;out[vid]=x
for b in ['zenyo','gascor','ut','shannon','kylvia']:
    hp=D[b]['hp']
    add(b,'hp+',lambda x:x.update(hp=round(hp*1.3)))
    add(b,'hp-',lambda x:x.update(hp=round(hp*.7)))
    def atk(d):
        def f(x):
            for m in x['moves'].values():
                if m['attack'] is not None and m['id']!='shoot':m['attack']+=d
        return f
    add(b,'atk+2',atk(2));add(b,'atk-2',atk(-2))
    def df(d):
        def f(x):
            for m in x['moves'].values():
                if m['id'] in('again',):continue
                m['defense']+=d;m['secondary']+=d
        return f
    add(b,'def-2',df(-2));add(b,'def+2',df(2))
    def fat(x):
        for m in x['moves'].values():
            if m['attack'] is not None and m['id']!='shoot' and m['id']!='guard':m['fatigue']=m['fatigue']+1
    add(b,'fat+1',fat)
    def nofat(x):
        for m in x['moves'].values():m['fatigue']=0
    add(b,'fat0',nofat)
    add(b,'size+2',lambda x:x.update(size=x['size']+2))
    add(b,'spr+2',lambda x:x.update(sprint=x['sprint']+2,sprints=x['sprints']+[x['sprints'][-1]]*2))
    add(b,'arm',lambda x:x.update(armor=[3,5]))
    add(b,'noarm',lambda x:x.update(armor=[]))
json.dump(out,open(sys.argv[1],'w'))
print(len(out),'varianti')
