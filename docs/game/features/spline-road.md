# Feature: The spline road

**Status:** in progress: steps 1 to 3 of 4 built (`T-133` the curve maths, `T-134` collision, `T-135` the mesh). **Owner task:** `T-132`,
branch `feature/spline-road`, lane 1. Built behind a switch, and merged only when the user has
driven it there.

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

**Built in step 1** (`T-133`): `Shared/Road/Spline` (the curve), `Shared/Road/SplineGen` (the
generator), every number in `Shared/Config/Spline.luau`. Width, barriers and colours stay
`Config.Road`'s.

**Not control points, and that is the one change from the plan.** A Catmull-Rom or B-spline
through control points has no arc length of its own, so "how far along am I" would need a table
and a search, and its curvature is whatever falls out between the points, so `MinRadius` could
only be checked, not kept. Instead the curve is described by **what it does along its own length**:
three tracks of knots `(s, value)`, where `s` is plan arc length from the road's start.

| Track | Between knots | So |
|---|---|---|
| Curvature (1/radius, + is left) | Straight line | Every bend eases in and out (a clothoid, as real roads are set out); the heading is its exact integral and has no kinks; `MinRadius` holds by construction |
| Grade (dy/ds) | Straight line | Height is a piecewise parabola: crests and dips with no creases |
| Bank (+ raises the right edge) | Smoothstep | The bank and its rate are both continuous, so the kerb never creases where a bank starts or stops (a straight-line bank put a 2.9-degree crease at the kerb, measured) |

- **`s` is the parameter itself,** so the car's own `s` is its progress, and the ground under a
  point is two or three Newton steps from last step's `s`: measured **3.3 microseconds** a query.
- **The surface** is ruled along plan cross-sections: the point `d` studs right of the centre line
  is `centre(s) + d x planRight(s) + (0, d x tan(bank), 0)`. That one formula is what the mesh is
  drawn from and what the car stands on.
- **The plan position** has no closed form for a clothoid, so it is integrated once (Simpson) and
  kept every 4 studs; a query between samples integrates the last few studs itself. Measured
  against an integration 16 times finer: 0.00006 studs out over 3 300 studs.
- **Single precision is the floor, not the maths.** The road starts 20 000 studs out, where a
  `Vector3` holds a position to about 0.002 studs. The maths is exact to 1e-11 in double precision;
  anything that checks it uses `surfaceXYZ`, not `surface`.

**The limits** sit inside the piece road's lids (`Config.Road`), at what the piece road actually
drives rather than its ceilings, and the tests check both:

| Limit | Value | The piece road's lid |
|---|---|---|
| Tightest bend | 70 studs, its hairpin | — |
| Easing | 1/(70 x 45) per stud: 45 studs from straight into a hairpin | — |
| Grade | 8 degrees, changing at most 0.0015 a stud | `MaxGrade` 20; `MaxPitchStep` 1.15 per 13-stud chord |
| Height | Within -160..+160 studs of the start; the grade turns back before an edge | — |
| Bank | 10 degrees (the touge decision, 2026-11-06), full at radius 160 or less, 30% of bends flat | `MaxBank` 30; `MaxBankStep` 1.5 per chord, matched exactly |
| Lean | Measured worst 15.4 degrees at the kerb, normal Y 0.964 | `MaxSurfaceTilt` 35; a wall below 0.7 |

**The generator lays sections, not pieces.** Each is a bend (one of four kinds, a radius, a
direction, a turn) or a straight, with its grade and bank, easing in from the curvature the road
already had. Hairpin 70-95 studs turning 120-195 degrees, tight, medium, and sweepers out to 900,
chosen with **the piece road's bias** against whatever was used recently. Hairpins wait until 1 500
studs in.

- **It can't cross itself.** Every point of a new section keeps **74 studs** (road, both barriers
  and a 20-stud gap) from every point of road that is not its neighbour along the curve, including
  road laid long ago. Neighbours are points under 94 studs apart along the road: on the tightest
  bend, those are already 74 apart in a straight line.
- **It can't trap itself** without the piece road's deep look-ahead: a section is accepted only if
  the road could straighten up after it and run 260 studs clear. If no random section passes in
  14 tries, that escape is laid, and it was checked when the section before was accepted.
- **A general direction.** The heading stays within 115 degrees of the start heading, so a hairpin
  can swing the road right round but it never spirals.
