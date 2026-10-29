#!/usr/bin/env python3
"""Legge le righe RIS di tests/balance_matrix.gd e calcola la forza di ogni personaggio.
duelli: percentuale di vittorie e matrice testa a testa; squadre: regressione logistica
(quanto la presenza di un personaggio in squadra cambia la probabilità di vincere)."""
import sys, glob, math, collections
files = sys.argv[1:]
duel = collections.defaultdict(lambda: [0.0, 0])
h2h = collections.defaultdict(lambda: [0.0, 0])
teams = []
for f in files:
    for line in open(f):
        if not line.startswith('RIS '):
            continue
        a, b, w, turn, s0, s1 = line[4:].strip().split('|')
        w = int(w); s0 = float(s0); s1 = float(s1)
        # chi vince: il vincitore dichiarato, altrimenti (limite di turni) chi ha più vita residua
        if w == 0: r = 1.0
        elif w == 1: r = 0.0
        else: r = 1.0 if s0 > s1 + .1 else (0.0 if s1 > s0 + .1 else .5)
        A = a.split(','); B = b.split(',')
        if len(A) == 1:
            duel[A[0]][0] += r; duel[A[0]][1] += 1
            duel[B[0]][0] += 1 - r; duel[B[0]][1] += 1
            h2h[(A[0], B[0])][0] += r; h2h[(A[0], B[0])][1] += 1
            h2h[(B[0], A[0])][0] += 1 - r; h2h[(B[0], A[0])][1] += 1
        else:
            teams.append((A, B, r))
if duel:
    names = sorted(duel, key=lambda k: -duel[k][0] / duel[k][1])
    print('DUELLI 1 contro 1 (vittorie %)')
    for n in names:
        print('  %-12s %5.1f%%  (%d partite)' % (n, 100 * duel[n][0] / duel[n][1], duel[n][1]))
    print('\n  riga contro colonna, % vittorie della riga')
    print('  %-12s' % '' + ''.join('%6s' % n[:5] for n in names))
    for a in names:
        print('  %-12s' % a + ''.join(('%6.0f' % (100 * h2h[(a, b)][0] / h2h[(a, b)][1])) if (a, b) in h2h else '     -' for b in names))
if teams:
    types = sorted({t for A, B, r in teams for t in A + B})
    w = {t: 0.0 for t in types}
    # regressione logistica semplice con discesa del gradiente (regolarizzata)
    for it in range(3000):
        g = {t: 0.0 for t in types}
        for A, B, r in teams:
            z = sum(w[t] for t in A) - sum(w[t] for t in B)
            p = 1 / (1 + math.exp(-z))
            for t in A: g[t] += (r - p)
            for t in B: g[t] -= (r - p)
        for t in types:
            w[t] += .5 * (g[t] / len(teams) - .002 * w[t])
        m = sum(w.values()) / len(w)
        for t in types: w[t] -= m
    print('\nSQUADRE 3 contro 3 (%d partite): forza relativa (0 = nella media)' % len(teams))
    for t in sorted(types, key=lambda t: -w[t]):
        # contro una squadra media, sostituire un membro medio con questo personaggio porta la vittoria da 50% a...
        print('  %-12s %+5.2f   -> %4.0f%% di vittorie se sostituisce un compagno medio' % (t, w[t], 100 / (1 + math.exp(-w[t]))))
