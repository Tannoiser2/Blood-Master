"""Effetti sonori di Blood Master, sintetizzati da zero (nessun campione esterno).

Uso:  python3 tools/audio/synth.py      -> assets/audio/*.ogg

Ogni suono ha più varianti (nome_1, nome_2, ...): board3d.gd ne sceglie una a caso.
Per sostituirne uno con una registrazione vera basta mettere un file con lo stesso
nome in assets/audio/ (.ogg o .wav).
"""
import subprocess, tempfile
from pathlib import Path
import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 22050
OUT = Path(__file__).resolve().parents[2] / 'assets/audio'
OUT.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(7)


def t(d):
    return np.arange(int(SR * d)) / SR


def env(n, a=.005, d=.3, curve=4.0):
    x = np.arange(n) / SR
    att = np.clip(x / max(a, 1e-4), 0, 1)
    return att * np.exp(-curve * np.maximum(x - a, 0) / d)


def bp(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), min(hi / (SR / 2), .99)], 'band')
    return signal.lfilter(b, a, x)


def lp(x, f, order=2):
    b, a = signal.butter(order, min(f / (SR / 2), .99), 'low'); return signal.lfilter(b, a, x)


def hp(x, f, order=2):
    b, a = signal.butter(order, f / (SR / 2), 'high'); return signal.lfilter(b, a, x)


def noise(d):
    return rng.standard_normal(int(SR * d))


def save(name, x, gain=.9):
    x = np.asarray(x, dtype=float)
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    fade = min(len(x), int(SR * .01)); x[-fade:] *= np.linspace(1, 0, fade)
    with tempfile.NamedTemporaryFile(suffix='.wav') as f:
        wavfile.write(f.name, SR, (x * 32767).astype(np.int16))
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', f.name, '-c:a', 'libvorbis', '-q:a', '4',
                        str(OUT / f'{name}.ogg')], check=True)


def mix(*parts):
    n = max(len(p) for p in parts); y = np.zeros(n)
    for p in parts:
        y[:len(p)] += p
    return y


def at(x, start, total):
    y = np.zeros(int(SR * total)); s = int(SR * start); y[s:s + len(x)] += x[:len(y) - s]; return y


# ---------------------------------------------------------------- armi
def whoosh(d=.32, lo=300, hi=2600):
    n = noise(d); k = len(n)
    out = np.zeros(k); seg = 256
    for s in range(0, k, seg):              # filtro passa banda che sale e scende: il fendente
        ph = s / k; f = lo + (hi - lo) * np.sin(np.pi * ph) ** 1.5
        out[s:s + seg] = bp(n[max(0, s - 512):s + seg], f * .7, f * 1.4)[-len(n[s:s + seg]):]
    return out * np.sin(np.pi * np.linspace(0, 1, k)) ** 2


def clash(d=.9, base=900):
    x = t(d); y = np.zeros_like(x)
    for r, a in ((1, 1), (2.76, .7), (5.40, .5), (8.93, .35), (13.3, .2)):   # modi inarmonici del metallo
        f = base * r * rng.uniform(.98, 1.02)
        y += a * np.sin(2 * np.pi * f * x + rng.uniform(0, 6)) * np.exp(-x * (3 + r * 1.6))
    hit = hp(noise(.03), 2000) * env(int(SR * .03), .0005, .01, 3)
    return mix(y * .6, hit)


def flesh(d=.35):
    x = t(d)
    thud = np.sin(2 * np.pi * (90 - 40 * x / d) * x) * env(len(x), .002, .09, 4)
    crunch = lp(noise(d), 1800) * env(len(x), .001, .05, 5)
    return mix(thud, crunch * .7)


def armor_hit(d=.5):
    return mix(flesh(d) * .8, clash(d, 420) * .35)


def step_sand(d=.16):
    x = noise(d); return bp(x, 250, 2200) * env(len(x), .004, .05, 5)


def fall(d=.7):
    a = flesh(.4); b = lp(noise(.5), 700) * env(int(SR * .5), .01, .2, 4)
    return mix(a, at(b * .8, .08, d), at(step_sand(.2) * .5, .18, d))


def bow_twang(d=.6):
    x = t(d); f = 140 * (1 + .25 * np.exp(-x * 30))
    s = np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)) * .3 + np.sin(2 * np.pi * np.cumsum(f) / SR)
    return mix(lp(s, 1500) * env(len(x), .001, .12, 4), hp(noise(.05), 3000) * env(int(SR * .05), .0005, .01, 3) * .3)


