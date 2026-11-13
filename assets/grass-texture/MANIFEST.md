# Grass texture (T-187)

The spline road's grass runoff texture (`features/mountain-road.md` "The grass's texture"). Candidates live in `..\art\generated\grass-texture\` (outside git).

Image tool: `tools\imagegen.ps1` (Codex built-in image generation, Codex app CLI `f71a721e0e6193a9`). The tool's model version is not reported; not checked against OpenAI's newest image release this round.

| File | Prompt | References | SHA-256 | Status |
|---|---|---|---|---|
| `painted-01.png` (1254 x 1254) | "Seamless tileable texture of short mown grass seen straight from above, stylized hand-painted look for a low-poly game, soft broad brush strokes in large gentle patches of slightly lighter and darker tone, low contrast, no fine high-frequency detail, no individual sharp blades, no flowers, no dirt, no shadows from objects, evenly lit, neutral mid grey-green so it can be tinted, square, edges wrap seamlessly" | none | `F0939D5C4D9D230D736F0462DD628A5064AE5FBECDDBB23AB5F7BB4850402CE1` | picked (as the grey tile below) |
| `painted-01-grey256.png` | Derived from `painted-01.png`: scaled to 256, luminance only, cross-faded with its half-offset copy so it tiles, evened out to mean `Shade` (0.49) at 1.5x its own contrast (range 114..150 of 255). Committed here as `grass-painted-grey256.png` | | `B8B1F5503B195C1E41A7D64C4BF427F7BBA5A96634FC90190C86C348B753083B` | **approved, uploaded** |

Shown to the user on the card in game (one screenshot each, same daylight view) beside three looks drawn in code: `mottled`, `soft`, `patches`. **The user picked "Painted"**, 2026-11-13 (DECISIONS.md); the drawn first try had been "a bit static-y".

## Uploaded

| File | Asset id | Uploaded by | Decoded | Used in |
|---|---|---|---|---|
| `grass-painted-grey256.png` | `rbxassetid://140682021733001` | Studio MCP `upload_image` (the user signed in to Studio), 2026-11-13 | 256 x 256, grey, mean 125/255, range 114..150 (read back as an EditableImage) | `Config.Spline.Grass.Image`, loaded by `Road/GrassTexture` |
