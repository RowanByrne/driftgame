# Grass texture (T-187)

The spline road's grass runoff texture (`features/mountain-road.md` "The grass's texture"). Candidates live in `..\art\generated\grass-texture\` (outside git).

Image tool: `tools\imagegen.ps1` (Codex built-in image generation, Codex app CLI `f71a721e0e6193a9`). The tool's model version is not reported; not checked against OpenAI's newest image release this round.

| File | Prompt | References | SHA-256 | Status |
|---|---|---|---|---|
| `painted-01.png` (1254 x 1254) | "Seamless tileable texture of short mown grass seen straight from above, stylized hand-painted look for a low-poly game, soft broad brush strokes in large gentle patches of slightly lighter and darker tone, low contrast, no fine high-frequency detail, no individual sharp blades, no flowers, no dirt, no shadows from objects, evenly lit, neutral mid grey-green so it can be tinted, square, edges wrap seamlessly" | none | `F0939D5C4D9D230D736F0462DD628A5064AE5FBECDDBB23AB5F7BB4850402CE1` | candidate |
| `painted-01-grey256.png` | Derived from `painted-01.png`: scaled to 256, luminance only, cross-faded with its half-offset copy so it tiles, evened out to mean `Shade` (0.49) at 1.5x its own contrast (range 114..150 of 255) | | | candidate |

Shown to the user on the card in game (one screenshot each, same daylight view) beside three looks drawn in code: `mottled`, `soft`, `patches`. Nothing uploaded.
