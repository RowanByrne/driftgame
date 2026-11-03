# Feature: Drift playground

**Status:** built (prototype). **Owner task:** `T-004`, branch `agent/playground-open` (`docs/CLAIMS.md`). The world it describes is in `WORLD.md`; the numbers are in `src/ServerScriptService/Playground/Layout.luau`.

The world the prototype is felt in: "a basic baseplate world with some obstacles to drift around" (`ROADMAP.md` "Next"). Not the game's map, and nothing in it survives into the real one except the lessons.

## Goal

Give the drift model somewhere to prove itself, with as little world as that takes. It is a test rig, not a level: a flat plate, obstacles to drift around, and the two shapes the model's ground code needs.

The first attempt was a one-way ribbon of track — straight, corner, hairpin, S-bend, berm, ramp — and the user rejected it (`DECISIONS.md`, 2026-11-03): *"all we need is a flat baseplate for testing - you can put some obstacles like pretend buildings or alleys to try and drift through to test the handling, but we don't need specific sections of track, unless you are building elevation/berms."* That is the brief this is built to.

## How it plays

The player spawns in a car in the middle of an open yard, facing a district of buildings across 360 studs of clear plate, and drives wherever they like. **There is no route, no racing line and no order.** Within sight of the spawn:

1. **The open yard**, 1000 by 740 studs of flat plate, clear of everything for 200 studs round the spawn: room to reach top speed (90 studs of it) and hold a slide as long as they can.
2. **The district**: 15 blocky buildings on a 3 by 5 grid. The gaps are the streets, 44 to 110 studs wide. The 110 is the one the spawn faces and is wide enough to drift down; the 44s punish a wide exit. Corners, crossroads and dead-end-looking gaps are all a matter of which way the player turns.
3. **Pillars and blocks** standing alone in the yard, to swing round, and to give the eye something to measure speed against where there are no buildings.
4. **A banked circle**, 150-stud radius, banked 8 degrees: holding one slide, and the model's ground-follow case.
5. **A ramp**, 9 studs over 110 with a flat lip: the airborne case, and nothing more.
6. **Cones** in clusters, to aim at and miss. They are knocked over and put back, so a line can be judged by eye.

Driving off the plate drops the car; it respawns at `Spawn`. There is no scoring, no timer and no goal: the player drives until they know how it feels.

## Rules and numbers

- **Built by code at runtime,** not by hand in Studio, so it is in git, is the same in every lane and place, and can be changed in a commit. Recorded in `ARCHITECTURE.md` "World and streaming".
- **One layout module** holds every position and size; the builder reads it and creates the parts. No positions anywhere else (`docs/workflow/WORLD-BUILDING.md`).
- **Flat unless it earns its elevation.** The plate is flat to a thousandth of a stud. Only two things rise out of it, the banked circle and the ramp, and only because `features/drift-model.md` "Rules and numbers" -> Ground needs a banked surface and an airborne case.
- **Obstacles are walls, never floors.** A building or a pillar is deliberately *not* tagged `DriftSurface`, so the model's ground ray misses it: driving into one is a collision, not a climb.
- **Named spots:** `Spawn`, `OpenGround`, `PillarRun`, `DistrictGate`, `Boulevard`, `TightAlley`, `CircleCentre`, `RampBase`. Gameplay and tests refer to these by name, never to coordinates.
- **Readable from the driving seat.** The first attempt failed on this: road and plate were the same tone and the world vanished. Obstacles now carry strong value contrast against the plate, and **no marker ever stands in the driving line** — a named spot is a flat disc on the ground.
- **Surfaces are smooth.** The circle is 96 segments and the ramp 32, so the model's ground rays never read a step (`PITCH.md` "Biggest risks": fidelity against the low-poly look). Flat-shaded and untextured is fine; segmented elevation is not.
- **Nothing floats and nothing shows daylight under it.** The circle and the ramp are 14-stud-thick prisms sunk into a 24-stud plate; buildings and pillars sink a stud into it; cones are rested on whatever a ray finds under them.
- **Everything is anchored**, with no constraints, so nothing of Roblox's physics touches the car. The cones are the exception: they are the one thing allowed to be knocked about, and they never touch the car's simulation.
- **Scale:** the plate is 2000 by 2000 studs and the furthest thing in the world is 895 studs from the spawn.

