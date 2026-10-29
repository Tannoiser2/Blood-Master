#!/usr/bin/env python3
"""Valore dei personaggi di Blood Master calcolato dalle pedine.

Tutto è espresso in FERITE ATTESE, con le regole del gioco digitale:
  totale = attacco + difesa del difensore + posizionale + dado (il 6 esplode: +1d6)
  ferite = totale - 10 (da 0 a 10; oltre 20: 10 + metà dell'eccedenza, massimo 16)
  armatura: se il dado di armatura cade nell'intervallo, assorbe quel numero di ferite.

Per ogni personaggio:
  offesa   = ferite attese per attacco (media delle sue pedine d'attacco) contro un difensore medio
  subite   = ferite attese che riceve da un attaccante medio, mediate sulle sue pedine
  vita     = ferite che può incassare (punti ferita, aumentati da quello che l'armatura assorbe)
  valore   = offesa * vita / subite   -> quante ferite infligge prima di cadere se si scambiano colpi alla pari
"""
import json, itertools, sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
D = json.load(open(os.path.join(HERE, '..', '..', 'data', 'characters.json')))
POS = [0, 1, 3, 5, 3, 1]

# dado che esplode sul 6: distribuzione del risultato
DIE = {}
for d in range(1, 7):
    if d < 6:
        DIE[d] = DIE.get(d, 0) + 1 / 6
    else:
        for e in range(1, 7):
            DIE[6 + e] = DIE.get(6 + e, 0) + 1 / 36

def wounds(total):
    if total > 20:
        return min(16, 10 + -(-(total - 20) // 2))
    return max(0, min(10, total - 10))

def armor_cut(n, armor):
    if not armor or n <= 0:
        return n
    lo, hi = armor
    return sum(max(0, n - d) if lo <= d <= hi else n for d in range(1, 7)) / 6

# da che lato arriva un colpo: in media per lo più di fronte, a volte di lato, raramente alle spalle
SIDE_W = {0: .45, 1: .15, 5: .15, 2: .09, 4: .09, 3: .07}

def ew(attack, token, armor=None):
    """ferite attese di un attacco 'attack' contro chi ha questa pedina"""
    out = 0.0
    for side, w in SIDE_W.items():
        dv = token['defense']
        if token['blue'] and side not in token['blue']:
            dv = token['secondary']
        pos = 0 if side in token['red'] else POS[side]
        for d, p in DIE.items():
            out += w * p * armor_cut(wounds(attack + dv + pos + d), armor)
    return out

CORE = ['guard', 'advance', 'run', 'parry_r', 'parry_l', 'dodge', 'charge', 'right', 'left', 'thrust',
        'cleave', 'sweep', 'kick', 'spin', 'shoot', 'load', 'punch', 'meditate', 'roll']
WARRIORS = ['zenyo', 'gascor', 'ut', 'shannon', 'kylvia']
ALL = ['zenyo', 'gascor', 'ut', 'shannon', 'kylvia', 'gandy', 'thorn', 'sanguinaria']

def play_tokens(c):
    """le pedine che si giocano davvero (niente a terra / sbilanciato / Ancora)"""
    return [m for k, m in D[c]['moves'].items() if k not in ('unbalanced', 'down', 'again', 'pieces', 'rise', 'weapon')]

def attack_tokens(c):
    return [m for m in play_tokens(c) if m['attack'] is not None and not m.get('spell')]

# difensore medio = tutte le pedine dei guerrieri; attaccante medio = tutte le loro pedine d'attacco
REF_DEF = [m for c in WARRIORS for m in play_tokens(c) if not m.get('spell')]
REF_ATK = [m['attack'] for c in WARRIORS for m in attack_tokens(c) if m['id'] != 'shoot']

def offense_of(m, size):
    a = m['attack']
    if m['id'] == 'shoot':
        a = 15 - 4          # tiro a 4 esagoni di media
    base = sum(ew(a, t) for t in REF_DEF) / len(REF_DEF)
    # sbilanciamento: con ferite, dado + stazza + modificatore contro stazza media 4 (tabella)
    imb = 0.0
    if m.get('imbalance') is not None and base > 0:
        hit = sum(1 for d in range(1, 7) if d + size + m['imbalance'] >= 10) / 6
        imb = hit * 1.5     # sbilanciare vale circa un colpo e mezzo (perde la mossa, poi è esposto)
    # fatica: -1 all'attacco e +1 alla difesa avversaria finché non si riposa (circa 2 turni)
    fat = m['fatigue'] * 2 * .8
    return base, imb, fat

def received(m, armor):
    return sum(ew(a, m, armor) for a in REF_ATK) / len(REF_ATK)

def report(chars=ALL):
    rows = []
    for c in chars:
        x = D[c]
        atk = attack_tokens(c)
        offs = [offense_of(m, x['size']) for m in atk]
        off = sum(b + i - f * 0 for b, i, f in offs) / max(1, len(offs))
        fatp = sum(f for b, i, f in offs) / max(1, len(offs))
        toks = [m for m in play_tokens(c) if not m.get('spell')]
        sub = sum(received(m, x['armor']) for m in toks) / len(toks)
        sub_noarm = sum(received(m, None) for m in toks) / len(toks)
        life = x['hp'] * (sub_noarm / sub if sub else 1)
        mob = sum(len(m['green']) for m in toks) / len(toks)
        val = (off - fatp * .25) * x['hp'] / sub if sub else 0
        rows.append((c, x['hp'], x['size'], x['sprint'], len(atk), off, fatp, sub, life, mob, val))
    return rows

if __name__ == '__main__':
    rows = report()
    print('%-12s %3s %4s %4s %4s %7s %6s %7s %6s %5s %7s' % ('pers', 'PF', 'staz', 'spr', 'n.at', 'offesa', 'fat', 'subite', 'vita', 'mob', 'VALORE'))
    for r in rows:
        print('%-12s %3d %4d %4d %4d %7.2f %6.2f %7.2f %6.1f %5.2f %7.1f' % r)
