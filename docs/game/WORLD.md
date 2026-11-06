# World

This game's world and map: its areas, how players get around, and the named spots code reads. The layout is the user's call. It's sketched and approved before areas are built (docs/workflow/WORLD-BUILDING.md), then kept current as the map changes. How the world looks is in `ART-DIRECTION.md` "World"; how it's built (by code or by hand, streaming) is in `ARCHITECTURE.md`.

## Overview

There is no map yet. There are **three separate worlds**, none of which is the map, each built a different way and each with a different job. They share one Y: every surface in the game tops out at Y = 0 -- except the road, which descends as it is generated (`features/road-elevation.md`). **A fall is therefore measured from the last ground the car touched, not from a world height** (`T-067`): `Config.Drift.FallBelowSurface`, which on flat ground at Y = 0 is the same comparison the old absolute number made. `Config.Playground.FallY` is still absolute and still right for the plate.

### The three worlds, and where each is

| World | Where it is | Built by | What it is for |
|---|---|---|---|
| The hand-placed track | **At the origin**, where its author put it. Within about x/z ±560 | By hand, in `DR-Main` only; git never sees it (`AGENTS.md` "Hand-built content"). Adopted at runtime by `TrackService` | The kart circuit the user added. Only the Main place has one; no lane does |
| The playground | **`Config.Drift.PlaygroundOffsetFromTrack` = (-2024, 0, 0)**, so its 2000-stud plate runs x -3024..-1024 and meets the track's baseplate edge to edge at x = -1024 | Code, by `PlaygroundService` at `Init`, from `Playground/Layout.luau` | Where the drift feel was approved, and where it is tuned. The two above are deliberately **side by side on one continuous floor**, 464 studs of bare baseplate apart, so a car can be driven from one to the other (`T-026`) |
| **The road** | **`Config.Road.Offset` = (0, 0, -20000)** | Code, by `RoadService`, **only when something calls `Generate(seed)`** — it is off by default (`T-044`) | The endless generated road (`features/track-generation.md`). Flat, 50 studs wide, barriers down both edges |

**The road is far away on purpose, and 20 000 studs is a measured number, not a gesture.** It is not a place on a plate: it grows away from its own start for as long as the run lasts, so it needs a quarter of the world to itself. -Z is the empty one — the other two worlds never leave z ±1024, the collision tests stand their rig at (20000, 500, 20000) and the jitter tests probe at (2000, 0, 0). Measured, 500 generated pieces wandered to x -22 739 and z -33 459 and never came back above z -15 821; a random walk of ~350-stud pieces would need about 3 300 of them — some three hours of continuous driving — to drift the 20 000 studs back to the others, and only about fourteen pieces exist at once anyway. `RoadTests` asserts the live window stays clear of both other worlds (18 761 studs at the last measurement).

**Only the window exists.** The road is not a 500-piece object: `AheadPieces` 10 are built in front of the car and `BehindPieces` 4 kept behind it, so about 14 pieces — measured at a peak of 1 059 parts — are in the Workspace at any moment, however long the run. That is why `StreamingEnabled` can stay off for it too.

The **prototype testing ground** (the playground) is a flat 2000 by 2000 stud plate with an open yard round the spawn, a district of blocky buildings making streets and alleys, scattered pillars and cones, and two elevated features — a banked bowl and a ramp. It is a test rig for the drift model, not a level: there is no route, no racing line, no scoring and no goal, and nothing in it survives into the real map except the lessons. Its spec is `features/drift-playground.md`.

The real map is designed once the drift feel is agreed (`ROADMAP.md`). This doc is then rewritten from a layout sketch.

**Map:** none yet. The testing ground needs no sketch: its areas are listed below and every number is in `src/ServerScriptService/Playground/Layout.luau`. The road has no sketch either, by its nature: every piece of it is in `src/ReplicatedStorage/Shared/Config/Road.luau`.

## Areas

| Area | Role | What's there | Unlocks by | Travel from spawn | Status |
|---|---|---|---|---|---|
| The plate | The whole prototype world | A 2000-stud square plate at Y = 0, flat and drivable everywhere | — | 0 s | Built (code) |
| The open yard | Room to reach top speed and hold a slide | 1000 by 740 studs of clear plate round the spawn, with pillars, two blocks and cone clusters scattered in it. Nothing at all within 200 studs of the spawn | — | 0 s, the spawn is in it | Built (code) |
| The district | Streets and alleys to pick a line through | 15 buildings on a 3 by 5 grid, 32 to 140 studs tall, alternating near-black and near-white. The gaps between them are the streets: 44 to 110 studs wide | — | about 4 s to its near edge, 10 s to its far corner | Built (code) |
| The bowl | Holding one slide, and the ground-follow case | A 150-stud constant-radius band, 60 wide, banked 8 degrees, inner edge flush with the plate, with an 80-wide apron outside it falling back to the plate: 259 studs from the middle to the outside | — | about 6 s | Built (code) |
| The ramp | The airborne case | 9 studs of climb over 110, eased in at the bottom and steepest at the top, with a 16-stud lip carrying straight on at that slope to 11.9 studs | — | about 6 s | Built (code) |
| **The test hill** | Feeling a climb and a descent without starting a run | **Twenty pieces of the real endless road**, built permanently off the plate's southern edge: ten climbing at 7 degrees to **259 studs**, then ten descending at 5 and landing level with the plate. 5 136 studs of road, about 2 700 parts, on a plate of its own (`features/test-hill.md`) | — | about 12 s to `HillBase` | Built (code) |

