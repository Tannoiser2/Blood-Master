#!/usr/bin/env python3
"""Taratura del calcolatore di punti (BloodForge.COEF) sulle partite simulate.

uso: fit.py features.txt duelli_cast.txt[,..] squadre_cast.txt[,..] varianti.txt[,..]
  features.txt : righe FEAT di tests/forge_features.gd (VARS=varianti.json)
  duelli/squadre: righe RIS di tests/balance_matrix.gd (MODE=duel / MODE=team)
  varianti     : righe RIS di tests/balance_variants.gd

Forza osservata di un personaggio = logit della sua percentuale di vittorie in duello contro il cast,
più lo scarto squadra-duello del suo archetipo (arcieri e maghi rendono di più in squadra).
Si cerca la combinazione lineare delle caratteristiche (in log per offesa, vita e ferite subite)
che la riproduce meglio (minimi quadrati con un po' di regolarizzazione)."""
import sys, json, math, collections
import numpy as np

def logit(p): p = min(max(p, .03), .97); return math.log(p / (1 - p))
def read_ris(paths):
    out = []
    for p in paths.split(','):
        for line in open(p):
            if not line.startswith('RIS '): continue
            a, b, w, turn, s0, s1 = line[4:].strip().split('|')
            w = int(w); s0 = float(s0); s1 = float(s1)
            r = 1.0 if w == 0 else 0.0 if w == 1 else (1.0 if s0 > s1 + .1 else 0.0 if s1 > s0 + .1 else .5)
            out.append((a.split(','), b.split(','), r))
    return out

feat = {}
for line in open(sys.argv[1]):
    if line.startswith('FEAT '):
        d = json.loads(line[5:]); feat[d['id']] = d['f']
duels = read_ris(sys.argv[2]); teams = read_ris(sys.argv[3]); var = read_ris(sys.argv[4])
TWIN = {'anteos': 'gascor', 'shaara': 'zenyo', 'zak': 'kylvia', 'nuchra': 'ut', 'ramok': 'shannon'}

def winrate(games, who):
    s = collections.defaultdict(lambda: [0.0, 0])
    for A, B, r in games:
        if len(A) != 1: continue
        if A[0] == who: s['x'][0] += r; s['x'][1] += 1
        if B[0] == who: s['x'][0] += 1 - r; s['x'][1] += 1
    return s['x'][0] / max(1, s['x'][1]), s['x'][1]

# forza in squadra (regressione logistica come analyze.py)
types = sorted({t for A, B, r in teams for t in A + B})
w = {t: 0.0 for t in types}
for it in range(3000):
    g = {t: 0.0 for t in types}
    for A, B, r in teams:
        z = sum(w[t] for t in A) - sum(w[t] for t in B); p = 1 / (1 + math.exp(-z))
        for t in A: g[t] += r - p
        for t in B: g[t] -= r - p
    for t in types: w[t] += .5 * (g[t] / len(teams) - .002 * w[t])
    m = sum(w.values()) / len(w)
    for t in types: w[t] -= m
duel_logit = {t: logit(winrate(duels, t)[0]) for t in types}
# stessa scala del duello: si riporta la forza in squadra alla dispersione dei duelli
k = np.std([duel_logit[t] for t in types]) / max(1e-6, np.std([w[t] for t in types]))
team_adj = {t: w[t] * k - duel_logit[t] for t in types}   # quanto rende in più (o in meno) in squadra
# il duello conta metà, la squadra metà: si gioca in tutti e due i modi
TEAM_SHARE = .5

rows = []   # (id, caratteristiche, forza osservata, peso)
for t in ['zenyo', 'gascor', 'ut', 'shannon', 'kylvia']:
    rows.append((t, feat[t], duel_logit[t] + TEAM_SHARE * team_adj[t], 3.0))
vids = sorted({x for A, B, r in var for x in A + B if x.startswith('v_')})
for v in vids:
    p, n = winrate(var, v)
    base = v.split('_')[1]
    rows.append((v, feat[v], logit(p) + TEAM_SHARE * team_adj[base], 1.0))

KEYS = ['off', 'hp', 'sub', 'sprint', 'size', 'fat', 'imb', 'shoot']
def x_of(f):
    return [math.log(max(f['off'], .05)), math.log(max(f['hp'], 1)), math.log(max(f['sub'], .05)), f['sprint'], f['size'], f['fat'], f['imb'], f['shoot'], 1.0]
X = np.array([x_of(r[1]) for r in rows]); y = np.array([r[2] for r in rows]); W = np.array([r[3] for r in rows])
lam = float(sys.argv[5]) if len(sys.argv) > 5 else .3
A = X.T @ (X * W[:, None]) + lam * np.diag([1] * (X.shape[1] - 1) + [0]); bvec = X.T @ (y * W)
coef = np.linalg.solve(A, bvec)
pred = X @ coef
print('coefficienti:')
for k, c in zip(KEYS + ['zero'], coef): print('  %-7s %+.3f' % (k, c))
res = y - pred
print('errore medio (logit) %.3f  ·  correlazione %.3f' % (np.sqrt(np.average(res ** 2, weights=W)), np.corrcoef(pred, y)[0, 1]))
print('\n%-22s %8s %8s' % ('personaggio', 'osserv.', 'stima'))
for r, p in zip(rows, pred):
    if r[3] > 1 or r[0].endswith(('hp+', 'atk+2', 'def-2', 'fat0')): print('%-22s %+8.2f %+8.2f' % (r[0], r[2], p))
print('\nCOEF=' + json.dumps({k: round(float(c), 4) for k, c in zip(KEYS + ['zero'], coef)}))
