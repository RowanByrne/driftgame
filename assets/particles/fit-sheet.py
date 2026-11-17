"""Fit a generated particle sheet into an exact flipbook grid (features/tyre-particles.md).

The image tool returns a square canvas (1254 px) with one piece roughly centred in each cell
of an N x N grid. A ParticleEmitter flipbook needs the texture to be an exact multiple of
the grid, with a gutter between frames so mipmaps don't bleed one frame into the next.

For each source cell: crop to the piece (alpha >= 8), scale it uniformly to fit inside the
target cell less the gutter, centre it. Then fill every clear pixel's colour with the
nearest painted colour (edge bleed), so blending and mipmaps show no dark or white fringe.
The master is never changed; this writes a new file.

    python fit-sheet.py <master.png> <out.png> <grid N> [size 1024] [gutter px each side]
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

def fit(src, out, n, size=1024, gutter=None):
    im = Image.open(src).convert("RGBA")
    a = np.array(im)
    h, w = a.shape[:2]
    cell = size // n
    gutter = gutter if gutter is not None else max(6, cell // 32)
    sheet = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    report = []
    # Which frame each painted pixel belongs to: find the pieces' solid cores (alpha >= 64),
    # give each core to the cell its centre is in, then give every painted pixel (alpha >= 8)
    # to its nearest core. So a lobe or a soft halo that strays over a cell line stays with
    # its own piece instead of being cut off.
    paint = a[:, :, 3] >= 8
    cores, count = ndimage.label(a[:, :, 3] >= 64)
    cellOf = np.zeros(count + 1, dtype=int) - 1
    for i, (cy, cx) in enumerate(ndimage.center_of_mass(np.ones((h, w)), cores, range(1, count + 1)), 1):
        cellOf[i] = min(n - 1, int(cy * n / h)) * n + min(n - 1, int(cx * n / w))
    _, (iy, ix) = ndimage.distance_transform_edt(cores == 0, return_indices=True)
    owner = cellOf[cores[iy, ix]]
    owner[~paint] = -1
    # A soft halo far from any core fades out over 20..60 px, so the line between two
    # frames' halos never shows as a straight cut.
    far = np.hypot(iy - np.arange(h)[:, None], ix - np.arange(w)[None, :])
    a = a.copy()
    a[:, :, 3] = (a[:, :, 3] * np.clip((60 - far) / 40, 0, 1)).astype(np.uint8)
    for r in range(n):
        for c in range(n):
            mine = owner == r * n + c
            ys, xs = np.nonzero(mine)
            if len(ys) == 0:
                report.append((r, c, "empty", 0))
                continue
            y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
            part = a[y0:y1, x0:x1].copy()
            part[~mine[y0:y1, x0:x1], 3] = 0
            # How far the piece strays outside its own source cell, in source px.
            stray = max(0, round(r * h / n) - y0, y1 - round((r + 1) * h / n),
                        round(c * w / n) - x0, x1 - round((c + 1) * w / n))
            crop = Image.fromarray(part)
            room = cell - 2 * gutter
            k = min(room / crop.width, room / crop.height)
            crop = crop.resize((max(1, round(crop.width * k)), max(1, round(crop.height * k))), Image.LANCZOS)
            ox = c * cell + (cell - crop.width) // 2
            oy = r * cell + (cell - crop.height) // 2
            sheet.alpha_composite(crop, (ox, oy))
            report.append((r, c, f"{crop.width}x{crop.height}", int(stray)))
    s = np.array(sheet)
    clear = s[:, :, 3] < 8
    if clear.any() and (~clear).any():
        _, (iy, ix) = ndimage.distance_transform_edt(clear, return_indices=True)
        s[:, :, :3] = s[iy, ix, :3]
        s[clear, 3] = 0
    Image.fromarray(s).save(out, optimize=True)
    return report

if __name__ == "__main__":
    args = sys.argv[1:]
    rep = fit(args[0], args[1], int(args[2]), int(args[3]) if len(args) > 3 else 1024,
              int(args[4]) if len(args) > 4 else None)
    stray = [f"r{r}c{c} {e}px" for r, c, _, e in rep if e > 0]
    empty = sum(1 for _, _, d, _ in rep if d == "empty")
    print(f"{args[1]}: {len(rep)} frames, {empty} empty, over a cell line: {', '.join(stray) or 'none'}")
