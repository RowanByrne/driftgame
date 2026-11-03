# Feature: Drift playground

**Status:** built (prototype). **Owner task:** `T-004`, branch `agent/drift-playground` (`docs/CLAIMS.md`). The world it describes is in `WORLD.md`; the numbers are in `src/ServerScriptService/Playground/Layout.luau`.

The world the prototype is felt in: "a basic baseplate world with some obstacles to drift around" (`ROADMAP.md` "Next"). Not the game's map, and nothing in it survives into the real one except the lessons.

## Goal

Give the drift model somewhere to prove itself: enough shapes that every part of the model is felt within a minute of driving, and nothing else. It is a test rig, not a level.

## How it plays

The player spawns on a flat plate in a car and drives. Within sight of the spawn there is:

1. **A straight** long enough to reach top speed, with a braking marker.
2. **A 90° corner** with a wide entry: the main thing to learn.
3. **A hairpin**, tighter than the slide wants, so a bad entry is punished.
4. **An S-bend**, two corners that need the car caught and flicked the other way: the test of `GripBlendOut`.
5. **A constant-radius circle**, for holding one slide for as long as the player can.
6. **A ramp and a berm**, for the ground follow and the airborne case.
7. **Cones**, scattered: visible markers to aim at and miss, which are knocked over and reset, so a line can be judged by eye.

Driving off the plate drops the car; it respawns at the start. There is no scoring, no timer and no goal: the player drives until they know how it feels.

## Rules and numbers

- **Built by code at runtime,** not by hand in Studio, so it is in git, is the same in every lane and place, and can be changed in a commit. Recorded in `ARCHITECTURE.md` "World and streaming".
- **One layout module** holds every position and size; the builder reads it and creates the parts. No positions anywhere else (`docs/workflow/WORLD-BUILDING.md`).
- **Named spots:** `Spawn`, `StraightStart`, `CornerEntry`, `HairpinEntry`, `SBendEntry`, `CircleCentre`, `RampBase`. Gameplay and tests refer to these by name, never to coordinates.
- **Surfaces are smooth.** Corners, the circle and the berm are made of enough segments that the drift model's ground rays never read a step: a corner is at least 24 segments, the circle 48 (`PITCH.md` "Biggest risks": fidelity against the low-poly look). Flat-shaded and untextured is fine; segmented elevation is not.
- **Everything is anchored**, with no constraints, so nothing of Roblox's physics touches the car. The cones are the exception: they are the one thing allowed to be knocked about, and they never touch the car's simulation.
- **Scale:** the plate is 2000 by 2000 studs, which is a lap of about 25 seconds at the model's top speed.

## UI

None.

## Server and client

The server builds the playground once on start, in `Workspace`. The client builds nothing. Falling off and respawning is the server's.

## Contracts

- `PlaygroundService:GetSpot(name)` returns a named spot's CFrame; `DebugState()` lists the spots and the part count.
- Tag `DriftSurface` on every part the car may drive on, so the model's rays can filter to it.

## Analytics

None in the prototype.

## Monetization

None.

## Platform risks

None: untextured parts of our own.

## Art and sound

Placeholder: flat colours from `ART-DIRECTION.md`'s palette if there is one, else grey with coloured markers. No art is generated for this world, and none of it ships.

## Testing

- `DebugState()` returns every named spot and the part count; a playtest asserts each spot exists and sits on a surface.
- A ray down from each named spot hits a part tagged `DriftSurface` within 5 studs.
- The circle's and corners' segment counts are asserted, because the fidelity rule above is the one that quietly breaks the drift model.
- Part count stays under 1,500, and a playtest joins with no console warnings.


## As built

| Module | What it is |
|---|---|
| `ServerScriptService/Playground/Layout.luau` | Every position and size: the plate, the course chain, the circle, the markers and the cone scatter. Nothing else holds a coordinate |
| `ServerScriptService/Playground/Path.luau` | The pure maths: walking a straight, an arc and a ring. Every node of an arc sits on the true circle, so consecutive nodes are its chords |
| `ServerScriptService/Playground/Build.luau` | Turns nodes into anchored, tagged parts. Neighbouring segments share their endpoints, so the top faces meet exactly and a ground ray reads a curve, never a joint |
| `ServerScriptService/Services/PlaygroundService.luau` | Builds the world at `Init` (`Priority` 100), hands out the spots, catches fallers, resets cones |
| `ReplicatedStorage/Shared/Config/Playground.luau` | The tuning that is not geometry: the fall height, the cone reset, the part budget, the placeholder palette |
| `ServerScriptService/Tests/PlaygroundTests.luau` | The asserted rules: spots on surfaces, segment counts, everything anchored and constraint-free but the cones, the part budget, and the ray walks |

**The course, as a chain.** Each step starts where the last one ended, so the surface is continuous by construction and moving one feature moves everything after it. Straight 620, 90 degree corner at radius 150 over a 4-stud crest, link 210, 180 degree hairpin at radius 62, link 190, S-bend of 72 degrees each way at radius 120 with 50 between, link 170, a 90 degree berm at radius 160 banked 12 degrees, link 150, a ramp climbing 11 studs over 130 and an 18-stud lip. The circle is separate: radius 150 to the middle of its road, banked 4 degrees.

**Why the berm costs 192 segments.** A part can bank but it cannot twist, so where the bank changes, two neighbouring segments disagree at the road's edge by half the width times the bank change over one segment. Its arc length, bank and segment count are set by that, not by taste. A banked ribbon also rotates about its centre line, which would bury its inner edge in the plate, so the centre line lifts with the bank to keep that edge level with the road: the berm and the circle are bowls to lean on, not walls.

**Measured** (`DR-Lane2`, 2026-11-03): 493 parts, 64 cones. The largest surface height change per stud travelled, along the ideal curve of each feature, is in `WORLD.md` "Surface fidelity": 0.004 studs on the circle, 0.098 on the 90 degree corner, 0.078 on the berm, 0.127 up the ramp, with no sample missing a tagged surface.

## Open questions

- Nothing to decide: it is a test rig, and it is replaced by the real map when the feel is agreed.
