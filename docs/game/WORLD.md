# World

This game's world and map: its areas, how players get around, and the named spots code reads. The layout is the user's call. It's sketched and approved before areas are built (docs/workflow/WORLD-BUILDING.md), then kept current as the map changes. How the world looks is in `ART-DIRECTION.md` "World"; how it's built (by code or by hand, streaming) is in `ARCHITECTURE.md`.

## Overview

There is no map yet. The only world is the **prototype playground**: a flat 2000 by 2000 stud plate with a chain of drift shapes laid across it, built by code at runtime so the lanes and the Main place are identical. It is a test rig for the drift model, not a level — no scoring, no timer, no goal — and nothing in it survives into the real map except the lessons. Its spec is `features/drift-playground.md`.

The real map is designed once the drift feel is agreed (`ROADMAP.md`). This doc is then rewritten from a layout sketch.

**Map:** none yet. The playground needs no sketch: its shapes are listed below and every number is in `src/ServerScriptService/Playground/Layout.luau`.

## Areas

| Area | Role | What's there | Unlocks by | Travel from spawn | Status |
|---|---|---|---|---|---|
| Playground plate | The whole prototype world | A 2000-stud square plate at Y = 0, drivable everywhere | — | 0 s | Built (code) |
| The course | The drift shapes, in one chain | Straight, 90 degree corner, hairpin, S-bend, berm, ramp | — | 0 s, it starts at spawn | Built (code) |
| The circle | Holding one slide | A constant-radius banked ring, on its own on the plate | — | about 11 s at the model's top speed | Built (code) |

**The course, in the order you drive it:** a 620-stud straight with three braking boards, a 90 degree corner over a gentle crest, a 180 degree hairpin tighter than the slide wants, an S-bend of two 72 degree corners the car has to be caught and flicked through, a banked berm, and a ramp that launches it off the end. The circle sits apart, to be driven on to from the plate.

## Getting around

By car, everywhere: the plate is one continuous drivable surface, so running wide off the road costs a quarter-stud kerb and nothing else. A car or character that drives off the plate's edge falls; `PlaygroundService` puts it back at `Spawn` once it is below Y = -40.

## Landmarks and wayfinding

The course's shapes are coloured differently from the plate and from each other, so the next feature reads from a distance. Three red boards either side of the straight count down to the first corner. A translucent yellow pillar stands at every named spot. Cones are scattered along the racing line to aim at and miss, and are put back when they are knocked over.

## Named spots

Every spot comes from `PlaygroundService:GetSpot(name)`, which returns a CFrame facing the way the course runs; the positions live only in the layout module (`CONTRACTS.md`).

| Spot | Area | How code finds it | Teleport |
|---|---|---|---|
| `Spawn` | The course | `PlaygroundService:GetSpot("Spawn")` | (no admin console yet) |
| `StraightStart` | The course | `PlaygroundService:GetSpot("StraightStart")` | " |
| `CornerEntry` | The course | `PlaygroundService:GetSpot("CornerEntry")` | " |
| `HairpinEntry` | The course | `PlaygroundService:GetSpot("HairpinEntry")` | " |
| `SBendEntry` | The course | `PlaygroundService:GetSpot("SBendEntry")` | " |
| `CircleCentre` | The circle | `PlaygroundService:GetSpot("CircleCentre")` | " |
| `RampBase` | The course | `PlaygroundService:GetSpot("RampBase")` | " |

A ray straight down from every one of them hits a part tagged `DriftSurface` within 5 studs, asserted by `PlaygroundTests`.

## Scale

- **Player:** the car, not a character: top speed 90 studs/s, wheelbase 6 studs (`features/drift-model.md`).
- **Sizes:** the road is 60 studs wide and sits a quarter stud proud of the plate. The 90 degree corner's radius is 150 studs, the hairpin's 62, the S-bend's 120, the berm's 160, and the circle's 150 to the middle of its road. The ramp climbs 11 studs over 130.
- **World:** 2000 by 2000 studs, about a 25 second lap at top speed. Streaming is **off** (`ARCHITECTURE.md`). Measured budget: **493 parts**, against a limit of 1,500 asserted in `PlaygroundTests`.

### Surface fidelity

The one measurement that matters, because a surface that reads as segments quietly breaks the drift model (`PITCH.md` "Biggest risks"). A ray walked down the ideal curve of each feature at 1-stud steps, measured in `DR-Lane2`:

| Feature | Segments | Largest height change per stud | Holes |
|---|---|---|---|
| Circle, centre line | 48 | 0.004 studs | none |
| Circle, 20 studs out | 48 | 0.004 studs | none |
| 90 degree corner, centre line | 32 | 0.053 studs | none |
| 90 degree corner, 20 studs out | 32 | 0.098 studs | none |
| Hairpin | 48 | 0.000 studs | none |
| Berm, centre line | 192 | 0.078 studs | none |
| Berm, 24 studs in (the low edge) | 192 | 0.067 studs | none |
| Berm, 24 studs out (the high edge) | 192 | 0.157 studs | none |
| Ramp | 32 | 0.127 studs | none |

The limit asserted in `PlaygroundTests` is 0.25 studs per stud travelled, so the worst of these has a little over half the budget left.

The berm is the expensive one: a part can bank but it cannot twist, so where the bank changes, two neighbouring segments disagree at the road's edge. Its outer edge is the worst case in the whole world, because it both climbs with the bank and carries that disagreement. Its arc length, bank and segment count are all set by that, and the reasoning is written into the layout module beside the numbers.

## Versions

| Version | Date | What changed |
|---|---|---|
| playground-v1 | 2026-11-03 | The prototype playground: plate, course, circle, cones |
