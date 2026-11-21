# Ground textures (T-340)

The mountain ground's texture sheet (DECISIONS.md, 2026-11-20: the ground look goes on as a texture sheet over the colour blend). One opaque PNG, a 2x2 sheet: top-left grass, top-right rocky grass, bottom-left rock, bottom-right snow. Each triangle of the ground mesh picks one square by steepness and height, and the texture is multiplied by the per-vertex colours, so the squares must be near-neutral grey, averaging about 75 to 85% brightness, and each must tile with itself. Candidates live in `..\art\generated\ground-textures\` (outside git). Nothing here is picked or uploaded yet.

Image tool: `tools\imagegen.ps1` (Codex built-in image generation), run on `ROWANWKEY` on 2026-11-20 with the Codex app's CLI `codex-cli 0.162.0-alpha.17.2`. That's older than the `0.167.0-alpha.4.1` recorded on another PC on 2026-11-14 (`assets/settings-menu/MANIFEST.md`), so this PC's Codex is probably behind. The tool's model version isn't reported, and it wasn't checked against OpenAI's newest image release this round. References are from `assets/reference/environment-mood/`, used for mood and brushwork only. Every candidate came back 1254 x 1254, opaque.

## Checks

Measured with a throwaway script (`..\scratch\ground-textures-seamcheck.ps1`). Each quadrant is taken as exactly half the sheet (627 px). The script measures luminance (Rec. 709).

- **Seam:** the mean absolute difference between a quadrant's left and right columns (LR), and between its top and bottom rows (TB). It's shown against the mean difference between adjacent interior columns or rows (adj), and against columns or rows half a tile apart (unrel, which is what a seam between unrelated content scores).
- **Ratio:** seam / adj. Near 1 means the edge wraps like the interior. A seam close to unrel doesn't wrap at all.
- **Low-pass:** the same figures after 8 x 8 box averaging. Flat-shaded art has near-zero adjacent differences, which inflates the full-resolution ratio, and stippled art has pixel noise, which hides it. The low-pass figures judge both fairly.
- **Bright:** mean luminance, as a % of white.
- **Chroma:** mean (max - min) of RGB, out of 255. 0 is pure grey.
- **Wrap previews:** each quadrant rolled by half, so its seams cross its middle. They're in `..\scratch\ground-textures-wrap-<name>.png`.

## Candidates

### painterly-01.png: painterly oil and gouache

- **File:** `..\art\generated\ground-textures\painterly-01.png` (1254 x 1254, opaque)
- **SHA-256:** `37EDEB1EB9B2D97EDEAD693BEB5E6240343E2AE0CBDB742A7A7DA5BD467A2087`
- **References:** `assets/reference/environment-mood/snow-pass-sunset.png`, `assets/reference/environment-mood/moonlit-pampas-ridge.png`
- **Status:** approved 2026-11-20. The user, asked which candidate goes on the mountain: "Painterly". Copied unchanged to `assets/ground-textures/painterly-01.png` (same SHA-256)
- **Prompt:** "Hand-painted oil and gouache texture sheet for a stylized Japanese mountain driving game, in the painterly brushwork of the attached concept paintings (their brush handling only, not their colours or subjects). Neutral grayscale only: no colour at all, pale mid-light greys averaging about 80% brightness, white highlights, soft mid-grey shadows, low contrast. One opaque square image divided into a 2x2 grid of four square texture tiles that touch edge to edge with no border, gap, frame or text, same artist and brush on all four: top-left a grassy meadow seen from above at a slight angle, loose directional brush strokes suggesting tufts of grass blades; top-right the same grass broken up by scattered small stones and patches of bare earth; bottom-left a rock cliff face with flat fractured planes and cracks, chunky palette-knife strokes; bottom-right soft snow drifts, very subtle gentle mounds with faint grey shadows. Each of the four tiles is a seamless repeating texture: its left edge continues exactly into its right edge and its top edge into its bottom edge, evenly lit with no light gradient or vignette, detail spread evenly with no single focal feature, no horizon, no sky. Avoid the generic look: no photo texture, no glossy 3D render, no airbrushed gradients, no noise filter."

