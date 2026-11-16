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

`Road/RoadTexture` paints one image, 256 x 1 024 pixels, that every road chunk shares (`Road/SplineMesh` sets it as the road MeshPart's texture):

- **U runs across the tarmac**, edge to edge (4.8 pixels a stud), **V along the road**, one copy every `PeriodStuds` (480, rounded to whole `MarkInterval`s so the dashes run on). Along needs fewer pixels (2.1 a stud): it is seen at a glancing angle.
- **The plain band:** the image's first and last 8 columns are `Grass.Shade` grey. The gravel bevels, the skirt and a grove's trees sample UV (0, 0) there, so they look exactly as before.
- **Painted in this order:** the tarmac colour; two wheel tracks a lane (`TrackGap` apart, darker toward `TarmacWorn`, wandering a little) and a faint oil strip between them; the dusty edge (`EdgeWear`, ragged, with gravel specks); patches of newer and older tarmac with a seam; grain (large mottling, painterly strokes stretched along, fine speckle; smoother in the tracks and patches); the lines (solid white edge lines `EdgeLineInset` in from each edge, the centre line `CentreLineStyle`), worn by noise; then cracks (mostly along the edges, a few short ones across) and a few long pairs of tyre streaks.
- **The tone:** each tarmac vertex is shaded darker or lighter by up to `Tone` (and a little warmer or cooler) from slow noise along the road, which never repeats, so the 480-stud period does not show as a repeat. It changes only along the road and slowly, so a chunk drawn coarse far ahead (T-263) shades almost exactly as the same chunk drawn whole.
- **The centre-line dash parts are gone** when the tarmac is textured: the texture paints the dashes, on the same `MarkInterval` / `MarkDashLength` world spacing, so the speed cue (2026-11-04) is kept.
- **When:** a client starts painting as soon as the road's code loads, `SliceMs` (3) a frame; a chunk asking earlier waits for it.
- **Switching it off:** `Config.Spline.Tarmac.Enabled = false`, or in Studio `workspace.__tarmac_texture = false` (from the next chunk built: start a new run).

The tuning numbers are all in config: colours and lines in `Config.Road` (`Colours.Tarmac`, `TarmacWorn`, `TarmacEdge`, `TarmacPatch`, `Crack`, `TyreStreak`, `EdgeLine`, `CentreLine`; `EdgeLineWidth`, `EdgeLineInset`, `CentreLineStyle`, `CentreLineGap`), the texture in `Config.Spline.Tarmac`. **The orange centre line** of the sakura art (Japan's no-overtaking line): `CentreLine = Color3.fromRGB(232, 158, 52)` with `CentreLineStyle = "solid"` (or `"double"`).

## Platform risks

None. Nothing is uploaded; the image exists only in each client's memory.

## Art and sound

The tarmac's look, painted in code. Trial: the user judges it in a lane.

## Testing

Measured in lanes 4 (before) and 2 (after), seed 31337, the road as the client draws it (ground runoff):

| | Before | After |
|---|---|---|
| Triangles a chunk (8 chunks) | 1 218 | 1 218 (539 of them textured tarmac) |
| Plain parts a chunk | 147.4 | 127.4 (the 20 dash parts gone) |
| Building a chunk | 8.24 ms of work, 2.9 frames | 8.32 and 8.65 ms (two runs), 2.6 frames |
| Most of a chunk any one frame paid | 4.3 ms | 4.35-4.7 ms (aim 3, one step can overrun; the same spread as before) |
| Painting the texture, once | none | 58-62 ms of work over 20-21 frames (159 ms wall) |
| Render CPU / GPU a frame, parked at noon, same session, texture off then on | 1.41-1.72 / 0.33-0.40 ms | 1.40-1.46 / 0.33-0.35 ms |

- **Far chunks (T-263):** its `Mesh.Far` draws a chunk with one strip across and cuts up to 96 studs apart. The lines, tracks and patches are in the texture, mapped by distance across and along, so they stay put; only the per-vertex tone could differ. Over 6 000 studs, drawn far against drawn whole, the tone differs by 0.4% of brightness on average and 2.3% at worst (5.7% before it was made along-only and slower). Built with those options (`tolerance = 1, maxStep = 96, across = 1`): 292 triangles a chunk, all 30 tarmac faces mapped, 3.96 ms. Checked against T-263's numbers by passing them as `SplineMesh.build` options, not on its branch.
- **Mapping:** of a chunk's 1 218 faces, all 539 tarmac faces are mapped inside the tarmac's columns and 678 others sample the plain corner (one face is neither; not chased).
- **Driving:** unchanged by construction (nothing the car reads was touched).

## As built

- `Road/RoadTexture` (new): `enabled()`, `period()`, `base(s0)`, `uv(s, d, base)`, `tone(s, d)`, `paint(yield)`, `get()`, `prepare()`, `DebugState()`.
- `Road/SplineMesh`: when the ground draws the runoff, the road's mesh takes the tarmac's texture instead of the grass's; the tarmac's vertices get UVs and tones, the bevels keep the plain band, and no dash parts are made. Stats gain `tarmacTriangles`, `grassTextured`, `tarmacTextured`.
- Config: `Config.Spline.Tarmac` (new block), and the colour and line keys in `Config.Road`.

## Open questions

- **The user's verdict on the look,** and the centre line: white dashes (default, keeps the speed cue) or solid orange like the sakura art.
- If kept: a roughness map for wet roads with weather, and per-biome tarmac colours (`features/road-biomes.md`).
