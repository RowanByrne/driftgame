# Feature: Tyre smoke, grass and mud particles, one painted family

**Status:** built; step 3 (tune and prove) in review; the low end (T-290) in review. **Owner task:** T-279: art round T-280, emitters T-283 (merged), tuning T-286, the low end T-290.

The user, 2026-11-17: *"I want to improve the particle effects we have for tire smoke, grass, and mud effects. right now they clash hard as our particles are super low def and our smoke is super high def. I want something a bit more in the middle that leans towards high def for all. research the best way to do them, similar to how we did the tire mark effect changes, and propose a plan."*

This sits beside `features/car-fx.md` (the gates, rates, heat and fades are all unchanged) and changes only **what the particles look like**.

## Goal

Every particle a drift throws, the tarmac smoke, the grass bits, the mud clods and the gravel dust, looks like it was painted by the same hand as the environment concept art and the painted vista: soft-edged, with real shapes, lit by the same day and night. Nothing reads as flat squares, and nothing reads as a photo pasted on a painting.

## The problem, measured

What each effect uses today (`Config/Fx.luau`, built by `makeEmitter` in `Drift/Wheels.luau`). All are `ParticleEmitter`s facing the camera (the default `Orientation`), with no flipbook, no `Squash`, no `ZOffset`, and one flat colour each.

| Effect | Texture | Size (studs, born → dies) | Lifetime | Rate /s | Look | Light |
|---|---|---|---|---|---|---|
| Tarmac smoke, diffuse layer | Built-in `smoke_main.dds`: **128 x 128**, DXT5, a soft realistic wisp | 2.5 → 11 | 0.8–1.6 s | 8–60 | 0.55 see-through, fades in, any rotation, slow spin | Lit by the scene (`LightInfluence` 1, `LightEmission` 0) |
| Tarmac smoke, stylized layer | Same `smoke_main.dds` | 0.9 → 4.2 | 0.30–0.55 s | 0–42 (by tyre heat) | 0.18, fast spin (±140°/s) | Half lit, half glowing (`LightInfluence` 0.6, `LightEmission` 0.35) |
| Grass clippings | Built-in `SquareParticle.png`: a **solid white square**, 256 x 256, 346 bytes, no shading and no soft edge | 0.42 → 0.26 | 0.45–0.8 s | 25–90 | Fully opaque from birth, one flat green, spinning ±400°/s | Fully lit (1, 0) |
| Mud / dirt clods | Same `SquareParticle.png` | 0.55 → 0.35 | 0.5–0.9 s | 20–110 | Fully opaque, one flat brown, ±300°/s | Fully lit (1, 0) |
| Gravel dust | `smoke_main.dds`, tan | 1.6 → 6 | 0.6–1.1 s | 10–45 | 0.5 see-through | Fully lit (1, 0) |
| Floor-scrape sparks (`Drift/Scrape`) | Roblox's default sparkle | 0.12 → 0 | 0.15–0.35 s | 30–160 a point | Streaks (`VelocityParallel`, `Squash` 1.5) | Glowing (0, 1) |

**Why they clash.** It isn't the pixel count: the smoke's texture is actually the smaller one. It's three things:

1. **The debris isn't a picture of anything.** A clipping or a clod is a flat-coloured square with hard edges, a third to half a stud across. From the chase camera that's a few pixels, spinning flat on the screen, so it reads as pixel confetti. It was chosen on purpose as "the low-poly look" (`T-188`), under the old "stylized low poly" pillar, before the user's painted concept art became the target (2026-11-15).
2. **The smoke is a photo-real wisp.** `smoke_main` is a soft, blurry, realistic texture, so it scales up smoothly and reads as "high def". It isn't painted either: the concept art's smoke is heaped, billowing, shaded cloud (`snow-pass-sunset.png`, `autumn-maple-cliffs.png`), the same hand as the cloud sea the user picked for the vista (`assets/painted-vista/cloud-oil-03.png`, "Heaped billows").
3. **Each layer is lit differently.** The clods and clippings are fully lit and go nearly black at night. The stylized puff glows a little at every hour. The diffuse smoke is fully lit. So the gap is widest at night and sunset, and on grass there's no soft layer at all: the smoke fades out and only the squares are left.

