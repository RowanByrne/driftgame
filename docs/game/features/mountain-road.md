# Feature: The mountain road

**Status:** building (`T-140`, lane 1, branch `feature/mountain-road`). Step 1, grass, edges and K-rails to drive on (`T-141`), and step 2, drawing them (`T-142`), are built and waiting for the user's drive. **Owner task:** `T-140`.

## Goal

The user, 2026-11-12: *"endless spline mode is the direction we are taking the game. I want to pick
a scenery that we are going to use to get started, and that's going to be Japan. We will start with
classic japanese mountain roads ... we are not longer going to be in the endless sky void with no
edges on the track. time to ditch our barriers for good. on the edge of the road, we want to add
runoff, which can just be grass for now. at some point in the distance on the sides of the road,
that will terminate. for now the temrination can just be a hedge, a rocky face (mimicking uphill of
a mountain road) or a cliff drop. we will add K rail barriers in some places too."*

The endless spline road (`spline-road.md`) stops being a strip of tarmac between two walls in the
sky and becomes a road on a mountainside: grass either side, then a hedge, the mountain rising, or
the drop. Running wide is no longer stopped by a wall; it costs you grip, then the edge decides.

## How it plays

1. **START ENDLESS RUN** lays the spline road. It is now the run's only road (`Config.Road.Mode`
   defaults to `"spline"`).
2. **No side barriers.** Either side of the tarmac is a strip of **grass runoff**, a few car widths
   wide, widening and narrowing as the road goes. Grass holds about half as well as tarmac and
   scores about half, as dirt does today: a drift that runs wide onto it washes out.
3. **Past the grass, each side ends in one of three edges**, which change along the road:
   - **Rock face:** the mountain rising on the uphill side. A wall: you hit it and grind along it.
   - **Hedge:** a low green wall. A wall, as the rock face.
   - **Cliff drop:** the grass ends at an edge and the ground falls away. Go over and it is a fall,
     and the run puts you back on the road as it does today.
4. **K-rails**, drawn as **metal crash barriers** (a rounded W-beam steel guardrail held off square
   posts on spacer blocks, bolted at its splices, a yellow-and-black striped hazard panel at
   each end of a run), stand at the tarmac's edge in places, mostly on the outside of bends
   above a cliff. They stop you like a wall, before the grass. They were first drawn as concrete
   jersey barriers; on 2026-11-12 the user said "the K rails you made are not what I meant, my
   bad. These concrete barriers arn't what i was looking for - i meant the metal crash
   barriers", so T-149 redrew them. Only the look changed: where they go and how they stop the
   car did not. The code keeps the `KRail` names. The user then sent reference photos (T-155,
   2026-11-12): "model the metal barriers like these things please. with the begining and end
   having this type of hazard end piece thing on it", so the beam was rounded and the spacers,
   bolts and end panels added.
5. **Tight cliff edges** (T-181). The user, 2026-11-13: *"some cliff edges should be barrier
   rails that are right on the edge of the asphalt with less than 3 or 4 studs of gravel before
   the cliff."* Now and then, on a side with a cliff the whole way along a section, the runoff
   closes in to a strip of **gravel** 2.5 to 3.5 studs wide, a crash barrier stands on the
   tarmac's edge, and the lip is just past it; then it opens out to grass again. Gravel grips
   and scores as grass to start (`GripGravel`, `ScoreGravel`, their own numbers).
6. Everything else is the run as it is: the score, the closing barrier behind you, joining
   another player's road, respawn after a fall.

## Left out

- **The view past the edges:** the valley floor, distant mountains, trees, villages, lighting and
  time of day. The drop fades into a light haze for now. That is the next feature, with the
  setting's art direction and references.
