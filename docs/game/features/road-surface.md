# Feature: Road surface

**Status:** the tarmac approved (T-268, the user: "road surface looking great"); the gravel's texture waiting on the user (T-270). **Owner task:** `agent/gravel-texture` (`docs/CLAIMS.md`).

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

Nothing changes in how the car drives. The surface the car reads, grip, and the mesh's shape are exactly as before (`Drift/SplineWorld` stands the car on the curve's maths; the mesh is purely visual). The player sees a weathered touge: two faded, cracked white edge lines, plain textured asphalt, and a double yellow centre line only through the tight bends, starting just before each and ending just after.

## Left out

- **No generated image.** The texture is painted in code, so nothing needs the user's pick before it can be tried. No image-tool candidates were made: the code version reads well, and a generated image could not be previewed in the lane without uploading it.
- **Uploaded since T-274:** a painted 1 024 x 1 024 EditableImage holds 32 tiles of the client's mesh memory (`ground-trial.md` "The mesh budget"), so the painted pixels were exported exactly (0 of 4 194 304 bytes differ, read back from Roblox) and uploaded (`assets/road/MANIFEST.md`); the client loads that and paints nothing. Only a client that cannot load it paints it, a few ms a frame as before, and makes it opaque content, which holds none of that memory either. `SplineMeshTests` checks the painting still sums to `Tarmac.ImageHash`: change anything it paints from and the image is exported and uploaded again. In a lane, `workspace.__tarmac_painted = true` before Play draws the painted one, to compare.
- **Wet roads, puddles and reflections** (would need a roughness map, `SurfaceAppearance`, and weather).
- **Road debris** (leaves, petals): scenery, with the biomes.
- **The road drawing its own grass** (`__runoff_by = "road"`, T-251's other option): its mesh carries the grass's texture, so its tarmac stays flat with the dash parts, as before. So does the texture switched off, and a device that will not make the image.
- **A parts copy of the road** (a device that cannot make meshes, `Road/SplineParts`) keeps the plain Asphalt tarmac and its own dashes.
- **Tyre marks and wheel tracks:** none painted (send-back 2). Tracks only on the hairpins would need a second tarmac in the image, and the car's own drift marks already rubber a hairpin it is drifted round; the code for tracks stays, off (`TrackDark = 0`).

## Rules and numbers

`Road/RoadTexture` paints one image, 1 024 x 1 024 pixels (the largest EditableImage a client makes: 2 048 either way is refused, measured), that every road chunk shares (`Road/SplineMesh` sets it as the road MeshPart's texture):

- **Columns, left to right:** 32 plain, the tarmac (832: 16.6 pixels a stud across), the LINE BAND (32), the gravel band (96), 32 plain. **V runs along the road**, one copy every `PeriodStuds` (120 since send-back 4; 240 before). Along: 8.5 pixels a stud (4.3 before send-back 4).
- **The plain bands** are `Grass.Shade` grey. The gravel bevels, the skirt and a grove's trees sample UV (0, 0) there, so they look exactly as before.
- **The tarmac, painted in this order:** the tarmac colour; the dusty edge (send-back 4: going over to the gravel's bare bed in soft ragged shapes, no specks); faint patches of newer tarmac, ragged and feathered, with a light seam; grain (large mottling, painterly strokes stretched along, a finer aggregate octave, speckle); the two white edge lines, `EdgeLineInset` in from each edge; then thin cracks (`CrackWidth`, mostly along the edges, a few short ones across), and `LineCracks` short cracks across each edge line.
- **The paint's weathering** (edge lines and double yellow alike): each line fades along the road between `LineFade` of full over `LineFadeStuds`, each side on its own; wears through to the tarmac in holes (`LineHoles`, `LineHoleStuds`); thins with the fine grain (`LineGrain`) and the wear noise (`LineWear`); has its sides chipped (`LineChip`); and is broken by cracks across it.
- **The double yellow** (`Config.Road.CentreLine*`): only on the TIGHT STRETCHES, `RoadTexture.centreRuns`: wherever the curve is tighter than `CentreLineRadius` (130 studs: every hairpin, 70 to 95, and the tightest "Tight" bends), `CentreLineLead` (40) studs either side as lead-in and run-out, gaps under `CentreLineMerge` (80) closed so a switchback's two bends get one line, read on a fixed grid of `CentreLineStep` (2) studs along the whole road. A chunk anywhere, near or far, finds the same runs (checked: 12 chunks' runs joined equal the whole road's). Each line is a strip of the road's mesh, `CentreLineWidth` (0.45) wide, `CentreLineGap` (0.45) apart, laid on the drawn tarmac between its own vertices and lifted `CentreLineLift` (0.04, plus a quarter of the chunk's tolerance: 0.29 on a far chunk); the mesh gets a cut at each end of a run, so the line starts and stops square. The strips are mapped to the line band: one weathered yellow line on tarmac, the second line half a period on so the two never wear alike. **Why strips:** the texture repeats along the road, so its pixels cannot know where the bends are.
- **The tone:** each tarmac vertex is shaded darker or lighter by up to `Tone` (and a little warmer or cooler) from slow noise along the road, which never repeats, so the 120-stud period does not show as a repeat. It changes only along the road and slowly, so a chunk drawn coarse far ahead (T-263) shades almost exactly as the same chunk drawn whole.
- **No centre dashes** where the tarmac is textured, neither painted nor as parts (send-back 2). That drops the speed cue the dashes were added for (2026-11-04); the edge lines' weathering and the grain still stream past.
- **When:** a client starts painting as soon as the road's code loads, `SliceMs` (3) a frame; a chunk asking earlier waits for it.
- **Switching it off:** `Config.Spline.Tarmac.Enabled = false`, or in Studio `workspace.__tarmac_texture = false` (from the next chunk built: start a new run).

The tuning numbers are all in config: colours and lines in `Config.Road` (`Colours.Tarmac`, `TarmacWorn`, `TarmacEdge`, `TarmacPatch`, `Crack`, `EdgeLine`, `CentreLine`; `EdgeLineWidth`, `EdgeLineInset`, `CentreLineStyle` (`"tight"` or `"none"`), `CentreLineWidth`, `CentreLineGap`, `CentreLineRadius`, `CentreLineLead`, `CentreLineMerge`, `CentreLineStep`, `CentreLineLift`), the texture in `Config.Spline.Tarmac`.

## The send-back (2026-11-16)

The user, on the first cut: *"doesn't work - tyre marks are ugly. try again, bit higher res this time for the main asphalt texturing"*.

- **Tyre marks:** the first cut painted four pairs of dark tyre streaks and dark, sharp wheel tracks (0.9 of the way to `TarmacWorn`, 3.2 studs wide). In a texture that repeats along the road a streak cannot follow the bends, so they read as parallel stripes; and they were the colour of the car's own drift marks (`Config.Fx.Marks`: (26, 26, 28) at 0.52 transparency over this tarmac makes about (49, 50, 57); a painted streak was about (50, 51, 58)), so they looked like drift marks that never fade. Now: **no painted streaks**, and the wheel tracks are broad, faint polish (0.3 of the way, 4.5 studs wide, grain half as rough): a track's middle is about (63, 64, 75) against the tarmac's (70, 72, 84), so a live drift mark, about (49, 50, 57), stays clearly darker than anything painted.
- **Resolution:** 256 x 1 024 over 480 studs became 1 024 x 1 024 over 240: four times the pixels across (19.2 a stud), twice along (4.3), with a finer aggregate octave of grain (`Fine`, `FineStuds`) and cracks drawn `CrackWidth` wide. The shorter repeat is hidden by the vertices' tone, which never repeats; there are 2 patches a copy instead of 4, and 6 cracks instead of 10.
- **Patches:** at the higher resolution the first cut's patches showed as hard flat rectangles (one lighter, "older"). Now: newer, darker tarmac only, half blended, feathered over 0.6 studs, its edge made ragged by noise.

## Send-back 2 (2026-11-16)

The user, on the second cut: *"get rid of the dashes - it's not realistic. do the 2 painted lines on either side - that's the classic touge design style. they should be faded and cracked/weather lines though. you can do the double yellow lines that touge has for dangerous 2 lane sections, like switchbacks. I still don't like the tire marks you did - you can use those types of marks on hairpins maybe - otherwise keep it simple textured"*.

- **No dashes** anywhere the tarmac is textured.
- **The edge lines** weathered (above): faded along the road, worn through, chipped and cracked across.
- **The double yellow** on the tight stretches only, as strips of the mesh (above).
- **No wheel tracks or tyre marks:** plain textured asphalt. Not tried on the hairpins (Left out).
- The image keeps its 1 024 x 1 024; the line band takes 32 columns from the tarmac (19.2 to 18.6 pixels a stud).

## The gravel (T-270)

The user, after approving the tarmac: *"do the same for the gravel on the sides of the road. get a proper texture for it, that is."*

- **What was gravel:** the bevel at each edge of the tarmac (in the road's mesh, sampling the image's plain grey band, in `GravelColour`), and a tight cliff edge's narrow gravel runoff (T-181), which the ground mesh draws (T-251) with its vertices in `GravelColour`.
- **The gravel band:** 96 more columns of the same 1 024 x 1 024 image (no image of its own, no memory more), right of the line band, painted in code by `RoadTexture.paintGravel` with random numbers of its own. It covers `BandStuds` (3) across at 29 pixels a stud, and repeats every `PeriodStuds` (64) along at 16 pixels a stud; the right side reads half a copy on from the left.
- **Its look: B, the user's pick of three (2026-11-16),** painted like the approved asphalt: a dusty bed (`Colours.GravelDust`) with the asphalt's kind of grain (soft mottling, strokes stretched along, a finer octave; no per-pixel speckle), and a medium density of stones (about 420 a copy, radius 0.15 to 0.36 studs) with soft painted shading (a soft edge a few pixels wide, lighter toward the light, a faint soft shadow; no outlines, no cel steps), their tones a little toward `GravelLight` or `GravelDark`. Looks A (dense small stones) and C (mostly bed) and the Studio switch between them are gone; the numbers are B's, in `Config.Spline.Gravel`.
- **In the asphalt's colours** (send-back 3, "keep the coloration generally of the road"): the blue-violet grey of `Tarmac`, a little lighter and less blue, dustier. In the image, the gravel's middle is (88, 89, 98) against the tarmac's (77, 79, 92); it was a warm light grey, (110, 108, 109).
- Its edges have no hard seam: its bare bed (no stones) takes over in soft ragged shapes over its first `EdgeSoft` (0.45) studs, the bed the tarmac's dusty edge goes over to (send-back 4), and grass (`Colours.GravelGrass`) in soft shapes from `GrassFrom` (2.4) studs to its end.
- **The bevels** are mapped to it, from the tarmac's edge to their foot (the grass end), or to `RunFoot` (2.2, before the grass) in a gravel run, shaded by the tarmac's tone along the road. No triangles more.
- **Lit as one surface with the tarmac** (send-back 3, "edit both gravel and road textures so that they mesh evenly ... the part color might be making it appear quite different in lighting conditions"). What was multiplied in, face by face: the part's colour (white) and material (Asphalt, projected in world space) are one for the whole mesh, and the bevel already took the tarmac's tone, so neither differed. What did: the painted colours (above), and the bevel's normal, flat at its slope, 19 degrees off the tarmac's: at noon it took 22% less sun than the tarmac beside it (sun on the normal 0.69 against 0.88), a crease of light along the road's edge. Now a bevel's top vertex keeps the tarmac's own normal and only its foot has the slope's, so the light runs on across the seam and shades down the bevel. Read off the drawn mesh: sun on the normal at noon 0.88 for the tarmac and the bevel's top (0.84 at its foot); at 17:42 (golden hour) 0.07 for all three; at night the same for both.
- **The gravel runoff:** a strip of the road's mesh laid over a gravel run's flat runoff, from the bevel's foot to the lip, on the surface the car stands on there and lifted `RunoffLift` (0.06, plus a quarter of the chunk's tolerance on a far chunk), mapped to the band's pure gravel (`RunFrom` 1.0 to `RunFoot` 2.2). The ground's vertices under it stay grass now (`GroundMeshView`, look only): coloured gravel, they smeared it a whole ground cell, 8 studs or more, out across the grass beside it. The ground's shape, budget and what the car stands on are unchanged.
- **The tarmac** gives the band its columns: 16.6 pixels a stud across, from 18.6.
- **Switching it off:** `Config.Spline.Gravel.Enabled = false`, or in Studio `workspace.__gravel_texture = false` (from the next chunk built: start a new run): the bevels plain again, no strips, the ground's runoff gravel-coloured again.

### The gravel's send-back (2026-11-16)

The user, on the first gravel: *"texture too noisy and static-y. try something that will match road texture stylization, that sort of anime look we have going in teh concept art"*. The first cut painted about 5 700 tiny faceted stones with per-pixel grain, rims and random grass tufts: it shimmered. Now the look above: flat values, about 160 clear pebbles a copy, nothing per pixel. Measured as the mean difference between neighbouring pixels (green, of 255): the gravel band 2.22, the approved tarmac 2.75, so the gravel is now as calm as the road beside it.

### The gravel's send-back 2 (2026-11-16)

The user, on the anime gravel: *"that's too cartoony"*. So the target sits between the first two: the asphalt's painterly, realistic read at driving distance. Rather than a third single guess, three looks in that range, switchable live in the lane, each tuned to the asphalt's fine detail (above). Painting the image at load with B: 362 ms of work over 110 frames.

### The gravel's send-back 3 (2026-11-16)

The user: *"B. save that and then edit both gravel and road textures so that they mesh evenly. keep the coloration generally of the road. the part color might be making it appear quite different in lighting conditions."* Look B kept as the only one; the gravel in the asphalt's colours; the bevel lit as the tarmac at their seam (above). At the seam itself, the image's last 0.3 studs of tarmac are (104, 102, 103) and the gravel's first 0.3 studs (101, 99, 101): both take the tarmac's dusty edge colour, so they meet within 3 of 255.

## Send-back 4 (2026-11-17, T-277)

The user, on the approved tarmac and gravel, close up: *"is the road texture stretched length wise (the axis u drive, not across the road)? The gravel texture seems so too. Also is that static-y texture I drew a circle around part of the road texture or the gravel texture? it doesn't match either style wise."* Then: *"fix the road stretch ... On texture, just use the current area that is static-y on the road texture to prepare for the transition to gravel, the soft transition is what we are looking for. no gravel pebbles on the road texture itself tho"*.

- **The tarmac's stretch:** it had 16.6 pixels a stud across but 4.3 along (1 024 pixels over 240 studs), so its grain smeared along the road. Now one copy every 120 studs: **8.5 along**, the image the same size. What is counted a copy is halved, so the road per stud is as approved: 1 patch a copy (8.3 per 1 000 studs, as before), 3 cracks (25 per 1 000), 5 cracks across each edge line and the yellow (42 per 1 000). The noise is in studs already. The repeat is twice as often, still under the vertices' tone, which never repeats (its `ToneStuds` 200 is longer than a copy).
- **The static strip** was the tarmac's dusty edge: gravel specks, single random pixels, between the edge line and the gravel. Gone. The last stud or so of tarmac now goes over to the gravel's bare bed (`GravelDust`, its colour and value) in soft ragged shapes, all of it in the last `EdgeFull` (0.25) studs, none past `EdgeWear` (1.4), with the asphalt's grain and the per-pixel speckle fading out into it; the gravel band's first `EdgeSoft` studs start from the same bare bed, its stones coming in raggedly. No stones or specks on the tarmac.
- **The gravel's stretch** was a bug: a stone was turned in pixels, where a stud along is 16 pixels and across 29, so a stone turned square to the road came out longer along than across. Now it is turned in studs: every stone is the shape `Aspect` asks for. The gravel's own resolution is unchanged (29 across, 16 along: features are in studs, so nothing is stretched, only a little softer along).

| Measured on the painted image | Before (v1) | Now (v2) |
|---|---|---|
| Tarmac pixels a stud, across / along | 16.6 / 4.3 | 16.6 / 8.5 |
| Gravel pixels a stud, across / along | 29.3 / 16 | 29.3 / 16 |
| Stones' extent along / across (all 422 a copy, geometric mean; worst) | 1.86; 4.68, 65% over 1.5 | 1.00; 1.42, none over 1.5 |
| The dusty edge (outer 0.9 studs), mean neighbouring-pixel difference (green, of 255) | 15.4 | 1.7 (tarmac's middle 2.7, the gravel band 2.1) |
| Tarmac's last 0.3 studs / gravel's first 0.3 studs | (104, 102, 103) / (101, 99, 101) | (88, 89, 99) / (88, 89, 99): within 1 |
| Patches / cracks per 1 000 studs | 8.3 / 25 | 8.3 / 25 |
| The image | 1 024 x 1 024 | the same, so no memory or build change |

Uploaded as `tarmac-v2.png` (`assets/road/MANIFEST.md`), read back identical. Not changed: the gravel's period (64 studs) and the grain's own stroke shapes, stretched along by design (`GrainStuds` 0.6 x 3.5): if the road still reads streaky, those are next.

## Platform risks

None. Since T-274 the painted image is uploaded (`assets/road/`, `Config.Spline.Tarmac.Image`): code-made pixels, owned by whoever was signed in to Studio, so check the experience may load it before launch (ART-PIPELINE.md "Ownership and permissions").

## Art and sound

The tarmac's look, painted in code. Trial: the user judges it in a lane.

## Testing

Measured in lanes 4 (before), 2 (first cut) and 1 (second and third cuts, on main with T-263), seed 31337, the road as the client draws it (ground runoff):

| | Before | First cut | Second cut | Third cut (send-back 2) |
|---|---|---|---|---|
| Triangles a chunk | 1 218 (chunks 1-8) | 1 218 (539 textured tarmac) | 1 218 | 1 215 over chunks 1-11, the double yellow included: 612 of its triangles in 4 of the 11 (84 to 232 each); far, 261 with 124 |
| Plain parts a chunk | 147.4 | 127.4 (the 20 dash parts gone) | 127.4 | 102.5 over chunks 1-11 (no dashes) |
| Building a chunk | 8.24 ms of work, 2.9 frames | 8.32-8.65 ms, 2.6 frames | 8.74 ms, 2.8 frames | 8.28 ms (worst 11.1), 2.7 frames; far 3.50 ms |
| Most of a chunk any one frame paid | 4.3 ms | 4.35-4.7 ms | 4.58 ms | 4.81 ms (aim 3; one step can overrun, as before) |
| The image | none | 256 x 1 024, 1 MB | 1 024 x 1 024, 4 MB (client memory +9.9 MB while painted, the 4 MB pixel buffer included) | the same |
| Painting it, once, as the client loads | none | 58-62 ms of work over 20-21 frames | 243 ms of work over 78 frames | 244 ms over 78 frames (638 ms wall); the longest frame meanwhile 10.0 ms |
| Render CPU / GPU a frame, parked at noon | | 1.41-1.72 / 0.33-0.40 off, 1.40-1.46 / 0.33-0.35 on | 1.66-1.76 / 0.50-0.52 off, 1.52-1.62 / 0.29-0.34 on | 1.56-1.67 / 0.36-0.37 on |

- **Far chunks (T-263):** its `Mesh.Far` draws a chunk with one strip across and cuts up to 96 studs apart. The lines, tracks and patches are in the texture, mapped by distance across and along, so they stay put; only the per-vertex tone could differ. Over 6 000 studs, drawn far against drawn whole, the tone differs by 0.4% of brightness on average and 2.3% at worst (5.7% before it was made along-only and slower). Built with `Config.Spline.Mesh.Far` on main after T-263 merged (`Tolerance = 1, MaxStep = 96, Across = 1`): 292 triangles a chunk, all 30 tarmac faces mapped, 3.99 ms. Live, early in a run: 4 near chunks and 7 far, all 11 with the tarmac's texture, none with dash parts, 12 rebuilt from far to near with no fallback. Third cut: 5 near and 7 far, all textured, no dash parts, no fallback. The double yellow is drawn on far chunks too (124 triangles over 11), from the same runs, so it starts and ends at the same points when a chunk switches; only its lift differs (0.29 far, 0.05 near).
- **Mapping:** of a chunk's 1 218 faces, all 539 tarmac faces are mapped inside the tarmac's columns and 678 others sample the plain corner (one face is neither; not chased).
- **Driving:** unchanged by construction (nothing the car reads was touched).
- **The car's drift marks on it:** measured by colour (send-back 1): a live mark, about (49, 50, 57) over this tarmac, is the darkest thing on it; nothing painted is near it now.
- **Seed 31337's tight stretches:** 206-464 (tightest radius 114), 2 242-2 484 (89, a hairpin), 4 640-5 076 (109).

**The gravel (T-270)**, lane 1, seed 31337, chunks 1-11 near and far:

| | Before (T-268) | With the gravel |
|---|---|---|
| Triangles a chunk, near | 1 215 | 1 225 (the runoff strips: 118 over the 11; the bevels' 2 908 mapped, none added) |
| Triangles a chunk, far | 261 | 263 (strips 28, bevels' 652 mapped) |
| Building a chunk | 8.28 ms, 2.7 frames | 8.93 ms (worst 12.7), 3.0 frames; far 3.62. Later, a slower session, on then off in one go: 10.97 on, 12.87 off (noise; the build code did not change with the look) |
| Most of a chunk any one frame paid | 4.81 ms | 4.64 ms |
| Painting the image, once | 244 ms of work, 78 frames | first cut 232 ms over 75 frames; the anime look 337-348 ms over 101-108 frames (834-888 ms wall), the longest frame meanwhile 11.5-13.8 ms (its pebbles are blended colour by colour) |
| Image memory | 4 MB | 4 MB (a band of the same image) |
| Render CPU / GPU, parked at a gravel run, gravel off then on in one session | 2.13-2.57 / 0.56-0.63 ms | 1.79-2.02 / 0.41-0.49 ms |

- **Seed 31337's gravel runs:** left 1 864-2 130 (runoff 2.7), right 3 878-4 098 (3.4).
- **The ground under them:** 0 of the ground tiles' vertices in the gravel colour with the texture on (292 tiles read).
- **Live:** 6 near and 8 far chunks, no fallbacks, no errors or warnings.

## As built

- `Road/RoadTexture` (new): `enabled()`, `period()`, `base(s0)`, `uv(s, d, base)`, `lineUV(s, side, base, which)`, `centreRuns(spline, s0, s1)`, `tone(s, d)`, `paint(yield)`, `get()`, `prepare()`, `DebugState()`; T-270: `gravelEnabled()`, `gravelPeriod()`, `gravelBase(s0)`, `gravelUV(s, e, base, side)`, `paintGravel(px, yield)`.
- T-270: `Road/SplineMesh` maps the bevels to the gravel band and lays the gravel runoff strips (stats `bevelTriangles`, `gravelTriangles`); `strip` takes an `onFace` callback. `Drift/GroundMeshView` keeps a gravel run's runoff vertices grass while the gravel is textured. Config: `Config.Spline.Gravel` (new block), `Config.Road.Colours.Gravel*`.
- `Road/SplineMesh`: when the ground draws the runoff, the road's mesh takes the tarmac's texture instead of the grass's; the tarmac's vertices get UVs and tones, the bevels keep the plain band, no dash parts are made, and the tight stretches get the double yellow's strips (with a cut at each end of a run). Stats gain `tarmacTriangles`, `grassTextured`, `tarmacTextured`, `centreLineTriangles`, `centreRuns`.
- Config: `Config.Spline.Tarmac` (new block), and the colour and line keys in `Config.Road`.

## Open questions

- **The user's verdict on the third cut.** Their send-back 2 removed the centre dashes, the speed cue of DECISIONS.md 2026-11-04: worth a line in DECISIONS.md if they keep it.
- If kept: a roughness map for wet roads with weather, and per-biome tarmac colours (`features/road-biomes.md`).
