# Final synthesized engine set: loops at fixed rpm, on/off load, loudness-matched,
# packed into one "sheet" file with each loop at a known region (one upload).
import sys, json, numpy as np, soundfile as sf
sys.path.insert(0, sys.argv[1]); import synth
SR = synth.SR
out = sys.argv[2]
RPMS = [900, 1370, 2090, 3190, 4860, 7400]
SLOT = 2.6          # seconds per slot in the sheet (2 s loop + 0.25 s of itself each side)
LOOP_S = 2.0        # target loop length (whole engine cycles)
TARGET_RMS = 0.16

def write_ogg(path, y):
    # libsndfile's Vorbis writer overflows its stack on long single writes: write in blocks.
    with sf.SoundFile(path, "w", SR, 1, format="OGG", subtype="VORBIS") as f:
        for i in range(0, len(y), 8192):
            f.write(y[i:i+8192])

def norm(y):
    r = np.sqrt((y**2).mean()); y = y * (TARGET_RMS / max(r, 1e-9))
    pk = np.max(np.abs(y))
    if pk > 0.98: y *= 0.98/pk
    return y

loops, regions = {}, []
sheet = np.zeros(int(SLOT*SR*len(RPMS)*2))
slot = 0
for rpm in RPMS:
    for load, key in ((1.0, "on"), (0.0, "off")):
        y = norm(synth.engine_loop(rpm, load, seconds=LOOP_S, seed=rpm*10 + (1 if key == "off" else 0)))
        loops[(rpm, key)] = y
        # PADDED WITH ITSELF: a quarter second of the loop's own end before it and of its
        # start after it, so the codec's smear at the region's edges is continuous engine
        # sound, not silence, and the wrap the game makes is seamless.
        pad = int(0.25*SR)
        base = int(round(slot*SLOT*SR))
        i0 = base + pad
        sheet[base:i0] = y[-pad:]
        sheet[i0:i0+len(y)] = y
        sheet[i0+len(y):i0+len(y)+pad] = y[:pad]
        regions.append({"rpm": rpm, "load": key, "start": round(i0/SR, 6), "length": round(len(y)/SR, 6)})
        write_ogg(f"{out}/loop-{rpm}-{key}.ogg", y)
        slot += 1
write_ogg(f"{out}/engine-sheet.ogg", sheet)
json.dump(regions, open(f"{out}/engine-sheet-regions.json", "w"), indent=1)

# Demo through the layering the game will do (neighbouring loops crossfaded by rpm, each pitched
# around its own rpm, on/off by load), on the same scripted drive as the first demo.
ldict = {r: {"on": loops[(r, "on")], "off": loops[(r, "off")]} for r in RPMS}
def rpm_path(t):
    if t < 1.5: return 900
    if t < 4.0: return 900 + (t-1.5)/2.5*5900
    if t < 4.4: return 6800 - (t-4.0)/0.4*2300
    if t < 6.0: return 4500 + (t-4.4)/1.6*1800
    if t < 6.3: return 6300 + (t-6.0)/0.3*700
    if t < 9.5: return 6700 + 250*np.sin(2*np.pi*1.6*(t-6.3))
    if t < 10.5: return 7400 - 420*(np.floor((t-9.5)*14) % 2)
    if t < 11.3: return 7400 - (t-10.5)/0.8*3300
    return 4100
def load_path(t):
    if t < 1.5: return 0.15
    if 4.0 <= t < 4.15: return 0.0
    if 10.5 <= t < 11.3: return 0.0
    if 9.5 <= t < 10.5: return 0.0 if (np.floor((t-9.5)*14) % 2) else 1.0
    return 1.0
demo = synth.render_sweep(ldict, rpm_path, load_path, 12.5)
write_ogg(f"{out}/demo-drive.ogg", demo)
print(json.dumps(regions[:3]), "...", len(regions), "regions; sheet", round(len(sheet)/SR,1), "s")
