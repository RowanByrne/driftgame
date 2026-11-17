"""Make a ring's strips join without a seam (docs/game/features/painted-vista.md, T-271).

Three different paintings never match at their ends, so a ring of them shows a step at every
join (the user: "just check that the seems are good"). This makes every strip of a ring end
the same way: a connector, a short window cut from the ring's first strip, is split in half;
each strip's left end fades (over FADE of its width) into the connector's right half, and its
right end into the connector's left half. Whichever two strips meet, the join shows the
connector whole: one continuous piece of the painting. The ridgeline morphs from one to the
other and the land beneath blends (`blend`), so there is no see-through ghost of either ridge.

The picks are never changed: this writes a derived `<name>-joined.png` beside each, logged in
the manifest (ART-PIPELINE.md, "Never edit a pick's pixels"; derived files as the grass did).

Run on a folder outside git holding the picks (`..rtsourcepainted-vista`), then copy only the
`-joined` results the game uses into assets/painted-vista:
  python -I pipeline/vista/join-strips.py ../art/source/painted-vista near-forest-01-clear near-forest-01-v1-clear near-forest-01-v2-clear
"""
import hashlib
import sys

import numpy as np
from PIL import Image

FADE = 0.08  # of the strip's width, at each end
SOLID_FROM, SOLID_TO = 32 / 255, 192 / 255  # alpha below is clear, above is solid

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


def ridge_rows(a):
    """Each column's ridgeline: the first row that is solid, or the height if none is."""
    solid = a[..., 3] > 0.5
    return np.where(solid.any(axis=0), solid.argmax(axis=0), a.shape[0])


def blend(a, b, t):
    """`a` fading into `b` as t goes 0 to 1, the ends exactly a and b. The ridgeline morphs from
    a's to b's, column by column, so there is one solid outline and no see-through ghost of
    either ridge (a plain cross-fade, or the union of both outlines, left blurred bumps on the
    ridgeline at every join). Below it, where both are solid the colours blend; where only one
    is, that one shows."""
    hgt = a.shape[0]
    ra, rb = ridge_rows(a), ridge_rows(b)
    tt = t[0, :, 0]
    line = ra * (1 - tt) + rb * tt
    rows = np.arange(hgt)[:, None]
    alpha = np.clip(rows - line[None, :] + 1, 0, 1)  # a one-pixel soft edge
    sa, sb = (a[..., 3] > 0.5)[..., None], (b[..., 3] > 0.5)[..., None]
    wa = np.where(sa & sb, 1 - t, np.where(sa, 1.0, 0.0))
    wb = np.where(sa & sb, t, np.where(sb, 1.0, 0.0))
    total = np.maximum(wa + wb, 1e-6)
    rgb = (a[..., :3] * wa + b[..., :3] * wb) / total
    # rows under the morphed line that neither paints solidly: take the nearer end's colour
    neither = ~(sa | sb)
    rgb = np.where(neither, np.where(t < 0.5, a[..., :3], b[..., :3]), rgb)
    out = np.concatenate([rgb, alpha[..., None]], axis=2)
    return out


for name, s in zip(names, strips):
    p = s.copy()
    t = (np.arange(f) / (f - 1))[None, :, None]  # 0 at the strip's outer edge
    # left end: connector's right half at the edge, the strip itself by FADE in
    p[:, :f, :] = blend(right_half, s[:, :f, :], t)
    # right end: the strip, then the connector's left half at the edge
    p[:, w - f:, :] = blend(s[:, w - f:, :], left_half, t)
    # SOLID: the image tool paints the land at alpha 200-254, never 255, so each ring let the
    # rings and skirts behind it show through as boxes at its panels' edges (lane 1). Land is
    # made fully opaque; only a soft edge of a few pixels stays along the ridgeline.
    p[..., 3] = np.clip((p[..., 3] - SOLID_FROM) / (SOLID_TO - SOLID_FROM), 0, 1)
    out = (np.clip(p, 0, 1) * 255 + 0.5).astype(np.uint8)
    path = f"{folder}/{name}-joined.png"
    Image.fromarray(out, "RGBA").save(path)
    digest = hashlib.sha256(open(path, "rb").read()).hexdigest().upper()
    print(f"{path}  connector from {names[0]} x {centre - f}..{centre + f}  sha256 {digest}")
