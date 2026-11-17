# Road texture (T-274)

The tarmac's texture, with its line band and gravel band (`features/road-surface.md`). It is **painted in code** by `Road/RoadTexture.paint` from `Config.Spline.Tarmac`, `Config.Spline.Gravel`, `Config.Road` and `Config.Spline.Grass.Shade` (T-268, T-270): nothing here was generated or drawn by hand. It is uploaded only because a painted 1 024 x 1 024 EditableImage holds 32 tiles of the client's mesh memory, and an uploaded image none (T-274, `Config.Spline.Mesh.Budget`). A client that cannot load it paints it as before.

| File | Made from | SHA-256 | Status |
|---|---|---|---|
| `tarmac-v1.png` (1024 x 1024, RGB) | The pixels `RoadTexture.paint()` makes at commit `cafab6d` (main after T-273), exactly: painted in the Edit datamodel of DR-Lane1, its RGBA buffer posted to a loopback listener in eight base64 pieces, written losslessly with Pillow as RGB (every alpha was 255). The painting's sum (`RoadTexture.pixelHash`) was `2423809896` in Studio's client, server and Edit alike, and Python's of the file's pixels (below) the same | `94927B73E8C162E4C2C6708FA5E638CBB2CDB58E3C491D748C3F00D96ED73139` | superseded by v2 (T-277) |
| `tarmac-v2.png` (1024 x 1024, RGB) | The pixels `RoadTexture.paint()` makes at commit `249fa18` (T-277: the tarmac 8.5 px/stud along over 120 studs, the dusty edge going softly over to the gravel's bed with no specks, the gravel's stones shaped in studs), exactly: painted in the Edit datamodel of DR-Lane2, its RGBA buffer posted to a loopback listener in eight pieces (`HttpService:JSONEncode` of a buffer gives base64, zstd-compressed when large: Python 3.14's `compression.zstd` reads it), written as RGB with filter 0 by a few lines of `zlib` (no Pillow on `MONSOONPC`). Every alpha was 255; the sum was `1346105968` in Studio and in Python | `B053824FFBE83A832EBB9E44EC8D3B13991E281EB8CD55DA13D081B990566096` | superseded by v3 (T-285) |
| `tarmac-v3.png` (1024 x 1024, RGB) | The pixels `RoadTexture.paint()` makes at commit `7483bc1` (T-285: `Tarmac.Patches` 0, so no patch of newer tarmac is painted; they are rare pieces of the road's mesh now, `features/road-surface.md` "Send-back 5"), exactly: painted in the Edit datamodel of DR-Lane3 and exported as v2 was. It differs from v2 only where v2's one patch was (35 063 pixels, in 164 rows wrapping the copy's ends, columns 566-794): the patch's random numbers are still drawn, so the cracks and everything else are the same pixels. Every alpha was 255; the sum was `385304080` in Studio and in Python | `8EAAD9E0BFF24CAD6EEBA37C0C6320E74D5D363B3C9265B5C594065988653E1F` | **approved to upload (the task's brief), uploaded; its look waits on the user** |

**Approval:** Rowan approved uploading v1 in chat, 2026-11-16 (T-274's brief, on its card): the approved painted texture (T-268, T-270) unchanged, so no candidates were shown. v2 is the user's send-back 4 on it (T-277, `features/road-surface.md`), uploaded as the task's brief asked. v3 is v2 without its painted patch (T-285, send-back 5), uploaded as that task's brief asked; its look is the user's to approve in the lane.

## Uploaded

| File | Asset id | Uploaded by | Decoded | Used in |
|---|---|---|---|---|
| `tarmac-v1.png` | `rbxassetid://118359063841549` | Studio MCP `upload_image` (the user signed in to Studio on `WKEYSTUDIOS1680`), 2026-11-16 | 1024 x 1024, **identical to the painted pixels**: read back as an EditableImage in Studio and compared byte for byte, 0 of 4 194 304 bytes differ | nothing since T-277 |
| `tarmac-v2.png` | `rbxassetid://116617809550507` | Studio MCP `upload_image` from a loopback URL (the user signed in to Studio on `MONSOONPC`), 2026-11-17 | 1024 x 1024, **identical to the painted pixels**: 0 of 4 194 304 bytes differ, read back in DR-Lane2 | nothing since T-285 |
| `tarmac-v3.png` | `rbxassetid://83047839659045` | Studio MCP `upload_image` from a loopback URL (the user signed in to Studio on `MONSOONPC`), 2026-11-17 | 1024 x 1024, **identical to the painted pixels**: 0 of 4 194 304 bytes differ, read back in DR-Lane3 | `Config.Spline.Tarmac.Image`, loaded by `Road/RoadTexture.get` |

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