def bow_draw(d=.7):
    x = t(d); creak = np.sin(2 * np.pi * (60 + 25 * x) * x) * (1 + .5 * np.sin(2 * np.pi * 23 * x))
    return mix(lp(creak, 900) * np.linspace(.2, 1, len(x)) * .5, bp(noise(d), 1500, 4000) * .08)


def arrow_hit(d=.3):
    return mix(flesh(d) * .9, hp(noise(.02), 1500) * env(int(SR * .02), .0005, .006, 3))


def arrow_ground(d=.35):
    x = t(d); thunk = np.sin(2 * np.pi * 180 * x) * env(len(x), .001, .04, 4)
    return mix(thunk, bp(noise(d), 300, 1800) * env(len(x), .001, .08, 4) * .8)


# ---------------------------------------------------------------- voci (sintesi a formanti)
VOWELS = {'a': (800, 1200, 2500, 3400), 'o': (500, 900, 2400, 3300), 'e': (550, 1800, 2500, 3500),
          'u': (350, 750, 2400, 3300), 'aa_f': (950, 1400, 2900, 3900), 'e_f': (650, 2100, 2900, 4000)}


def glottal(f0, rasp=.0):
    ph = np.cumsum(f0 / SR) % 1.0
    g = np.where(ph < .6, .5 - .5 * np.cos(np.pi * ph / .6), np.cos(np.pi * (ph - .6) / .8) ** 2 * (ph < 1))
    g = np.diff(g, prepend=0)
    if rasp:
        g = g * (1 + rasp * rng.standard_normal(len(g)))
    return g


def voice(f0, vowel_from, vowel_to, d, rasp=.25, breath=.15, bw=(90, 110, 160, 200)):
    n = int(SR * d); src = glottal(f0[:n], rasp) * 40 + breath * hp(noise(d), 800)
    k = np.linspace(0, 1, n) ** .8
    F0, F1 = np.array(VOWELS[vowel_from]), np.array(VOWELS[vowel_to])
    out = np.zeros(n); seg = 256
    for s in range(0, n, seg):
        F = F0 + (F1 - F0) * k[s]; chunk = src[max(0, s - 768):s + seg]; y = np.zeros(len(chunk))
        for f, b, a in zip(F, bw, (1, .7, .35, .2)):
            y += a * bp(chunk, max(60, f - b), f + b)
        out[s:s + seg] = y[-len(src[s:s + seg]):]
    return np.tanh(out * 2.5)


def contour(d, start, peak, end, peak_at=.15, vib=4.5, jitter=.012):
    x = t(d); p = x / d
    f = np.where(p < peak_at, start + (peak - start) * p / peak_at, peak + (end - peak) * (p - peak_at) / (1 - peak_at))
    return f * (1 + .015 * np.sin(2 * np.pi * vib * x)) * (1 + jitter * rng.standard_normal(len(x)).cumsum() / 60)


def shout(kind, d, f0s, vowels, rasp, amp_shape='pain'):
    f = contour(d, *f0s)
    v = voice(f, vowels[0], vowels[1], d, rasp=rasp)
    a = env(len(v), .03 if amp_shape == 'pain' else .01, d * .55, 2.2)
    return v * a


def growl(d=.9, f0=55):
    f = contour(d, f0 * .9, f0 * 1.15, f0 * .8, .3, 7, .03)
    v = voice(f, 'o', 'u', d, rasp=.9, breath=.4)
    return mix(v * env(len(v), .05, d * .6, 2), lp(noise(d), 400) * env(int(SR * d), .05, d * .5, 2) * .3)


# ---------------------------------------------------------------- magia
def shimmer(d=1.1, base=880):
    x = t(d); y = np.zeros_like(x)
    for k in range(9):
        f = base * (1.5 ** (k % 5)) * rng.uniform(.99, 1.01); st = rng.uniform(0, .45)
        y += np.sin(2 * np.pi * f * x) * np.exp(-np.maximum(x - st, 0) * 5) * (x > st)
    return mix(y * env(len(x), .05, .6, 2), bp(noise(d), 4000, 9000) * env(len(x), .02, .4, 3) * .25)


def fire(d=1.0):
    n = noise(d); roar = lp(n, 500) * (1 + .5 * np.sin(2 * np.pi * 3 * t(d)))
    crack = np.zeros(len(n))
    for _ in range(25):
        p = rng.integers(0, len(n) - 200); crack[p:p + 60] += hp(rng.standard_normal(60), 2500) * rng.uniform(.3, 1)
    return (roar + crack * .5) * env(len(n), .08, d * .6, 2)


def thunder(d=1.2):
    crack = hp(noise(.08), 1500) * env(int(SR * .08), .0005, .02, 3)
    rumble = lp(noise(d), 180) * env(int(SR * d), .01, d * .5, 2.5)
    return mix(crack * 1.2, rumble * 2)


