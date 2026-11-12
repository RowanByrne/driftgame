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
4. **K-rails**, drawn as **metal crash barriers** (a W-beam steel guardrail on round posts, as on
   Japan's mountain roads), stand at the tarmac's edge in places, mostly on the outside of bends
   above a cliff. They stop you like a wall, before the grass. They were first drawn as concrete
   jersey barriers; on 2026-11-12 the user said "the K rails you made are not what I meant, my
   bad. These concrete barriers arn't what i was looking for - i meant the metal crash
   barriers", so T-149 redrew them. Only the look changed: where they go and how they stop the
   car did not. The code keeps the `KRail` names.
5. Everything else is the run as it is: the score, the closing barrier behind you, joining
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
| Runoff on the inside of a bend | Never past 60% of the way to the bend's centre | So the inside of a hairpin keeps a strip, not a spike |
| Runoff slope | Follows the road's bank, then eases flat | A banked road's grass doesn't lip up into a ramp |
| Rock face | Rises 25 to 60 studs at 50 to 70 degrees | Height is looks; to the car it is a wall |
| Hedge | 6 studs high, 4 thick | |
| Cliff | The ground ends; the face drops 80 studs into haze | Past the lip, nothing to stand on |
| K-rail (metal crash barrier) | 3 studs high, 2 thick, at the tarmac's edge | Runs of 60 to 300 studs. To the car a wall that size; drawn as a 1.2-stud W-beam, top at 3 studs, face on the tarmac's edge, round posts every 7 studs behind it inside the wall |

### Where each edge goes

A mountain road has the mountain on one side and the drop on the other, so the generator picks
**which side is uphill** and keeps it for a long stretch:

- **Uphill side:** rock face, sometimes hedge.
- **Downhill side:** cliff drop, sometimes hedge.
- The uphill side swaps now and then (the road crosses a ridge), never in a bend, through a
  stretch of hedge both sides.
- **K-rails:** on the outside of a bend whose outside is a cliff, about half the time, and the
  odd stretch elsewhere.
- **Seeded and replayed,** like the curve: the server chooses, the edges go to the clients with
  each section (`RoadSpline`), and the clients replay them. A client never chooses.

### Driving on it, from the maths

The road stays purely visual: the car still reads everything from the curve (`SplineWorld`).

| The model asks | Now answered |
|---|---|
| `probe`: the ground under a point | Tarmac or grass, by lateral offset, with its grip and score. Nothing past a cliff's lip, so the car falls there |
| `sweep`: how far the car may move | Stops at a rock face, a hedge or a K-rail, with the wall's normal. Nothing at the tarmac's edge any more |
| Surface | Grass uses dirt's numbers to start (`GripDirt` 0.5, `ScoreDirt` 0.5), as its own `GripGrass` / `ScoreGrass` so they can part later |

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
- **Crash barriers (T-149):** the beam is three boxes per piece (two ridges and the groove
  between), a piece up to 12 studs on a straight and cut finer round a bend; a round post every 7
  studs. Measured on seed 31337, 8 000 studs: 322 parts for 675 studs of rail (116 as K-rails),
  135 at most in one chunk (50 before). From the grass side the car stops at the wall's back
  face, about a stud behind the posts.
  A device that cannot make a mesh still draws the tarmac only.
- **Nothing drawn collides.** As now.

## UI

None. The TEST ONLY panel loses its guardrail button.

## Server and client

- **Server:** chooses the edges with the curve, sends them with the sections, places the car and
  the respawn as now.
- **Client:** replays the edges, draws them, and drives on them through `SplineWorld`.

## Contracts

- `RoadSpline`'s section data gains each side's runoff and edge knots, and the K-rail runs
  (`CONTRACTS.md`, in the same commit).
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