- **Seeded and deterministic, and the server chooses.** One seed is one road. But a client does
  not re-run the choices: it gets the server's sections (a few knots each) and replays them. A
  choice is a comparison, and a last-digit difference in `math.sin` between a phone and the
  server could tip one the other way and give that phone a different road. Replaying the sections
  gives the same road to 0 studs (measured), and the client still builds everything itself.
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

**Built in step 2** (`T-134`): `Drift/SplineWorld`, which `DriftController:UseSpline` switches the
car to. As planned, with three things learned building it:

- **The car's box tilts with the road,** as `Drift/World` tilts it (`T-073`): on a bank its top
  corner leans out past its wheels, so what meets the barrier is the box's shadow, not a flat
  footprint. Without it the spline stopped the car up to 0.2 studs later than the parts did on a
  10-degree bank. The footprint is six points, the corners and the middle of each long side,
  because on the inside of a hairpin the barrier bulges in toward the car's middle.
- **A lookup that does not converge is not an answer.** From a hint hundreds of studs out (a
  respawn, a teleport) Newton runs out of steps; it now says so, and the world searches the
  road's grid instead. Before that it put the ground 21 studs out.
- **The closing barrier** is a plane across the road at its `s` (`setClosing`), and it never
  switches off. The side barriers switch with the guardrail button (`setRails`).
- **Measured cost:** a whole model step (autopilot included) **86 microseconds on the maths
  against 495 on a parts copy** of the same road.

**A spline road to drive in Studio** until the run lays one (step 4): the TEST ONLY panel's
**SPLINE TEST ROAD** button (`SplineTestService`, Studio only). The server lays an 8 000-stud road
far out on +X, sends the client its sections, and puts the car on it; what you see is the same road
as parts nothing can touch (`Road/SplineParts`), standing in for step 3's mesh. A fall goes back on
to it. The button again takes you back.

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


**Built in step 3** (`T-135`): `Road/SplineMesh` draws a chunk, `Drift/SplineRoadView` keeps the
chunks round the car (`DriftController:UseSpline` makes one). Numbers in `Config.Spline.Mesh`.
What changed from the plan, and why:

- **Only the surface is a mesh.** A MeshPart made from an `EditableMesh` is drawn from it for as
  long as it exists: free the mesh data and the road vanished (seen in the lane). And a client may
  hold only **eight** EditableMeshes at once, whatever their size (measured: 8 empty, 8 of 2 000
  vertices, 8 of 20 000; the ninth comes back nil with "reaching memory budget limits"). So each
  chunk spends its one mesh on what only a mesh can draw, the surface that curves, banks and
  twists, and the barriers and the centre line are plain parts like the piece road's: an upright
  box per cross-section either side, **pitched along the grade** so its top runs on without
  steps, and a flat box per dash.
- **Chunks are 480 studs,** so the window (1 600 ahead, 300 behind) is five meshes, plus one being
  built: six of the eight.
- **Detail follows the surface, not just curvature:** a cross-section goes as far on as it can
  while the true surface halfway along stays within 0.05 studs of the straight line, at the centre
  and both kerbs; 12 studs on a straight, down to 1 where it needs. **Four strips across,** because
  where the bank rolls on a grade through a bend the surface twists and a full-width triangle
  cannot follow it.
- **No road parts on the server at all.** The test road's server-built stand-in is gone; each
  client draws its own.
- **Fallback:** a chunk this device cannot make a mesh for is drawn as non-solid parts
  (`Road/SplineParts`), and the view counts how often.
### The server

The server owns the seed, generates the same curve, and checks the car's reported position against
it, as it checks against the pieces today (`CarService:BelievedPosition`). Joining a run, respawn
after a fall, and the closing barrier all work in arc length.

## UI

None new. The run button and the score panel are unchanged.

## Server and client

- **Server:** the seed, the curve, progress, respawn, the closing barrier. No road instances.
- **Client:** the same curve from the same seed; the collision world; the meshes.
- **The road reaches clients as the server's sections** ("The curve" above), not as a seed:
  a few knots per section, on the run's state. A client never chooses anything. Step 4 builds it.

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

