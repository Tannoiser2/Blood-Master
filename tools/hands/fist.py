"""Chiude le mani di un modello seguendo la curva che le dita hanno già.

I modelli non hanno le ossa delle dita e le mani sono scolpite: spesso con le quattro dita fuse in un blocco, già
piegate ad artiglio, e con pochi vertici. Arrotolarle come se fossero tese le accartoccia. Qui invece:
 1. oltre la linea delle nocche si separano il blocco delle dita e il pollice (pezzi non collegati fra loro);
 2. di ogni pezzo si misura la distanza lungo la superficie dalla base alla punta: dà la linea di mezzo anche se
    il dito è curvo, quanto piega già e da che parte (il palmo è dal lato interno della curva);
 3. si aggiunge solo la piega che manca per arrivare a una mano da presa, su tre articolazioni.
Lavora sul GLB spostando solo i vertici della mano: scheletro, pesi, animazioni e texture non cambiano.
Messo a punto guardando il risultato in Blender (scena ProvaMani); controllare sempre con tools/hands/handcam.gd.

uso: python3 tools/hands/fist.py modello.glb [--out file.glb] [--right 1] [--left 1] [--total 195]
  --right/--left 0 lascia quella mano com'è; --total: gradi complessivi di piega delle dita a mano chiusa"""
import argparse, heapq
import numpy as np
import pygltflib

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}

def view(g, blob, acc_i):
    a = g.accessors[acc_i]; bv = g.bufferViews[a.bufferView]
    dt = np.dtype(CT[a.componentType]); n = NC[a.type]
    off = (bv.byteOffset or 0) + (a.byteOffset or 0); stride = bv.byteStride or dt.itemsize * n
    return np.ndarray((a.count, n), dtype=dt, buffer=blob, offset=off, strides=(stride, dt.itemsize)), a

def _comps(n, edges, keep):
    par = np.arange(n)
    def find(a):
        while par[a] != a:
            par[a] = par[par[a]]; a = par[a]
        return a
    for a, b in edges:
        if keep[a] and keep[b]:
            ra, rb = find(a), find(b)
            if ra != rb: par[ra] = rb
    return np.array([find(i) if keep[i] else -1 for i in range(n)])

def _rot(P, piv, axis, ang):
    v = P - piv; c = np.cos(ang)[:, None]; s = np.sin(ang)[:, None]
    return piv + v * c + np.cross(axis, v) * s + axis * (v @ axis)[:, None] * (1 - c)

def _smooth(e0, e1, x):
    t = np.clip((x - e0) / max(e1 - e0, 1e-9), 0, 1); return t * t * (3 - 2 * t)

def geodesic(n, edges, P, seeds, mask):
    adj = [[] for _ in range(n)]
    for a, b in edges:
        if mask[a] and mask[b]:
            w = float(np.linalg.norm(P[a] - P[b])); adj[a].append((b, w)); adj[b].append((a, w))
    g = np.full(n, np.inf); h = []
    for s in seeds: g[s] = 0.0; heapq.heappush(h, (0.0, int(s)))
    while h:
        dd, a = heapq.heappop(h)
        if dd > g[a]: continue
        for b, w in adj[a]:
            if dd + w < g[b]: g[b] = dd + w; heapq.heappush(h, (g[b], b))
    return g

