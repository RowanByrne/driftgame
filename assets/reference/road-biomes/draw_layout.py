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
          'T-203 / Revised layout v2 / The existing mountain road, with shorter terrain categories along it')
    d.rounded_rectangle((48, 164, 1752, 815), radius=24, fill=PANEL)
    spans = [('Fields', 600, FIELD), ('Small cliffs', 700, SMALL),
             ('Steep', 400, STEEP), ('Fields', 600, FIELD),
             ('Small cliffs', 700, SMALL), ('Steep', 400, STEEP), ('Fields', 600, FIELD)]
    ends, total = [], 0
    for _, length, _ in spans:
        total += length
        ends.append(total)
    def rgb(color):
        return tuple(int(color[i:i + 2], 16) for i in [1, 3, 5])
    def color_at(s):
        for i, end in enumerate(ends[:-1]):
            if end - 90 <= s <= end + 90:
                t = (s - end + 90) / 180
                t = t * t * (3 - 2 * t)
                a, b = rgb(spans[i][2]), rgb(spans[i + 1][2])
                return tuple(round(x + (y - x) * t) for x, y in zip(a, b))
        index = next((i for i, end in enumerate(ends) if s <= end), len(spans) - 1)
        return rgb(spans[index][2])
    def pos(s):
        return (140 + 1510 * s / total,
                440 + 65 * math.sin(s / 250) + 35 * math.sin(s / 620))
    text(d, (90, 192), 'Same road and mountain forms; category changes can happen partway through a bend.', 24, MUTED)
    text(d, (90, 240), 'Uphill mountain', 21, MUTED)
    text(d, (90, 590), 'Downhill slope / drop', 21, MUTED)
    def sides(s):
        x, y = pos(s)
        a, b = pos(s - 1), pos(s + 1)
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        nx, ny = -dy / length * 65, dx / length * 65
        return [(x + nx, y + ny), (x - nx, y - ny)]
    for s in range(0, total, 2):
        a, b = sides(s), sides(s + 2)
        d.polygon([a[0], a[1], b[1], b[0]], fill=color_at(s + 1))
    path = [pos(s) for s in range(0, total + 1, 2)]
    line(d, path, EDGE, 22)
    line(d, path, ROAD, 16)
    # Arbitrary existing section seams, independent of the biome's distance schedule.
    for s in [350, 980, 1570, 2150, 2720, 3190, 3790]:
        x, y = pos(s)
        for dy in range(-90, 91, 17):
            line(d, [(x, y + dy), (x, y + dy + 8)], '#e0e5e0', 2)
    text(d, (90, 642), 'Distance along this single continuous road (studs)', 21, MUTED)
    for s in range(total):
        x = round(pos(s)[0])
        line(d, [(x, 682), (x, 736)], color_at(s), 2)
    start = 0
    for name, length, color in spans:
        mid = pos(start + length / 2)[0]
        text(d, (mid, 709), name, 21, BG, True, 'mm')
        text(d, (mid, 765), str(length), 21, MUTED, anchor='mm')
        start += length
    arrow(d, (119, 390), (119, 490), '#acc9d3', 4)
    text(d, (68, 843), 'How the stretches link', 29, bold=True)
    text(d, (68, 889), '400 - 900 studs between category boundaries; each join blends over 180 studs.', 24, MUTED)
    text(d, (68, 928), 'Grey marks are existing road section ends. Category blends cross them independently.', 24, MUTED)
    text(d, (68, 967), 'Keep current terrain style, bends and switchbacks; vary the existing terrain along the road.', 24, MUTED)
    # Proportions count transitions half to each neighbour, or by their blend weight.
    x, y, width = 68, 1030, 1664
    for name, share, color in [('Fields', .45, FIELD), ('Small cliffs', .35, SMALL), ('Steep cliffs', .20, STEEP)]:
        dx = round(width * share)
        d.rectangle((x, y, x + dx, y + 65), fill=color)
        text(d, (x + dx / 2, y + 32), f'{name} {share:.0%}', 25, BG, True, 'mm')
        x += dx
    text(d, (68, 1125), 'Distance target, including blends / this is an example, not a repeating pattern', 22, MUTED)
    text(d, (68, 1170), 'At 100 studs/s: a category changes every 4 - 9 s; a blend takes 1.8 s; example is 40 s.', 24)
    text(d, (68, 1210), 'Illustrative pace below the stock cars\' top speeds. Tight bends take longer.', 21, MUTED)
    text(d, (68, 1266), 'Hairpins, recovery climbs and clearance checks keep their existing safety limits.', 22, MUTED)
    im.save(OUT / 'route-v2.png')