- **Unit tests** (`ServerScriptService/Tests/SplineTests.luau`, pure, 27 checks in under 3 s):
  `game.ServerStorage.DebugBridge:Invoke("DebugSplineTests", "run")`. Measured in step 1:

  | Check | Measured |
  |---|---|
  | Every limit, 5 seeds x 20 000 studs (100 km), off the knots and sampled every stud | Tightest radius 70.2; easing, grade rate and bank rate exactly at their limits; grade 8.00; bank 10.00; height -158.7..159.9; worst lean 15.4 degrees |
  | Continuous | 1 stud of road is 1 stud of plan to 8e-6; no heading change over a stud above the tightest bend's |
  | Never crosses itself, brute force over every pair of points 4 studs apart (62 million pairs) | Closest non-neighbouring road **88.7 studs**, against 74 required |
  | Never boxed in, 20 seeds x 30 000 studs | **0 stalls**, 0 escapes needed in 2 341 sections; mean 0.16 ms a section, worst 0.77 ms |
  | Bends of every radius | 70..900 studs: 260 hairpins, 432 tight, 539 medium, 411 sweepers, 679 straights |
  | Same seed, same road; a client's replay of the sections | Identical knots; the replay is the same road to **0** studs |
  | Nearest point | From a hint: to 5e-12 studs; with no hint: 0 of 3 000 missed; against a brute-force scan every 0.02 studs: within 0.006 (the scan's own step) |
  | Ground height and normal | Height to 1e-12 studs; normal within 0.04 degrees of finite differences; nothing found 400 studs off the road |
- **Collision against the old road** (`ServerScriptService/Tests/SplineWorldTests.luau`, 14
  checks, about 3 s; it lays 2 600 studs of the road as 7 800 parts and takes them away again).
  The yardstick is the game's own collision: `World.live`'s rays and sweeps on a parts copy of the
  same curve, cut every 2 studs the way the piece road cuts its triangles. Measured in step 2:

  | Check | Measured |
  |---|---|
  | Ground height, 3 000 points across the road | **0.06 studs** worst (the parts' own triangles; the piece road allows itself 0.3) |
  | Ground normal | Mean **0.63 degrees**; worst 6.5 where the bank rolls on a grade through a bend and the surface twists, which a full-width triangle cannot follow |
  | A 4-stud step into a barrier, 300 of them at 10..80 degrees | Stops within **0.13 studs** across the wall; 2 grazes the parts' sweep missed and its own overlap then caught; 0 disagreements |
  | Barrier normal | Within 2 degrees (the parts are chords) |
  | A car 0.2..0.9 studs inside a barrier, 183 of them | Pushed out as far to **0.06 studs** |
  | The autopilot down 2 450 studs on each | Maths: all of it in 33.6 s, 0 steps off the road, 0 airborne. Parts: all of it in 32.9 s, 0 off, 0 airborne. The first 2.5 s are the same drive to 0.000 studs |
  | Barriers off | The car leaves the road and falls (177 studs off, 136 below after 3 s); on, the barrier holds it |
  | Closing barrier | A car driven back at it stops with its middle 7.6 studs in front (half the car is 7) |
- **The mesh** (`ServerScriptService/Tests/SplineMeshTests.luau`, 9 checks): the whole 8 210-stud
  test road as 18 chunks, 9 728 triangles and 2 775 barrier and dash parts; a chunk builds in
  3.0 ms on average, 5.5 at worst; every one of 6 166 road vertices, read back through its part,
  is within **0.0003 studs** of the surface the car stands on; between cross-sections the drawn
  surface is within 0.049 of the true one; neighbouring chunks share their edge to 0.002 studs;
  barrier tops step by 0.03 at most; nothing drawn is solid; a device that cannot make a mesh
  says so.
- **The mesh in a playtest** (`DR-Lane1`): 4 chunks drawn as meshes on arriving, 0 fallbacks, 4
  EditableMeshes still free; teleported 3 000 studs on, 5 old chunks taken down and 5 built, 3
  free; with the fallback forced, 5 chunks drawn as 3 605 parts and the car still 0.003 studs off
  the surface. Looked at once: a smooth curved road with its dashes and barriers.
- **In a playtest** (`DR-Lane1`, the test road): the car lands on the curve with its ride height
  0.005 studs off; every ground probe is answered by the maths (14 696 of 14 696); hands-off it
  grinds along a barrier and never leaves the road; guardrails off, it went off the edge, fell,
  asked for a respawn and was put back on the centre line further along; leaving puts it back in
  the playground and removes the road. No errors in the console.
- **In the lane:** a 10-minute scripted run with barriers on and off. Measure frame time, the cost
  of a collision step, mesh triangles and memory, chunk build time, and that no road part ever
  exists on the server. Then the user drives it there.

## Open questions

- **The swap.** Whether the spline road replaces the piece road once it's driven, or both stay.
- **Shape mix.** How twisty the generator should be is tuning (`MinRadius`, the heading-change
  ranges). The first pass aims at today's road's mix of straights and corners.