## UI

None.

## Server and client

The server builds the playground once on start, in `Workspace`. The client builds nothing. Falling off and respawning is the server's.

## Contracts

- `PlaygroundService:GetSpot(name)` returns a named spot's CFrame; `DebugState()` lists the spots and the counts. `DebugWalk`, `DebugBounds` and `DebugObstacles` sit beside it, Studio only.
- Tag `DriftSurface` on every part the car may drive on, so the model's rays can filter to it. Buildings and pillars do not carry it.

## Analytics

None in the prototype.

## Monetization

None.

## Platform risks

None: untextured parts of our own.

## Art and sound

Placeholder: flat colours chosen for value contrast, not for looks (`Config.Playground.Palette`). No art is generated for this world, and none of it ships.

## Testing

- `DebugState()` returns every named spot and the counts; a playtest asserts each spot exists and sits on a `DriftSurface` within 5 studs.
- The plate is proved flat by a grid of rays over the open yard, and nothing drivable is allowed to share a footprint with a building or a pillar.
- The circle's and the ramp's segment counts are asserted, because the fidelity rule above is the one that quietly breaks the drift model, and both are ray-walked at 1-stud steps along the centre line and both edges.
- The elevated features are **looked at from the ground** as well as measured, for gaps, steps and missing chunks: the user asked for that in as many words, and a ray walk cannot see a wedge out of a rim.
- Part count stays under 1,500, and a playtest joins with no console warnings.

## As built

| Module | What it is |
|---|---|
| `ServerScriptService/Playground/Layout.luau` | Every position and size: the plate, the open yard, the district grid, the blocks and pillars, the circle, the ramp, the spots and the cone clusters. Nothing else holds a coordinate |
| `ServerScriptService/Playground/Path.luau` | The pure maths: walking a straight, an arc and a ring. Every node of a ring sits on the true circle, so consecutive nodes are its chords |
| `ServerScriptService/Playground/Build.luau` | Turns nodes into anchored, tagged parts, and boxes and cylinders into untagged walls. Neighbouring ribbon segments share their endpoints, so a ground ray reads a curve and never a joint |
| `ServerScriptService/Services/PlaygroundService.luau` | Builds the world at `Init` (`Priority` 100), hands out the spots, catches fallers, resets cones |
| `ReplicatedStorage/Shared/Config/Playground.luau` | The tuning that is not geometry: the fall height, the cone reset, the part budget, the placeholder palette |
| `ServerScriptService/Tests/PlaygroundTests.luau` | The asserted rules: spots on surfaces, segment counts, a flat plate, nothing floating, no drivable surface through a wall, street widths, the clear yard, the reach from spawn, everything anchored and constraint-free but the cones, the part budget, and the ray walks |

**The district, as a grid.** Three X strips (100, 104 and 92 studs deep) crossed with five Z strips (100, 56, 96, 96 and 84), making 15 buildings; the gaps between the strips are the streets, 56 and 76 along Z and 44, 110, 44 and 50 along X. Heights are a per-row base plus a per-column bump, so the skyline varies without a random number: 32 to 140 studs.

**Two things a banked box gets wrong.** A part can bank but it cannot twist, and two neighbours on a curve share their centre point while turning by the yaw step, so their *outer* corners pull apart by (half the width) times (that step): the wedge that reads from the ground as a bite out of the rim. Each box is lengthened by exactly that, which closes it; the inner corners then overlap, which a banked surface hides because neighbours are never coplanar. Separately, a raised edge on a thin ribbon shows daylight under it, so the circle and the ramp are solid 14-stud prisms and the plate is 24 thick: every underside is buried.

**Measured** (`DR-Lane2`, 2026-11-03, 44 checks passing): 229 parts, 64 cones, 15 buildings and 2 blocks, 8 pillars. The largest surface height change per stud travelled is 0.005 studs on the circle and 0.123 up the ramp, against a limit of 0.25, with no sample missing a tagged surface. The plate's top varies by 0 studs across 1,230 rays. `WORLD.md` "Scale" has the rest.

## Open questions

- Nothing to decide: it is a test rig, and it is replaced by the real map when the feel is agreed.