def profiles():
    im = Image.new('RGB', (W, H), BG)
    d = ImageDraw.Draw(im)
    title(d, 'Three terrain profiles, one road',
          'T-203 / Revised layout v2 / First two profiles retained; steep category uses the existing mountain form')
    center, scale, road_half = 650, 3.8, 25
    def point(x, y, base):
        return (center + x * scale, base - y * (0.55 if base == 930 else 1.45))

    rows = [
        (190, 465, FIELD, 'Fields', 'Broad grass; gentle fall down the mountain.',
         [(-155, 30), (-125, 8), (-105, 5), (-25, 0), (25, 0), (105, -5), (125, -8), (155, -50)]),
        (480, 780, SMALL, 'Small cliffs', 'A low uphill bank and one downhill drop.',
         [(-155, 35), (-110, 27), (-65, 17), (-45, 0), (-25, 0), (25, 0), (45, 0), (54, -30), (155, -48)]),
        (795, 1115, STEEP, 'Steep cliffs', 'Mountain rises uphill; the opposite side drops downhill, as it does today.',
         [(-155, 145), (-110, 150), (-85, 140), (-60, 95), (-45, 0), (-25, 0), (25, 0), (40, 0), (44, -15), (55, -140), (155, -160)]),
    ]
    for n, (top, bottom, color, name, sub, pts) in enumerate(rows):
        d.rounded_rectangle((48, top, 1752, bottom), radius=22, fill=PANEL)
        text(d, (80, top + 18), name, 30, color, True)
        base = [342, 635, 930][n]
        coords = [point(x, y, base) for x, y in pts]
        d.polygon([*coords, (coords[-1][0], bottom - 18), (coords[0][0], bottom - 18)], fill='#35443c')
        line(d, coords, color, 6)
        line(d, [point(-road_half, 0, base), point(road_half, 0, base)], ROAD, 18)
        for x in [-road_half, road_half]:
            line(d, [point(x, 0, base), point(x, 0, base)], EDGE, 5)
        # A small stylised car makes the cross-section's scale readable.
        d.rounded_rectangle((center - 11, base - 15, center + 11, base - 2), radius=3, fill=EDGE)
        if n == 2:
            for x in [27]:
                px, py = point(x, 0, base)
                line(d, [(px, py), (px, py - 17)], '#d9e2e1', 5)
        notes = [
            ['50-wide tarmac', '80 of grass past each road edge', 'About 3.5 degrees of cross-slope', 'Outer banks are visible limits'],
            ['20 of runoff past each road edge', 'Uphill rise: roughly 15 - 35', 'Downhill drop: roughly 25 - 50', 'Low, gentle banks are traversable'],
            ['Current tall uphill mountain', 'Current deep downhill cliff', 'Current face shaping and fitting', 'More rails at exposed edges'],
        ][n]
        for i, note in enumerate(notes):
            text(d, (1290, top + 75 + i * 36), note, 21, MUTED)
        text(d, (80, bottom - 45), sub, 22, color)
        if n == 0:
            arrow(d, (300, 287), (970, 314), '#bed2d8', 3)
            text(d, (420, 249), 'Gentle fall line', 20, MUTED)
    text(d, (68, 1150), 'Categories of the terrain we already have. Vertical scale compressed for the sketches.', 24)
    text(d, (68, 1190), 'Fields narrow visibly near tight turns or close road legs. Car and walking ground match the drawing.', 22, MUTED)
    text(d, (68, 1228), 'No invisible floor past a drop. Supported field edges are finite and visibly shaped before streaming in.', 22, MUTED)
    text(d, (68, 1270), 'Each 180-stud transition blends the existing profile smoothly while you drive along a section.', 22, MUTED)
    im.save(OUT / 'profiles-v2.png')


if __name__ == '__main__':
    route()
    profiles()
    print('Created route-v2.png and profiles-v2.png')