## What made the tyre-mark changes work, and the particle version of it

`T-265` and `T-269` replaced Roblox's built-in `Trail` with something made for the job. What worked:

| Tyre marks (T-265, T-269, T-274) | The particle analogue |
|---|---|
| Researched how good racing games draw marks before building | This research (below) |
| Dropped the built-in primitive's look (a flat unlit quad) for one made on purpose: a lit ribbon with a shaped profile | Drop the built-in textures (`SquareParticle`, `smoke_main`) for **sprite sheets made for this game** |
| A streak texture with variety along the mark | A **flipbook sheet of variants**, so each particle picks a different puff, blade or clod |
| Soft edges and fade-in/out, never a hard edge | Painted alpha edges, and edge colour bled into the clear pixels so no dark or white fringe shows |
| Lit by the scene, so it reads by day and by night | **One lighting rule for every particle**, checked at noon, sunset and night |
| Made in code at first, then uploaded once it was settled, because a 1 024 x 1 024 `EditableImage` costs 32 tiles of the client's mesh memory (`T-274`) | **Uploaded sheets from the start:** they cost no mesh memory, and Roblox doesn't document `EditableImage` on particles |
| Measured: heights, vertices, frame time, day and night shots | Measured: live particle counts, rates under the mobile cap, frame time, three shots (noon, sunset, night) |

## Research: what Roblox gives us today

