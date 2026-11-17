"""Make a ring's strips join without a seam (docs/game/features/painted-vista.md, T-271).

Three different paintings never match at their ends, so a ring of them shows a step at every
join (the user: "just check that the seems are good"). This makes every strip of a ring end
the same way: a connector, a short window cut from the ring's first strip, is split in half;
each strip's left end fades (over FADE of its width) into the connector's right half, and its
right end into the connector's left half. Whichever two strips meet, the join shows the
connector whole: one continuous piece of the painting. Colour blends premultiplied and the
outline is the union of both ridgelines (`blend`), so no see-through ghost ridges.

The picks are never changed: this writes a derived `<name>-joined.png` beside each, logged in
the manifest (ART-PIPELINE.md, "Never edit a pick's pixels"; derived files as the grass did).

Run:  python -I pipeline/vista/join-strips.py assets/painted-vista near-forest-01 near-forest-01-v1 near-forest-01-v2
"""
import hashlib
import sys

import numpy as np
from PIL import Image

FADE = 0.08  # of the strip's width, at each end

folder, names = sys.argv[1], sys.argv[2:]
strips = [np.asarray(Image.open(f"{folder}/{n}.png").convert("RGBA")).astype(np.float64) / 255 for n in names]
h, w = strips[0].shape[:2]
assert all(s.shape == strips[0].shape for s in strips), "strips differ in size"
f = int(round(w * FADE))

# the connector: 2f columns from the first strip, centred where its ridgeline is lowest in its
# middle half (a saddle, so the join falls between summits)
first = strips[0]
top = np.array([np.argmax(first[:, x, 3] > 0.5) if (first[:, x, 3] > 0.5).any() else h for x in range(w)])
lo, hi = w // 4, 3 * w // 4
centre = lo + int(np.argmax(top[lo:hi]))  # largest row index = lowest ridge
connector = first[:, centre - f:centre + f, :]
left_half, right_half = connector[:, :f, :], connector[:, f:, :]


def premul(a):
    out = a.copy()
    out[..., :3] *= out[..., 3:4]
    return out


def unpremul(a):
    out = a.copy()
    alpha = np.maximum(out[..., 3:4], 1e-6)
    out[..., :3] = np.where(out[..., 3:4] > 0, out[..., :3] / alpha, 0)
    return out


def blend(a, b, t):
    """`a` fading into `b` as t goes 0 to 1. Colour blends premultiplied; the outline is the
    union of both, each counted in only over its own half of the fade, so neither leaves a
    see-through ghost of its ridge over the other's sky, and the ends are exactly a and b."""
    pa, pb = premul(a), premul(b)
    c = pa * (1 - t) + pb * t
    out = unpremul(c)
    wa, wb = np.clip(2 * (1 - t), 0, 1), np.clip(2 * t, 0, 1)
    out[..., 3:4] = np.maximum(a[..., 3:4] * wa, b[..., 3:4] * wb)
    return out


for name, s in zip(names, strips):
    p = s.copy()
    t = (np.arange(f) / (f - 1))[None, :, None]  # 0 at the strip's outer edge
    # left end: connector's right half at the edge, the strip itself by FADE in
    p[:, :f, :] = blend(right_half, s[:, :f, :], t)
    # right end: the strip, then the connector's left half at the edge
    p[:, w - f:, :] = blend(s[:, w - f:, :], left_half, t)
    out = (np.clip(p, 0, 1) * 255 + 0.5).astype(np.uint8)
    path = f"{folder}/{name}-joined.png"
    Image.fromarray(out, "RGBA").save(path)
    digest = hashlib.sha256(open(path, "rb").read()).hexdigest().upper()
    print(f"{path}  connector from {names[0]} x {centre - f}..{centre + f}  sha256 {digest}")
