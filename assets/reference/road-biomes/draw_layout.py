"""Rebuild the T-203 layout review diagrams. Run beside this file; requires Pillow.

These are design sketches, not generated game geometry or measured driving results.
All output paths are relative to this source file.
"""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent
W, H = 1800, 1320
BG, PANEL = '#101b21', '#18282f'
INK, MUTED = '#edf3ed', '#b6c8ca'
FIELD, SMALL, STEEP = '#98bc70', '#d9b277', '#bcb2c8'
ROAD, EDGE = '#49545b', '#f2e9cd'


def font(size, bold=False):
    name = 'DejaVuSans-Bold.ttf' if bold else 'DejaVuSans.ttf'
    try:
        return ImageFont.truetype(name, size)
    except OSError:
        return ImageFont.load_default(size=size)


def text(d, xy, words, size=24, fill=INK, bold=False, anchor=None):
    d.text(xy, words, font=font(size, bold), fill=fill, anchor=anchor)


def line(d, pts, fill=INK, width=3):
    d.line(pts, fill=fill, width=width, joint='curve')


def arrow(d, a, b, fill=INK, width=4):
    line(d, [a, b], fill, width)
    angle = math.atan2(b[1] - a[1], b[0] - a[0])
    tip = [(b[0] - 17 * math.cos(angle + off), b[1] - 17 * math.sin(angle + off))
           for off in [-0.48, 0.48]]
    d.polygon([b, *tip], fill=fill)


def title(d, heading, sub):
    text(d, (64, 46), heading, 43, bold=True)
    text(d, (66, 108), sub, 23, MUTED)


def route():
    im = Image.new('RGB', (W, H), BG)
    d = ImageDraw.Draw(im)
    title(d, 'Linked mountain biomes',
          'T-203 / Layout proposal v1 / Representative route, not a fixed map or generated seed')
    d.rounded_rectangle((48, 164, 1752, 815), radius=24, fill=PANEL)
    # Five linked legs; bends here communicate rhythm, not construction radii.
    bands = [(FIELD, 205, 310), (SMALL, 320, 423), (STEEP, 433, 544),
             (SMALL, 554, 653), (FIELD, 663, 776)]
    for col, y0, y1 in bands:
        d.rounded_rectangle((85, y0, 1510, y1), radius=38, fill=col)
    labels = [('Fields', '0 - 2,400', 255), ('Small cliffs', '2,400 - 4,500', 370),
              ('Steep ridge', '4,500 - 6,900', 486), ('Small cliffs', '6,900 - 9,000', 602),
              ('Fields', '9,000 - 12,000', 720)]
    for name, dist, y in labels:
        text(d, (110, y - 27), name, 27, BG, True)
        text(d, (110, y + 10), dist + ' studs', 20, BG)
    paths = [
        [(410 + i * 10, 255 + 18 * math.sin(i / 22)) for i in range(105)],
        [(1450 - i * 10, 370 + 23 * math.sin(i / 13)) for i in range(105)],
        [(410 + i * 10, 486 + 27 * math.sin(i / 5.2)) for i in range(105)],
        [(1450 - i * 10, 602 + 23 * math.sin(i / 13)) for i in range(105)],
        [(410 + i * 10, 720 + 18 * math.sin(i / 22)) for i in range(105)],
    ]
    for pts in paths:
        line(d, pts, EDGE, 19)
        line(d, pts, ROAD, 14)
    # Broad hairpin connections; each highlighted window is a 480-stud morph.
    for n in range(4):
        right = n % 2 == 0
        x = 1450 if right else 410
        y0, y1 = paths[n][-1][1], paths[n + 1][0][1]
        pts = [(x + (70 if right else -70) * math.sin(math.pi * i / 40),
                y0 + (y1 - y0) * i / 40) for i in range(41)]
        line(d, pts, EDGE, 19)
        line(d, pts, ROAD, 14)
        d.rounded_rectangle((x - 51, y0 - 13, x + 51, y1 + 13), radius=20,
                            outline='#f3d27b', width=4)
    text(d, (1544, 238), 'Mountain', 22, MUTED)
    text(d, (1544, 270), 'fall line', 22, MUTED)
    arrow(d, (1620, 315), (1620, 676), '#acc9d3', 5)
    text(d, (1544, 714), 'Downhill', 22, MUTED)
    text(d, (410, 194), 'Start', 21, BG, True)
    arrow(d, (650, 240), (760, 240), EDGE, 3)
    arrow(d, (1070, 727), (1180, 727), EDGE, 3)
    text(d, (68, 843), 'How the stretches link', 29, bold=True)
    text(d, (68, 889), '1,600 - 3,200 studs per typical stretch; seeded order can use all six transitions.', 24, MUTED)
    text(d, (68, 928), '480-stud blends are centred on each boundary (yellow windows above).', 24, MUTED)
    text(d, (68, 967), 'Terrain, bend preference and rail need change gradually; the 50-stud road stays continuous.', 24, MUTED)
    # Proportions count transitions half to each neighbour, or by their blend weight.
    x, y, width = 68, 1030, 1664
    for name, share, color in [('Fields', .45, FIELD), ('Small cliffs', .35, SMALL), ('Steep ridges', .20, STEEP)]:
        dx = round(width * share)
        d.rectangle((x, y, x + dx, y + 65), fill=color)
        text(d, (x + dx / 2, y + 32), f'{name} {share:.0%}', 25, BG, True, 'mm')
        x += dx
    text(d, (68, 1125), 'Distance target, including blends / not a repeating five-leg pattern', 22, MUTED)
    text(d, (68, 1170), 'At 100 studs/s: a stretch is 16 - 32 s; a blend is 4.8 s; this example is 2 min.', 24)
    text(d, (68, 1210), 'Illustrative pace below the stock cars\' top speeds. Tight bends take longer.', 21, MUTED)
    text(d, (68, 1266), 'Hairpins, recovery climbs and clearance checks keep their existing safety limits.', 22, MUTED)
    im.save(OUT / 'route-v1.png')