Checked 2026-11-17 against [the ParticleEmitter reference](https://create.roblox.com/docs/reference/engine/classes/ParticleEmitter) and [the particle emitters guide](https://create.roblox.com/docs/effects/particle-emitters).

- **Flipbooks.** `FlipbookLayout`: `None`, `Grid2x2` (4 frames), `Grid4x4` (16), `Grid8x8` (64), or `Custom` with `FlipbookSizeX` and `FlipbookSizeY`. The texture must be an exact multiple of the grid. The release supports square textures up to **1 024 x 1 024**, and custom layouts since removed the square and power-of-two rules ([flipbook release](https://devforum.roblox.com/t/particles%E2%80%99-flipbook-release/2029388), [custom layouts](https://devforum.roblox.com/t/client-beta-optimize-your-particle-animations-with-custom-flipbook-layouts/4005128)). Plan for 1 024 and measure what Roblox decodes (ART-PIPELINE step 5).
  - At 1 024: **2x2 is 512 px a frame** (4x the smoke's current 128), and **4x4 is 256 px a frame**, plenty for a one-stud clod.
  - `FlipbookMode`: `Loop`, `OneShot` (once over the lifetime), `PingPong`, `Random` (random order, crossfaded). `FlipbookFramerate` goes up to 30 fps. `FlipbookStartRandom` plus a framerate of **0 gives each particle one random still frame**. That's the variety trick, and it needs no animation drawn.
  - `FlipbookBlendFrames` crossfades between frames instead of cutting.
  - The guide asks for **spacing between frames** so mipmaps don't bleed one frame into the next.
  - **Flipbooks cost memory, and Roblox may turn them off on low-memory devices** (older phones). What a sheet looks like then is unmeasured (a risk, below).
- **`Orientation`**: `FacingCamera` (today), `FacingCameraWorldUp` (turns only about world up, so a puff painted lit-from-above stays lit from above), `VelocityParallel` and `VelocityPerpendicular` (lined up with the direction it flies, which is good for blades and streaks).
- **`Squash`**: stretches a particle over its life. Positive is tall and thin; it's negative with `VelocityParallel`.
- **`ZOffset`**: moves a particle toward or away from the camera without changing its size. It layers emitters: the debris and the stylized puff in front of the diffuse cloud.
- **Light**: `LightEmission` 0 is normal blending and 1 is additive (glow). `LightInfluence` 0..1 is how much the scene lights it (**`Instance.new` makes it 0, Studio makes it 1**: always set it). `Brightness` only works at `LightInfluence` 0.
- **Cost**: one emitter makes at most **400 particles a second on desktop and 100 on mobile**. Large particles cost fill-rate, and overlapping see-through layers (overdraw) cost GPU time. Today's `Dirt.RateMax` (110) is already over the mobile cap.
- **Beams**: a textured strip between two points. Good for a streak or a spray sheet, not for puffs or bits. Not used.
- **Small 3D chunks (MeshParts) instead of particles**: real 3D, lit and able to cast shadows, but each one is a part to pool and move every frame (`Scrape` does this for six spark slots). A spray is 60 to 100 bits a car, plus a mesh to make in Blender and upload. From the chase camera a painted sprite of a clod reads the same. Not now (see "Left out").

## The approach (recommended)

**Three uploaded sprite sheets, painted in one hand, and one lighting rule.** Every effect is drawn from one of them:

| Sheet | Grid | Frames | Used by | Tinted? |
|---|---|---|---|---|
| **Billows** | 2x2 at 1 024 (512 px a frame) | 4 heaped cumulus puffs, white tops, cool grey-lavender undersides, soft painted edges | Tarmac smoke (both layers), gravel dust, and the new grass spray puff | Yes: painted near-neutral, coloured by each emitter's `Color` (rubber white, tan dust, earthy green-brown spray) |
| **Grass bits** | 4x4 at 1 024 (256 px a frame) | 16 torn blades, tufts and turf scraps, painted green with yellow tips and darker roots | Grass clippings | No: painted in colour, `Color` white |
| **Clods** | 4x4 at 1 024 | 16 mud clods and crumbs, a lit top edge and a wet dark side, a few with grass still on | Mud / dirt spray | No: painted in colour, `Color` white |

How each effect changes:

- **Tarmac smoke, diffuse.** The billows sheet, a random still frame each (`FlipbookStartRandom`, framerate 0). Or `Random` mode with `FlipbookBlendFrames`, so a puff slowly morphs as it grows: the lane decides. `FacingCameraWorldUp`, rotation kept within about ±15° so the painted light stays on top. Sizes and rates start where they are, and the rate may come down because a painted puff is denser than a wisp. `ZOffset` about −0.5, so everything else draws in front of it.
- **Tarmac smoke, stylized.** The same sheet: smaller, more opaque and a shade warmer, as now, but its glow drops (`LightEmission` 0.35 to about 0.1) so it doesn't shine at night.
- **Grass clippings.** The grass-bits sheet, **bigger and fewer**: about 0.6 → 0.4 studs (from 0.42 → 0.26) at about 15–55 a second (from 25–90). A soft fade at the end instead of a pop. Spin about ±200°/s, not ±400°/s. The lane picks between `FacingCamera` and `VelocityParallel` (blades lined up with their flight).
- **Mud / dirt.** The clods sheet, about 0.8 → 0.5 studs at about 12–60 a second (from 20–110, which brings it under the mobile cap), heavier and less spin.
- **New: a grass spray puff**, one emitter per wheel. The billows sheet in an earthy green-brown, low rate, behind the bits. Today the smoke fades out on grass and nothing soft replaces it. This is the layer that makes clods and smoke one family, and the concept art always has it (spray, leaves and petals in a cloud). It runs on the same per-wheel grass mix and dirt share as the bits.
- **Gravel dust.** Moved onto the billows sheet in tan. Free once the smoke is done.
- **One lighting rule.** Every particle sits at `LightInfluence` about 0.8 with `LightEmission` 0 (the stylized puff about 0.1), so the scene tints them all alike: gold at sunset, blue at night, never pitch black. That's checked at noon, sunset and night (`features/day-night.md`).
- **Clean edges.** The build script that fits each pick into its exact grid also leaves a gutter between frames and fills the clear pixels with the nearest painted colour (edge bleed). That way mipmaps and alpha blending show no dark or white outline round a puff.

Everything keeps the current rules: built once, switched with `Enabled` and `Rate`, and no new `NumberSequence` while driving.

## Options for the user

1. **The style of all of them.**
   - **A. Painted billows** (recommended): match the concept art and the vista's cloud sea.
   - **B. Keep today's realistic smoke** and make only the bits realistic to meet it: soft-edged photo-like clods and dust.
   - **C. Cel-shaded** puffs and bits: two flat tones with a hard light/shade line, anime-style.

   A is the only one that matches the world the user picked. B is the cheapest change to the smoke the user approved. C is the boldest, and the vista isn't drawn that way.
2. **Where the debris comes from.** Painted sprites on particles (recommended), or small 3D chunks. The chunks are real 3D and cast shadows, but cost a mesh, an upload, and parts moved every frame. Not now.
3. **The grass spray puff** (recommended: yes). Adds 4 instances a car, 46 to 50.
4. **The stylized smoke layer.** Keep it on the new sheet (recommended), or drop it now that the billows have their own shape. Dropping it saves 4 emitters a car.
5. **How candidates are shown.**
   - Previews made off-line (recommended, and nothing is uploaded until the pick): each sheet, plus a still of its puffs and bits composited over a lane screenshot of the car drifting, by day and by night.
   - Or the user allows the candidates to be uploaded, unused and private, so they can be compared in a lane. ART-PIPELINE says never to upload art the user hasn't picked, so this needs their OK.

## Art the user picks

All from `tools\imagegen.ps1` with `-Transparent`, which gave real alpha for the vista (`assets/painted-vista/MANIFEST.md`). References are `assets/painted-vista/cloud-oil-03.png` and the two concept paintings with smoke and debris, as mood only. Record every candidate in `assets/particles/MANIFEST.md`.

- **Billows**: 2 to 4 candidates. Each is a sheet of four separate puffs, one per quadrant, on a clear canvas, in the vista's oil hand. Vary the medium (oil impasto, gouache, soft anime cel). The prompt asks for even top light and neutral colour so the game can tint it.
- **Grass bits**: 2 to 3 candidates, a 4x4 set on one clear canvas (ART-PIPELINE: "a set goes on one sheet" so it's one hand).
- **Clods**: 2 to 3 candidates, the same way.
- If the alpha fails (holes, a see-through middle), ask for an opaque version on flat black and key it, as ART-PIPELINE says.

The user picks each sheet. The agent cuts each pick into its exact grid with gutters and edge bleed, uploads it as the user signed in to Studio, measures the decoded size, and records the id. The tuning of sizes, rates and light is then shown in a lane for the user's eye, as every look has been.

## Grass and mud: what was tried, and what was picked (T-283)

The user drove the painted sprites (2026-11-17): the smoke and the dust are good (smoke "a bit" denser and smaller: rate 10–75 from 8–60, size 2.1 → 9 from 2.5 → 11), but *"the dirt and grass sprites look like shit. it just doesn't work. we need a different solution, i don't think it's about the art style."* A flat picture turned to the camera reads as a sticker over a 3D world however it's painted. Three ways were then built behind an on-screen switch and driven: cube 3D chunks, a fine spray of streaks, and the sprites.

**Picked:**
- **Grass: the fine spray.** *"fine spray is my decision for grass - it looks great to simulate blades ripping off and flying away"*. `Grass.Clippings`: the grass-bits sheet as tiny streaks along their flight (`VelocityParallel`, `Squash` 1.4, 0.24 → 0.14 studs, 30–90 a second), thrown from under the middle of the wheel (`DebrisOffset` 0; it was 0.95 studs to one side).
- **Mud: small low-poly 3D clods.** *"the 3D chunks might work for dirt - maybe we should try super low poly (30 tri max) smaller chunks instead of the cubes we have now, and tone up the rate"*. `Drift/Debris`, `Ground.Chunks`: a pool of 96 of Roblox's own corner wedges and wedges per client, each of its own uneven size so a tumbling one reads as a jagged shard (8 triangles at most), in the ground's `Ground` material and the rut's soils, 0.22–0.5 studs, 14–40 a wheel a second on the dirt ramp. Thrown from the debris attachment, they tumble, fly under gravity and drag, bounce once, lie on the ground and sink into it; lit and shadowed like the world, moved together with one `BulkMoveTo` a frame.

**Not EditableMeshes.** The first build made six 20-triangle rocks in code as EditableMeshes, and the tyre marks vanished: those meshes took the client's EditableMesh budget, so neither mark ribbon could be built (DR-Lane2: both failed "no EditableMesh", the console "reaching memory budget limits"; the user: *"the skidmarks are gone? why? fix it"*). A rounder rock would have to be an uploaded mesh asset.

The sprites and the switch are gone, and so is the clods sheet (uploaded, unused). The earthy cloud and the ruts are unchanged.

## Measured (T-286, DR-Lane1, 2026-11-17)

- **Frame time:** the same straddling drift (two wheels on tarmac, two on grass) and an all-grass drift, effects on and off in alternating 3-second blocks, twice each: 22.2 ms mean, 23.3–23.7 ms p95, both ways. Studio held the client at 45 fps, so a difference smaller than that cap can't show here; the CPU cost below is the honest number.
- **The clods' own cost:** `Debris.Step` with all 96 out, thrown at 120 a second (above the four-wheel peak of 113): **168 µs a frame**.
- **Peak rates, four wheels** (sampled every 0.3 s through the drifts): tarmac-side smoke 109/s and the puff 17/s; all-grass drift: grass spray 126/s, earthy cloud 51/s, clods 113/s with up to 70 out at once, gravel dust 31/s. Every emitter's own maximum is at or under the mobile cap of 100 a second.
- **Live particles a car at those peaks** (rate × mean lifetime): tarmac about 140; grass about 97 particles plus up to 70 clods (the pool caps them at 96).
- **Day and night:** at noon the ruts, cloud and clods read as one ground; at night the smoke takes the blue night light without glowing or going black. The clods read as black specks at night at their first colours, so they were lifted (`Chunks.Colours`, 112–162 from 72–120).
- **Lowest graphics quality: not settled.** The one shot at `Level01` caught the car between slides, with nothing firing, so whether phones that turn flipbooks off show the sheets well is still unmeasured.
- **Mesh budget:** both mark ribbons build alongside the clods (none of them is an EditableMesh).

## Smoke over the marks and the wheels (T-289, DR-Lane1, 2026-11-17)

The user: *"looks kinda weird when theres the wheel silhouette and the tire trails render on top of the smoke"*. Three artefacts, two causes, both measured:

- **The marks drawn over the smoke.** Roblox sorts see-through things back to front a whole part at a time, by the part's centre. Each rubber strip is one `MeshPart` 2 000 studs across, centred on its **origin**, which sat where the tyre was when it last moved: behind the car, so toward the chase camera. In a drift the origins were 15 to 18 studs from the camera and the smoke's emitters 49, nearer in 37% of frames (1 792 strip-frames), and those frames drew the whole strip after, so over, the smoke. **Fix:** a strip with a camera keeps its origin `Marks.Ribbon.SortAhead` (600) studs straight down the view, and moves it on when it comes nearer than `SortMinDepth` (300) (`GroundMarks` "sortSpot"). After: 0 of 7 192 strip-frames had an origin nearer than the smoke, about one move every 2.5 s, and the marks don't shift when it moves (FxTests: 3e-5 studs). The grass ribbon is opaque, so it never had this.
- **The wheel-shaped hole.** `ZOffset` moves a particle's depth, so it decides which opaque geometry hides it. The diffuse smoke is born 1.0 stud off the tyre's axis, inside its 1.25 radius, and at −0.5 sat up to about a stud behind the tyre's near face: the tyre cut a hard wheel outline out of the cloud. **Fix:** every emitter moved 1.5 toward the camera, keeping T-283's order: diffuse **1.0**, dust 1.2, spray 1.3, stylized 1.5, bits 1.8.
- **The square-stepped bottom edges.** The same depth test against the road: a puff's camera-facing quad grows faster than it rises, so for its first half second its lower part is under the road and clipped (Roblox has no soft particles). −0.5 made that deeper; at +1.0 about 0.2 studs more of each puff shows at the chase camera's 13° pitch. **It's reduced, not gone:** a flat cut along the cloud's bottom still shows in the lane. Fully removing it means lifting the puffs (spawning higher or rising faster), which changes the approved look, so it's a question for the user.

## The low end: billows or wisp (T-290, DR-Lane3, 2026-11-17)

The user: *"the top end is great, when we are spawning tons of smoke due to crazy drift. the mid and low is not ... at low speeds or when drifts just barely start, we spawn the sprites so slow that it's a sequence of split puffs. Is a solution to use our old drift smoke in combination with the new system?"* Built both answers, behind a live switch, for the user to compare on the same drift; the loser comes out after the pick.

**The cause, measured.** The diffuse layer spawns `Smoke.RateMin` (10) a second at the gate, and the stylized layer starts at zero (it builds with heat). A light drift on the stand-in runs 1-5 degrees at 55-72 studs/s, so one 2.1-stud puff every **5.8 studs**. A mid drift (30-35 degrees, ~40 studs/s) was 1.25 studs apart; a hard one (48-55, slowing to ~18) 0.57.

**The fix: a base layer that hands over.** A third smoke emitter a wheel (`FxBase_<Wheel>_<surface>`, on the diffuse layer's source) spawns **by the stud**: one puff every `Gap` studs of road, clamped to `RateMin`..`RateMax`. As the slip grows it hands over to today's diffuse cloud: with `w` a smoothstep of slip from `HandoverStartDegrees` (15) to `HandoverFullDegrees` (50), the base runs at `(1 - w)` of its rate and the diffuse at `w` of today's. **From 50 degrees on it is today's smoke exactly** (the approved top end); the stylized layer is untouched throughout. Only rates move while driving; a mode change re-dresses the base emitters once.

| Mode | The base layer | Gap | Rate /s | Size (studs) | See-through | Light | ZOffset |
|---|---|---|---|---|---|---|---|
| **`billows`** (default) | The painted billows sheet, smaller and fainter: many puffs merge into one stream, and it grows into today's big clouds as the handover brings the diffuse layer in | 0.7 | 30-95 | 0.9 → 4.5 | 0.72 | the one rule | 1.0 |
| **`wisp`** | Roblox's built-in `smoke_main` wisp, the smoke before T-283 (any rotation, facing the camera), fading out as the painted billows fade in | 1.4 | 15-50 | 1.8 → 8 | 0.66 | the one rule | 1.0 |
| `off` | None: today's smoke exactly | | | | | | |

**The switch.** `workspace:SetAttribute("__low_smoke", "billows" | "wisp" | "off")` (`Config.Fx.LowSmoke.Attribute`), read every frame, so the command bar switches it mid-drive. Or the admin console's `smoke billows|wisp|off` (your screen only). Anything else is the default.

**Measured** (FxTests and three held-steer drives in each mode, the rear-left wheel; live particles are rate × mean lifetime, since Roblox has no live count):

| Mode | Drift | Slip, speed | Base / diffuse / stylized /s | Studs between puffs | Live a car | Frame |
|---|---|---|---|---|---|---|
| off | light | 3.5°, 67 | 0 / 11.3 / 0.3 | **5.77** | ~27 | 5.56 ms |
| off | mid | 32°, 41 | 0 / 21.5 / 11.2 | 1.25 | ~107 | 5.56 ms |
| off | hard | 49°, 18 | 0 / 27.7 / 4.1 | 0.57 | ~139 | 5.55 ms |
| billows | light | 3.6°, 67 | 93.4 / 0 / 0.3 | **0.71** | ~140 | 5.55 ms |
| billows | mid | 32°, 41 | 30.7 / 10.2 / 11.1 | 0.78 | ~140 | 5.56 ms |
| billows | hard | 49°, 18 | 2.5 / 25.7 / 4.1 | 0.56 | ~137 | 5.56 ms |
| wisp | light | 3.5°, 67 | 47.5 / 0 / 0.3 | **1.40** | ~114 | 5.56 ms |
| wisp | mid | 32°, 41 | 15.3 / 10.3 / 11.2 | 1.11 | ~124 | 5.55 ms |
| wisp | hard | 49°, 18 | 1.2 / 25.7 / 4.1 | 0.58 | ~136 | 5.57 ms |

- **Top end unchanged:** at 90 degrees every mode gives the diffuse layer today's 42.5/s and no base (FxTests); at 50 degrees and past, the handover is complete.
- **Mobile cap:** the base peaked at 95/s (billows) and 50/s (wisp) an emitter, under 100.
- **Frame time:** no difference between the modes in Studio (5.55-5.57 ms means); the live particles a car stay at or under today's hard-drift ~140.
- **Budget:** 46 to 50 instances a car (`Wheels.perWheel()` 8 to 9). Switching modes 5 times created nothing.
- **Shots:** a light drift by day in billows and in wisp (both one unbroken stream from each rear tyre), and billows at night.

## Left out

- **3D debris chunks** (option 2). They can come later as a few big clods on top of the sprites, if the sprites don't hold up close.
- **Leaves, petals, snow and rain spray** from the concept art. They need biomes (none since the 2026-11-15 rollback). The billows and bits sheets are where they'd plug in.
- **Coloured smoke as a cosmetic.** It's still a monetization call (`car-fx.md` "Monetization"), but one tinted sheet makes it a single `Color`.
- **Floor-scrape sparks.** Already a glowing streak, and they don't clash with anything. They could move onto the family later (light step 4).
- **Remote cars.** Unchanged: they show none of these effects (`car-fx.md` "Server and client").
- **The marks, the gates, the rates' drivers, the heat and the fades.** Unchanged.

## Rules and numbers

All in `Config/Fx.luau`, starting values to be tuned in a lane:

| Number | Start | What it does |
|---|---|---|
| `Sheets.Billows` / `GrassBits` / `Clods` | the picked ids; `Layout` `Grid2x2` / `Grid4x4` / `Grid4x4` | One texture per family |
| Each emitter's `Flipbook` | `{ Mode = "Loop", Framerate = 0, StartRandom = true, Blend = false }` | A random still frame per particle |
| Each emitter's `Orientation` | smoke and dust `FacingCameraWorldUp`, bits `FacingCamera` | Keeps painted light on top |
| Each emitter's `ZOffset` | diffuse 1.0, dust 1.2, spray 1.3, stylized 1.5, bits 1.8 (T-289: all 1.5 up from −0.5, −0.3, −0.2, 0, +0.3) | Draw order, and in front of the tyre |
| `Smoke.RotationDegrees` | ±15 (from ±180) | Painted light stays up |
| `Light.Influence` / `Light.Emission` | 0.8 / 0 (stylized 0.1) | One lighting rule |
| `Grass.Clippings` | size 0.6 → 0.4, rate 15–55, spin ±200 | Bigger, fewer, calmer |
| `Grass.Dirt` | size 0.8 → 0.5, rate 12–60, spin ±150 | Under the mobile cap of 100 |
| `Grass.Spray` (new) | billows, earthy colour, size 1.2 → 4.5, rate 4–20, 0.6 see-through | The soft layer on grass |

**Budget:** `perWheel()` goes from 8 to 9 with the spray puff, so `perCar()` goes from 46 to 50. Texture memory: three 1 024 sheets, about 1.3 MB each with mipmaps. That isn't the client's mesh memory, because the sheets are uploaded content, not `EditableImage`.

## UI

None.

## Server and client

All client, as `car-fx.md`. Nothing replicated.

## Contracts

`Config.Fx` grows `Sheets`, `Light` and `Ground.Grass.Spray`. `Config.Fx.Names.GroundEmitter` gains the kind `"spray"` (`FxKick_<Wheel>_spray`). `Wheels.perWheel()` goes to 9 and `perCar()` to 50. `DebugState` per wheel grows `sprayRate`. CONTRACTS.md is updated in the same commit.

## Analytics

None.

## Monetization

None now; see "Left out".

## Platform risks

- **Outside art:** none. Every sheet comes from the project's image tool, picked by the user, and is recorded with its prompt and hash. No Creator Store particles (a mixed hand, which is the problem we're fixing), and nothing from the reference game.
- **Low-memory devices may turn flipbooks off.** What a sheet then shows (likely the whole grid on one particle) is unmeasured. Step 3 checks it with Studio's lowest quality level. If it reads badly, the fallback is designing each sheet so the full grid still reads as a cluster of puffs or bits, or one frame per sheet on low graphics.
- **Mobile caps:** each emitter stays at or under 100 a second at its maximum. Fill-rate is checked with the biggest smoke over the whole screen.
- **The car is still the AE86 placeholder,** not approved to publish (unchanged).

## Art and sound

Three sprite sheets (above), final art once picked. No sound.

## Testing

- `FxTests`: each emitter has its sheet's id, layout and an exact-multiple size. No emitter's `RateMax` is over 100. The instance count is 50 and unchanged over 1 000 frames. The spray follows the grass mix and fades like the bits.
- **Lane, quiet playtest:**
  - live particles per car (rate × mean lifetime) on tarmac, grass and gravel, peak against today's 387;
  - frame time with the effects on and off in alternating blocks;
  - the lowest quality level with flipbooks possibly off.
- **Three screenshots:** the same drift at noon, at sunset and at night, for the user's eye.

## Proposed steps

| # | Step | Files | Tier | Needs the user's pick |
|---|---|---|---|---|
| 1 | **The art round:** candidates for billows, grass bits and clods in one hand; off-line previews over a lane screenshot by day and night; after the picks, a build script that fits each into its exact grid with gutters and edge bleed; upload; decoded size checked | `assets/particles/MANIFEST.md`, the picked sheets in `assets/particles/`, candidates in `..\art\generated\particles\` | standard | **Yes**: style (option 1), then one pick per sheet |
| 2 | **The emitters take the sheets:** `makeEmitter` gains flipbook, orientation, `ZOffset`, `Squash` and the one lighting rule from config. The bits get bigger and fewer, the grass spray puff is added (46 to 50), gravel dust moves onto the billows. `FxTests` and CONTRACTS updated | `Shared/Config/Fx.luau`, `Drift/Wheels.luau`, `Tests/FxTests.luau`, `docs/game/CONTRACTS.md`, `features/car-fx.md` | standard | Options 3 and 4 decided first; the sheets from step 1 |
| 3 | **Tune and prove it in a lane:** sizes, rates, light and draw order at noon, sunset and night; particle counts, frame time, mobile caps, the lowest quality level; three screenshots; ready for the user's look | `Shared/Config/Fx.luau` (numbers only), `features/car-fx.md` | standard | The user's look in the lane |
| 4 | *(optional)* **The rest of the family:** floor-scrape sparks and anything else with a built-in texture onto the same light rule (a spark streak painted on the billows' hand if wanted) | `Drift/Scrape.luau`, `Shared/Config/Fx.luau` | light | Only if it adds art |

Steps 2 and 3 can be one worker task. Step 2's code can be written against the built-in textures while step 1's pick is pending, then pointed at the ids.

## Open questions

- Option 1 (the style), and options 3 to 5.
- Whether the user is happy for the **approved** diffuse smoke to change look. The request says "all", so this spec assumes yes. Option B keeps it.