- **Final art.** Programmer colours and very low poly shapes: green grass, a green box hedge,
  faceted grey rock, a grey cliff face, galvanized grey crash barriers (white is a one-line
  swap in `Config.Spline`'s `KRailColour`).
- **Road dressing:** kerbs, road signs, mirrors, painted edge lines, crash barriers anywhere but the K-rail runs.
- **A cost for a wall hit or a fall** in the score: still none (`endless-score.md`).
- **Obstacles, shortcuts, set pieces and changing stretches** (`T-137`, `T-138`): later, on top of
  this.
- **Road stacked over road** (a switchback seen below you): the no-crossing rule stays in plan.
- **Removing the piece road's code.** The spline road becomes the default; the piece road stays
  behind the switch until a cleanup task takes it out. The track and the playground are untouched.

## Rules and numbers

Starting values. All of them go in `Config.Spline` (a `Terrain` block) as numbers, not code.

### The cross-section

Each side of the centre line, at every `s`, is: tarmac (`Config.Road.Width / 2`, 25 studs), then
runoff, then an edge. Every width changes smoothly along the road (smoothstep knots, as the bank
does), so nothing steps.

| | Start | Notes |
|---|---|---|
| Runoff width | 12 to 40 studs, each side on its own | About 2 to 5 car widths |
| Tight cliff edge (T-181) | Gravel 2.5 to 3.5 studs wide for 80 to 270 studs, easing in and out at 0.4 stud per stud (`Tight*` in `Terrain`) | A K-rail over the narrow part and 12 studs (at most half the easing) past each end; the gravel covers the same stretch |
| Runoff on the inside of a bend | Never past 60% of the way to the bend's centre | So the inside of a hairpin keeps a strip, not a spike |
| Runoff slope | Follows the road's bank, then eases flat | A banked road's grass doesn't lip up into a ramp |
| Rock face | Rises 25 to 60 studs at 50 to 70 degrees | Height is looks; to the car it is a wall |
| Hedge | 6 studs high, 4 thick | |
| Cliff | The ground ends; the face drops 80 studs into haze | Past the lip, nothing to stand on |
| K-rail (metal crash barrier) | 3 studs high, 2 thick, at the tarmac's edge | Runs of 60 to 300 studs. To the car a wall that size; drawn as a 1.2-stud rounded W-beam, top at 3 studs, face on the tarmac's edge; square posts every 7 studs on spacer blocks behind it, inside the wall; a striped hazard panel at each end |

### Where each edge goes

A mountain road has the mountain on one side and the drop on the other, so the generator picks
**which side is uphill** and keeps it for a long stretch:

- **Uphill side:** rock face, sometimes hedge.
- **Downhill side:** cliff drop, sometimes hedge.
- The uphill side swaps now and then (the road crosses a ridge), never in a bend, through a
  stretch of hedge both sides.
- **K-rails:** on the outside of a bend whose outside is a cliff, about half the time, and the
  odd stretch elsewhere.
- **Tight cliff edges:** in a section with a cliff the whole way along one side, 30% of the
  time, if the section is long enough for the easing in, 80 studs narrow and the easing out.
  A K-rail chosen on that side gives way to the tight edge's own. The section carries it as
  its runoff knots, a K-rail run and a gravel run (`gv`).
- **Seeded and replayed,** like the curve: the server chooses, the edges go to the clients with
  each section (`RoadSpline`), and the clients replay them. A client never chooses.

### Driving on it, from the maths

The road stays purely visual: the car still reads everything from the curve (`SplineWorld`).

| The model asks | Now answered |
|---|---|
| `probe`: the ground under a point | Tarmac or grass, by lateral offset, with its grip and score. Nothing past a cliff's lip, so the car falls there |
| `sweep`: how far the car may move | Stops at a rock face, a hedge or a K-rail, with the wall's normal. Nothing at the tarmac's edge any more |
| Surface | Grass uses dirt's numbers to start (`GripDirt` 0.5, `ScoreDirt` 0.5), as its own `GripGrass` / `ScoreGrass` so they can part later. Gravel (T-181) the same, as `GripGravel` / `ScoreGravel` |

- **The side barriers go, for good,** and with them the guardrail switch (`setRails`, the TEST
  ONLY button). The closing barrier behind you stays.
- **No-crossing grows:** two stretches of road now keep their *edges* apart, not their barriers:
  the clearance covers the tarmac, both runoffs and the edges. This makes the road a little less
  twisty; the build measures by how much and says so.

### Drawing it

- **Still within eight meshes.** A client may hold only eight `EditableMesh`es and the road uses
  six (`spline-road.md` "The mesh"). So the runoff is drawn **in the same chunk mesh** as the
  tarmac, coloured by vertex, not as meshes of its own. The rock and cliff faces go in that mesh
  too if the triangle budget holds, else as cheap non-colliding parts; the build measures which.
- **Hedges and K-rails are plain parts,** one box per stretch of cross-section, pitched along the
  grade as the barriers were.
- **Measured (T-142):** the rock and cliff faces fit in the chunk mesh. A chunk is about 1 700
  triangles (940 before the faces), the window round the car about 8 600; a chunk builds in 7 ms
  on average, 13 at worst.
- **Crash barriers (T-149):** the beam is three parts per piece (two flattened cylinders for
  the rounded ridges, a box for the groove between), a piece up to 12 studs on a straight and cut
  finer round a bend; a square post and its spacer block every 7 studs; two bolt heads at every
  second post (a splice; `KRailSpliceBolts = 0` drops them); a hazard panel at each end, its
  stripes one `UIGradient` on a `SurfaceGui`, no image. Measured on seed 31337, 8 000 studs: 522
  parts for 675 studs of rail (116 as concrete K-rails, 322 as the first plain guardrail), 213 at
  most in one chunk (50, then 135); about 377 plain parts in the window round the car. From the
  grass side the car stops at the wall's back face, about 0.9 studs behind the posts.
  A device that cannot make a mesh still draws the tarmac only.
- **Tight cliff edges (T-181):** the gravel is the runoff's own strips in the chunk mesh, in
  `GravelColour`, so no mesh and no triangle more; its rail is the crash barrier as drawn
  anywhere else. Walking on it, the ground tiles are Pebble. Measured, 5 seeds of 20 000 studs:
  46 tight edges, **4.6 per 10 000 studs**, 7.6% of the road's length; gravel 2.55 to 3.50
  studs at its narrowest; a cliff past it and a rail on the tarmac's edge at every one of 3 828
  points sampled; a client's replay the same. Seed 31337, 8 000 studs: 31 538 triangles (31 400
  without), the window still 5 meshes, about 738 plain parts in it (423 without: 2 004 studs
  of rail where there were 540). The car driven square at a tight edge's rail at 50 studs/s
  stops with its nose at the rail's face, 2.9 studs short of the lip; driven at it glancing
  (30 degrees, 60 studs/s) it is held on the tarmac, on the ground.