**There is no course and no order.** The player spawns in the middle of the yard facing the district with 360 studs of clear plate ahead — reaching top speed takes 90 — and drives wherever they like. The district's widest street, 110 studs, runs straight at the spawn; the narrowest alleys are 44 and punish a wide exit. The circle and the ramp sit off to either side of the yard, both within about 600 studs.

## Getting around

By car, everywhere: the plate is one continuous flat drivable surface, so running wide costs a quarter-stud kerb and nothing else. Buildings and pillars are walls — untagged, so the drift model's ground ray misses them and driving into one is a collision, never a climb. The bowl is entered from any side: the band's inner edge is flush with the plate and its rim stands 8.4 studs proud, and the apron outside it climbs to that rim at 1 in 9.6, so there is no edge anywhere on it taller than the quarter-stud kerb. That matters since `T-026`: a raised surface's vertical faces are walls to the car whether or not they are road, so a rim the car cannot drive up is a rim it cannot cross. A car or character that drives off the plate's edge falls; `PlaygroundService` puts it back at `Spawn` once it is below Y = -40.

**The test hill is entered from the south edge** and nowhere else: a short ramp off the plate at `HillBase`, then twenty pieces of road with barriers down both sides, ending back at plate level on the hill's own ground. The **LIFT TO HILL TOP** button puts the car at the crest without driving up, and the **GUARDRAILS** button stands every wall on the hill *and* on the endless road down so the hill can be left on purpose (`features/test-hill.md`). Fall off low down and the pad catches you; fall off near the top, 259 studs up, and the client's own fall test (`FallBelowSurface`, 150) puts you back at `Spawn` before you land.

## Landmarks and wayfinding

Value contrast does the work, because the old course failed for want of it: buildings are near-black (38, 42, 50) and near-white (206, 210, 214) against a mid-grey plate (104, 112, 120), alternating across the grid, so a street reads as a street from the far side of the yard. The ramp is the only warm colour in the world. Pillars are the darkest thing in the open. **Nothing stands in the driving line to mark a place:** a named spot is shown by a flat 26-stud disc lying on the ground, not by a pillar. Cones are scattered in clusters to aim at and miss, and are put back when they are knocked over.

## Named spots

Every spot comes from `PlaygroundService:GetSpot(name)`, which returns a CFrame facing a sensible way to set off; the positions live only in the layout module (`CONTRACTS.md`).

**The spots are world-space and already carry `PlaygroundService.Offset`**, which is zero unless the place also has a hand-placed track — a place with both builds the playground out of the track's way (`PlaygroundOffsetFromTrack`, `T-026`). The layout's own coordinates stay written about the origin; where the playground *is* is a world-level fact and lives in `Config.Drift`. So read a spot, never a layout coordinate.

| Spot | Area | How code finds it | Teleport |
|---|---|---|---|
| `Spawn` | The open yard | `PlaygroundService:GetSpot("Spawn")` | (no admin console yet) |
| `OpenGround` | The open yard | `PlaygroundService:GetSpot("OpenGround")` | " |
| `PillarRun` | The open yard | `PlaygroundService:GetSpot("PillarRun")` | " |
| `DistrictGate` | The district | `PlaygroundService:GetSpot("DistrictGate")` | " |
| `Boulevard` | The district | `PlaygroundService:GetSpot("Boulevard")` | " |
| `TightAlley` | The district | `PlaygroundService:GetSpot("TightAlley")` | " |
| `CircleCentre` | The banked circle | `PlaygroundService:GetSpot("CircleCentre")` | " |
| `RampBase` | The ramp | `PlaygroundService:GetSpot("RampBase")` | " |
| `HillBase` | The test hill | `PlaygroundService:GetSpot("HillBase")` | " |
| `HillTop` | The test hill | `PlaygroundService:GetSpot("HillTop")` | the **LIFT TO HILL TOP** button (`Drift/TestHud`) |

A ray straight down from every one of them hits a part tagged `DriftSurface` within 5 studs, asserted by `PlaygroundTests`.