| Quadrant | Bright | Chroma | LR seam / adj / unrel (ratio) | TB seam / adj / unrel (ratio) | Low-pass LR ratio | Low-pass TB ratio |
|---|---|---|---|---|---|---|
| Grass | 75% | 2.3 | 7.4 / 5.1 / 18.8 (1.5x) | 8.3 / 6.2 / 18.5 (1.3x) | 0.6x | 0.7x |
| Rocky grass | 74% | 2.3 | 7.1 / 4.5 / 18.0 (1.6x) | 10.0 / 5.5 / 18.3 (1.8x) | 0.7x | 1.3x |
| Rock | 77% | 2.4 | 6.0 / 3.6 / 17.5 (1.7x) | 8.1 / 3.4 / 16.6 (2.4x) | 0.7x | 0.6x |
| Snow | 85% | 2.1 | 3.8 / 1.8 / 11.9 (2.1x) | 6.2 / 2.6 / 11.1 (2.4x) | 0.9x | 0.5x |

**Notes:** Tiles well. The wrap preview shows only a faint horizontal line on the rocky grass, and that square's stones are its most repeat-prone feature. All four squares are within the brightness target.

### flatcel-01.png: flat stylized cel-shaded shapes

- **File:** `..\art\generated\ground-textures\flatcel-01.png` (1254 x 1254, opaque)
- **SHA-256:** `994D139C86FEB5A4224E33CE80A9C2589953741E12480E3B5E146D6CD31F82D9`
- **References:** none
- **Status:** rejected 2026-11-20 (the user picked painterly-01)
- **Prompt:** "Flat stylized cel-shaded texture sheet, like background art for a low-poly anime game: crisp flat shapes in three or four grey tones with clean hard edges, no brush noise. Neutral grayscale only, no colour: light greys averaging about 80% brightness, white tops, mid-grey undersides, low contrast. One opaque square image as a 2x2 grid of four square textures butted edge to edge, no borders, gaps, outlines around tiles, frames or text, all four drawn in the same hand: top-left grass as overlapping flat leaf-shaped clumps and simple blade tufts seen from above; top-right the same grass clumps with small flat-shaded pebbles and bare earth patches between them; bottom-left rock as faceted angular planes with a few sharp crack lines, like low-poly stone; bottom-right snow as soft rounded flat-shaded drift shapes with a pale shadow tone. Every tile tiles seamlessly with itself on all sides (left edge matches right edge, top matches bottom), shapes crossing an edge continue on the opposite side, even lighting, no gradient across a tile, evenly spread shapes with no focal point. Avoid the generic look: no photo texture, no glossy 3D, no airbrushed gradients, no realistic detail."

| Quadrant | Bright | Chroma | LR seam / adj / unrel (ratio) | TB seam / adj / unrel (ratio) | Low-pass LR ratio | Low-pass TB ratio |
|---|---|---|---|---|---|---|
| Grass | 79% | 0.8 | 17.3 / 1.6 / 23.4 (10.8x) | 20.1 / 1.5 / 23.3 (13.0x) | 2.6x | 3.2x |
| Rocky grass | 76% | 0.9 | 11.8 / 1.5 / 26.2 (7.9x) | 15.4 / 1.7 / 22.6 (9.0x) | 2.0x | 2.1x |
| Rock | 78% | 0.9 | 5.3 / 1.1 / 26.7 (5.1x) | 19.1 / 1.1 / 22.7 (17.4x) | 1.4x | 4.3x |
| Snow | 90% | 0.6 | 4.6 / 0.5 / 12.8 (10.1x) | 5.9 / 0.7 / 7.5 (8.2x) | 2.1x | 1.3x |

**Notes:** Doesn't tile. The grass and rock seams are close to the unrelated baseline. The clumps are large, and the rocky grass has a stray large arc. Regenerated once with a stronger tiling instruction as flatcel-02.

### flatcel-02.png: flat cel-shaded shapes, stronger tiling (retry of flatcel-01)

