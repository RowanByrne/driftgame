# Feature: One continuous mountain

**Status:** building (`T-190`, lane 5, branch `feature/continuous-mountain`). The user approved the plan on 2026-11-13. Step 1, the mountain as one surface (`T-194`), is built and waiting for the user's drive; see "As built" at the end, which says where it differs from the first guesses below. Step 2, the turn checks, is not started. **Owner task:** `T-190`.

## Goal

The user, 2026-11-13: *"we need to sell the idea that we are actually on a endless mountain road here -
that means we can't be constantly looking at the inside of cliffs ... right now i can go into a
switchback and be staring at a mountain lol."* Their idea: let the runoff (grass, trees and the like) get much wider at times, not the drivable road,
and have the generator "send out horizontal checks" before sharp turns so the upcoming road doesn't
make unnatural geometry. They asked for a sanity check and better methods.

## What's wrong today

The scenery is a **ribbon that follows the road**: each section draws its own rock face on one side
and its own drop on the other, a fixed distance out. Nothing exists between two legs of road. So:

- Between a leg and the one below it is haze, with each leg's rock and cliff floating as separate
  slabs (the user's screenshots 2 and 3: "mountain" on one leg, "cliff" on the other, nothing
  joining them).
- At a hairpin the ribbon's rock face swings round with the road, so you drive straight at a wall
  that a real mountain wouldn't have there (screenshot 1).

## The recommendation

The user's two ideas help, but neither fixes the cause. The fix is to make the mountain **one
surface in the world** and cut the road into it:

1. **One mountain surface.** The ground is a single height function of world position: falling
   steadily along the fall line (`mountain-direction.md`), with broad, seeded ridges and gullies
   across it. The road is cut into it: where the surface is above the road you get a rock face (a
   cutting), where it is below you get a drop or an embankment. Because every leg is cut into the
   same surface, the ground between a leg and the one below is real mountainside, and a hairpin's
   outside opens onto the slope and the valley instead of a wall.