- **Nothing drawn collides.** As now.

### Walking on the road

T-154. The user, 2026-11-12: *"when i get out of the car in endless mode, i want to be able to
stand on the ground, instead i fall through."* Nothing on the road is solid (the car stands on the
maths), so an avatar out of the car (`car-v2.md`) had nothing under it.

- **What it is:** while our own avatar is out of the car, `RoadGroundController` (client) keeps a
  patch of invisible, anchored, colliding tiles round it, built from this client's curve: the
  tarmac and the grass on the surface's own slope, a wall at a rock face (80 high, unclimbable), a
  hedge (12 high: the drawn hedge is 6, which a jump clears into nothing), a K-rail (the car's
  wall, 3 high: it can be jumped, onto the grass behind it) and the closing barrier. **Nothing
  past a cliff's lip** or past the end of the laid road: walking off falls, and the fall does
  what it always did (the server sits the avatar back in the car).
- **How:** tiles on a fixed lattice along the road, 4 studs a row, up to 6 wide, 6 rows each way
  of the avatar and 24 studs either side of it, so the tile underfoot never moves. Rebuilt only
  when the avatar crosses a row or a band, the closing barrier moves, or more road arrives.
  Footsteps sound right: tarmac tiles are Asphalt, grass Grass.
- **Only our own avatar:** each client simulates its own character, so each makes ground for its
  own; everyone else's avatar is seen standing where its own client keeps it.
- **The car never meets them:** they exist only while the car is held (not driving), when
  nothing asks the car's world anything, and they go the moment the server seats the avatar,
  checked every frame before the drift step. None is tagged `DriftSurface`.
- **Measured (DR-Lane3, seed of the day):** feet 0.002 studs above the curve's ground over 5 s
  standing; on the grass 0.000 to 0.01; stopped at a rock face 0.7 from its line, at a hedge
  0.6 (a jump does not clear it), at a K-rail 0.5 (a running jump does, onto grass at 0.000), at
  the closing barrier 0.6; walking off a cliff's lip, in freefall 2.5 studs past it (the root's middle, read every 0.1 s
  at walking pace, so most of that is the step between reads). About 70 to 145
  parts; a rebuild costs about 1.4 ms (1.9 at worst), about four times a second at a walk. Back
  in the car, 604 and 785 frames driving with no tile in the world, and the car drove on as
  before (grounded, ride error -0.02, no wall stops).

## UI

None. The TEST ONLY panel loses its guardrail button.

## Server and client

- **Server:** chooses the edges with the curve, sends them with the sections, places the car and
  the respawn as now.
- **Client:** replays the edges, draws them, and drives on them through `SplineWorld`.

## Contracts

- `RoadSpline`'s section data gains each side's runoff and edge knots, and the K-rail runs
  (`CONTRACTS.md`, in the same commit); since T-181, its gravel runs (`gv`) too.
- `setRails` and the guardrail message are removed.
- `Config.Road.Mode` defaults to `"spline"`.

## Analytics

None yet.

## Monetization

None.

## Platform risks

None. A Japanese mountain road is a setting, not a real place, brand or road: no real road layout,
signs or names are copied.

## Art and sound

Programmer art only, as "Left out" says. The setting's look (references, palette, lighting) is set
in `ART-DIRECTION.md` "World" with the next feature.

## Testing

- **Unit tests** (the spline tests, run from the DebugBridge): the cross-section at a point gives
  the right surface and edge on both sides; a cliff lip ends `probe`; a rock face, a hedge and a
  K-rail stop `sweep`; server and client replays give the same edges; no-crossing holds with the
  wider clearance over long seeded roads.
- **In the lane:** a scripted run with the car steered wide on purpose: it reaches the grass,
  slows, hits a rock face and grinds, goes off a cliff and is respawned. Count each. Frame time,
  meshes in use (at most eight), triangles per chunk, parts per chunk.
- **Then the user drives it there,** before it merges.

## Open questions

- None blocking. The numbers above are first guesses to drive and tune.
