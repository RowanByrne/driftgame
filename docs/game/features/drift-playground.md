# Feature: Drift playground

**Status:** specced. **Owner task:** none yet (`docs/CLAIMS.md`).

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

## Open questions

- Nothing to decide: it is a test rig, and it is replaced by the real map when the feel is agreed.