**`HillTop` is the only spot on a graded surface**, and it is read off the road piece it sits on rather than from a coordinate, so it carries that piece's grade and bank. `PlaygroundService:HillTopCFrame()` is the same pose moved down the spot's **own** up to `RideHeight`, which is what the lift button puts a car at; moving it down the world's up would be a stud out sideways on a 7-degree climb. Spot markers are laid in the spot's own frame for the same reason (which fixed `RampBase` too).

## Scale

- **Player:** the car, not a character: top speed 90 studs/s, wheelbase 6 studs (`features/drift-model.md`).
- **Open yard:** x -800 to 200, z -380 to 360 — **1000 by 740 studs** of flat plate. Clear of everything for **200 studs** round the spawn (the nearest obstacle is a pillar at 253).
- **Streets:** six of them, **narrowest 44 studs, widest 110**. Buildings are 92 by 56 studs at the smallest and 104 by 100 at the largest, and 32 to 140 tall.
- **Reach:** the furthest thing in the world is the district's far corner, **895 studs** from the spawn — about 10 seconds at top speed. The bowl is 550 to its middle and 809 to its far outside edge, the ramp 497 to its base.
- **World:** 2000 by 2000 studs, **plus the test hill's own plate off its southern edge** — 1 474 by 1 738 studs, sized at build time to the hill's footprint plus 180, overlapping the main plate so there is no seam to drop through. Streaming is **off** (`ARCHITECTURE.md`). Measured budget: **326 parts** for the playground proper against a limit of 1,500, and the hill against its own `HillPartBudget` of 3,400; both asserted in `PlaygroundTests`.
- **The hill's eastern limit is `CarService:WorldAt`, not the ground.** That answers "which world is this position in" by which world's spawn is nearer, and the line between the playground's and a track's falls at about x = +1 010 in layout coordinates — the plate's own eastern edge, which is where the two worlds meet. A hill reaching past it would have a car falling off its eastern side respawn on the kart track. `Layout.Hill.x` is set so the pad stops at x = 957, and `PlaygroundTests` measures every corner of it.

### Surface fidelity

The one measurement that matters, because a surface that reads as segments quietly breaks the drift model (`PITCH.md` "Biggest risks"). A ray walked down the ideal line of each elevated feature at 1-stud steps, measured in `DR-Lane2`:

| Feature | Segments | Largest height change per stud | Holes |
|---|---|---|---|
| Circle band, centre line | 96 | 0.004 studs | none |
| Circle band, 24 studs out (the high edge) | 96 | 0.005 studs | none |
| Circle band, 24 studs in (the low edge) | 96 | 0.004 studs | none |
| Apron, centre line | 96 | 0.012 studs | none |
| Apron, 34 studs in (the high edge) | 96 | 0.017 studs | none |
| Apron, 34 studs out (the low edge) | 96 | 0.004 studs | none |
| Ramp, centre line and both edges | 32 | 0.161 studs | none |
| Ramp lip | 2 | 0.163 studs | none |

The ramp's two numbers are its own slope, not a joint: the launch profile is steepest where it ends and the lip carries that slope on (`features/drift-playground.md`). The limit `PlaygroundTests` asserts is 0.25 studs per stud.

The limit asserted in `PlaygroundTests` is 0.25 studs per stud travelled, so the worst of these has half the budget left. The plate itself is flat to within a thousandth of a stud, checked by a 25-stud grid of 1,230 rays over the open yard.

**Two things a banked box gets wrong, and how they are fixed.** A part can bank but it cannot twist, and two neighbours on a curve share their centre point while turning by the yaw step, so their *outer* corners pull apart into a wedge — from the ground that reads as a bite out of the rim. Each box is now lengthened by exactly (half the width) times (the yaw step), which closes it. Separately, a raised edge on a thin ribbon shows daylight under it: the circle and the ramp are 14-stud-thick prisms and the plate is 24 thick, so every underside is buried. Both were checked by eye from the ground, not only by ray.

## Looking at it in Studio: the showroom

Every one of the three worlds is built by code at runtime, so in Studio's **edit mode** the place is empty and there is nothing to fly around. `src/ServerScriptService/Tools/Showroom.luau` is the answer to that: an edit-mode tool that builds the playground and one of every road piece into the open place's Workspace, where they can be flown around, clicked and looked at while the code that makes them is still being written. Nothing in the game requires it and it is never reached at runtime.

Run it from Studio's command bar, and take it away again the same way:

```
require(game.ServerScriptService.Tools.Showroom).build()
require(game.ServerScriptService.Tools.Showroom).clear()
```

What it leaves behind, all of it under one folder and all of it anchored:

| Under `Workspace.Showroom` | What it is |
|---|---|
| `Playground` | exactly what `PlaygroundService:Build()` makes, where it makes it: 325 parts |
| `Gallery` | one of every variant in `Pieces.order()`, in a grid: 16 pieces, 2,091 parts |

