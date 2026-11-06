# Feature: The test hill, the lift and the guardrail switch

**Status:** **built** (`T-065` and `T-067`). **Owner task:** `T-065`, branch `agent/test-hill`.

Three things that exist for one reason: **let the user feel a hill.** The road descends now
(`features/road-elevation.md`) and nobody could judge it, because the only way on to a graded road
was the endless run, where there is no horizon, no landmark and no second run of the same road.

> *"hard to judge because i can't really test this as the endless run makes it hard to tell what's
> up and what's down. add short (maybe 10 track pieces long, and with good variety) permanent
> sections of track to the playground... it should start with just going up up up up for 10 or so
> pieces, then down down down down for 10 pieces until you are back on the baseplate. add a button
> to teleport to the top of the track so I can easily test driving down."*
>
> *"i can't drive off the side because of barriers. can u add a button to instantly remove the
> guardrails that just turns them off and on?"*

## Goal

A permanent, repeatable, **real** piece of graded road the user can drive up and down whenever they
like, a button that puts them at the top of it, and a button that takes the walls away so they can
leave it on purpose. None of it ships.

## How it plays

1. Drive south-east across the playground to the **`HillBase`** marker, at the plate's southern
   edge. A short ramp lifts off the plate and the road begins.
2. **Ten pieces climb**, all of them at 7 degrees, 259 studs up over 2 070 studs of road: a
   straight, two hairpins, two chicanes, a sweeper, a 90-degree corner and three links.
3. At the top the floor leaves: a **corkscrew** hands the road 5 degrees of descent, and **ten
   pieces come down** — corners, sweepers, a hairpin, a second corkscrew, a hairpin stack that
   drops 40 studs in one piece, and a banked corner that arrives **level with the plate**, so the
   car drives off the end of the road on to the ground.
4. Press **LIFT TO HILL TOP** and the server puts the car back at the crest, on the first
   descending piece. Drive it again.
5. Press **GUARDRAILS: ON** and the walls stand down. Drive off the side; the hill has ground of
   its own under it, so a car that goes over the edge lands rather than falling out of the world —
   unless it goes over near the top, where it is 259 studs up and the client's own fall test
   (`Config.Drift.FallBelowSurface`, 150 studs) puts it back at the playground spawn first.

## Left out

- **It is not a course.** No start, no finish, no timing, no score — the same decision
  `track-generation.md` makes about the road itself.
- **It is not in the endless run.** `RoadService` knows nothing about it; the hill is built by
  `PlaygroundService` out of the same two modules a run uses.
- **It does not ship.** The HUD says so in words. There is no art and no sound.
- **It climbs at one grade.** 7 degrees everywhere, because `Link` is the only piece in the set
  that climbs and that is the number it hands on. A hill at several grades needs a piece set
  change, which is `Config/Road.luau`'s and not this task's.

## Rules and numbers

### The hill

Twenty pieces of the real road set, in `Playground/Layout.luau` (`Layout.Hill`), placed by
`Shared/Road/Pieces` and built by `Shared/Road/Builder` exactly as a run builds them.

