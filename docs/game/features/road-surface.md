# Feature: Road surface

**Status:** trial, waiting on the user (T-268). **Owner task:** `agent/road-texture-trial` (`docs/CLAIMS.md`).

## Goal

The user, 2026-11-16: *"i want to work on a road texture rework, going for more of what we see in the concept art, try that pls".* The tarmac should read like the mountain roads in the concept art (`assets/reference/environment-mood/`, ART-DIRECTION.md "References"): a real Japanese pass with painted lines, worn wheel tracks and a surface that changes as you drive, not a flat grey band. Looks only: driving is unchanged.

## What the concept art's roads have that ours didn't

- **Tone:** a cool blue-violet mid grey that catches the light, lighter where worn. Ours was one flat dark grey, and since the grass texture went on (T-187) it had lost even Asphalt's grain.
- **Painted lines:** solid white edge lines just in from each edge (sakura, autumn), and a centre line (solid orange in sakura, faint white dashes in snow). Ours had only the white centre dashes.
- **Wheel tracks:** darker, polished bands where the tyres run in each lane, and long curving tyre streaks through the bends (autumn, snow).
- **Edges:** the last stud or two of tarmac is lighter and dusty, broken up, gravel creeping on before the shoulder.
- **Variation along the road:** patches of newer and older tarmac, repairs, cracks near the edges, soft painterly mottling.
- **Grain:** soft brush-stroke grain stretched along the road, not fine noise.
- **Not in this trial:** wet sheen and reflections (rain scenes), and leaves or petals lying on the road: weather and scenery.

## How it plays

Nothing changes in how the car drives. The surface the car reads, grip, and the mesh's shape and triangle count are exactly as before (`Drift/SplineWorld` stands the car on the curve's maths; the mesh is purely visual).

## Left out