The gallery sits past the playground's plate -- 400 studs clear of it -- in as square a grid as the set allows, of cells as wide as the widest piece plus a gap. All of it is measured from the built parts, so the layout re-lays itself when the piece set changes: the nine flat pieces made a 3 x 3 and the sixteen of the touge set make a 4 x 4, with no two pieces closer than 245 studs.

**The touge pieces drop, and the floor drops with them.** Every variant is placed from a socket at road level and the grid centres it in X and Z only, never in height, so a piece that descends starts level with its neighbours and falls away from them -- which is the one thing worth seeing about it. They reach as far below road level as they descend: 12 studs of slab for the flat nine and the `Link`, 27 for a `Banked30`, 32 for a `Corkscrew`, 52 for a `HairpinStack`. So each cell has a floor pad of its own, flush under the bottom of the piece over it, and a descending piece stands on a plinth rather than sinking through one slab laid at road level.

`build()` is `clear()` followed by a fresh build, so seeing a code change is one line and there is never a second showroom.

**The labels are two, and they take turns.** Each piece has its variant id on a sign lying flat in front of it, in 45-stud letters, and on a small billboard 13 studs above it. The sign is the one that reads from the air; the billboard is only for when the camera is down among the pieces, where a sign lying on the ground is edge-on. Both are sized in **studs**, so both shrink with distance like the thing they name, and the billboard stops drawing past 210 studs so a pulled-back view has none of them in it at all.

**Both were halved on the user's call** (2026-11-06), and the numbers either side of it, measured from cameras 300, 800 and 1 500 studs over the sixteen-piece grid at 1525 x 663 and 70 degrees. Sign height on screen went from 3-235 pixels to 2-114 at 300 studs up, 5-39 to 3-19 at 800, and 5-17 to 3-8 at 1 500; the billboard went from 111 x 28 pixels to 55 x 14 in the close-up it exists for. No two labels overlap at any of the three heights and no billboard draws at any of them -- where at the old size the signs did overlap, in two pairs, from 300 studs up. The far rows at 1 500 studs are a few pixels tall and are not meant to be read from there: fly lower.

The version before that sized the billboard in *pixels*, which does not shrink with distance: nine labels 110 pixels tall, a sixth of the screen each, overlapping in 27 to 36 of the 36 pairs and hiding every piece.

Three things to know:

- **Save the place (Ctrl+S) or it is gone.** The showroom is ordinary instances in the Workspace, not something a script rebuilds on open.
- **A playtest takes it down by itself, and leaves it alone.** `PlaygroundService:Build()` destroys `Workspace.Showroom` before it lays its own playground, because the two sit at the same coordinates and two playgrounds in one space is a place nobody can drive in. A playtest runs on a copy of the datamodel, so nothing that is saved is touched: stop the playtest and the showroom is still there to fly around. You do not have to clear it by hand.
- **It borrows the place's baseplate.** The playground's own 2 000-stud plate is coplanar with Studio's default `Baseplate`, so `Build()` destroys it exactly as the game does. The showroom records its size, position, colour and material first, and `clear()` puts it back.

## Versions

| Version | Date | What changed |
|---|---|---|
| playground-v1 | 2026-11-03 | The first prototype playground: plate, a one-way course of track sections, circle, cones |
| playground-v2 | 2026-11-03 | Replaced by the open testing ground: the course removed entirely, district of buildings and alleys added, one banked circle and one ramp kept |
| playground-v3 | 2026-11-04 | `T-026`: an apron added round the banked circle so the bowl can be driven on to instead of only out of; the ramp's profile changed from eased-in-and-out to steepest-at-the-top so it jumps; the cone cluster in the ramp's mouth moved. 229 parts to 325 |
| road-v1 | 2026-11-04 | `T-044` step 1: the endless road, a third world at (0, 0, -20 000). Two piece types — a 220-stud `Straight` and a mirrored 220-radius 90-degree `Corner` — 35 studs wide, flat, with barriers down both edges. Off by default; a run starts on `RoadService:Generate(seed)` |
| road-v2 | 2026-11-04 | `T-050` added the sweeper (radius 400, 45°), the hairpin (radius 70, 180°, gated to piece 8) and the chicane (radius 140, 40° each way), each number measured by driving it. `T-052` widened the road to 50 studs on the user's call and made the lookahead a standing plan sliced across ticks: the worst single generator call went from 1 422 ms to 8.31 ms, and the road stopped trapping itself |
| playground-v4 | 2026-11-06 | `T-065`: the **test hill** — twenty real road pieces, ten climbing at 7 degrees to 259 studs and ten descending at 5 to exactly plate level — built permanently off the southern edge on a plate of its own, with a lift button to its top and a switch that stands the guardrails down (`features/test-hill.md`) |
