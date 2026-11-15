"""Chiude a pugno le mani di un modello (i modelli non hanno le ossa delle dita: la mano è scolpita aperta).
Lavora sul GLB così com'è, spostando solo i vertici della mano: scheletro, pesi, animazioni e texture non cambiano.
Le dita (i vertici oltre le nocche, lungo l'asse della mano) si arrotolano verso il palmo attorno a tre pieghe.

uso: python3 tools/hands/fist.py assets/models/nuchra/nuchra.glb [--out file.glb] [--right 1.0] [--left 1.0] [--flip-right] [--flip-left]
  --right/--left: quanto chiudere (0 = lascia aperta, 1 = pugno pieno, 0.75 = presa attorno a un'impugnatura)
  --flip-*: se la mano si chiude dal lato sbagliato (il palmo non è stato riconosciuto)
Tenere sempre l'originale (git): lo script riparte dal file che gli si dà."""
import sys, argparse, struct
import numpy as np
import pygltflib

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}

def view(g, blob, acc_i):
    """vista scrivibile sui dati di un accessor (rispetta byteStride)"""
    a = g.accessors[acc_i]; bv = g.bufferViews[a.bufferView]
    dt = np.dtype(CT[a.componentType]); n = NC[a.type]
    off = (bv.byteOffset or 0) + (a.byteOffset or 0)
    stride = bv.byteStride or dt.itemsize * n
    return np.ndarray((a.count, n), dtype=dt, buffer=blob, offset=off, strides=(stride, dt.itemsize)), a

def smooth(e0, e1, x):
    t = np.clip((x - e0) / max(e1 - e0, 1e-9), 0, 1); return t * t * (3 - 2 * t)

def rot(points, pivot, axis, ang):
    """ruota i punti attorno a un asse (per punto: angolo diverso)"""
    v = points - pivot; c = np.cos(ang)[:, None]; s = np.sin(ang)[:, None]
    return pivot + v * c + np.cross(axis, v) * s + axis * (v @ axis)[:, None] * (1 - c)

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("glb"); ap.add_argument("--out")
    ap.add_argument("--right", type=float, default=1.0); ap.add_argument("--left", type=float, default=1.0)
    ap.add_argument("--flip-right", action="store_true"); ap.add_argument("--flip-left", action="store_true")
    o = ap.parse_args()
    g = pygltflib.GLTF2().load(o.glb); blob = bytearray(g.binary_blob())
    skin = g.skins[0]; names = [g.nodes[j].name for j in skin.joints]
    ibm, _ = view(g, blob, skin.inverseBindMatrices)
    bind = [np.linalg.inv(m.reshape(4, 4).T.astype(np.float64)) for m in ibm]   # matrice globale dell'osso a riposo
    for side, amount, flip in (("Right", o.right, o.flip_right), ("Left", o.left, o.flip_left)):
        if amount <= 0: continue
        hj = names.index(side + "Hand"); fj = names.index(side + "ForeArm")
        W = bind[hj][:3, 3]; F = bind[fj][:3, 3]
        # tutti i vertici della mano, su tutte le parti del modello
        parts = []
        for mesh in g.meshes:
            for pr in mesh.primitives:
                at = pr.attributes
                if at.JOINTS_0 is None or at.POSITION is None: continue
                J, _ = view(g, blob, at.JOINTS_0); Wt, wa = view(g, blob, at.WEIGHTS_0)
                wt = Wt.astype(np.float64)
                if wa.componentType == 5121: wt /= 255.0
                elif wa.componentType == 5123: wt /= 65535.0
                hw = (wt * (J == hj)).sum(1)
                idx = np.nonzero(hw > .5)[0]
                if len(idx) == 0: continue
                P, pacc = view(g, blob, at.POSITION)
                N = view(g, blob, at.NORMAL)[0] if at.NORMAL is not None else None
                T = view(g, blob, at.TANGENT)[0] if at.TANGENT is not None else None
                parts.append((P, pacc, N, T, idx))
        if not parts: print(side, "mano: nessun vertice"); continue
        pts = np.concatenate([p[0][p[4]].astype(np.float64) for p in parts])
        # assi della mano misurati sulla sua forma (ogni modello ha le mani scolpite e orientate a modo suo rispetto
        # all'osso): d lungo le dita partendo dal polso, n attraverso il palmo (lo spessore), s di lato
        d0 = W - F; d0 /= np.linalg.norm(d0)
        c = pts.mean(0); _, _, vt = np.linalg.svd(pts - c, full_matrices=False)
        d = vt[0] if vt[0] @ d0 > 0 else -vt[0]
        if abs(d @ d0) < .6: d = d0
        n = vt[2] - d * (vt[2] @ d); n /= np.linalg.norm(n); s = np.cross(d, n)
        t = (pts - W) @ d; L = np.percentile(t, 99.5)
        u = (pts - W) @ n; v = (pts - W) @ s
        # il palmo è dalla parte verso cui le dita, già a riposo, piegano un poco. Non sempre si capisce:
        # guardare il risultato (tools/hands/handcam.gd) e, se la mano si chiude all'indietro, usare --flip-right/--flip-left
        tips = t > .78 * L; palm = (t > .15 * L) & (t < .45 * L)
        sign = 1.0 if u[tips].mean() - u[palm].mean() > 0 else -1.0
        if flip: sign = -sign
        # pollice: quello che sporge di lato oltre la larghezza delle quattro dita
        fing = t > .7 * L; vc = np.median(v[fing]); half = max(np.percentile(np.abs(v[fing] - vc), 97), .24 * L)
        print(f"{side}: {len(pts)} vertici, lunga {L:.3f}, palmo verso {'+' if sign>0 else '-'}n {np.round(n,2)}, mezza larghezza dita {half:.3f}")
        umid = np.median(u[palm])
        joints = [(.50, 82.0), (.70, 88.0), (.86, 62.0)]   # nocche, falangi: dove (frazione della mano) e di quanto piegano
        for P, pacc, N, T, idx in parts:
            p = P[idx].astype(np.float64); tt = (p - W) @ d; vv = (p - W) @ s
            thumb = smooth(half * 1.05, half * 1.35, np.abs(vv - vc)) * (tt < .8 * L)
            nn = N[idx].astype(np.float64) if N is not None else None
            tg = T[idx, :3].astype(np.float64) if T is not None else None
            pivots = [W + d * (f * L) + n * umid for f, _ in joints]
            for k, (f, deg) in enumerate(joints):
                band = .05 * L
                ang = -sign * np.radians(deg) * amount * smooth(f * L - band, f * L + band, tt) * (1 - thumb)
                piv = pivots[k]
                p = rot(p, piv, s, ang)
                if nn is not None: nn = rot(nn, np.zeros(3), s, ang)
                if tg is not None: tg = rot(tg, np.zeros(3), s, ang)
                # le pieghe più avanti si spostano con il dito (ruotate di tutta la piega)
                full = np.array([-sign * np.radians(deg) * amount])
                for q in range(k + 1, len(pivots)): pivots[q] = rot(pivots[q][None, :], piv, s, full)[0]
            P[idx] = p.astype(np.float32)
            if nn is not None: N[idx] = (nn / np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-9)).astype(np.float32)
            if tg is not None: T[idx, :3] = tg.astype(np.float32)
            allp = P.astype(np.float64); pacc.min = [float(x) for x in allp.min(0)]; pacc.max = [float(x) for x in allp.max(0)]
    g.set_binary_blob(bytes(blob)); g.save(o.out or o.glb); print("scritto", o.out or o.glb)
main()
