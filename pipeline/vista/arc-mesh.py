"""The painted vista's curved panel (docs/game/features/painted-vista.md, T-266).

One arc of a ring, `ARC_DEG` degrees wide, shaded smooth (every normal points in at the ring's
centre), so the real sun lights a ring of them with no step where two meet. The top
`ART_SHARE` of its height carries the picture (u across, v down); below that a skirt reaches
down with v held at the picture's bottom row, so the skirt is the art's own base colour, lit
the same way.

Writes a .glb (glTF 2.0, Y up). In mesh space the ring's centre is on -Z, the side the inner
face looks at, and the bounding box is centred on the origin, as Roblox centres a mesh in its
part. Run:  python -I pipeline/vista/arc-mesh.py assets/painted-vista/vista-arc.glb
"""
import json
import math
import struct
import sys

ARC_DEG = 36.0  # 10 panels a ring
ART_SHARE = 0.4228  # the picture's share of the height (659 of 659 + 900 studs)
RADIUS = 1000.0  # studs; the game scales it
COLUMNS = 24
SKIRT_V = 0.995  # the picture's bottom row, kept clear of the wrap to its transparent top

half = math.radians(ARC_DEG / 2)
width = 2 * RADIUS * math.sin(half)
art_h = width / 3  # the pictures are 3:1
height = art_h / ART_SHARE
zc = -RADIUS * (1 + math.cos(half)) / 2  # the ring's centre, so the box is centred

pos, nrm, uv = [], [], []
for i in range(COLUMNS + 1):
    t = i / COLUMNS
    a = half - 2 * half * t  # u = 0 at +X: the viewer at the centre, looking +Z, has +X on the left
    x, z = RADIUS * math.sin(a), zc + RADIUS * math.cos(a)
    n = (-math.sin(a), 0.0, -math.cos(a))
    for y, v in ((height / 2, 0.0), (height / 2 - art_h, SKIRT_V), (-height / 2, SKIRT_V)):
        pos.append((x, y, z))
        nrm.append(n)
        uv.append((t, v))

idx = []
for i in range(COLUMNS):
    for r in range(2):
        tl, bl = i * 3 + r, i * 3 + r + 1
        tr, br = tl + 3, bl + 3
        # front faces look in at the centre (-Z side)
        idx += [tl, bl, tr, tr, bl, br]

# check the winding: each triangle's face normal points at the centre
for k in range(0, len(idx), 3):
    p0, p1, p2 = (pos[j] for j in idx[k:k + 3])
    e1 = [p1[c] - p0[c] for c in range(3)]
    e2 = [p2[c] - p0[c] for c in range(3)]
    cz = e1[0] * e2[1] - e1[1] * e2[0]
    cx = e1[1] * e2[2] - e1[2] * e2[1]
    to_centre = (-p0[0], 0, zc - p0[2])
    assert cx * to_centre[0] + cz * to_centre[2] > 0, "a triangle faces away from the centre"

def pack(fmt, rows):
    return b"".join(struct.pack(fmt, *r) for r in rows)

b_pos, b_nrm, b_uv = pack("<3f", pos), pack("<3f", nrm), pack("<2f", uv)
b_idx = struct.pack(f"<{len(idx)}H", *idx)
while len(b_idx) % 4:
    b_idx += b"\0"
blob = b_pos + b_nrm + b_uv + b_idx
offs = [0, len(b_pos), len(b_pos) + len(b_nrm), len(b_pos) + len(b_nrm) + len(b_uv)]
xs, ys, zs = zip(*pos)
gltf = {
    "asset": {"version": "2.0", "generator": "pipeline/vista/arc-mesh.py"},
    "scene": 0,
    "scenes": [{"nodes": [0]}],
    "nodes": [{"mesh": 0, "name": "VistaArc"}],
    "meshes": [{"name": "VistaArc", "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3}]}],
    "buffers": [{"byteLength": len(blob)}],
    "bufferViews": [
        {"buffer": 0, "byteOffset": offs[0], "byteLength": len(b_pos), "target": 34962},
        {"buffer": 0, "byteOffset": offs[1], "byteLength": len(b_nrm), "target": 34962},
        {"buffer": 0, "byteOffset": offs[2], "byteLength": len(b_uv), "target": 34962},
        {"buffer": 0, "byteOffset": offs[3], "byteLength": len(idx) * 2, "target": 34963},
    ],
    "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3", "min": [min(xs), min(ys), min(zs)], "max": [max(xs), max(ys), max(zs)]},
        {"bufferView": 1, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
        {"bufferView": 2, "componentType": 5126, "count": len(uv), "type": "VEC2"},
        {"bufferView": 3, "componentType": 5123, "count": len(idx), "type": "SCALAR"},
    ],
}
js = json.dumps(gltf, separators=(",", ":")).encode()
while len(js) % 4:
    js += b" "
glb = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
glb += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(blob), 0x004E4942) + blob
open(sys.argv[1], "wb").write(glb)
print(f"{sys.argv[1]}: {len(pos)} vertices, {len(idx) // 3} triangles, box {max(xs) - min(xs):.1f} x {max(ys) - min(ys):.1f} x {max(zs) - min(zs):.1f}")