**The climb is at 7 degrees and the descent at 5, and that asymmetry is the piece set's.** `Link`
is the only piece that climbs, and it hands on +7; `Corkscrew` is the only one that sets a descent,
and it hands on -5. Everything else **carries** the grade it arrived at (`Config.Road.Pieces`, "the
road's height is a state machine"). So ten pieces up gain more than ten pieces down lose unless the
descent is built of longer pieces — and it is: the climb leans on hairpins and chicanes (196 to 220
studs) and the descent on corners and sweepers (314 to 346).

| # | Piece | Grade | Top at its end |
|---|---|---|---|
| 1 | `Link` | +3.5 deg | 14.7 |
| 2 | `Straight` | +7.0 | 41.8 |
| 3 | `HairpinR` | +7.0 | 68.8 |
| 4 | `ChicaneR` | +7.0 | 92.8 |
| 5 | `HairpinL` | +7.0 | 119.8 |
| 6 | `ChicaneR` | +7.0 | 143.8 |
| 7 | `Link` | +7.0 | 161.0 |
| 8 | `SweeperR` | +7.0 | 199.5 |
| 9 | `Link` | +7.0 | 216.7 |
| 10 | `CornerL` | +7.0 | **259.1 — the top** |
| 11 | `CorkscrewL` | -4.9 (8.8 at its steepest) | 239.2 |
| 12 | `CornerL` | -5.0 | 208.9 |
| 13 | `HairpinStackR` | -5.2 | 168.9 |
| 14 | `CorkscrewR` | -4.9 | 148.9 |
| 15 | `CornerL` | -5.0 | 118.7 |
| 16 | `SweeperR` | -5.0 | 91.2 |
| 17 | `HairpinL` | -5.0 | 72.0 |
| 18 | `SweeperR` | -5.0 | 44.5 |
| 19 | `CornerR` | -5.0 | 14.3 |
| 20 | `Banked30R` | -3.8 | **0.25 — the plate's own kerb height** |

All nine piece kinds appear; six of them in the climb. 5 136 studs of road, **4 843 parts**, no two
pieces overlapping. (It was 2 723 before `Config.Road.TriangulateSegments` landed on main — the
same change took the worst step at the kerb from 0.336 studs per stud to 0.169, which is how the
hill's kerbs came to be held to the same limit as its centre line.)

**Which end is pinned, and why that way round.** The **exit** is, exactly: `PlaygroundService`
places the whole hill once at zero simply to read what it comes to (-5.90 studs), then places it
again at the height that lands the last piece on `Layout.Surface.height`. So the entry floats to
wherever it must be — 6.15 studs today — and a short ramp carries the plate up to it. A ramp at the
entry is taken at 20 studs/s; a ramp at the exit would be taken at 150. **Change a piece in the
list and the hill still meets the ground**, which is the point of doing it this way rather than
writing a start height down.

### Where it is

Off the **southern** edge of the playground's plate, pushed as far towards **+X** as it safely
goes, which is the side a hand-placed track is on (`Config.Drift.PlaygroundOffsetFromTrack` is
-2024 on X). It cannot literally be beside the kart track: that track exists only in `DR-Main` and
git never sees it, so no lane has one.

**It has a plate of its own.** 5 136 studs of road does not fit on a 2 000-stud square that already
has a district, a bowl and a ramp on it, and a hill with nothing under it is a hill you cannot fall
off safely. `HillPad` is sized at build time to the hill's own footprint plus 180 studs, and
overlaps the playground's plate at its northern edge so there is no seam to drop through.

**The eastern limit is `CarService:WorldAt`, not the geometry.** That decides which world a
position is in by which world's spawn is nearer, and the line between the playground's spawn and a
track's falls at about x = +1 010 in layout coordinates — the plate's own eastern edge, which is
where the two worlds meet. A hill that crossed it would have a car falling off its eastern side
respawn on the kart track. At `Layout.Hill.x = 190` the pad reaches x = 957, about 50 studs clear
at its worst corner, and `PlaygroundTests` asserts it.

### The two buttons

| | Lift | Guardrails |
|---|---|---|
| Sends | the string `"lift"` | the string `"rails"` |
| Server does | `CarService:Place(player, PlaygroundService:HillTopCFrame())` | flips every barrier's `CanQuery` and `CanCollide`, on the hill **and** on the endless road |
| Never sends | a position, a piece, a height, a boolean, or anything else at all | " |
| Asks a second per UserId | `Config.Drift.CarSwitchRateLimit` = 5 | " |
| Seconds between two that land | `Config.Drift.RespawnCooldown` = 0.5 | " |

The two guards are borrowed rather than chosen, for exactly the reason `endless-run.md` borrows
them: a press is a car being put somewhere, so a respawn's cooldown is the right shape for it, and
neither wants a number of its own until something asks for one.

**`CanQuery` is the one that matters, not `CanCollide`.** The car is kinematic — Roblox physics
never moves it — and what stops it at a wall is a `Blockcast` through `RaycastParams`
(`Drift/World`), which obeys `CanQuery`. Both are set, so a player's character cannot walk through
a standing wall either. The walls are left visible at `Transparency = 0.85` so "the rails are off"
reads differently from "this piece has no rails".

**It touches the walls and nothing else.** `Road/Builder` hands back the slabs and the barriers in
two separate lists; the slabs are what the ground rays find (tagged `DriftSurface`) and the
barriers are deliberately untagged, which is what makes a barrier a wall and not a kerb. Touching a
slab would take the road out from under the car. `PlaygroundTests` and `RoadService` both count
slabs before and after.

**The road's closing barrier is not a guardrail** and is deliberately left alone: it is the wall
that stops a driver reversing into road that is about to be destroyed, not a fence along the edge.

## UI

One screen, `Drift/TestHud`, in `UI-INVENTORY.md`. A `ScreenGui` named `DriftTest` holding two
`TextButton`s (`LiftToTop`, `Guardrails`) and one `TextLabel` (`TestOnly`), bottom left.

**Two things about it are load-bearing rather than cosmetic,** and both cost this game real time
before:

- **`ZIndexBehavior = Sibling`.** `Instance.new("ScreenGui")` still defaults to the legacy `Global`
  behaviour, in which a child does not draw above its parent.
- **`DisplayOrder = 16`,** above the drag pad's 5 and below the tuner's 20. The whole screen is a
  steering pad — a finger's horizontal distance IS the car's rate of turn — so without this a thumb
  on a button would also be a thumb hauling the car round.

It is a LocalScript and not a controller, for the same reason `Drift/RoadHud` is: the client loader
only loads `Controllers/`, and this talks to one remote and nothing else.

## Server and client

**The client may say one of three things and nothing on the wire is read as anything else:**
`"lift"`, `"rails"`, or nil for "what is the state?". It may not send a position, a piece, a height
or a boolean. Where the top of the hill is, is the server's own number, read off the pieces
`PlaygroundService` placed; a client that could name where to put its car would be a client with a
teleport. This is the same line `endless-run.md` "Server and client" draws, for the same reason.

**The server moves the car**, through `CarService:Place`, which is the path that already exists for
the run's start button. **The lift is refused while the player is in a run**: the roster would
still have them on the road and the window would follow a car that had left it.

## Contracts

In `CONTRACTS.md`:

- `TestTools`, a new both-ways RemoteEvent, with its validation and both its guards.
- `PlaygroundService:HasHill`, `HillTopCFrame`, `SetBarriers`, `BarriersOn`, `ToolState`, and the
  Studio-only `DebugHill`, `DebugHillBounds`, `DebugBarrierReport`, `DebugTool`,
  `DebugClearToolLimits`.
- `RoadService:SetBarriers`, `BarriersOn`, and the Studio-only `DebugBarrierReport`.
- Two new named spots, `HillBase` and `HillTop`.
- `PlayerScripts.TestHudBridge`, the Studio-only bridge for a LocalScript the loader cannot see.

## Analytics

None. It is a testing feature and it does not ship.

## Monetization

None.

## Platform risks

None beyond what `drift-model.md` already records: the car is still the AE86 placeholder, which is
**not approved to publish**. This HUD must not ship either, which is why it is labelled.

## Art and sound

Programmer art and nothing else: one magenta nothing else in the game uses, a rounded rectangle and
native text. The hill is the road's own programmer art — grey asphalt, grey walls, a white centre
line — on a plate a shade darker than the playground's so the join between the two is visible.

## Testing

### Driven, both ways

The number the user actually wants: **the car gets up it.** Driven by the test autopilot — a copy
of `RoadTests`', with its numbers — on the real model against the real Workspace, in `DR-Lane1`.

| | Climb (pieces 1-10) | Descent (pieces 11-20) |
|---|---|---|
| Entered | on piece 1 at 90 studs/s | at the lift's own CFrame, **standing start** |
| Got to | **all ten, and on into the descent** (piece 13 in 55 s) | **all ten**, and off the end on to the pad at Y 2.39 |
| Speed | **3.1 to 105.1 studs/s, mean 58.8** | **2.4 to 101.1, mean 53.7** (pieces 11-19) |
| Steps off the road | **0** | **0** |
| Airborne | 0 | 0 |

For comparison, `Config/Road.luau`'s own table: the autopilot's mean on a **flat** generated road
is 59 studs/s, and on a road of 8-degree descents it falls to 36. This hill reads 58.8 up and 53.7
down, so neither half costs the car anything like the 8-degree row does — which is what choosing
7 and 5 was for.

**It also makes it up from a standing start on the plate**: 250 studs of flat run-up before the
approach ramp, reaching 100 studs/s at the ramp and piece 13 in 55 seconds.

**Where it is hard, and it is one place:** piece 5, the second climbing hairpin. 70 studs of radius
and 180 degrees of it, on a 7-degree climb, took the autopilot down to **3.1 studs/s** — it very
nearly stopped — and it was drifting 60% of the piece. It got through every time. A hairpin on a
climb is the slowest thing in the set and that is the piece to watch if the climb ever wants
re-tuning.

**Per piece, on the climb** (speed min..max, mean studs/s):

```
 1 Link           90.0.. 96.3  93.5     6 ChicaneR      37.7.. 65.7  51.7
 2 Straight       66.8.. 97.7  78.9     7 Link          65.8.. 76.6  70.7
 3 HairpinR       22.3.. 67.4  39.5     8 SweeperR      76.6.. 94.9  84.9
 4 ChicaneR       31.2.. 62.7  48.4     9 Link          94.9..102.8  98.9
 5 HairpinL        3.1.. 62.6  31.0    10 CornerL       70.2..105.1  86.5
```

**And on the descent:**

```
11 CorkscrewL      2.4.. 81.2  37.6    16 SweeperR      46.2.. 81.0  66.8
12 CornerL        66.0.. 93.1  77.0    17 HairpinL      23.9.. 67.4  46.3
13 HairpinStackR   3.5.. 68.0  34.7    18 SweeperR      45.6..100.7  76.4
14 CorkscrewR     35.5.. 84.4  62.8    19 CornerR       64.6..101.1  88.9
15 CornerL        16.1.. 83.6  50.0    20 Banked30R      ..  97.5  -- and off the end
```

**A standing start at the crest takes about 2.4 seconds to roll away**, because the crest is still
pointing up at 7 degrees — that is what a crest is. After that the corkscrew's floor leaves and the
car is at 81 studs/s within the piece.

### By hand, in a playtest

Measured in `DR-Lane1`, with a **real mouse click** on each button:

- **LIFT:** the car went from (115, 2.40, -76) in the playground to the crest, and `steer` stayed
  **0** with the drag pad's pointer `nil` through the press. Lifted again with the rails down and
  again with them up: both times the car sat at (685, 261.77, -2224) — the lift's own CFrame —
  `grounded` true, **all four wheels down**, `surfaceGrip` **1.00**.
- **GUARDRAILS:** the button went `GUARDRAILS: ON` -> `OFF`, the server put all **1 652** hill
  walls to `CanQuery = false` and `CanCollide = false`, and all **826 slabs** stayed queryable,
  solid and tagged. Pressed again: 1 652 of 1 652 walls back. `steer` **0** through both presses.
- **Neither button steers:** at each button's own pixels the topmost Active GuiObject is
  `DriftTest.LiftToTop` / `DriftTest.Guardrails`, with `DriftControls.DragArea` beneath it.
- **Ten forged requests down the real remote from a real client** — a CFrame, a Vector3, both
  booleans, a number, `"LIFT"`, a table naming a world and a place, a list, an Instance and a NaN —
  moved the car **0 studs** beyond the 43 it was already rolling, raised no error, and were all
  refused and counted (20 refusals, 3 lifts, 2 rail switches over the whole session).

### The suites

All of them, in one playtest on the rebased branch: `PlaygroundTests` **76/76** (and again after
`RoadTests`, in case its fixtures left `Config.Road` dirty), `RoadTests` **53/53** (173 s),
`RunTests` **17/17**, `CollisionTests` 50, `DriftTests` 50, `FxTests` 78, `GarageTests` 24,
`JitterTests` 11, `TrajectoryTests` 13. No errors or warnings in the console beyond `RoadTests`'
own two deliberate "the road boxed itself in" lines.

**`RoadTests` has to be run on its own**, and that is worth knowing rather than re-learning: run
as the eighth suite in one long-lived thread it died with "exhausted allowed execution time", and
run alone in a fresh thread after a playtest restart it passed in 173 seconds. Nothing in this
task changed it; the triangles made it about twice as slow as it was (87 s before).

`ServerScriptService/Tests/PlaygroundTests.luau`, run from the server debug bridge **in a
playtest**:

```
game.ServerStorage.DebugBridge:Invoke("DebugPlaygroundTests", "run")
```

The hill's own checks: every climbing piece climbs and every descending one descends; the top is
the end of the climb; the exit lands on the plate to within a thousandth of a stud; the entry is a
ramp and not a step; nothing is steeper than `Config.Road.MaxGrade`; no two pieces overlap; the
slabs are tagged and the walls are not; the switch stands the walls down, leaves the slabs alone
and puts the walls back; the hill stands on its own plate and every corner of that plate is nearer
the playground's spawn than a track's; the surface walks clean down the centre line and both kerbs;
the lift aims at the crest; and ten forged tool requests do nothing.

**The forgery check needs a player in the place** and says so rather than passing vacuously.

### The Studio-only methods it adds

| Method | What for |
|---|---|
| `PlaygroundService:DebugHill()` | The whole profile: every piece's length, start and end height, grade and part count, plus the entry, the exit, the top and the pad |
| `PlaygroundService:DebugHillBounds()` | The hill's footprint, its ROAD's footprint on its own and its pad, in world space |
| `PlaygroundService:DebugHillLine(spacing?)` | The hill's centre line as world points, each carrying the piece it is on: what a test autopilot aims at, since the hill has no generator to ask |
| `PlaygroundService:DebugBarrierReport()` | Walls and slabs counted by `CanQuery`, `CanCollide` and tag, so "the switch did not touch the road" is a number |
| `PlaygroundService:DebugTool(what, userId?)` | Press a testing button for a player with no client, through the real handler — rate limit, cooldown, type check and all |
| `PlaygroundService:DebugClearToolLimits()` | Stand the two guards down, so a test that is not measuring them is not measuring a wait |
| `RoadService:DebugBarrierReport()` | The same count for the endless road's walls |
| `PlayerScripts.TestHudBridge` | `DebugState` and `DebugPress` on the client, for a LocalScript the client loader's own bridge cannot see |

## Open questions

- **Whether the climb's one grade is enough.** 7 degrees is all the piece set can hand on, and the
  user may want to feel 4 and 12 as well. That is a `Config/Road.luau` change (a second climbing
  link, or a `Link` with a steeper `EndGrade`), not a change here.
- **What a fall off the top should do.** It currently respawns at the playground spawn, 1 500 studs
  away, because the client's fall test fires 150 studs below the last ground. Landing on the pad
  instead would want a bigger `FallBelowSurface` or a hill that is not 259 studs tall.
- **Whether the hill should be somewhere a player would ever see.** It is a test rig in the test
  world; the real map is designed after the drift feel is agreed (`WORLD.md`).
