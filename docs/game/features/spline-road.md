# Feature: The spline road

**Status:** specced, waiting for the user's OK (`T-131`). **Owner task:** none yet. Built in a lane
of its own, behind a switch, and merged only when the user has driven it there.

## Goal

The user: *"i want to try something big. do this on it's own lane. instead of chaining together
prefab road parts, generate the road as a single continuous spline, generate the road parts using
tri meshing, then use the spline equation for cars collision. the road is purely visual, the actual
physics msut be calculated off of the spline."*

Today the endless road is prefab pieces (straights, arcs, a chicane) joined socket to socket, built
by the server as about 1,300 parts, and the car finds the ground and the walls by casting rays at
those parts (`track-generation.md`, `road-elevation.md`). The road becomes **one continuous curve**.
What you see is a triangle mesh drawn along it. What you drive on is the curve's own maths.

## How it plays

The same endless run, the same button, the same score. The road no longer comes in set shapes. It
flows: corners of any radius, tightening and opening, with crests, dips and banking that change
smoothly rather than per piece. There are no seams, and the surface under the tyres is exactly
smooth, because it's an equation and not a row of slabs. Walls along both edges still stop you,
and switching the barriers off still lets you drive off the edge and fall.

## Left out

- **Removing the piece road.** It stays, behind `Config.Road.Mode`, until the user says the
  spline road replaces it. The track and the playground keep their parts either way.
- **New road art.** Same tarmac, centre line and barrier colours, drawn as meshes. No verges,
  scenery or lighting work.
- **Changing the drive.** The car's physics stays as approved. Only where it reads the ground and
  the walls from changes.
- **Junctions, forks or a closed circuit.** One line, forward, endless.
- **Dirt and other surfaces** on the road. Tarmac only, as now.

## Rules and numbers

### The curve

- **The generator lays control points, not pieces.** Each new point follows from the last by a
  heading change, a climb and a bank, drawn within limits: no bend tighter than `MinRadius`, the
  same `MaxGrade`, `MaxBank`, `MaxSurfaceTilt` and `MaxBankStep` the piece road obeys
  (`Config.Road`), and the same bias against repeating itself.
- **The road is a smooth spline through them** (a centripetal Catmull-Rom, or a cubic B-spline if
  the curvature limits need it). Position, heading, grade and bank are continuous all along it.
- **Seeded and deterministic,** as now. One seed is one road, on the server and on every client.
- **It can't cross itself.** The look-ahead search the piece road uses becomes a check of the
  curve's swept width against what's already laid, `LookAhead` points deep.
- **Progress is distance along the curve** (arc length), not piece number. The window, "forward
  on new road", the closing barrier and the respawn point all read it.

### Collision, from the curve

The car keeps its own **`s`**, how far along the curve it is, and finds the nearest point each step
with a couple of Newton iterations starting from last step's `s`. No search over the whole road.
From there, everything is arithmetic:

| The model asks (`Model.World`) | The spline world answers |
|---|---|
| `probe(pos)`: the ground under a point | Height and normal of the banked surface at that point's `s` and lateral offset. **Nothing** past the road's edge, so the car falls there |
| `sweep(from, to)`: how far the car may move | Stops the car's box at the barrier line, `Width / 2` either side of the centre, with the wall's normal |
| `penetration`, `edge` | The same distances, from the same `s` and offset |

- **Barriers off:** `sweep` stops nothing, and `probe` still ends at the edge.
- **Off the road,** in the track or playground, or in the garage, the part-based world answers as
  today. The two are combined, and the spline answers first wherever the car is within its reach.
- **Cost:** a handful of cubic evaluations a step, against today's raycasts. Measured in the lane
  and written into this spec.

### The mesh, purely visual

- **Built on each client, from the seed.** The server makes no road parts at all. Each client draws
  the curve as triangle strips with `EditableMesh` (road surface, centre line, both barriers), in
  chunks of `ChunkLength` studs, ahead and behind the car, the same window as now.
- **Nothing collides with it.** `CanCollide`, `CanQuery` and `CanTouch` are off on every mesh. The
  car never asks the mesh anything.
- **Detail follows curvature.** Tight bends get more cross-sections than straights, within a
  triangle budget per chunk.
- **Fallback:** if `EditableMesh` can't be created on a client (memory budget, or a device that
  refuses it), each triangle is drawn as two wedge parts, also never collided with.

### The server

The server owns the seed, generates the same curve, and checks the car's reported position against
it, as it checks against the pieces today (`CarService:BelievedPosition`). Joining a run, respawn
after a fall, and the closing barrier all work in arc length.

## UI

None new. The run button and the score panel are unchanged.

## Server and client

- **Server:** the seed, the curve, progress, respawn, the closing barrier. No road instances.
- **Client:** the same curve from the same seed; the collision world; the meshes.
- **The seed reaches clients** on the run's existing state (`RoadRun`), as an attribute the server
  sets; a client never chooses it.

## Contracts

- `Config.Road.Mode`: `"pieces"` (today) or `"spline"`. Default stays `"pieces"` until the user
  approves the swap.
- A `Shared/Road/Spline` module (pure, server and client): evaluate, nearest point, arc length.
- A road-seed attribute on the run, and arc-length progress in place of piece number in
  `RoadService`'s API, both recorded in `CONTRACTS.md` when built.

## Analytics

None.

## Monetization

None.

## Platform risks

None. Everything is generated in code. `EditableMesh` is a Roblox feature; its device limits are
the fallback's job.

## Art and sound

None new. The mesh uses today's road colours and materials.

## Testing

- **Unit tests** (`SplineTests`): the same seed gives the same curve on the server and on a client;
  position, heading, grade and bank are continuous (no jump between samples); no bend under
  `MinRadius`; every limit holds over 50 km of road on five seeds; it never crosses itself; the
  nearest point is within 0.01 studs of a brute-force search.
- **Collision against the old road:** the same drive on the spline world and on a part-built copy
  of the same curve gives the same ground height and wall stops, within a tolerance.
- **In the lane:** a 10-minute scripted run with barriers on and off. Measure frame time, the cost
  of a collision step, mesh triangles and memory, chunk build time, and that no road part ever
  exists on the server. Then the user drives it there.

## Open questions

- **The swap.** Whether the spline road replaces the piece road once it's driven, or both stay.
- **Shape mix.** How twisty the generator should be is tuning (`MinRadius`, the heading-change
  ranges). The first pass aims at today's road's mix of straights and corners.