- **No uploaded or generated image.** The texture is painted in code on each device, so nothing needs the user's pick before it can be tried. No image-tool candidates were made: the code version reads well, and a generated image could not be previewed in the lane without uploading it.
- **Wet roads, puddles and reflections** (would need a roughness map, `SurfaceAppearance`, and weather).
- **Road debris** (leaves, petals): scenery, with the biomes.
- **The road drawing its own grass** (`__runoff_by = "road"`, T-251's other option): its mesh carries the grass's texture, so its tarmac stays flat with the dash parts, as before.
- **A parts copy of the road** (a device that cannot make meshes, `Road/SplineParts`) keeps the plain Asphalt tarmac.

## Rules and numbers

`Road/RoadTexture` paints one image, 1 024 x 1 024 pixels (the largest EditableImage a client makes: 2 048 either way is refused, measured), that every road chunk shares (`Road/SplineMesh` sets it as the road MeshPart's texture):

- **U runs across the tarmac**, edge to edge (19.2 pixels a stud), **V along the road**, one copy every `PeriodStuds` (240, rounded to whole `MarkInterval`s so the dashes run on). Along needs fewer pixels (4.3 a stud): it is seen at a glancing angle.
- **The plain band:** the image's first and last 32 columns are `Grass.Shade` grey. The gravel bevels, the skirt and a grove's trees sample UV (0, 0) there, so they look exactly as before.
- **Painted in this order:** the tarmac colour; two broad, faint wheel tracks a lane (`TrackGap` apart, `TrackDark` of the way to `TarmacWorn`, their grain smoother, wandering a little) and a fainter oil strip between them; the dusty edge (`EdgeWear`, ragged, with gravel specks); faint patches of newer tarmac, ragged and feathered, with a light seam; grain (large mottling, painterly strokes stretched along, a finer aggregate octave, speckle; smoother in the tracks and patches); the lines (solid white edge lines `EdgeLineInset` in from each edge, the centre line `CentreLineStyle`), worn by noise; then thin cracks (`CrackWidth`, mostly along the edges, a few short ones across). Tyre streaks can be painted (`Streaks`) but are off (below).
- **The tone:** each tarmac vertex is shaded darker or lighter by up to `Tone` (and a little warmer or cooler) from slow noise along the road, which never repeats, so the 240-stud period does not show as a repeat. It changes only along the road and slowly, so a chunk drawn coarse far ahead (T-263) shades almost exactly as the same chunk drawn whole.
- **The centre-line dash parts are gone** when the tarmac is textured: the texture paints the dashes, on the same `MarkInterval` / `MarkDashLength` world spacing, so the speed cue (2026-11-04) is kept.
- **When:** a client starts painting as soon as the road's code loads, `SliceMs` (3) a frame; a chunk asking earlier waits for it.
- **Switching it off:** `Config.Spline.Tarmac.Enabled = false`, or in Studio `workspace.__tarmac_texture = false` (from the next chunk built: start a new run).

The tuning numbers are all in config: colours and lines in `Config.Road` (`Colours.Tarmac`, `TarmacWorn`, `TarmacEdge`, `TarmacPatch`, `Crack`, `TyreStreak`, `EdgeLine`, `CentreLine`; `EdgeLineWidth`, `EdgeLineInset`, `CentreLineStyle`, `CentreLineGap`), the texture in `Config.Spline.Tarmac`. **The orange centre line** of the sakura art (Japan's no-overtaking line): `CentreLine = Color3.fromRGB(232, 158, 52)` with `CentreLineStyle = "solid"` (or `"double"`).

## The send-back (2026-11-16)

The user, on the first cut: *"doesn't work - tyre marks are ugly. try again, bit higher res this time for the main asphalt texturing"*.

- **Tyre marks:** the first cut painted four pairs of dark tyre streaks and dark, sharp wheel tracks (0.9 of the way to `TarmacWorn`, 3.2 studs wide). In a texture that repeats along the road a streak cannot follow the bends, so they read as parallel stripes; and they were the colour of the car's own drift marks (`Config.Fx.Marks`: (26, 26, 28) at 0.52 transparency over this tarmac makes about (49, 50, 57); a painted streak was about (50, 51, 58)), so they looked like drift marks that never fade. Now: **no painted streaks**, and the wheel tracks are broad, faint polish (0.3 of the way, 4.5 studs wide, grain half as rough): a track's middle is about (63, 64, 75) against the tarmac's (70, 72, 84), so a live drift mark, about (49, 50, 57), stays clearly darker than anything painted.
- **Resolution:** 256 x 1 024 over 480 studs became 1 024 x 1 024 over 240: four times the pixels across (19.2 a stud), twice along (4.3), with a finer aggregate octave of grain (`Fine`, `FineStuds`) and cracks drawn `CrackWidth` wide. The shorter repeat is hidden by the vertices' tone, which never repeats; there are 2 patches a copy instead of 4, and 6 cracks instead of 10.
- **Patches:** at the higher resolution the first cut's patches showed as hard flat rectangles (one lighter, "older"). Now: newer, darker tarmac only, half blended, feathered over 0.6 studs, its edge made ragged by noise.

## Platform risks

None. Nothing is uploaded; the image exists only in each client's memory.

## Art and sound

The tarmac's look, painted in code. Trial: the user judges it in a lane.

## Testing

Measured in lanes 4 (before), 2 (first cut) and 1 (after the send-back, on main with T-263), seed 31337, the road as the client draws it (ground runoff):

| | Before | First cut | After the send-back |
|---|---|---|---|
| Triangles a chunk (8 chunks) | 1 218 | 1 218 (539 textured tarmac) | 1 218 (539) |
| Plain parts a chunk | 147.4 | 127.4 (the 20 dash parts gone) | 127.4 |
| Building a chunk | 8.24 ms of work, 2.9 frames | 8.32-8.65 ms, 2.6 frames | 8.74 ms, 2.8 frames |
| Most of a chunk any one frame paid | 4.3 ms | 4.35-4.7 ms | 4.58 ms (aim 3; one step can overrun, as before) |
| The image | none | 256 x 1 024, 1 MB | 1 024 x 1 024, 4 MB (the client's total memory rose 9.9 MB while it was painted, the 4 MB pixel buffer included) |
| Painting it, once, as the client loads | none | 58-62 ms of work over 20-21 frames | 243 ms of work over 78 frames (630 ms wall); the longest frame meanwhile 10.6 ms |
| Render CPU / GPU a frame, parked at noon, texture off then on in one session | | 1.41-1.72 / 0.33-0.40 off, 1.40-1.46 / 0.33-0.35 on | 1.66-1.76 / 0.50-0.52 off, 1.52-1.62 / 0.29-0.34 on |

- **Far chunks (T-263):** its `Mesh.Far` draws a chunk with one strip across and cuts up to 96 studs apart. The lines, tracks and patches are in the texture, mapped by distance across and along, so they stay put; only the per-vertex tone could differ. Over 6 000 studs, drawn far against drawn whole, the tone differs by 0.4% of brightness on average and 2.3% at worst (5.7% before it was made along-only and slower). Built with `Config.Spline.Mesh.Far` on main after T-263 merged (`Tolerance = 1, MaxStep = 96, Across = 1`): 292 triangles a chunk, all 30 tarmac faces mapped, 3.99 ms. Live, early in a run: 4 near chunks and 7 far, all 11 with the tarmac's texture, none with dash parts, 12 rebuilt from far to near with no fallback.
- **Mapping:** of a chunk's 1 218 faces, all 539 tarmac faces are mapped inside the tarmac's columns and 678 others sample the plain corner (one face is neither; not chased).
- **Driving:** unchanged by construction (nothing the car reads was touched).
- **The car's drift marks on it:** measured by colour, above (a live mark stays clearly darker than the painted tracks). A screenshot of them was tried and missed: the drift ran off onto the grass.

## As built

- `Road/RoadTexture` (new): `enabled()`, `period()`, `base(s0)`, `uv(s, d, base)`, `tone(s, d)`, `paint(yield)`, `get()`, `prepare()`, `DebugState()`.
- `Road/SplineMesh`: when the ground draws the runoff, the road's mesh takes the tarmac's texture instead of the grass's; the tarmac's vertices get UVs and tones, the bevels keep the plain band, and no dash parts are made. Stats gain `tarmacTriangles`, `grassTextured`, `tarmacTextured`.
- Config: `Config.Spline.Tarmac` (new block), and the colour and line keys in `Config.Road`.

## Open questions

- **The user's verdict on the second cut,** and the centre line: white dashes (default, keeps the speed cue) or solid orange like the sakura art.
- If kept: a roughness map for wet roads with weather, and per-biome tarmac colours (`features/road-biomes.md`).
