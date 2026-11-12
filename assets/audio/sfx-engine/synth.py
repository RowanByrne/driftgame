# Procedural inline-4 engine: circular (seamless) loops at fixed rpm, on- and off-load.
import sys, numpy as np, soundfile as sf
SR = 48000
rng_master = np.random.default_rng(7)

def damped(f, t60, n):
    t = np.arange(n)/SR
    return np.sin(2*np.pi*f*t) * np.exp(-6.91*t/t60)

def onepole_lp(x, fc):
    a = np.exp(-2*np.pi*fc/SR); y = np.empty_like(x); s = 0.0
    for i in range(len(x)): s = (1-a)*x[i] + a*s; y[i] = s
    return y

def fft_filter(x, lo, hi, slope=2):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1/SR)
    g = 1/(1+(lo/np.maximum(f,1))**(2*slope)) if lo else 1
    g = g * (1/(1+(f/hi)**(2*slope)) if hi else 1)
    return np.fft.irfft(X*g, len(x))

def engine_loop(rpm, load, seconds=2.0, seed=1):
    rng = np.random.default_rng(seed)
    fire = rpm/30.0                    # inline-4, 4-stroke: 2 firings per rev
    cycles = max(1, round(seconds*rpm/120))   # whole engine cycles (720 deg) -> seamless
    n = int(round(cycles*120/rpm*SR))
    per = n/(cycles*4)
    train = np.zeros(n)
    cyl_amp = np.array([1.0, 0.86, 0.95, 0.80])   # uneven cylinders give the 4-pot texture
    cyl_off = np.array([0.0, 0.03, -0.02, 0.015])
    for k in range(cycles*4):
        c = k % 4
        pos = (k + cyl_off[c] + rng.normal(0, 0.012)) * per
        i = int(pos) % n
        a = cyl_amp[c] * (1 + rng.normal(0, 0.06))
        if load < 0.5: a *= (0.35 + 0.65*rng.random()**2)    # off-load: weak, uneven burble
        train[i] += a
    # pulse kernel: exhaust resonances + combustion noise burst
    kn = int(0.03*SR)
    t60 = 0.010 + 0.018*(1-load)
    br = 0.5 + 0.5*load
    kern = (1.0*damped(95, t60*2.2, kn) + 0.8*damped(210, t60*1.5, kn)
            + 0.55*br*damped(440, t60, kn) + 0.3*br*damped(980, t60*0.6, kn))
    nb = rng.normal(0, 1, kn) * np.exp(-np.arange(kn)/SR/(0.002+0.003*load))
    kern += (0.9*load + 0.25) * fft_filter(np.pad(nb,(0,0)), 200, 3500)
    # circular convolution => seamless loop
    y = np.fft.irfft(np.fft.rfft(train) * np.fft.rfft(kern, n), n)
    # intake / mechanical hiss, tied to rpm, circular-safe (generated at length n)
    hiss = fft_filter(rng.normal(0, 1, n), 1500, 6000) * (0.02 + 0.05*load*rpm/7000)
    y += hiss * (1 + 0.5*np.sin(2*np.pi*np.arange(n)/n*cycles*4))
    # pipe body: gentle low shelf for weight
    y = y + 0.6*fft_filter(y, 0, 160)
    # brightness rises with rpm and load
    y = fft_filter(y, 30, 1800 + 2600*load + 900*rpm/7000, slope=1)
    y /= np.max(np.abs(y)) + 1e-9
    return y*0.8

def render_sweep(loops, path_rpm, path_load, dur):
    # crossfade between fixed-rpm loops, each pitched around its own rpm (the planned layering)
    n = int(dur*SR); out = np.zeros(n)
    rpms = sorted(loops)
    blk = 256
    phases = {k: 0.0 for k in loops}
    for b in range(0, n, blk):
        t = b/SR; r = path_rpm(t); L = path_load(t)
        # weights: triangular between neighbouring loop rpms
        w = {}
        for j, base in enumerate(rpms):
            lo = rpms[j-1] if j > 0 else None; hi = rpms[j+1] if j+1 < len(rpms) else None
            if r <= base:
                v = 1.0 if lo is None else max(0, (r-lo)/(base-lo))
            else:
                v = 1.0 if hi is None else max(0, (hi-r)/(hi-base))
            w[base] = v
        for base in rpms:
            if w[base] <= 0.001: 
                phases[base] += blk*r/base; continue
            rate = r/base
            for loadkey, gain in (("on", L), ("off", 1-L)):
                src = loops[base][loadkey]; m = len(src)
                idx = (phases[base] + np.arange(blk)*rate) % m
                i0 = idx.astype(int); fr = idx - i0
                seg = src[i0]*(1-fr) + src[(i0+1) % m]*fr
                out[b:b+blk] += seg[:min(blk, n-b)] * w[base] * gain * (0.55 + 0.45*L)
            phases[base] += blk*rate
    return out/np.max(np.abs(out))*0.85

if __name__ == "__main__":
    outdir = sys.argv[1]
    loops = {}
    for rpm in (1000, 3000, 5000, 7000):
        loops[rpm] = {"on": engine_loop(rpm, 1.0, seed=rpm), "off": engine_loop(rpm, 0.0, seed=rpm+1)}
        for k in ("on", "off"):
            sf.write(f"{outdir}/synth-{rpm}-{k}.ogg", loops[rpm][k], SR, format="OGG", subtype="VORBIS")
    # demo: idle, pull through, drift (revs up, held, feathered), limiter, lift, hook-up
    def rpm_path(t):
        if t < 1.5: return 1000
        if t < 4.0: return 1000 + (t-1.5)/2.5*5000
        if t < 4.4: return 6000 - (t-4.0)/0.4*2000
        if t < 6.0: return 4000 + (t-4.4)/1.6*2200
        if t < 6.3: return 6200 + (t-6.0)/0.3*800           # flare
        if t < 9.5: return 6600 + 300*np.sin(2*np.pi*1.6*(t-6.3))  # feathering in the drift
        if t < 10.5: return 7000 - 250*(np.floor((t-9.5)*12) % 2)  # limiter bounce
        if t < 11.3: return 7000 - (t-10.5)/0.8*3200           # lift / hook-up
        return 3800
    def load_path(t):
        if t < 1.5: return 0.2
        if 4.0 <= t < 4.4: return 0.0
        if 10.5 <= t < 11.3: return 0.0
        if 9.5 <= t < 10.5: return 0.0 if (np.floor((t-9.5)*12) % 2) else 1.0
        return 1.0
    demo = render_sweep(loops, rpm_path, load_path, 12.5)
    sf.write(f"{outdir}/synth-demo-drive.ogg", demo, SR, format="OGG", subtype="VORBIS")
    print("ok")