def dark(d=1.3):
    x = t(d); s = sum(np.sin(2 * np.pi * f * x) for f in (55, 58.3, 82.4)) * env(len(x), .2, d * .7, 2)
    return mix(s, lp(noise(d), 300) * env(len(x), .2, d * .6, 2) * .6)


def heal(d=1.2):
    x = t(d); y = sum(np.sin(2 * np.pi * f * x) * np.exp(-x * 2.5) * (x > st) for f, st in ((523, 0), (659, .12), (784, .24), (1046, .36)))
    return mix(y, shimmer(d, 1320) * .3)


def swirl(d=1.1):
    w = whoosh(d, 200, 1400); x = t(d)
    return mix(w * (1 + .6 * np.sin(2 * np.pi * 6 * x[:len(w)])), np.sin(2 * np.pi * (300 + 200 * np.sin(2 * np.pi * 2 * x)) * x) * env(len(x), .1, .6, 2) * .2)


def build():
    for k in range(3):
        save(f'swing_{k + 1}', whoosh(rng.uniform(.25, .38), rng.uniform(250, 400), rng.uniform(2000, 3200)), .6)
        save(f'clash_{k + 1}', clash(.9, rng.uniform(700, 1200)))
        save(f'hit_{k + 1}', armor_hit(.5) if k == 2 else flesh(.35))
    for k in range(4):
        save(f'step_{k + 1}', step_sand(rng.uniform(.12, .18)), .35)
    save('fall_1', fall()); save('fall_2', fall(.8))
    save('bow_draw_1', bow_draw(), .5); save('bow_release_1', bow_twang()); save('bow_release_2', bow_twang(.5))
    save('arrow_hit_1', arrow_hit()); save('arrow_ground_1', arrow_ground())
    # voci: uomo, donna, mostro (Thorn), spirito (Ziggy)
    for k, (d, f0s, vw) in enumerate([(.75, (150, 240, 120), ('a', 'o')), (.6, (170, 260, 140), ('a', 'u')),
                                      (.9, (130, 210, 100), ('e', 'a'))]):
        save(f'pain_m_{k + 1}', shout('m', d, f0s, vw, .35), .8)
    for k, (d, f0s, vw) in enumerate([(.7, (330, 520, 280), ('aa_f', 'e_f')), (.6, (360, 560, 300), ('aa_f', 'aa_f'))]):
        save(f'pain_f_{k + 1}', shout('f', d, f0s, vw, .2), .8)
    for k in range(3):
        save(f'grunt_m_{k + 1}', shout('m', rng.uniform(.25, .35), (140, 170, 120, .3), ('a', 'o'), .5, 'effort'), .6)
    for k in range(2):
        save(f'grunt_f_{k + 1}', shout('f', rng.uniform(.22, .3), (300, 360, 270, .3), ('aa_f', 'e_f'), .3, 'effort'), .6)
    save('death_m_1', shout('m', 1.5, (170, 250, 80, .1), ('a', 'u'), .45), .85)
    save('death_f_1', shout('f', 1.4, (380, 600, 200, .1), ('aa_f', 'u'), .25), .85)
    save('pain_monster_1', growl(.9, 60)); save('pain_monster_2', growl(.7, 70)); save('death_monster_1', growl(1.6, 50))
    save('grunt_monster_1', growl(.4, 75), .6)
    save('pain_spirit_1', mix(swirl(.7) * .6, shimmer(.7, 1500) * .3)); save('death_spirit_1', swirl(1.6))
    for k in range(2):   # scheletri: ossa che sbattono
        y = np.zeros(int(SR * .6))
        for _ in range(14):
            p = rng.integers(0, len(y) - 900); c = bp(rng.standard_normal(900), 900, 3200) * env(900, .0005, .012, 3)
            y[p:p + 900] += c * rng.uniform(.3, 1)
        save(f'pain_bones_{k + 1}', y, .7)
    y = np.zeros(int(SR * 1.2))
    for _ in range(40):
        p = rng.integers(0, len(y) - 900); y[p:p + 900] += bp(rng.standard_normal(900), 700, 3000) * env(900, .0005, .015, 3) * rng.uniform(.2, 1)
    save('death_bones_1', y, .8)
    save('cast_1', shimmer()); save('cast_2', shimmer(1.0, 660))
    save('spell_fire_1', fire()); save('spell_lightning_1', thunder()); save('spell_dark_1', dark())
    save('spell_heal_1', heal()); save('spell_wind_1', swirl())
    print('suoni:', len(list(OUT.glob('*.ogg'))))


if __name__ == '__main__':
    build()