def profiles():
    im = Image.new('RGB', (W, H), BG)
    d = ImageDraw.Draw(im)
    title(d, 'Three terrain profiles, one road',
          'T-203 / Layout proposal v1 / Typical mid-stretch profiles; vertical scale compressed; dimensions in studs')
    center, scale, road_half = 650, 3.8, 25
    def point(x, y, base):
        return (center + x * scale, base - y * 1.45)

    rows = [
        (190, 465, FIELD, 'Fields', 'Broad grass; gentle fall down the mountain.',
         [(-155, 30), (-125, 8), (-105, 5), (-25, 0), (25, 0), (105, -5), (125, -8), (155, -50)]),
        (480, 780, SMALL, 'Small cliffs', 'A low uphill bank and one downhill drop.',
         [(-155, 35), (-110, 27), (-65, 17), (-45, 0), (-25, 0), (25, 0), (45, 0), (54, -30), (155, -48)]),
        (795, 1115, STEEP, 'Steep ridges', 'Exposed drops on both sides; rails assess each side.',
         [(-155, -95), (-55, -85), (-44, -15), (-40, 0), (-25, 0), (25, 0), (40, 0), (44, -15), (55, -85), (155, -95)]),
    ]
    for n, (top, bottom, color, name, sub, pts) in enumerate(rows):
        d.rounded_rectangle((48, top, 1752, bottom), radius=22, fill=PANEL)
        text(d, (80, top + 18), name, 30, color, True)
        base = [342, 635, 895][n]
        coords = [point(x, y, base) for x, y in pts]
        d.polygon([*coords, (coords[-1][0], bottom - 18), (coords[0][0], bottom - 18)], fill='#35443c')
        line(d, coords, color, 6)
        line(d, [point(-road_half, 0, base), point(road_half, 0, base)], ROAD, 18)
        for x in [-road_half, road_half]:
            line(d, [point(x, 0, base), point(x, 0, base)], EDGE, 5)
        # A small stylised car makes the cross-section's scale readable.
        d.rounded_rectangle((center - 11, base - 15, center + 11, base - 2), radius=3, fill=EDGE)
        if n == 2:
            for x in [-27, 27]:
                px, py = point(x, 0, base)
                line(d, [(px, py), (px, py - 17)], '#d9e2e1', 5)
        notes = [
            ['50-wide tarmac', '80 of grass past each road edge', 'About 3.5 degrees of cross-slope', 'Outer banks are visible limits'],
            ['20 of runoff past each road edge', 'Uphill rise: roughly 15 - 35', 'Downhill drop: roughly 25 - 50', 'Low, gentle banks are traversable'],
            ['10 - 20 of runoff per side', 'Drops: roughly 80 - 160', 'Tighter bends; substantially more rails', 'Ridge joins back into hillside'],
        ][n]
        for i, note in enumerate(notes):
            text(d, (1290, top + 75 + i * 36), note, 21, MUTED)
        text(d, (80, bottom - 45), sub, 22, color)
        if n == 0:
            arrow(d, (300, 287), (970, 314), '#bed2d8', 3)
            text(d, (420, 249), 'Gentle fall line', 20, MUTED)
    text(d, (68, 1150), 'Typical profiles, not promised heights: neighbouring road and turn clearance always win.', 24)
    text(d, (68, 1190), 'Fields narrow visibly near tight turns or close road legs. Car and walking ground match the drawing.', 22, MUTED)
    text(d, (68, 1228), 'No invisible floor past a drop. Supported field edges are finite and visibly shaped before streaming in.', 22, MUTED)
    text(d, (68, 1270), 'Each 480-stud transition blends the full profile; it does not swap a wall at a section seam.', 22, MUTED)
    im.save(OUT / 'profiles-v1.png')


if __name__ == '__main__':
    route()
    profiles()
    print('Created route-v1.png and profiles-v1.png')