2. **Fit the turns to the mountain (the user's "horizontal checks").** Before laying a hairpin or
   switchback, the generator samples the surface sideways across the turn and ahead, and only takes
   a turn that keeps the cutting and the drop within limits: a hairpin goes where the slope can hold
   it, and a turn that would aim the road into the hillside is refused or eased. This is where the
   user's idea fits, and it's cheap: a few dozen height samples per candidate turn.
3. **Wider runoff** (the user's first idea) comes from step 1: with the ground continuous, grass and trees can run as wide as the slope allows. The user, 2026-11-13: "i didn't mean actually wider drive-able roads, i meant the sections of runoff (grass, trees, etc.) would all be wider - and you are already saying that with point 1 so it's probs not needed!" So there is no separate step, and the drivable road keeps its width.

## How it plays

You drive the same road, with the same feel. Looking out from a switchback, you see the leg below
you lying on the same hillside, the slope running down between them, and the valley beyond.
Cuttings rise where the road digs into the hill, and drops fall where it hangs out over it. You
rarely drive into a wall at a hairpin.

## Left out

- Hedges (they come back later as decoration only), new art, trees placed on the open slope
  (follow-up), the far horizon.
- Any change to the car, the drift or the score.

## Rules and numbers

First guesses, all in `Config.Spline` (a `Mountain` block):

| | Start | Notes |
|---|---|---|
| Slope across the fall line | 25 to 35° average | Steep enough for cuttings and drops, gentle enough for legs to share it |
| Ridges and gullies | 300 to 900 studs across, ±40 studs | Seeded noise; gives cuttings and embankments their variety |
| Drawn out to | 400 studs either side of the road | Far enough to meet the next leg; past it the horizon takes over |
| Cutting height | capped by the turn check | So a hairpin never sits in a 200-stud trench |

- **Seeded and replayed:** the surface is a pure function of the seed and world position, so every
  device computes the same mountain; nothing extra goes over the wire.
- **The car still drives on the maths:** walls are where the cutting is; the drop is where the
  ground falls past the lip.
- **Budget:** still within eight meshes. The wider ground costs triangles; the build measures it and
  coarsens far ground first.

## Server and client

- **Server:** lays the road on the surface, runs the turn checks.
- **Client:** draws the surface around the road from the same function.

## Contracts

The section data may lose fields it no longer needs (the per-section edge kinds become derived from
the surface); the build says what changes in `CONTRACTS.md`.

## Testing

- Unit tests: the surface is identical on server and client; no point of a leg's drawn ground pokes
  through another leg; turn checks refuse turns into the hillside; no-crossing holds.
- Measured: how often you face a wall within 150 studs ahead at a hairpin (before/after), triangles
  and build time per chunk, frame time.
- The user drives it in a lane before it merges.

## Open questions

- None blocking.

## As built (step 1, T-194)

The ground between the legs. `Road/SplineHill` is the maths, `Road/SplineMesh` draws it in each
chunk's own mesh, numbers in `Config.Spline.Hill`. A look only: to the car a rock face is still a
wall and a cliff's lip still a fall.

### What it is

- **Past every face the ground carries on:** up from a rock body's crest, down from a cliff's foot,
  on rays out from each cross-section of the road. A rock body has no back slope any more and a
  cliff's foot stands on ground, not in haze.
- **Each piece of ground belongs to the stretch of road whose edge is nearest.** A ray runs out
  until another stretch is as near: the middle of the gap between two legs, or the centre of a bend
  on its inside. So no two stretches draw the same ground, and where they meet is a gully or a
  ridge line. With nothing in the way a ray runs `Reach` (500 studs) past the road's edge.
- **Where two stretches meet they agree on the height:** what every station of road round that
  point thinks the ground there is, the nearest counting most. It depends on the place alone, so
  both sides compute the same number.
- **Faces fit the room there is.** A rock face under another leg's drop share the height there
  really is between the two roads, less a gentle slope across the gap; further apart than 300
  studs they are capped less and less. Near a hairpin, where two legs are a few studs apart in
  height, both come down to a low bank (4 studs of rock, a 6-stud drop: never nothing, since the
  car's wall and fall are still there). Also: no taller than 1.5 times the ground a face has to
  stand in (the inside of a bend), and both down to nothing at the point the mountain changes
  sides in a turn, so the rock on one side ends level where the drop begins.
- **A face is as tall as its side faces squarely up or down the mountain.** Full across the slope,
  none where the road points straight down it. So round the outside of a hairpin the rock comes
  down steadily, and where the road points down the mountain the view ahead is open.
- **Broad ridges and gullies:** noise 420 studs across, 26 studs either way, eased in past each
  face.
- **Steep ground is drawn as rock,** the rest in a few greens.
- **A chunk is redrawn when new road comes beside it** (`Drift/SplineRoadView`): the leg below a
  chunk is often laid after the chunk is drawn. Only once the chunk is within 800 studs of the
  car, so it is not redrawn for every stretch of that leg.

### Where it differs from the first guesses

- **The slope is about 11 degrees, not 25 to 35.** The road only drops 1 stud in 25, so two legs a
  few hundred studs apart are a few tens of studs apart in height. A steeper hillside from the leg
  above would miss the leg below. The steepness is in the rock faces and drops beside the road.
- **A grand rock face and a grand drop do not both fit between two legs,** so far apart (mid-leg)
  the ground between them is a ridge by the lower leg and a ravine under the upper one, and near a
  turnaround both faces are small. This is the one place this feature and "Grand cliffs"
  (`mountain-road.md`, T-185) pull against each other; `RelaxFrom` and `RelaxRate` set where the
  line is.
- **Two legs more than about 1 100 studs apart do not meet.** Each has the ground it would have
  alone, ending at a rim (a drop's falls away 60 studs at its rim). As they close in, each eases
  toward the meeting height over the last 150 studs of its reach, and there the two sheets of
  ground pass one over the other.
- **Trees on the open slope, and the car driving on it,** are not built.

### A climb is the far side of a valley

The road keeps zig-zagging the same way in plan while it climbs (`mountain-direction.md`
"Climbs"), so on a climb each new leg is higher than the one before: the mountain is on the other
side of the road. Before this the rock stayed on the compass's uphill side through a climb, about
a third of the road, with every later leg standing above the drop of the leg before it.

- The climb, and the descent after it, now begin where the road next points straight along the
  fall line inside a turnaround (a hairpin, a switchback or a double hairpin; never a sideways
  stretch). From there the rock and the drop are on the other sides (`SplineGen.flip`), and
  through that one turn they keep their sides: the valley's floor, and at the top the pass.
- The height band waits at `DescentFloor` or `ClimbTop` for that turn, and the stretches planned
  before it are cut to 250 studs so it comes soon, but no sooner than the faces already drawn
  were told a turnaround would come (`FlipClear`).
- Nothing new goes over the wire: the sections already carry each side's edge. The client now
  keeps the fall line it was always sent (`spline.fall`), for the slope.

### Measured (DR-Lane5)

Three seeds of 12 000 studs (`SplineHillTests`), unless said.

- **Seams:** of 976 places two stretches' ground meets, the two sides are 5.5 studs apart at
  worst, 1 more than 4. 410 more rays end in the last 150 studs of their reach, easing apart.
- **No ground on a road:** of 12 000 hillside vertices, none over any road's tarmac or grass.
- **Rock under the leg above:** of 42 rock faces under another leg's drop within 150 studs, none
  stands above that leg's edge by more than the 4 studs it always keeps.
- **A client's replay** draws the same hillside: 0 of 600 rays differ.
- **The view ahead in a turnaround** (ground more than 15 studs over the driver's eye within 150
  studs straight ahead, off the road): on the way down the mountain, 0 of 5 turnarounds at any of
  three points (as it begins, 45 degrees off the fall line, pointing down the mountain). Climbing
  the far side of a valley, 6 of 7 once the road is 45 degrees round: there the mountain being
  climbed is ahead, as on any climbing hairpin. Where the mountain changes sides, 3 of 5 pointing
  down it (the valley's far side). With every face at full height through the turn the counts are
  the same but for that last group (3 of 5 at 45 degrees, now 1): the taper lowers what is ahead
  (63 studs to 60 at the tallest), it does not change which turnarounds face the hill.
- **The road:** 64 of 64 spline checks. Over 20 roads of 10 000 studs, 3.9 legs and 3.5
  turnarounds per 10 000 studs, no turn refused, the mountain changes sides 3.6 times per 10 000
  studs and only inside a turnaround; 41 climbs, 34% of the road. One road of 150 000 studs:
  lowest point Y -413 (kill height -500).
- **Drawing cost** (seed 31337, 8 000 studs): a chunk is about 3 900 triangles (3 200 without the
  hillside) and builds in 22 ms of work, 29 at worst (16 without), a few ms a frame: 4.9 ms the
  most any one frame paid. A road vertex read back from the mesh is now up to 0.022 studs off the curve (the
  check's bound was 0.01): the mesh is much bigger with the hillside in it, and the error has
  grown with its size (0.015 when a chunk's mesh was 973 studs across), as if a mesh kept its
  vertices to a 65 536th of its size.
- **Driving a run** at 100 studs a second for 5 200 studs, teleported along the curve, the road
  arriving as it does in play: frames 8.3 ms mean, 10.2 p99, 13.5 worst, none over 20 in 6 647;
  5 meshes alive; 16 chunks drawn, 10 redrawn for new road beside them.
- Mesh 17 of 17, horizon 25 of 25, groves 11 of 11. `SplineWorldTests` 19 of 21: the same two
  normal checks that fail on `main`.

### Known

- **The car still meets a wall where the rock is only a low bank, and still falls at a drop that
  now has ground a few studs below it.** Its world is unchanged (`Drift/SplineWorld`).
- On a climb, and at a valley's floor, a hairpin turns toward the mountain, so ground rises ahead
  part way round. Step 2's turn checks are where that is weighed.
