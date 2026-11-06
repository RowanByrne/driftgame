# UI tools

Scripts for UI art and UI checks, called from `docs/workflow/UI.md`, `ART-PIPELINE.md` and `TESTING.md`.

- **PowerShell tools** run on any Windows 11 PC with nothing to install: Windows PowerShell 5.1, .NET's System.Drawing, and Edge for SVG rendering. They share `lib/RobloxUiTools.ps1`. Run them from `repo\` as `powershell -ExecutionPolicy Bypass -File tools\ui\<tool>.ps1 ...`. Each script's header has its full usage.
- **Luau tools** are sent whole as `execute_luau` code. Each starts with a `CONFIG` table to fill in, and returns only string-keyed tables.
- **`LayoutDrag.luau`** is a game module, not a tool: games copy it unchanged into the UI kit (CODING.md "The kit's fixed names").

| Tool | Where it runs | What it does |
|---|---|---|
| `measure-png.ps1` | PowerShell | For each PNG: size, transparency, visible rect (alpha ≥ 8, 1 px margin), visible aspect and SHA-256. With `-Aspect`, the distortion against the slot and whether it's within the 20% limit. `-Json` for the manifest |
| `contact-sheet.ps1` | PowerShell | The sheet the user picks from. Draws each candidate into a `-Slot WxH` box over a game screenshot (`-Background`, `-SlotAt x,y`), a tile or a flat colour at 1×, then magnified (`-Zoom`). Labels A–F with visible aspect and distortion, and flags `OFF-ASPECT` (`-DropOffAspect` leaves those out) |
| `cut-sheet.ps1` | PowerShell | Cuts a generated grid sheet (`-Cols`, `-Rows`, `-Names`) into one PNG per piece, losslessly, along the fully transparent lines nearest the grid. Refuses to cut through a piece; warns when one touches its cell edge |
| `measure-anchors.ps1` | PowerShell | Where a piece of art leaves room for native content: its socket (the largest enclosed transparent hole) and the band its body covers, as fractions of the visible rect, for the registry |
| `svg-icons-to-atlas.ps1` | PowerShell | SVG folder → white 256 px masters, `atlas.png` (≤ 1024 px, 128 px cells), `atlas.json` (each icon's alpha-cropped rect) and a contact sheet at 36 and 24 px. `-SetAssetId <id> -Registry <file.luau>` writes the uploaded id and generates the Luau icon registry. Unchanged SVGs render to identical bytes, so the id is kept |
| `serve-assets.ps1` | PowerShell | Serves one folder read-only on `127.0.0.1` for `upload_image`, and prints a URL per image. Images only, nothing outside `-Root`. Stops after `-Minutes`, after `-MaxRequests`, or on `GET /__stop` |
| `source-gate.ps1` | PowerShell | Hashes the `.luau` files changed against git `HEAD` (or `-Files`): LF-normalised UTF-8 bytes, `h = (h * 31 + byte) % 2^32`. Maps them to instances through `default.project.json` and writes `SourceGate.luau` with its `CONFIG` filled in (`-Out`) |
| `SourceGate.luau` | Edit datamodel | Compares each module's `.Source` with the disk's bytes and hash, and compile-checks it with `loadstring`. Returns `ok`, `failed` and a status per file |
| `DecodeRects.luau` | Edit datamodel | Loads each uploaded id with `AssetService:CreateEditableImageAsync` and returns its decoded size, `rectOffset`, `rectSize` and `aspect` (alpha ≥ 8, 1 px margin), optionally per atlas cell |
| `MeasureUI.luau` | Client datamodel, in a playtest | Once per screen size: checks the renderer is live, then every visible GuiObject for text fit, effective text size (UIScale included; `TextAux` labels may go to 14 px), target size (`TargetExempt = "<reason>"` skips one), image loading, `ArtworkWithinLimit`, captions above their skins, overlaps between the pieces you list plus the touch-control zones, the safe area, and optionally coverage % |
| `SimulatorSweep.luau` | Edit datamodel, or Client during a playtest | One step of a device-simulator sweep per call: `list`, `plan` (match each screen-size row to a simulator device), `set` (device, then actual resolution, then orientation; returns the viewport it got) and `stop` (always run it) |
| `LayoutDrag.luau` | The game, in Studio only | The layout drag mode (UI.md "Programmer art"). Its header has the API a screen's view needs |

## How they were checked

On 2026-11-05, against real uploaded assets and a fixture screen in an empty local place, Studio 0.745:

- **`measure-png`:** a recorded visible aspect of 2.60 measured 2.609.
- **`contact-sheet`:** flagged the one off-aspect candidate (1.208) for its slot.
- **`cut-sheet` and `measure-anchors`:** cut a HUD's generated sheets into layers and measured their sockets and bands; a screen laid out from those anchors lined up in Studio.
- **`svg-icons-to-atlas`:** masked SVGs rendered with transparency in about 7 s; the registry was generated after `-SetAssetId`.
- **`serve-assets`:** GET and HEAD returned the exact bytes; `..` escapes, other files and subfolders returned 404; `/__stop` stopped it.
- **`source-gate` and `SourceGate`:** LF and CRLF files with non-ASCII text both matched and compiled; a syntax error reported its line; a one-character edit with the same byte count was caught by the hash; a module missing from Studio reported `missing`.
- **`DecodeRects`:** decoded sizes and alpha bounds matched earlier records to the pixel.
- **`MeasureUI`:** a fixture with one deliberate failure per check caught every one and flagged nothing else.
- **`SimulatorSweep`:** 42 devices; iPhone 7 gave 667 × 375 and iPhone 13 Pro portrait 390 × 763; `stop` restored the viewport.
- **`LayoutDrag`:** real mouse drags in a playtest: with snapping on, a card dragged by +5, −97 px landed at +8, −96; with it off, another landed exactly where dropped.