- **File:** `..\art\generated\ground-textures\flatcel-02.png` (1254 x 1254, opaque)
- **SHA-256:** `442A9B8FBAB7983237F94ACE3D832F1CB21BA56EBCEA72E89E0F7B259057C778`
- **References:** none
- **Status:** rejected 2026-11-20 (the user picked painterly-01)
- **Prompt:** "Flat stylized cel-shaded texture sheet, like background art for a low-poly anime game: crisp flat shapes in three or four grey tones with clean hard edges, no brush noise. Neutral grayscale only, no colour: light greys averaging about 80% brightness, white tops, mid-grey undersides, low contrast. One opaque square image as a 2x2 grid of four equal square textures butted edge to edge at the exact centre lines, no borders, gaps, outlines around tiles, frames or text, all four drawn in the same hand: top-left grass as many small overlapping flat leaf-shaped clumps and blade tufts seen from above, all about the same size; top-right the same small grass clumps with scattered flat-shaded pebbles and bare earth patches between them; bottom-left rock as faceted angular planes of similar size with thin crack lines, like low-poly stone; bottom-right snow as soft rounded flat-shaded drift ripples with a pale shadow tone. CRITICAL: each square is a seamless wrap-around tile, drawn as if on a torus. Any clump, pebble, rock plane or drift that is cut off at a square right edge must continue and complete itself at that square left edge at exactly the same height, and anything cut at its bottom edge continues at its top edge at exactly the same position. Nothing stops, fades or changes tone near the edges; the pattern density is the same at the edges as in the middle. Even flat lighting, no gradient across a tile, no single large or focal shape. Avoid the generic look: no photo texture, no glossy 3D, no airbrushed gradients, no realistic detail."

| Quadrant | Bright | Chroma | LR seam / adj / unrel (ratio) | TB seam / adj / unrel (ratio) | Low-pass LR ratio | Low-pass TB ratio |
|---|---|---|---|---|---|---|
| Grass | 77% | 0.9 | 8.1 / 3.2 / 24.4 (2.5x) | 9.3 / 3.1 / 24.6 (3.0x) | 1.6x | 1.1x |
| Rocky grass | 76% | 0.9 | 13.4 / 2.8 / 22.5 (4.7x) | 11.3 / 3.0 / 24.2 (3.7x) | 1.5x | 0.9x |
| Rock | 80% | 0.7 | 1.7 / 1.3 / 19.8 (1.3x) | 3.1 / 1.5 / 20.4 (2.1x) | 0.5x | 0.9x |
| Snow | 90% | 0.6 | 2.0 / 0.4 / 10.6 (5.0x) | 4.2 / 0.8 / 9.1 (5.4x) | 1.8x | 2.1x |

**Notes:** Much better than flatcel-01. The rock wraps cleanly, and the snow nearly does: its high full-resolution ratio comes from the flat fills, and its seam is only 2 to 4 levels. The grass and rocky grass still cut some clumps at the edges, which shows as faint lines in the wrap preview. Snow is a little brighter than the target.

### stipple-01.png: soft stipple and dry-brush illustration

- **File:** `..\art\generated\ground-textures\stipple-01.png` (1254 x 1254, opaque)
- **SHA-256:** `32C76D3CAB0EAE961CE6128F65D474C3D0566415D2D3E49D8CF91E902ED798FF`
- **References:** `assets/reference/environment-mood/snow-pass-sunset.png`
- **Status:** rejected 2026-11-20 (the user picked painterly-01)
- **Prompt:** "Soft dry-brush and stipple illustration texture sheet, like a hand-inked storybook landscape: fine dabs, stippled dots and scratchy dry-brush strokes on lightly textured paper, in the spirit of the attached concept painting (its mark-making only, not its colours or subject). Neutral grayscale only, no colour: mostly pale grey and off-white, averaging about 80% brightness, gentle mid-grey marks, low contrast. One opaque square image split into a 2x2 grid of four square textures that meet edge to edge with no border, gap, frame or text; same illustrator and tools on all four: top-left a grass meadow seen from above, short dry-brush flicks for blades in small clusters; top-right grass interrupted by stippled small stones and dry earth; bottom-left a cracked rock face, dry-brush planes with hatched cracks; bottom-right snow, sparse soft stipple shading of low drifts, mostly white. Each tile is a seamless tileable texture: its left edge flows into its right edge and its top edge into its bottom edge with no visible seam, flat even lighting with no gradient or vignette, marks evenly distributed with no single standout feature. Avoid the generic look: no photo texture, no glossy 3D, no airbrushed gradients, no digital noise."

