"""Chiude a pugno le mani di un modello (i modelli non hanno le ossa delle dita: la mano è scolpita aperta).
Lavora sul GLB così com'è, spostando solo i vertici della mano: scheletro, pesi, animazioni e texture non cambiano.
Le dita (i vertici oltre le nocche, lungo l'asse della mano) si avvolgono in un arco continuo attorno all'impugnatura
dell'arma, là dove l'arma sta davvero nel modello: così il lato del palmo e il raggio della presa non si indovinano.
La mano senza arma prende, specchiate, le misure dell'altra.

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

def node_matrix(nd):
    if nd.matrix: return np.array(nd.matrix, dtype=np.float64).reshape(4, 4).T
    m = np.eye(4)
    if nd.scale: m = m @ np.diag(list(nd.scale) + [1.0])
    if nd.rotation:
        x, y, z, w = nd.rotation
        r = np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)], [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)], [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])
        rm = np.eye(4); rm[:3, :3] = r; m = rm @ m
    if nd.translation: tm = np.eye(4); tm[:3, 3] = nd.translation; m = tm @ m
    return m

def haft_line(g, bind_hand, hand_node):
    """retta dell'impugnatura dell'arma tenuta da questa mano, nello spazio della mesh: (punto, direzione) o None"""
    for want in ("ArmaAzione", "Spada", "SpadaSinistra", "Arma"):
        for k in (g.nodes[hand_node].children or []):
            nd = g.nodes[k]
            if nd.name != want or nd.mesh is None: continue
            lo = np.array([np.inf] * 3); hi = -lo
            for pr in g.meshes[nd.mesh].primitives:
                a = g.accessors[pr.attributes.POSITION]; lo = np.minimum(lo, a.min); hi = np.maximum(hi, a.max)
            ax = np.zeros(3); ax[np.argmax(hi - lo)] = 1.0; cen = (lo + hi) / 2; half = (hi - lo).max() / 2
            m = bind_hand @ node_matrix(nd)
            p0 = (m @ np.append(cen - ax * half, 1.0))[:3]; p1 = (m @ np.append(cen + ax * half, 1.0))[:3]
            return p0, (p1 - p0) / np.linalg.norm(p1 - p0)
    return None

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("glb"); ap.add_argument("--out")
    ap.add_argument("--right", type=float, default=1.0); ap.add_argument("--left", type=float, default=1.0)
    ap.add_argument("--flip-right", action="store_true"); ap.add_argument("--flip-left", action="store_true")
    ap.add_argument("--wrap", type=float, default=205.0, help="gradi di avvolgimento delle dita a pugno pieno")
    o = ap.parse_args()
    g = pygltflib.GLTF2().load(o.glb); blob = bytearray(g.binary_blob())
    skin = g.skins[0]; names = [g.nodes[j].name for j in skin.joints]
    ibm, _ = view(g, blob, skin.inverseBindMatrices)
    bind = [np.linalg.inv(m.reshape(4, 4).T.astype(np.float64)) for m in ibm]   # matrice globale dell'osso a riposo
    measured = None   # misure della mano con l'arma: palmo (vettore), nocche (frazione), raggio (frazione)
    for side, amount, flip in (("Right", o.right, o.flip_right), ("Left", o.left, o.flip_left)):
        hj = names.index(side + "Hand"); fj = names.index(side + "ForeArm")
        W = bind[hj][:3, 3]; F = bind[fj][:3, 3]
        parts = []
        for mesh in g.meshes:
            for pr in mesh.primitives:
                at = pr.attributes
                if at.JOINTS_0 is None or at.POSITION is None: continue
                J, _ = view(g, blob, at.JOINTS_0); Wt, wa = view(g, blob, at.WEIGHTS_0)
                wt = Wt.astype(np.float64)
                if wa.componentType == 5121: wt /= 255.0
                elif wa.componentType == 5123: wt /= 65535.0
                idx = np.nonzero((wt * (J == hj)).sum(1) > .5)[0]
                if len(idx) == 0: continue
                P, pacc = view(g, blob, at.POSITION)
                N = view(g, blob, at.NORMAL)[0] if at.NORMAL is not None else None
                T = view(g, blob, at.TANGENT)[0] if at.TANGENT is not None else None
                parts.append((P, pacc, N, T, idx))
        if not parts: print(side, "mano: nessun vertice"); continue
        pts = np.concatenate([p[0][p[4]].astype(np.float64) for p in parts])
        # assi della mano misurati sulla sua forma: d lungo le dita dal polso, n attraverso il palmo (lo spessore), s di lato
        d0 = W - F; d0 /= np.linalg.norm(d0)
        c = pts.mean(0); _, _, vt = np.linalg.svd(pts - c, full_matrices=False)
        d = vt[0] if vt[0] @ d0 > 0 else -vt[0]
        if abs(d @ d0) < .6: d = d0
        n = vt[2] - d * (vt[2] @ d); n /= np.linalg.norm(n); s = np.cross(d, n)
        t = (pts - W) @ d; L = np.percentile(t, 99.5); u = (pts - W) @ n; v = (pts - W) @ s
        palm = (t > .15 * L) & (t < .45 * L); umid = np.median(u[palm])
        hl = haft_line(g, bind[hj], skin.joints[hj])
        if hl is not None:
            # l'impugnatura passa nel palmo: dice da che parte è il palmo, dove cominciano le dita e quanto è larga la presa
            p0, hd = hl; q = p0 + hd * ((W + d * .5 * L - p0) @ hd)   # punto dell'asta più vicino al centro della mano
            sign = 1.0 if (q - W) @ n > umid else -1.0
            t1 = np.clip((q - W) @ d / L - .08, .38, .6); rb = np.clip(abs((q - W) @ n - umid) / L, .1, .2)
            measured = (sign * n, t1, rb)
            src = "dall'arma"
        elif measured is not None:
            pv = measured[0] * np.array([-1.0, 1.0, 1.0])   # specchio sul piano di simmetria del corpo
            sign = 1.0 if pv @ n > 0 else -1.0; t1 = measured[1]; rb = measured[2]; src = "specchio dell'altra"
        else:
            tips = t > .78 * L; sign = 1.0 if u[tips].mean() - umid > 0 else -1.0; t1 = .5; rb = .14; src = "dalla forma"
        if flip: sign = -sign
        print(f"{side}: {len(pts)} vertici, lunga {L:.3f}, palmo verso {np.round(sign*n,2)} ({src}), nocche a {t1:.2f}, raggio {rb:.2f}")
        if amount <= 0: continue
        T1 = t1 * L; RB = rb * L; e_out = -sign * n            # dal centro della presa verso il dorso delle dita
        fing = t > T1 + .1 * L
        uf = np.median(u[fing]) if fing.sum() > 10 else umid   # metà spessore delle dita
        C = W + d * T1 + n * uf - e_out * RB                    # asse della presa (parallelo a s)
        cap = np.radians(o.wrap) * amount
        for P, pacc, N, T, idx in parts:
            p = P[idx].astype(np.float64); tt = (p - W) @ d - T1; sel = tt > 0
            if not sel.any(): continue
            rel = p[sel] - C; r = np.maximum(rel @ e_out, .15 * RB); vv = rel @ s; x = tt[sel]
            th = np.minimum(x / RB, cap); extra = x - th * RB       # oltre l'arco le dita proseguono dritte
            tang = d[None, :] * np.cos(th)[:, None] - e_out[None, :] * np.sin(th)[:, None]
            rad = e_out[None, :] * np.cos(th)[:, None] + d[None, :] * np.sin(th)[:, None]
            p[sel] = C + rad * r[:, None] + tang * extra[:, None] + s[None, :] * vv[:, None]
            P[idx] = p.astype(np.float32)
            for A, cols in ((N, slice(None)), (T, slice(0, 3))):
                if A is None: continue
                a = A[idx][:, cols].astype(np.float64); b = a[sel]
                b = (b @ d)[:, None] * tang + (b @ e_out)[:, None] * rad + (b @ s)[:, None] * s[None, :]
                a[sel] = b / np.maximum(np.linalg.norm(b, axis=1, keepdims=True), 1e-9)
                if cols == slice(None): A[idx] = a.astype(np.float32)
                else:
                    full = A[idx]; full[:, :3] = a.astype(np.float32); A[idx] = full
            allp = P.astype(np.float64); pacc.min = [float(x) for x in allp.min(0)]; pacc.max = [float(x) for x in allp.max(0)]
    g.set_binary_blob(bytes(blob)); g.save(o.out or o.glb); print("scritto", o.out or o.glb)
main()
