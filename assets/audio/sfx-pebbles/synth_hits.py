# Our own stones-on-sheet-steel hits, modal synthesis. Writes a sheet (one file, hits at known
# offsets) and its region table. Deterministic (seeded).
import numpy as np, soundfile as sf, json, sys
SR = 48000
def hp(x, fc):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1/SR); X[f < fc] *= (f[f < fc]/fc)**2; return np.fft.irfft(X, len(x))
def hit(rng, heavy):
    L = int((0.30 if heavy else 0.16)*SR); t = np.arange(L)/SR; y = np.zeros(L)
    # the stone's contact: a very short bright burst
    nb = int(rng.uniform(0.0004, 0.0012)*SR)
    burst = rng.standard_normal(nb) * np.hanning(nb)
    y[:nb] += hp(np.pad(burst, (0, 64)), 2500)[:nb] * (0.6 if heavy else 0.9)
    # the panel: damped modes, inharmonic, a couple of them strong (the "ping")
    n = 14
    lo, hi = (180, 3500) if heavy else (900, 7500)
    for k in range(n):
        f0 = np.exp(rng.uniform(np.log(lo), np.log(hi)))
        tau = rng.uniform(0.012, 0.07 if not heavy else 0.11) * (1500/f0)**0.35
        a = rng.uniform(0.2, 1.0) * (1.6 if k < 2 else 1.0) / (f0/1000)**0.25
        y += a * np.exp(-t/tau) * np.sin(2*np.pi*f0*t + rng.uniform(0, 6.28))
    if heavy:  # the hollow box behind the panel: a low thunk
        f1 = rng.uniform(95, 170); y += 2.2*np.exp(-t/0.035)*np.sin(2*np.pi*f1*t)
    # a little grit after the hit
    g = rng.standard_normal(L) * np.exp(-t/0.012) * 0.15; y += hp(g, 3000)
    att = np.minimum(1, t/0.0003); y *= att
    fade = int(0.02*SR); y[-fade:] *= np.linspace(1, 0, fade)
    return y/np.abs(y).max()*0.7
rng = np.random.default_rng(29217)
hits = [(hit(rng, False), False) for _ in range(24)] + [(hit(rng, True), True) for _ in range(8)]
gap = int(0.05*SR); sheet = [np.zeros(gap)]; regions = []; pos = gap
for y, heavy in hits:
    regions.append({"start": round(pos/SR, 4), "length": round(len(y)/SR, 4), "clack": heavy, "gain": 0.714})
    sheet += [y, np.zeros(gap)]; pos += len(y) + gap
sheet = np.concatenate(sheet)
out = sys.argv[1]
with sf.SoundFile(out, "w", SR, 1, format="OGG", subtype="VORBIS") as f:
    for i in range(0, len(sheet), 8192): f.write(sheet[i:i+8192])
json.dump(regions, open(out.replace(".ogg", "-regions.json"), "w"), indent=1)
print(len(regions), "hits,", round(len(sheet)/SR, 2), "s")