def close_geo(P, edges, W, F, thr=.45, total=195.0, thumb_total=95.0, amount=1.0, joints=(.2, .5, .78), split=(.3, .4, .3), log=print):
    """P: vertici saldati della mano, edges: spigoli, W polso, F gomito -> nuove posizioni"""
    d0 = (W - F) / np.linalg.norm(W - F); t = (P - W) @ d0; L = np.percentile(t, 99.5); n = len(P)
    lab = _comps(n, edges, t > thr * L); ids, cnt = np.unique(lab[lab >= 0], return_counts=True)
    out = P.copy(); order = np.argsort(-cnt)
    big = cnt[order[0]] if len(order) else 0
    for rank, oi in enumerate(order[:5]):
        if cnt[oi] < max(8, .04 * n): continue
        m = lab == ids[oi]; idx = np.nonzero(m)[0]
        is_thumb = rank > 0 and cnt[oi] < .45 * big   # il pezzo piccolo accanto al blocco delle dita
        seeds = set()
        for a, b in edges:
            if m[a] and not m[b]: seeds.add(a)
            if m[b] and not m[a]: seeds.add(b)
        if not seeds: continue
        g = geodesic(n, edges, P, seeds, m)[idx]; g[~np.isfinite(g)] = 0.0
        Q = P[idx]; K = 10; qs = np.quantile(g, np.linspace(0, 1, K + 1))
        sl = [(g >= qs[j]) & (g <= qs[j + 1]) for j in range(K)]
        if any(s.sum() == 0 for s in sl): continue
        line = np.array([Q[s].mean(0) for s in sl]); gm = np.array([g[s].mean() for s in sl])
        seg = np.linalg.norm(np.diff(line, axis=0), axis=1)
        if np.linalg.norm(line[2] - line[0]) < 1e-9 or np.linalg.norm(line[-1] - line[-3]) < 1e-9: log("   pezzo troppo piccolo per misurarlo: lasciato"); continue
        arc = np.concatenate([[0], np.cumsum(seg)]); Ln = arc[-1]; s = np.interp(g, gm, arc)
        chord = line[-1] - line[0]; chord /= np.linalg.norm(chord)
        bow = (line[0] + line[-1]) / 2 - line[K // 2]; bow -= chord * (bow @ chord); bl = np.linalg.norm(bow)
        t0 = line[2] - line[0]; t0 /= np.linalg.norm(t0); t1 = line[-1] - line[-3]; t1 /= np.linalg.norm(t1)
        have = float(np.degrees(np.arccos(np.clip(t0 @ t1, -1, 1))))
        name = "pollice" if is_thumb else "dita"
        if bl < .03 * Ln: log(f"   {name}: {len(idx)} vertici, quasi dritto: non si capisce dov'è il palmo, lasciato"); continue
        fpalm = bow / bl; add = max(0.0, (thumb_total if is_thumb else total) * amount - have)
        for jf, fr in zip(joints, split):
            js = jf * Ln; j = min(max(int(np.searchsorted(arc, js)), 1), K - 1)
            w = (js - arc[j - 1]) / max(arc[j] - arc[j - 1], 1e-9); piv = line[j - 1] + w * (line[j] - line[j - 1])
            while j < K - 1 and np.linalg.norm(line[j] - line[j - 1]) < 1e-9: j += 1
            tang = line[j] - line[j - 1]; tang /= max(np.linalg.norm(tang), 1e-12)
            axis = np.cross(tang, fpalm); axis /= np.linalg.norm(axis)
            ang = np.radians(add * fr); band = .1 * Ln
            Q = _rot(Q, piv, axis, ang * _smooth(js - band, js + band, s))
            far = arc > js
            if far.any(): line[far] = _rot(line[far], piv, axis, np.full(far.sum(), ang))
            fpalm = _rot(fpalm[None, :], np.zeros(3), axis, np.array([ang]))[0]
        out[idx] = Q
        log(f"   {name}: {len(idx)} vertici, piegava già {have:.0f} gradi, aggiunti {add:.0f}")
    return out

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("glb"); ap.add_argument("--out")
    ap.add_argument("--right", type=float, default=1.0); ap.add_argument("--left", type=float, default=1.0)
    ap.add_argument("--total", type=float, default=195.0)
    o = ap.parse_args()
    g = pygltflib.GLTF2().load(o.glb); blob = bytearray(g.binary_blob())
    skin = g.skins[0]; names = [g.nodes[j].name for j in skin.joints]
    ibm, _ = view(g, blob, skin.inverseBindMatrices)
    bind = [np.linalg.inv(m.reshape(4, 4).T.astype(np.float64)) for m in ibm]
    for side, amount in (("Right", o.right), ("Left", o.left)):
        if amount <= 0: continue
        hj = names.index(side + "Hand"); W = bind[hj][:3, 3]; F = bind[names.index(side + "ForeArm")][:3, 3]
        parts = []; allp = []; tris = []; base = 0
        for mesh in g.meshes:
            for pr in mesh.primitives:
                at = pr.attributes
                if at.JOINTS_0 is None or at.POSITION is None or pr.indices is None: continue
                J, _ = view(g, blob, at.JOINTS_0); Wt, wa = view(g, blob, at.WEIGHTS_0); wt = Wt.astype(np.float64)
                if wa.componentType == 5121: wt /= 255.0
                elif wa.componentType == 5123: wt /= 65535.0
                hand = (wt * (J == hj)).sum(1) > .5
                if not hand.any(): continue
                P, pacc = view(g, blob, at.POSITION); N = view(g, blob, at.NORMAL)[0] if at.NORMAL is not None else None
                idx = np.nonzero(hand)[0]; local = -np.ones(len(P), dtype=np.int64); local[idx] = base + np.arange(len(idx))
                I = view(g, blob, pr.indices)[0].reshape(-1, 3).astype(np.int64)
                ok = hand[I].all(1); tris.append(local[I[ok]])
                parts.append((P, pacc, N, idx, base)); allp.append(P[idx].astype(np.float64)); base += len(idx)
        if not parts: print(side, "nessun vertice"); continue
        allp = np.concatenate(allp); tris = np.concatenate(tris)
        key = np.round(allp / max(np.ptp(allp), 1e-9), 5); uniq, inv = np.unique(key, axis=0, return_inverse=True); inv = inv.ravel()
        Pw = np.zeros((len(uniq), 3)); np.add.at(Pw, inv, allp); Pw /= np.bincount(inv)[:, None]   # doppioni delle cuciture saldati
        tw = inv[tris]; ed = np.concatenate([tw[:, [0, 1]], tw[:, [1, 2]], tw[:, [2, 0]]]); ed = ed[ed[:, 0] != ed[:, 1]]
        edges = np.unique(np.sort(ed, axis=1), axis=0)
        print(f"{side}: {len(Pw)} vertici")
        out = close_geo(Pw, edges, W, F, total=o.total, amount=amount)
        moved = np.linalg.norm(out - Pw, axis=1) > 1e-9
        if not moved.any(): continue
        # normali rifatte dalle facce (pesate sull'area) per i vertici spostati
        fn = np.cross(out[tw[:, 1]] - out[tw[:, 0]], out[tw[:, 2]] - out[tw[:, 0]]); vn = np.zeros_like(out)
        for k in range(3): np.add.at(vn, tw[:, k], fn)
        vn /= np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-12)
        delta = out - Pw
        for P, pacc, N, idx, b in parts:
            w = inv[b:b + len(idx)]; mv = moved[w]
            P[idx[mv]] = (P[idx[mv]].astype(np.float64) + delta[w[mv]]).astype(np.float32)
            if N is not None: N[idx[mv]] = vn[w[mv]].astype(np.float32)
            a = P.astype(np.float64); pacc.min = [float(x) for x in a.min(0)]; pacc.max = [float(x) for x in a.max(0)]
    g.set_binary_blob(bytes(blob)); g.save(o.out or o.glb)
main()
