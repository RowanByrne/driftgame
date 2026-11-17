# Road texture (T-274)

The tarmac's texture, with its line band and gravel band (`features/road-surface.md`). It is **painted in code** by `Road/RoadTexture.paint` from `Config.Spline.Tarmac`, `Config.Spline.Gravel`, `Config.Road` and `Config.Spline.Grass.Shade` (T-268, T-270): nothing here was generated or drawn by hand. It is uploaded only because a painted 1 024 x 1 024 EditableImage holds 32 tiles of the client's mesh memory, and an uploaded image none (T-274, `Config.Spline.Mesh.Budget`). A client that cannot load it paints it as before.

| File | Made from | SHA-256 | Status |
|---|---|---|---|
| `tarmac-v1.png` (1024 x 1024, RGB) | The pixels `RoadTexture.paint()` makes at commit `cafab6d` (main after T-273), exactly: painted in the Edit datamodel of DR-Lane1, its RGBA buffer posted to a loopback listener in eight base64 pieces, written losslessly with Pillow as RGB (every alpha was 255). The painting's sum (`RoadTexture.pixelHash`) was `2423809896` in Studio's client, server and Edit alike, and Python's of the file's pixels (below) the same | `94927B73E8C162E4C2C6708FA5E638CBB2CDB58E3C491D748C3F00D96ED73139` | **approved, uploaded** |

**Approval:** Rowan approved uploading this texture in chat, 2026-11-16 (T-274's brief, on its card). It is the approved painted texture (T-268, T-270) unchanged, so no candidates were shown.

## Uploaded

| File | Asset id | Uploaded by | Decoded | Used in |
|---|---|---|---|---|
| `tarmac-v1.png` | `rbxassetid://118359063841549` | Studio MCP `upload_image` (the user signed in to Studio on `WKEYSTUDIOS1680`), 2026-11-16 | 1024 x 1024, **identical to the painted pixels**: read back as an EditableImage in Studio and compared byte for byte, 0 of 4 194 304 bytes differ | `Config.Spline.Tarmac.Image`, loaded by `Road/RoadTexture.get` |

## Painting changed? Export it again

`SplineMeshTests` ("the tarmac's uploaded image is exactly what is painted") fails when the painting no longer sums to `Tarmac.ImageHash`. Then:

1. Paint it in a lane's Edit datamodel and post the RGBA buffer to a loopback listener (Studio's Edit datamodel may make HTTP requests to `127.0.0.1`; a playtest's client and server may not). `execute_luau`'s `require` cache can hold stale copies of `Config`: clone `ReplicatedStorage.Shared` into `ServerStorage` and point the clone's `RoadTexture` at the clone's `Config` before requiring it.
2. Write it losslessly as PNG (`tarmac-v2.png`: a new file, never over `v1`), check its pixels' sum with the Python below, upload it (ART-PIPELINE.md step 5), read it back as an EditableImage and compare.
3. Set `Tarmac.Image` and `Tarmac.ImageHash`, and add a row here.

The sum, in Python (it follows Luau's doubles, so it is not FNV's own value):

```python
import math, struct
from PIL import Image
raw = Image.open("tarmac-v1.png").convert("RGBA").tobytes()
h = 2166136261.0
for (w,) in struct.iter_unpack("<I", raw):
    h = float(int(h) ^ w)
    a = h * 16777619.0
    h = a - math.floor(a / 4294967296.0) * 4294967296.0
print(int(h))  # 2423809896
```