| Quadrant | Bright | Chroma | LR seam / adj / unrel (ratio) | TB seam / adj / unrel (ratio) | Low-pass LR ratio | Low-pass TB ratio |
|---|---|---|---|---|---|---|
| Grass | 90% | 6.9 | 12.5 / 11.0 / 19.5 (1.1x) | 12.6 / 9.5 / 20.4 (1.3x) | 0.9x | 1.0x |
| Rocky grass | 90% | 7.1 | 13.9 / 10.0 / 19.1 (1.4x) | 11.5 / 9.8 / 19.9 (1.2x) | 0.9x | 1.0x |
| Rock | 87% | 7.0 | 13.3 / 10.5 / 22.2 (1.3x) | 15.9 / 10.2 / 21.9 (1.6x) | 1.0x | 0.5x |
| Snow | 94% | 6.6 | 7.2 / 5.8 / 9.8 (1.2x) | 8.0 / 6.3 / 9.7 (1.3x) | 1.2x | 0.5x |

**Notes:** Tiles well, with only a faint vertical seam on the rocky grass in the wrap preview. But it's a pencil drawing on cream paper: it's too light (87 to 94%, above the target), it has a slight warm tint (chroma about 7), and the marks are faint, so the tint would carry most of the look. The grass also has small flower sprigs. That's why stipple-02 was made.

### stipple-02.png: stipple and dry-brush, fuller mid-tone (variation of stipple-01)

- **File:** `..\art\generated\ground-textures\stipple-02.png` (1254 x 1254, opaque)
- **SHA-256:** `2DD964A52D6001B11F0C435D11A6293B07695D7C7BF112B33201C1500506EC50`
- **References:** `..\art\generated\ground-textures\stipple-01.png`
- **Status:** rejected 2026-11-20 (the user picked painterly-01)
- **Prompt:** "Graphite-pencil stipple and dry-brush ink illustration texture sheet on plain white with no paper grain, a new variation by the same illustrator as the attached sheet but with a fuller mid-tone: the marks cover more of the surface so each tile reads as a light-to-mid grey overall, averaging about 78% brightness rather than near-white. Neutral grayscale only, pure grey with no warm or cream paper tint, no colour. One opaque square image split into a 2x2 grid of four equal square textures meeting edge to edge at the exact centre lines, no border, gap, frame or text: top-left a dense grass meadow seen from above, clustered dry-brush blade flicks with a light grey wash between them, no flowers; top-right the same grass broken by small stippled stones and bare dry earth; bottom-left a cracked rock face of angular planes, dry-brush shading with hatched cracks, mid grey; bottom-right snow, soft stippled shading of low rounded drifts, the lightest of the four but still clearly shaded. Each square tiles seamlessly with itself: its left edge flows into its right edge and its top edge into its bottom edge with no visible seam, flat even lighting with no gradient or vignette, marks evenly distributed with no single standout feature. Avoid the generic look: no photo texture, no glossy 3D, no airbrushed gradients, no digital noise."

| Quadrant | Bright | Chroma | LR seam / adj / unrel (ratio) | TB seam / adj / unrel (ratio) | Low-pass LR ratio | Low-pass TB ratio |
|---|---|---|---|---|---|---|
| Grass | 65% | 1.9 | 19.2 / 18.8 / 28.3 (1.0x) | 20.2 / 16.5 / 28.9 (1.2x) | 1.8x | 1.2x |
| Rocky grass | 66% | 1.8 | 19.1 / 13.5 / 25.5 (1.4x) | 16.6 / 14.1 / 26.4 (1.2x) | 1.5x | 1.3x |
| Rock | 66% | 1.9 | 17.2 / 12.9 / 26.0 (1.3x) | 21.9 / 12.6 / 25.5 (1.7x) | 1.5x | 1.4x |
| Snow | 77% | 1.6 | 12.2 / 8.7 / 17.6 (1.4x) | 12.3 / 9.7 / 18.1 (1.3x) | 2.1x | 1.0x |

**Notes:** The tint is gone, but it overshot dark: grass, rocky grass and rock are 65 to 66%, below the target. The surface has an embossed, filtered grain. Seams are worse than stipple-01: the wrap preview shows visible lines through the grass and rock.
