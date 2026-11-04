# World

This game's world and map: its areas, how players get around, and the named spots code reads. The layout is the user's call. It's sketched and approved before areas are built (docs/workflow/WORLD-BUILDING.md), then kept current as the map changes. How the world looks is in `ART-DIRECTION.md` "World"; how it's built (by code or by hand, streaming) is in `ARCHITECTURE.md`.

## Overview

There is no map yet. The only world is the **prototype testing ground**: a flat 2000 by 2000 stud plate with an open yard round the spawn, a district of blocky buildings making streets and alleys, scattered pillars and cones, and two elevated features — a banked bowl and a ramp. It is built by code at runtime, so the lanes and the Main place are identical. It is a test rig for the drift model, not a level: there is no route, no racing line, no scoring and no goal, and nothing in it survives into the real map except the lessons. Its spec is `features/drift-playground.md`.

The real map is designed once the drift feel is agreed (`ROADMAP.md`). This doc is then rewritten from a layout sketch.

**Map:** none yet. The testing ground needs no sketch: its areas are listed below and every number is in `src/ServerScriptService/Playground/Layout.luau`.

## Areas

| Area | Role | What's there | Unlocks by | Travel from spawn | Status |
|---|---|---|---|---|---|
| The plate | The whole prototype world | A 2000-stud square plate at Y = 0, flat and drivable everywhere | — | 0 s | Built (code) |
| The open yard | Room to reach top speed and hold a slide | 1000 by 740 studs of clear plate round the spawn, with pillars, two blocks and cone clusters scattered in it. Nothing at all within 200 studs of the spawn | — | 0 s, the spawn is in it | Built (code) |
| The district | Streets and alleys to pick a line through | 15 buildings on a 3 by 5 grid, 32 to 140 studs tall, alternating near-black and near-white. The gaps between them are the streets: 44 to 110 studs wide | — | about 4 s to its near edge, 10 s to its far corner | Built (code) |
| The bowl | Holding one slide, and the ground-follow case | A 150-stud constant-radius band, 60 wide, banked 8 degrees, inner edge flush with the plate, with an 80-wide apron outside it falling back to the plate: 259 studs from the middle to the outside | — | about 6 s | Built (code) |
| The ramp | The airborne case | 9 studs of climb over 110, eased in at the bottom and steepest at the top, with a 16-stud lip carrying straight on at that slope to 11.9 studs | — | about 6 s | Built (code) |

**There is no course and no order.** The player spawns in the middle of the yard facing the district with 360 studs of clear plate ahead — reaching top speed takes 90 — and drives wherever they like. The district's widest street, 110 studs, runs straight at the spawn; the narrowest alleys are 44 and punish a wide exit. The circle and the ramp sit off to either side of the yard, both within about 600 studs.

## Getting around

By car, everywhere: the plate is one continuous flat drivable surface, so running wide costs a quarter-stud kerb and nothing else. Buildings and pillars are walls — untagged, so the drift model's ground ray misses them and driving into one is a collision, never a climb. The bowl is entered from any side: the band's inner edge is flush with the plate and its rim stands 8.4 studs proud, and the apron outside it climbs to that rim at 1 in 9.6, so there is no edge anywhere on it taller than the quarter-stud kerb. That matters since `T-026`: a raised surface's vertical faces are walls to the car whether or not they are road, so a rim the car cannot drive up is a rim it cannot cross. A car or character that drives off the plate's edge falls; `PlaygroundService` puts it back at `Spawn` once it is below Y = -40.

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

A ray straight down from every one of them hits a part tagged `DriftSurface` within 5 studs, asserted by `PlaygroundTests`.

## Scale

- **Player:** the car, not a character: top speed 90 studs/s, wheelbase 6 studs (`features/drift-model.md`).
- **Open yard:** x -800 to 200, z -380 to 360 — **1000 by 740 studs** of flat plate. Clear of everything for **200 studs** round the spawn (the nearest obstacle is a pillar at 253).
- **Streets:** six of them, **narrowest 44 studs, widest 110**. Buildings are 92 by 56 studs at the smallest and 104 by 100 at the largest, and 32 to 140 tall.
- **Reach:** the furthest thing in the world is the district's far corner, **895 studs** from the spawn — about 10 seconds at top speed. The bowl is 550 to its middle and 809 to its far outside edge, the ramp 497 to its base.
- **World:** 2000 by 2000 studs. Streaming is **off** (`ARCHITECTURE.md`). Measured budget: **325 parts**, against a limit of 1,500 asserted in `PlaygroundTests`.

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

## Versions

| Version | Date | What changed |
|---|---|---|
| playground-v1 | 2026-11-03 | The first prototype playground: plate, a one-way course of track sections, circle, cones |
| playground-v2 | 2026-11-03 | Replaced by the open testing ground: the course removed entirely, district of buildings and alleys added, one banked circle and one ramp kept |
| playground-v3 | 2026-11-04 | `T-026`: an apron added round the banked circle so the bowl can be driven on to instead of only out of; the ramp's profile changed from eased-in-and-out to steepest-at-the-top so it jumps; the cone cluster in the ramp's mouth moved. 229 parts to 325 |
